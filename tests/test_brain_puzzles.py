"""Brain puzzles: generated answers must be right, every time."""

import random
import re

import pytest
from flask import Flask

from games import brain_puzzles as bp
from utils.room_manager import RoomRegistry

LEVELS = range(1, 11)


def many(kind, n=300, seed=11):
    rng = random.Random(seed)
    return [bp.make(kind, rng.choice(LEVELS), rng) for _ in range(n)]


@pytest.mark.parametrize("kind", bp.ALL_KINDS)
def test_every_kind_and_level_is_well_formed(kind):
    for p in many(kind, 150):
        assert p["prompt"] and p["answer"] and p["hint"] and p["explain"]
        assert p["skill"] == bp.SKILLS[kind]
        if p["options"] is not None:
            assert p["answer"] in p["options"]
            assert len(set(p["options"])) == len(p["options"]) >= 3


def test_number_words():
    assert bp.number_words(0) == "zero"
    assert bp.number_words(14) == "fourteen"
    assert bp.number_words(70) == "seventy"
    assert bp.number_words(123) == "one hundred twenty three"
    assert bp.number_words(2048) == "two thousand forty eight"


def test_sequence_answers_are_never_negative_and_accept_words():
    for p in many("sequence"):
        n = int(p["answer"])
        assert n >= 0
        assert bp.number_words(n) in p["accepts"]


def test_math_answers_are_correct():
    ops = {"plus": "+", "minus": "-", "times": "*"}
    for p in many("math"):
        text = re.sub(r"^Quick maths: what is |\?$", "", p["prompt"])
        if text.startswith(("half", "ten percent", "a quarter")):
            continue
        expr = text.replace(",", "")
        for word, sym in ops.items():
            expr = expr.replace(f" {word} ", f" {sym} ")
        assert eval(expr) == int(p["answer"]), p["prompt"]


def test_memory_reverses_from_level_four():
    rng = random.Random(3)
    low, high = bp.make("memory", 2, rng), bp.make("memory", 6, rng)
    shown = lambda p: re.findall(r"\d", p["prompt"].split(":")[1])
    assert low["answer"].split() == shown(low)
    assert high["answer"].split() == list(reversed(shown(high)))
    assert "".join(high["answer"].split()) in high["accepts"]


def test_logic_answer_follows_from_the_facts():
    for p in many("logic"):
        facts = re.findall(r"(\w+) is (\w+) than (\w+)", p["prompt"])
        greater = {}
        for a, rel, b in facts:
            bigger, smaller = (a, b) if rel in ("taller", "faster", "older") else (b, a)
            greater.setdefault(bigger, set()).add(smaller)
        people = {x for a, _, b in facts for x in (a, b)}
        top = [x for x in people if not any(x in s for s in greater.values())]
        bottom = [x for x in people if x not in greater]
        asked_top = re.search(r"the (tallest|fastest|oldest)\?", p["prompt"])
        assert p["answer"] == (top[0] if asked_top else bottom[0]), p["prompt"]


def test_calendar_answers_are_correct():
    days = bp._DAYS
    for p in many("calendar"):
        start = next(d for d in days if d in p["prompt"])
        k = int(re.search(r"(\d+) days", p["prompt"]).group(1))
        steps = k + 3 if "day before yesterday" in p["prompt"] else k
        assert p["answer"] == days[(days.index(start) + steps) % 7]


def test_rotation_has_exactly_one_true_rotation():
    for p in many("rotation"):
        target = [tuple(c) for c in p["visual"]["target"]]
        rotations = {tuple(bp._rotate(target, k)) for k in range(4)}
        hits = [i for i, c in enumerate(p["visual"]["choices"])
                if tuple(bp._normalize([tuple(x) for x in c])) in rotations]
        assert len(hits) == 1
        assert p["options"][hits[0]] == p["answer"]


def test_library_kinds_do_not_repeat_for_a_table():
    room = RoomRegistry().create("brain_battle")
    room.add_player("phone-1", "A", "s1")
    rng = random.Random(1)
    seen = [bp.make("analogy", 3, rng, room)["prompt"] for _ in range(40)]
    assert len(set(seen)) == len(seen)


def test_mix_rotates_through_skills():
    puzzles = bp.mix(14, 4, bp.VOICE_KINDS, random.Random(2))
    kinds = [p["kind"] for p in puzzles]
    assert all(kinds[i] != kinds[i + 1] for i in range(len(kinds) - 1))
    assert set(kinds) == set(bp.VOICE_KINDS)


def test_endpoint():
    app = Flask(__name__)
    app.register_blueprint(bp.brain_bp, url_prefix="/api/brain")
    client = app.test_client()
    body = client.get("/api/brain/puzzles?level=4&count=6&kinds=sequence,math,bogus").get_json()
    assert body["success"] and len(body["puzzles"]) == 6
    assert {p["kind"] for p in body["puzzles"]} <= {"sequence", "math"}
    junk = client.get("/api/brain/puzzles?level=x&count=y").get_json()
    assert junk["level"] == 3 and len(junk["puzzles"]) == 10
