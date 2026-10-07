"""Travel Mode engines: story_chain, plus the travel playlist.

twenty_questions and hot_takes moved to engines/talk.py as TV + phone
games (tests/test_talk_games.py); this file only checks that the old
travel import path still resolves to them.
"""

import json
import random
import time

import pytest

from games.native_hub.engines import travel
from games.native_hub.engines.travel import (
    STORY_FUNNIEST_BONUS,
    STORY_POINTS_PER_SENTENCE,
    STORY_POINTS_PER_VOTE,
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
