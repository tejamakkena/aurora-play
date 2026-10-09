"""Variety for every party game: one place that hands out prompts,
questions and words, and remembers who has already seen them.

Before this, each game drew from a small fixed list (7 Mind Meld
categories, 10 drawing prompts, 15 Wavelength spectra, 23 Bluff facts...)
and only avoided repeats inside one game -- Play Again, or the next game
night, started from scratch.

Where content comes from (all merged, deduped by a per-kind key):
  1. the lists in the engines (games/native_hub/engines/_content.py ...);
  2. the content library: games/content_library/<kind>.json, committed
     and grown offline with scripts/grow_content.py;
  3. a runtime pool the server grows in the background while it runs:
     the LLM (OpenAI, then Gemini; games/llm_json.py) for prompts, and
     Open Trivia DB (free, no key) for trivia questions.

What "already seen" means -- checked in this order, relaxed only when
nothing fresh is left:
  1. this ROOM, across Play Again (room.content_history);
  2. every player DEVICE at the table, across rooms and nights
     (players' ids are stable device UUIDs; saved to data/, best-effort);
  3. the current game's own picks (``avoid``).

Engines call ``pick(room, kind)``; nothing here ever blocks a game on the
network -- generation only runs in a background thread when the fresh
supply for a kind runs low.
"""

from __future__ import annotations

import importlib
import json
import os
import random
import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

ROOM_HISTORY_CAP = 400
DEVICE_HISTORY_CAP = 800
RUNTIME_POOL_CAP = 1500
LOW_WATER = 40                 # refill when fewer fresh items than this remain
REFILL_BATCH = 30
REFILL_MIN_INTERVAL = 90.0     # seconds between refills of one kind

_lock = threading.RLock()


# ---------------------------------------------------------------------------
# validation helpers
# ---------------------------------------------------------------------------

def _clean(text, limit: int) -> str | None:
    """A trimmed single line that reads fine on a TV and aloud, or None."""
    if not isinstance(text, str):
        return None
    from games.topic_gen import _tts_clean
    text = " ".join(text.split())
    ok, _ = _tts_clean(text)
    if not ok or len(text) > limit:
        return None
    return text


def norm_key(text) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(text or "").lower())


# ---------------------------------------------------------------------------
# kinds
# ---------------------------------------------------------------------------

@dataclass
class Kind:
    name: str
    #: Built-in items, already in the engine's native shape.
    bundled: Callable[[], list]
    #: JSON / model item -> native item, or None when invalid.
    parse: Callable[[Any], Any]
    #: Native item -> JSON-able form (library files, runtime pool).
    dump: Callable[[Any], Any]
    #: Native item -> dedupe key.
    key: Callable[[Any], str]
    #: What to ask the model for; None = no LLM generation for this kind.
    ask: str | None = None
    #: The shape of one item, shown to the model.
    example: str = '"..."'


def _text_kind(name, bundled, limit, ask, example, check=None) -> Kind:
    def parse(raw):
        text = _clean(raw, limit)
        if text is None or (check and not check(text)):
            return None
        return text
    return Kind(name, bundled, parse, lambda i: i, norm_key, ask, example)


def _bundled(module: str, attr: str) -> Callable[[], list]:
    def load():
        import importlib
        return list(getattr(importlib.import_module(module), attr))
    return load


_C = "games.native_hub.engines._content"


def _parse_bluff(raw):
    if isinstance(raw, (list, tuple)) and len(raw) == 2:
        raw = {"fact": raw[0], "answer": raw[1]}
    if not isinstance(raw, dict):
        return None
    fact = raw.get("fact")
    if not isinstance(fact, str) or fact.count("____") != 1:
        return None
    # The blank itself trips the "no markdown underscores" speech check.
    fact = _clean(fact.replace("____", "BLANKMARK"), 200)
    answer = _clean(raw.get("answer"), 30)
    if not fact or not answer:
        return None
    return (fact.replace("BLANKMARK", "____"), answer)


