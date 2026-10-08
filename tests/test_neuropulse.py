"""NeuroPulse: the daily ten-step workout, its ELO engine and its HTTP."""

import datetime as dt
import random

import pytest

from app import create_app
from games import neuropulse as np

DEV = "dev-neuro-1"
OTHER = "dev-neuro-2"


# --------------------------------------------------------------------------
# rating engine
# --------------------------------------------------------------------------

class TestElo:
    def test_expected_score_is_even_at_equal_rating(self):
        assert np.expected_score(1200, 1200) == pytest.approx(0.5)
        assert np.expected_score(1400, 1200) > 0.7
        assert np.expected_score(1000, 1400) < 0.15

    def test_k_factor_shrinks_as_a_discipline_settles(self):
        assert np.k_factor(0) == 40
        assert np.k_factor(9) == 40
        assert np.k_factor(10) == 24
        assert np.k_factor(29) == 24
        assert np.k_factor(30) == 16
        assert np.k_factor(500) == 16

    def test_right_answer_raises_and_wrong_lowers(self):
        up = np.rate(1200, 50, 1200, True, 5000, 10000)
        down = np.rate(1200, 50, 1200, False, 5000, 10000)
        assert up > 1200 > down

    def test_a_hard_win_moves_more_than_an_easy_one(self):
        hard = np.rate(1200, 50, 1600, True, 9000, 10000)
        easy = np.rate(1200, 50, 800, True, 9000, 10000)
        assert hard - 1200 > easy - 1200 > 0

    def test_fast_answers_earn_a_bonus_and_slow_ones_less(self):
        fast = np.rate(1200, 50, 1200, True, 3000, 10000)
        normal = np.rate(1200, 50, 1200, True, 8000, 10000)
        slow = np.rate(1200, 50, 1200, True, 14000, 10000)
        assert fast > normal > slow > 1200

    def test_speed_never_softens_a_wrong_answer(self):
        quick = np.rate(1200, 50, 1200, False, 500, 10000)
        slow = np.rate(1200, 50, 1200, False, 30000, 10000)
        assert quick == slow < 1200

    def test_ratings_stay_inside_their_bounds(self):
        assert np.rate(np.MIN_RATING, 0, 2400, False, 1, 1000) >= np.MIN_RATING
        assert np.rate(np.MAX_RATING, 0, 800, True, 1, 1000) <= np.MAX_RATING

    def test_level_and_target_are_inverses_around_the_handicap(self):
        for level in range(1, 11):
            target = np.elo_target_for_level(level)
            assert np.level_for_rating(target - np.CHALLENGE_OFFSET) == level
        assert np.level_for_rating(50) == 1
        assert np.level_for_rating(9000) == 10

    def test_a_right_answer_is_the_likely_outcome_at_level(self):
        for rating in (900, 1200, 1800):
            target = np.elo_target_for_level(np.level_for_rating(rating))
            assert 0.55 < np.expected_score(rating, target) < 0.85

    def test_points_reward_correctness_level_and_speed(self):
        assert np.step_points(False, 9, 100, 10000) == 0
        assert np.step_points(True, 9, 100, 10000) > np.step_points(True, 1, 100, 10000)
        assert np.step_points(True, 5, 500, 10000) > np.step_points(True, 5, 9500, 10000)


# --------------------------------------------------------------------------
# the daily ten
# --------------------------------------------------------------------------

