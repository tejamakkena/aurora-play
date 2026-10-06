"""Make-your-own decks and quizzes, written by the AI from a typed topic.

    POST /api/decks/generate
        {"kind": "quiz"|"headsup"|"truth"|"dare"|"wyr"|"hotpotato",
         "topic": "Tollywood 2000s", "count": 20,
         "familySafe": true, "language": "en"|"te"|"hi"}
    -> {"success": true, "kind", "topic", "source": "openai"|"gemini"|"cache"|"none",
        "items": [...]}

Item shapes:
    quiz      {"question", "options"[4], "correct_answer"}  (same as trivia;
              send to a TV room with the set_custom_questions socket event)
    headsup   "a word or name to act out"
    truth     "a truth question"
    dare      "a dare"
    wyr       "Would you rather ... or ...?"
    hotpotato "a category to name things in, e.g. Things in a kitchen"

Everything is validated (speech/TV-safe text, lengths, quiz shape) and
cached per (kind, topic, language, family-safe), so asking twice for the
same deck costs one model call. With no model configured the result is
an empty list and the phone uses its bundled decks.
"""

from __future__ import annotations

import json
import os
import threading
from pathlib import Path

from flask import Blueprint, jsonify, request

from games import llm_json, topic_gen

KINDS = ("quiz", "headsup", "truth", "dare", "wyr", "hotpotato")
LANGUAGES = {"en": "English", "te": "Telugu (in Telugu script)", "hi": "Hindi (in Devanagari script)"}
_MAX_COUNT = 40
_lock = threading.RLock()

_ASK = {
    "quiz": ("multiple-choice quiz questions about {topic}. Exactly 4 options, one "
             "correct, correct_answer is its 0-based index",
             '{"question": "...?", "options": ["A", "B", "C", "D"], "correct_answer": 2}'),
    "headsup": ("words, names or short phrases about {topic} for a Heads Up guessing "
                "game: things people can describe or act out, 1 to 4 words each",
                '"Shah Rukh Khan"'),
    "truth": ("truth questions for a truth-or-dare game, themed around {topic}",
              '"What is the most embarrassing thing you have done at a wedding?"'),
    "dare": ("dares for a truth-or-dare game that can be done right now in a living "
             "room, themed around {topic}",
             '"Speak only in rhymes until your next turn."'),
    "wyr": ('"Would you rather ... or ...?" questions themed around {topic}',
            '"Would you rather only eat biryani forever or never eat it again?"'),
    "hotpotato": ("categories for a fast word game where players name items in the "
                  "category before a timer runs out, themed around {topic}",
                  '"Things you find in a kitchen"'),
}


def _cache_path() -> Path:
    override = os.environ.get("DECKS_CACHE_PATH")
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1] / "data" / "decks_cache.json"


def _cache_key(kind, topic, language, safe) -> str:
    return f"{kind}|{topic_gen.norm_topic(topic)}|{language}|{int(bool(safe))}"


def _cache_get(key: str) -> list:
    with _lock:
        try:
            data = json.loads(_cache_path().read_text(encoding="utf-8"))
        except Exception:
            return []
        items = data.get(key) if isinstance(data, dict) else None
        return items if isinstance(items, list) else []


def _cache_put(key: str, items: list) -> None:
    with _lock:
        try:
            data = json.loads(_cache_path().read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                data = {}
        except Exception:
            data = {}
        data[key] = items[:_MAX_COUNT * 2]
        while len(data) > 300:
            data.pop(next(iter(data)))
        try:
            _cache_path().parent.mkdir(parents=True, exist_ok=True)
            _cache_path().write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        except OSError:
            pass


def validate(kind: str, item, language: str = "en"):
    """The item in its clean shape, or None."""
    if kind == "quiz":
        if not isinstance(item, dict):
            return None
        q = {"question": str(item.get("question", "")).strip(),
             "options": [str(o).strip() for o in (item.get("options") or [])],
             "correct_answer": item.get("correct_answer")}
        return q if topic_gen.validate_question(q)[0] else None
    if not isinstance(item, str):
        return None
    text = " ".join(item.split())
    ok, _ = topic_gen._tts_clean(text)
    limit = 40 if kind == "headsup" else 160
    if not ok or not 2 <= len(text) <= limit:
        return None
    if kind == "wyr" and language == "en" and not text.lower().startswith("would you rather"):
        return None
    return text


def build_prompt(kind: str, topic: str, count: int, family_safe: bool, language: str) -> str:
    what, example = _ASK[kind]
    tone = ("Strictly family-friendly: fine for children and grandparents, nothing "
            "rude, romantic, scary or about drinking." if family_safe else
            "Adult party tone is fine, but nothing hateful, sexual or dangerous.")
    lang = LANGUAGES.get(language, "English")
    return (
        f"Write {count} {what.format(topic=topic)}.\n"
        f"Language: {lang}. {tone}\n"
        f'Return ONLY a JSON object: {{"items": [ ... ]}} where each item looks like {example}\n'
        "Plain text only: no emojis, no markdown, no numbering. Every item different."
    )


def generate(kind: str, topic: str, count: int = 20, family_safe: bool = True,
             language: str = "en") -> tuple[list, str]:
    """(items, source). Never raises; ([], "none") when no model answers."""
    count = max(1, min(int(count), _MAX_COUNT))
    language = language if language in LANGUAGES else "en"
    topic = " ".join(str(topic or "").split())[:80] or "anything fun"
    key = _cache_key(kind, topic, language, family_safe)
    cached = _cache_get(key)
    if len(cached) >= count:
        return cached[:count], "cache"
    try:
        raw, source = llm_json.json_items(build_prompt(kind, topic, count, family_safe, language))
    except llm_json.LLMError:
        return cached, ("cache" if cached else "none")
    seen = {json.dumps(c, sort_keys=True, ensure_ascii=False).lower() for c in cached}
    items = list(cached)
    for r in raw:
        clean = validate(kind, r, language)
        if clean is None:
            continue
        sig = json.dumps(clean, sort_keys=True, ensure_ascii=False).lower()
        if sig not in seen:
            seen.add(sig)
            items.append(clean)
    if items:
        _cache_put(key, items)
    return items[:count], source


decks_bp = Blueprint("decks", __name__)


@decks_bp.route("/decks/generate", methods=["POST"])
def decks_generate():
    body = request.get_json(force=True, silent=True) or {}
    kind = body.get("kind")
    if kind not in KINDS:
        return jsonify({"success": False, "error": f"kind must be one of {', '.join(KINDS)}"}), 400
    try:
        count = int(body.get("count") or 20)
    except (TypeError, ValueError):
        count = 20
    items, source = generate(kind, body.get("topic") or "", count,
                             body.get("familySafe", True) is not False,
                             str(body.get("language") or "en"))
    return jsonify({"success": True, "kind": kind, "topic": body.get("topic") or "",
                    "source": source, "items": items})