def _parse_pair(raw):
    if isinstance(raw, dict):
        raw = (raw.get("left"), raw.get("right"))
    if not isinstance(raw, (list, tuple)) or len(raw) != 2:
        return None
    left, right = _clean(raw[0], 22), _clean(raw[1], 22)
    if not left or not right or norm_key(left) == norm_key(right):
        return None
    return (left, right)


def _parse_wyr(raw):
    if isinstance(raw, dict):
        raw = (raw.get("left"), raw.get("right"))
    if not isinstance(raw, (list, tuple)) or len(raw) != 2:
        return None
    a, b = _clean(raw[0], 70), _clean(raw[1], 70)
    if not a or not b or norm_key(a) == norm_key(b):
        return None
    return (a, b)


def _parse_lot(raw):
    if isinstance(raw, dict):
        raw = (raw.get("lot"), raw.get("value"))
    if not isinstance(raw, (list, tuple)) or len(raw) != 2:
        return None
    lot, value = _clean(raw[0], 60), raw[1]
    if not lot or not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= 10:
        return None
    return (lot, value)


def _parse_word(raw):
    if not isinstance(raw, str):
        return None
    word = raw.strip().upper()
    return word if re.fullmatch(r"[A-Z]{3,10}", word) else None


def _parse_mc(raw):
    """Multiple-choice trivia: {"question", "options"[4], "correct_answer"}."""
    from games.topic_gen import validate_question
    if not isinstance(raw, dict):
        return None
    q = {"question": raw.get("question"), "options": raw.get("options"),
         "correct_answer": raw.get("correct_answer")}
    if not validate_question(q)[0]:
        return None
    category = _clean(raw.get("category"), 24)
    if category:
        q["category"] = category
    return q


def _parse_analogy(raw):
    """"a is to b as c is to answer": {"a", "b", "c", "answer", "accepts"}."""
    if not isinstance(raw, dict):
        return None
    parts = {k: _clean(raw.get(k), 30) for k in ("a", "b", "c", "answer")}
    if not all(parts.values()):
        return None
    accepts = [a for a in (_clean(x, 30) for x in raw.get("accepts") or []) if a][:5]
    return {**parts, "accepts": accepts}


def _parse_odd_word(raw):
    """Four words, one doesn't belong: {"words"[4], "answer", "why"}."""
    if not isinstance(raw, dict):
        return None
    words = [_clean(w, 24) for w in raw.get("words") or []]
    answer, why = _clean(raw.get("answer"), 24), _clean(raw.get("why"), 120)
    if len(words) != 4 or not all(words) or not answer or not why:
        return None
    if len({norm_key(w) for w in words}) != 4 or norm_key(answer) not in {norm_key(w) for w in words}:
        return None
    return {"words": words, "answer": answer, "why": why}


