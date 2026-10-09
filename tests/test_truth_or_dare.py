"""Truth or Dare: host-run setup, random non-repeating turns, lie punishment."""

import random

import pytest

from games import content_service as cs
from games.native_hub.engines import _truthdare as D
from games.native_hub.engines.truth_dare import TruthOrDareEngine
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


class _Null:
    def state(self): pass
    def room_update(self): pass
    def error(self, *a, **k): pass


def make(phones=1, seed=3):
    random.seed(seed)
    room = RoomRegistry().create("truth_or_dare")
    roster = [room.add_player(f"p{i}", f"Phone{i}", f"s{i}") for i in range(phones)]
    engine = TruthOrDareEngine(room, _Null())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, room


def host_id(room):
    return room.host().id


def begin(names="Asha, Ravi, Meera", level="family"):
    engine, room = make()
    h = host_id(room)
    engine.handle_action(h, "add_names", {"names": names})
    engine.handle_action(h, "set_level", {"level": level})
    engine.handle_action(h, "start_play", {})
    return engine, room, h


def test_registered_and_catalogued():
    assert ENGINES["truth_or_dare"] is TruthOrDareEngine
    from games.native_hub.rules import RULES
    assert "truth_or_dare" in RULES


def test_content_decks_exist_for_every_level():
    for kind in ("truth", "dare", "punish"):
        for level in D.LEVELS:
            assert len(cs.all_items(f"td_{kind}_{level}")) >= 10


def test_host_phone_adds_names_and_starts_alone():
    engine, room = make()
    h = host_id(room)
    assert engine.public_state()["phase"] == "setup"
    engine.handle_action(h, "start_play", {})          # only one name so far
    assert engine.phase == "setup"
    engine.handle_action(h, "add_names", {"names": "Asha, Ravi\nMeera,  asha "})
    names = [p["name"] for p in engine.public_state()["participants"]]
    assert names == ["Phone0", "Asha", "Ravi", "Meera"]   # duplicates dropped
    engine.handle_action(h, "start_play", {})
    assert engine.phase == "choose" and engine.current


def test_only_host_runs_setup_and_judging():
    engine, room = make(phones=2)
    guest = [p for p in room.players if not p.is_host][0]
    engine.handle_action(guest.id, "add_names", {"names": "Zed"})
    assert all(p["name"] != "Zed" for p in engine.public_state()["participants"])
    h = host_id(room)
    engine.handle_action(h, "start_play", {})
    engine.handle_action(guest.id, "end", {})
    assert not engine.is_over()
    engine.handle_action(h, "choose", {"kind": "truth"})
    before = {p["id"]: p["score"] for p in engine.participants}
    engine.handle_action(guest.id, "done", {})            # not the host
    assert {p["id"]: p["score"] for p in engine.participants} == before
    assert engine.phase == "prompt"


def test_players_own_phone_can_choose_for_themselves_only():
    engine, room = make(phones=3)
    h = host_id(room)
    engine.handle_action(h, "start_play", {})
    cur = engine.current
    stranger = next(p.id for p in room.players if p.id != cur)
    if stranger == h:
        stranger = next(p.id for p in room.players if p.id not in (cur, h))
    engine.handle_action(stranger, "choose", {"kind": "dare"})
    assert engine.phase == "choose"
    engine.handle_action(cur, "choose", {"kind": "dare"})
    assert engine.phase == "prompt" and engine.kind == "dare"


def test_everyone_goes_before_anyone_repeats_and_never_twice_in_a_row():
    engine, room, h = begin("A, B, C, D, E")
    order = []
    for _ in range(12):
        order.append(engine.current)
        engine.handle_action(h, "choose", {"kind": "truth"})
        engine.handle_action(h, "done", {})
    n = len(engine.participants)
    for lap in range(0, len(order) - n + 1, n):
        assert len(set(order[lap:lap + n])) == n
    assert all(a != b for a, b in zip(order, order[1:]))


def test_cards_never_repeat_in_a_long_game():
    engine, room, h = begin("A, B, C", level="adults")
    seen = []
    for i in range(60):
        engine.handle_action(h, "choose", {"kind": "truth" if i % 2 else "dare"})
        seen.append(engine.prompt)
        engine.handle_action(h, "done", {})
    assert len(set(seen)) == len(seen)


def test_new_game_in_same_room_does_not_replay_cards():
    random.seed(11)
    registry = RoomRegistry()
    room = registry.create("truth_or_dare")
    p = room.add_player("p0", "Host", "s0")
    room.state = RoomState.PLAYING
    first = []
    for _ in range(2):
        engine = TruthOrDareEngine(room, _Null())
        room.engine = engine
        engine.start([p])
        engine.handle_action("p0", "add_names", {"names": "A, B"})
        engine.handle_action("p0", "start_play", {})
        for _ in range(8):
            engine.handle_action("p0", "choose", {"kind": "truth"})
            first.append(engine.prompt)
            engine.handle_action("p0", "done", {})
    assert len(set(first)) == len(first)


