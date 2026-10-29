"""What a game's score means: results say "Winner", "Won", "42 chips" or nothing
instead of "1 pts" or "1000 pts", and a game with no winner does not hand out
Game Night placings."""

import pytest

from games import game_night
from games.native_hub import scoring
from games.native_hub.broadcast import final_results
from games.native_hub.registry import ENGINES
from tests.test_one_stop import make_room


def test_points_is_the_default():
    assert scoring.label("trivia", 12) == "12 pts"
    assert scoring.label(None, 0) == "0 pts"
    assert scoring.kind("not-a-game") == scoring.POINTS


def test_winner_only_games_name_the_winner_and_hide_the_rest():
    assert scoring.label("chess", 1) == "Winner"
    assert scoring.label("connect4", 0) == ""


def test_side_and_coop_games_say_won_or_lost():
    assert scoring.label("mafia", 1000) == "Won"
    assert scoring.label("mafia", 0) == "Lost"
    assert scoring.label("defuse", 1000) == "Won"
    assert scoring.label("heist_escape", 0) == "Lost"


def test_games_with_no_winner_show_no_score():
    for game_id in ("truth_or_dare", "would_rather", "most_likely_to", "never_have_i_ever"):
        assert scoring.label(game_id, 7) == ""
        assert scoring.is_social(game_id)


def test_unit_games_say_what_they_count():
    assert scoring.label("poker", 450) == "450 chips"
    assert scoring.label("snake_ladder", 87) == "square 87"
    assert scoring.label("memory", 6) == "6 pairs"


@pytest.mark.parametrize("game_id", sorted(scoring.SCORING))
def test_every_scored_game_is_a_real_game(game_id):
    assert game_id in ENGINES


def test_results_rows_carry_the_label():
    room = make_room("chess", ids=("a", "b"))
    rows = final_results(room, [{"playerID": "a", "score": 1, "rank": 1},
                                {"playerID": "b", "score": 0, "rank": 2}])
    assert [r["scoreLabel"] for r in rows] == ["Winner", ""]
    room = make_room("trivia", ids=("a", "b"))
    rows = final_results(room, [{"playerID": "a", "score": 30, "rank": 1},
                                {"playerID": "b", "score": 10, "rank": 2}])
    assert [r["scoreLabel"] for r in rows] == ["30 pts", "10 pts"]


def night_points(game_id, scores):
    room = make_room(game_id, ids=tuple(scores))
    game_night.start(room, [game_id, "trivia"])
    rows = sorted(scores.items(), key=lambda kv: -kv[1])
    ranked = []
    for i, (pid, s) in enumerate(rows):
        tied = i and s == rows[i - 1][1]          # equal scores share a rank
        ranked.append({"playerID": pid, "name": pid.upper(), "score": s,
                       "rank": ranked[-1]["rank"] if tied else i + 1})
    game_night.record_game(room, ranked)
    return {r["playerID"]: r["points"] for r in game_night.standings(room)}


def test_a_game_with_no_winner_gives_everyone_the_same_night_point():
    assert night_points("truth_or_dare", {"a": 9, "b": 4, "c": 0}) == {"a": 1, "b": 1, "c": 1}


def test_a_lost_coop_game_gives_everyone_the_same_night_point():
    assert night_points("defuse", {"a": 0, "b": 0, "c": 0}) == {"a": 1, "b": 1, "c": 1}


def test_a_won_coop_game_and_a_normal_game_still_place_players():
    assert night_points("defuse", {"a": 1000, "b": 1000, "c": 1000}) == {"a": 10, "b": 10, "c": 10}
    assert night_points("trivia", {"a": 30, "b": 20, "c": 10}) == {"a": 10, "b": 7, "c": 5}
