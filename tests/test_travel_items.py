"""Travel Mode quizmaster items: games/travel_items.py.

Covers answer-based dedupe (the point of the module), validation of what
the model returns, the pool serving without model calls, the
OpenAI -> Gemini -> none chain, and the POST /api/travel/items contract.
"""

import json

import pytest
from flask import Flask

import games.travel_items as ti


@pytest.fixture(autouse=True)
def isolated_files(tmp_path, monkeypatch):
    monkeypatch.setenv("TRAVEL_ITEMS_POOL_PATH", str(tmp_path / "pool.json"))
    monkeypatch.setenv("TRAVEL_ITEMS_SERVED_PATH", str(tmp_path / "served.json"))
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)


def item(answer, prompt=None):
    return {
        "prompt": prompt or f"Which thing is called {answer.upper()[::-1]}?",
        "answer": answer,
        "accepts": [],
        "hint": "Think hard.",
        "fact": "Fun fact here.",
    }


def fake_generate(monkeypatch, batches):
    """Each call to the model returns the next batch (raw items)."""
    calls = []

    def fake(prompt):
        calls.append(prompt)
        return list(batches[min(len(calls) - 1, len(batches) - 1)])

    monkeypatch.setattr(ti, "_openai_batch", fake)
    return calls


# --------------------------------------------------------------------------
# answer keys
# --------------------------------------------------------------------------

@pytest.mark.parametrize("a,b", [
    ("a piano", "Piano!"),
    ("The Pianos", "piano"),
    ("echoes", "an echo"),
    ("Your Name", "name"),
])
def test_answer_key_matches_spoken_variants(a, b):
    assert ti.answer_key(a) == ti.answer_key(b)


def test_answer_key_keeps_double_s_words():
    assert ti.answer_key("glass") == "glass"
    assert ti.answer_key("grass") != ti.answer_key("gras")


# --------------------------------------------------------------------------
# validation
# --------------------------------------------------------------------------

def test_valid_item_passes():
    ok, reason = ti.validate_item(item("a piano", "What has keys but no locks?"))
    assert ok, reason


@pytest.mark.parametrize("patch", [
    {"answer": ""},
    {"prompt": "Has emoji \U0001F600?"},
    {"hint": "**bold** hint"},
    {"answer": "x" * 41},
    {"accepts": "piano"},
    {"fact": "see https://example.com"},
])
def test_invalid_items_are_rejected(patch):
    bad = item("a piano", "What has keys but no locks?")
    bad.update(patch)
    assert not ti.validate_item(bad)[0]


def test_item_that_gives_away_the_answer_is_rejected():
    giveaway = item("a piano", "What piano has keys?")
    assert not ti.validate_item(giveaway)[0]
    hint_giveaway = item("a piano", "What has keys but no locks?")
    hint_giveaway["hint"] = "It's a piano."
    assert not ti.validate_item(hint_giveaway)[0]


# --------------------------------------------------------------------------
# generation chain
# --------------------------------------------------------------------------

def test_prompt_lists_every_excluded_answer():
    prompt = ti.build_prompt("riddle", 12, ["piano", "egg", "towel"])
    assert "piano, egg, towel" in prompt


def test_generate_drops_answers_the_model_was_told_to_avoid(monkeypatch):
    fake_generate(monkeypatch, [[item("a piano"), item("a towel"), item("a comb")]])
    made, source = ti.generate("riddle", 12, ["piano", "towels"])
    assert source == "openai"
    assert [ti.answer_key(i["answer"]) for i in made] == ["comb"]


def test_generate_falls_back_to_gemini(monkeypatch):
    def broken(prompt):
        raise ti.GenError("no key")
    monkeypatch.setattr(ti, "_openai_batch", broken)
    monkeypatch.setattr(ti, "_gemini_batch", lambda prompt: [item("a comb")])
    made, source = ti.generate("riddle", 12, [])
    assert source == "gemini" and made[0]["answer"] == "a comb"


def test_generate_raises_when_no_model_is_configured():
    with pytest.raises(ti.GenError):
        ti.generate("quiz", 12, [])