KINDS: dict[str, Kind] = {k.name: k for k in [
    _text_kind("herd", _bundled(_C, "HERD_PROMPTS"), 90,
               'short "Name a ..." prompts where everyone tries to give the SAME answer '
               "as the rest of the group (common, everyday categories)",
               '"Name a breakfast food."'),
    _text_kind("most_likely", _bundled(_C, "MOST_LIKELY_PROMPTS"), 120,
               'funny, kind "Most likely to ..." prompts for friends and family to vote on '
               "(never mean, rude or about appearance)",
               '"Most likely to fall asleep during a family movie night."',
               check=lambda t: t.lower().startswith("most likely to")),
    Kind("bluff", _bundled(_C, "BLUFF_FACTS"), _parse_bluff,
         lambda i: {"fact": i[0], "answer": i[1]}, lambda i: norm_key(i[0]),
         "TRUE but surprising facts with exactly one key word replaced by ____ , so players "
         "can invent fake answers to fool each other. The answer is 1-3 words. Only use "
         "facts you are certain are true",
         '{"fact": "The world\'s largest ____ weighs over 900 kilograms.", "answer": "pumpkin"}'),
    _text_kind("spy_location", _bundled(_C, "SPY_LOCATIONS"), 40,
               "everyday places for a Spyfall-style game, where everyone except the spy "
               "knows the place (e.g. a dentist's clinic, a cricket stadium)",
               '"Railway station"'),
    Kind("wavelength", _bundled(_C, "WAVELENGTH_SPECTRA"), _parse_pair,
         lambda i: {"left": i[0], "right": i[1]}, lambda i: norm_key(i[0] + "|" + i[1]),
         "opposite ends of a spectrum for the game Wavelength, where a clue-giver names "
         "something that sits somewhere between them (fun, debatable spectra)",
         '{"left": "Overrated", "right": "Underrated"}'),
    Kind("would_rather", _bundled("games.native_hub.engines._wyr", "DILEMMAS"), _parse_wyr,
         lambda i: {"left": i[0], "right": i[1]}, lambda i: norm_key(i[0] + "|" + i[1]),
         '"Would you rather" dilemmas for a family party: two funny, harmless choices, '
         'each a short phrase that completes "Would you rather ..." (never mean, scary or rude)',
         '{"left": "be able to fly", "right": "be able to turn invisible"}'),
    Kind("auction", _bundled(_C, "AUCTION_LOTS"), _parse_lot,
         lambda i: {"lot": i[0], "value": i[1]}, lambda i: norm_key(i[0]),
         "funny or dreamy things to bid on in a party auction game, each with a value "
         "from 1 (silly) to 10 (priceless)",
         '{"lot": "A lifetime of free chai", "value": 6}'),
    _text_kind("charades", _bundled(_C, "CHARADES_TITLES"), 50,
               "famous, widely known Indian movie titles (Hindi, Telugu, Tamil) that "
               "are fun to act out in dumb charades. Real titles only",
               '"Sholay"'),
    _text_kind("emoji_movie", _bundled(_C, "EMOJI_TITLES"), 50,
               "very famous movie titles from anywhere in the world that people could "
               "describe using only emoji. Real titles only",
               '"Titanic"'),
    _text_kind("meld_category", _bundled("games.native_hub.engines.legacy_new",
                                         "MELD_CATEGORIES"), 30,
               "simple categories where a group tries to think of the same word "
               "(e.g. Pizza toppings, Things in a fridge)",
               '"Things at a beach"'),
    _text_kind("draw_prompt", _bundled("games.native_hub.engines.legacy_new",
                                       "DRAW_PROMPTS"), 30,
               "simple, fun things to draw on a phone in under a minute "
               "(objects, animals, simple scenes)",
               '"A snowman"'),
    _text_kind("hot_take", _bundled("games.native_hub.engines.talk", "HOT_TAKES"), 160,
               'fun, family-friendly debate questions in the style of "Is a hot dog a '
               'sandwich?" (silly, never political or religious)',
               '"Is cereal a soup?"',
               check=lambda t: t.endswith("?")),
    Kind("cipher_word", _bundled(_C, "CIPHER_WORDS"), _parse_word, lambda i: i, norm_key,
         "single common English nouns, 3 to 10 letters, for a Codenames-style word grid",
         '"TIGER"'),
    Kind("mc", lambda: [], _parse_mc, lambda i: dict(i), lambda i: norm_key(i["question"]),
         "fun, family-friendly multiple-choice quiz questions for a game night in India: "
         "a mix of science, nature, geography, cricket and other sport, Indian and world "
         "movies and music, food, inventions, history and recent events. Exactly 4 "
         "options, one correct; correct_answer is its 0-based index",
         '{"question": "Which planet has the most moons?", '
         '"options": ["Earth", "Saturn", "Mars", "Venus"], "correct_answer": 1}'),
    Kind("analogy", lambda: [], _parse_analogy, lambda i: dict(i),
         lambda i: norm_key(f"{i['a']}|{i['b']}|{i['c']}"),
         "word analogies for a family brain game (\"Bird is to nest as bee is to ...\"), "
         "each with one clear, short answer and a few other accepted spoken forms",
         '{"a": "Bird", "b": "Nest", "c": "Bee", "answer": "Hive", "accepts": ["beehive"]}'),
    Kind("odd_word", lambda: [], _parse_odd_word, lambda i: dict(i),
         lambda i: norm_key("|".join(sorted(i["words"]))),
         "odd-one-out puzzles: four everyday words where exactly one does not belong, "
         "with a short explanation. The answer must be one of the four words",
         '{"words": ["Apple", "Banana", "Carrot", "Mango"], "answer": "Carrot", '
         '"why": "It is a vegetable, the others are fruits."}'),
]}


