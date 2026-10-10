"""The Host Is Lying: lie schedule, tells that are hints and not giveaways,
secret votes, scoring, and what phones are (and are not) told."""

import random
import time

import pytest

from games.native_hub.engines import _hostlies as H
from games.native_hub.engines.host_lies import (
    CATCH_LIE, CHALLENGER_HIT, CHALLENGER_MISS, FALSE_ACCUSATION, MAX_PRESSES,
    TRUST_RIGHT, HostLiesEngine)
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


def make(n=4, seed=1):
    room = RoomRegistry().create("host_lies")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(n)]
    engine = HostLiesEngine(room, None)
    engine.rng = random.Random(seed)
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def push(engine):
    engine.deadline = time.time() - 1
    engine.tick(0)


def to_vote(engine):
    push(engine)       # claim -> grill
    push(engine)       # grill -> vote
    assert engine.phase == "vote"


def test_registered_and_bank_is_clean():
    assert ENGINES["host_lies"] is HostLiesEngine
    assert len(H.FACTS) >= 70
    assert len({f[0] for f in H.FACTS}) == len(H.FACTS)
    for true, false, why in H.FACTS:
        assert true != false and why.endswith(".") and len(true) < 140


def test_schedule_mixes_lies_and_truths_without_long_runs():
    for seed in range(40):
        engine, _ = make(seed=seed)
        s = engine.schedule
        assert len(s) == engine.total_rounds
        assert 3 <= sum(s) <= 5
        run = longest = 1
        for a, b in zip(s, s[1:]):
            run = run + 1 if a == b else 1
            longest = max(longest, run)
        assert longest <= 3


def test_tells_are_hints_not_giveaways():
    """A tell is much likelier on a lie, but honest lines show them too and
    some lies show none. Simulated over many rounds at every difficulty."""
    engine, _ = make()
    for rnd in (1, 4, 8):
        engine.round = rnd
        lie_tell = true_tell = lie_clean = 0
        n = 4000
        for _ in range(n):
            lie = engine.pick_tells(True)
            honest = engine.pick_tells(False)
            lie_tell += bool(lie)
            lie_clean += not lie
            true_tell += bool(honest)
        assert lie_tell / n > true_tell / n + 0.15     # informative
        assert true_tell / n > 0.08                    # honest hosts fidget
        assert lie_clean / n > 0.10                    # some lies are clean
    # and the tells fade as the game goes on
    engine.round = 1
    early = sum(bool(engine.pick_tells(True)) for _ in range(3000))
    engine.round = 8
    late = sum(bool(engine.pick_tells(True)) for _ in range(3000))
    assert early > late


def test_delivery_changes_with_tells():
    engine, _ = make()
    plain = engine.deliver("The sky is blue.", [])
    assert plain["text"] == "The sky is blue." and plain["rate"] < 1.0
    rushed = engine.deliver("The sky is blue.", ["rushed"])
    assert rushed["rate"] > 1.2 and rushed["preDelay"] == 0
    stall = engine.deliver("The sky is blue.", ["stall"])
    assert stall["preDelay"] > 1.0
    for t in ("hedge", "overexplain", "repeat"):
        assert len(engine.deliver("The sky is blue.", [t])["text"]) > len(plain["text"])


def test_claim_is_spoken_and_phones_never_see_the_verdict():
    engine, roster = make()
    pub = engine.public_state()
    assert pub["speech"]["seq"] >= 1 and engine.statement in pub["speech"]["text"]
    priv = engine.private_state("p0")
    assert priv["statement"] == engine.statement
    blob = str(priv)
    assert "isLie" not in blob and "tells" not in blob and "rate" not in blob
    assert engine.item[0] not in blob or engine.item[0] == engine.statement
    assert HostLiesEngine.heavy_state is True


def test_grill_limits_and_challenger():
    engine, roster = make(5)
    push(engine)                                   # to grill
    assert engine.phase == "grill"
    engine.handle_action("p0", "press", {})
    engine.handle_action("p0", "press", {})        # one press each
    for pid in ("p1", "p2", "p3"):
        engine.handle_action(pid, "press", {})
    assert len(engine.defences) == MAX_PRESSES
    assert engine.pressers[0] == "p0"
    assert engine.private_state("p4")["canPress"] is False
    assert engine.public_state()["speech"]["text"] == engine.defences[-1]["text"]
    engine.handle_action("p1", "vote", {"side": "liar"})      # wrong phase
    assert engine.votes == {}


def test_voting_is_secret_validated_and_ends_early():
    engine, roster = make(3)
    to_vote(engine)
    engine.handle_action("p0", "vote", {"side": "liar"})
    engine.handle_action("p1", "vote", {"side": "banana"})
    engine.handle_action("ghost", "vote", {"side": "trust"})
    assert list(engine.votes) == ["p0"]
    pub = engine.public_state()
    assert pub["votesSoFar"] == 1 and pub["reveal"] is None
    assert engine.private_state("p1")["myVote"] is None
    engine.handle_action("p1", "vote", {"side": "trust"})
    engine.handle_action("p2", "vote", {"side": "trust"})
    engine.tick(0)                                  # everyone voted: no waiting
    assert engine.phase == "reveal"


@pytest.mark.parametrize("lie", [True, False])
def test_scoring(lie):
    engine, roster = make(4)
    engine.schedule[0] = lie
    engine.is_lie = lie                              # round 1 already dealt
    push(engine)                                     # grill
    engine.handle_action("p3", "press", {})          # p3 is the challenger
    push(engine)                                     # vote
    engine.is_lie = lie
    engine.handle_action("p0", "vote", {"side": "liar"})
    engine.handle_action("p1", "vote", {"side": "trust"})
    push(engine)                                     # reveal
    s = engine.scores
    if lie:
        assert s["p0"] == CATCH_LIE and s["p1"] == 0
        assert s["p3"] == CHALLENGER_HIT
    else:
        assert s["p0"] == 0                          # floor at zero
        assert s["p1"] == TRUST_RIGHT
        assert s["p3"] == 0
    rev = engine.private_state("p0")["reveal"]
    assert rev["isLie"] is lie and rev["fooled"] == 1
    assert rev["truth"] == engine.item[0]
    assert engine.public_state()["speech"]["text"]
    delta0 = engine.private_state("p0")["reveal"]["delta"]
    assert delta0 == (CATCH_LIE if lie else FALSE_ACCUSATION)


def test_false_accusation_can_cost_points_once_earned():
    engine, roster = make(2)
    engine.scores["p0"] = 200
    engine.is_lie = False
    to_vote(engine)
    engine.is_lie = False
    engine.handle_action("p0", "vote", {"side": "liar"})
    engine.handle_action("p1", "vote", {"side": "trust"})
    push(engine)
    assert engine.scores["p0"] == 200 + FALSE_ACCUSATION
    assert engine.scores["p1"] == TRUST_RIGHT


def test_full_game_never_repeats_a_fact_and_ends():
    engine, roster = make(3, seed=9)
    seen = set()
    for _ in range(engine.total_rounds):
        seen.add(engine.item[0])
        to_vote(engine)
        engine.handle_action("p0", "vote", {"side": "liar"})
        push(engine)           # reveal
        assert engine.phase == "reveal"
        push(engine)           # next round or final
    assert len(seen) == engine.total_rounds
    assert engine.is_over()
    assert [r["rank"] for r in engine.results()][0] == 1