class TestSession:
    def test_ten_steps_ending_on_the_zen_reset(self):
        steps = np.build_session(DEV, "2026-05-05")["steps"]
        assert len(steps) == np.SESSION_STEPS
        assert [s["index"] for s in steps] == list(range(np.SESSION_STEPS))
        assert all(s["discipline"] != "zen" for s in steps[:np.GRADED_STEPS])
        assert steps[-1]["discipline"] == "zen"

    def test_every_thinking_discipline_appears(self):
        used = {s["discipline"] for s in np.build_session(DEV, "2026-05-05")["steps"]}
        assert used == set(np.DISCIPLINES)

    def test_no_two_neighbours_share_a_discipline(self):
        steps = np.build_session(DEV, "2026-05-05")["steps"]
        for a, b in zip(steps, steps[1:]):
            assert a["discipline"] != b["discipline"]

    def test_a_discipline_visited_twice_asks_two_different_kinds(self):
        steps = np.build_session(DEV, "2026-05-05")["steps"]
        for discipline in np.DISCIPLINES:
            kinds = [s["kind"] for s in steps if s["discipline"] == discipline]
            assert len(kinds) == len(set(kinds))

    def test_the_same_day_is_stable_and_days_differ(self):
        first = np.build_session(DEV, "2026-05-05")
        again = np.build_session(DEV, "2026-05-05")
        assert [s["prompt"] for s in first["steps"]] == [s["prompt"] for s in again["steps"]]
        other_day = np.build_session(DEV, "2026-05-06")
        assert [s["prompt"] for s in first["steps"]] != [s["prompt"] for s in other_day["steps"]]

    def test_two_devices_get_their_own_session(self):
        mine = np.build_session(DEV, "2026-05-05")
        yours = np.build_session(OTHER, "2026-05-05")
        assert [s["prompt"] for s in mine["steps"]] != [s["prompt"] for s in yours["steps"]]

    def test_levels_follow_the_ratings_given(self):
        low = np.build_session(DEV, "2026-05-05", {d: 800 for d in np.DISCIPLINES})
        high = np.build_session(DEV, "2026-05-05", {d: 2000 for d in np.DISCIPLINES})
        assert max(s["level"] for s in low["steps"]) < min(s["level"] for s in high["steps"])

    def test_every_step_carries_what_the_phone_needs(self):
        for step in np.build_session(DEV, "2026-05-05")["steps"]:
            assert {"discipline", "kind", "skill", "level", "prompt", "spoken",
                    "answer", "accepts", "options", "inputStyle", "visual",
                    "hint", "explain", "index", "eloTarget",
                    "targetResponseMs"} <= set(step)
            assert step["inputStyle"] in ("choice", "number", "grid", "breathe", "reflect")
            assert step["eloTarget"] == np.elo_target_for_level(step["level"])
            assert step["targetResponseMs"] > 0
            if step["inputStyle"] == "choice":
                assert step["options"] and step["answer"] in step["options"]
            if step["inputStyle"] in ("breathe", "reflect"):
                assert step["answer"] == ""

    def test_every_kind_generates_at_every_level(self):
        for discipline, kinds in np.KINDS.items():
            for kind in kinds:
                for level in range(1, 11):
                    task = np.make_task(discipline, kind, level, random.Random(level))
                    assert task["discipline"] == discipline
                    assert task["kind"] == kind
                    assert task["prompt"]
                    if kind not in np.UNGRADED_KINDS:
                        assert task["answer"]

    def test_graded_answers_are_correct(self):
        """Spot-check the generators that compute their own answer."""
        rng = random.Random(3)
        for _ in range(60):
            chain = np.make_task("math", "chain", rng.randint(1, 10), rng)
            value = None
            body = chain["prompt"].removesuffix(". What do you have?")
            for part in body.split(", then "):
                part = part.strip()
                if part.startswith("Start with"):
                    value = int(part.split()[-1])
                elif part.startswith("add"):
                    value += int(part.split()[-1])
                elif part.startswith("take away"):
                    value -= int(part.split()[-1])
                elif part == "double it":
                    value *= 2
                elif part == "halve it":
                    value //= 2
                elif part.startswith("times"):
                    value *= int(part.split()[-1])
            assert str(value) == chain["answer"]

            target = np.make_task("math", "target", rng.randint(1, 10), rng)
            wanted = int(target["prompt"].removesuffix("?").split()[-1])
            add = "add up to" in target["prompt"]
            hits = 0
            for option in target["options"]:
                a, b = (int(x) for x in option.split(" and "))
                if (a + b if add else a * b) == wanted:
                    hits += 1
                    assert option == target["answer"]
            assert hits == 1

            flash = np.make_task("memory", "flash", rng.randint(1, 10), rng)
            digits = flash["visual"]["flashDigits"]
            shown = list(reversed(digits)) if flash["visual"]["reversed"] else digits
            assert flash["answer"] == "".join(str(d) for d in shown)

            nback = np.make_task("memory", "nback", rng.randint(1, 10), rng)
            run = nback["visual"]["flashLetters"]
            back = 2 if "two before" in nback["prompt"] else 3
            assert nback["answer"] == run[-1 - back]
            assert nback["answer"] in nback["options"]

            grid = np.make_task("memory", "grid", rng.randint(1, 10), rng)
            cells = grid["visual"]["cells"]
            assert grid["answer"] == ",".join(str(c) for c in cells)
            assert len(set(cells)) == len(cells)
            assert max(cells) < grid["visual"]["rows"] * grid["visual"]["cols"]

            stroop = np.make_task("zen", "stroop", rng.randint(1, 10), rng)
            visual = stroop["visual"]
            wanted = visual["word"] if not visual["askInk"] else visual["ink"].upper()
            assert stroop["answer"].upper() == wanted
            assert stroop["answer"] in stroop["options"]

    def test_the_breathing_reset_is_about_its_target_length(self):
        for level in range(1, 11):
            task = np.make_task("zen", "breathing", level, random.Random(level))
            pattern = task["visual"]["pattern"]
            seconds = sum(pattern) * task["visual"]["cycles"]
            assert len(pattern) == len(task["visual"]["labels"]) == 4
            assert abs(seconds - np.BREATH_SECONDS) <= 10


# --------------------------------------------------------------------------
# recording a session
# --------------------------------------------------------------------------

def answers(session, correct=True, response_ms=4000):
    """Answer a built session: every graded step, plus the reset."""
    out = []
    for step in session["steps"]:
        row = {"index": step["index"], "discipline": step["discipline"],
               "kind": step["kind"], "level": step["level"],
               "eloTarget": step["eloTarget"],
               "targetResponseMs": step["targetResponseMs"],
               "responseMs": response_ms, "correct": correct}
        if step["kind"] in np.UNGRADED_KINDS:
            row.update({"correct": False, "completed": True})
        out.append(row)
    return out


