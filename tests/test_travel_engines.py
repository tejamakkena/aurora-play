"""Travel Mode engines: story_chain, twenty_questions, hot_takes.

Covers the full conversational flow of each game: turn order, scoring,
phase transitions, privacy (the twenty_questions secret never leaks into
public_state), and the edge cases the car asks for -- an empty sentence,
a give-up, and a timer running out.
"""

import json
import random
import time

import pytest

from games.native_hub.engines import travel
from games.native_hub.engines.travel import (
    HOT_TAKES,
    HOT_TAKES_AWARD_POINTS,
    STORY_FUNNIEST_BONUS,
    STORY_POINTS_PER_SENTENCE,
    STORY_POINTS_PER_VOTE,
    TWENTY_BASE_POINTS,
    TWENTY_MAX_QUESTIONS,
    TWENTY_POINTS_PER_UNUSED,
    TWENTY_THINGS,
    HotTakesEngine,
    StoryChainEngine,
    TwentyQuestionsEngine,
    next_travel_game,
)
from games.native_hub.registry import ENGINES, engine_for
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(game_id, players=4, seed=7):
    random.seed(seed)
    cls = ENGINES[game_id]
    registry = RoomRegistry()
    room = registry.create(game_id)
    count = min(max(cls.min_players, players), cls.max_players)
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(count)]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def host(roster):
    roster[0].is_host = True
    return roster[0].id


@pytest.fixture(autouse=True)
def isolated_topic_cache(tmp_path, monkeypatch):
    """The topic cache is process-global: isolate it per test and keep the
    repo tree clean (no data/topic_cache.json written by tests)."""
    import games.topic_gen as tg
    monkeypatch.setenv("TOPIC_CACHE_PATH", str(tmp_path / "topic_cache.json"))
    tg._CACHE.clear()
    yield
    tg._CACHE.clear()


# ---------------------------------------------------------------------------
# registration + playlist
# ---------------------------------------------------------------------------

class TestTravelRegistry:
    def test_all_three_travel_engines_registered(self):
        assert engine_for("story_chain") is StoryChainEngine
        assert engine_for("twenty_questions") is TwentyQuestionsEngine
        assert engine_for("hot_takes") is HotTakesEngine

    def test_travel_engines_implement_the_contract(self):
        for gid in ("story_chain", "twenty_questions", "hot_takes"):
            engine, roster = make(gid)
            assert engine.game_id == gid
            assert engine.is_over() is False
            assert engine.public_state()
            for p in roster:
                assert engine.private_state(p.id)  # non-empty, never raises

    def test_state_is_json_serialisable(self):
        for gid in ("story_chain", "twenty_questions", "hot_takes"):
            engine, _ = make(gid)
            json.dumps(engine.public_state())

    def test_playlist_order(self):
        assert travel.TRAVEL_PLAYLIST == [
            "trivia", "most_likely_to", "story_chain",
            "twenty_questions", "hot_takes",
        ]

    def test_playlist_next_steps_forward(self):
        assert next_travel_game("trivia") == "most_likely_to"
        assert next_travel_game("story_chain") == "twenty_questions"
        assert next_travel_game("twenty_questions") == "hot_takes"

    def test_playlist_wraps_at_the_end(self):
        assert next_travel_game("hot_takes") == "trivia"

    def test_playlist_starts_at_the_beginning_for_unknown_or_none(self):
        assert next_travel_game(None) == "trivia"
        assert next_travel_game("not_a_game") == "trivia"


# ---------------------------------------------------------------------------
# story_chain
# ---------------------------------------------------------------------------