# Truth or Dare decks: one kind per (card type, tone level) so the TV game
# can deal cumulative levels and still never repeat for a table.
_TD = "games.native_hub.engines._truthdare"
_TD_ASK = {
    "family": "all ages, for kids and grandparents together",
    "teens": "cheeky, for teenagers (school, phones, friends), never mean",
    "adults": "lively grown-up house party, embarrassing and funny but never explicit, "
              "sexual, dangerous or cruel",
}
for _type, _attr, _what, _eg in (
        ("truth", "TRUTHS", "personal Truth questions to answer out loud", '"What is the silliest thing you were scared of as a kid?"'),
        ("dare", "DARES", "harmless, quick Dare challenges to perform in a living room", '"Sing the chorus of a song in a robot voice."'),
        ("punish", "PUNISHMENTS", "bigger forfeit dares for a player caught lying on a Truth, funny not painful", '"Wear your socks on your hands for two rounds."')):
    for _level, _tone in _TD_ASK.items():
        _name = f"td_{_type}_{_level}"
        KINDS[_name] = _text_kind(
            _name, (lambda a=_attr, l=_level: list(getattr(importlib.import_module(_TD), a)[l])), 140,
            f"{_what}; tone: {_tone}", _eg)


# ---------------------------------------------------------------------------
# library + runtime pool
# ---------------------------------------------------------------------------

_LIBRARY_DIR = Path(__file__).resolve().parent / "content_library"
_items_cache: dict[str, list] = {}
_runtime: dict[str, list] = {}
_runtime_loaded = False


def library_path(kind: str) -> Path:
    return _LIBRARY_DIR / f"{kind}.json"


def _load_library(kind: str) -> list:
    try:
        raw = json.loads(library_path(kind).read_text(encoding="utf-8"))
    except Exception:
        return []
    spec = KINDS[kind]
    return [i for i in (spec.parse(r) for r in raw if r is not None) if i is not None] \
        if isinstance(raw, list) else []


def _data_path(env: str, name: str) -> Path:
    override = os.environ.get(env)
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1] / "data" / name


def _read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _write_json(path: Path, data: dict) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass   # best-effort: the hosted disk may be read-only or wiped


def _ensure_runtime() -> None:
    global _runtime_loaded
    if _runtime_loaded:
        return
    _runtime_loaded = True
    data = _read_json(_data_path("CONTENT_POOL_PATH", "content_pool.json"))
    for kind, raw in data.items():
        if kind in KINDS and isinstance(raw, list):
            spec = KINDS[kind]
            _runtime[kind] = [i for i in (spec.parse(r) for r in raw) if i is not None]


def all_items(kind: str) -> list:
    """Every known item of a kind, deduped by key (bundled first)."""
    with _lock:
        _ensure_runtime()
        if kind not in _items_cache:
            spec = KINDS[kind]
            out, seen = [], set()
            for item in spec.bundled() + _load_library(kind):
                k = spec.key(item)
                if k and k not in seen:
                    seen.add(k)
                    out.append(item)
            _items_cache[kind] = out
        base = _items_cache[kind]
        keys = {KINDS[kind].key(i) for i in base}
        extra = [i for i in _runtime.get(kind, []) if KINDS[kind].key(i) not in keys]
        return base + extra


