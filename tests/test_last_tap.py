"""Last Tap Standing: varied reflex rounds, lives, private tile layouts."""

import time

import pytest

from games.native_hub.engines import last_tap as lt
from games.native_hub.engines.last_tap import KINDS, LastTapEngine
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


def make(n=4):
    room = RoomRegistry().create("last_tap")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(n)]
    engine = LastTapEngine(room, None)
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def go(engine, kind):
    """Jump straight into the playing phase of a given kind."""
    engine.kind = kind
    engine.round -= 1
    engine._bag = [kind]
    engine._next_round()
    engine.go_at = time.time() - 1
    engine.tick(0)
    assert engine.phase == "go" and engine.kind == kind


def finish(engine):
    engine.go_shown_at = time.time() - 60
    engine.tick(0)
    assert engine.phase == "reveal"


def test_registered():
    assert ENGINES["last_tap"] is LastTapEngine


def test_every_kind_is_played_before_any_repeats_and_never_twice_in_a_row():
    engine, _ = make(2)
    kinds = [engine.kind]
    for _ in range(len(KINDS) * 3 - 1):
        engine._next_round()
        kinds.append(engine.kind)
    for lap in range(3):
        assert sorted(kinds[lap * len(KINDS):(lap + 1) * len(KINDS)]) == sorted(KINDS)
    assert all(a != b for a, b in zip(kinds, kinds[1:]))


def test_reaction_round_false_start_and_ranking():
    engine, _ = make(4)
    go(engine, "reaction")
    engine.handle_action("p0", "tap", {})
    time.sleep(0.02)
    engine.handle_action("p1", "tap", {})
    engine.handle_action("p2", "tap", {})
    engine.handle_action("p3", "tap", {})
    engine.tick(0)
    assert engine.phase == "reveal"
    res = engine.public_state()["results"]
    assert [r["playerID"] for r in res][0] == "p0"
    assert all(not r["falseStart"] for r in res)


def test_tapping_before_go_in_a_reaction_round_is_a_false_start():
    engine, _ = make(3)
    engine.kind = "reaction"
    engine.phase = "arming"
    engine.go_at = time.time() + 30
    engine.handle_action("p0", "tap", {})
    assert engine.private_state("p0")["falseStart"] is True


def test_pump_round_most_taps_survives_and_fastest_gap_is_enforced():
    engine, _ = make(4)
    go(engine, "pump")
    for i in range(30):
        engine.last_tap_at["p0"] = 0.0          # a human, spaced out
        engine.handle_action("p0", "tap", {})
    for _ in range(10):
        engine.last_tap_at["p1"] = 0.0
        engine.handle_action("p1", "tap", {})
    for _ in range(5):                         # a macro: no gap at all
        engine.handle_action("p2", "tap", {})
    assert engine.taps["p2"] == 1
    finish(engine)
    st = engine.public_state()
    assert st["results"][0]["playerID"] == "p0"
    assert st["results"][0]["detail"] == "30 taps"
    assert st["lostLifePlayerIDs"]            # somebody always loses a life


def test_colour_round_correct_tile_wins_wrong_tile_loses():
    engine, _ = make(3)
    go(engine, "colour")
    # Tiles are private and shuffled per player; none says which is right.
    priv = engine.private_state("p0")
    assert len(priv["tiles"]) == 9 and priv["target"]["name"] == engine.target[0]
    assert all("ok" not in t for t in priv["tiles"])
    right = next(i for i, t in enumerate(engine.tiles["p0"]) if t["ok"])
    wrong = next(i for i, t in enumerate(engine.tiles["p1"]) if not t["ok"])
    engine.handle_action("p0", "tap", {"tile": right})
    engine.handle_action("p1", "tap", {"tile": wrong})
    finish(engine)
    res = {r["playerID"]: r for r in engine.public_state()["results"]}
    assert res["p0"]["detail"].endswith(" s")
    assert res["p1"]["detail"].startswith("tapped ")
    assert res["p2"]["detail"] == "no tap"
    assert engine.lost_life_this_round[0] in ("p1", "p2")


