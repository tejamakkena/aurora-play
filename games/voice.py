"""Voice-quizmaster HTTP API: cloud TTS proxy + answer grading.

Both endpoints keep third-party API keys server-side -- the iOS/tvOS apps
never see them.

    GET  /api/voice/tts?text=<urlencoded>&voice=<name>&style=<style>   -> audio/mpeg
    POST /api/voice/tts  {"text": "...", "voice": "...", "style": "..."} -> audio/mpeg
    POST /api/voice/grade {"question","options","correct_answer",
                          "transcript"}                 -> {"correct","method"}

The GET form exists so clients can use their HTTP cache (URLCache on iOS):
the response is deterministic per (model, voice, text) and served with a
long immutable Cache-Control. The POST form is for texts too long for a URL.

Setup -- the PR description has the full checklist; the short version:
    OPENAI_API_KEY must be set for TTS (https://platform.openai.com/api-keys).
    TTS_MODEL / TTS_VOICE are optional (defaults: gpt-4o-mini-tts / marin).
    TTS_PROVIDER=elevenlabs switches the voice to ElevenLabs (docs/VOICE.md).
    Grading reuses GEMINI_API_KEY via games.topic_gen, but the fuzzy matcher
    runs first, so the large majority of grades never touch the network.

Cost (Oct 2026 pricing): ~7 cents per 10-question game, ~95% of it TTS.
"""

import hashlib
import json
import logging
import os
import threading
from concurrent.futures import ThreadPoolExecutor
import time
import urllib.parse
import urllib.request
from pathlib import Path

from flask import Blueprint, Response, jsonify, request

from games import voice_styles

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


# --- one paid call per line ------------------------------------------------
# A line can be asked for twice at once: prewarmed in the background and then
# requested by the TV. The second caller waits for the first and reads the
# cache instead of paying again.

_locks_guard = threading.Lock()
_locks: dict[str, threading.Lock] = {}


def _key_lock(key: str) -> threading.Lock:
    with _locks_guard:
        if len(_locks) > 2000:
            for k in [k for k, lk in _locks.items() if not lk.locked()]:
                del _locks[k]
        return _locks.setdefault(key, threading.Lock())


def _cache_dir() -> Path:
    override = os.environ.get("TTS_CACHE_PATH")
    if override:
        return Path(override)
    repo_root = Path(__file__).resolve().parents[1]
    return repo_root / "data" / "tts_cache"


def _cache_key(model: str, voice: str, text: str, instructions: str = "") -> str:
    # No instructions: the same key as before, so audio cached earlier still hits.
    extra = f"\x00{instructions}" if instructions else ""
    return hashlib.sha256(f"{model}\x00{voice}\x00{text}{extra}".encode("utf-8")).hexdigest()


def _instructions_for(model: str, style: str | None) -> str:
    """The acting direction for this line, or "" for a model that takes none.

    Only the gpt-4o voices follow ``instructions``; tts-1 would reject the field.
    ``TTS_STYLES=0`` switches it off (flat voice, the old behaviour).
    """
    if not str(model).startswith("gpt-4o") or os.environ.get("TTS_STYLES", "1") == "0":
        return ""
    return voice_styles.resolve(style) or voice_styles.STYLES[voice_styles.DEFAULT]


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


_ELEVEN_API = "https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"


def _eleven_config(style: str | None) -> dict:
    """ElevenLabs settings from the environment. ``ELEVENLABS_VOICE_ID_INDIAN``
    voices the "indian" style (Hindi and Telugu words); ``ELEVENLABS_VOICE_ID``
    is every other line."""
    voice_id = os.environ.get("ELEVENLABS_VOICE_ID", "")
    if style == "indian" and os.environ.get("ELEVENLABS_VOICE_ID_INDIAN"):
        voice_id = os.environ["ELEVENLABS_VOICE_ID_INDIAN"]
    return {
        "api_key": os.environ.get("ELEVENLABS_API_KEY"),
        "voice_id": voice_id,
        "model": os.environ.get("ELEVENLABS_MODEL", "eleven_v4"),
    }


def _synthesize_elevenlabs(text: str, style: str | None) -> tuple[bytes, str]:
    """The same contract as ``synthesize_speech``, with the ElevenLabs voice.

    Eleven v4 and v3 act a line from audio tags ("[excited]", "[giggles]"),
    which ``voice_styles.tagged`` puts in front; other models would say the
    brackets aloud, so they read the text as it is.
    """
    cfg = _eleven_config(style)
    if not cfg["api_key"] or not cfg["voice_id"]:
        raise VoiceError("ELEVENLABS_API_KEY or ELEVENLABS_VOICE_ID is not set")
    takes_tags = cfg["model"] in ("eleven_v4", "eleven_v3")
    # A host moment ("answers_none") acts like its style ("roast").
    spoken = voice_styles.tagged(text, voice_styles.canonical(style)) if takes_tags else text

    key = _cache_key(f"eleven:{cfg['model']}", cfg["voice_id"], spoken)
    path = _cache_dir() / f"{key}.mp3"
    with _key_lock(key):
        return _eleven_render(cfg, spoken, text, path)


