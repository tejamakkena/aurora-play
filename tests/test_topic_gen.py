"""Live topic-based generation: games/topic_gen.py.

Covers the validation gate (bad generations are rejected), the chain
(session dedupe -> cache -> LLM batch -> bundled fallback), cache hits
avoiding the API (mocked), the offline fallback, and the iOS endpoint
contract.
"""

import json

import pytest
from flask import Flask

import games.topic_gen as tg


@pytest.fixture(autouse=True)
def isolated_cache(tmp_path, monkeypatch):
    """Point the topic cache at a temp file and start with an empty cache."""
    monkeypatch.setenv("TOPIC_CACHE_PATH", str(tmp_path / "topic_cache.json"))
    tg._CACHE.clear()
    yield
    tg._CACHE.clear()


def good_question(i=0):
    return {
        "question": f"What is question number {i} about?",
        "options": ["Alpha", "Beta", "Gamma", "Delta"],
        "correct_answer": i % 4,
    }


def mock_llm(monkeypatch, items):
    """Pretend the model returned ``items`` (raw, unvalidated)."""
    calls = []
    def fake(kind, topic, count, exclude=()):
        calls.append((kind, topic, count))
        return list(items)
    monkeypatch.setattr(tg, "_llm_batch", fake)
    return calls


def _batch_url(calls):
    """The api.php batch request (a token request may come first)."""
    return next(c for c in calls if "api.php" in c)


def opentdb_result(question, correct, incorrect, category="Sports"):
    return {"category": category, "type": "multiple", "difficulty": "easy",
            "question": question, "correct_answer": correct,
            "incorrect_answers": list(incorrect)}


def mock_opentdb(monkeypatch, payload=None, exc=None):
    """Pretend api.php returned ``payload`` (or raised ``exc``)."""
    calls = []
    class FakeResp:
        def __init__(self, data):
            self._data = data
        def read(self):
            return json.dumps(self._data).encode("utf-8")
        def __enter__(self):
            return self
        def __exit__(self, *a):
            return False
    def fake(req, timeout=None):
        calls.append(req.full_url)
        if exc is not None:
            raise exc
        return FakeResp(payload)
    monkeypatch.setattr(tg.urllib.request, "urlopen", fake)
    return calls


# ---------------------------------------------------------------------------
# validation
# ---------------------------------------------------------------------------

class TestValidation:
    def test_good_question_accepted(self):
        ok, _ = tg.validate_question(good_question())
        assert ok

    @pytest.mark.parametrize("mutate", [
        lambda q: q.update({"options": ["A", "B", "C"]}),          # 3 options
        lambda q: q.update({"options": ["A", "B", "C", "D", "E"]}),  # 5 options
        lambda q: q.update({"correct_answer": 4}),                  # out of range
        lambda q: q.update({"correct_answer": -1}),                 # negative
        lambda q: q.update({"correct_answer": True}),               # bool not int
        lambda q: q.update({"options": ["Same", "same", "Other", "More"]}),  # dupes
        lambda q: q.update({"question": "Which emoji wins? \U0001F3C6"}),    # emoji
        lambda q: q.update({"question": "Pick *one* answer"}),      # markdown
        lambda q: q.update({"question": ""}),                       # empty
        lambda q: q.pop("options"),                                 # missing
    ])
    def test_bad_questions_rejected(self, mutate):
        q = good_question()
        mutate(q)
        ok, reason = tg.validate_question(q)
        assert not ok, f"accepted bad question ({reason}): {q}"

    def test_w_slash_rejected(self):
        q = good_question()
        q["options"][0] = "Tea w/ milk"
        ok, _ = tg.validate_question(q)
        assert not ok

    def test_validate_secret(self):
        ok, _ = tg.validate_secret("Eiffel Tower")
        assert ok
        ok, _ = tg.validate_secret("Bad \U0001F600 name")
        assert not ok
        ok, _ = tg.validate_secret("x" * 61)
        assert not ok

    def test_validate_hot_take(self):
        ok, _ = tg.validate_hot_take("Is a hot dog a sandwich?")
        assert ok
        ok, _ = tg.validate_hot_take("This is not a question.")
        assert not ok
        ok, _ = tg.validate_hot_take("Is cereal *really* soup?")
        assert not ok


