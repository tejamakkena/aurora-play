"""Brain Battle: a TV puzzle party built on games/brain_puzzles.py.

Every round is one generated puzzle (sequences, quick maths, memory chains,
ordering and calendar logic, analogies, odd-one-out words and shape
rotation). The TV shows the puzzle, every phone shows the same four answer
buttons, and the fastest correct answers score the most.

Phases per round::

    memorize (memory puzzles only) -> answer -> reveal

and after the last round a ``summary`` phase where the TV shows the final
ranking with each player's "brain title" before the room moves to results.

Scoring happens at the end of the answer phase, not on the tap, so the
scoreboard on the TV never gives away who was right before the reveal.

Each human player's "Brain Score" (0-100, percent correct weighted by
puzzle level) is compared with their personal best, saved best-effort to
``data/brain_scores.json`` (override with ``BRAIN_SCORES_PATH``) keyed by
player id -- player ids are stable device UUIDs.
"""

import json
import os
import random
import time
from pathlib import Path

from games import brain_puzzles as bp
from games.native_hub.engines._bases import RoundBasedEngine

#: skill name (brain_puzzles.SKILLS values) -> end-of-game title.
BRAIN_TITLES = {
    "Patterns": "Pattern Master",
    "Number Speed": "Number Ninja",
    "Memory": "Memory Champ",
    "Logic": "Logic Legend",
    "Word Smarts": "Word Wizard",
    "Spatial": "Shape Shifter",
}
#: Tie-break order when two skills are equally strong.
SKILL_ORDER = ["Logic", "Spatial", "Memory", "Patterns", "Number Speed", "Word Smarts"]
FALLBACK_TITLE = "Brain in Training"


def _scores_path() -> Path:
    override = os.environ.get("BRAIN_SCORES_PATH")
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[3] / "data" / "brain_scores.json"