class TestStoryChain:
    def _play_adding(self, engine, roster):
        """Play the whole adding phase: everyone adds two sentences."""
        for round_no in range(2):
            for p in roster:
                assert engine.is_my_turn(p.id)
                engine.handle_action(p.id, "add_sentence",
                                     {"sentence": f"Sentence {round_no} by {p.name}."})
        return engine

    def test_turn_order_rotates(self):
        engine, roster = make("story_chain")
        assert engine.is_my_turn("p0")
        engine.handle_action("p0", "add_sentence", {"sentence": "Once upon a time."})
        assert engine.is_my_turn("p1")
        engine.handle_action("p1", "add_sentence", {"sentence": "A dragon woke up."})
        assert engine.is_my_turn("p2")

    def test_story_accumulates_and_counts(self):
        engine, roster = make("story_chain")
        engine.handle_action("p0", "add_sentence", {"sentence": "Once upon a time."})
        state = engine.public_state()
        assert state["sentenceCount"] == 1
        assert state["story"][0]["text"] == "Once upon a time."
        assert state["story"][0]["name"] == "P0"
        assert "Once upon a time." in state["storyText"]
        assert state["targetSentences"] == 8  # 4 players x 2 sentences

    def test_vote_phase_opens_when_target_reached(self):
        engine, roster = make("story_chain")
        self._play_adding(engine, roster)
        assert engine.phase == "vote"
        state = engine.public_state()
        assert state["sentenceCount"] == 8
        assert "vote" in state["hostPrompt"].lower()

    def test_voting_and_scoring(self):
        engine, roster = make("story_chain")
        self._play_adding(engine, roster)
        host(roster)
        # Everyone votes for p1; p1 also votes for p2.
        for p in roster:
            engine.handle_action(p.id, "vote", {"targetID": "p1" if p.id != "p1" else "p2"})
        engine.handle_action("p0", "reveal", {})
        assert engine.is_over()
        results = {r["playerID"]: r["score"] for r in engine.results()}
        p1_votes = 3
        # 2 sentences x sentence points + 3 votes x vote points + funniest bonus
        assert results["p1"] == (2 * STORY_POINTS_PER_SENTENCE
                                 + p1_votes * STORY_POINTS_PER_VOTE
                                 + STORY_FUNNIEST_BONUS)
        assert results["p2"] == (2 * STORY_POINTS_PER_SENTENCE
                                 + 1 * STORY_POINTS_PER_VOTE)
        top = [r for r in engine.public_state()["roundResults"] if r["funniest"]]
        assert len(top) == 1 and top[0]["playerID"] == "p1"

    def test_empty_sentence_rejected(self):
        engine, roster = make("story_chain")
        engine.handle_action("p0", "add_sentence", {"sentence": "   "})
        assert engine.public_state()["sentenceCount"] == 0
        assert engine.is_my_turn("p0")  # turn not consumed

    def test_out_of_turn_rejected(self):
        engine, roster = make("story_chain")
        engine.handle_action("p2", "add_sentence", {"sentence": "Not my turn."})
        assert engine.public_state()["sentenceCount"] == 0
        assert engine.is_my_turn("p0")

    def test_self_vote_rejected(self):
        engine, roster = make("story_chain")
        self._play_adding(engine, roster)
        engine.handle_action("p0", "vote", {"targetID": "p0"})
        assert engine.public_state()["votesSoFar"] == 0

    def test_ballot_stays_secret_until_reveal(self):
        engine, roster = make("story_chain")
        self._play_adding(engine, roster)
        engine.handle_action("p0", "vote", {"targetID": "p1"})
        state = engine.public_state()
        assert state["votesSoFar"] == 1
        assert state["roundResults"] == []

    def test_turn_timeout_skips_to_next_player(self):
        engine, roster = make("story_chain")
        engine.deadline = 0.0001
        time.sleep(0.01)
        engine.tick(1.0)
        assert engine.is_my_turn("p1")
        assert engine.public_state()["sentenceCount"] == 0

    def test_leave_during_adding_passes_the_turn(self):
        engine, roster = make("story_chain")
        roster[0].connected = False
        engine.on_player_leave("p0")
        assert engine.is_my_turn("p1")

    def test_ignores_junk_actions(self):
        engine, roster = make("story_chain")
        engine.handle_action("p0", "explode", {})
        engine.handle_action("nobody", "add_sentence", {"sentence": "x"})
        assert engine.public_state()["sentenceCount"] == 0


# ---------------------------------------------------------------------------
# twenty_questions
# ---------------------------------------------------------------------------

