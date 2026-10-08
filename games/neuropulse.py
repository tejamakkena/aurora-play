"""NeuroPulse: the daily 10-step brain workout and its rating engine.

One session a day, ten steps, about five minutes. Nine graded tasks across
four thinking disciplines, then step ten is always the Zen reset -- the
session ends calm rather than on a hard puzzle.

    GET  /api/neuro/daily?device=ID[&date=YYYY-MM-DD][&name=NAME][&caps=KIND,KIND]
    POST /api/neuro/result
    POST /api/neuro/arcade
    GET  /api/neuro/profile/<device>
    GET  /api/neuro/leaderboard?date=YYYY-MM-DD[&device=ID]

Disciplines (``DISCIPLINES``), each with its own rating:

  logic    -- calendar shifts, relative reasoning, syllogisms
  math     -- arithmetic chaining, fast estimation, target numbers
  memory   -- visual flash recall, n-back probes, spatial grids
  pattern  -- geometric sequences, rotational matching, odd one out
  zen      -- box breathing, Stroop inhibition, sensory resets

Difficulty is an ELO loop per discipline, not a global level: someone can
be strong at patterns and still be stretched by mental maths, and each
discipline is paced on its own. A task carries the rating it is "worth"
(``eloTarget``); answering it right pulls the rating toward that target,
getting it wrong pushes the rating down, and the K-factor shrinks as a
discipline settles (``k_factor``). Answers inside
``SPEED_BONUS_FRACTION`` of the task's target time earn a little extra,
and correct-but-slow answers earn a little less (``_speed_scale``).

The day's ten steps are generated from a seed of the date plus the device
(``daily_seed``), so a session is stable if the app is reopened, while two
people on the same day get tasks pitched at their own ratings.

Beside the daily ten sits the arcade (``ARCADE_GAMES``): short replayable
games, each training one discipline, that report one 0-1 score for the
whole run instead of right-or-wrong per step. ``rate`` takes that score as
the actual result. Only the first run of each game per day moves a rating
and a practice run never does, so replaying cannot farm a discipline.

The phone grades its own answers (the task carries ``answer``) exactly
like the older Daily Brain Challenge, so a session plays offline; the
server rates the session when the results arrive. Storage is a
best-effort JSON file (NEURO_PATH, default data/neuropulse.json): on the
free host it can vanish, so the apps keep their own copy too.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import math
import os
import random
import re
import threading
from pathlib import Path

from flask import Blueprint, jsonify, request

from games import brain_puzzles as bp

_lock = threading.RLock()
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_DEVICE_RE = re.compile(r"^[A-Za-z0-9._-]{4,64}$")
_KEEP_DAYS = 60

#: One rating per discipline. "zen" is tracked for inhibition work
#: (Stroop); breathing and sensory steps are completion-only.
DISCIPLINES = ("logic", "math", "memory", "pattern", "zen")

DISCIPLINE_NAMES = {
    "logic": "Logic",
    "math": "Number Speed",
    "memory": "Memory",
    "pattern": "Patterns",
    "zen": "Calm Focus",
}

#: Where a new player starts, and the range a rating may wander in.
START_RATING = 1000
MIN_RATING = 600
MAX_RATING = 2400

#: A task's nominal worth: level 1 is 800, each level adds 160.
LEVEL_BASE = 800
LEVEL_STEP = 160

#: Tasks are pitched a little below the rating, so most answers are right
#: and the session stays encouraging (expected score about 0.67).
CHALLENGE_OFFSET = -120

#: Answer inside this fraction of the target time for the speed bonus.
SPEED_BONUS_FRACTION = 0.6
SPEED_BONUS = 0.15
SLOW_DAMPENER = 0.75

#: The ten steps: nine graded, then the Zen reset.
# The arcade: short replayable games that sit beside the daily ten. Each
# trains one discipline and reports a single 0-1 score for the run. The
# discipline is fixed here, not taken from the phone.
ARCADE_GAMES = {
    "probe": "logic",       # find the hidden rule with as few test inputs as you can
    "drift": "pattern",     # notice when the sorting rule changes
    "ballpark": "math",     # calibrated ranges for real-world numbers
    "split": "memory",      # a rhythm and a sum at the same time
}

SESSION_STEPS = 10
GRADED_STEPS = 9

#: Pulse score per step, for the day's headline number and leaderboard.
STEP_BASE_POINTS = 60
STEP_LEVEL_POINTS = 40
STEP_SPEED_POINTS = 100
ZEN_POINTS = 100


# ---------------------------------------------------------------------------
# rating engine
# ---------------------------------------------------------------------------

def expected_score(rating: float, target: float) -> float:
    """The classic ELO expectation: the chance of getting this right."""
    return 1.0 / (1.0 + 10.0 ** ((float(target) - float(rating)) / 400.0))


def k_factor(games_played: int) -> int:
    """Big steps while a discipline is new, small ones once it settles."""
    games = max(0, int(games_played))
    if games < 10:
        return 40
    if games < 30:
        return 24
    return 16


def level_for_rating(rating: float) -> int:
    """The task level a rating should be meeting, 1-10."""
    level = 1 + (float(rating) + CHALLENGE_OFFSET - LEVEL_BASE) / LEVEL_STEP
    return max(1, min(10, int(round(level))))


def elo_target_for_level(level: int) -> int:
    """What a level is worth, in rating points."""
    level = max(1, min(10, int(level)))
    return LEVEL_BASE + (level - 1) * LEVEL_STEP


def target_response_ms(discipline: str, level: int) -> int:
    """How long this task should take. Used for the speed bonus and for
    the ring on the phone; it is not a hard cut-off."""
    level = max(1, min(10, int(level)))
    base = {"math": 7000, "memory": 9000, "pattern": 11000,
            "logic": 13000, "zen": 4000}.get(discipline, 10000)
    return int(base + (level - 1) * 900)


def _speed_scale(correct: bool, response_ms: float, target_ms: float) -> float:
    """Multiplier on the rating move: quick-and-right gains a little more,
    slow-and-right a little less. A wrong answer is never softened."""
    if not correct:
        return 1.0
    if target_ms <= 0:
        return 1.0
    if response_ms <= target_ms * SPEED_BONUS_FRACTION:
        return 1.0 + SPEED_BONUS
    if response_ms > target_ms:
        return SLOW_DAMPENER
    return 1.0


def rate(rating: float, games_played: int, elo_target: float, correct: bool,
         response_ms: float = 0.0, target_ms: float = 0.0,
         score: float | None = None) -> int:
    """One result's effect on one discipline's rating.

    A step is right or wrong, so ``correct`` gives an actual score of 1 or
    0 and the speed modifier applies. A session-sized game (the arcade)
    has no single right answer, so it reports ``score``, 0 to 1, which is
    used as the actual score directly. A score already folds in how well
    and how fast the run went, so the speed modifier is not applied on top
    of it. Left out, ``score`` changes nothing: every call that predates
    it behaves exactly as before.
    """
    exp = expected_score(rating, elo_target)
    if score is None:
        actual = 1.0 if correct else 0.0
        scale = _speed_scale(correct, response_ms, target_ms)
    else:
        actual = max(0.0, min(1.0, float(score)))
        scale = 1.0
    move = k_factor(games_played) * (actual - exp) * scale
    return int(round(max(MIN_RATING, min(MAX_RATING, float(rating) + move))))


def step_points(correct: bool, level: int, response_ms: float, target_ms: float) -> int:
    """This step's share of the day's pulse score."""
    if not correct:
        return 0
    level = max(1, min(10, int(level)))
    points = STEP_BASE_POINTS + STEP_LEVEL_POINTS * level / 10.0
    if target_ms > 0:
        fresh = max(0.0, 1.0 - float(response_ms) / float(target_ms))
        points += STEP_SPEED_POINTS * fresh
    return int(round(points))


# ---------------------------------------------------------------------------
# task generators
#
# Each returns the same shape as games/brain_puzzles.py plus `discipline`
# and `inputStyle`, so the phone renders every task through one view:
#
#   choice  -- tap one of four options
#   number  -- type or tap a number
#   grid    -- tap the cells that were lit
#   breathe -- follow the breathing pacer, no answer
#   reflect -- a grounding prompt with a timer, no answer
# ---------------------------------------------------------------------------

_COLORS = ("RED", "BLUE", "GREEN", "YELLOW", "PURPLE", "ORANGE")
_LETTERS = "ABCDEFGHJKLMNPRSTUVWXZ"


def _step(discipline: str, kind: str, level: int, prompt: str, answer, *,
          options=None, input_style: str = "choice", visual=None,
          hint: str = "", explain: str = "", spoken: str | None = None,
          accepts=()) -> dict:
    return {
        "discipline": discipline,
        "kind": kind,
        "skill": DISCIPLINE_NAMES[discipline],
        "level": int(level),
        "prompt": prompt,
        "spoken": spoken or prompt,
        "answer": str(answer),
        "accepts": [str(a) for a in accepts if str(a) != str(answer)],
        "options": options,
        "inputStyle": input_style,
        "visual": visual,
        "hint": hint,
        "explain": explain,
    }


def _from_brain(discipline: str, kind: str, level: int, rng: random.Random) -> dict:
    """Wrap one of the existing puzzle generators (games/brain_puzzles.py)."""
    puzzle = bp.make(kind, level, rng)
    # Every kind NeuroPulse borrows offers four options; the number style
    # is the fallback for a generator that ever stops doing so.
    style = "choice" if puzzle.get("options") else "number"
    return _step(discipline, kind, level, puzzle["prompt"], puzzle["answer"],
                 options=puzzle.get("options"), input_style=style,
                 visual=puzzle.get("visual"), hint=puzzle.get("hint", ""),
                 explain=puzzle.get("explain", ""), spoken=puzzle.get("spoken"),
                 accepts=puzzle.get("accepts", ()))


# ---- logic ----------------------------------------------------------------

_SYLLOGISMS = [
    ("All {a} are {b}. All {b} are {c}.", "Are all {a} {c}?", True),
    ("All {a} are {b}. Some {b} are {c}.", "Are all {a} {c}?", False),
    ("No {a} are {b}. All {c} are {a}.", "Are any {c} {b}?", False),
    ("All {a} are {b}. No {b} are {c}.", "Are any {a} {c}?", False),
    ("Some {a} are {b}. All {b} are {c}.", "Are some {a} {c}?", True),
]
#: Invented creatures, so the answer comes only from the two statements
#: and never from what the player already knows about the world.
_SYL_WORDS = [
    ("Blims", "Zogs", "Trids"), ("Vexes", "Morks", "Plibs"),
    ("Jats", "Krels", "Wumps"), ("Snerts", "Flods", "Gribs"),
    ("Yarns", "Dremes", "Oobs"), ("Quills", "Narls", "Tazzes"),
]


def _syllogism(level: int, rng: random.Random) -> dict:
    premise, question, truth = rng.choice(_SYLLOGISMS if level >= 4 else _SYLLOGISMS[:3])
    a, b, c = rng.choice(_SYL_WORDS)
    text = (premise + " " + question).format(a=a, b=b, c=c)
    answer = "Yes" if truth else "No"
    return _step("logic", "syllogism", level, text, answer,
                 options=["Yes", "No"],
                 hint="Only what the two statements say counts.",
                 explain=f"{answer}: the statements {'force' if truth else 'do not force'} it.")


_RELATIVE = [
    ("older", "younger", "oldest", "youngest"),
    ("taller", "shorter", "tallest", "shortest"),
    ("faster", "slower", "fastest", "slowest"),
    ("heavier", "lighter", "heaviest", "lightest"),
]
_NAMES = ("Asha", "Ben", "Chen", "Divya", "Eli", "Farah", "Gopi", "Hana",
          "Ira", "Jay", "Kiran", "Leo", "Maya", "Nikhil", "Omar", "Priya")


def _relative(level: int, rng: random.Random) -> dict:
    count = 3 if level <= 3 else (4 if level <= 6 else 5)
    people = rng.sample(_NAMES, count)          # people[0] is "the most"
    more, less, most, least = rng.choice(_RELATIVE)
    facts = []
    for i in range(count - 1):
        first, second = people[i], people[i + 1]
        if rng.random() < 0.5:
            facts.append(f"{first} is {more} than {second}")
        else:
            facts.append(f"{second} is {less} than {first}")
    rng.shuffle(facts)
    ask_most = rng.random() < 0.5
    answer = people[0] if ask_most else people[-1]
    word = most if ask_most else least
    options = [answer] + [n for n in people if n != answer][:3]
    while len(options) < 4:
        extra = rng.choice(_NAMES)
        if extra not in options:
            options.append(extra)
    rng.shuffle(options)
    return _step("logic", "relative", level,
                 ". ".join(facts) + f". Who is the {word}?", answer,
                 options=options,
                 hint=f"Line them up from {most} to {least}.",
                 explain="In order: " + ", ".join(people) + f". So {answer} is the {word}.")


# ---- math -----------------------------------------------------------------

def _chain(level: int, rng: random.Random) -> dict:
    """Arithmetic chaining: hold a running total through several steps."""
    links = 2 if level <= 2 else (3 if level <= 6 else 4)
    value = rng.randint(3, 9 + level * 2)
    text = [f"Start with {value}"]
    for _ in range(links):
        pick = rng.random()
        if pick < 0.34:
            n = rng.randint(2, 6 + level)
            value += n
            text.append(f"add {n}")
        elif pick < 0.62:
            n = rng.randint(2, min(value - 1, 5 + level)) if value > 3 else 1
            value -= n
            text.append(f"take away {n}")
        elif pick < 0.84 or value > 400:
            value *= 2
            text.append("double it")
        else:
            n = rng.randint(2, 4)
            value *= n
            text.append(f"times {n}")
    if value % 2 == 0 and level >= 5 and rng.random() < 0.4:
        value //= 2
        text.append("halve it")
    prompt = ", then ".join([text[0]] + text[1:]) + ". What do you have?"
    return _step("math", "chain", level, prompt, value, input_style="number",
                 accepts=[bp.number_words(value)],
                 hint="Keep the running total in your head, one step at a time.",
                 explain=f"It comes to {value}.")


def _estimate(level: int, rng: random.Random) -> dict:
    """Fast estimation: close enough, quickly, without exact working."""
    a = rng.randint(18, 29 + level * 7)
    b = rng.randint(11, 19 + level * 3)
    exact = a * b
    options = {exact}
    while len(options) < 4:
        skew = rng.choice([0.55, 0.7, 1.35, 1.6, 2.0])
        options.add(max(10, int(exact * skew)))
    picks = sorted(options)
    return _step("math", "estimate", level,
                 f"Roughly, what is {a} times {b}?", str(exact),
                 options=[str(p) for p in picks],
                 hint="Round both numbers, multiply, then pick the closest.",
                 explain=f"{a} times {b} is {exact}.")


def _target_number(level: int, rng: random.Random) -> dict:
    """Target numbers: which pair of these reaches the target?"""
    pool = rng.sample(range(2, 14 + level * 3), 5)
    x, y = rng.sample(pool, 2)
    use_product = level >= 5 and rng.random() < 0.5
    target = x * y if use_product else x + y
    verb = "multiply to" if use_product else "add up to"
    pairs = [(x, y)]
    seen = {tuple(sorted((x, y)))}
    while len(pairs) < 4:
        p, q = rng.sample(pool, 2)
        key = tuple(sorted((p, q)))
        value = p * q if use_product else p + q
        if key in seen or value == target:
            continue
        seen.add(key)
        pairs.append((p, q))
    labels = [f"{p} and {q}" for p, q in pairs]
    answer = labels[0]
    rng.shuffle(labels)
    return _step("math", "target", level,
                 f"Which two {verb} {target}?", answer, options=labels,
                 hint="Try the biggest pair first.",
                 explain=f"{answer} {verb} {target}.")


# ---- memory ---------------------------------------------------------------

def _flash(level: int, rng: random.Random) -> dict:
    """Visual flash recall: digits appear, vanish, then you repeat them."""
    length = min(4 + (level + 1) // 2, 9)
    digits = [rng.randint(1, 9) for _ in range(length)]
    backwards = level >= 5
    target = list(reversed(digits)) if backwards else digits
    how = "backwards" if backwards else "in the same order"
    answer = "".join(str(d) for d in target)
    flash_ms = max(1600, 3200 - level * 120)
    return _step("memory", "flash", level,
                 f"Watch the numbers, then tap them {how}.", answer,
                 input_style="number",
                 visual={"flashDigits": digits, "flashMs": flash_ms,
                         "reversed": backwards},
                 accepts=[" ".join(str(d) for d in target)],
                 hint=f"It starts with {target[0]}.",
                 explain=f"{how.capitalize()}, it was {' '.join(str(d) for d in target)}.")


def _nback(level: int, rng: random.Random) -> dict:
    """An n-back probe: hold a moving window of letters in mind."""
    back = 2 if level <= 5 else 3
    length = min(5 + level // 2, 9)
    letters = [rng.choice(_LETTERS) for _ in range(length)]
    while len(set(letters)) < 4:
        letters = [rng.choice(_LETTERS) for _ in range(length)]
    answer = letters[-1 - back]
    options = [answer]
    for letter in reversed(letters):
        if letter not in options:
            options.append(letter)
        if len(options) == 4:
            break
    while len(options) < 4:
        extra = rng.choice(_LETTERS)
        if extra not in options:
            options.append(extra)
    rng.shuffle(options)
    ordinal = {2: "two", 3: "three"}[back]
    return _step("memory", "nback", level,
                 f"Which letter came {ordinal} before the last one?", answer,
                 options=options,
                 visual={"flashLetters": letters,
                         "flashMs": max(700, 1100 - level * 30)},
                 hint="Count back from the end of the run.",
                 explain=f"The run was {' '.join(letters)}, so it was {answer}.")


def _grid(level: int, rng: random.Random) -> dict:
    """Spatial grid matrix: cells light up, then you tap them back."""
    side = 3 if level <= 3 else (4 if level <= 7 else 5)
    lit_count = min(3 + (level + 1) // 2, side * side - 2)
    cells = sorted(rng.sample(range(side * side), lit_count))
    answer = ",".join(str(c) for c in cells)
    return _step("memory", "grid", level,
                 f"Tap the {lit_count} squares that lit up.", answer,
                 input_style="grid",
                 visual={"rows": side, "cols": side, "cells": cells,
                         "flashMs": max(1500, 2800 - level * 110)},
                 hint="Remember the shape they made, not each square.",
                 explain="The lit squares are shown again.")


# ---- steps that need a newer phone ---------------------------------------
#
# These kinds are only dealt to a phone that says it can show them (the
# `caps` query on /neuro/daily). A phone that predates them gets exactly the
# sessions it always got.

_CULPRIT_SCENES = (
    "took the last slice of cake",
    "left the garden gate open",
    "hid the TV remote",
    "ate the leftover biryani",
    "broke the lamp",
)


def _stated(statements: list, thief: str, index: int, stack: tuple = ()):
    """Is statement ``index`` true if ``thief`` is the culprit? A statement
    about another speaker's honesty follows that speaker's own statement.
    Returns None when the statements refer to each other in a circle."""
    if index in stack:
        return None
    kind = statements[index]["type"]
    target = statements[index]["target"]
    if kind == "was":
        return thief == target
    if kind == "wasnt":
        return thief != target
    other = next(i for i, st in enumerate(statements) if st["by"] == target)
    inner = _stated(statements, thief, other, stack + (index,))
    if inner is None:
        return None
    return (not inner) if kind == "lies" else inner


def solve_culprits(statements: list, suspects: list, liars: int) -> list:
    """Every suspect who, as the culprit, leaves exactly ``liars`` statements
    false. A solvable puzzle has exactly one."""
    found = []
    for thief in suspects:
        truths = [_stated(statements, thief, i) for i in range(len(statements))]
        if any(t is None for t in truths):
            return []
        if sum(1 for t in truths if not t) == liars:
            found.append(thief)
    return found


def _statement_text(st: dict) -> str:
    who, kind, target = st["by"], st["type"], st["target"]
    if kind == "was":
        return "It was me." if target == who else f"It was {target}."
    if kind == "wasnt":
        return "It wasn't me." if target == who else f"It wasn't {target}."
    if kind == "lies":
        return f"{target} is lying."
    return f"{target} is telling the truth."


def _liars_row(level: int, rng: random.Random) -> dict:
    """Knights-and-knaves in a line-up: each suspect makes one statement and
    exactly one (later, two) of the statements is false. Who did it? Every
    puzzle is checked to have exactly one answer before it is dealt."""
    count = 4 if level <= 3 else (5 if level <= 7 else 6)
    liars = 1 if level <= 7 else 2
    suspects = rng.sample(_NAMES, count)
    statements = None
    for _ in range(400):
        trial = []
        for who in suspects:
            roll = rng.random()
            others = [n for n in suspects if n != who]
            if level >= 6 and roll < 0.18:
                kind, target = "truth", rng.choice(others)
            elif level >= 4 and roll < 0.40:
                kind, target = "lies", rng.choice(others)
            elif roll < 0.72:
                kind, target = "was", rng.choice(suspects)
            else:
                kind, target = "wasnt", rng.choice(suspects)
            trial.append({"by": who, "type": kind, "target": target})
        if len(solve_culprits(trial, suspects, liars)) == 1:
            statements = trial
            break
    if statements is None:                       # a known-good line-up
        thief = suspects[0]
        statements = [{"by": who, "type": "was", "target": thief} for who in suspects]
        for i in range(1, 1 + liars):
            statements[i] = {"by": suspects[i], "type": "wasnt", "target": thief}
    answer = solve_culprits(statements, suspects, liars)[0]
    scene = rng.choice(_CULPRIT_SCENES)
    lines = [f"{st['by']}: \"{_statement_text(st)}\"" for st in statements]
    verb = "is lying" if liars == 1 else "are lying"
    head = (f"{count} friends are in the room and one of them {scene}. "
            f"Exactly {'one' if liars == 1 else 'two'} of them {verb}.")
    prompt = head + "\n" + "\n".join(lines) + "\nWho did it?"
    options = [answer] + rng.sample([n for n in suspects if n != answer], 3)
    rng.shuffle(options)
    false_by = [st["by"] for i, st in enumerate(statements)
                if not _stated(statements, answer, i)]
    return _step("logic", "liars_row", level, prompt, answer,
                 options=options,
                 spoken=prompt.replace("\n", " "),
                 visual={"suspects": suspects, "statements": statements,
                         "liars": liars},
                 hint="Try each name as the culprit and count the false statements.",
                 explain=(f"If {answer} did it, the false statement"
                          f"{'' if liars == 1 else 's'} would be from "
                          + " and ".join(false_by)
                          + f" -- exactly {liars}. No one else fits."))


_COMPASS = {
    "north": (-1, 0), "south": (1, 0), "east": (0, 1), "west": (0, -1),
    "north-east": (-1, 1), "north-west": (-1, -1),
    "south-east": (1, 1), "south-west": (1, -1),
}


_OPPOSITE = {
    "north": "south", "south": "north", "east": "west", "west": "east",
    "north-east": "south-west", "south-west": "north-east",
    "north-west": "south-east", "south-east": "north-west",
}


def _dead_reckoning(level: int, rng: random.Random) -> dict:
    """Walk a dot across a blank grid from words alone and tap where you end
    up. Nothing is lit: the whole task is held in your head."""
    side = 3 if level <= 2 else (4 if level <= 6 else 5)
    count = 2 + (level + 1) // 2
    diagonals = level >= 6
    names = [n for n in _COMPASS if diagonals or "-" not in n]
    for _ in range(200):
        start = (rng.randrange(side), rng.randrange(side))
        row, col = start
        moves = []
        previous = None
        ok = True
        for _step_no in range(count):
            options = []
            for name in names:
                # No repeats and no stepping straight back: "north 1, north
                # 1" is just "north 2", and "north 1, south 1" is a wasted
                # move that makes the path trivial to hold.
                if previous and name in (previous, _OPPOSITE[previous]):
                    continue
                dr, dc = _COMPASS[name]
                reach = 1 if "-" in name else 2
                for steps in range(1, reach + 1):
                    nr, nc = row + dr * steps, col + dc * steps
                    if 0 <= nr < side and 0 <= nc < side:
                        options.append((name, steps, nr, nc))
            if not options:
                ok = False
                break
            name, steps, row, col = rng.choice(options)
            moves.append(f"{name} {steps}")
            previous = name
        if ok and (row, col) != start:
            break
    else:                                        # cannot really happen
        start, moves, row, col = (0, 0), ["east 1"], 0, 1
    answer = str(row * side + col)
    return _step("memory", "dead_reckoning", level,
                 "Start at the dot. Move: " + ", ".join(moves)
                 + ". Tap where you end up.", answer,
                 input_style="grid",
                 visual={"rows": side, "cols": side, "cells": [],
                         "start": start[0] * side + start[1],
                         "moves": moves, "flashMs": 0},
                 hint="Walk the dot one move at a time; don't jump to the end.",
                 explain=f"You finish on row {row + 1}, column {col + 1}.")


# ---- zen ------------------------------------------------------------------

def _stroop(level: int, rng: random.Random) -> dict:
    """Stroop inhibition: read the ink, not the word."""
    word, ink = rng.sample(_COLORS, 2)
    if level <= 2 and rng.random() < 0.5:
        ink = word                      # an easy matching trial to warm up
    ask_ink = level <= 6 or rng.random() < 0.5
    answer = ink.capitalize() if ask_ink else word.capitalize()
    asked = "colour it is printed in" if ask_ink else "word itself"
    options = [c.capitalize() for c in rng.sample(_COLORS, 4)]
    if answer not in options:
        options[0] = answer
    rng.shuffle(options)
    return _step("zen", "stroop", level,
                 f"Tap the {asked}.", answer, options=options,
                 visual={"word": word, "ink": ink.lower(), "askInk": ask_ink},
                 hint="Slow down for half a second before you tap.",
                 explain=f"The word was {word} printed in {ink.lower()}.")


#: Patterns are (name, [in, hold, out, hold]); the cycle count is worked
#: out so the closing reset lands near BREATH_SECONDS either way.
_BREATH_PATTERNS = [
    ("Box breathing", [4, 4, 4, 4]),
    ("Longer out-breath", [4, 2, 6, 2]),
    ("Steady square", [5, 5, 5, 5]),
]
BREATH_SECONDS = 45


def _breathing(level: int, rng: random.Random) -> dict:
    name, pattern = rng.choice(_BREATH_PATTERNS)
    cycles = max(2, round(BREATH_SECONDS / sum(pattern)))
    seconds = sum(pattern) * cycles
    return _step("zen", "breathing", level,
                 f"{name}. Follow the circle for {seconds} seconds.", "",
                 input_style="breathe",
                 visual={"pattern": pattern, "cycles": cycles,
                         "labels": ["Breathe in", "Hold", "Breathe out", "Hold"]},
                 hint="Let your shoulders drop.",
                 explain="Slow breathing settles a racing mind in about a minute.")


_SENSORY = [
    "Name three things you can hear right now.",
    "Find five things you can see that are blue.",
    "Notice three things your hands can feel.",
    "Name one thing you can smell, and one you would like to.",
    "Pick one sound far away and one close by.",
    "Name three things you are glad about today.",
]


def _sensory(level: int, rng: random.Random) -> dict:
    return _step("zen", "sensory", level, rng.choice(_SENSORY), "",
                 input_style="reflect",
                 visual={"seconds": 30},
                 hint="There is no score here.",
                 explain="Naming what your senses pick up pulls attention out of a spiral.")


#: Which task kinds belong to each discipline.
KINDS = {
    "logic": ("calendar", "relative", "syllogism"),
    "math": ("chain", "estimate", "target"),
    "memory": ("flash", "nback", "grid"),
    "pattern": ("sequence", "rotation", "odd_word", "analogy"),
    "zen": ("stroop", "breathing", "sensory"),
}

#: The Zen kinds that are completion-only (never rated, never scored wrong).
UNGRADED_KINDS = ("breathing", "sensory")

#: Kinds a phone must ask for (``caps``) before the server deals them.
OPTIONAL_KINDS = {
    "logic": ("liars_row",),
    "memory": ("dead_reckoning",),
}
KNOWN_CAPS = frozenset(k for kinds in OPTIONAL_KINDS.values() for k in kinds)


def kinds_for(discipline: str, caps=()) -> tuple:
    """The kinds one discipline deals from, for a phone with ``caps``."""
    extra = tuple(k for k in OPTIONAL_KINDS.get(discipline, ()) if k in caps)
    return tuple(KINDS[discipline]) + extra

_LOCAL_MAKERS = {
    "syllogism": _syllogism,
    "relative": _relative,
    "chain": _chain,
    "estimate": _estimate,
    "target": _target_number,
    "flash": _flash,
    "nback": _nback,
    "grid": _grid,
    "liars_row": _liars_row,
    "dead_reckoning": _dead_reckoning,
    "stroop": _stroop,
    "breathing": _breathing,
    "sensory": _sensory,
}


def make_task(discipline: str, kind: str, level: int,
              rng: random.Random | None = None) -> dict:
    """One task, at ``level``, tagged with its discipline."""
    rng = rng or random.Random()
    level = max(1, min(10, int(level)))
    if kind in _LOCAL_MAKERS:
        return _LOCAL_MAKERS[kind](level, rng)
    return _from_brain(discipline, kind, level, rng)


# ---------------------------------------------------------------------------
# the daily session
# ---------------------------------------------------------------------------

def today() -> str:
    return dt.date.today().isoformat()


def daily_seed(device: str, date: str) -> int:
    """Stable per device per day, so reopening the app resumes the same ten."""
    digest = hashlib.sha256(f"{date}:{device}".encode("utf-8")).hexdigest()
    return int(digest[:12], 16)


#: The nine graded steps: three rounds through the four thinking
#: disciplines (minus one), so no two neighbours are the same discipline
#: and every discipline is exercised at least twice.
_GRADED_ORDER = ("logic", "math", "memory", "pattern",
                 "math", "memory", "pattern", "logic", "memory")


def build_session(device: str, date: str | None = None,
                  ratings: dict | None = None, caps=()) -> dict:
    """The day's ten steps, pitched at this device's ratings. ``caps`` names
    the optional kinds the phone can show; without them the session is
    exactly the one older phones have always been dealt."""
    date = date or today()
    ratings = ratings or dict(_ratings_of(device))
    rng = random.Random(daily_seed(device, date))
    bags: dict[str, list] = {}

    def next_kind(discipline: str) -> str:
        """Each discipline deals from its own shuffled bag, so a session
        that visits a discipline three times asks three different kinds."""
        bag = bags.get(discipline)
        if not bag:
            bag = list(kinds_for(discipline, caps))
            rng.shuffle(bag)
            bags[discipline] = bag
        return bag.pop()

    steps = []
    for index, discipline in enumerate(_GRADED_ORDER):
        rating = float(ratings.get(discipline, START_RATING))
        level = level_for_rating(rating)
        kind = next_kind(discipline)
        task = make_task(discipline, kind, level, rng)
        task["index"] = index
        task["eloTarget"] = elo_target_for_level(level)
        task["targetResponseMs"] = target_response_ms(discipline, level)
        steps.append(task)

    # Step ten is always the reset. Stroop is graded; the other two are
    # completion-only, so the session can end on pure calm.
    zen_rating = float(ratings.get("zen", START_RATING))
    zen_level = level_for_rating(zen_rating)
    zen_kind = next_kind("zen")
    zen = make_task("zen", zen_kind, zen_level, rng)
    zen["index"] = GRADED_STEPS
    zen["eloTarget"] = elo_target_for_level(zen_level)
    zen["targetResponseMs"] = target_response_ms("zen", zen_level)
    steps.append(zen)
    return {"date": date, "seed": daily_seed(device, date), "steps": steps}


# ---------------------------------------------------------------------------
# storage
# ---------------------------------------------------------------------------

def _path() -> Path:
    override = os.environ.get("NEURO_PATH")
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1] / "data" / "neuropulse.json"


def _load() -> dict:
    try:
        data = json.loads(_path().read_text(encoding="utf-8"))
    except Exception:
        return {"devices": {}}
    if not isinstance(data, dict) or not isinstance(data.get("devices"), dict):
        return {"devices": {}}
    return data


def _save(data: dict) -> None:
    try:
        path = _path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")
    except Exception:
        pass                    # ratings are a nice-to-have, never a blocker


def _blank() -> dict:
    return {
        "name": "",
        "ratings": {d: START_RATING for d in DISCIPLINES},
        "games": {d: 0 for d in DISCIPLINES},
        "best": {d: START_RATING for d in DISCIPLINES},
        "streak": 0,
        "lastDate": "",
        "restUsedOn": "",
        "zenMinutes": 0,
        "days": {},
        "arcade": {},          # per game: plays, best, last, lastDate
        "arcadeDays": {},      # per date: the games already rated that day
    }


def _entry(data: dict, device: str) -> dict:
    entry = data["devices"].get(device)
    if not isinstance(entry, dict):
        entry = _blank()
        data["devices"][device] = entry
    base = _blank()
    for key, value in base.items():
        entry.setdefault(key, value)
    for d in DISCIPLINES:                 # a discipline added after a save
        entry["ratings"].setdefault(d, START_RATING)
        entry["games"].setdefault(d, 0)
        entry["best"].setdefault(d, entry["ratings"][d])
    return entry


def _ratings_of(device: str) -> dict:
    with _lock:
        data = _load()
        return dict(_entry(data, device)["ratings"])


def _prune(entry: dict) -> None:
    days = entry.get("days", {})
    if len(days) > _KEEP_DAYS:
        for key in sorted(days)[:-_KEEP_DAYS]:
            days.pop(key, None)
    played = entry.get("arcadeDays", {})
    if len(played) > _KEEP_DAYS:
        for key in sorted(played)[:-_KEEP_DAYS]:
            played.pop(key, None)


def _advance_streak(entry: dict, date: str) -> int:
    """A day's streak, forgiving one missed day a week."""
    last = entry.get("lastDate") or ""
    if last == date:
        return int(entry.get("streak") or 1)
    if not _DATE_RE.match(last):
        return 1
    try:
        gap = (dt.date.fromisoformat(date) - dt.date.fromisoformat(last)).days
    except ValueError:
        return 1
    if gap <= 0:
        return int(entry.get("streak") or 1)
    if gap == 1:
        return int(entry.get("streak") or 0) + 1
    if gap == 2:
        rest = entry.get("restUsedOn") or ""
        fresh = True
        if _DATE_RE.match(rest):
            try:
                fresh = (dt.date.fromisoformat(date)
                         - dt.date.fromisoformat(rest)).days >= 7
            except ValueError:
                fresh = True
        if fresh:
            entry["restUsedOn"] = date
            return int(entry.get("streak") or 0) + 1
    return 1


