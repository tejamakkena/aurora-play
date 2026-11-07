"""Voice delay: lines are rendered ahead of the TV asking, once, and a host
moment acts like its style."""

import threading
import time

import pytest

from app import create_app
from games import voice, voice_styles


@pytest.fixture(autouse=True)
def _isolated(monkeypatch, tmp_path):
    monkeypatch.setenv("TTS_CACHE_PATH", str(tmp_path))
    monkeypatch.delenv("TTS_PREWARM", raising=False)
    monkeypatch.setattr(voice, "_prewarm_pool", None)


def test_nothing_is_queued_without_a_voice(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setenv("TTS_PROVIDER", "openai")
    assert voice.prewarm([("Welcome", "welcome")]) == 0


def test_prewarm_can_be_switched_off(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    monkeypatch.setenv("TTS_PREWARM", "0")
    assert voice.prewarm([("Welcome", "welcome")]) == 0


def test_lines_are_rendered_in_the_background(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    seen = []
    done = threading.Event()

    def fake(text, voice_name=None, style=None):
        seen.append((text, style))
        if len(seen) == 2:
            done.set()
        return b"x", "openai"

    monkeypatch.setattr(voice, "synthesize_speech", fake)
    assert voice.prewarm([("One", "welcome"), ("Two", None), ("", "x"), (5, "x"), "bad"]) == 2
    assert done.wait(3)
    assert sorted(seen) == [("One", "welcome"), ("Two", None)]


def test_a_failing_render_is_swallowed(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    ran = threading.Event()

    def boom(*args, **kwargs):
        ran.set()
        raise voice.VoiceError("cap reached")

    monkeypatch.setattr(voice, "synthesize_speech", boom)
    assert voice.prewarm([("One", None)]) == 1
    assert ran.wait(3)


def test_no_more_than_the_cap_per_call(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    done = []
    finished = threading.Event()

    def fake(*args, **kwargs):
        done.append(1)
        if len(done) == voice._PREWARM_MAX:
            finished.set()
        return b"x", "openai"

    monkeypatch.setattr(voice, "synthesize_speech", fake)
    assert voice.prewarm([(f"line {i}", None) for i in range(40)]) == voice._PREWARM_MAX
    assert finished.wait(5)             # let the background renders end before the next test


def test_a_line_asked_for_twice_at_once_is_paid_for_once(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "k")
    monkeypatch.setenv("TTS_PROVIDER", "openai")
    calls = []

    class Resp:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self): return b"audio" * 200

    def slow_open(req, timeout=0):
        calls.append(1)
        time.sleep(0.2)
        return Resp()

    monkeypatch.setattr(voice.urllib.request, "urlopen", slow_open)
    results = []
    threads = [threading.Thread(target=lambda: results.append(voice.synthesize_speech("Hello there", None, "welcome")))
               for _ in range(3)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(5)
    assert len(calls) == 1
    assert len(results) == 3 and {r[0] for r in results} == {b"audio" * 200}
    assert sorted(r[1] for r in results) == ["cache", "cache", "openai"]


def test_a_host_moment_gets_its_styles_audio_tag(monkeypatch):
    monkeypatch.setenv("TTS_PROVIDER", "elevenlabs")
    monkeypatch.setenv("ELEVENLABS_API_KEY", "k")
    monkeypatch.setenv("ELEVENLABS_VOICE_ID", "v")
    monkeypatch.setenv("ELEVENLABS_MODEL", "eleven_v4")
    bodies = []

    class Resp:
        status = 200
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def read(self): return b"audio" * 200

    def capture(req, timeout=0):
        import json
        bodies.append(json.loads(req.data))
        return Resp()

    monkeypatch.setattr(voice.urllib.request, "urlopen", capture)
    voice.synthesize_speech("Nobody got it.", None, "answers_none")
    assert bodies[0]["text"] == "[sarcastic] Nobody got it."


def test_canonical_names():
    assert voice_styles.canonical("roast") == "roast"
    assert voice_styles.canonical("answers_none") == "roast"
    assert voice_styles.canonical("intro_any") == "welcome"
    assert voice_styles.canonical("herd_kids") == "kids"
    assert voice_styles.canonical("nonsense") is None
    assert voice_styles.canonical(None) is None


def test_the_warm_endpoint_is_cheap():
    app, _ = create_app("default")
    body = app.test_client().get("/api/voice/warm").get_json()
    assert body["ok"] is True and "voice" in body
