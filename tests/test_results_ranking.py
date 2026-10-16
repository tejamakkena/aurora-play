"""End-of-game ranking: the results screen shows the game's own ranking.

Reported: in Battleship the host was always listed first. Every results
screen used to sort the seats by their running ``score``, and games that only
record a winner (or keep their own score) left every seat at 0, so the sort
kept join order and the host -- first to join -- came out on top.

Now ``broadcast.final_results`` stores the engine's ranking on the room and
every screen shows it as-is. These tests pin that down, plus the per-game
rankings fixed in the same audit.
"""

import time

import pytest

from games.native_hub.broadcast import final_results
from games.native_hub.registry import ENGINES
from tests.test_native_engines import make
from utils.room_manager import RoomState


def ranks(rows):
    return [(r["playerID"], r["rank"]) for r in rows]


# ---- the plumbing -----------------------------------------------------------

def test_equal_scores_share_a_rank_instead_of_going_to_the_host():
    engine, _ = make("herd", players=4)
    rows = engine.ranked_results({"p0": 5, "p1": 9, "p2": 5, "p3": 1})
    assert ranks(rows) == [("p1", 1), ("p0", 2), ("p2", 2), ("p3", 4)]


@pytest.mark.parametrize("game_id", sorted(ENGINES))
def test_nobody_is_ahead_before_anything_happens(game_id):
    """A game that ends before anyone scores is a tie for everyone: never a
    win for the first seat (Heist's guard, chosen at random, is the one game
    whose rules hand it the win when nothing happens)."""
    engine, roster = make(game_id, players=3)
    rows = final_results(engine.room, engine.results())
    assert sorted(r["playerID"] for r in rows) == sorted(p.id for p in roster)
    if game_id != "heist":
        assert {r["rank"] for r in rows} == {1}, ranks(rows)


def test_final_results_are_stored_on_the_room_and_sent_only_on_results():
    engine, roster = make("battleship", players=2)
    room = engine.room
    guest = roster[1].id
    engine.finish(winner=guest)
    room.results = final_results(room, engine.results())
    room.state = RoomState.PLAYING
    assert room.to_json()["results"] is None
    room.state = RoomState.RESULTS
    sent = room.to_json()["results"]
    assert sent[0]["playerID"] == guest and sent[0]["rank"] == 1
    assert sent[1]["rank"] == 2


def test_final_results_fill_in_missing_seats_and_sync_scores():
    engine, roster = make("herd", players=3)
    rows = final_results(engine.room, [
        {"playerID": "p2", "name": "P2", "score": 7, "rank": 1},
        {"playerID": "p2", "name": "dupe", "score": 1, "rank": 2},
        {"playerID": "p0", "name": "P0", "score": "3", "rank": "x"},
    ])
    assert [r["playerID"] for r in rows] == ["p2", "p0", "p1"]
    assert [r["rank"] for r in rows] == [1, 2, 3]
    assert engine.room.player("p2").score == 7 and engine.room.player("p0").score == 3


def test_a_game_ended_by_players_leaving_ranks_the_ones_who_stayed_first():
    engine, roster = make("battleship", players=2)
    room = engine.room
    host, guest = roster[0].id, roster[1].id
    engine.scores = {host: 5, guest: 2}            # host was ahead, then left
    room.player(host).connected = False
    rows = final_results(room, engine.results(), forfeit=True)
    assert ranks(rows) == [(guest, 1), (host, 2)]
    # Without a forfeit (a normal end) the points decide.
    rows = final_results(room, engine.results())
    assert ranks(rows) == [(host, 1), (guest, 2)]


# ---- per game ---------------------------------------------------------------

def test_battleship_winner_first_even_when_the_host_hit_more():
    engine, roster = make("battleship", players=2)
    host, guest = roster[0].id, roster[1].id
    engine.scores = {host: 9, guest: 14}
    engine.finish(winner=guest)
    rows = engine.results()
    assert ranks(rows) == [(guest, 1), (host, 2)]
    assert rows[0]["detail"].endswith("ships sunk")


def test_snakes_and_ladders_rank_the_race():
    engine, roster = make("snake_ladder", players=3)
    a, b, c = (p.id for p in roster)
    engine.positions = {a: 12, b: 88, c: 40}
    engine.scores = {a: 12, b: 88, c: 40}
    assert ranks(engine.results()) == [(b, 1), (c, 2), (a, 3)]


def test_ludo_ranks_progress_not_captures():
    engine, roster = make("ludo", players=3)
    a, b, c = (p.id for p in roster)
    engine.tokens[a] = [105, 105, 105, -1]          # three home
    engine.tokens[b] = [3, -1, -1, -1]
    engine.tokens[c] = [20, 10, -1, -1]
    engine.scores = {a: 0, b: 2, c: 0}               # b captured twice
    rows = engine.results()
    assert [r["playerID"] for r in rows] == [a, c, b]
    assert rows[0]["detail"].startswith("3/4 home")


