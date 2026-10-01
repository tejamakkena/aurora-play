"""Tests for the localised question packs in content_packs.py.

Covers the registry contract, the fallback behaviour, content quality
(no empty strings, no emoji), and that the kbc/trivia engines actually
draw from the configured pack.
"""

import random
import re

import pytest

from games.native_hub.engines import _content as C
from games.native_hub.engines.content_packs import (
    PACKS,
    SUPPORTED_PACKS,
    questions_for,
)
from games.native_hub.engines.legacy_social import TRIVIA_QUESTIONS
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


# Pictographs, symbols, dingbats and the emoji variation selector.
# ZWJ/ZWNJ are deliberately excluded -- they are legitimate characters
# in Indic scripts.
EMOJI_RE = re.compile(
    "[\U0001F000-\U0001FAFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F]"
)


def _all_strings(item):
    """Yield every string inside a question tuple, including options."""
    for field in item:
        if isinstance(field, str):
            yield field
        elif isinstance(field, (list, tuple)):
            for sub in field:
                if isinstance(sub, str):
                    yield sub


def _check_kbc_item(item):
    # Same shape as the KBC_QUESTIONS entries in _content.py:
    # (question, options, answer_index).
    assert isinstance(item, (tuple, list)) and len(item) == 3
    question, options, answer = item
    assert isinstance(question, str) and question.strip()
    assert isinstance(options, list) and len(options) >= 2
    assert all(isinstance(o, str) and o.strip() for o in options)
    assert type(answer) is int and 0 <= answer < len(options)


def _check_trivia_item(item):
    # Same shape as the TRIVIA_QUESTIONS entries in legacy_social.py:
    # (category, question, options, answer_index).
    assert isinstance(item, (tuple, list)) and len(item) == 4
    category, question, options, answer = item
    assert isinstance(category, str) and category.strip()
    assert isinstance(question, str) and question.strip()
    assert isinstance(options, list) and len(options) >= 2
    assert all(isinstance(o, str) and o.strip() for o in options)
    assert type(answer) is int and 0 <= answer < len(options)


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def _make(game_id, pack=None, players=2, seed=11):
    random.seed(seed)
    cls = ENGINES[game_id]
    registry = RoomRegistry()
    room = registry.create(game_id)
    if pack is not None:
        room.content_pack = pack
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


# ---- registry contract ------------------------------------------------------


def test_supported_packs_lists_three_languages():
    assert SUPPORTED_PACKS == [("en", "English"), ("te", "Telugu"), ("hi", "Hindi")]


def test_packs_registry_has_trivia_and_kbc_for_each_language():
    assert set(PACKS) == {"en", "te", "hi"}
    for pack_id, pack in PACKS.items():
        assert set(pack) == {"trivia", "kbc"}, pack_id


def test_each_pack_has_at_least_twenty_questions_total():
    for pack_id in PACKS:
        total = len(questions_for(pack_id, "trivia")) + len(questions_for(pack_id, "kbc"))
        assert total >= 20, pack_id


def test_unknown_pack_id_falls_back_to_english():
    assert questions_for("xx", "trivia") == questions_for("en", "trivia")
    assert questions_for("xx", "kbc") == questions_for("en", "kbc")
    assert questions_for("", "trivia") == questions_for("en", "trivia")


def test_english_pack_reuses_existing_tables():
    assert questions_for("en", "kbc") == list(C.KBC_QUESTIONS)
    assert questions_for("en", "trivia") is TRIVIA_QUESTIONS


# ---- content shape and quality ----------------------------------------------


@pytest.mark.parametrize("pack_id", ["en", "te", "hi"])
def test_kbc_items_match_existing_shape(pack_id):
    for item in questions_for(pack_id, "kbc"):
        _check_kbc_item(item)


@pytest.mark.parametrize("pack_id", ["en", "te", "hi"])
def test_trivia_items_have_valid_answer_indexes(pack_id):
    for item in questions_for(pack_id, "trivia"):
        _check_trivia_item(item)


@pytest.mark.parametrize("pack_id", ["en", "te", "hi"])
@pytest.mark.parametrize("kind", ["trivia", "kbc"])
def test_no_empty_strings(pack_id, kind):
    for item in questions_for(pack_id, kind):
        for s in _all_strings(item):
            assert s.strip(), f"empty string in {pack_id}/{kind}: {item!r}"


@pytest.mark.parametrize("pack_id", ["en", "te", "hi"])
@pytest.mark.parametrize("kind", ["trivia", "kbc"])
def test_no_emoji_in_pack_strings(pack_id, kind):
    for item in questions_for(pack_id, kind):
        for s in _all_strings(item):
            assert not EMOJI_RE.search(s), f"emoji in {pack_id}/{kind}: {s!r}"


def test_telugu_pack_uses_telugu_script():
    text = " ".join(s for item in questions_for("te", "trivia") + questions_for("te", "kbc")
                    for s in _all_strings(item))
    telugu = sum(1 for ch in text if "\u0C00" <= ch <= "\u0C7F")
    assert telugu > 50


def test_hindi_pack_uses_devanagari_script():
    text = " ".join(s for item in questions_for("hi", "trivia") + questions_for("hi", "kbc")
                    for s in _all_strings(item))
    devanagari = sum(1 for ch in text if "\u0900" <= ch <= "\u097F")
    assert devanagari > 50


# ---- engines honour the room's content pack ---------------------------------


def test_kbc_engine_defaults_to_english_pool():
    engine, _ = _make("kbc")
    assert len(engine.questions) == min(12, len(C.KBC_QUESTIONS))
    assert all(q in C.KBC_QUESTIONS for q in engine.questions)


def test_kbc_engine_uses_telugu_pack_when_configured():
    engine, _ = _make("kbc", pack="te")
    pool = questions_for("te", "kbc")
    assert len(engine.questions) == min(12, len(pool))
    assert all(q in pool for q in engine.questions)


def test_trivia_engine_defaults_to_english_pool():
    engine, _ = _make("trivia")
    assert len(engine.pool) == min(engine.TOTAL_ROUNDS, len(TRIVIA_QUESTIONS))
    assert all(q in TRIVIA_QUESTIONS for q in engine.pool)


def test_trivia_engine_uses_hindi_pack_when_configured():
    engine, _ = _make("trivia", pack="hi")
    pool = questions_for("hi", "trivia")
    assert len(engine.pool) == min(engine.TOTAL_ROUNDS, len(pool))
    assert all(q in pool for q in engine.pool)


def test_trivia_engine_falls_back_to_english_for_unknown_pack():
    engine, _ = _make("trivia", pack="xx")
    assert all(q in TRIVIA_QUESTIONS for q in engine.pool)