def load_brain_scores() -> dict:
    try:
        data = json.loads(_scores_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_brain_scores(data: dict) -> None:
    path = _scores_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass   # best-effort: the hosted disk may be read-only or wiped


def memory_options(rng: random.Random, digits: list[int], backwards: bool) -> tuple[str, list[str]]:
    """The answer and four multiple-choice options for a memory chain.

    Distractors are near misses: two neighbours swapped, one digit changed,
    and (when asked backwards) the sequence in the order it was shown.
    """
    target = list(reversed(digits)) if backwards else list(digits)
    answer = " ".join(str(d) for d in target)
    candidates: list[list[int]] = []
    if backwards and digits != target:
        candidates.append(list(digits))            # forgot to reverse
    for _ in range(3):
        i = rng.randrange(len(target) - 1)
        swapped = list(target)
        swapped[i], swapped[i + 1] = swapped[i + 1], swapped[i]
        candidates.append(swapped)
    for _ in range(6):
        changed = list(target)
        i = rng.randrange(len(changed))
        changed[i] = rng.choice([d for d in range(1, 10) if d != changed[i]])
        candidates.append(changed)
    opts = [answer]
    for c in candidates:
        text = " ".join(str(d) for d in c)
        if text not in opts:
            opts.append(text)
        if len(opts) == 4:
            break
    while len(opts) < 4:                           # paranoia: always four
        filler = " ".join(str(rng.randint(1, 9)) for _ in target)
        if filler not in opts:
            opts.append(filler)
    rng.shuffle(opts)
    return answer, opts


class BrainBattleEngine(RoundBasedEngine):
    """Twelve generated puzzles, fastest correct answer scores most."""

    game_id = "brain_battle"
    min_players = 2
    max_players = 12
    total_rounds = 12
    first_phase = "answer"
    phase_seconds = {"memorize": 4, "answer": 20, "reveal": 7, "summary": 14}

    BASE_POINTS = 500
    SPEED_BONUS = 500
    START_LEVEL = 2
    MAX_LEVEL = 10

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.rng = random.Random(random.random())
        self.kind_order: list[str] = list(bp.ALL_KINDS)
        self.puzzle: dict = {}
        self.memory_digits: list[int] = []
        self.memory_backwards = False
        self.answer_started = 0.0
        self.round_outcome: dict | None = None
        #: player_id -> skill -> {"correct": n, "total": n}
        self.skill_stats: dict[str, dict[str, dict[str, int]]] = {}
        #: player_id -> [weighted correct, weighted total]
        self.level_points: dict[str, list[int]] = {}
        self.final: list[dict] = []

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players):
        self.rng.shuffle(self.kind_order)
        super().start(players)

    def level_for_round(self, round_no: int) -> int:
        return min(self.MAX_LEVEL, self.START_LEVEL + (round_no - 1) // 2)

    def kind_for_round(self, round_no: int) -> str:
        return self.kind_order[(round_no - 1) % len(self.kind_order)]

    def start_round(self):
        self.submissions = {}
        self.round_outcome = None
        self._make_puzzle()
        self.enter_phase("memorize" if self.puzzle.get("kind") == "memory" else "answer")

    def _make_puzzle(self):
        kind = self.kind_for_round(self.round)
        level = self.level_for_round(self.round)
        try:
            puzzle = bp.make(kind, level, self.rng, self.room)
        except Exception:
            puzzle = bp.make("sequence", level, self.rng, None)
        self.memory_digits = []
        self.memory_backwards = False
        if puzzle.get("kind") == "memory":
            # Re-derive the digits from the puzzle's own answer so the
            # generator stays the single source of truth.
            target = [int(c) for c in str(puzzle["answer"]).split()]
            self.memory_backwards = "backwards" in puzzle.get("prompt", "")
            self.memory_digits = list(reversed(target)) if self.memory_backwards else target
            answer, options = memory_options(self.rng, self.memory_digits, self.memory_backwards)
            how = "backwards (last digit first)" if self.memory_backwards else "in the same order"
            puzzle = dict(puzzle)
            puzzle["answer"] = answer
            puzzle["options"] = options
            puzzle["prompt"] = f"Which digits did you see, {how}?"
            puzzle["explain"] = f"The digits were {' '.join(str(d) for d in self.memory_digits)}" + (
                f", so backwards it is {answer}." if self.memory_backwards else ".")
        options = [str(o) for o in (puzzle.get("options") or [])]
        if len(options) < 2 or str(puzzle["answer"]) not in options:
            puzzle = bp.make("sequence", level, self.rng, None)
            options = [str(o) for o in puzzle["options"]]
        puzzle["options"] = options
        self.puzzle = puzzle

    def memorize_seconds(self) -> int:
        """Long chains get a little longer on screen (4s for four digits)."""
        return max(4, 2 + len(self.memory_digits) // 2 + 1)

    def enter_phase(self, phase):
        super().enter_phase(phase)
        if phase == "memorize":
            self.deadline = time.time() + self.memorize_seconds()

    def begin_phase(self, phase):
        if phase == "answer":
            self.answer_started = time.time()

    def resolve_phase(self, phase):
        if phase == "memorize":
            return "answer"
        if phase == "answer":
            self._score_round()
            return "reveal"
        return None          # reveal / summary end the round

    def end_round(self):
        if self.phase == "summary":
            self._finished = True
            self.phase = "final"
            self.deadline = 0.0
            return
        if self.round >= self.total_rounds:
            self._finalize()
            self.enter_phase("summary")
            return
        super().end_round()

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id, action, data):
        if action != "answer" or self.phase != "answer" or self._finished:
            return
        if self.room.player(player_id) is None or player_id in self.submissions:
            return                           # unknown player, or already locked
        choice = data.get("choice") if isinstance(data, dict) else None
        if not isinstance(choice, str) or choice not in self.puzzle.get("options", []):
            return
        elapsed = max(0.0, time.time() - self.answer_started)
        self.submissions[player_id] = {"choice": choice, "elapsed": elapsed}

    # ---- scoring -----------------------------------------------------------

    def points_for(self, elapsed: float) -> int:
        total = float(self.phase_seconds["answer"])
        left = max(0.0, min(total, total - elapsed))
        return self.BASE_POINTS + int(round(self.SPEED_BONUS * left / total))

    def _score_round(self):
        answer = str(self.puzzle.get("answer", ""))
        skill = self.puzzle.get("skill") or bp.SKILLS.get(self.puzzle.get("kind", ""), "Logic")
        level = int(self.puzzle.get("level", 1) or 1)
        rows, correct_ids = [], []
        fastest_id, fastest_time = None, None
        counted = {p.id for p in self.active_players()} | set(self.submissions)
        for pid in counted:
            self.scores.setdefault(pid, 0)
            sub = self.submissions.get(pid)
            ok = bool(sub) and sub["choice"] == answer
            stats = self.skill_stats.setdefault(pid, {}).setdefault(skill, {"correct": 0, "total": 0})
            stats["total"] += 1
            lv = self.level_points.setdefault(pid, [0, 0])
            lv[1] += level
            points = 0
            if ok:
                stats["correct"] += 1
                lv[0] += level
                points = self.points_for(sub["elapsed"])
                self.award(pid, points)
                correct_ids.append(pid)
                if fastest_time is None or sub["elapsed"] < fastest_time:
                    fastest_id, fastest_time = pid, sub["elapsed"]
            if sub:
                rows.append({"playerID": pid, "name": self.player_name(pid),
                             "choice": sub["choice"], "correct": ok, "points": points,
                             "seconds": round(sub["elapsed"], 1)})
        rows.sort(key=lambda r: (not r["correct"], r["seconds"]))
        self.round_outcome = {
            "answer": answer,
            "explain": self.puzzle.get("explain", ""),
            "correctIDs": correct_ids,
            "fastestID": fastest_id,
            "fastestName": self.player_name(fastest_id) if fastest_id else None,
            "fastestSeconds": round(fastest_time, 1) if fastest_time is not None else None,
            "answers": rows,
        }

    # ---- end of game -------------------------------------------------------

    def best_skill(self, player_id: str) -> str | None:
        stats = self.skill_stats.get(player_id, {})
        best, best_key = None, None
        for skill, s in stats.items():
            if s["correct"] <= 0 or s["total"] <= 0:
                continue
            order = SKILL_ORDER.index(skill) if skill in SKILL_ORDER else len(SKILL_ORDER)
            key = (s["correct"] / s["total"], s["correct"], -order)
            if best_key is None or key > best_key:
                best, best_key = skill, key
        return best

    def brain_title(self, player_id: str) -> str:
        skill = self.best_skill(player_id)
        return BRAIN_TITLES.get(skill, FALLBACK_TITLE) if skill else FALLBACK_TITLE

    def brain_score(self, player_id: str) -> int:
        got, total = self.level_points.get(player_id, [0, 0])
        return int(round(100 * got / total)) if total else 0

    def _skill_rows(self, player_id: str) -> list[dict]:
        stats = self.skill_stats.get(player_id, {})
        return [{"skill": k, "correct": v["correct"], "total": v["total"]}
                for k, v in sorted(stats.items())]

    def _build_rows(self) -> list[dict]:
        rows = self.ranked_results(self.scores)
        for row in rows:
            pid = row["playerID"]
            row.update({
                "brainTitle": self.brain_title(pid),
                "bestSkill": self.best_skill(pid),
                "brainScore": self.brain_score(pid),
                "skills": self._skill_rows(pid),
                "personalBest": False,
                "previousBest": None,
            })
        return rows

    def _finalize(self):
        """Build the final ranking and record personal bests (once)."""
        if self.final:
            return
        rows = self._build_rows()
        store = load_brain_scores()
        changed = False
        for row in rows:
            pid = row["playerID"]
            player = self.room.player(pid)
            if player is None or getattr(player, "is_bot", False):
                continue
            entry = store.get(pid)
            prev = entry.get("best") if isinstance(entry, dict) else None
            prev = prev if isinstance(prev, int) else None
            score = row["brainScore"]
            row["previousBest"] = prev
            if (prev is None and score > 0) or (prev is not None and score > prev):
                row["personalBest"] = True
                store[pid] = {"best": score, "name": row["name"], "at": int(time.time())}
                changed = True
        if changed:
            save_brain_scores(store)
        self.final = rows

    def results(self):
        if self.final:
            return [dict(r) for r in self.final]
        # Asked before the summary (e.g. the room ended early): rank what
        # has been played so far, without touching the personal bests.
        return self._build_rows()

    # ---- state -------------------------------------------------------------

    def _public_puzzle(self) -> dict:
        p = self.puzzle
        return {
            "id": f"r{self.round}",
            "kind": p.get("kind", ""),
            "skill": p.get("skill", ""),
            "level": p.get("level", 1),
            "prompt": p.get("prompt", ""),
            # Options stay hidden while the memory digits are on screen.
            "options": [] if self.phase == "memorize" else list(p.get("options") or []),
            "visual": p.get("visual"),
        }

    def public_state(self):
        state = self.base_public()
        in_round = self.phase in ("memorize", "answer", "reveal")
        state.update({
            "puzzle": self._public_puzzle() if in_round else None,
            "memoryDigits": list(self.memory_digits) if self.phase == "memorize" else [],
            "memoryBackwards": self.memory_backwards,
            "phaseSeconds": (self.memorize_seconds() if self.phase == "memorize"
                             else self.phase_seconds.get(self.phase, 0)),
            "lockedCount": len(self.submissions),
            "activeCount": len(self.active_players()),
            "reveal": self.round_outcome if self.phase == "reveal" else None,
            "results": [dict(r) for r in self.final] if self.phase in ("summary", "final") else [],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        sub = self.submissions.get(player_id)
        p = self.puzzle
        in_round = self.phase in ("memorize", "answer", "reveal")
        state.update({
            "puzzleID": f"r{self.round}",
            "totalRounds": self.total_rounds,
            "kind": p.get("kind", "") if in_round else "",
            "skill": p.get("skill", "") if in_round else "",
            "prompt": p.get("prompt", "") if in_round else "",
            "options": list(p.get("options") or []) if self.phase in ("answer", "reveal") else [],
            "visual": p.get("visual") if in_round else None,
            "myAnswer": sub["choice"] if sub else None,
            "locked": sub is not None,
            "myScore": self.scores.get(player_id, 0),
            "wasCorrect": None,
            "pointsEarned": 0,
            "correctAnswer": None,
            "isFastest": False,
        })
        if self.phase == "reveal" and self.round_outcome is not None:
            ok = player_id in self.round_outcome["correctIDs"]
            state.update({
                "wasCorrect": ok,
                "pointsEarned": self.points_for(sub["elapsed"]) if (ok and sub) else 0,
                "correctAnswer": self.round_outcome["answer"],
                "isFastest": self.round_outcome["fastestID"] == player_id,
            })
        if self.phase in ("summary", "final"):
            mine = next((r for r in self.final if r["playerID"] == player_id), None)
            if mine is not None:
                state.update({
                    "rank": mine["rank"],
                    "brainTitle": mine["brainTitle"],
                    "brainScore": mine["brainScore"],
                    "personalBest": mine["personalBest"],
                })
        return state

    def on_player_join(self, player):
        self.scores.setdefault(player.id, 0)


ENGINES = {
    "brain_battle": BrainBattleEngine,
}
