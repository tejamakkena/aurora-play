"""Contract test: NeonSnakeEngine.private_state exposes `isOut` (inverse of
`alive`), which the phone DPad controller reads for its "You're out" subtitle.
"""

import random

from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make_neon_snake(players=2):
    random.seed(7)
    cls = ENGINES["neon_snake"]
    registry = RoomRegistry()
    room = registry.create("neon_snake")
    count = min(max(cls.min_players, players), cls.max_players)
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(count)]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def test_isout_false_while_alive():
    engine, roster = make_neon_snake()
    pid = roster[0].id if hasattr(roster[0], "id") else roster[0]["id"]
    state = engine.private_state(pid)
    assert state["alive"] is True
    assert state["isOut"] is False


def test_isout_true_when_dead():
    engine, roster = make_neon_snake()
    pid = roster[0].id if hasattr(roster[0], "id") else roster[0]["id"]
    engine.snakes[pid]["alive"] = False
    state = engine.private_state(pid)
    assert state["alive"] is False
    assert state["isOut"] is True