def add_runtime(kind: str, items: list) -> int:
    """Add generated items to the runtime pool; returns how many were new."""
    spec = KINDS[kind]
    with _lock:
        _ensure_runtime()
        have = {spec.key(i) for i in all_items(kind)}
        new = []
        for item in items:
            k = spec.key(item)
            if k and k not in have:
                have.add(k)
                new.append(item)
        if new:
            _runtime[kind] = (_runtime.get(kind, []) + new)[-RUNTIME_POOL_CAP:]
            _write_json(_data_path("CONTENT_POOL_PATH", "content_pool.json"),
                        {k: [KINDS[k].dump(i) for i in v] for k, v in _runtime.items()})
        return len(new)


# ---------------------------------------------------------------------------
# who has seen what
# ---------------------------------------------------------------------------

_heard: dict[str, dict[str, list[str]]] | None = None


def _heard_store() -> dict:
    global _heard
    if _heard is None:
        raw = _read_json(_data_path("CONTENT_HEARD_PATH", "content_heard.json"))
        _heard = {d: {k: list(v) for k, v in kinds.items() if isinstance(v, list)}
                  for d, kinds in raw.items() if isinstance(kinds, dict)}
    return _heard


def _devices(room) -> list[str]:
    return [p.id for p in getattr(room, "players", [])
            if not getattr(p, "is_bot", False) and getattr(p, "id", None)]


def _room_history(room, kind: str) -> list:
    hist = getattr(room, "content_history", None)
    if hist is None:
        hist = {}
        try:
            room.content_history = hist
        except Exception:
            return []
    return hist.setdefault(kind, [])


def seen_keys(room, kind: str) -> tuple[set, set]:
    """(seen in this room, seen by any player's device)."""
    with _lock:
        store = _heard_store()
        devices = set()
        for d in _devices(room):
            devices.update(store.get(d, {}).get(kind, []))
        return set(_room_history(room, kind)), devices


def record(room, kind: str, keys: list[str]) -> None:
    keys = [k for k in keys if k]
    if not keys:
        return
    with _lock:
        hist = _room_history(room, kind)
        for k in keys:
            if k in hist:
                hist.remove(k)
            hist.append(k)
        del hist[:-ROOM_HISTORY_CAP]
        store = _heard_store()
        for d in _devices(room):
            dev = store.setdefault(d, {}).setdefault(kind, [])
            for k in keys:
                if k in dev:
                    dev.remove(k)
                dev.append(k)
            del dev[:-DEVICE_HISTORY_CAP]
        _write_json(_data_path("CONTENT_HEARD_PATH", "content_heard.json"), store)


# ---------------------------------------------------------------------------
# picking
# ---------------------------------------------------------------------------

def pick(room, kind: str, count: int = 1, avoid=()) -> list:
    """``count`` items nobody at the table has seen, if possible.

    Relaxes in order: fresh for room + devices -> fresh for this room ->
    not in ``avoid`` (this game's own picks) -> anything. Records the
    picks and, when the fresh supply runs low, starts a background refill.
    """
    spec = KINDS[kind]
    items = all_items(kind)
    if not items:
        return []
    avoid_keys = {a if isinstance(a, str) else spec.key(a) for a in avoid}
    room_seen, device_seen = seen_keys(room, kind)
    tiers = (room_seen | device_seen | avoid_keys, room_seen | avoid_keys, avoid_keys, set())
    fresh_left = 0
    chosen: list = []
    for i, excluded in enumerate(tiers):
        candidates = [it for it in items if spec.key(it) not in excluded]
        if i == 0:
            fresh_left = len(candidates)
        if len(candidates) >= count or i == len(tiers) - 1:
            chosen = random.sample(candidates, min(count, len(candidates)))
            break
    record(room, kind, [spec.key(c) for c in chosen])
    if fresh_left - len(chosen) < LOW_WATER:
        request_refill(kind)
    return chosen


def pick_one(room, kind: str, avoid=()):
    got = pick(room, kind, 1, avoid)
    return got[0] if got else None


# ---------------------------------------------------------------------------
# background refill
# ---------------------------------------------------------------------------

_refilling: set[str] = set()
_last_refill: dict[str, float] = {}

#: Open Trivia DB categories for the general trivia pool (kid-friendly mix).
_OPENTDB_CATEGORIES = (9, 9, 17, 22, 27, 11, 12, 21, 23, 10, 15, 18)


