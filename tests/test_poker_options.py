"""Poker table options picked on the TV: hands, chips, re-buys, ending."""

import time

from games.native_hub import options
from games.native_hub.engines.legacy_cards import PokerEngine
from utils.room_manager import Room, RoomState


def table(n=3, **picked):
    room = Room(code="ABCDEF", game_id="poker")
    room.options.update(picked)
    for i in range(n):
        room.add_player(f"p{i}", f"P{i}", f"s{i}")
    room.state = RoomState.PLAYING
    engine = PokerEngine(room, None)
    room.engine = engine
    engine.start(list(room.players))
    return room, engine


def finish_hand(engine, winner="p0"):
    """End the current hand by everyone else folding."""
    for _ in range(20):
        if engine.next_hand_at or engine._finished:
            return
        pid = engine.current_player_id()
        if pid == winner:
            engine.handle_action(pid, "check" if engine.current_bet == engine.contrib[pid] else "call", {})
        else:
            engine.handle_action(pid, "fold", {})


def next_hand(engine):
    engine.next_hand_at = time.time() - 1
    engine.tick(0)


def test_menu_defaults_and_validation():
    room = Room(code="ABCDEF", game_id="poker")
    assert options.get(room, "hands") == "20"
    assert options.valid("poker", "hands", "0") and not options.valid("poker", "hands", "7")
    assert not options.valid("poker", "nope", "x")
    room.options["hands"] = "garbage"
    assert options.get(room, "hands") == "20"          # a bad pick falls back
    keys = [o["key"] for o in room.to_json()["options"]]
    assert keys == ["hands", "stack", "rebuys"]
    assert Room(code="ABCDEF", game_id="herd").to_json()["options"] == []


def test_default_table_plays_twenty_hands():
    _, e = table()
    assert e.max_hands == 20 and e.stack == 1000 and e.rebuys is False
    assert e.public_state()["maxHands"] == 20 and e.public_state()["unlimited"] is False


def test_stack_scales_the_blinds():
    _, e = table(stack="5000")
    assert sum(e.chips[p] + e.contrib[p] for p in e.order) == 3 * 5000
    assert e.BIG_BLIND == 100 and e.SMALL_BLIND == 50
    assert e.private_state("p0")["minBet"] >= 100


def test_a_hand_limit_ends_the_game_and_unlimited_does_not():
    _, e = table(hands="10")
    for _ in range(30):
        if e._finished:
            break
        finish_hand(e)
        next_hand(e)
    assert e._finished and e.hand_number == 10
    _, u = table(hands="0")
    for _ in range(25):
        finish_hand(u)
        next_hand(u)
    assert not u._finished and u.hand_number > 20
    assert u.public_state()["unlimited"] is True


def bust(e, pid):
    """Make `pid` lose everything in the hand in play."""
    e.chips[pid] = 0
    e.chips["p0" if pid != "p0" else "p1"] += e.stack


def test_rebuy_adds_a_stack_and_is_counted_in_the_net_result():
    _, e = table(3, rebuys="on", hands="0")
    finish_hand(e)
    e.chips["p2"] = 0
    e._sync_scores()
    assert e.private_state("p2")["canRebuy"] is True
    before = e.chips["p0"]
    e.handle_action("p2", "rebuy", {})
    assert e.chips["p2"] == e.stack and e.buy_ins["p2"] == 2
    assert e.chips["p0"] == before
    assert e.scores["p2"] == -e.stack                 # holds one stack, paid for two
    assert e.private_state("p2")["canRebuy"] is False   # not below a full stack any more


def test_rebuy_is_refused_when_off_or_mid_hand_or_when_not_short():
    _, off = table(3)
    finish_hand(off)
    off.chips["p2"] = 0
    off.handle_action("p2", "rebuy", {})
    assert off.chips["p2"] == 0
    _, e = table(3, rebuys="on")
    e.chips["p2"] = 0
    e.handle_action("p2", "rebuy", {})                # a hand is in play
    assert e.chips["p2"] == 0
    finish_hand(e)
    e.chips["p0"] = e.stack          # a full stack cannot buy another
    e.handle_action("p0", "rebuy", {})
    assert e.buy_ins["p0"] == 1


def test_a_broke_player_gets_a_longer_pause_and_the_game_goes_on_after_a_rebuy():
    _, e = table(2, rebuys="on", hands="0")
    # p1 loses everything in a hand: p0 wins the whole pot.
    e.chips["p0"] += e.chips["p1"] + e.contrib["p1"]
    e.pot += e.chips["p1"]
    e.contrib["p1"] += e.chips["p1"]
    e.chips["p1"] = 0
    e._award("p0")
    assert e.game_over_pending is False               # re-buys keep the table alive
    assert e.next_hand_at - time.time() > 10
    e.handle_action("p1", "rebuy", {})
    assert e.next_hand_at - time.time() <= 3.5        # everyone is back: no need to wait
    next_hand(e)
    assert not e._finished and e.hand_number == 2


def test_without_rebuys_a_busted_table_ends():
    _, e = table(2, hands="0")
    e.chips["p0"] += e.chips["p1"] + e.contrib["p1"]
    e.pot += e.chips["p1"]
    e.chips["p1"] = 0
    e._award("p0")
    assert e.game_over_pending is True


def test_everyone_voting_end_finishes_after_the_hand():
    _, e = table(3, hands="0")
    e.handle_action("p0", "vote_end", {})
    e.handle_action("p1", "vote_end", {})
    assert e.public_state()["endVotes"] == 2 and e.public_state()["endVotesNeeded"] == 3
    e.handle_action("p1", "vote_end", {})            # changed their mind
    e.handle_action("p1", "vote_end", {})
    e.handle_action("p2", "vote_end", {})
    assert e.private_state("p2")["votedEnd"] is True
    assert not e._finished                           # the hand in play still finishes
    finish_hand(e)
    assert e.game_over_pending is True
    next_hand(e)
    assert e._finished


def test_voting_end_between_hands_ends_quickly_and_a_lone_vote_does_nothing():
    _, e = table(3, hands="0")
    finish_hand(e)
    e.handle_action("p0", "vote_end", {})
    assert e.game_over_pending is False
    e.handle_action("p1", "vote_end", {})
    e.handle_action("p2", "vote_end", {})
    assert e.game_over_pending is True and e.next_hand_at - time.time() <= 1.5


def test_final_ranking_is_by_net_result_after_rebuys():
    _, e = table(2, rebuys="on", hands="0")
    finish_hand(e, winner="p0")
    e.chips["p1"] = 0
    e.handle_action("p1", "rebuy", {})
    # p1 bought in twice (spent 2 stacks) and holds one: net -stack.
    assert e.buy_ins["p1"] == 2 and e._net("p1") == e.chips["p1"] - 2 * e.stack
    e.chips["p0"], e.chips["p1"] = e.stack + 300, e.stack - 300 + e.stack
    e._sync_scores()
    e.handle_action("p0", "vote_end", {})
    e.handle_action("p1", "vote_end", {})
    next_hand(e)
    next_hand(e)
    assert e._finished
    res = e.results()
    assert res[0]["playerID"] == "p0"


def test_sit_out_lets_the_table_move_on():
    _, e = table(3, rebuys="on", hands="0")
    finish_hand(e)
    e.chips["p2"] = 0
    e._sync_scores()
    e.handle_action("p2", "sit_out", {})
    assert e.next_hand_at - time.time() <= 2.5
    next_hand(e)
    assert "p2" not in e.hands and "p2" in e.folded