class TestTwentyQuestions:
    def test_secret_is_private_to_the_answerer(self):
        engine, roster = make("twenty_questions")
        pub = engine.public_state()
        assert "secret" not in pub
        priv_answerer = engine.private_state("p0")
        priv_other = engine.private_state("p1")
        assert priv_answerer["secret"]
        assert "secret" not in priv_other
        assert pub["answererID"] == "p0"

    def test_content_pack_shapes(self):
        assert set(TWENTY_THINGS) == {"places", "foods", "movies", "animals"}
        for cat, items in TWENTY_THINGS.items():
            assert len(items) == 15, cat
            assert all(isinstance(i, str) and i and len(i) < 40 for i in items)

    def test_ask_answer_flow(self):
        engine, roster = make("twenty_questions")
        engine.handle_action("p1", "question", {"text": "Is it bigger than a car?"})
        engine.handle_action("p0", "answer", {"value": "yes"})
        state = engine.public_state()
        assert state["questionsAsked"] == 1
        assert state["questions"][0] == {"text": "Is it bigger than a car?", "answer": "yes"}
        assert state["questionsLeft"] == TWENTY_MAX_QUESTIONS - 1

    def test_answerer_cannot_ask_and_asker_cannot_answer(self):
        engine, roster = make("twenty_questions")
        engine.handle_action("p0", "question", {"text": "Can I ask my own?"})
        engine.handle_action("p1", "answer", {"value": "yes"})
        assert engine.public_state()["questionsAsked"] == 0

    def test_must_answer_before_next_question(self):
        engine, roster = make("twenty_questions")
        engine.handle_action("p1", "question", {"text": "First?"})
        engine.handle_action("p2", "question", {"text": "Second?"})
        assert engine.public_state()["questionsAsked"] == 1

    def test_only_yes_or_no_accepted(self):
        engine, roster = make("twenty_questions")
        engine.handle_action("p1", "question", {"text": "First?"})
        engine.handle_action("p0", "answer", {"value": "maybe"})
        assert engine.public_state()["questions"][0]["answer"] is None
        engine.handle_action("p0", "answer", {"value": "no"})
        assert engine.public_state()["questions"][0]["answer"] == "no"

    def test_correct_guess_scores_and_reveals(self):
        engine, roster = make("twenty_questions")
        secret = engine.private_state("p0")["secret"]
        engine.handle_action("p1", "question", {"text": "Is it famous?"})
        engine.handle_action("p0", "answer", {"value": "yes"})
        engine.handle_action("p2", "guess", {"text": secret})
        state = engine.public_state()
        assert state["phase"] == "reveal"
        assert state["secret"] == secret
        asked = 1
        expected = TWENTY_BASE_POINTS + TWENTY_POINTS_PER_UNUSED * (TWENTY_MAX_QUESTIONS - asked)
        assert engine.scores["p2"] == expected

    def test_fewer_questions_means_more_points(self):
        e1, _ = make("twenty_questions", seed=11)
        e2, _ = make("twenty_questions", seed=11)
        assert e1.private_state("p0")["secret"] == e2.private_state("p0")["secret"]
        e1.handle_action("p1", "guess", {"text": e1.private_state("p0")["secret"]})
        e2.handle_action("p1", "question", {"text": "Is it famous?"})
        e2.handle_action("p0", "answer", {"value": "yes"})
        e2.handle_action("p1", "guess", {"text": e2.private_state("p0")["secret"]})
        assert e1.scores["p1"] > e2.scores["p1"]

    def test_guess_matching_is_case_and_punctuation_insensitive(self):
        engine, roster = make("twenty_questions")
        secret = engine.private_state("p0")["secret"]
        engine.handle_action("p1", "guess", {"text": f"  {secret.upper()}!! "})
        assert engine.public_state()["phase"] == "reveal"

    def test_wrong_guess_keeps_playing(self):
        engine, roster = make("twenty_questions")
        engine.handle_action("p1", "guess", {"text": "A flying toaster"})
        assert engine.public_state()["phase"] == "play"
        assert engine.scores["p1"] == 0

    def test_give_up_reveals_with_no_points(self):
        engine, roster = make("twenty_questions")
        secret = engine.private_state("p0")["secret"]
        engine.handle_action("p1", "give_up", {})
        state = engine.public_state()
        assert state["phase"] == "reveal"
        assert state["secret"] == secret
        assert sum(engine.scores.values()) == 0

    def test_twentieth_question_ends_the_round(self):
        engine, roster = make("twenty_questions", players=2)
        for i in range(TWENTY_MAX_QUESTIONS):
            engine.handle_action("p1", "question", {"text": f"Question {i}?"})
            engine.handle_action("p0", "answer", {"value": "no"})
        assert engine.public_state()["phase"] == "reveal"
        assert "secret" in engine.public_state()

    def test_rounds_rotate_the_answerer_and_end(self):
        engine, roster = make("twenty_questions", players=3)
        host(roster)
        for expected_answerer in ("p0", "p1", "p2"):
            assert engine.public_state()["answererID"] == expected_answerer
            engine.handle_action("p1" if expected_answerer != "p1" else "p2",
                                 "give_up", {})
            assert engine.public_state()["phase"] == "reveal"
            engine.handle_action("p0", "next_round", {})
        assert engine.is_over()
        assert engine.results()
        json.dumps(engine.results())

    def test_secrets_do_not_repeat_within_a_game(self):
        engine, roster = make("twenty_questions", players=8)
        host(roster)
        seen = []
        for _ in range(8):
            seen.append(engine.private_state(engine.public_state()["answererID"])["secret"])
            engine.handle_action("p0", "give_up", {})
            engine.handle_action("p0", "next_round", {})
        assert len(set(seen)) == 8

    def test_answerer_leaving_reveals_so_the_game_moves_on(self):
        engine, roster = make("twenty_questions")
        roster[0].connected = False
        engine.on_player_leave("p0")
        assert engine.public_state()["phase"] == "reveal"
        assert "secret" in engine.public_state()

    def test_topic_generates_secrets_when_available(self, monkeypatch):
        import games.topic_gen as tg
        monkeypatch.setattr(tg, "_llm_batch",
                            lambda kind, topic, count, exclude=(): ["Tollywood Star", "Film City"])
        engine, roster = make("twenty_questions")
        engine.room.topic = "Tollywood movies"
        engine.used.clear()
        category, secret = engine._pick_secret()
        assert category == "Tollywood movies"
        assert secret in ("Tollywood Star", "Film City")

    def test_topic_failure_falls_back_to_bundled(self, monkeypatch):
        import games.topic_gen as tg
        def boom(kind, topic, count, exclude=()):
            raise tg._GenError("no key")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        engine, roster = make("twenty_questions")
        engine.room.topic = "Tollywood movies"
        engine.used.clear()
        category, secret = engine._pick_secret()
        assert category in TWENTY_THINGS
        assert secret in TWENTY_THINGS[category]