class TestRecording:
    def test_a_clean_run_raises_every_rating(self):
        np.reset_for_tests()
        session = np.build_session(DEV, "2026-05-05")
        out = np.record_session(DEV, answers(session), date="2026-05-05", name="Teja")
        graded = np.GRADED_STEPS + (
            0 if session["steps"][-1]["kind"] in np.UNGRADED_KINDS else 1)
        assert out["correct"] == out["graded"] == graded
        assert out["pulse"] > 0
        for discipline in ("logic", "math", "memory", "pattern"):
            assert out["ratings"][discipline] > np.START_RATING
            assert out["deltas"][discipline] > 0
        assert out["streak"] == 1
        assert out["improvedMost"] in np.DISCIPLINES

    def test_wrong_answers_lower_the_ratings(self):
        np.reset_for_tests()
        session = np.build_session(DEV, "2026-05-05")
        out = np.record_session(DEV, answers(session, correct=False), date="2026-05-05")
        assert out["pulse"] == 0 or session["steps"][-1]["kind"] in np.UNGRADED_KINDS
        for discipline in ("logic", "math", "memory", "pattern"):
            assert out["ratings"][discipline] < np.START_RATING

    def test_only_the_answered_disciplines_move(self):
        np.reset_for_tests()
        session = np.build_session(DEV, "2026-05-05")
        rows = [r for r in answers(session) if r["discipline"] == "math"]
        out = np.record_session(DEV, rows, date="2026-05-05")
        assert out["deltas"]["math"] > 0
        assert out["deltas"]["logic"] == 0
        assert out["ratings"]["logic"] == np.START_RATING

    def test_an_ungraded_reset_scores_but_never_rates(self):
        np.reset_for_tests()
        rows = [{"discipline": "zen", "kind": "breathing", "level": 3,
                 "eloTarget": 1200, "correct": False, "completed": True,
                 "responseMs": 45000, "targetResponseMs": 4000}]
        out = np.record_session(DEV, rows, date="2026-05-05", zen_seconds=45)
        assert out["pulse"] == np.ZEN_POINTS
        assert out["ratings"]["zen"] == np.START_RATING
        assert out["deltas"]["zen"] == 0
        assert np.profile(DEV)["zenMinutes"] == 0       # 45 s is not a minute yet

    def test_replaying_a_day_scores_but_cannot_farm_rating(self):
        np.reset_for_tests()
        session = np.build_session(DEV, "2026-05-05")
        first = np.record_session(DEV, answers(session), date="2026-05-05")
        again = np.record_session(DEV, answers(session), date="2026-05-05")
        assert again["alreadyPlayed"] is True
        assert again["ratings"] == first["ratings"]
        assert again["deltas"] == {d: 0 for d in np.DISCIPLINES}
        assert again["pulse"] > 0

    def test_games_played_and_bests_are_tracked(self):
        np.reset_for_tests()
        session = np.build_session(DEV, "2026-05-05")
        np.record_session(DEV, answers(session), date="2026-05-05")
        prof = np.profile(DEV)
        graded = np.GRADED_STEPS + (
            0 if session["steps"][-1]["kind"] in np.UNGRADED_KINDS else 1)
        assert sum(prof["games"].values()) == graded
        for discipline in ("logic", "math", "memory", "pattern"):
            assert prof["best"][discipline] == prof["ratings"][discipline]
            assert prof["levels"][discipline] == np.level_for_rating(
                prof["ratings"][discipline])

    def test_a_dip_keeps_the_best(self):
        np.reset_for_tests()
        session = np.build_session(DEV, "2026-05-05")
        high = np.record_session(DEV, answers(session), date="2026-05-05")["ratings"]
        np.record_session(DEV, answers(np.build_session(DEV, "2026-05-06"),
                                       correct=False), date="2026-05-06")
        prof = np.profile(DEV)
        assert prof["ratings"]["math"] < high["math"]
        assert prof["best"]["math"] == high["math"]

    def test_the_session_difficulty_follows_the_new_ratings(self):
        np.reset_for_tests()
        day = dt.date(2026, 5, 5)
        levels = []
        for i in range(6):
            date = (day + dt.timedelta(days=i)).isoformat()
            session = np.build_session(DEV, date, np.profile(DEV)["ratings"])
            levels.append(max(s["level"] for s in session["steps"]))
            np.record_session(DEV, answers(session, response_ms=1000), date=date)
        assert levels[-1] > levels[0]

    def test_history_is_kept_per_day(self):
        np.reset_for_tests()
        for i in range(3):
            date = (dt.date(2026, 5, 5) + dt.timedelta(days=i)).isoformat()
            np.record_session(DEV, answers(np.build_session(DEV, date)), date=date)
        history = np.profile(DEV)["history"]
        assert [row["date"] for row in history] == ["2026-05-05", "2026-05-06", "2026-05-07"]
        assert all(row["pulse"] > 0 for row in history)

    def test_mood_is_kept_only_when_it_is_in_range(self):
        np.reset_for_tests()
        np.record_session(DEV, [], date="2026-05-05", mood=4)
        np.record_session(DEV, [], date="2026-05-06", mood=99)
        moods = {row["date"]: row["mood"] for row in np.profile(DEV)["history"]}
        assert moods["2026-05-05"] == 4 and moods["2026-05-06"] == 0

    def test_junk_answers_are_ignored_not_fatal(self):
        np.reset_for_tests()
        rows = ["nope", 7, {}, {"discipline": "nonsense", "correct": True},
                {"discipline": "math", "level": 99, "correct": True,
                 "eloTarget": 1200, "responseMs": -5, "targetResponseMs": 0}]
        out = np.record_session(DEV, rows, date="2026-05-05")
        assert out["ratings"]["math"] > np.START_RATING
        assert out["deltas"]["logic"] == 0


