"""Live topic-based question generation for Travel Mode.

The passenger types a TOPIC ("Tollywood movies", "cricket", "world
capitals") instead of picking a fixed pack; the server generates fresh
questions on demand.

Chain per call for trivia questions: session dedupe -> topic cache
(in-memory + JSON file) -> Open Trivia DB (free, no key) for topics that
map to one of its categories -> Gemini batch generation for arbitrary
free-text topics that don't map -> bundled-pack fallback (offline or any
API failure). Twenty-questions secrets and hot-takes prompts skip
OpenTDB (it only serves multiple-choice trivia) and go cache -> Gemini
-> bundled.

The Gemini integration is REUSED from games/trivia/routes.py (the
gemini-2.0-flash-exp model and the JSON-array prompt shape) rather than
a new provider. Notes on the deprecation: google.generativeai 0.8.6 is
end-of-life upstream and its import emits a FutureWarning pointing at
the google.genai package. The import here is lazy (only when generation
is actually attempted) so the warning never fires on app startup or in
tests, and every failure mode (no key, import error, API error) drops
cleanly to the bundled packs, so the deprecation can never break a
game. Migrating to google.genai later is a small change: swap
_genai_model() for genai.Client(api_key=...) and
client.models.generate_content().

The iOS worker's contract is the topic_bp blueprint below, registered at
/api/travel in app.py:

    GET /api/travel/questions?topic=<topic>&count=10
    GET /api/travel/secrets?topic=<topic>&count=5
    GET /api/travel/hot_takes?topic=<topic>&count=5

All responses are JSON: {"success": true, "topic": ..., "source":
"opentdb"|"llm"|"cache"|"bundled", "fallback": true|false, ...items}.
``fallback`` is true exactly when the bundled packs served the request
(offline or API failure) -- that is the signal the iOS client uses to
fall back to its own offline deck or the legacy POST /trivia/generate
path (whose result it can then inject via create_room "seedQuestions").
"""

import html
import json
import os
import random
import re
import threading
import urllib.parse
import urllib.request
from pathlib import Path

from flask import Blueprint, jsonify, request

# ---------------------------------------------------------------------------
# validation
# ---------------------------------------------------------------------------

_EMOJI_RE = re.compile(
    "[" "\U0001F000-\U0001FAFF" "\u2600-\u27BF" "\u2B00-\u2BFF"
    "\uFE0F" "\u200D" "\u20E3" "\u2190-\u21FF" "\u2300-\u23FF" "]"
)
_EXEMPT = set("\u2660\u2665\u2666\u2663")  # card suits read fine

#: Text patterns that read badly through a speech synthesizer.
_TTS_HOSTILE = ("w/", "http://", "https://", "www.", "<", ">", "**", "__")


def _tts_clean(text: str) -> tuple[bool, str]:
    """True when ``text`` is safe to read aloud via AVSpeechSynthesizer."""
    if not text or not text.strip():
        return False, "empty text"
    if text != text.strip():
        return False, "leading/trailing whitespace"
    if any(ch in text for ch in "*#"):
        return False, "markdown characters"
    if any(p in text for p in _TTS_HOSTILE):
        return False, "TTS-hostile pattern"
    bad = [c for c in text if _EMOJI_RE.match(c) and c not in _EXEMPT]
    if bad:
        return False, "emoji"
    return True, ""


def _norm(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum())


def norm_topic(topic: str) -> str:
    """Canonical cache/dedupe key for a free-text topic."""
    return re.sub(r"\s+", " ", (topic or "").strip().lower())