def test_grey_round_clear_every_colour_and_never_a_grey():
    engine, _ = make(3)
    go(engine, "grey")
    tiles = engine.tiles["p0"]
    assert sum(1 for t in tiles if t["grey"]) == lt.LastTapEngine.GREY_COUNT
    for i, t in enumerate(tiles):
        if not t["grey"]:
            engine.handle_action("p0", "tap", {"tile": i})
    assert "p0" in engine.score_value and engine.score_value["p0"] < 5
    grey = next(i for i, t in enumerate(engine.tiles["p1"]) if t["grey"])
    engine.handle_action("p1", "tap", {"tile": grey})
    assert engine.detail["p1"] == "tapped a grey"
    # p2 clears a few, then time runs out.
    for i, t in enumerate(engine.tiles["p2"]):
        if not t["grey"] and len(engine.cleared["p2"]) < 3:
            engine.handle_action("p2", "tap", {"tile": i})
    finish(engine)
    res = [r["playerID"] for r in engine.public_state()["results"]]
    assert res[0] == "p0" and res[-1] == "p1"


def test_numbers_round_in_order_with_a_penalty_for_mistakes():
    engine, _ = make(2)
    go(engine, "numbers")

    def play(pid, mistakes):
        order = sorted(range(9), key=lambda i: engine.tiles[pid][i]["n"])
        for _ in range(mistakes):
            wrong = next(i for i in order if engine.tiles[pid][i]["n"] == 5)
            engine.handle_action(pid, "tap", {"tile": wrong})
        for i in order:
            engine.handle_action(pid, "tap", {"tile": i})

    play("p0", 0)
    play("p1", 3)
    assert engine.score_value["p1"] - engine.score_value["p0"] >= 3 * lt.LastTapEngine.NUMBERS_MISTAKE_SECONDS - 0.1
    engine.tick(0)
    assert engine.phase == "reveal"


def test_bad_tile_indexes_are_ignored():
    engine, _ = make(2)
    go(engine, "colour")
    for bad in (None, -1, 99, "3", True, 3.5):
        engine.handle_action("p0", "tap", {"tile": bad})
    engine.handle_action("p0", "tap", None)
    assert "p0" not in engine.score_value


def test_taps_before_the_round_starts_are_free_in_non_reaction_rounds():
    engine, _ = make(2)
    engine.kind = "pump"
    engine.phase = "arming"
    engine.go_at = time.time() + 30
    engine.handle_action("p0", "tap", {})
    assert engine.taps["p0"] == 0 and "p0" not in engine.score_value
    assert engine.private_state("p0")["canTap"] is False


def test_lives_last_several_rounds_and_the_survivor_wins():
    engine, _ = make(3)
    assert engine.max_lives == 3
    rounds = 0
    while not engine._finished and rounds < 40:
        go(engine, "pump")
        for _ in range(20):
            engine.last_tap_at["p0"] = 0.0
            engine.handle_action("p0", "tap", {})
        finish(engine)
        engine.phase_until = time.time() - 1
        engine.tick(0)
        rounds += 1
    assert engine._finished and engine.alive == ["p0"]
    # 2 losers x 3 lives each, one loses a life per round: at least 5 rounds.
    assert rounds >= 5
    res = engine.results()
    assert res[0]["playerID"] == "p0" and res[0]["rank"] == 1


def test_nobody_is_ever_eliminated_all_at_once():
    for n in (2, 3, 5, 8):
        engine, _ = make(n)
        for _ in range(40):
            if engine._finished:
                break
            go(engine, "colour")
            finish(engine)                       # nobody taps
            assert len(engine.alive) >= 1
            engine.phase_until = time.time() - 1
            engine.tick(0)
        assert len(engine.alive) >= 1


@pytest.mark.parametrize("kind", KINDS)
def test_state_has_what_the_clients_need(kind):
    engine, _ = make(3)
    go(engine, kind)
    pub, priv = engine.public_state(), engine.private_state("p0")
    for key in ("phase", "kind", "title", "howTo", "secondsLeft", "alivePlayerIDs", "players", "progress"):
        assert key in pub
    for key in ("phase", "kind", "isAlive", "canTap", "lives", "tiles", "myTaps"):
        assert key in priv
    assert pub["kind"] == priv["kind"] == kind