class TestStreak:
    def test_back_to_back_days_build_a_streak(self):
        np.reset_for_tests()
        for i in range(4):
            date = (dt.date(2026, 5, 5) + dt.timedelta(days=i)).isoformat()
            out = np.record_session(DEV, [], date=date)
            assert out["streak"] == i + 1

    def test_one_missed_day_a_week_is_forgiven(self):
        np.reset_for_tests()
        np.record_session(DEV, [], date="2026-05-05")
        out = np.record_session(DEV, [], date="2026-05-07")      # skipped the 6th
        assert out["streak"] == 2

    def test_a_second_miss_in_the_same_week_resets(self):
        np.reset_for_tests()
        np.record_session(DEV, [], date="2026-05-05")
        np.record_session(DEV, [], date="2026-05-07")            # rest day used
        out = np.record_session(DEV, [], date="2026-05-09")
        assert out["streak"] == 1

    def test_the_rest_day_comes_back_after_a_week(self):
        np.reset_for_tests()
        np.record_session(DEV, [], date="2026-05-05")
        np.record_session(DEV, [], date="2026-05-07")            # rest day spent
        streak = 2
        for i in range(8, 15):                                   # 8th to 14th
            out = np.record_session(DEV, [], date=f"2026-05-{i:02d}")
            streak += 1
            assert out["streak"] == streak
        out = np.record_session(DEV, [], date="2026-05-16")      # forgiven again
        assert out["streak"] == streak + 1

    def test_a_long_gap_starts_over(self):
        np.reset_for_tests()
        np.record_session(DEV, [], date="2026-05-05")
        out = np.record_session(DEV, [], date="2026-06-20")
        assert out["streak"] == 1


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------

@pytest.fixture
def client():
    np.reset_for_tests()
    app, _ = create_app("default")
    return app.test_client()


class TestHTTP:
    def test_daily_serves_a_session_and_remembers_the_name(self, client):
        res = client.get(f"/api/neuro/daily?device={DEV}&date=2026-05-05&name=Teja")
        assert res.status_code == 200
        body = res.get_json()
        assert body["success"] is True
        assert len(body["steps"]) == np.SESSION_STEPS
        assert body["completed"] is False
        assert set(body["ratings"]) == set(np.DISCIPLINES)
        assert body["levels"]["math"] == np.level_for_rating(body["ratings"]["math"])
        assert body["names"]["zen"] == np.DISCIPLINE_NAMES["zen"]
        assert np.profile(DEV)["name"] == "Teja"

    def test_daily_rejects_a_bad_device(self, client):
        assert client.get("/api/neuro/daily?device=no").status_code == 400
        assert client.get("/api/neuro/daily").status_code == 400

    def test_a_bad_date_falls_back_to_today(self, client):
        body = client.get(f"/api/neuro/daily?device={DEV}&date=tomorrow").get_json()
        assert body["date"] == np.today()

    def test_result_rates_the_session_and_daily_then_says_completed(self, client):
        session = np.build_session(DEV, "2026-05-05")
        res = client.post("/api/neuro/result", json={
            "device": DEV, "date": "2026-05-05", "name": "Teja",
            "answers": answers(session), "seconds": 290, "zenSeconds": 45, "mood": 4,
        })
        assert res.status_code == 200
        body = res.get_json()
        assert body["success"] is True and body["pulse"] > 0
        assert body["ratings"]["logic"] > np.START_RATING
        again = client.get(f"/api/neuro/daily?device={DEV}&date=2026-05-05").get_json()
        assert again["completed"] is True

    def test_result_rejects_junk(self, client):
        assert client.post("/api/neuro/result", json={"device": "x"}).status_code == 400
        assert client.post("/api/neuro/result",
                           json={"device": DEV, "answers": "nope"}).status_code == 400
        assert client.post("/api/neuro/result",
                           json={"device": DEV,
                                 "answers": [{}] * 41}).status_code == 400

    def test_profile_endpoint(self, client):
        client.post("/api/neuro/result", json={
            "device": DEV, "date": "2026-05-05", "name": "Teja",
            "answers": answers(np.build_session(DEV, "2026-05-05")),
        })
        body = client.get(f"/api/neuro/profile/{DEV}").get_json()
        assert body["success"] is True
        assert body["name"] == "Teja" and body["streak"] == 1
        assert len(body["history"]) == 1
        assert client.get("/api/neuro/profile/zz").status_code == 400

    def test_leaderboard_ranks_everyone_and_lists_friends(self, client):
        from games import profiles
        for device, name, correct in ((DEV, "Teja", True), (OTHER, "Asha", False)):
            client.post("/api/neuro/result", json={
                "device": device, "date": "2026-05-05", "name": name,
                "answers": answers(np.build_session(device, "2026-05-05"),
                                   correct=correct),
            })
        from utils.room_manager import Player
        profiles.record_results("trivia", [
            {"playerID": DEV, "name": "Teja", "rank": 1},
            {"playerID": OTHER, "name": "Asha", "rank": 2},
        ], [Player(id=DEV, name="Teja"), Player(id=OTHER, name="Asha")])
        body = client.get(
            f"/api/neuro/leaderboard?date=2026-05-05&device={DEV}").get_json()
        assert [row["name"] for row in body["everyone"]] == ["Teja", "Asha"]
        assert body["everyone"][0]["rank"] == 1
        assert {row["device"] for row in body["friends"]} == {DEV, OTHER}
        empty = client.get("/api/neuro/leaderboard?date=2026-05-04").get_json()
        assert empty["everyone"] == [] and empty["friends"] == []


# --------------------------------------------------------------------------
# arcade: session-sized games that report one 0-1 score
# --------------------------------------------------------------------------