# ---------------------------------------------------------------------------
# OpenTDB: topic -> category mapping
# ---------------------------------------------------------------------------

class TestTopicToCategory:
    @pytest.mark.parametrize("topic,expected", [
        ("Tollywood movies", 11),
        ("cricket", 21),
        ("  CRICKET  ", 21),
        ("world capitals", 22),
        ("board games", 16),
        ("video games", 15),
        ("anime", 31),
        ("cartoons", 32),
        ("mythology", 20),
        ("musicals", 13),
        ("cooking recipes", None),   # unmapped -> LLM
        ("quantum knitting", None),
        ("", 9),                     # empty -> General Knowledge
    ])
    def test_mapping(self, topic, expected):
        assert tg.topic_to_opentdb_category(topic) == expected

    def test_no_false_positives(self):
        # "art" must not fire on "earth"; "tv" must not fire on "festival".
        assert tg.topic_to_opentdb_category("earth science") == 17
        assert tg.topic_to_opentdb_category("festivals") is None
        assert tg.topic_to_opentdb_category("hotdog") is None


# ---------------------------------------------------------------------------
# OpenTDB: batch fetching
# ---------------------------------------------------------------------------

class TestOpenTDBBatch:
    def test_parses_and_decodes_entities(self, monkeypatch):
        calls = mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result(
                "Which team won the &quot;1983&quot; final?",
                "India", ["West Indies", "England", "Australia"])]})
        items = tg._opentdb_batch("cricket", 21, 1)
        assert len(items) == 1
        q = items[0]
        assert q["question"] == 'Which team won the "1983" final?'
        assert sorted(q["options"]) == ["Australia", "England", "India",
                                        "West Indies"]
        assert q["options"][q["correct_answer"]] == "India"
        ok, _ = tg.validate_question(q)
        assert ok
        assert "category=21" in _batch_url(calls)
        assert "type=multiple" in _batch_url(calls)
        assert "amount=" in _batch_url(calls)   # one batched request

    def test_invalid_results_dropped(self, monkeypatch):
        mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result("Only three?", "A", ["B", "C"]),
                        opentdb_result("Good?", "A", ["B", "C", "D"])]})
        items = tg._opentdb_batch("cricket", 21, 2)
        assert [q["question"] for q in items] == ["Good?"]

    def test_bad_response_code_raises(self, monkeypatch):
        mock_opentdb(monkeypatch, {"response_code": 1, "results": []})
        with pytest.raises(tg._GenError):
            tg._opentdb_batch("cricket", 21, 2)

    def test_network_error_raises(self, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("offline"))
        with pytest.raises(tg._GenError):
            tg._opentdb_batch("cricket", 21, 2)


# ---------------------------------------------------------------------------
# chain: cache -> opentdb/llm -> bundled
# ---------------------------------------------------------------------------