def test_openai_request_shape(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    sent = {}

    class Resp:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self):
            content = json.dumps({"items": [item("a comb")]})
            return json.dumps({"choices": [{"message": {"content": content}}]}).encode()

    def fake_urlopen(req, timeout=None):
        sent["url"] = req.full_url
        sent["auth"] = req.headers.get("Authorization")
        sent["body"] = json.loads(req.data.decode())
        return Resp()

    monkeypatch.setattr(ti.urllib.request, "urlopen", fake_urlopen)
    raw = ti._openai_batch("make riddles")
    assert raw[0]["answer"] == "a comb"
    assert sent["url"].endswith("/v1/chat/completions")
    assert sent["auth"] == "Bearer sk-test"
    assert sent["body"]["response_format"] == {"type": "json_object"}


# --------------------------------------------------------------------------
# pool + per-device history
# --------------------------------------------------------------------------

def test_items_never_repeat_an_answer_for_the_same_device(monkeypatch):
    batch = [item(a) for a in ("a comb", "a towel", "a candle", "a stamp")]
    fake_generate(monkeypatch, [batch, [item("a mirror"), item("a map")]])
    first, _ = ti.get_items("riddle", 4, device="car-1")
    second, _ = ti.get_items("riddle", 4, device="car-1")
    a1 = {ti.answer_key(i["answer"]) for i in first}
    a2 = {ti.answer_key(i["answer"]) for i in second}
    assert len(a1) == 4
    assert a1.isdisjoint(a2)


def test_client_seen_answers_are_excluded_even_for_a_new_device(monkeypatch):
    fake_generate(monkeypatch, [[item("a comb"), item("a towel")]])
    items, _ = ti.get_items("riddle", 5, device="fresh", seen=["Combs", "a towel"])
    assert items == []


def test_pool_serves_other_devices_without_a_model_call(monkeypatch):
    calls = fake_generate(monkeypatch, [[item(a) for a in ("a comb", "a towel", "a stamp")]])
    ti.get_items("quiz", 3, device="car-1")
    assert len(calls) == 1
    items, source = ti.get_items("quiz", 3, device="car-2")
    assert source == "pool" and len(items) == 3
    assert len(calls) == 1


def test_model_call_excludes_pool_answers_so_the_pool_grows(monkeypatch):
    calls = fake_generate(monkeypatch, [[item("a comb")], [item("a stamp")]])
    ti.get_items("riddle", 1, device="car-1")
    ti.get_items("riddle", 1, device="car-1")
    assert "comb" in calls[1]


def test_no_model_and_empty_pool_returns_none_source():
    items, source = ti.get_items("riddle", 5, device="car-1")
    assert items == [] and source == "none"


# --------------------------------------------------------------------------
# HTTP contract
# --------------------------------------------------------------------------

@pytest.fixture
def client():
    app = Flask(__name__)
    app.register_blueprint(ti.travel_items_bp, url_prefix="/api/travel")
    return app.test_client()


def test_endpoint_returns_items(client, monkeypatch):
    fake_generate(monkeypatch, [[item("a comb"), item("a towel")]])
    resp = client.post("/api/travel/items",
                       json={"kind": "riddle", "count": 2, "device": "car-1",
                             "seen": ["piano"]})
    body = resp.get_json()
    assert resp.status_code == 200 and body["success"]
    assert body["source"] == "openai"
    assert {i["answer"] for i in body["items"]} == {"a comb", "a towel"}
    assert set(body["items"][0]) == {"prompt", "answer", "accepts", "hint", "fact"}


def test_endpoint_rejects_unknown_kind(client):
    resp = client.post("/api/travel/items", json={"kind": "poker"})
    assert resp.status_code == 400


def test_endpoint_tolerates_junk_input(client):
    resp = client.post("/api/travel/items",
                       json={"kind": "quiz", "count": "lots", "seen": "nope"})
    body = resp.get_json()
    assert resp.status_code == 200 and body["items"] == [] and body["source"] == "none"
