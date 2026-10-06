"""Brain puzzles for Travel Mode "Brain Teasers" and the TV "Brain Battle".

Most puzzles are GENERATED, not written: sequences, mental maths, memory
chains, ordering logic, calendar logic and shape rotation are computed,
so the answer is always right, the supply never runs out (nothing to
de-duplicate), and difficulty is a dial (``level`` 1-10). Analogies and
odd-one-out words come from the content library via content_service
(grown by the LLM, no-repeat per table).

    make(kind, level, rng=None, room=None) -> dict
        {"kind", "skill", "level", "prompt", "spoken", "answer",
         "accepts": [...], "hint", "explain",
         "options": [...] | None,   # multiple choice (TV), answer is one of them
         "visual": {...} | None}    # TV-only drawing data (rotation)

    GET /api/brain/puzzles?level=3&count=10&kinds=sequence,math&device=...
"""

from __future__ import annotations

import random
from typing import Callable

from flask import Blueprint, jsonify, request

#: kind -> the skill it exercises (Brain Battle's end-of-game profile).
SKILLS = {
    "sequence": "Patterns",
    "math": "Number Speed",
    "memory": "Memory",
    "logic": "Logic",
    "calendar": "Logic",
    "analogy": "Word Smarts",
    "odd_word": "Word Smarts",
    "rotation": "Spatial",
}

#: Puzzles that work by voice alone (Travel Mode).
VOICE_KINDS = ("sequence", "math", "memory", "logic", "calendar", "analogy", "odd_word")
#: Everything, for the TV.
ALL_KINDS = VOICE_KINDS + ("rotation",)

_ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
         "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
         "seventeen", "eighteen", "nineteen"]
_TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