class TestChain:
    def test_cache_hit_avoids_the_api(self, monkeypatch):
        tg._cache_add("cricket", "questions", [good_question(1), good_question(2)])
        def boom(kind, topic, count, exclude=()):
            raise AssertionError("API must not be called on a cache hit")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        items, source = tg._fetch("questions", "cricket", 2)
        assert source == "cache"
        assert [i["question"] for i in items] == [
            "What is question number 1 about?",
            "What is question number 2 about?",
        ]

    def test_cache_miss_calls_llm_once_then_caches(self, monkeypatch):
        # "quantum knitting" maps to no OpenTDB category -> LLM path.
        calls = mock_llm(monkeypatch, [good_question(0), good_question(1)])
        items, source = tg._fetch("questions", "quantum knitting", 2)
        assert source == "llm"
        assert len(calls) == 1                       # one batch, not per question
        assert calls[0][1] == "quantum knitting"
        # Second call is a cache hit: the API stays quiet.
        def boom(kind, topic, count, exclude=()):
            raise AssertionError("second call must be a cache hit")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        items2, source2 = tg._fetch("questions", "quantum knitting", 2)
        assert source2 == "cache"
        assert items2 == items

    def test_invalid_generations_are_dropped_not_regenerated(self, monkeypatch):
        bad = good_question(9)
        bad["options"] = ["Only", "Three", "Here"]   # invalid: 3 options
        mock_llm(monkeypatch, [good_question(0), bad])
        items, source = tg._fetch("questions", "quantum knitting", 1)
        assert source == "llm"
        assert len(items) == 1
        assert items[0]["question"] == "What is question number 0 about?"

    @pytest.mark.parametrize("topic", ["cricket", "quantum knitting"])
    def test_api_failure_falls_back_to_bundled(self, monkeypatch, topic):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        def boom(kind, topic, count, exclude=()):
            raise tg._GenError("offline")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        items, source = tg._fetch("questions", topic, 5)
        assert source == "bundled"
        assert len(items) == 5
        for q in items:
            ok, _ = tg.validate_question(q)
            assert ok

    def test_missing_api_key_falls_back(self, monkeypatch):
        # Unmapped topic -> LLM path, which needs the key.
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        items, source = tg._fetch("questions", "quantum knitting", 3)
        assert source == "bundled"
        assert len(items) == 3

    def test_session_dedupe_filters_cache(self, monkeypatch):
        tg._cache_add("cricket", "questions",
                      [good_question(0), good_question(1), good_question(2)])
        mock_opentdb(monkeypatch, exc=OSError("down"))
        def boom(kind, topic, count, exclude=()):
            raise tg._GenError("force the fallback path")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        asked = ["What is question number 0 about?",
                 "What is question number 1 about?"]
        # Only one cached question is fresh; a partial on-topic batch is
        # returned short rather than mixed with bundled questions.
        items, source = tg._fetch("questions", "cricket", 2,
                                  session_history=asked)
        assert source == "cache"
        assert [i["question"] for i in items] == \
            ["What is question number 2 about?"]

    def test_bundled_secrets_and_hot_takes(self, monkeypatch):
        def boom(kind, topic, count, exclude=()):
            raise tg._GenError("offline")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        secrets, source = tg._fetch("secrets", "cricket", 4)
        assert source == "bundled"
        assert all(tg.validate_secret(s)[0] for s in secrets)
        takes, source = tg._fetch("hot_takes", "cricket", 4)
        assert source == "bundled"
        assert all(tg.validate_hot_take(t)[0] for t in takes)

    def test_norm_topic_canonicalizes(self):
        assert tg.norm_topic("  Tollywood   MOVIES ") == "tollywood movies"

    def test_question_dict_to_tuple(self):
        cat, q, opts, idx = tg.question_dict_to_tuple("cricket", good_question(2))
        assert cat == "cricket"
        assert q == "What is question number 2 about?"
        assert opts == ["Alpha", "Beta", "Gamma", "Delta"]
        assert idx == 2