class TestFractionalRating:
    def test_rate_without_a_score_is_unchanged(self):
        """Every call that predates `score` must give the same answer. The
        pinned numbers were taken from the implementation before `score`
        existed (K=16 at 50 games: +8 x 1.15 for a fast right answer, -8 for
        a wrong one)."""
        assert np.rate(1200, 50, 1200, True, 3000, 10000) == 1209
        assert np.rate(1200, 50, 1200, False, 3000, 10000) == 1192
        assert np.rate(1200, 5, 1300, True) == np.rate(1200, 5, 1300, True, 0.0, 0.0, None)

    def test_a_full_score_matches_a_correct_answer_without_the_speed_bonus(self):
        full = np.rate(1200, 50, 1200, False, score=1.0)
        plain = np.rate(1200, 50, 1200, True, 8000, 10000)      # inside target: x1.0
        assert full == plain > 1200

    def test_a_zero_score_matches_a_wrong_answer(self):
        assert np.rate(1200, 50, 1200, True, score=0.0) == np.rate(1200, 50, 1200, False)

    def test_scoring_exactly_what_was_expected_does_not_move_the_rating(self):
        target = 1400
        exp = np.expected_score(1200, target)
        assert np.rate(1200, 50, target, False, score=exp) == 1200

    def test_a_partial_score_lands_between_the_extremes(self):
        low = np.rate(1200, 50, 1200, False, score=0.0)
        mid = np.rate(1200, 50, 1200, False, score=0.5)
        high = np.rate(1200, 50, 1200, False, score=1.0)
        assert low < mid < high

    def test_speed_is_not_applied_on_top_of_a_score(self):
        fast = np.rate(1200, 50, 1200, True, 100, 10000, score=0.8)
        slow = np.rate(1200, 50, 1200, True, 99999, 10000, score=0.8)
        assert fast == slow

    def test_out_of_range_scores_are_clamped_by_rate(self):
        assert np.rate(1200, 50, 1200, False, score=7.0) == np.rate(1200, 50, 1200, False, score=1.0)
        assert np.rate(1200, 50, 1200, False, score=-3.0) == np.rate(1200, 50, 1200, False, score=0.0)

    def test_ratings_still_stay_inside_their_bounds(self):
        assert np.rate(np.MIN_RATING, 0, 2400, False, score=0.0) >= np.MIN_RATING
        assert np.rate(np.MAX_RATING, 0, 800, False, score=1.0) <= np.MAX_RATING


class TestArcadeRecording:
    DAY = "2026-03-02"

    def test_every_arcade_game_maps_to_a_real_discipline(self):
        assert set(np.ARCADE_GAMES.values()) <= set(np.DISCIPLINES)
        assert "zen" not in np.ARCADE_GAMES.values()

    def test_a_good_run_raises_the_games_discipline_only(self):
        out = np.record_arcade(DEV, "probe", 5, 0.95, date=self.DAY)
        assert out["rated"] and out["discipline"] == "logic"
        assert out["delta"] > 0 and out["after"] == out["before"] + out["delta"]
        for d in np.DISCIPLINES:
            if d != "logic":
                assert out["ratings"][d] == np.START_RATING

    def test_a_poor_run_lowers_it(self):
        out = np.record_arcade(DEV, "drift", 5, 0.05, date=self.DAY)
        assert out["discipline"] == "pattern" and out["delta"] < 0

    def test_the_discipline_comes_from_the_game_not_the_phone(self):
        out = np.record_arcade(DEV, "ballpark", 3, 0.9, date=self.DAY)
        assert out["discipline"] == "math"

    def test_only_the_first_run_of_a_game_per_day_is_rated(self):
        first = np.record_arcade(DEV, "probe", 5, 0.9, date=self.DAY)
        again = np.record_arcade(DEV, "probe", 5, 1.0, date=self.DAY)
        assert first["rated"] and not again["rated"]
        assert again["alreadyRated"] and again["delta"] == 0
        assert again["after"] == first["after"]

    def test_a_different_game_the_same_day_is_rated(self):
        np.record_arcade(DEV, "probe", 5, 0.9, date=self.DAY)
        other = np.record_arcade(DEV, "drift", 5, 0.9, date=self.DAY)
        assert other["rated"] and other["delta"] > 0

    def test_the_next_day_is_rated_again(self):
        np.record_arcade(DEV, "probe", 5, 0.9, date=self.DAY)
        nxt = np.record_arcade(DEV, "probe", 5, 0.9, date="2026-03-03")
        assert nxt["rated"]

    def test_a_practice_run_never_moves_the_rating_or_uses_up_the_day(self):
        practice = np.record_arcade(DEV, "probe", 5, 1.0, date=self.DAY, practice=True)
        assert not practice["rated"] and practice["delta"] == 0
        assert not practice["alreadyRated"]
        real = np.record_arcade(DEV, "probe", 5, 1.0, date=self.DAY)
        assert real["rated"] and real["delta"] > 0

    def test_a_rated_run_counts_towards_the_k_factor(self):
        np.record_arcade(DEV, "probe", 5, 0.9, date=self.DAY)
        assert np.profile(DEV)["games"]["logic"] == 1
        np.record_arcade(DEV, "probe", 5, 0.9, date=self.DAY, practice=True)
        assert np.profile(DEV)["games"]["logic"] == 1

    def test_a_harder_level_pays_more_for_the_same_score(self):
        easy = np.record_arcade("dev-easy-1", "probe", 1, 0.9, date=self.DAY)
        hard = np.record_arcade("dev-hard-1", "probe", 10, 0.9, date=self.DAY)
        assert hard["delta"] > easy["delta"]

    def test_the_level_is_clamped(self):
        assert np.record_arcade("dev-lvl-high", "probe", 99, 0.5, date=self.DAY)["level"] == 10
        assert np.record_arcade("dev-lvl-low", "probe", -4, 0.5, date=self.DAY)["level"] == 1

    @pytest.mark.parametrize("score", [-0.1, 1.01, float("nan"), float("inf"), "x", None])
    def test_a_bad_score_is_refused(self, score):
        with pytest.raises((ValueError, TypeError)):
            np.record_arcade(DEV, "probe", 5, score, date=self.DAY)

    def test_an_unknown_game_is_refused(self):
        with pytest.raises(ValueError):
            np.record_arcade(DEV, "pong", 5, 0.5, date=self.DAY)

    def test_a_refused_run_leaves_the_ratings_alone(self):
        with pytest.raises(ValueError):
            np.record_arcade(DEV, "probe", 5, 2.0, date=self.DAY)
        assert np.profile(DEV)["ratings"]["logic"] == np.START_RATING

    def test_the_arcade_does_not_touch_the_daily_streak_or_pulse(self):
        np.record_arcade(DEV, "probe", 5, 1.0, date=self.DAY)
        prof = np.profile(DEV)
        assert prof["streak"] == 0 and prof["history"] == []

    def test_a_daily_session_and_an_arcade_run_both_count(self):
        sess = np.build_session(DEV, self.DAY)
        np.record_session(DEV, answers(sess, True), date=self.DAY)
        before = np.profile(DEV)["ratings"]["logic"]
        out = np.record_arcade(DEV, "probe", 5, 1.0, date=self.DAY)
        assert out["rated"] and out["before"] == before

    def test_the_profile_lists_every_game_even_unplayed(self):
        arcade = np.profile(DEV)["arcade"]
        assert set(arcade) == set(np.ARCADE_GAMES)
        assert all(row["plays"] == 0 and row["best"] == 0.0 for row in arcade.values())

    def test_the_profile_tracks_plays_best_and_last(self):
        np.record_arcade(DEV, "drift", 4, 0.6, date=self.DAY)
        np.record_arcade(DEV, "drift", 4, 0.9, date="2026-03-03")
        np.record_arcade(DEV, "drift", 4, 0.3, date="2026-03-04")
        row = np.profile(DEV)["arcade"]["drift"]
        assert row["plays"] == 3 and row["best"] == 0.9
        assert row["last"] == 0.3 and row["lastDate"] == "2026-03-04"

    def test_practice_runs_still_show_in_plays_and_best(self):
        np.record_arcade(DEV, "probe", 4, 0.7, date=self.DAY, practice=True)
        row = np.profile(DEV)["arcade"]["probe"]
        assert row["plays"] == 1 and row["best"] == 0.7

    def test_old_arcade_days_are_pruned(self):
        base = dt.date(2025, 1, 1)
        for i in range(np._KEEP_DAYS + 10):
            np.record_arcade(DEV, "probe", 3, 0.5, date=(base + dt.timedelta(days=i)).isoformat())
        data = np._load()
        assert len(data["devices"][DEV]["arcadeDays"]) <= np._KEEP_DAYS

    def test_an_entry_saved_before_the_arcade_existed_still_loads(self):
        data = {"devices": {DEV: {"ratings": {d: 1100 for d in np.DISCIPLINES},
                                   "games": {d: 3 for d in np.DISCIPLINES}}}}
        np._save(data)
        assert np.profile(DEV)["arcade"]["probe"]["plays"] == 0
        assert np.record_arcade(DEV, "probe", 5, 0.9, date=self.DAY)["rated"]