def _arcade_summary(entry: dict) -> dict:
    """Plays, best and last score for every arcade game, zeros included so
    the phone can draw a tile for a game that has not been played yet."""
    stored = entry.get("arcade") or {}
    out = {}
    for game, discipline in ARCADE_GAMES.items():
        row = stored.get(game) if isinstance(stored.get(game), dict) else {}
        out[game] = {
            "discipline": discipline,
            "plays": int(row.get("plays") or 0),
            "best": float(row.get("best") or 0.0),
            "last": float(row.get("last") or 0.0),
            "lastDate": str(row.get("lastDate") or ""),
        }
    return out


def profile(device: str) -> dict:
    """Ratings, levels, streak and the last 30 days, for the phone."""
    with _lock:
        data = _load()
        entry = _entry(data, device)
        days = entry.get("days", {})
        history = [{"date": key, **days[key]} for key in sorted(days)[-30:]]
        return {
            "device": device,
            "name": entry.get("name", ""),
            "ratings": dict(entry["ratings"]),
            "levels": {d: level_for_rating(entry["ratings"][d]) for d in DISCIPLINES},
            "games": dict(entry["games"]),
            "best": dict(entry["best"]),
            "streak": int(entry.get("streak") or 0),
            "lastDate": entry.get("lastDate", ""),
            "zenMinutes": int(entry.get("zenMinutes") or 0),
            "names": DISCIPLINE_NAMES,
            "history": history,
            "arcade": _arcade_summary(entry),
        }


