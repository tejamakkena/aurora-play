"""The Trivia game show (games/native_hub/engines/trivia_show.py).

Covers the whole server-driven phase flow: intro, category vote (and its
random tie-break), powers and shields, scoring with the speed bonus, the
Final Climb finale and its endings, custom quizzes skipping the vote, and
bots playing a whole show without breaking it.
"""

import json
import random
import time

import pytest

from games.native_hub import bots
from games.native_hub.engines import trivia_show
from games.native_hub.engines.trivia_show import TriviaEngine
from utils.room_manager import RoomRegistry, RoomState


class _Null:
    def state(self): pass
    def room_update(self): pass
    def error(self, *a, **k): pass


class _Clock:
    def __init__(self, monkeypatch):
        self.now = 1_800_000_000.0
        monkeypatch.setattr(time, "time", lambda: self.now)

    def advance(self, seconds):
        self.now += seconds


def make(players=3, seeds=None, topic="", pack=None, seed=5, bots_count=0):
    random.seed(seed)
    room = RoomRegistry().create("trivia")
    if seeds is not None:
        room.seed_questions = seeds
    room.topic = topic
    if pack:
        room.content_pack = pack
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    for _ in range(bots_count):
        roster.append(room.add_bot())
    engine = TriviaEngine(room, _Null())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def to_phase(engine, phase, limit=300):
    for _ in range(limit):
        if engine.phase == phase:
            return
        engine.deadline = 0.0
        engine.tick(0.0)
    raise AssertionError(f"never reached {phase}; stuck in {engine.phase}")


def answer(engine, pid, index):
    engine.handle_action(pid, "answer",
                         {"choiceIndex": index, "questionID": engine.question_id})


def wrong_index(engine):
    return (engine.question[3] + 1) % len(engine.question[2])


SEEDS = [{"question": f"Seeded question {i}?",
          "options": ["A", "B", "C", "D"], "correct_answer": i % 4}
         for i in range(20)]


# ---- phase flow ---------------------------------------------------------------


class TestPhaseFlow:
    def test_full_show_runs_in_order(self):
        engine, roster = make(players=3)
        seen = [engine.phase]
        for _ in range(400):
            if engine.is_over():
                break
            engine.deadline = 0.0
            engine.tick(0.0)
            if engine.phase != seen[-1]:
                seen.append(engine.phase)
        assert engine.is_over()
        assert seen[0] == "intro"
        assert seen[1] == "category_vote"
        assert seen[2] == "category_reveal"
        assert seen.count("category_vote") == 3          # one per round
        assert seen.count("question") >= 1
        assert seen.count("standings") == 3
        assert "finale_intro" in seen and "finale_question" in seen
        assert seen[-1] == "summary"
        assert engine.question_no == 9
        # Every phase change carries a deadline for the clients' timers.
        assert isinstance(engine.public_state()["deadline"], float)

    def test_every_phase_is_json_serialisable_for_tv_and_phones(self):
        engine, roster = make(players=3)
        for _ in range(400):
            json.dumps(engine.public_state())
            for p in roster:
                json.dumps(engine.private_state(p.id))
            if engine.is_over():
                break
            engine.deadline = 0.0
            engine.tick(0.0)
        assert engine.is_over()

    def test_powers_come_before_every_second_question(self):
        engine, roster = make(players=3)
        to_phase(engine, "question")
        assert engine.question_no == 1
        to_phase(engine, "power_pick")
        # Nobody picked a power: straight on to question two.
        to_phase(engine, "question")
        assert engine.question_no == 2

    def test_question_never_leaks_correctness_to_the_tv(self):
        engine, roster = make(players=2)
        to_phase(engine, "question")
        answer(engine, roster[0].id, engine.question[3])
        board = engine.public_state()
        assert "correctIndex" not in board and "lastResults" not in board
        assert all(p["score"] == 0 for p in board["players"])
        engine.tick(0.0)          # p1 has not answered: still open
        assert engine.phase == "question"
        answer(engine, roster[1].id, wrong_index(engine))
        engine.tick(0.0)          # everyone answered: early reveal
        assert engine.phase == "reveal"
        board = engine.public_state()
        assert board["correctIndex"] == engine.question[3]
        rows = {r["playerID"]: r for r in board["lastResults"]}
        assert rows[roster[0].id]["correct"] and rows[roster[0].id]["points"] > 0
        assert not rows[roster[1].id]["correct"]

    def test_stale_or_junk_answers_are_ignored(self):
        engine, roster = make(players=2)
        to_phase(engine, "question")
        pid = roster[0].id
        engine.handle_action(pid, "answer", {"choiceIndex": 0, "questionID": "q99"})
        engine.handle_action(pid, "answer", {"choiceIndex": 9, "questionID": engine.question_id})
        engine.handle_action(pid, "answer", {"choiceIndex": True, "questionID": engine.question_id})
        engine.handle_action(pid, "answer", "garbage")
        assert pid not in engine.answered
        answer(engine, pid, 1)
        answer(engine, pid, 2)            # locked in: the second is ignored
        assert engine.answered[pid] == 1