class TestArcadeHTTP:
    def test_a_run_is_rated_over_http(self, client):
        res = client.post("/api/neuro/arcade", json={
            "device": DEV, "game": "probe", "level": 5, "score": 0.9,
            "date": "2026-03-02", "seconds": 80, "name": "Teja"})
        body = res.get_json()
        assert res.status_code == 200 and body["success"] and body["rated"]
        assert body["discipline"] == "logic" and body["delta"] > 0
        assert body["arcade"]["probe"]["plays"] == 1

    def test_the_second_run_of_the_day_is_not_rated(self, client):
        payload = {"device": DEV, "game": "probe", "level": 5, "score": 0.9,
                   "date": "2026-03-02"}
        client.post("/api/neuro/arcade", json=payload)
        again = client.post("/api/neuro/arcade", json=payload).get_json()
        assert again["alreadyRated"] and not again["rated"]

    def test_practice_is_honoured(self, client):
        res = client.post("/api/neuro/arcade", json={
            "device": DEV, "game": "drift", "level": 5, "score": 1.0, "practice": True})
        assert res.get_json()["rated"] is False

    @pytest.mark.parametrize("payload", [
        {"game": "probe", "score": 0.5},                                  # no device
        {"device": "x", "game": "probe", "score": 0.5},                   # bad device
        {"device": DEV, "game": "pong", "score": 0.5},                    # unknown game
        {"device": DEV, "game": "", "score": 0.5},
        {"device": DEV, "game": "probe"},                                 # no score
        {"device": DEV, "game": "probe", "score": 1.5},
        {"device": DEV, "game": "probe", "score": -1},
        {"device": DEV, "game": "probe", "score": "high"},
        {"device": DEV, "game": "probe", "score": 0.5, "level": "abc"},
    ])
    def test_bad_requests_are_400(self, client, payload):
        res = client.post("/api/neuro/arcade", json=payload)
        assert res.status_code == 400 and res.get_json()["success"] is False

    def test_a_non_json_body_is_400(self, client):
        assert client.post("/api/neuro/arcade", data="nope").status_code == 400

    def test_the_profile_endpoint_carries_the_arcade(self, client):
        client.post("/api/neuro/arcade", json={
            "device": DEV, "game": "split", "level": 3, "score": 0.7})
        body = client.get(f"/api/neuro/profile/{DEV}").get_json()
        assert body["arcade"]["split"]["plays"] == 1
        assert body["arcade"]["split"]["discipline"] == "memory"