def test_switch_allowed_once_per_turn():
    engine, room, h = begin()
    engine.handle_action(h, "choose", {"kind": "truth"})
    assert engine.public_state()["canSwitch"]
    engine.handle_action(h, "switch", {})
    assert engine.kind == "dare" and not engine.public_state()["canSwitch"]
    prompt = engine.prompt
    engine.handle_action(h, "switch", {})
    assert engine.kind == "dare" and engine.prompt == prompt


def test_caught_lying_leads_to_a_punishment_dare():
    engine, room, h = begin()
    engine.handle_action(h, "choose", {"kind": "truth"})
    engine.handle_action(h, "done", {})                      # +1 for someone
    cur = engine.current
    engine.handle_action(h, "choose", {"kind": "truth"})
    engine.handle_action(h, "caught", {})
    st = engine.public_state()
    assert st["phase"] == "punish" and st["kind"] == "punish" and st["currentID"] == cur
    assert st["prompt"] in D.PUNISHMENTS["family"]
    assert "Caught lying" in st["say"]["text"]
    assert not st["canSwitch"]
    engine.handle_action(h, "switch", {})                    # no escape
    assert engine.kind == "punish"
    engine.handle_action(h, "done", {})
    assert engine.phase == "choose" and engine.current != cur
    assert engine.last_result["outcome"] == "punished"


def test_dare_cannot_be_called_lying():
    engine, room, h = begin()
    engine.handle_action(h, "choose", {"kind": "dare"})
    engine.handle_action(h, "caught", {})
    assert engine.phase == "prompt"


def test_scoring_and_floor():
    engine, room, h = begin("A, B")
    pid = engine.current
    score = lambda: next(p["score"] for p in engine.participants if p["id"] == pid)
    engine.handle_action(h, "choose", {"kind": "dare"})
    engine.handle_action(h, "done", {})
    assert score() == 2
    # lie once and refuse the punishment: 2 - 1 - 2 floors at 0
    while engine.current != pid:
        engine.handle_action(h, "choose", {"kind": "truth"})
        engine.handle_action(h, "done", {})
    engine.handle_action(h, "choose", {"kind": "truth"})
    engine.handle_action(h, "caught", {})
    engine.handle_action(h, "skip", {})
    assert score() == 0


def test_levels_limit_the_cards():
    engine, room, h = begin(level="family")
    seen = set()
    for i in range(30):
        engine.handle_action(h, "choose", {"kind": "truth"})
        seen.add(engine.prompt)
        engine.handle_action(h, "done", {})
    assert seen <= set(D.TRUTHS["family"]) | set(cs.all_items("td_truth_family"))
    assert not seen & set(D.TRUTHS["adults"])


def test_tv_speaks_every_step_with_a_new_sequence_number():
    engine, room, h = begin()
    seqs = [engine.public_state()["say"]["seq"]]
    name = engine.public_state()["currentName"]
    assert name in engine.public_state()["say"]["text"]
    engine.handle_action(h, "choose", {"kind": "truth"})
    st = engine.public_state()
    assert st["prompt"] in st["say"]["text"] and st["say"]["seq"] > seqs[0]


def test_host_can_end_at_any_time_and_results_rank():
    engine, room, h = begin("A, B, C")
    engine.handle_action(h, "choose", {"kind": "dare"})
    engine.handle_action(h, "done", {})
    engine.handle_action(h, "end", {})
    assert engine.is_over()
    rows = engine.results()
    assert rows[0]["rank"] == 1 and rows[0]["score"] == 2
    engine2, room2 = make()
    engine2.handle_action(host_id(room2), "end", {})
    assert engine2.is_over()


def test_leaving_player_is_removed_and_turn_moves_on():
    engine, room, h = begin("A, B, C")
    cur = engine.current
    engine.on_player_leave(cur)
    assert all(p["id"] != cur for p in engine.participants)
    assert engine.phase == "choose" and engine.current != cur


def test_too_few_players_returns_to_setup():
    engine, room, h = begin("A")
    assert len(engine.participants) == 2           # the host phone plus A
    engine.on_player_leave(engine.participants[-1]["id"])
    assert len(engine.participants) == 1
    assert engine.phase == "setup"                 # waits for more names


def test_private_state_marks_host_and_turn():
    engine, room, h = begin()
    st = engine.private_state(h)
    assert st["isHost"] is True and "participants" in st
    engine.handle_action(h, "choose", {"kind": "truth"})
    assert engine.private_state("nobody")["isHost"] is False


def test_name_limits():
    engine, room = make()
    h = host_id(room)
    engine.handle_action(h, "add_names", {"names": ["x" * 80] + [f"N{i}" for i in range(30)]})
    assert len(engine.participants) == 12
    assert all(len(p["name"]) <= 20 for p in engine.participants)
    engine.handle_action(h, "add_names", {"names": [None, 5, {"a": 1}]})   # junk ignored
    assert len(engine.participants) == 12