# ---- category vote ----------------------------------------------------------


class TestCategoryVote:
    def test_three_doors_and_majority_wins(self):
        engine, roster = make(players=3)
        to_phase(engine, "category_vote")
        assert len(engine.categories) == 3
        assert len(set(engine.categories)) == 3
        for p in roster:
            engine.handle_action(p.id, "vote_category", {"index": 2})
        engine.tick(0.0)                   # all voted: closes early
        assert engine.phase == "category_reveal"
        assert engine.chosen_category == engine.categories[2]

    def test_tie_is_broken_randomly_between_the_leaders(self):
        winners = set()
        for seed in range(30):
            engine, roster = make(players=2, seed=seed)
            to_phase(engine, "category_vote")
            engine.handle_action(roster[0].id, "vote_category", {"index": 0})
            engine.handle_action(roster[1].id, "vote_category", {"index": 1})
            engine.tick(0.0)
            assert engine.chosen_index in (0, 1)       # never the empty door
            winners.add(engine.chosen_index)
        assert winners == {0, 1}

    def test_votes_are_once_only_and_validated(self):
        engine, roster = make(players=3)
        to_phase(engine, "category_vote")
        pid = roster[0].id
        engine.handle_action(pid, "vote_category", {"index": 7})
        engine.handle_action(pid, "vote_category", {"index": "1"})
        assert pid not in engine.votes
        engine.handle_action(pid, "vote_category", {"index": 1})
        engine.handle_action(pid, "vote_category", {"index": 0})
        assert engine.votes[pid] == 1
        assert engine.private_state(pid)["myVote"] == 1

    def test_round_questions_come_from_the_chosen_category(self):
        engine, roster = make(players=2)
        to_phase(engine, "category_vote")
        for p in roster:
            engine.handle_action(p.id, "vote_category", {"index": 0})
        engine.tick(0.0)
        chosen = engine.chosen_category
        to_phase(engine, "question")
        assert engine.question[0] == chosen
        assert engine.public_state()["category"] == chosen


# ---- powers -------------------------------------------------------------------