# --------------------------------------------------------------------------
# steps that need a newer phone: Liar's Row and Dead Reckoning
# --------------------------------------------------------------------------

def _truth(statements, thief, index, seen=()):
    """Independent re-statement of the rules, written without np helpers."""
    st = statements[index]
    if st["type"] == "was":
        return thief == st["target"]
    if st["type"] == "wasnt":
        return thief != st["target"]
    other = [i for i, x in enumerate(statements) if x["by"] == st["target"]][0]
    assert other not in seen and other != index, "statements refer in a circle"
    inner = _truth(statements, thief, other, seen + (index,))
    return (not inner) if st["type"] == "lies" else inner


def _culprits(statements, suspects, liars):
    return [t for t in suspects
            if sum(1 for i in range(len(statements))
                   if not _truth(statements, t, i)) == liars]


class TestLiarsRow:
    @pytest.mark.parametrize("level", range(1, 11))
    def test_every_puzzle_has_exactly_one_answer_and_it_is_the_dealt_one(self, level):
        for seed in range(120):
            task = np.make_task("logic", "liars_row", level, random.Random(seed * 31 + level))
            vis = task["visual"]
            found = _culprits(vis["statements"], vis["suspects"], vis["liars"])
            assert found == [task["answer"]], (level, seed, task["prompt"])

    @pytest.mark.parametrize("level", range(1, 11))
    def test_shape_and_options(self, level):
        task = np.make_task("logic", "liars_row", level, random.Random(level))
        assert task["discipline"] == "logic" and task["kind"] == "liars_row"
        assert task["inputStyle"] == "choice"
        assert len(task["options"]) == 4 and len(set(task["options"])) == 4
        assert task["answer"] in task["options"]
        assert set(task["options"]) <= set(task["visual"]["suspects"])

    def test_difficulty_scales_with_the_level(self):
        low = np.make_task("logic", "liars_row", 1, random.Random(1))["visual"]
        mid = np.make_task("logic", "liars_row", 5, random.Random(1))["visual"]
        high = np.make_task("logic", "liars_row", 10, random.Random(1))["visual"]
        assert (len(low["suspects"]), len(mid["suspects"]), len(high["suspects"])) == (4, 5, 6)
        assert (low["liars"], mid["liars"], high["liars"]) == (1, 1, 2)

    def test_only_harder_levels_use_statements_about_honesty(self):
        for seed in range(80):
            easy = np.make_task("logic", "liars_row", 2, random.Random(seed))["visual"]
            assert {s["type"] for s in easy["statements"]} <= {"was", "wasnt"}
        seen = set()
        for seed in range(80):
            hard = np.make_task("logic", "liars_row", 9, random.Random(seed))["visual"]
            seen |= {s["type"] for s in hard["statements"]}
        assert {"lies", "truth"} & seen

    def test_the_prompt_shows_every_statement_and_says_how_many_lie(self):
        task = np.make_task("logic", "liars_row", 9, random.Random(4))
        for st in task["visual"]["statements"]:
            assert f"{st['by']}:" in task["prompt"]
        assert "Exactly two" in task["prompt"] and task["prompt"].rstrip().endswith("Who did it?")
        one = np.make_task("logic", "liars_row", 2, random.Random(4))
        assert "Exactly one" in one["prompt"]

    def test_nobody_is_asked_to_vouch_for_themselves(self):
        for seed in range(100):
            vis = np.make_task("logic", "liars_row", 9, random.Random(seed))["visual"]
            for st in vis["statements"]:
                if st["type"] in ("lies", "truth"):
                    assert st["target"] != st["by"]

    def test_the_explanation_names_the_false_speakers(self):
        task = np.make_task("logic", "liars_row", 3, random.Random(2))
        vis = task["visual"]
        liars = [st["by"] for i, st in enumerate(vis["statements"])
                 if not _truth(vis["statements"], task["answer"], i)]
        for name in liars:
            assert name in task["explain"]

    def test_same_seed_same_puzzle(self):
        a = np.make_task("logic", "liars_row", 6, random.Random(77))
        b = np.make_task("logic", "liars_row", 6, random.Random(77))
        assert a == b

    def test_spoken_text_has_no_line_breaks(self):
        assert "\n" not in np.make_task("logic", "liars_row", 5, random.Random(1))["spoken"]


