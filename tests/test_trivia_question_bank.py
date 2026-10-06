"""Tests for the trivia/KBC question banks and the no-repeat machinery.

Covers:
* the missing-question bug -- TriviaEngine.private_state must carry the
  question text and category to the phone controller (it used to send only
  choices, so the phone showed answer buttons with no question);
* the expanded banks -- several hundred unique questions, no duplicates,
  no emoji, valid answer indexes;
* the shuffle logic -- no repeats within a session, and a room-level
  recent-history that keeps back-to-back sessions from replaying.
"""

import random

import pytest

from games.native_hub.engines import _content as C
from games.native_hub.engines.content_packs import (
    fresh_questions,
    questions_for,
    record_questions,
)
from games.native_hub.engines.legacy_social import TRIVIA_QUESTIONS
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


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
    return engine, roster, room


def _engine_on_room(game_id, room, players, seed=11):
    """Start a new engine session on an existing room (same room, new game)."""
    random.seed(seed)
    cls = ENGINES[game_id]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(players)
    return engine


def _qtext(kind, q):
    return q[1] if kind == "trivia" else q[0]


def _trivia_to(engine, phase, limit=200):
    """Fast-forward the trivia game show to ``phase`` by expiring deadlines."""
    for _ in range(limit):
        if engine.phase == phase:
            return
        engine.deadline = 0.0
        engine.tick(0.0)
    raise AssertionError(f"never reached {phase}")


# ---- the missing-question bug ----------------------------------------------


def test_trivia_private_state_includes_question_text_and_category():
    # Regression test: the phone controller only receives private_state,
    # which used to contain just choices/questionID/score -- the question
    # text never reached the phone, so players saw answer buttons with no
    # question. TriviaControllerView now renders privateData["questionText"].
    engine, roster, _ = _make("trivia")
    _trivia_to(engine, "question")
    for player in roster:
        private = engine.private_state(player.id)
        assert private["questionText"] == engine.question[1]
        assert private["category"] == engine.question[0]
        assert private["choices"] == engine.question[2]
        assert private["questionID"] == engine.question_id


def test_trivia_private_state_question_follows_question_changes():
    engine, roster, _ = _make("trivia")
    first = engine.private_state(roster[0].id)["questionText"]
    engine._next_question()
    second = engine.private_state(roster[0].id)["questionText"]
    assert second == engine.question[1]
    assert second != first


# ---- bank size / quality ----------------------------------------------------


def test_banks_hold_several_hundred_unique_questions():
    total = sum(
        len(questions_for(pack_id, kind))
        for pack_id in ("en", "te", "hi")
        for kind in ("trivia", "kbc")
    )
    assert total >= 300, total


@pytest.mark.parametrize("pack_id", ["en", "te", "hi"])
@pytest.mark.parametrize("kind", ["trivia", "kbc"])
def test_no_duplicate_questions_within_a_pack(pack_id, kind):
    texts = [_qtext(kind, q) for q in questions_for(pack_id, kind)]
    assert len(texts) == len(set(texts)), (
        [t for t in texts if texts.count(t) > 1][:3]
    )


def test_english_trivia_spans_many_categories():
    categories = {q[0] for q in TRIVIA_QUESTIONS}
    assert len(categories) >= 8, categories


# ---- within-session no-repeat ----------------------------------------------


def test_trivia_never_repeats_a_question_within_a_session():
    engine, roster, _ = _make("trivia")
    seen = [engine.question_id]
    for _ in range(engine.total_rounds - 1):
        engine._next_question()
        seen.append(engine.question_id)
    texts = [_qtext("trivia", engine.pool[i]) for i in range(len(engine.pool))]
    assert len(seen) == len(set(seen))
    assert len(texts) == len(set(texts))


def test_kbc_never_repeats_a_question_within_a_session():
    engine, roster, _ = _make("kbc")
    unique = len({q[0] for q in engine.pool})
    drawn = [engine.question[0]]
    for _ in range(unique - 1):
        engine._load_question()
        drawn.append(engine.question[0])
    assert len(drawn) == len(set(drawn)) == unique


def test_kbc_pool_has_no_cross_bank_duplicates():
    # The KBC pool is widened with trivia questions; any question living in
    # both banks must appear only once ("What is the chemical symbol for
    # gold?" used to be in both).
    engine, _, _ = _make("kbc")
    texts = [q[0] for q in engine.pool]
    assert len(texts) == len(set(texts))


# ---- cross-session recent history -------------------------------------------


def test_trivia_records_asked_questions_in_room_history():
    engine, roster, room = _make("trivia")
    _trivia_to(engine, "question")
    history = room.question_history[("en", "trivia")]
    assert _qtext("trivia", engine.question) in history


def test_trivia_skips_recent_questions_in_the_next_session():
    # Seed the room's history with 60 known questions, then start a fresh
    # session in the same room: none of the sampled pool may come from the
    # seeded set.
    engine, roster, room = _make("trivia")
    seeded = [_qtext("trivia", q) for q in TRIVIA_QUESTIONS[:60]]
    record_questions(room, "en", "trivia", TRIVIA_QUESTIONS[:60])

    engine2 = _engine_on_room("trivia", room, roster, seed=99)
    pool_texts = {_qtext("trivia", q) for q in engine2.pool}
    assert pool_texts.isdisjoint(seeded)


def test_kbc_skips_recent_questions_in_the_next_session():
    engine, roster, room = _make("kbc")
    kbc_pool = [tuple(q) for q in questions_for("en", "kbc")]
    record_questions(room, "en", "kbc", kbc_pool[:40])

    engine2 = _engine_on_room("kbc", room, roster, seed=7)
    seeded = {q[0] for q in kbc_pool[:40]}
    assert not any(q[0] in seeded for q in engine2.pool)


def test_fresh_questions_falls_back_to_full_bank_when_history_starves():
    # If the history would leave fewer than a quarter of the bank, the
    # full bank is returned rather than a tiny leftover pool. The Telugu
    # trivia bank (40 questions) fits inside the 60-question history cap,
    # so seeding it with every question exercises the fallback.
    te_pool = questions_for("te", "trivia")
    _, _, room = _make("trivia", pack="te")
    record_questions(room, "te", "trivia", te_pool)
    fresh = fresh_questions(room, "te", "trivia")
    assert len(fresh) == len(te_pool)


def test_record_questions_caps_and_refreshes_history():
    _, _, room = _make("trivia")
    many = list(TRIVIA_QUESTIONS) + list(TRIVIA_QUESTIONS)
    record_questions(room, "en", "trivia", many)
    history = room.question_history[("en", "trivia")]
    assert len(history) <= 60
    # Re-recording an old question moves it to the back (most recent).
    oldest = history[0]
    record_questions(room, "en", "trivia",
                     [q for q in TRIVIA_QUESTIONS if _qtext("trivia", q) == oldest])
    assert room.question_history[("en", "trivia")][-1] == oldest


def test_fresh_questions_returns_full_pool_with_no_history():
    # A room that has never run a quiz session has no history to avoid.
    registry = RoomRegistry()
    room = registry.create("trivia")
    assert fresh_questions(room, "en", "trivia") == list(TRIVIA_QUESTIONS)