def validate_question(q) -> tuple[bool, str]:
    """A generated trivia question must have exactly 4 distinct choices and
    exactly one correct answer, and every string must be TTS-clean."""
    if not isinstance(q, dict):
        return False, "not an object"
    question = q.get("question")
    ok, reason = _tts_clean(question if isinstance(question, str) else "")
    if not ok:
        return False, f"bad question text: {reason}"
    if len(question) > 300:
        return False, "question too long"
    options = q.get("options")
    if not isinstance(options, list) or len(options) != 4:
        return False, "must have exactly 4 options"
    for opt in options:
        ok, reason = _tts_clean(opt if isinstance(opt, str) else "")
        if not ok:
            return False, f"bad option: {reason}"
        if len(opt) > 120:
            return False, "option too long"
    if len({_norm(o) for o in options}) != 4:
        return False, "options must be distinct"
    correct = q.get("correct_answer")
    if not isinstance(correct, int) or isinstance(correct, bool):
        return False, "correct_answer must be an integer"
    if not 0 <= correct <= 3:
        return False, "correct_answer must be 0-3"
    return True, ""


def validate_secret(item) -> tuple[bool, str]:
    """A twenty_questions secret: one short familiar name, TTS-clean."""
    if not isinstance(item, str):
        return False, "not a string"
    ok, reason = _tts_clean(item)
    if not ok:
        return False, reason
    if len(item) > 60:
        return False, "secret too long"
    return True, ""


def validate_hot_take(prompt) -> tuple[bool, str]:
    """A hot_takes prompt: one short debatable question, TTS-clean."""
    if not isinstance(prompt, str):
        return False, "not a string"
    ok, reason = _tts_clean(prompt)
    if not ok:
        return False, reason
    if len(prompt) > 200:
        return False, "prompt too long"
    if not prompt.endswith("?"):
        return False, "must be a question"
    return True, ""


_VALIDATORS = {
    "questions": validate_question,
    "secrets": validate_secret,
    "hot_takes": validate_hot_take,
}

# ---------------------------------------------------------------------------
# LLM batch generation (reuses the games/trivia/routes.py integration)
# ---------------------------------------------------------------------------

BATCH_SIZE = 10          # never one question per round-trip
_MODEL_NAME = "gemini-2.0-flash-exp"


class _GenError(Exception):
    """Anything that means 'fall back to the bundled packs'."""


def _genai_model(temperature: float | None = None):
    """Lazily build the Gemini model, exactly like games/trivia/routes.py.

    Raises _GenError when there is no API key, the package is missing, or
    configuration fails -- the caller treats all of these as 'use the
    bundled packs'.
    """
    try:
        import google.generativeai as genai  # lazy: deprecation warning only on use
    except ImportError as exc:
        raise _GenError(f"google.generativeai not installed: {exc}")
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise _GenError("GEMINI_API_KEY is not set")
    genai.configure(api_key=api_key)
    if temperature is None:
        return genai.GenerativeModel(_MODEL_NAME)
    return genai.GenerativeModel(
        _MODEL_NAME,
        generation_config=genai.GenerationConfig(temperature=temperature),
    )