class TestPowers:
    def _to_power_pick(self, players=3):
        engine, roster = make(players=players)
        to_phase(engine, "power_pick")
        return engine, roster

    def test_power_only_affects_its_target(self):
        engine, roster = self._to_power_pick()
        a, b, c = (p.id for p in roster)
        engine.handle_action(a, "pick_power", {"power": "freeze", "targetID": b})
        engine.tick(0.0)
        assert engine.phase == "power_pick"     # b and c still picking
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.phase == "power_reveal"
        events = engine.public_state()["powerEvents"]
        assert events == [{"power": "freeze", "fromID": a, "fromName": "P0",
                           "toID": b, "toName": "P1", "blocked": False}]
        to_phase(engine, "question")
        assert [h["power"] for h in engine.private_state(b)["hitBy"]] == ["freeze"]
        assert engine.private_state(a)["hitBy"] == []
        assert engine.private_state(c)["hitBy"] == []

    def test_shield_blocks_one_incoming_power(self):
        engine, roster = self._to_power_pick()
        a, b, c = (p.id for p in roster)
        engine.handle_action(b, "pick_power", {"power": "shield"})
        engine.handle_action(a, "pick_power", {"power": "fog", "targetID": b})
        engine.handle_action(c, "pick_power", {"power": "scramble", "targetID": b})
        engine.tick(0.0)                         # everyone picked
        assert engine.phase == "power_reveal"
        events = engine.power_events
        assert [(e["power"], e["blocked"]) for e in events] == [
            ("fog", True), ("scramble", False)]
        private = engine.private_state(b)
        assert [h["power"] for h in private["hitBy"]] == ["scramble"]
        assert private["shieldBlocked"] == ["P0"]

    def test_shield_without_attack_changes_nothing(self):
        engine, roster = self._to_power_pick()
        a, b, c = (p.id for p in roster)
        engine.handle_action(a, "pick_power", {"power": "shield"})
        engine.handle_action(b, "pick_power", {"power": "scramble", "targetID": c})
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.private_state(c)["hitBy"][0]["power"] == "scramble"
        assert engine.private_state(a)["hitBy"] == []

    def test_invalid_picks_are_ignored(self):
        engine, roster = self._to_power_pick()
        a, b, _ = (p.id for p in roster)
        engine.handle_action(a, "pick_power", {"power": "freeze", "targetID": a})
        engine.handle_action(a, "pick_power", {"power": "freeze", "targetID": "ghost"})
        engine.handle_action(a, "pick_power", {"power": "lightning", "targetID": b})
        engine.handle_action(a, "pick_power", {"power": "freeze"})
        assert a not in engine.power_picks

    def test_powers_wear_off_after_the_question(self):
        engine, roster = self._to_power_pick()
        a, b, _ = (p.id for p in roster)
        engine.handle_action(a, "pick_power", {"power": "freeze", "targetID": b})
        to_phase(engine, "question")
        assert engine.private_state(b)["hitBy"]
        to_phase(engine, "reveal")
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.private_state(b)["hitBy"] == []
        assert engine.public_state()["powerEvents"] == []

    def test_no_powers_with_a_single_player(self):
        engine, roster = make(players=1)
        to_phase(engine, "question")
        to_phase(engine, "reveal")
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.phase == "question" and engine.question_no == 2


# ---- scoring --------------------------------------------------------------------