def test_last_tap_ranks_by_how_long_you_lasted():
    engine, roster = make("last_tap", players=3)
    a, b, c = (p.id for p in roster)
    engine.alive = [c]
    engine.out_round = {a: 2, b: 5}
    engine.room.player(a).score = 9                  # out first, most points
    engine.room.player(b).score = 3
    engine.room.player(c).score = 4
    rows = engine.results()
    assert [r["playerID"] for r in rows] == [c, b, a]
    assert rows[0]["detail"] == "Last one standing"
    assert rows[2]["detail"] == "Out in round 2"


def test_poker_shared_top_is_a_shared_win():
    engine, roster = make("poker", players=3)
    a, b, c = (p.id for p in roster)
    engine.chips = {a: engine.stack + 250, b: engine.stack + 250, c: engine.stack - 500}
    engine._finish_game()
    assert engine.winner is None
    rows = engine.results()
    assert sorted(r["rank"] for r in rows) == [1, 1, 3]


def test_simon_says_the_last_one_in_wins():
    engine, roster = make("simon_says", players=3)
    a, b, c = (p.id for p in roster)
    engine.room.player(a).score = 90                 # out first with most points
    engine.out_order = [a, c]
    engine.order = [b]
    rows = engine.results()
    assert [r["playerID"] for r in rows] == [b, c, a]


def test_simon_says_a_phone_gone_on_its_turn_is_out():
    engine, roster = make("simon_says", players=3)
    pid = engine.current_player()
    player = engine.room.player(pid)
    player.connected, player.disconnected_at = False, time.time() - 60
    engine.tick(0.1)
    assert pid not in engine.order and pid in engine.out_order


def test_code_breaker_losers_rank_by_their_best_guess():
    engine, roster = make("digit_guess", players=3)
    a, b, c = (p.id for p in roster)
    engine.secret = "1234"
    engine.handle_action(a, "guess", {"code": "5678"})
    engine.handle_action(b, "guess", {"code": "1243"})   # 2 right, 2 close
    engine.handle_action(c, "guess", {"code": "1234"})   # solved
    rows = engine.results()
    assert [r["playerID"] for r in rows] == [c, b, a]
    assert rows[0]["detail"] == "Cracked it in 1"


def test_teen_patti_equal_hands_split_the_pot():
    engine, roster = make("teen_patti", players=2)
    a, b = (p.id for p in roster)
    engine.hands = {a: [{"rank": r, "suit": "♠"} for r in (14, 13, 12)],
                    b: [{"rank": r, "suit": "♥"} for r in (14, 13, 12)]}
    before = {pid: engine.chips[pid] for pid in (a, b)}
    pot = engine.pot
    engine._showdown()
    assert engine.winner is None
    assert engine.chips[a] - before[a] + engine.chips[b] - before[b] == pot
    assert {r["rank"] for r in engine.results()} == {1}


def test_teen_patti_abandoned_hand_returns_the_pot():
    engine, roster = make("teen_patti", players=2)
    total = sum(engine.chips.values()) + engine.pot
    rows = engine.results()
    assert sum(r["score"] for r in rows) == total


def test_chess_score_is_material_and_stalemate_is_a_draw():
    engine, roster = make("chess", players=2)
    white = next(p for p, c in engine.piece_color.items() if c == "white")
    black = next(p for p, c in engine.piece_color.items() if c == "black")
    engine.captured = {"white": ["♛", "♟"], "black": ["♙"]}
    rows = engine.results()
    assert rows[0]["playerID"] == white and rows[0]["score"] == 10
    engine.draw = True
    engine.finish(winner=None)
    assert {r["rank"] for r in engine.results()} == {1}
    assert black in {r["playerID"] for r in engine.results()}


def test_story_chain_counts_votes_cast_before_an_early_end():
    engine, roster = make("story_chain", players=3)
    a, b, c = (p.id for p in roster)
    engine.phase = "vote"
    engine.votes = {a: b, c: b}
    rows = engine.results()
    assert rows[0]["playerID"] == b and rows[0]["detail"].startswith("Funniest")


def test_kbc_players_without_a_turn_rank_after_everyone_who_played():
    engine, roster = make("kbc", players=4)
    engine.order = [p.id for p in roster[:2]]
    engine.banked_by = {roster[0].id: 0, roster[1].id: 1000, roster[2].id: 0, roster[3].id: 0}
    rows = engine.results()
    assert ranks(rows)[:2] == [(roster[1].id, 1), (roster[0].id, 2)]
    assert [r["rank"] for r in rows[2:]] == [3, 3]
    assert rows[3]["detail"] == "No turn in the hot seat"


def test_charades_gives_everyone_the_same_number_of_turns():
    for players in (3, 4, 5, 7):
        engine, roster = make("bollywood_charades", players=players)
        assert engine.total_rounds % len(roster) == 0 and engine.total_rounds >= 6


def test_trivia_equal_standing_shares_a_rank():
    engine, roster = make("trivia", players=3)
    a, b, c = (p.id for p in roster)
    engine.winner_id = None
    engine.scores = {a: 300, b: 300, c: 100}
    engine.rungs = {a: 2, b: 2, c: 1}
    assert sorted(r["rank"] for r in engine.results()) == [1, 1, 3]
    assert engine._leader_by_score() is None