def _llm_batch(kind: str, topic: str, count: int,
               exclude: tuple = ()) -> list:
    """One batched model call. Returns raw parsed objects (unvalidated).

    Temperature is high (0.9) so repeat topics come back different, and the
    exclusion list keeps the model from paraphrasing questions the device
    has already seen.

    Raises _GenError on any failure so the caller falls back.
    """
    avoid = "\n".join(f"- {t[:160]}" for t in exclude[:40] if t)
    avoid_block = (
        "\nDo NOT repeat or closely paraphrase any of these recently asked "
        f"items:\n{avoid}\n" if avoid else ""
    )
    # Rotate the angle each call so even a cold model varies its output.
    angles = ("", " This time lean into records, statistics, and firsts.",
              " This time lean into people and personalities.",
              " This time lean into recent events and modern history.",
              " This time lean into origins and 'how it started' stories.")
    angle = random.choice(angles)
    if kind == "questions":
        instruction = (
            f"Generate {count} multiple-choice trivia questions about {topic}.{angle}\n"
            "Return ONLY a JSON array, no other text, with this exact shape:\n"
            '[{"question": "Question text?", '
            '"options": ["A", "B", "C", "D"], "correct_answer": 0}]\n'
            "Rules: exactly 4 distinct options, correct_answer is the 0-based "
            "index of the single correct option, plain text only (no emojis, "
            "no markdown, no abbreviations like w/), family-friendly, and "
            "phrased to sound natural when read aloud."
            f"{avoid_block}"
        )
    elif kind == "secrets":
        instruction = (
            f"List {count} well-known, family-friendly things related to {topic} "
            "(places, foods, movies, animals, or objects) suitable for a game "
            f"of Twenty Questions.{angle}\n"
            "Return ONLY a JSON array of short names, no other text, e.g. "
            '["Eiffel Tower", "Pizza"].\n'
            "Rules: each name 1-4 words, plain text, no emojis, no duplicates."
            f"{avoid_block}"
        )
    elif kind == "hot_takes":
        instruction = (
            f"Write {count} fun, family-friendly debate prompts related to {topic}, "
            f'in the style of "Is a hot dog a sandwich?".{angle}\n'
            "Return ONLY a JSON array of question strings, no other text.\n"
            "Rules: each is one short debatable question ending with a question "
            "mark, plain text, no emojis, no duplicates."
            f"{avoid_block}"
        )
    else:
        raise _GenError(f"unknown kind: {kind}")

    # OpenAI first (the key the voice already uses), then Gemini -- the
    # shared helper in games/llm_json.py. The prompt asks for a bare JSON
    # array; OpenAI's JSON mode wraps it as {"items": [...]}, which the
    # helper unwraps.
    from games import llm_json
    try:
        parsed, _provider = llm_json.json_items(
            instruction + '\nIf you must return an object, use {"items": [...]}.')
    except llm_json.LLMError as exc:
        raise _GenError(str(exc))
    return parsed


def _validated_batch(kind: str, topic: str, count: int,
                     exclude: tuple = ()) -> list:
    """One LLM batch with invalid generations dropped (never regenerated one
    at a time -- cost and latency). Raises _GenError when the call itself
    fails."""
    validator = _VALIDATORS[kind]
    good = []
    for raw in _llm_batch(kind, topic, count, exclude):
        item = _coerce(kind, raw)
        ok, _ = validator(item)
        if ok:
            good.append(item)
    return good


def _coerce(kind: str, raw):
    """Normalize one raw generation into the stored shape."""
    if kind == "questions" and isinstance(raw, dict):
        return {
            "question": str(raw.get("question", "")).strip(),
            "options": [str(o).strip() for o in (raw.get("options") or [])],
            "correct_answer": raw.get("correct_answer"),
        }
    return raw.strip() if isinstance(raw, str) else raw


# ---------------------------------------------------------------------------
# Open Trivia DB (free, no key) -- first-priority live source for questions
# ---------------------------------------------------------------------------

_OPENTDB_API = "https://opentdb.com/api.php"
_OPENTDB_GENERAL_KNOWLEDGE = 9

#: Free-text topic -> OpenTDB category id. Specific entries first (board
#: games before video games, musicals before music). Matched against
#: normalized words, so "car" never fires on "cartoon" and "tv" never
#: fires on "festival".
_OPENTDB_TOPIC_KEYWORDS: tuple[tuple[int, tuple[str, ...]], ...] = (
    (16, ("board game", "chess", "card game")),
    (15, ("video game", "gaming", "game", "esports")),
    (13, ("musical", "theatre", "theater", "broadway")),
    (12, ("music", "song", "band", "singer", "album", "concert")),
    (11, ("film", "movie", "cinema", "bollywood", "hollywood", "tollywood",
           "kollywood")),
    (14, ("tv", "television", "series", "netflix", "show")),
    (31, ("anime", "manga")),
    (32, ("cartoon", "animation")),
    (29, ("comic", "superhero", "marvel")),
    (10, ("book", "novel", "author", "literature", "poetry")),
    (18, ("computer", "tech", "coding", "programming", "software", "internet",
           "ai")),
    (30, ("gadget", "smartphone", "iphone")),
    (19, ("math", "algebra", "geometry")),
    (17, ("science", "physics", "chemistry", "biology", "nature", "space",
           "planet")),
    (20, ("mythology", "myth", "greek god", "norse")),
    (21, ("sport", "cricket", "football", "soccer", "tennis", "basketball",
           "olympic", "ipl", "golf", "baseball")),
    (22, ("geography", "capital", "country", "countries", "world", "continent",
           "map", "city")),
    (23, ("history", "ancient", "war", "civilization")),
    (24, ("politic", "election", "president", "government")),
    (25, ("art", "painting", "sculpture", "artist")),
    (26, ("celebrity", "actor", "actress", "famous")),
    (27, ("animal", "wildlife", "dog", "cat", "bird", "fish", "insect",
           "pet")),
    (28, ("vehicle", "car", "truck", "bike", "airplane", "train")),
)


