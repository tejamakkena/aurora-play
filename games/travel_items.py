"""Fresh riddles and fun-fact questions for the Travel Mode quizmaster.

    POST /api/travel/items
        {"kind": "riddle" | "quiz", "count": 8, "device": "<id>",
         "seen": ["piano", "egg", ...]}            # answers already heard
    ->  {"success": true, "kind": ..., "source": "pool"|"openai"|"gemini"|"none",
         "items": [{"prompt", "answer", "accepts": [...], "hint", "fact"}]}

Why ANSWERS, not question texts, are what "already asked" means here: the
same riddle comes back reworded ("What has keys but can't open locks?" /
"I have keys but open no doors...") and a text match never catches it.
The answer ("a piano") is stable, short, and cheap to send: ~200 of them
fit in one request, where the old trivia path could only pass the model
40 truncated question texts.

Repeats are blocked three ways:
  1. the phone sends the answers it has heard (its history survives app
     restarts and server redeploys -- Render's disk does not);
  2. the server keeps its own per-device answer history (helps a fresh
     install on a device id it already knows);
  3. the model is told every one of those answers is off limits, and its
     output is filtered against them anyway.

Generation is OpenAI first (OPENAI_API_KEY -- the same key the voice
already uses; TRAVEL_TEXT_MODEL picks the model), then Gemini
(GEMINI_API_KEY), then nothing: the phone's bundled deck keeps playing.
Everything generated goes into a shared pool so most requests are served
without any model call at all.
"""

import json
import os
import random
import re
import threading
import urllib.request
from pathlib import Path

from flask import Blueprint, jsonify, request

from games import topic_gen

KINDS = ("riddle", "quiz")
BATCH = 12
POOL_MAX_PER_KIND = 600
SERVED_MAX_PER_DEVICE = 600
SEEN_MAX_FROM_CLIENT = 300
EXCLUDE_IN_PROMPT = 200

_OPENAI_CHAT = "https://api.openai.com/v1/chat/completions"
_TIMEOUT = 40

_lock = threading.Lock()


class GenError(Exception):
    """The model could not produce a batch; the caller falls back."""


# ---------------------------------------------------------------------------
# normalising answers ("A Piano!" == "piano" == "pianos")
# ---------------------------------------------------------------------------

_ARTICLES = {"a", "an", "the", "your", "some"}


def answer_key(text: str) -> str:
    words = re.findall(r"[a-z0-9]+", str(text or "").lower())
    while words and words[0] in _ARTICLES:
        words.pop(0)
    out = []
    for w in words:
        if len(w) > 4 and w.endswith("es") and not w.endswith("sses"):
            w = w[:-2]
        elif len(w) > 3 and w.endswith("s") and not w.endswith("ss"):
            w = w[:-1]
        out.append(w)
    return " ".join(out)


def prompt_key(text: str) -> str:
    return "".join(ch for ch in str(text or "").lower() if ch.isalnum())


# ---------------------------------------------------------------------------
# validation: everything here is spoken aloud by the quizmaster
# ---------------------------------------------------------------------------


def validate_item(item) -> tuple[bool, str]:
    if not isinstance(item, dict):
        return False, "not an object"
    for field, limit in (("prompt", 220), ("answer", 40), ("hint", 120)):
        value = item.get(field)
        ok, reason = topic_gen._tts_clean(value if isinstance(value, str) else "")
        if not ok:
            return False, f"bad {field}: {reason}"
        if len(value) > limit:
            return False, f"{field} too long"
    fact = item.get("fact")
    if fact is not None:
        ok, reason = topic_gen._tts_clean(fact if isinstance(fact, str) else "")
        if not ok or len(fact) > 200:
            return False, "bad fact"
    accepts = item.get("accepts")
    if not isinstance(accepts, list) or len(accepts) > 8:
        return False, "accepts must be a short list"
    if any(not isinstance(a, str) or not a.strip() or len(a) > 40 for a in accepts):
        return False, "bad accepted answer"
    if not answer_key(item["answer"]):
        return False, "empty answer"
    # Giving the answer away in the question or the hint ruins it.
    key = answer_key(item["answer"])
    if len(key) >= 4 and (key in answer_key(item["prompt"]) or key in answer_key(item["hint"])):
        return False, "answer appears in the prompt or hint"
    return True, ""


