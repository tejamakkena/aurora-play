"""Bot players: policies, room wiring, and act-once-per-phase behavior."""

import time

import pytest

from games.native_hub import bots
from games.native_hub.bots import maybe_bot_action
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make_room(game_id, n_humans=3, n_bots=1):
    registry = RoomRegistry()
    room = registry.create(game_id)
    humans = [room.add_player(f"h{i}", f"Human{i}", f"s{i}") for i in range(n_humans)]
    bot_players = [room.add_bot() for _ in range(n_bots)]
    return room, humans, bot_players


def start_engine(room):
    cls = ENGINES[room.game_id]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    engine.start(list(room.players))
    return engine


# ---- room wiring -----------------------------------------------------------

def test_add_bot_creates_named_bot_player():
    room, _, _ = make_room("bluff_it", n_humans=2, n_bots=0)
    bot = room.add_bot()
    assert bot.is_bot
    assert bot.sid is None
    assert not bot.is_host
    assert bot.id.startswith("bot-")
    assert bot.name  # got a display name


def test_bot_names_are_unique_per_room():
    room, _, _ = make_room("bluff_it", n_humans=1, n_bots=0)
    names = {room.add_bot().name for _ in range(5)}
    assert len(names) == 5


def test_bots_never_become_host():
    room, humans, _ = make_room("bluff_it", n_humans=1, n_bots=2)
    assert humans[0].is_host
    room.reassign_host()
    assert humans[0].is_host
    assert not any(b.is_host for b in room.players if b.is_bot)


def test_remove_bot_refuses_humans():
    room, humans, _ = make_room("bluff_it", n_humans=1, n_bots=1)
    assert room.remove_bot(humans[0].id) is None
    assert room.remove_bot("bot-nope") is None
    bot = next(p for p in room.players if p.is_bot)
    assert room.remove_bot(bot.id) is bot


def test_room_with_only_bots_is_empty():
    room, humans, _ = make_room("bluff_it", n_humans=1, n_bots=1)
    room.remove_player(humans[0].id)
    assert room.is_empty()


def test_player_json_marks_bots():
    room, _, bots_ = make_room("bluff_it", n_humans=1, n_bots=1)
    assert bots_[0].to_json()["isBot"] is True


# ---- policy behavior --------------------------------------------------------

def test_bluff_it_bot_submits_lie_then_picks():
    room, _, bots_ = make_room("bluff_it", n_humans=3, n_bots=1)
    engine = start_engine(room)
    bot = bots_[0]
    assert engine.phase == "write"

    assert maybe_bot_action(engine, bot) is None  # schedules thinking delay
    bot.bot_act_at = 0.0
    act = maybe_bot_action(engine, bot)
    assert act is not None
    verb, payload = act
    assert verb == "submit_lie" and payload["text"]
    engine.handle_action(bot.id, verb, payload)
    assert bot.id in engine.submissions

    # Acts only once per phase.
    assert maybe_bot_action(engine, bot) is None

    engine.advance()  # write -> pick
    assert maybe_bot_action(engine, bot) is None  # new phase: reschedules
    bot.bot_act_at = 0.0
    act = maybe_bot_action(engine, bot)
    assert act is not None
    assert act[0] == "pick"


def test_most_likely_to_bot_votes_for_other():
    room, _, bots_ = make_room("most_likely_to", n_humans=3, n_bots=1)
    engine = start_engine(room)
    bot = bots_[0]
    assert maybe_bot_action(engine, bot) is None  # schedules thinking delay
    bot.bot_act_at = 0.0
    act = maybe_bot_action(engine, bot)
    assert act is not None
    verb, payload = act
    assert verb == "vote"
    assert payload["targetID"] != bot.id
    assert room.player(payload["targetID"]) is not None


def test_bot_thinks_before_acting():
    room, _, bots_ = make_room("bluff_it", n_humans=3, n_bots=1)
    engine = start_engine(room)
    bot = bots_[0]
    # First sight of a phase only schedules; no immediate action.
    assert maybe_bot_action(engine, bot) is None
    assert bot.bot_act_at > time.time()
    # ...until the thinking delay passes.
    bot.bot_act_at = time.time() - 1
    assert maybe_bot_action(engine, bot) is not None


def test_unknown_game_bot_abstains():
    room, _, bots_ = make_room("bluff_it", n_humans=3, n_bots=1)
    engine = start_engine(room)
    engine.game_id = "not_a_real_game"
    bot = bots_[0]
    bot.bot_phase_key = "definitely-not-a-phase"
    bot.bot_act_at = 0.0
    assert maybe_bot_action(engine, bot) is None


def test_bot_error_never_raises():
    room, _, bots_ = make_room("bluff_it", n_humans=3, n_bots=1)
    assert maybe_bot_action(None, bots_[0]) is None