def _topic_words(topic: str) -> set[str]:
    """Normalized words plus crude singular stems ("movies" -> "movie")."""
    words = set(re.findall(r"[a-z0-9]+", topic))
    stems = set()
    for w in words:
        if len(w) > 4 and w.endswith("ies"):
            stems.add(w[:-3] + "y")          # countries -> country
        elif len(w) > 4 and w.endswith("s") and not w.endswith("ss"):
            stems.add(w[:-1])                # movies -> movie
    return words | stems


def topic_to_opentdb_category(topic: str) -> int | None:
    """Map a free-text topic to the closest OpenTDB category id.

    Returns None when nothing maps -- those topics go to the LLM
    instead. An empty topic defaults to General Knowledge so the
    endpoint can serve free questions with no topic at all.
    """
    t = norm_topic(topic)
    if not t:
        return _OPENTDB_GENERAL_KNOWLEDGE
    words = _topic_words(t)
    for category_id, keywords in _OPENTDB_TOPIC_KEYWORDS:
        for kw in keywords:
            if " " in kw:
                if kw in t:
                    return category_id
            elif kw in words:
                return category_id
            elif len(kw) >= 6 and kw in t:
                # Long distinctive stems may match inside a word
                # ("cricket" in "cricketer").
                return category_id
    return None


def _opentdb_to_question(raw: dict) -> dict:
    """Convert one OpenTDB result into the stored question shape.

    OpenTDB HTML-entity-encodes its text (&quot; &#039; &amp; ...), so
    everything is unescaped (and any stray markup stripped) before the
    options are shuffled.
    """
    def clean(text) -> str:
        text = html.unescape(str(text or ""))
        text = re.sub(r"<[^>]+>", "", text)
        return re.sub(r"\s+", " ", text).strip()

    options = [clean(raw.get("correct_answer"))]
    options += [clean(o) for o in (raw.get("incorrect_answers") or [])]
    order = list(range(len(options)))
    random.shuffle(order)
    shuffled = [options[i] for i in order]
    return {
        "question": clean(raw.get("question")),
        "options": shuffled,
        "correct_answer": order.index(0),
    }


_OPENTDB_TOKEN_API = "https://opentdb.com/api_token.php"

_opentdb_token_value: str | None = None
_opentdb_token_lock = threading.Lock()


def _opentdb_token_path() -> Path:
    override = os.environ.get("OPENTDB_TOKEN_PATH")
    if override:
        return Path(override)
    repo_root = Path(__file__).resolve().parents[1]
    return repo_root / "data" / "opentdb_token.txt"