def _auto_refill_enabled() -> bool:
    if os.environ.get("CONTENT_AUTO_REFILL", "1") == "0":
        return False
    return "PYTEST_CURRENT_TEST" not in os.environ


def request_refill(kind: str) -> bool:
    """Start one background refill for ``kind`` unless one ran recently."""
    if not _auto_refill_enabled():
        return False
    with _lock:
        if kind in _refilling or time.time() - _last_refill.get(kind, 0) < REFILL_MIN_INTERVAL:
            return False
        _refilling.add(kind)
        _last_refill[kind] = time.time()
    threading.Thread(target=_refill_worker, args=(kind,), daemon=True,
                     name=f"content-refill-{kind}").start()
    return True


def _refill_worker(kind: str) -> None:
    try:
        refill(kind)
    except Exception:
        pass
    finally:
        with _lock:
            _refilling.discard(kind)


def generation_prompt(kind: str, count: int, exclude: list[str]) -> str:
    spec = KINDS[kind]
    avoid = ""
    if exclude:
        avoid = ("\nThese already exist -- do not repeat them or anything basically the "
                 "same:\n" + "; ".join(exclude[:150]) + "\n")
    return (
        f"Write {count} {spec.ask}.\n"
        f'Return ONLY a JSON object: {{"items": [ ... ]}} where each item looks like {spec.example}\n'
        "Rules: family-friendly, plain words only (no emojis, no markdown, no symbols), "
        "every item different from the others."
        f"{avoid}"
    )


def generate(kind: str, count: int = REFILL_BATCH) -> list:
    """One validated batch of new items (not yet added anywhere)."""
    spec = KINDS[kind]
    existing = all_items(kind)
    keys = {spec.key(i) for i in existing}
    if kind == "mc":
        # Trivia grows from two sources: the LLM (newest, Indian-flavoured,
        # current events) when a key is set, and Open Trivia DB (free, no
        # key) otherwise or when the LLM call fails.
        from games import llm_json, topic_gen
        raw = []
        if llm_json.configured() and random.random() < 0.6:
            sample = [i["question"] for i in random.sample(existing, min(150, len(existing)))]
            try:
                raw, _ = llm_json.json_items(generation_prompt(kind, count, sample))
            except llm_json.LLMError:
                raw = []
        if not raw:
            try:
                raw = topic_gen._opentdb_batch("", random.choice(_OPENTDB_CATEGORIES), count)
            except Exception:
                return []
    else:
        if spec.ask is None:
            return []
        from games import llm_json
        sample = [json.dumps(spec.dump(i), ensure_ascii=False).strip('"')
                  for i in random.sample(existing, min(150, len(existing)))]
        try:
            raw, _ = llm_json.json_items(generation_prompt(kind, count, sample))
        except llm_json.LLMError:
            return []
    out = []
    for r in raw:
        item = spec.parse(r)
        if item is not None and spec.key(item) not in keys:
            keys.add(spec.key(item))
            out.append(item)
    return out


def refill(kind: str) -> int:
    return add_runtime(kind, generate(kind))


# ---------------------------------------------------------------------------
# trivia / KBC (multiple choice) helpers
# ---------------------------------------------------------------------------

def mc_extra(kind: str) -> list:
    """Live trivia questions in the engine's tuple shape: trivia tuples are
    (category, question, options, answer); KBC tuples (question, options,
    answer)."""
    out = []
    for q in all_items("mc"):
        if kind == "trivia":
            out.append((q.get("category") or "General", q["question"],
                        list(q["options"]), q["correct_answer"]))
        else:
            out.append((q["question"], list(q["options"]), q["correct_answer"]))
    return out


def reset_for_tests() -> None:
    """Drop all in-memory state (tests point the data paths at tmp files)."""
    global _heard, _runtime_loaded
    with _lock:
        _heard = None
        _runtime_loaded = False
        _runtime.clear()
        _items_cache.clear()
        _refilling.clear()
        _last_refill.clear()