def _coerce(raw) -> dict | None:
    if not isinstance(raw, dict):
        return None
    accepts = raw.get("accepts") or []
    if isinstance(accepts, str):
        accepts = [accepts]
    fact = raw.get("fact")
    fact = str(fact).strip() if fact else None
    return {
        "prompt": str(raw.get("prompt") or raw.get("question") or "").strip(),
        "answer": str(raw.get("answer") or "").strip(),
        "accepts": [str(a).strip() for a in accepts if str(a).strip()][:8]
                   if isinstance(accepts, list) else [],
        "hint": str(raw.get("hint") or "").strip(),
        "fact": fact or None,
    }


# ---------------------------------------------------------------------------
# generation
# ---------------------------------------------------------------------------

_ANGLES = {
    "riddle": (
        "classic what-am-I riddles about everyday objects",
        "silly pun riddles that make kids groan and laugh",
        "riddles about animals and nature",
        "riddles about food and the kitchen",
        "riddles about things you see on a road trip",
        "lateral-thinking riddles with a twist",
    ),
    "quiz": (
        "surprising animal facts",
        "space, planets and the night sky",
        "the human body",
        "world geography and famous places",
        "food from around the world",
        "inventions and how everyday things were invented",
        "weird science that sounds made up but is true",
        "dinosaurs and prehistoric life",
    ),
}


def build_prompt(kind: str, count: int, exclude: list[str]) -> str:
    angle = random.choice(_ANGLES[kind])
    if kind == "riddle":
        what = (f"{count} family-friendly riddles for a car full of kids and adults. "
                f"Theme for this batch: {angle}. Each needs a short, definite answer "
                "that people can shout out loud.")
    else:
        what = (f"{count} fun, educational quiz questions for a car full of kids and adults. "
                f"Theme for this batch: {angle}. Open answer (no multiple choice), "
                "with a short answer people can shout out, and a fun fact that makes "
                "people say 'no way!'.")
    avoid = ""
    if exclude:
        avoid = ("\nThese answers have ALREADY been used. Do not use any of them, "
                 "or anything that is basically the same thing:\n"
                 + ", ".join(exclude[:EXCLUDE_IN_PROMPT]) + "\n")
    return (
        f"Write {what}\n"
        "Return ONLY a JSON object: {\"items\": [{\"prompt\": \"...\", \"answer\": \"...\", "
        "\"accepts\": [\"other ways people would say the answer\"], \"hint\": \"...\", "
        "\"fact\": \"...\"}]}\n"
        "Rules: everything is read aloud by a voice, so plain words only (no emojis, "
        "no markdown, no symbols, no abbreviations). prompt under 200 characters. "
        "answer 1 to 4 words, e.g. 'a piano'. accepts: up to 5 alternative spoken forms "
        "(synonyms, digits for numbers). hint: one short clue that does not contain the "
        "answer. fact: one short funny or surprising sentence, or a punchline."
        f"{avoid}"
    )


def _parse_items(text: str) -> list:
    text = (text or "").strip()
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]
    try:
        parsed = json.loads(text)
    except Exception as exc:
        raise GenError(f"could not parse model JSON: {exc}")
    if isinstance(parsed, dict):
        parsed = parsed.get("items")
    if not isinstance(parsed, list):
        raise GenError("model did not return a list of items")
    return parsed


def _openai_batch(prompt: str) -> list:
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise GenError("OPENAI_API_KEY is not set")
    body = json.dumps({
        "model": os.environ.get("TRAVEL_TEXT_MODEL", "gpt-4o-mini"),
        "temperature": 1.0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system",
             "content": "You are a witty road-trip quizmaster writing content for families."},
            {"role": "user", "content": prompt},
        ],
    }).encode("utf-8")
    req = urllib.request.Request(_OPENAI_CHAT, data=body, headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "User-Agent": "AuroraPlay/1.0 (travel-items)",
    })
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        text = data["choices"][0]["message"]["content"]
    except Exception as exc:
        raise GenError(f"OpenAI request failed: {exc}")
    return _parse_items(text)


def _gemini_batch(prompt: str) -> list:
    try:
        model = topic_gen._genai_model(temperature=1.0)
        text = model.generate_content(prompt).text
    except topic_gen._GenError as exc:
        raise GenError(str(exc))
    except Exception as exc:
        raise GenError(f"Gemini request failed: {exc}")
    return _parse_items(text)


def generate(kind: str, count: int, exclude: list[str]) -> tuple[list[dict], str]:
    """One batch from the first model that answers. Raises GenError when
    none does (no keys, offline, bad output)."""
    prompt = build_prompt(kind, count, exclude)
    blocked = {answer_key(a) for a in exclude}
    errors = []
    for name, call in (("openai", _openai_batch), ("gemini", _gemini_batch)):
        try:
            raw = call(prompt)
        except GenError as exc:
            errors.append(f"{name}: {exc}")
            continue
        good, seen = [], set()
        for r in raw:
            item = _coerce(r)
            if item is None or not validate_item(item)[0]:
                continue
            k = answer_key(item["answer"])
            if k in blocked or k in seen:
                continue   # the model ignored the exclusion list
            seen.add(k)
            good.append(item)
        if good:
            return good, name
        errors.append(f"{name}: no usable items")
    raise GenError("; ".join(errors))