def _eleven_render(cfg: dict, spoken: str, text: str, path: Path) -> tuple[bytes, str]:
    """Cache check, then the paid call. Runs under the line's lock, so a line
    being prewarmed is not paid for twice when the TV asks for it too."""
    try:
        if path.is_file():
            return path.read_bytes(), "cache"
    except OSError:
        pass

    _check_cap(len(text))
    body = {"text": spoken, "model_id": cfg["model"]}
    if cfg["model"] == "eleven_v3":
        body["voice_settings"] = {"stability": 0.5}      # v3: 0 creative, 0.5 natural, 1 robust
    req = urllib.request.Request(
        _ELEVEN_API.format(voice_id=urllib.parse.quote(cfg["voice_id"], safe="")) + "?output_format=mp3_44100_64",
        data=json.dumps(body).encode("utf-8"),
        headers={"xi-api-key": cfg["api_key"], "Content-Type": "application/json",
                 "Accept": "audio/mpeg", "User-Agent": "AuroraPlay/1.0 (quizmaster)"},
    )
    try:
        with urllib.request.urlopen(req, timeout=_TTS_TIMEOUT) as resp:
            if resp.status != 200:
                raise VoiceError(f"ElevenLabs HTTP {resp.status}")
            audio = resp.read()
    except VoiceError:
        raise
    except Exception as exc:
        raise VoiceError(f"ElevenLabs request failed: {exc}")
    if not audio:
        raise VoiceError("ElevenLabs returned no audio")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(audio)
    except OSError:
        pass
    return audio, "elevenlabs"


def synthesize_speech(text: str, voice: str | None = None,
                      style: str | None = None) -> tuple[bytes, str]:
    """Return (mp3_bytes, source). Source is 'cache' or 'openai'.

    ``style`` names how it is said (games/voice_styles.py: "welcome", "roast",
    or a Game Night host moment); no style is the warm host voice.

    Raises VoiceError when TTS is unavailable -- callers fall back to the
    on-device voice instead of failing the game.
    """
    cfg = _config()
    text = _tts_clean_for_speech(text)
    if not text:
        raise VoiceError("empty text")
    if os.environ.get("TTS_PROVIDER", "openai") == "elevenlabs":
        return _synthesize_elevenlabs(text, style)
    voice = (voice or cfg["voice"]).strip() or cfg["voice"]
    model = cfg["model"]

    instructions = _instructions_for(model, style)
    key = _cache_key(model, voice, text, instructions)
    path = _cache_dir() / f"{key}.mp3"
    with _key_lock(key):
        return _openai_render(cfg, model, voice, text, instructions, path)


def _openai_render(cfg: dict, model: str, voice: str, text: str, instructions: str,
                   path: Path) -> tuple[bytes, str]:
    """Cache check, then the paid call (under the line's lock, see _eleven_render)."""
    try:
        if path.is_file():
            return path.read_bytes(), "cache"
    except OSError:
        pass

    if not cfg["api_key"]:
        raise VoiceError("OPENAI_API_KEY is not set")

    _check_cap(len(text))

    body = {
        "model": model,
        "input": text,
        "voice": voice,
        "response_format": "mp3",
    }
    if instructions:
        body["instructions"] = instructions
    payload = json.dumps(body).encode("utf-8")
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


# --- prewarm: have the lines ready before the TV asks ------------------------
# The server already knows what the host will say next (the party welcome and
# lineup, the Game Night host's quips). Rendering them as soon as they are
# written takes the wait out of the cloud voice, which otherwise renders each
# line the moment the TV asks. Best effort: never raises, respects the daily
# cap, and does nothing when no voice is configured.

_PREWARM_MAX = 12
_prewarm_pool: ThreadPoolExecutor | None = None
_prewarm_lock = threading.Lock()


def _voice_ready() -> bool:
    if os.environ.get("TTS_PREWARM", "1") == "0":
        return False
    if os.environ.get("TTS_PROVIDER", "openai") == "elevenlabs":
        return bool(os.environ.get("ELEVENLABS_API_KEY") and os.environ.get("ELEVENLABS_VOICE_ID"))
    return bool(_config()["api_key"])


def _prewarm_one(text: str, style: str | None) -> None:
    try:
        synthesize_speech(text, None, style)
    except VoiceError:
        pass
    except Exception:
        logger.exception("tts prewarm failed")


def prewarm(lines) -> int:
    """Render ``(text, style)`` pairs in the background; returns how many were
    queued. Style is a style name or a host moment, as for /api/voice/tts."""
    global _prewarm_pool
    if not _voice_ready():
        return 0
    queued = 0
    for item in list(lines)[:_PREWARM_MAX]:
        try:
            text, style = item
        except (TypeError, ValueError):
            continue
        if not isinstance(text, str) or not text.strip():
            continue
        with _prewarm_lock:
            if _prewarm_pool is None:
                _prewarm_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="tts-prewarm")
            _prewarm_pool.submit(_prewarm_one, text, style if isinstance(style, str) else None)
        queued += 1
    return queued


@voice_bp.route("/warm", methods=["GET"])
def warm():
    """GET /api/voice/warm -> a few bytes. The apps call it on launch and in the
    lobby so a sleeping free-tier server is awake by the first spoken line."""
    return jsonify({"ok": True, "voice": _voice_ready()})


def _tts_response(text: str, voice: str | None, style: str | None = None):
    try:
        audio, source = synthesize_speech(text, voice, style)
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
    style = request.args.get("style") or None
    if len(text) > 2000:
        return jsonify({"success": False,
                        "error": "text too long for GET; use POST"}), 413
    return _tts_response(text, voice, style)


@voice_bp.route("/tts", methods=["POST"])
def tts_post():
    """POST /api/voice/tts {"text": ..., "voice": ...} -> audio/mpeg."""
    data = request.get_json(force=True, silent=True) or {}
    return _tts_response(str(data.get("text") or ""),
                        data.get("voice") or None, data.get("style") or None)


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