class TestQuestionPriority:
    """opentdb (mapped) -> llm (unmapped) -> bundled. Strict tiers."""

    def test_mapped_topic_uses_opentdb_not_llm(self, monkeypatch):
        calls = mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result("Q?", "A", ["B", "C", "D"])]})
        def boom(kind, topic, count, exclude=()):
            raise AssertionError("LLM must not be called for a mapped topic")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        items, source = tg._fetch("questions", "cricket", 1)
        assert source == "opentdb"
        assert len(items) == 1
        assert calls  # exactly one batched request

    def test_opentdb_failure_skips_llm_straight_to_bundled(self, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        def boom(kind, topic, count, exclude=()):
            raise AssertionError("mapped topics never burn LLM budget")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        items, source = tg._fetch("questions", "cricket", 3)
        assert source == "bundled"
        assert len(items) == 3

    def test_unmapped_topic_uses_llm_not_opentdb(self, monkeypatch):
        def boom_urlopen(req, timeout=None):
            raise AssertionError("OpenTDB must not be called for unmapped topics")
        monkeypatch.setattr(tg.urllib.request, "urlopen", boom_urlopen)
        calls = mock_llm(monkeypatch, [good_question(0)])
        items, source = tg._fetch("questions", "quantum knitting", 1)
        assert source == "llm"
        assert calls and calls[0][1] == "quantum knitting"

    def test_empty_topic_serves_general_knowledge_live(self, monkeypatch):
        calls = mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result("Q?", "A", ["B", "C", "D"])]})
        items, source = tg._fetch("questions", "   ", 2)
        assert source == "opentdb"
        assert "category=9" in _batch_url(calls)

    def test_empty_topic_opentdb_down_to_bundled(self, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        items, source = tg._fetch("questions", "", 2)
        assert source == "bundled"
        assert len(items) == 2


# ---------------------------------------------------------------------------
# iOS endpoint contract
# ---------------------------------------------------------------------------

@pytest.fixture()
def client():
    app = Flask(__name__)
    app.register_blueprint(tg.topic_bp, url_prefix="/api/travel")
    return app.test_client()


class TestEndpoint:
    def test_questions_endpoint(self, client, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        resp = client.get("/api/travel/questions?topic=&count=2")
        assert resp.status_code == 200
        body = resp.get_json()
        assert body["success"] is True
        assert body["source"] == "bundled"   # OpenTDB mocked down below
        assert body["fallback"] is True
        assert len(body["questions"]) == 2
        q = body["questions"][0]
        assert set(q) == {"question", "options", "correct_answer"}
        assert len(q["options"]) == 4

    def test_secrets_endpoint(self, client):
        resp = client.get("/api/travel/secrets?count=3")
        body = resp.get_json()
        assert body["success"] is True
        assert len(body["secrets"]) == 3

    def test_hot_takes_endpoint(self, client):
        resp = client.get("/api/travel/hot_takes?topic=cricket&count=3")
        body = resp.get_json()
        assert body["success"] is True
        assert len(body["hot_takes"]) == 3
        assert all(h.endswith("?") for h in body["hot_takes"])

    def test_count_is_clamped(self, client, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        resp = client.get("/api/travel/questions?topic=cricket&count=999")
        body = resp.get_json()
        assert len(body["questions"]) <= 20
        resp = client.get("/api/travel/questions?topic=cricket&count=bogus")
        assert resp.get_json()["success"] is True

    def test_fallback_flag_true_when_bundled(self, client, monkeypatch):
        # OpenTDB down and no API key: bundled fallback, flagged.
        mock_opentdb(monkeypatch, exc=OSError("down"))
        resp = client.get("/api/travel/questions?topic=&count=2")
        body = resp.get_json()
        assert body["source"] == "bundled"
        assert body["fallback"] is True

    def test_fallback_flag_false_on_live_generation(self, client, monkeypatch):
        # Unmapped topic -> LLM path.
        mock_llm(monkeypatch, [good_question(0), good_question(1)])
        resp = client.get("/api/travel/questions?topic=quantum+knitting&count=2")
        body = resp.get_json()
        assert body["source"] == "llm"
        assert body["fallback"] is False
        assert len(body["questions"]) == 2

    def test_fallback_flag_false_on_opentdb(self, client, monkeypatch):
        mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result("Q?", "A", ["B", "C", "D"])]})
        resp = client.get("/api/travel/questions?topic=cricket&count=1")
        body = resp.get_json()
        assert body["source"] == "opentdb"
        assert body["fallback"] is False
        assert body["questions"][0]["options"][body["questions"][0]["correct_answer"]] == "A"


# ---------------------------------------------------------------------------
# engine integration
# ---------------------------------------------------------------------------

