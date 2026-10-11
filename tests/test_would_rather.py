"""Would You Rather: simultaneous votes, a split reveal, no repeated card."""

import random
import time

from games.native_hub.engines.would_rather import (
    LONE_WOLF_POINTS, MAJORITY_POINTS, WouldRatherEngine)
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


def make(n=4, seed=5):
    random.seed(seed)
    room = RoomRegistry().create("would_rather")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(n)]
    engine = WouldRatherEngine(room, None)
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def push(engine):
    engine.deadline = time.time() - 1
    engine.tick(0)


def test_registered():
    assert ENGINES["would_rather"] is WouldRatherEngine


def test_votes_are_secret_until_reveal_and_rejected_when_junk():
    engine, r = make()
    engine.handle_action("p0", "vote", {"side": "a"})
    engine.handle_action("p1", "vote", {"side": "zzz"})
    engine.handle_action("p2", "vote", None)
    st = engine.public_state()
    assert st["votesSoFar"] == 1 and st["reveal"] is None
    assert "myVote" not in st and "votes" not in st
    assert engine.private_state("p0")["myVote"] == "a"
    assert engine.private_state("p1")["hasVoted"] is False


def test_majority_and_lone_wolf_scoring_and_reveal():
    engine, r = make(4)
    for pid, side in (("p0", "a"), ("p1", "a"), ("p2", "a"), ("p3", "b")):
        engine.handle_action(pid, "vote", {"side": side})
    push(engine)
    assert engine.phase == "reveal"
    rev = engine.public_state()["reveal"]
    assert (rev["a"], rev["b"], rev["aPercent"], rev["bPercent"]) == (3, 1, 75, 25)
    assert rev["bNames"] == ["P3"]
    assert engine.scores["p0"] == MAJORITY_POINTS
    assert engine.scores["p3"] == LONE_WOLF_POINTS


def test_tie_scores_everyone_and_nobody_voting_is_fine():
    engine, r = make(2)
    engine.handle_action("p0", "vote", {"side": "a"})
    engine.handle_action("p1", "vote", {"side": "b"})
    push(engine)
    assert engine.scores["p0"] == engine.scores["p1"] == MAJORITY_POINTS
    engine2, _ = make(2)
    push(engine2)
    assert engine2.public_state()["reveal"]["total"] == 0


def test_no_dilemma_repeats_across_a_game():
    engine, r = make(3)
    seen = []
    for _ in range(WouldRatherEngine.total_rounds):
        seen.append((engine.a, engine.b))
        engine.handle_action("p0", "vote", {"side": "a"})
        push(engine)      # vote -> reveal
        push(engine)      # reveal -> next round
        if engine.is_over():
            break
    assert len(set(seen)) == len(seen) == WouldRatherEngine.total_rounds
