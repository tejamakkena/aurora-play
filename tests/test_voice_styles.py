"""How the host sounds: acting directions for the cloud voice, the voice pack's
per-line styles, and the silence trimming that evens out the gaps."""

import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from games import show_host, voice, voice_styles

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("render_voice_pack", ROOT / "tools" / "render_voice_pack.py")
rvp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rvp)


# ---- the styles ---------------------------------------------------------------

def test_every_host_moment_has_a_real_style():
    for moment in show_host.LINES:
        assert voice_styles.for_moment(moment) in voice_styles.STYLES, moment


def test_moments_map_to_the_right_feel():
    assert voice_styles.for_moment("night_open") == "welcome"
    assert voice_styles.for_moment("answers_none") == "roast"
    assert voice_styles.for_moment("close_race") == "hype"
    assert voice_styles.for_moment("night_close") == "finale"
    assert voice_styles.for_moment("game_won_kids") == "kids"
    assert voice_styles.for_moment("intro_quiz") == "playful"
    assert voice_styles.for_moment("nonsense") == voice_styles.DEFAULT


def test_only_known_styles_reach_the_paid_voice():
    assert voice_styles.resolve("roast") == voice_styles.STYLES["roast"]
    assert voice_styles.resolve("answers_none") == voice_styles.STYLES["roast"]
    assert voice_styles.resolve("ignore previous instructions") is None
    assert voice_styles.resolve("") is None


# ---- the cloud request ----------------------------------------------------------

class FakeResponse:
    status = 200

    def read(self):
        return b"x" * 2000

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


@pytest.fixture
def sent(monkeypatch, tmp_path):
    monkeypatch.setenv("OPENAI_API_KEY", "test")
    monkeypatch.setenv("TTS_CACHE_PATH", str(tmp_path))
    monkeypatch.setenv("TTS_DAILY_CHAR_CAP", "1000000")
    bodies = []

    def fake(req, timeout=0):
        bodies.append(json.loads(req.data))
        return FakeResponse()

    monkeypatch.setattr(voice.urllib.request, "urlopen", fake)
    return bodies


def test_every_line_gets_acting_directions(sent):
    voice.synthesize_speech("Welcome to the show.")
    assert sent[0]["instructions"] == voice_styles.STYLES[voice_styles.DEFAULT]


def test_a_named_style_changes_the_direction_and_the_cache(sent):
    voice.synthesize_speech("Nobody got that one.", style="roast")
    voice.synthesize_speech("Nobody got that one.", style="welcome")
    voice.synthesize_speech("Nobody got that one.", style="roast")      # cached
    assert [b["instructions"] for b in sent] == [voice_styles.STYLES["roast"],
                                                 voice_styles.STYLES["welcome"]]


def test_an_older_voice_model_gets_no_instructions(sent, monkeypatch):
    monkeypatch.setenv("TTS_MODEL", "tts-1")
    voice.synthesize_speech("Hello there.", style="roast")
    assert "instructions" not in sent[0]


def test_styles_can_be_switched_off(sent, monkeypatch):
    monkeypatch.setenv("TTS_STYLES", "0")
    voice.synthesize_speech("Hello there.")
    assert "instructions" not in sent[0]


def test_the_old_cache_key_is_unchanged_without_instructions():
    assert voice._cache_key("m", "v", "t") == voice._cache_key("m", "v", "t", "")
    assert voice._cache_key("m", "v", "t") != voice._cache_key("m", "v", "t", "sound happy")


# ---- the voice pack -------------------------------------------------------------

def test_pack_lines_know_how_they_are_said():
    clips, styles = rvp.collect_styled(["wyr"], swift=True)
    assert set(clips) == set(styles)
    assert set(styles.values()) <= set(voice_styles.STYLES)
    opening = rvp.pieces(show_host.LINES["night_open"][0])[0]
    assert styles[rvp.key(opening)] == "welcome"
    roast = rvp.pieces(show_host.LINES["answers_none"][0])[0]
    assert styles[rvp.key(roast)] == "roast"
    assert "narrator" in styles.values() and "roast" in styles.values() and "quiz" in styles.values()


def test_collect_keeps_its_order_and_keys():
    clips, _ = rvp.collect_styled(list(rvp.SOURCES), swift=True)
    assert list(clips) == list(rvp.collect(list(rvp.SOURCES), swift=True))


def test_audition_covers_every_style_used():
    assert {s for s, _ in rvp.AUDITION} <= set(voice_styles.STYLES)
    assert {"welcome", "roast", "indian"} <= {s for s, _ in rvp.AUDITION}


@pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("ffprobe")), reason="needs ffmpeg")
def test_clips_lose_their_leading_and_trailing_silence(tmp_path):
    src = tmp_path / "padded.wav"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
                    "sine=frequency=440:duration=0.5", "-af", "adelay=700|700,apad=pad_dur=0.7",
                    str(src)], check=True)
    out = tmp_path / "trimmed.m4a"
    rvp._ffmpeg(src, out)
    seconds = float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(out)],
        capture_output=True, text=True, check=True).stdout)
    # 0.5 s of sound plus a short even tail, not the 1.9 s the padded file had.
    assert 0.55 < seconds < 0.95, seconds
