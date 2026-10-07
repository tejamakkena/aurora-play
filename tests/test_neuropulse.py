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