class TestScoring:
    def test_speed_bonus_and_scores_land_at_the_reveal(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make(players=3)
        to_phase(engine, "question")
        a, b, c = (p.id for p in roster)
        clock.now = engine.choices_at                  # instant answer
        answer(engine, a, engine.question[3])
        clock.now = engine.choices_at + engine.QUESTION_SECONDS / 2
        answer(engine, b, engine.question[3])
        answer(engine, c, wrong_index(engine))
        assert engine.scores == {a: 0, b: 0, c: 0}    # held back
        engine.tick(0.0)
        assert engine.phase == "reveal"
        assert engine.scores[a] == 1000
        assert engine.scores[b] == 750
        assert engine.scores[c] == 0
        assert engine.private_state(a)["pointsEarned"] == 1000
        assert engine.private_state(c)["wasCorrect"] is False
        assert engine.room.player(a).score == 1000

    def test_answering_during_the_read_beat_gets_the_full_bonus(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, _ = make(players=2)
        to_phase(engine, "question")
        assert engine.points_for(engine.choices_at - 1) == 1000
        assert engine.points_for(engine.choices_at + 100) == 500

    def test_no_answer_scores_nothing(self):
        engine, roster = make(players=2)
        to_phase(engine, "question")
        to_phase(engine, "reveal")
        assert all(v == 0 for v in engine.scores.values())


# ---- finale -------------------------------------------------------------------


class TestFinale:
    def _to_finale(self, players=3, scores=None):
        engine, roster = make(players=players)
        to_phase(engine, "standings")
        # Jump past the remaining main questions.
        engine.question_no = engine.total_rounds
        if scores:
            engine.scores.update(scores)
        to_phase(engine, "finale_intro")
        return engine, roster

    def test_leaders_get_a_head_start(self):
        engine, roster = self._to_finale(scores={"p0": 3000, "p1": 1000, "p2": 0})
        assert engine.rungs == {"p0": 2, "p1": 1, "p2": 0}
        board = engine.public_state()
        assert {p["id"]: p["rung"] for p in board["players"]} == engine.rungs
        assert board["towerHeight"] == engine.TOWER_HEIGHT

    def test_right_climbs_wrong_slips_silence_stays(self):
        engine, roster = self._to_finale(scores={"p0": 3000, "p1": 1000, "p2": 0})
        to_phase(engine, "finale_question")
        answer(engine, "p0", wrong_index(engine))
        answer(engine, "p1", engine.question[3])
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.phase == "finale_reveal"
        assert engine.rungs == {"p0": 1, "p1": 2, "p2": 0}
        assert engine.finale_moves == {"p0": -1, "p1": 1, "p2": 0}
        assert engine.private_state("p1")["rungMove"] == 1

    def test_first_to_the_top_wins(self):
        engine, roster = self._to_finale(scores={"p0": 3000, "p1": 1000, "p2": 0})
        engine.rungs["p2"] = engine.TOWER_HEIGHT - 1
        to_phase(engine, "finale_question")
        answer(engine, "p2", engine.question[3])
        answer(engine, "p0", engine.question[3])
        answer(engine, "p1", engine.question[3])
        engine.tick(0.0)
        assert engine.winner_id == "p2"
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.phase == "summary"
        assert engine.public_state()["winnerID"] == "p2"
        results = engine.results()
        assert results[0]["playerID"] == "p2" and results[0]["rank"] == 1
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.is_over()

    def test_same_question_tie_at_the_top_goes_to_the_fastest(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = self._to_finale()
        engine.rungs.update({"p0": engine.TOWER_HEIGHT - 1, "p1": engine.TOWER_HEIGHT - 1})
        to_phase(engine, "finale_question")
        answer(engine, "p1", engine.question[3])
        clock.advance(1.0)
        answer(engine, "p0", engine.question[3])
        engine.deadline = 0.0
        engine.tick(0.0)
        assert engine.winner_id == "p1"

    def test_highest_after_the_last_question_wins(self):
        engine, roster = self._to_finale(scores={"p0": 100, "p1": 5000, "p2": 0})
        engine.rungs = {"p0": 0, "p1": 0, "p2": 0}
        asked = 0
        while engine.phase != "summary":
            to_phase(engine, "finale_question")
            asked += 1
            answer(engine, "p0", engine.question[3] if asked <= 3 else wrong_index(engine))
            engine.deadline = 0.0
            engine.tick(0.0)            # -> finale_reveal
            engine.deadline = 0.0
            engine.tick(0.0)            # -> next question or summary
        assert asked == engine.FINALE_QUESTIONS
        # p0 climbed 3 then slipped back down to 0; p1 stayed on 0 with the
        # bigger score, so score breaks the tie.
        assert engine.winner_id == "p1"
        assert engine.results()[0]["playerID"] == "p1"


# ---- question sources ----------------------------------------------------------


class TestSources:
    def test_custom_questions_skip_the_vote(self):
        engine, roster = make(players=2, seeds=SEEDS[:5])
        assert engine.custom and engine._pack == "seeded"
        seen = []
        for _ in range(100):
            if engine.is_over():
                break
            engine.deadline = 0.0
            engine.tick(0.0)
            seen.append(engine.phase)
        assert "category_vote" not in seen
        assert engine.total_rounds == 5
        assert engine.public_state()["quizName"] == "Your quiz"
        # All five custom questions were played, in order.
        history = engine.room.question_history[("seeded", "trivia")]
        assert history == [f"Seeded question {i}?" for i in range(5)]

    def test_custom_quiz_first_question_is_the_first_seed(self):
        engine, _ = make(players=2, seeds=SEEDS)
        to_phase(engine, "question")
        assert engine.question[1] == "Seeded question 0?"
        assert engine.question[0] == "Your quiz"
        # A long custom quiz feeds the finale from its leftover questions.
        assert len(engine.finale_pool) == engine.FINALE_QUESTIONS

    def test_topic_name_is_the_quiz_name(self):
        engine, _ = make(players=2, seeds=SEEDS[:3], topic="Cricket")
        assert engine.quiz_name == "Cricket"
        to_phase(engine, "question")
        assert engine.public_state()["category"] == "Cricket"

    @pytest.mark.parametrize("pack", ["te", "hi"])
    def test_language_packs_still_play(self, pack):
        from games.native_hub.engines.content_packs import questions_for
        engine, _ = make(players=2, pack=pack)
        bank = questions_for(pack, "trivia")
        to_phase(engine, "category_vote")
        assert all(c in {q[0] for q in bank} | {trivia_show.MIXED_CATEGORY}
                   for c in engine.categories)
        to_phase(engine, "question")
        assert engine.question in bank


# ---- bots ------------------------------------------------------------------------


class TestBots:
    def test_bots_play_a_whole_show(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make(players=1, bots_count=3)
        acted = set()
        for _ in range(2000):
            if engine.is_over():
                break
            clock.advance(0.5)
            engine.tick(0.5)
            for p in engine.room.players:
                if p.is_bot:
                    act = bots.maybe_bot_action(engine, p)
                    if act is not None:
                        verb, payload = act
                        acted.add(verb)
                        engine.handle_action(p.id, verb, payload)
        assert engine.is_over()
        assert {"vote_category", "pick_power", "answer"} <= acted
        results = engine.results()
        assert [r["rank"] for r in results] == [1, 2, 3, 4]

    def test_bot_policy_per_phase(self):
        engine, roster = make(players=2, bots_count=1)
        bot = roster[-1]
        assert bots._policy_trivia(engine, bot.id) is None        # intro
        to_phase(engine, "category_vote")
        verb, data = bots._policy_trivia(engine, bot.id)
        assert verb == "vote_category" and 0 <= data["index"] < 3
        to_phase(engine, "power_pick")
        verb, data = bots._policy_trivia(engine, bot.id)
        assert verb == "pick_power"
        engine.handle_action(bot.id, verb, data)
        assert bot.id in engine.power_picks
        assert engine.power_picks[bot.id].get("targetID") != bot.id
        to_phase(engine, "question")
        verb, data = bots._policy_trivia(engine, bot.id)
        engine.handle_action(bot.id, verb, data)
        assert bot.id in engine.answered


def test_summary_tells_each_phone_its_placing():
    engine, roster = make(players=3)
    engine.scores.update({"p0": 100, "p1": 900, "p2": 500})
    engine.question_no = engine.total_rounds
    to_phase(engine, "finale_intro")
    engine.rungs.update({"p0": 0, "p1": 0, "p2": engine.TOWER_HEIGHT - 1})
    to_phase(engine, "finale_question")
    answer(engine, "p2", engine.question[3])
    to_phase(engine, "summary")
    assert engine.private_state("p2")["youWon"] is True
    assert engine.private_state("p2")["placement"] == 1
    assert engine.private_state("p1")["youWon"] is False
    assert engine.private_state("p1")["winnerName"] == "P2"
    assert {engine.private_state(p.id)["placement"] for p in roster} == {1, 2, 3}
