"""Poker raise discipline and the away-player rule, at engine level."""

import time

from games.native_hub.engines.legacy_cards import PokerEngine
from utils.room_manager import Room, RoomState


def table(n=3):
    room = Room(code="ABCDEF", game_id="poker")
    for i in range(n):
        room.add_player(f"p{i}", f"P{i}", f"s{i}")
    room.state = RoomState.PLAYING
    engine = PokerEngine(room, None)
    engine.start(list(room.players))
    return room, engine


def turn(engine):
    return engine.current_player_id()


def test_a_raise_must_add_at_least_the_big_blind():
    _, e = table()
    pid = turn(e)
    e.handle_action(pid, "bet", {"amount": e.current_bet + 1})
    assert e.current_bet == 2 * e.BIG_BLIND


def test_a_raise_must_match_the_previous_raise():
    _, e = table()
    first = turn(e)
    e.handle_action(first, "bet", {"amount": 100})       # raise to 100: +80
    assert e.current_bet == 100 and e.last_raise == 80
    second = turn(e)
    e.handle_action(second, "bet", {"amount": 110})      # asks for +10: lifted
    assert e.current_bet == 180


def test_raises_are_capped_per_street():
    _, e = table(3)
    for _ in range(e.MAX_RAISES):
        e.handle_action(turn(e), "bet", {"amount": e.current_bet + e.last_raise})
    assert e.raises == e.MAX_RAISES
    before = e.current_bet
    pid = turn(e)
    e.handle_action(pid, "bet", {"amount": before * 5})   # becomes a call
    assert e.current_bet == before
    assert e.private_state(turn(e) or pid)["canRaise"] is False


def test_the_cap_resets_on_the_next_street():
    _, e = table(2)
    for _ in range(e.MAX_RAISES):
        e.handle_action(turn(e), "bet", {"amount": e.current_bet + e.last_raise})
    e.handle_action(turn(e), "call", {})
    assert e.phase == "flop" and e.raises == 0 and e.last_raise == e.BIG_BLIND


def test_all_in_for_less_than_a_raise_is_still_allowed():
    _, e = table(2)
    pid = turn(e)
    e.chips[pid] = 50
    e.handle_action(pid, "bet", {"amount": 5000})
    assert e.chips[pid] == 0 and pid in e.all_in


def test_an_away_player_on_turn_is_folded_after_a_short_wait():
    room, e = table(3)
    pid = turn(e)
    player = room.player(pid)
    player.connected, player.sid = False, None
    player.disconnected_at = time.time()
    e.tick(0.1)
    assert pid not in e.folded            # not yet: it may be a tab switch
    player.disconnected_at = time.time() - e.AWAY_SKIP_SECONDS - 1
    e.tick(0.1)
    assert pid in e.folded


def test_an_away_player_keeps_name_and_cards_for_when_they_return():
    room, e = table(3)
    pid = "p1"
    player = room.player(pid)
    player.connected, player.sid, player.disconnected_at = False, None, time.time()
    assert e.player_name(pid) == "P1"
    assert len(e.private_state(pid)["hand"]) in (0, 2)
