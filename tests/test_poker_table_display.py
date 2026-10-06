"""Display-only keys PokerEngine adds for the TV table (hand names, best
five, button/blind seats, last action). They never affect betting."""

from games.native_hub.engines.legacy_cards import _best_five, _best_hand, _hand_name
from tests.test_legacy_engines import act, latest, open_room, server, start_and_settle, tv  # noqa: F401


def name_of(cards):
    return _hand_name(_best_hand(cards))


def test_hand_names_read_like_a_broadcast():
    assert name_of(["K♠", "K♥", "7♦", "7♣", "K♦", "2♠", "3♥"]) \
        == "Full house, Kings over 7s"
    assert name_of(["A♠", "K♠", "Q♠", "J♠", "10♠", "2♥", "3♥"]) == "Royal flush"
    assert name_of(["A♠", "2♥", "5♦", "4♣", "3♦", "9♠", "J♥"]) \
        == "Straight, Five high"
    assert name_of(["Q♠", "Q♥", "9♦", "9♣", "3♦", "2♠", "7♥"]) \
        == "Two pair, Queens and 9s"
    assert name_of(["A♠", "2♥", "8♦", "4♣", "3♦", "9♠", "J♥"]) == "Ace high"


def test_best_five_is_the_scoring_hand():
    cards = ["K♠", "K♥", "7♦", "7♣", "K♦", "2♠", "3♥"]
    best = _best_five(cards)
    assert len(best) == 5
    assert sorted(best) == sorted(["K♠", "K♥", "K♦", "7♦", "7♣"])


def test_public_state_carries_table_markers_and_last_action(server, tv):  # noqa: F811
    app, socketio = server
    code, phones = open_room(app, socketio, tv, "poker", players=3)
    start_and_settle(socketio, tv, code)
    board = latest(tv, "game_state")["boardState"]
    ids = {p["id"] for p in board["players"]}
    assert board["dealerID"] in ids
    assert board["smallBlindID"] in ids and board["bigBlindID"] in ids
    assert board["currentBet"] == board["bigBlind"]
    assert board["turnSeconds"] > 0
    assert board["lastAction"] is None

    current = next(p["id"] for p in board["players"] if p["isCurrentTurn"])
    actor = phones[int(current[-1])]
    private = latest(actor, "private_state")["privateData"]
    assert {"myBet", "currentBet", "pot"} <= set(private)

    act(socketio, actor, code, current, "fold", {})
    after = latest(tv, "game_state")["boardState"]
    assert after["lastAction"]["playerID"] == current
    assert after["lastAction"]["action"] == "fold"
    assert after["lastAction"]["seq"] == 1