# ---------------------------------------------------------------------------
# hot_takes
# ---------------------------------------------------------------------------

class TestHotTakes:
    def test_prompts_are_tts_clean(self):
        assert len(HOT_TAKES) >= 20
        for prompt in HOT_TAKES:
            assert prompt == prompt.strip()
            assert prompt.endswith("?")
            for bad in ("w/", "*", "_", "#", "http"):
                assert bad not in prompt, f"{bad!r} in {prompt!r}"

    def test_discuss_phase_picks_a_prompt(self):
        engine, roster = make("hot_takes")
        assert engine.phase == "discuss"
        state = engine.public_state()
        from games import content_service
        assert state["prompt"] in content_service.all_items("hot_take")
        assert state["secondsLeft"] > 0
        assert "hot take" in state["hostPrompt"].lower()

    def test_prompts_do_not_repeat(self):
        engine, roster = make("hot_takes")
        host(roster)
        seen = [engine.public_state()["prompt"]]
        for _ in range(4):
            engine.enter_phase("award")
            engine.handle_action("p0", "award", {"targetID": "p1"})
            seen.append(engine.public_state()["prompt"])
        assert len(set(seen)) == 5

    def test_host_awards_points_and_round_advances(self):
        engine, roster = make("hot_takes")
        host(roster)
        engine.enter_phase("award")
        engine.handle_action("p0", "award", {"targetID": "p2"})
        assert engine.scores["p2"] == HOT_TAKES_AWARD_POINTS
        assert engine.phase == "discuss"   # next round
        assert engine.round == 2
        state = engine.public_state()
        assert state["awardedToID"] is None  # cleared for the new round

    def test_only_host_awards_when_a_host_exists(self):
        engine, roster = make("hot_takes")
        host(roster)
        engine.enter_phase("award")
        engine.handle_action("p1", "award", {"targetID": "p1"})
        assert engine.scores["p1"] == 0
        assert engine.phase == "award"     # no advance without the host

    def test_award_rejected_in_discuss_phase(self):
        engine, roster = make("hot_takes")
        host(roster)
        engine.handle_action("p0", "award", {"targetID": "p1"})
        assert engine.scores["p1"] == 0

    def test_timer_end_moves_to_award(self):
        engine, roster = make("hot_takes")
        engine.deadline = 0.0001
        time.sleep(0.01)
        engine.tick(1.0)
        assert engine.phase == "award"

    def test_full_game_completes_and_ranks(self):
        engine, roster = make("hot_takes")
        host(roster)
        for rnd in range(5):
            engine.enter_phase("award")
            engine.handle_action("p0", "award", {"targetID": f"p{rnd % 4}"})
        assert engine.is_over()
        results = engine.results()
        assert results[0]["playerID"] == "p0"   # p0 awarded twice
        assert results[0]["score"] == 2 * HOT_TAKES_AWARD_POINTS
        json.dumps(engine.results())

    def test_ignores_junk_actions(self):
        engine, roster = make("hot_takes")
        engine.handle_action("nobody", "award", {"targetID": "p1"})
        engine.handle_action("p0", "award", {"targetID": "nobody"})
        assert sum(engine.scores.values()) == 0

    def test_topic_generates_prompt_when_available(self, monkeypatch):
        import games.topic_gen as tg
        monkeypatch.setattr(tg, "_llm_batch",
                            lambda kind, topic, count, exclude=(): ["Is cricket better than football?"])
        engine, roster = make("hot_takes")
        engine.room.topic = "cricket"
        engine.begin_phase("discuss")
        assert engine.prompt == "Is cricket better than football?"