class TestDeadReckoning:
    OFFSETS = {"north": (-1, 0), "south": (1, 0), "east": (0, 1), "west": (0, -1),
               "north-east": (-1, 1), "north-west": (-1, -1),
               "south-east": (1, 1), "south-west": (1, -1)}

    def _walk(self, vis):
        side = vis["rows"]
        row, col = divmod(vis["start"], side)
        path = [(row, col)]
        for move in vis["moves"]:
            name, count = move.rsplit(" ", 1)
            dr, dc = self.OFFSETS[name]
            row, col = row + dr * int(count), col + dc * int(count)
            path.append((row, col))
        return side, path

    @pytest.mark.parametrize("level", range(1, 11))
    def test_the_answer_is_where_the_moves_end(self, level):
        for seed in range(100):
            task = np.make_task("memory", "dead_reckoning", level, random.Random(seed * 17 + level))
            side, path = self._walk(task["visual"])
            end = path[-1]
            assert task["answer"] == str(end[0] * side + end[1])
            assert path[0] != end

    @pytest.mark.parametrize("level", range(1, 11))
    def test_the_dot_never_leaves_the_grid(self, level):
        for seed in range(100):
            task = np.make_task("memory", "dead_reckoning", level, random.Random(seed * 5 + level))
            side, path = self._walk(task["visual"])
            assert all(0 <= r < side and 0 <= c < side for r, c in path)

    def test_nothing_is_lit_and_the_start_is_marked(self):
        task = np.make_task("memory", "dead_reckoning", 5, random.Random(1))
        vis = task["visual"]
        assert task["inputStyle"] == "grid" and vis["cells"] == [] and vis["flashMs"] == 0
        assert 0 <= vis["start"] < vis["rows"] * vis["cols"]

    def test_no_repeated_or_reversing_moves(self):
        opposite = {"north": "south", "south": "north", "east": "west", "west": "east",
                    "north-east": "south-west", "south-west": "north-east",
                    "north-west": "south-east", "south-east": "north-west"}
        for level in (3, 8, 10):
            for seed in range(120):
                moves = [m.rsplit(" ", 1)[0] for m in
                         np.make_task("memory", "dead_reckoning", level,
                                      random.Random(seed))["visual"]["moves"]]
                for a, b in zip(moves, moves[1:]):
                    assert a != b and opposite[a] != b

    def test_difficulty_scales_with_the_level(self):
        sides = [np.make_task("memory", "dead_reckoning", lv, random.Random(1))["visual"]["rows"]
                 for lv in (1, 3, 7, 10)]
        counts = [len(np.make_task("memory", "dead_reckoning", lv, random.Random(1))["visual"]["moves"])
                  for lv in (1, 4, 10)]
        assert sides == [3, 4, 5, 5]
        assert counts == [3, 4, 7]

    def test_diagonals_only_from_level_six(self):
        for seed in range(100):
            easy = np.make_task("memory", "dead_reckoning", 5, random.Random(seed))["visual"]["moves"]
            assert not any("-" in m for m in easy)
        seen = False
        for seed in range(100):
            hard = np.make_task("memory", "dead_reckoning", 9, random.Random(seed))["visual"]["moves"]
            seen = seen or any("-" in m for m in hard)
        assert seen

    def test_the_answer_is_a_single_cell(self):
        task = np.make_task("memory", "dead_reckoning", 6, random.Random(9))
        assert "," not in task["answer"] and task["answer"].isdigit()


class TestCapabilities:
    def test_optional_kinds_are_known(self):
        assert np.KNOWN_CAPS == {"liars_row", "dead_reckoning"}
        for discipline, kinds in np.OPTIONAL_KINDS.items():
            assert discipline in np.KINDS and not set(kinds) & set(np.KINDS[discipline])

    def test_a_phone_without_caps_never_gets_the_new_kinds(self):
        seen = set()
        for day in range(150):
            date = (dt.date(2026, 1, 1) + dt.timedelta(days=day)).isoformat()
            seen |= {s["kind"] for s in np.build_session(DEV, date)["steps"]}
        assert not seen & np.KNOWN_CAPS

    def test_a_phone_with_caps_does_get_them(self):
        seen = set()
        for day in range(150):
            date = (dt.date(2026, 1, 1) + dt.timedelta(days=day)).isoformat()
            seen |= {s["kind"] for s in np.build_session(DEV, date, caps=np.KNOWN_CAPS)["steps"]}
        assert np.KNOWN_CAPS <= seen

    def test_asking_for_only_one_kind_gets_only_that_one(self):
        seen = set()
        for day in range(150):
            date = (dt.date(2026, 1, 1) + dt.timedelta(days=day)).isoformat()
            seen |= {s["kind"] for s in
                     np.build_session(DEV, date, caps={"liars_row"})["steps"]}
        assert "liars_row" in seen and "dead_reckoning" not in seen

    def test_empty_caps_give_the_same_session_as_before_caps_existed(self):
        for day in range(40):
            date = (dt.date(2026, 5, 1) + dt.timedelta(days=day)).isoformat()
            assert np.build_session(DEV, date) == np.build_session(DEV, date, caps=())
            assert np.build_session(DEV, date) == np.build_session(DEV, date, caps={"nonsense"})

    def test_a_session_with_caps_keeps_the_shape_rules(self):
        for day in range(80):
            date = (dt.date(2026, 1, 1) + dt.timedelta(days=day)).isoformat()
            steps = np.build_session(DEV, date, caps=np.KNOWN_CAPS)["steps"]
            assert len(steps) == np.SESSION_STEPS
            assert steps[-1]["discipline"] == "zen"
            kinds = [s["kind"] for s in steps[:-1]]
            by_discipline = {}
            for s in steps[:-1]:
                by_discipline.setdefault(s["discipline"], []).append(s["kind"])
            for dkinds in by_discipline.values():
                assert len(dkinds) == len(set(dkinds)), "a kind repeated in a discipline"
            for a, b in zip(steps, steps[1:]):
                assert a["discipline"] != b["discipline"]
            assert len(kinds) == 9

    def test_the_daily_endpoint_honours_caps(self, client):
        plain = client.get(f"/api/neuro/daily?device={DEV}&date=2026-02-03").get_json()
        assert not {s["kind"] for s in plain["steps"]} & np.KNOWN_CAPS
        seen = set()
        for day in range(1, 29):
            res = client.get(f"/api/neuro/daily?device={DEV}&date=2026-02-{day:02d}"
                             "&caps=liars_row,dead_reckoning,bogus").get_json()
            seen |= {s["kind"] for s in res["steps"]}
        assert np.KNOWN_CAPS <= seen

    def test_new_kinds_are_graded_like_any_other(self):
        sess = np.build_session(DEV, "2026-02-10", caps=np.KNOWN_CAPS)
        out = np.record_session(DEV, answers(sess, True), date="2026-02-10")
        assert out["graded"] >= 8 and out["pulse"] > 0