def number_words(n: int) -> str:
    """Spoken form for 0-9999 ("one hundred twenty three")."""
    if n < 0:
        return "minus " + number_words(-n)
    if n < 20:
        return _ONES[n]
    if n < 100:
        return _TENS[n // 10] + ("" if n % 10 == 0 else " " + _ONES[n % 10])
    if n < 1000:
        rest = n % 100
        return _ONES[n // 100] + " hundred" + ("" if rest == 0 else " " + number_words(rest))
    rest = n % 1000
    return number_words(n // 1000) + " thousand" + ("" if rest == 0 else " " + number_words(rest))


def _num_accepts(n: int) -> list[str]:
    words = number_words(n)
    out = [words]
    if " hundred " in words:
        out.append(words.replace(" hundred ", " hundred and "))
    return out


def _options(rng: random.Random, answer, distractors: list) -> list[str]:
    seen, opts = {str(answer)}, [str(answer)]
    if isinstance(answer, int) and answer >= 0:
        distractors = [d for d in distractors if not isinstance(d, int) or d >= 0]
    for d in distractors:
        if str(d) not in seen:
            seen.add(str(d))
            opts.append(str(d))
        if len(opts) == 4:
            break
    rng.shuffle(opts)
    return opts


def _puzzle(kind, level, prompt, answer, *, spoken=None, accepts=(), hint="", explain="",
            options=None, visual=None) -> dict:
    return {
        "kind": kind, "skill": SKILLS[kind], "level": level,
        "prompt": prompt, "spoken": spoken or prompt,
        "answer": str(answer), "accepts": [str(a) for a in accepts if str(a) != str(answer)],
        "hint": hint, "explain": explain,
        "options": options, "visual": visual,
    }


# ---------------------------------------------------------------------------
# generated kinds
# ---------------------------------------------------------------------------

def _sequence(level: int, rng: random.Random, room=None) -> dict:
    """What comes next? Rule families unlock as the level rises."""
    rules: list[tuple[str, Callable[[], tuple[list[int], str]]]] = []

    def add():
        start, step = rng.randint(1, 5 + level * 3), rng.randint(2, 3 + level)
        return [start + step * i for i in range(5)], f"add {step} each time"

    def subtract():
        step = rng.randint(2, 3 + level)
        start = step * 5 + rng.randint(5, 20 + level * 5)
        return [start - step * i for i in range(5)], f"take away {step} each time"

    def multiply():
        start, r = rng.randint(1, 4), rng.choice([2, 3] if level < 6 else [2, 3, 4])
        return [start * r ** i for i in range(5)], f"multiply by {r} each time"

    def alternating():
        a = rng.randint(3, 4 + level)
        b = rng.randint(1, a - 1)           # net upward: no negative numbers
        seq, x = [], rng.randint(1, 10)
        for i in range(5):
            seq.append(x)
            x += a if i % 2 == 0 else -b
        return seq, f"add {a}, then take away {b}, and repeat"

    def growing_gaps():
        x, gap = rng.randint(1, 10), rng.randint(1, 3)
        seq = []
        for _ in range(5):
            seq.append(x)
            x += gap
            gap += 1
        return seq, "the gap grows by one each time"

    def squares():
        k = rng.randint(1, 4 + level // 2)
        return [(k + i) ** 2 for i in range(5)], "they are square numbers"

    def fibonacci():
        a, b = rng.randint(1, 4), rng.randint(1, 5)
        seq = [a, b]
        while len(seq) < 5:
            seq.append(seq[-1] + seq[-2])
        return seq, "each number is the two before it added together"

    rules += [("add", add), ("subtract", subtract)]
    if level >= 3:
        rules += [("multiply", multiply), ("alternating", alternating)]
    if level >= 5:
        rules += [("gaps", growing_gaps), ("squares", squares)]
    if level >= 7:
        rules += [("fibonacci", fibonacci)]
    _, rule = rng.choice(rules)
    seq, why = rule()
    shown, answer = seq[:4], seq[4]
    listed = ", ".join(str(n) for n in shown)
    return _puzzle(
        "sequence", level, f"What comes next? {listed}, ...", answer,
        spoken=f"What comes next? {', '.join(number_words(n) for n in shown)}...",
        accepts=_num_accepts(answer), hint=f"Look at how it changes: {why.split(',')[0]}."
        if level <= 3 else "Look at the gap between each pair of numbers.",
        explain=f"It's {answer}: {why}.",
        options=_options(rng, answer, [answer + d for d in rng.sample([-3, -2, -1, 1, 2, 3, 4], 5)]),
    )


def _math(level: int, rng: random.Random, room=None) -> dict:
    if level <= 2:
        a, b = rng.randint(2, 9 + level * 5), rng.randint(2, 9 + level * 5)
        text, answer = f"{a} plus {b}", a + b
    elif level <= 4:
        a, b = rng.randint(3, 12), rng.randint(3, 12)
        if rng.random() < 0.5:
            text, answer = f"{a} times {b}", a * b
        else:
            big = rng.randint(30, 99)
            text, answer = f"{big} minus {a + b}", big - a - b
    elif level <= 7:
        a, b, c = rng.randint(3, 12), rng.randint(3, 12), rng.randint(2, 20)
        choice = rng.randint(0, 2)
        if choice == 0:
            text, answer = f"{a} times {b}, plus {c}", a * b + c
        elif choice == 1:
            n = rng.choice([20, 40, 60, 80, 120, 200]) * rng.randint(1, 3)
            text, answer = f"half of {n}", n // 2
        else:
            n = rng.choice([10, 20, 50]) * rng.randint(2, 10)
            text, answer = f"ten percent of {n}", n // 10
    else:
        a, b, c = rng.randint(11, 25), rng.randint(3, 9), rng.randint(2, 30)
        choice = rng.randint(0, 1)
        if choice == 0:
            text, answer = f"{a} times {b}, minus {c}", a * b - c
        else:
            n = rng.choice([40, 60, 80, 120, 200, 300])
            text, answer = f"a quarter of {n}, plus {c}", n // 4 + c
    return _puzzle(
        "math", level, f"Quick maths: what is {text}?", answer,
        accepts=_num_accepts(answer),
        hint="Break it into smaller steps.",
        explain=f"{text[0].upper() + text[1:]} is {answer}.",
        options=_options(rng, answer, [answer + d for d in rng.sample([-10, -2, -1, 1, 2, 10], 5)]),
    )


def _memory(level: int, rng: random.Random, room=None) -> dict:
    length = min(3 + (level + 1) // 2, 8)
    digits = [rng.randint(1, 9) for _ in range(length)]
    backwards = level >= 4
    target = list(reversed(digits)) if backwards else digits
    said = ", ".join(str(d) for d in digits)
    answer = " ".join(str(d) for d in target)
    how = "backwards" if backwards else "in the same order"
    return _puzzle(
        "memory", level, f"Remember these numbers and say them {how}: {said}", answer,
        spoken=f"Memory test. Listen carefully, then say them {how}. "
               + "... ".join(number_words(d) for d in digits) + ".",
        accepts=["".join(str(d) for d in target), ", ".join(str(d) for d in target),
                 " ".join(number_words(d) for d in target)],
        hint=f"It starts with {target[0]}.",
        explain=f"{how.capitalize()}, it was {answer}.",
    )


_NAMES = ["Asha", "Ben", "Chen", "Divya", "Eli", "Farah", "Gopi", "Hana", "Ira", "Jay",
          "Kiran", "Leo", "Maya", "Nikhil", "Omar", "Priya", "Ravi", "Sara", "Tara", "Vik"]
_RELATIONS = [("taller", "shorter", "tallest", "shortest"),
              ("faster", "slower", "fastest", "slowest"),
              ("older", "younger", "oldest", "youngest")]


def _logic(level: int, rng: random.Random, room=None) -> dict:
    """Ordering: chain of comparisons, ask for one end."""
    n = 3 if level <= 3 else 4 if level <= 6 else 5
    people = rng.sample(_NAMES, n)        # people[0] is the "most"
    more, less, most, least = rng.choice(_RELATIONS)
    facts = []
    for i in range(n - 1):
        a, b = people[i], people[i + 1]
        facts.append(f"{a} is {more} than {b}" if rng.random() < 0.5 else f"{b} is {less} than {a}")
    rng.shuffle(facts)
    ask_most = rng.random() < 0.5
    answer = people[0] if ask_most else people[-1]
    question = most if ask_most else least
    return _puzzle(
        "logic", level, ". ".join(facts) + f". Who is the {question}?", answer,
        hint=f"Line them up from {most} to {least}.",
        explain=f"In order: {', '.join(people)}. So {answer} is the {question}.",
        options=_options(rng, answer, rng.sample([p for p in people if p != answer], len(people) - 1)),
    )


_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def _calendar(level: int, rng: random.Random, room=None) -> dict:
    start = rng.randrange(7)
    if level <= 3:
        k = rng.randint(2, 6)
        text = f"If today is {_DAYS[start]}, what day will it be in {k} days?"
        steps = k
    elif level <= 6:
        k = rng.randint(8, 20)
        text = f"If today is {_DAYS[start]}, what day will it be in {k} days?"
        steps = k
    else:
        k = rng.randint(2, 5)
        text = (f"If the day before yesterday was {_DAYS[start]}, "
                f"what day will it be {k} days after tomorrow?")
        steps = 2 + 1 + k
    answer = _DAYS[(start + steps) % 7]
    return _puzzle(
        "calendar", level, text, answer,
        hint="Every 7 days the week starts again.",
        explain=f"Counting {steps} days on from {_DAYS[start]} lands on {answer}.",
        options=_options(rng, answer, [d for d in rng.sample(_DAYS, 7) if d != answer]),
    )


# ---- spatial: which shape is the rotated one? (TV only) --------------------

_SHAPES = [  # polyomino cells (x, y), all asymmetric so a mirror is distinct
    [(0, 0), (1, 0), (2, 0), (2, 1)],
    [(0, 0), (1, 0), (1, 1), (2, 1), (3, 1)],
    [(0, 0), (0, 1), (1, 1), (2, 1), (2, 2), (3, 2)],
    [(0, 1), (1, 1), (1, 0), (2, 0), (3, 0), (3, 1)],
    [(0, 0), (1, 0), (2, 0), (1, 1), (1, 2), (2, 2)],
]


def _normalize(cells):
    mx, my = min(x for x, _ in cells), min(y for _, y in cells)
    return sorted((x - mx, y - my) for x, y in cells)


def _rotate(cells, quarter_turns):
    out = cells
    for _ in range(quarter_turns % 4):
        out = [(-y, x) for x, y in out]
    return _normalize(out)


def _mirror(cells):
    return _normalize([(-x, y) for x, y in cells])


def _is_chiral(cells) -> bool:
    """True when no rotation of the mirror image equals a rotation of
    the shape -- otherwise "rotated, not flipped" has two right answers."""
    base = _normalize(cells)
    rots = {tuple(_rotate(base, k)) for k in range(4)}
    return not rots & {tuple(_rotate(_mirror(base), k)) for k in range(4)}


assert all(_is_chiral(s) for s in _SHAPES)


def _rotation(level: int, rng: random.Random, room=None) -> dict:
    base = _normalize(rng.choice(_SHAPES[: 2 + min(level // 2, 3)]))
    rotations = {tuple(_rotate(base, k)) for k in range(4)}
    correct = _rotate(base, rng.randint(1, 3))
    decoys, tries = [], 0
    while len(decoys) < 3 and tries < 50:
        tries += 1
        d = _rotate(_mirror(base), rng.randint(0, 3))
        if level >= 6 and rng.random() < 0.5:      # near-miss: move one cell
            d = [list(c) for c in d]
            i = rng.randrange(len(d))
            d[i][0] += rng.choice([-1, 1])
            d = _normalize([tuple(c) for c in d])
            if len(set(d)) != len(d):
                continue
        if tuple(d) in rotations or d in decoys:
            continue
        decoys.append(d)
    letters = ["A", "B", "C", "D"]
    choices = [correct] + decoys
    rng.shuffle(choices)
    answer = letters[choices.index(correct)]
    return _puzzle(
        "rotation", level, "Which shape is the first shape turned around (not flipped)?", answer,
        hint="Imagine spinning it on the table, without picking it up.",
        explain=f"{answer} is the same shape, just rotated. The others are mirror images"
                + (" or changed." if level >= 6 else "."),
        options=letters[: len(choices)],
        visual={"target": [list(c) for c in base],
                "choices": [[list(c) for c in s] for s in choices]},
    )


# ---- library kinds (content_service: LLM-grown, no repeats per table) -------

def _analogy(level: int, rng: random.Random, room=None) -> dict:
    from games import content_service as cs
    item = cs.pick_one(room, "analogy") if room is not None else rng.choice(cs.all_items("analogy"))
    if item is None:
        return _sequence(level, rng, room)
    others = [i["answer"] for i in cs.all_items("analogy") if i["answer"] != item["answer"]]
    return _puzzle(
        "analogy", level, f"{item['a']} is to {item['b']} as {item['c']} is to what?",
        item["answer"], accepts=item.get("accepts", []),
        hint=f"Think about how {item['a'].lower()} and {item['b'].lower()} are connected.",
        explain=f"{item['a']} goes with {item['b']}, and {item['c']} goes with {item['answer']}.",
        # Plausible decoys: the other words in the puzzle, then other answers.
        options=_options(rng, item["answer"],
                         [item["b"], item["c"]] + rng.sample(others, min(6, len(others)))),
    )


def _odd_word(level: int, rng: random.Random, room=None) -> dict:
    from games import content_service as cs
    item = cs.pick_one(room, "odd_word") if room is not None else rng.choice(cs.all_items("odd_word"))
    if item is None:
        return _sequence(level, rng, room)
    words = list(item["words"])
    rng.shuffle(words)
    return _puzzle(
        "odd_word", level, f"Which is the odd one out: {', '.join(words[:3])}, or {words[3]}?",
        item["answer"], hint="Three of them have something in common.",
        explain=f"{item['answer']}. {item['why']}", options=words,
    )


_MAKERS = {
    "sequence": _sequence, "math": _math, "memory": _memory, "logic": _logic,
    "calendar": _calendar, "rotation": _rotation, "analogy": _analogy, "odd_word": _odd_word,
}


def make(kind: str, level: int = 3, rng: random.Random | None = None, room=None) -> dict:
    """One puzzle of ``kind`` at ``level`` (clamped to 1-10)."""
    level = max(1, min(10, int(level)))
    return _MAKERS[kind](level, rng or random.Random(), room)


def mix(count: int, level: int, kinds=VOICE_KINDS, rng: random.Random | None = None,
        room=None) -> list[dict]:
    """``count`` puzzles cycling through ``kinds`` in a shuffled order, so
    consecutive puzzles exercise different skills."""
    rng = rng or random.Random()
    order = list(kinds)
    rng.shuffle(order)
    return [make(order[i % len(order)], level, rng, room) for i in range(count)]


# ---------------------------------------------------------------------------
# HTTP (Travel Mode's Brain Teasers)
# ---------------------------------------------------------------------------

brain_bp = Blueprint("brain", __name__)


class _DeviceRoom:
    """Just enough of a Room for content_service's per-device history."""

    class _P:
        is_bot = False

        def __init__(self, pid):
            self.id = pid

    def __init__(self, device):
        self.players = [self._P(device)] if device else []
        self.content_history = {}


@brain_bp.route("/puzzles", methods=["GET"])
def brain_puzzles():
    """GET /api/brain/puzzles?level=3&count=10&kinds=sequence,math&device=..."""
    try:
        level = int(request.args.get("level") or 3)
    except ValueError:
        level = 3
    try:
        count = max(1, min(30, int(request.args.get("count") or 10)))
    except ValueError:
        count = 10
    asked = [k for k in (request.args.get("kinds") or "").split(",") if k in _MAKERS]
    kinds = tuple(asked) or VOICE_KINDS
    device = (request.args.get("device") or "").strip()[:64] or None
    puzzles = mix(count, level, kinds, room=_DeviceRoom(device))
    return jsonify({"success": True, "level": max(1, min(10, level)), "puzzles": puzzles})