# ---------------------------------------------------------------------------
# storage: a shared pool + per-device answer history (best-effort JSON)
# ---------------------------------------------------------------------------


def _data_path(env: str, name: str) -> Path:
    override = os.environ.get(env)
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1] / "data" / name


def _load(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save(path: Path, data: dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass   # persistence is best-effort


def _pool_path() -> Path:
    return _data_path("TRAVEL_ITEMS_POOL_PATH", "travel_items_pool.json")


def _served_path() -> Path:
    return _data_path("TRAVEL_ITEMS_SERVED_PATH", "travel_items_served.json")


def _served_answers(device: str | None, kind: str) -> list[str]:
    if not device:
        return []
    entry = _load(_served_path()).get(device) or {}
    items = entry.get(kind) if isinstance(entry, dict) else None
    return list(items) if isinstance(items, list) else []


def _record_served(device: str | None, kind: str, items: list[dict]) -> None:
    if not device or not items:
        return
    data = _load(_served_path())
    entry = data.get(device)
    if not isinstance(entry, dict):
        entry = {}
    have = entry.get(kind) if isinstance(entry.get(kind), list) else []
    known = set(have)
    for item in items:
        k = answer_key(item["answer"])
        if k and k not in known:
            have.append(k)
            known.add(k)
    entry[kind] = have[-SERVED_MAX_PER_DEVICE:]
    data[device] = entry
    _save(_served_path(), data)


def get_items(kind: str, count: int, device: str | None = None,
              seen: list[str] | None = None) -> tuple[list[dict], str]:
    """Up to ``count`` items this device hasn't heard. Never raises."""
    count = max(1, min(count, 20))
    heard = {answer_key(a) for a in (seen or [])[-SEEN_MAX_FROM_CLIENT:]}
    with _lock:
        heard |= set(_served_answers(device, kind))
        pool = [i for i in _load(_pool_path()).get(kind, []) if isinstance(i, dict)]
    heard.discard("")

    fresh = [i for i in pool if answer_key(i.get("answer")) not in heard]
    random.shuffle(fresh)
    items, source = fresh[:count], "pool"

    if len(items) < count:
        # Exclude what this device heard AND what the pool already holds,
        # so every model call also grows the pool with new answers. (No
        # lock held here: a model call can take many seconds.)
        exclude = list(dict.fromkeys(
            list(heard) + [answer_key(i.get("answer")) for i in pool]))
        random.shuffle(exclude)
        try:
            made, source = generate(kind, BATCH, exclude)
        except GenError:
            made = []
            if not items:
                source = "none"
        if made:
            with _lock:
                pool_data = _load(_pool_path())
                current = [i for i in pool_data.get(kind, []) if isinstance(i, dict)]
                known = {answer_key(i.get("answer")) for i in current}
                new = [i for i in made if answer_key(i["answer"]) not in known]
                if new:
                    pool_data[kind] = (current + new)[-POOL_MAX_PER_KIND:]
                    _save(_pool_path(), pool_data)
        have = {answer_key(i["answer"]) for i in items}
        for i in made:
            if len(items) >= count:
                break
            k = answer_key(i["answer"])
            if k not in heard and k not in have:
                items.append(i)
                have.add(k)

    with _lock:
        _record_served(device, kind, items)
    return items, source


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

travel_items_bp = Blueprint("travel_items", __name__)


@travel_items_bp.route("/items", methods=["POST"])
def travel_items():
    data = request.get_json(force=True, silent=True) or {}
    kind = str(data.get("kind") or "")
    if kind not in KINDS:
        return jsonify({"success": False, "error": "kind must be riddle or quiz"}), 400
    try:
        count = int(data.get("count") or 8)
    except (TypeError, ValueError):
        count = 8
    device = str(data.get("device") or "").strip()[:64] or None
    raw_seen = data.get("seen")
    seen = [str(s)[:60] for s in raw_seen if isinstance(s, str)] \
        if isinstance(raw_seen, list) else []
    items, source = get_items(kind, count, device=device,
                              seen=seen[-SEEN_MAX_FROM_CLIENT:])
    return jsonify({"success": True, "kind": kind, "source": source, "items": items})
