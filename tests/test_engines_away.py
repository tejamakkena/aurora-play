"""Every live engine keeps working when a player drops mid-game, and the
dropped seat still reads (and plays) normally if they come back."""

import time

import pytest

from games.native_hub.registry import ENGINES
from utils.room_manager import Room, RoomState

RETIRED = {
    "chess", "pong", "air_hockey", "carrom", "blast_runners", "neon_snake",
    "twenty48", "brick_breaker", "simon_says", "memory", "digit_guess",
    "hot_grid", "stock_panic", "kbc", "story_chain",
}
LIVE = sorted(set(ENGINES) - RETIRED)


def seated(game_id, extra=0):
    cls = ENGINES[game_id]
    n = min(cls.max_players, max(cls.min_players, 4) + extra)
    room = Room(code="ABCDEF", game_id=game_id)
    for i in range(n):
        room.add_player(f"p{i}", f"Player{i}", f"s{i}")
    room.state = RoomState.PLAYING
    engine = cls(room, None)
    engine.start(list(room.players))
    return room, engine


def drop(room, pid):
    p = room.player(pid)
    p.connected, p.sid, p.disconnected_at = False, None, time.time() - 30
    room.reassign_host()


@pytest.mark.parametrize("game_id", LIVE)
def test_engine_survives_a_dropped_player(game_id):
    room, engine = seated(game_id)
    drop(room, "p1")
    engine.on_player_leave("p1")
    for _ in range(5):
        engine.tick(0.5)
    engine.public_state()
    for p in room.players:
        assert isinstance(engine.private_state(p.id), dict)
    engine.is_over()
    engine.results()


@pytest.mark.parametrize("game_id", LIVE)
def test_dropped_player_keeps_their_name(game_id):
    room, engine = seated(game_id)
    drop(room, "p0")
    assert engine.player_name("p0") == "Player0"
    # and can come back
    p = room.player("p0")
    p.connected, p.sid, p.disconnected_at = True, "s9", None
    engine.on_player_join(p)
    assert isinstance(engine.private_state("p0"), dict)


@pytest.mark.parametrize("game_id", LIVE)
def test_everyone_dropping_does_not_crash_the_clock(game_id):
    room, engine = seated(game_id)
    for p in list(room.players):
        drop(room, p.id)
    for _ in range(8):
        engine.tick(1.0)
    engine.public_state()