def _opentdb_token() -> str | None:
    """Session token so OpenTDB never repeats a question within its pool.

    Without a token every api.php call draws *with replacement* -- repeats
    are statistically guaranteed, worse in small categories. The token is
    fetched once, persisted to data/opentdb_token.txt, and passed on every
    batch. Returns None when the token endpoint is unreachable (the batch
    still goes out untokened rather than failing the game).
    """
    global _opentdb_token_value
    with _opentdb_token_lock:
        if _opentdb_token_value:
            return _opentdb_token_value
        try:
            _opentdb_token_value = _opentdb_token_path().read_text(
                encoding="utf-8").strip() or None
        except OSError:
            pass
        if _opentdb_token_value:
            return _opentdb_token_value
        try:
            req = urllib.request.Request(
                f"{_OPENTDB_TOKEN_API}?command=request",
                headers={"User-Agent": "AuroraPlay/1.0 (Travel Mode)"},
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            token = (payload or {}).get("token")
        except Exception:
            return None
        if not token:
            return None
        _opentdb_token_value = token
        try:
            _opentdb_token_path().parent.mkdir(parents=True, exist_ok=True)
            _opentdb_token_path().write_text(token, encoding="utf-8")
        except OSError:
            pass
        return token


def _opentdb_drop_token() -> None:
    """Forget the token (response_code 3: expired). Next batch re-requests."""
    global _opentdb_token_value
    with _opentdb_token_lock:
        _opentdb_token_value = None
    try:
        _opentdb_token_path().unlink()
    except OSError:
        pass


def _opentdb_reset_token(token: str) -> None:
    """response_code 4: the pool is exhausted for this token -- reset it."""
    try:
        req = urllib.request.Request(
            f"{_OPENTDB_TOKEN_API}?command=reset&token={token}",
            headers={"User-Agent": "AuroraPlay/1.0 (Travel Mode)"},
        )
        with urllib.request.urlopen(req, timeout=10):
            pass
    except Exception:
        pass


def _opentdb_batch(topic: str, category_id: int, count: int,
                   exclude: tuple = ()) -> list[dict]:
    """One batched OpenTDB call (amount=N, never one question per
    round-trip). Returns validated question dicts; invalid ones are
    dropped. Raises _GenError on any failure so the caller falls back.

    The session token guarantees no repeats within the pool; ``exclude``
    (normalized question texts) additionally filters anything the device
    has already seen, over-requesting to top the batch back up.

    Etiquette: a single batched request per topic, and every usable
    question is cached aggressively (in-memory + persisted) so replays
    never re-hit the API.
    """
    amount = min(max(count + len(exclude), BATCH_SIZE), 50)
    params = {
        "amount": amount,
        "category": category_id,
        "type": "multiple",
    }
    token = _opentdb_token()
    if token:
        params["token"] = token

    def _call(extra: dict | None = None) -> dict:
        q = dict(params)
        if extra:
            q.update(extra)
        req = urllib.request.Request(
            f"{_OPENTDB_API}?{urllib.parse.urlencode(q)}",
            headers={"User-Agent": "AuroraPlay/1.0 (Travel Mode)"},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
        except Exception as exc:
            raise _GenError(f"OpenTDB request failed: {exc}")
        if not isinstance(payload, dict):
            raise _GenError("OpenTDB bad response_code: ?")
        return payload

    payload = _call()
    code = payload.get("response_code")
    if code == 3 and token:
        # Token expired (6 h idle) -- fetch a fresh one and retry once.
        _opentdb_drop_token()
        token = _opentdb_token()
        payload = _call({"token": token} if token else None)
        code = payload.get("response_code")
    if code == 4 and token:
        # Pool exhausted for this token -- reset and retry once.
        _opentdb_reset_token(token)
        payload = _call()
        code = payload.get("response_code")
    if code != 0:
        raise _GenError(f"OpenTDB bad response_code: {code}")
    results = payload.get("results")
    if not isinstance(results, list):
        raise _GenError("OpenTDB results not a list")
    excluded = {_norm(t) for t in exclude if t}
    good = []
    for raw in results:
        if not isinstance(raw, dict):
            continue
        q = _opentdb_to_question(raw)
        ok, _ = validate_question(q)
        if ok and _norm(q["question"]) not in excluded:
            good.append(q)
    return good


def _live_questions(topic: str, count: int,
                    exclude: tuple = ()) -> tuple[list, str]:
    """Live question batch for a topic. OpenTDB (free, no key) serves
    topics that map to one of its categories; the LLM serves arbitrary
    free-text topics that don't map. Returns (items, source) and raises
    _GenError when the chosen source fails -- the caller then falls back
    to the bundled packs (strict priority: a mapped topic never burns
    LLM budget on an OpenTDB outage).
    """
    category = topic_to_opentdb_category(topic)
    if category is not None:
        return _opentdb_batch(topic, category, count, exclude), "opentdb"
    return _validated_batch("questions", topic, count, exclude), "llm"


# ---------------------------------------------------------------------------
# cache: in-memory + JSON file
# ---------------------------------------------------------------------------

_CACHE: dict[str, dict[str, list]] = {}
_CACHE_LOCK = threading.Lock()
_CACHE_MAX_TOPICS = 100
_CACHE_MAX_PER_KIND = 200


def _cache_path() -> Path:
    override = os.environ.get("TOPIC_CACHE_PATH")
    if override:
        return Path(override)
    repo_root = Path(__file__).resolve().parents[1]
    return repo_root / "data" / "topic_cache.json"


def _cache_load() -> None:
    try:
        data = json.loads(_cache_path().read_text(encoding="utf-8"))
    except Exception:
        return
    if not isinstance(data, dict):
        return
    with _CACHE_LOCK:
        _CACHE.clear()
        for topic, entry in list(data.items())[:_CACHE_MAX_TOPICS]:
            if isinstance(entry, dict):
                _CACHE[str(topic)] = {
                    kind: list(entry.get(kind, []))[:_CACHE_MAX_PER_KIND]
                    for kind in _VALIDATORS
                }

# ---------------------------------------------------------------------------
# persistent per-device served history (kills repeats *across* games)
# ---------------------------------------------------------------------------
# The per-topic cache is a pool: once warm, every game would draw the same
# batch. The client sends its own asked-history as `exclude`, but a fresh
# install (or a second device) has no history -- so the server keeps its
# own: normalized question texts per device id, capped, best-effort.

_SERVED_MAX_PER_DEVICE = 500
_served_lock = threading.Lock()


def _served_path() -> Path:
    override = os.environ.get("TOPIC_SERVED_PATH")
    if override:
        return Path(override)
    repo_root = Path(__file__).resolve().parents[1]
    return repo_root / "data" / "topic_served.json"


def _served_get(device: str | None) -> set[str]:
    if not device:
        return set()
    with _served_lock:
        try:
            data = json.loads(_served_path().read_text(encoding="utf-8"))
        except Exception:
            return set()
        items = data.get(device) if isinstance(data, dict) else None
        return set(items) if isinstance(items, list) else set()


def _served_add(device: str | None, texts: list[str]) -> None:
    if not device or not texts:
        return
    with _served_lock:
        try:
            data = json.loads(_served_path().read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                data = {}
        except Exception:
            data = {}
        have = data.get(device)
        if not isinstance(have, list):
            have = []
        known = set(have)
        for t in texts:
            n = _norm(t)
            if n and n not in known:
                have.append(n)
                known.add(n)
        data[device] = have[-_SERVED_MAX_PER_DEVICE:]
        try:
            _served_path().parent.mkdir(parents=True, exist_ok=True)
            _served_path().write_text(json.dumps(data), encoding="utf-8")
        except OSError:
            pass


def _cache_save() -> None:
    try:
        path = _cache_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        with _CACHE_LOCK:
            snapshot = {t: {k: v[:] for k, v in e.items()}
                        for t, e in _CACHE.items()}
        path.write_text(json.dumps(snapshot, ensure_ascii=False, indent=1),
                        encoding="utf-8")
    except Exception:
        pass  # cache persistence is best-effort; memory cache still works


def _cache_get(topic_key: str, kind: str) -> list:
    with _CACHE_LOCK:
        return list(_CACHE.get(topic_key, {}).get(kind, []))


def _cache_add(topic_key: str, kind: str, items: list) -> None:
    if not items:
        return
    with _CACHE_LOCK:
        entry = _CACHE.setdefault(topic_key, {k: [] for k in _VALIDATORS})
        have = {_norm(_item_text(kind, i)) for i in entry[kind]}
        for item in items:
            if _norm(_item_text(kind, item)) not in have:
                entry[kind].append(item)
                have.add(_norm(_item_text(kind, item)))
        entry[kind] = entry[kind][-_CACHE_MAX_PER_KIND:]
        while len(_CACHE) > _CACHE_MAX_TOPICS:
            _CACHE.pop(next(iter(_CACHE)))
    _cache_save()


def _item_text(kind: str, item) -> str:
    if kind == "questions":
        return item.get("question", "") if isinstance(item, dict) else ""
    return item if isinstance(item, str) else ""


_cache_load()

# ---------------------------------------------------------------------------
# bundled-pack fallback (offline safety net, not the primary source)
# ---------------------------------------------------------------------------


def _bundled(kind: str, count: int, seen: set[str]) -> list:
    """Fixed packs as the offline fallback."""
    if kind == "questions":
        from games.native_hub.engines.legacy_social import TRIVIA_QUESTIONS
        pool = [
            {"question": q, "options": list(opts), "correct_answer": idx}
            for _cat, q, opts, idx in TRIVIA_QUESTIONS
            if _norm(q) not in seen
        ]
    elif kind == "secrets":
        from games.native_hub.engines.talk import TWENTY_THINGS
        pool = [item for items in TWENTY_THINGS.values() for item in items
                if _norm(item) not in seen]
    else:  # hot_takes
        from games.native_hub.engines.talk import HOT_TAKES
        pool = [p for p in HOT_TAKES if _norm(p) not in seen]
    return random.sample(pool, min(count, len(pool)))


# ---------------------------------------------------------------------------
# public chain: session dedupe -> topic cache -> LLM batch -> bundled
# ---------------------------------------------------------------------------


def _fetch(kind: str, topic: str, count: int,
           session_history=None, device: str | None = None) -> tuple[list, str]:
    """Return (items, source). Never raises: the bundled fallback always
    answers, even when the topic is empty or the API is down.

    ``device`` enables the persistent served history: the server's own
    memory of what this device has already seen, merged with the client's
    ``session_history``. Everything served is recorded, so back-to-back
    games never repeat -- even for a fresh client with no local history.
    """
    seen = _served_get(device) | {_norm(t) for t in (session_history or []) if t}
    key = norm_topic(topic)
    items: list = []
    source = "bundled"

    if key:
        cached = [i for i in _cache_get(key, kind)
                  if _norm(_item_text(kind, i)) not in seen]
        if len(cached) >= count:
            items = cached[:count]
            _served_add(device, [_item_text(kind, i) for i in items])
            return items, "cache"
        items = cached
        if items:
            source = "cache"
        try:
            need = max(count - len(items), BATCH_SIZE)
            if kind == "questions":
                # OpenTDB (free, no key) for mapped topics; the LLM for
                # arbitrary free-text topics that don't map.
                fresh, fresh_source = _live_questions(
                    topic.strip(), need, tuple(seen))
            else:
                fresh, fresh_source = (
                    _validated_batch(kind, topic.strip(), need, tuple(seen)),
                    "llm")
            known = {_norm(_item_text(kind, i)) for i in items}
            new = [i for i in fresh
                   if _norm(_item_text(kind, i)) not in seen
                   and _norm(_item_text(kind, i)) not in known]
            _cache_add(key, kind, new)
            items = items + new
            if new:
                source = fresh_source
        except _GenError:
            pass  # fall through to bundled
    elif kind == "questions":
        # No topic: a free general-knowledge batch, served live when
        # possible but never cached under an empty key.
        try:
            items = _opentdb_batch("", _OPENTDB_GENERAL_KNOWLEDGE, count,
                                   tuple(seen))
            source = "opentdb"
        except _GenError:
            pass

    if not items:
        # Nothing usable from the cache or the APIs: full bundled fallback.
        # A partial on-topic batch is returned short rather than mixed with
        # off-topic questions.
        items = _bundled(kind, count, seen)
        source = "bundled"
    items = items[:count]
    _served_add(device, [_item_text(kind, i) for i in items])
    return items, source


def get_questions(topic: str, count: int = 10, session_history=None,
                  device: str | None = None) -> list[dict]:
    """Fresh multiple-choice questions about ``topic``.

    Each item: {"question", "options" (4), "correct_answer" (0-3)} --
    the same shape the trivia engines consume.
    """
    items, _ = _fetch("questions", topic, max(1, count), session_history,
                      device=device)
    return items


def get_secrets(topic: str, count: int = 5, session_history=None,
                device: str | None = None) -> list[str]:
    """Fresh Twenty Questions secrets about ``topic``."""
    items, _ = _fetch("secrets", topic, max(1, count), session_history,
                      device=device)
    return items


def get_hot_takes(topic: str, count: int = 5, session_history=None,
                  device: str | None = None) -> list[str]:
    """Fresh debate prompts about ``topic``."""
    items, _ = _fetch("hot_takes", topic, max(1, count), session_history,
                      device=device)
    return items


def question_dict_to_tuple(topic: str, q: dict) -> tuple:
    """Convert a get_questions() item into the (category, question,
    options, answer_index) tuple the trivia engines consume."""
    return (topic.strip() or "General", q["question"], list(q["options"]),
            q["correct_answer"])


# ---------------------------------------------------------------------------
# HTTP contract for the iOS client
# ---------------------------------------------------------------------------

topic_bp = Blueprint("travel_topic", __name__)


def _clamp_count(raw, default: int) -> int:
    try:
        return max(1, min(20, int(raw)))
    except (TypeError, ValueError):
        return default


def _parse_exclude(raw) -> list[str]:
    """Already-asked question texts the client wants excluded (JSON array).

    The travel endpoint is stateless HTTP, so without this the per-topic
    cache returns the identical batch on every call and the client sees
    the same questions game after game. Capped so URLs stay sane.
    """
    if not raw:
        return []
    try:
        items = json.loads(raw)
    except (ValueError, TypeError):
        return []
    if not isinstance(items, list):
        return []
    # Clients send history oldest-first: keep the MOST RECENT 60. (Was
    # [:60], which kept the oldest and dropped exactly the texts most
    # likely to repeat next.)
    return [str(x)[:300] for x in items if isinstance(x, str)][-60:]


@topic_bp.route("/questions", methods=["GET"])
def travel_questions():
    """GET /api/travel/questions?topic=<topic>&count=10

    Free-text topic in, validated multiple-choice questions out.
    ``source`` tells the client where they came from.
    """
    topic = (request.args.get("topic") or "").strip()
    count = _clamp_count(request.args.get("count"), 10)
    exclude = _parse_exclude(request.args.get("exclude"))
    device = (request.args.get("device") or "").strip()[:64] or None
    items, source = _fetch("questions", topic, count, session_history=exclude,
                           device=device)
    return jsonify({"success": True, "topic": topic, "source": source,
                    "fallback": source == "bundled",
                    "questions": items})


@topic_bp.route("/secrets", methods=["GET"])
def travel_secrets():
    """GET /api/travel/secrets?topic=<topic>&count=5

    Twenty Questions secrets on the topic.
    """
    topic = (request.args.get("topic") or "").strip()
    count = _clamp_count(request.args.get("count"), 5)
    exclude = _parse_exclude(request.args.get("exclude"))
    device = (request.args.get("device") or "").strip()[:64] or None
    items, source = _fetch("secrets", topic, count, session_history=exclude,
                           device=device)
    return jsonify({"success": True, "topic": topic, "source": source,
                    "fallback": source == "bundled",
                    "secrets": items})


@topic_bp.route("/hot_takes", methods=["GET"])
def travel_hot_takes():
    """GET /api/travel/hot_takes?topic=<topic>&count=5

    Debate prompts on the topic.
    """
    topic = (request.args.get("topic") or "").strip()
    count = _clamp_count(request.args.get("count"), 5)
    exclude = _parse_exclude(request.args.get("exclude"))
    device = (request.args.get("device") or "").strip()[:64] or None
    items, source = _fetch("hot_takes", topic, count, session_history=exclude,
                           device=device)
    return jsonify({"success": True, "topic": topic, "source": source,
                    "fallback": source == "bundled",
                    "hot_takes": items})