def record_session(device: str, answers: list, date: str | None = None,
                   name: str = "", seconds: int = 0, mood: int = 0,
                   zen_seconds: int = 0) -> dict:
    """Rate a finished session and return the new standing.

    ``answers`` is one entry per step the player reached:
    ``{"discipline", "kind", "level", "eloTarget", "correct",
    "responseMs", "targetResponseMs"}``. A step the player skipped is
    simply absent. Replaying a day never raises the stored ratings twice:
    the first session of a date is the one that counts.
    """
    date = date or today()
    with _lock:
        data = _load()
        entry = _entry(data, device)
        if name:
            entry["name"] = str(name)[:24]
        already = date in entry.get("days", {})

        deltas = {d: 0 for d in DISCIPLINES}
        before = dict(entry["ratings"])
        pulse = 0
        correct_count = 0
        graded = 0
        for raw in answers if isinstance(answers, list) else []:
            if not isinstance(raw, dict):
                continue
            discipline = raw.get("discipline")
            if discipline not in DISCIPLINES:
                continue
            kind = str(raw.get("kind") or "")
            level = max(1, min(10, int(raw.get("level") or 1)))
            correct = bool(raw.get("correct"))
            response_ms = float(raw.get("responseMs") or 0)
            target_ms = float(raw.get("targetResponseMs")
                              or target_response_ms(discipline, level))
            if kind in UNGRADED_KINDS:
                pulse += ZEN_POINTS if correct or raw.get("completed") else 0
                continue
            graded += 1
            if correct:
                correct_count += 1
            pulse += step_points(correct, level, response_ms, target_ms)
            if already:
                continue            # scored for fun, but ratings stay put
            elo_target = float(raw.get("eloTarget") or elo_target_for_level(level))
            rating = float(entry["ratings"][discipline])
            fresh = rate(rating, entry["games"][discipline], elo_target,
                         correct, response_ms, target_ms)
            entry["ratings"][discipline] = fresh
            entry["games"][discipline] = int(entry["games"][discipline]) + 1
            entry["best"][discipline] = max(int(entry["best"][discipline]), fresh)
            deltas[discipline] += fresh - int(rating)

        if not already:
            entry["streak"] = _advance_streak(entry, date)
            entry["lastDate"] = date
            entry["zenMinutes"] = int(entry.get("zenMinutes") or 0) + int(
                max(0, zen_seconds) // 60)
            entry.setdefault("days", {})[date] = {
                "pulse": pulse,
                "correct": correct_count,
                "graded": graded,
                "seconds": max(0, int(seconds)),
                "mood": int(mood) if 1 <= int(mood or 0) <= 5 else 0,
                "ratings": dict(entry["ratings"]),
            }
            _prune(entry)
            _save(data)

        improved = ""
        best_gain = 0
        for d in DISCIPLINES:
            if deltas[d] > best_gain:
                best_gain, improved = deltas[d], d
        return {
            "date": date,
            "pulse": pulse,
            "correct": correct_count,
            "graded": graded,
            "ratings": dict(entry["ratings"]),
            "before": before,
            "deltas": deltas,
            "levels": {d: level_for_rating(entry["ratings"][d]) for d in DISCIPLINES},
            "streak": int(entry.get("streak") or 0),
            "best": dict(entry["best"]),
            "improvedMost": improved,
            "alreadyPlayed": already,
            "names": DISCIPLINE_NAMES,
        }


def record_arcade(device: str, game: str, level: int, score: float,
                  date: str | None = None, name: str = "", seconds: int = 0,
                  practice: bool = False) -> dict:
    """Rate one arcade run.

    ``score`` is 0 to 1 and the phone has already folded accuracy and speed
    into it. Only the first run of each game on a date moves the rating,
    and a run marked ``practice`` never does, so replaying cannot farm a
    discipline: at most one rating move per game per day.
    """
    if game not in ARCADE_GAMES:
        raise ValueError("unknown arcade game")
    score = float(score)
    if not math.isfinite(score) or not 0.0 <= score <= 1.0:
        raise ValueError("score must be between 0 and 1")
    date = date or today()
    level = max(1, min(10, int(level)))
    discipline = ARCADE_GAMES[game]
    with _lock:
        data = _load()
        entry = _entry(data, device)
        if name:
            entry["name"] = str(name)[:24]
        rated_today = game in (entry["arcadeDays"].get(date) or {})
        counts = not practice and not rated_today

        before = int(entry["ratings"][discipline])
        if counts:
            fresh = rate(before, entry["games"][discipline],
                         elo_target_for_level(level), False, score=score)
            entry["ratings"][discipline] = fresh
            entry["games"][discipline] = int(entry["games"][discipline]) + 1
            entry["best"][discipline] = max(int(entry["best"][discipline]), fresh)
            entry["arcadeDays"].setdefault(date, {})[game] = round(score, 3)

        row = entry["arcade"].get(game)
        if not isinstance(row, dict):
            row = {"plays": 0, "best": 0.0, "last": 0.0, "lastDate": ""}
        row["plays"] = int(row.get("plays") or 0) + 1
        row["best"] = max(float(row.get("best") or 0.0), score)
        row["last"] = score
        row["lastDate"] = date
        entry["arcade"][game] = row
        _prune(entry)
        _save(data)

        after = int(entry["ratings"][discipline])
        return {
            "game": game,
            "discipline": discipline,
            "date": date,
            "level": level,
            "score": score,
            "seconds": max(0, int(seconds)),
            "rated": counts,
            "alreadyRated": rated_today,
            "practice": bool(practice),
            "before": before,
            "after": after,
            "delta": after - before,
            "ratings": dict(entry["ratings"]),
            "levels": {d: level_for_rating(entry["ratings"][d]) for d in DISCIPLINES},
            "best": dict(entry["best"]),
            "arcade": _arcade_summary(entry),
            "names": DISCIPLINE_NAMES,
        }


def leaderboard(date: str | None = None, device: str = "") -> dict:
    """Today's pulse scores: everyone, and the device's friends."""
    date = date or today()
    with _lock:
        data = _load()
        rows = []
        for key, entry in data["devices"].items():
            day = (entry.get("days") or {}).get(date)
            if not isinstance(day, dict):
                continue
            rows.append({
                "device": key,
                "name": entry.get("name") or "Player",
                "pulse": int(day.get("pulse") or 0),
                "correct": int(day.get("correct") or 0),
                "streak": int(entry.get("streak") or 0),
            })
    rows.sort(key=lambda r: r["pulse"], reverse=True)
    for i, row in enumerate(rows):
        row["rank"] = i + 1
    everyone = rows[:20]
    friends = []
    if device:
        try:
            from games import profiles
            # profiles.friends_of returns rows keyed "id", not "device".
            allowed = {f.get("id") for f in profiles.friends_of(device)}
            allowed.discard(None)
        except Exception:
            allowed = set()
        allowed.add(device)
        friends = [r for r in rows if r["device"] in allowed]
    return {"date": date, "everyone": everyone, "friends": friends}


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

neuro_bp = Blueprint("neuropulse", __name__)


def _device_ok(device: str) -> bool:
    return bool(device) and bool(_DEVICE_RE.match(device))


def _date_arg(raw) -> str:
    raw = (raw or "").strip()
    return raw if _DATE_RE.match(raw) else today()


@neuro_bp.route("/neuro/daily", methods=["GET"])
def neuro_daily():
    device = (request.args.get("device") or "").strip()
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device"}), 400
    date = _date_arg(request.args.get("date"))
    name = (request.args.get("name") or "").strip()
    with _lock:
        data = _load()
        entry = _entry(data, device)
        if name and entry.get("name") != name[:24]:
            entry["name"] = name[:24]
            _save(data)
        ratings = dict(entry["ratings"])
        done = date in (entry.get("days") or {})
        streak = int(entry.get("streak") or 0)
    caps = {c.strip() for c in (request.args.get("caps") or "").split(",")}
    session = build_session(device, date, ratings, caps & KNOWN_CAPS)
    session.update({
        "success": True,
        "ratings": ratings,
        "levels": {d: level_for_rating(ratings[d]) for d in DISCIPLINES},
        "streak": streak,
        "completed": done,
        "names": DISCIPLINE_NAMES,
    })
    return jsonify(session)


@neuro_bp.route("/neuro/result", methods=["POST"])
def neuro_result():
    body = request.get_json(silent=True) or {}
    device = str(body.get("device") or "").strip()
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device"}), 400
    answers = body.get("answers")
    if not isinstance(answers, list) or len(answers) > 40:
        return jsonify({"success": False, "error": "bad answers"}), 400
    out = record_session(
        device, answers,
        date=_date_arg(body.get("date")),
        name=str(body.get("name") or "")[:24],
        seconds=int(body.get("seconds") or 0),
        mood=int(body.get("mood") or 0),
        zen_seconds=int(body.get("zenSeconds") or 0),
    )
    out["success"] = True
    return jsonify(out)


@neuro_bp.route("/neuro/arcade", methods=["POST"])
def neuro_arcade():
    body = request.get_json(silent=True) or {}
    device = str(body.get("device") or "").strip()
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device"}), 400
    try:
        out = record_arcade(
            device,
            str(body.get("game") or ""),
            int(body.get("level") or 1),
            body.get("score"),
            date=_date_arg(body.get("date")),
            name=str(body.get("name") or "")[:24],
            seconds=int(body.get("seconds") or 0),
            practice=bool(body.get("practice")),
        )
    except (TypeError, ValueError) as err:
        return jsonify({"success": False, "error": str(err) or "bad request"}), 400
    out["success"] = True
    return jsonify(out)


@neuro_bp.route("/neuro/profile/<device>", methods=["GET"])
def neuro_profile(device):
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device"}), 400
    out = profile(device)
    out["success"] = True
    return jsonify(out)


@neuro_bp.route("/neuro/leaderboard", methods=["GET"])
def neuro_leaderboard():
    date = _date_arg(request.args.get("date"))
    device = (request.args.get("device") or "").strip()
    out = leaderboard(date, device if _device_ok(device) else "")
    out["success"] = True
    return jsonify(out)


def reset_for_tests() -> None:
    with _lock:
        _save({"devices": {}})