class TestTriviaTopicIntegration:
    def _trivia(self, topic="", seed=7):
        import random
        from games.native_hub.engines.legacy_social import TriviaEngine
        from utils.room_manager import RoomRegistry, RoomState
        random.seed(seed)
        registry = RoomRegistry()
        room = registry.create("trivia")
        room.topic = topic
        roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(3)]

        class _Null:
            def state(self): pass
            def room_update(self): pass
            def error(self, *a, **k): pass

        engine = TriviaEngine(room, _Null())
        engine.start(roster)
        return engine, room, roster

    def test_topic_questions_seed_the_pool(self, monkeypatch):
        calls = mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [
                opentdb_result(
                    "Which country won the &quot;1983&quot; Cricket World Cup?",
                    "India", ["West Indies", "England", "Australia"]),
                opentdb_result("How many players are on a cricket team?",
                               "11", ["10", "12", "9"])]})
        engine, room, _ = self._trivia(topic="cricket")
        assert engine._pack == "topic:cricket"
        assert engine.total_rounds == 2
        assert engine.question[1] == \
            'Which country won the "1983" Cricket World Cup?'
        assert engine.question[0] == "cricket"
        assert "category=21" in _batch_url(calls)

    def test_topic_failure_uses_the_pack(self, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        def boom(kind, topic, count, exclude=()):
            raise tg._GenError("offline")
        monkeypatch.setattr(tg, "_llm_batch", boom)
        engine, room, _ = self._trivia(topic="cricket")
        assert engine._pack == "en"   # pack path, not the topic path

    def test_no_topic_uses_the_pack(self):
        engine, room, _ = self._trivia(topic="")
        assert engine._pack == "en"

    def test_asked_topic_questions_recorded_in_history(self, monkeypatch):
        mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result(
                "Which country won the &quot;1983&quot; Cricket World Cup?",
                "India", ["West Indies", "England", "Australia"])]})
        engine, room, _ = self._trivia(topic="cricket")
        assert 'Which country won the "1983" Cricket World Cup?' in \
            room.question_history.get(("topic:cricket", "trivia"), [])

    def test_seed_questions_win_over_topic_and_pack(self, monkeypatch):
        mock_opentdb(monkeypatch, exc=OSError("down"))
        engine, room, _ = self._trivia(topic="cricket")
        # direct engine-level injection (socket path covered in
        # test_native_hub.py)
        room2_seed = [{"question": "Seeded one?", "options": ["A", "B", "C", "D"],
                       "correct_answer": 2}]
        from games.native_hub.engines.legacy_social import TriviaEngine
        from utils.room_manager import RoomRegistry, RoomState
        import random
        random.seed(7)
        registry = RoomRegistry()
        room2 = registry.create("trivia")
        room2.topic = "cricket"
        room2.seed_questions = room2_seed
        roster = [room2.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(3)]

        class _Null:
            def state(self): pass
            def room_update(self): pass
            def error(self, *a, **k): pass

        engine2 = TriviaEngine(room2, _Null())
        engine2.start(roster)
        assert engine2._pack == "seeded"
        assert engine2.total_rounds == 1
        assert engine2.question[1] == "Seeded one?"
        assert engine2.question[3] == 2

    def test_empty_seeds_fall_through_to_topic(self, monkeypatch):
        mock_opentdb(monkeypatch, {
            "response_code": 0,
            "results": [opentdb_result("Q?", "A", ["B", "C", "D"])]})
        # _trivia never sets seed_questions: the topic path applies.
        engine, room, _ = self._trivia(topic="cricket")
        assert room.seed_questions == []
        assert engine._pack == "topic:cricket"


class TestExcludeParam:
    def test_exclude_filters_cached_questions(self, client):
        import json, urllib.parse
        tg._cache_add("cricket", "questions",
                      [good_question(0), good_question(1), good_question(2)])
        exclude = urllib.parse.quote(json.dumps(["What is question number 0 about?"]))
        resp = client.get(f"/api/travel/questions?topic=cricket&count=2&exclude={exclude}")
        body = resp.get_json()
        assert resp.status_code == 200
        got = [q["question"] for q in body["questions"]]
        assert "What is question number 0 about?" not in got
        assert got == ["What is question number 1 about?",
                       "What is question number 2 about?"]

    def test_exclude_malformed_is_ignored(self, client):
        resp = client.get("/api/travel/questions?topic=cricket&count=1&exclude=not-json{{")
        assert resp.status_code == 200
        assert resp.get_json()["success"] is True

    def test_exclude_empty_means_no_filtering(self, client):
        tg._cache_add("rugby", "questions", [good_question(5)])
        resp = client.get("/api/travel/questions?topic=rugby&count=1")
        body = resp.get_json()
        assert [q["question"] for q in body["questions"]] == \
            ["What is question number 5 about?"]
