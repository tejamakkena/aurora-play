"""Voice-quizmaster HTTP API: cloud TTS proxy + answer grading.

Both endpoints keep third-party API keys server-side -- the iOS/tvOS apps
never see them.

    GET  /api/voice/tts?text=<urlencoded>&voice=<name>   -> audio/mpeg
    POST /api/voice/tts  {"text": "...", "voice": "..."} -> audio/mpeg
    POST /api/voice/grade {"question","options","correct_answer",
                          "transcript"}                 -> {"correct","method"}

The GET form exists so clients can use their HTTP cache (URLCache on iOS):
the response is deterministic per (model, voice, text) and served with a
long immutable Cache-Control. The POST form is for texts too long for a URL.

Setup -- the PR description has the full checklist; the short version:
    OPENAI_API_KEY must be set for TTS (https://platform.openai.com/api-keys).
    TTS_MODEL / TTS_VOICE are optional (defaults: gpt-4o-mini-tts / marin).
    Grading reuses GEMINI_API_KEY via games.topic_gen, but the fuzzy matcher
    runs first, so the large majority of grades never touch the network.

Cost (Oct 2026 pricing): ~7 cents per 10-question game, ~95% of it TTS.
"""

import hashlib
import json
import logging
import os
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

from flask import Blueprint, Response, jsonify, request

logger = logging.getLogger(__name__)

voice_bp = Blueprint("voice", __name__)

_TTS_API = "https://api.openai.com/v1/audio/speech"
_TTS_MAX_CHARS = 4000          # OpenAI per-request limit is 4096
_TTS_TIMEOUT = 30


class VoiceError(Exception):
    """Anything the client should hear as 'TTS unavailable, use fallback'."""


def _config():
    return {
        "api_key": os.environ.get("OPENAI_API_KEY"),
        "model": os.environ.get("TTS_MODEL", "gpt-4o-mini-tts"),
        "voice": os.environ.get("TTS_VOICE", "marin"),
    }


def _cache_dir() -> Path:
    override = os.environ.get("TTS_CACHE_PATH")
    if override:
        return Path(override)
    repo_root = Path(__file__).resolve().parents[1]
    return repo_root / "data" / "tts_cache"


def _cache_key(model: str, voice: str, text: str) -> str:
    return hashlib.sha256(f"{model}\x00{voice}\x00{text}".encode("utf-8")).hexdigest()


# --- daily cost cap ---------------------------------------------------------
# A coarse guardrail so a bug (or a very enthusiastic party) can't burn the
# TTS budget: characters synthesized per UTC day, env-tunable.

_cap_lock = threading.Lock()
_cap_day = None
_cap_chars = 0


def _daily_cap() -> int:
    try:
        return max(0, int(os.environ.get("TTS_DAILY_CHAR_CAP", "500000")))
    except ValueError:
        return 500000


def _check_cap(chars: int) -> None:
    """Raise VoiceError when the day's cap would be exceeded."""
    global _cap_day, _cap_chars
    day = time.strftime("%Y-%m-%d", time.gmtime())
    with _cap_lock:
        if _cap_day != day:
            _cap_day, _cap_chars = day, 0
        if _cap_chars + chars > _daily_cap():
            raise VoiceError("daily TTS cap reached")
        _cap_chars += chars


def _tts_clean_for_speech(text: str) -> str:
    """Light prep so the model reads like a host, not a parser."""
    text = " ".join(str(text or "").split())
    return text[:_TTS_MAX_CHARS]


def synthesize_speech(text: str, voice: str | None = None) -> tuple[bytes, str]:
    """Return (mp3_bytes, source). Source is 'cache' or 'openai'.

    Raises VoiceError when TTS is unavailable -- callers fall back to the
    on-device voice instead of failing the game.
    """
    cfg = _config()
    text = _tts_clean_for_speech(text)
    if not text:
        raise VoiceError("empty text")
    voice = (voice or cfg["voice"]).strip() or cfg["voice"]
    model = cfg["model"]

    key = _cache_key(model, voice, text)
    path = _cache_dir() / f"{key}.mp3"
    try:
        if path.is_file():
            return path.read_bytes(), "cache"
    except OSError:
        pass

    if not cfg["api_key"]:
        raise VoiceError("OPENAI_API_KEY is not set")

    _check_cap(len(text))

    payload = json.dumps({
        "model": model,
        "input": text,
        "voice": voice,
        "response_format": "mp3",
    }).encode("utf-8")
    req = urllib.request.Request(
        _TTS_API, data=payload,
        headers={
            "Authorization": f"Bearer {cfg['api_key']}",
            "Content-Type": "application/json",
            "User-Agent": "AuroraPlay/1.0 (quizmaster)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=_TTS_TIMEOUT) as resp:
            if resp.status != 200:
                raise VoiceError(f"TTS HTTP {resp.status}")
            audio = resp.read()
    except VoiceError:
        raise
    except Exception as exc:
        raise VoiceError(f"TTS request failed: {exc}")
    if not audio:
        raise VoiceError("TTS returned no audio")

    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(audio)
    except OSError:
        pass  # cache is best-effort; the audio itself is fine
    return audio, "openai"


def _tts_response(text: str, voice: str | None):
    try:
        audio, source = synthesize_speech(text, voice)
    except VoiceError as exc:
        return jsonify({"success": False, "error": str(exc)}), 502
    return Response(
        audio,
        mimetype="audio/mpeg",
        headers={
            # Deterministic per (model, voice, text): safe to cache hard.
            "Cache-Control": "public, max-age=31536000, immutable",
            "X-TTS-Source": source,
        },
    )


@voice_bp.route("/tts", methods=["GET"])
def tts_get():
    """GET /api/voice/tts?text=...&voice=... -> audio/mpeg (cacheable)."""
    text = request.args.get("text", "")
    voice = request.args.get("voice") or None
    if len(text) > 2000:
        return jsonify({"success": False,
                        "error": "text too long for GET; use POST"}), 413
    return _tts_response(text, voice)


@voice_bp.route("/tts", methods=["POST"])
def tts_post():
    """POST /api/voice/tts {"text": ..., "voice": ...} -> audio/mpeg."""
    data = request.get_json(force=True, silent=True) or {}
    return _tts_response(str(data.get("text") or ""),
                        data.get("voice") or None)


# ---------------------------------------------------------------------------
# grading: fuzzy match first (free), LLM only when fuzzy is unsure
# ---------------------------------------------------------------------------

_LETTERS = ("a", "b", "c", "d")


def _letter_match(transcript: str):
    """'B', 'option b', 'the second one' -> 1. None when no letter found."""
    import re
    t = transcript.strip().lower()
    m = re.search(r"\boption\s+([a-d])\b", t) or re.search(r"\b([a-d])\b", t)
    if m:
        return _LETTERS.index(m.group(1))
    words = {"first": 0, "second": 1, "third": 2, "fourth": 3,
             "1st": 0, "2nd": 1, "3rd": 2, "4th": 3}
    for w, i in words.items():
        if re.search(rf"\b{w}\b", t):
            return i
    return None


def _llm_grade(question: str, correct_text: str, transcript: str) -> bool | None:
    """One tiny Gemini call. None when the model is unavailable."""
    try:
        from games import topic_gen
        model = topic_gen._genai_model()
    except Exception:
        return None
    prompt = (
        "You are grading a spoken quiz answer. Reply with ONLY 'yes' or 'no'.\n"
        f"Question: {question}\n"
        f"Correct answer: {correct_text}\n"
        f"The player said: \"{transcript}\"\n"
        "Is the player's answer correct (allowing for speech-recognition "
        "errors and paraphrase)?"
    )
    try:
        text = model.generate_content(prompt).text.strip().lower()
    except Exception:
        return None
    if text.startswith("yes"):
        return True
    if text.startswith("no"):
        return False
    return None


@voice_bp.route("/grade", methods=["POST"])
def grade():
    """POST /api/voice/grade -> {"success","correct","method"}.

    method is one of: letter (they said "B"), fuzzy (forgiving string
    match against the correct option), llm (one tiny model call),
    none (couldn't grade -- client falls back to host tap).
    """
    data = request.get_json(force=True, silent=True) or {}
    question = str(data.get("question") or "")
    options = data.get("options") or []
    correct = data.get("correct_answer")
    transcript = str(data.get("transcript") or "").strip()
    if not transcript or not isinstance(correct, int) or not 0 <= correct <= 3 \
            or not isinstance(options, list) or len(options) != 4:
        return jsonify({"success": False,
                        "error": "need transcript, 4 options, correct_answer 0-3"}), 400

    letter = _letter_match(transcript)
    if letter is not None:
        return jsonify({"success": True, "correct": letter == correct,
                        "method": "letter"})

    from games.native_hub.engines._matching import guess_matches
    correct_text = str(options[correct])
    if guess_matches(transcript, correct_text):
        return jsonify({"success": True, "correct": True, "method": "fuzzy"})
    # Also fuzzy-match the *wrong* options: a confident match to a wrong
    # option is a confident "no" without spending an LLM call.
    for i, opt in enumerate(options):
        if i != correct and guess_matches(transcript, str(opt)):
            return jsonify({"success": True, "correct": False,
                            "method": "fuzzy"})

    verdict = _llm_grade(question, correct_text, transcript)
    if verdict is None:
        return jsonify({"success": True, "correct": None, "method": "none"})
    return jsonify({"success": True, "correct": verdict, "method": "llm"})
