"""Nothing a table sees twice: a simulation of many games per content source.

Two layers:

* every content KIND (games/content_service.py) -- within a game, across
  Play Again in one room, across rooms that share a phone, and when the pool
  is exhausted (it must cycle oldest-first instead of repeating at random);
* every GAME that shows prompts, questions, words or letters -- several
  consecutive games in one room, then again in a new room with the same
  phones.
"""

from __future__ import annotations

import pytest

from games import content_service as cs
from games.native_hub.engines.content_packs import fresh_questions, record_questions
from games.native_hub.registry import engine_for
from utils.room_manager import RoomRegistry, RoomState


class _Null:
    def state(self): pass
    def room_update(self): pass
    def error(self, *a, **k): pass


def room_with(ids=("p0", "p1", "p2", "p3"), game_id="herd"):
    room = RoomRegistry().create(game_id)
    roster = [room.add_player(pid, pid.upper(), f"s-{pid}") for pid in ids]
    return room, roster


# ---------------------------------------------------------------------------
# kinds
# ---------------------------------------------------------------------------

#: Letter kinds are tiny by nature; the rest must be big enough that a long
#: game night does not wrap round.
LETTER_KINDS = {"npat_letter", "antakshari_letter", "atlas_letter"}
#: Forfeits only come up when someone is caught lying, so a smaller deck is fine.
MIN_POOL = {"antakshari_hint": 12, "td_punish_family": 20, "td_punish_teens": 20,
            "td_punish_adults": 20}
DEFAULT_MIN_POOL = 40


@pytest.mark.parametrize("kind", sorted(cs.KINDS))
def test_pool_is_big_enough(kind):
    size = len(cs.all_items(kind))
    floor = 10 if kind in LETTER_KINDS else MIN_POOL.get(kind, DEFAULT_MIN_POOL)
    assert size >= floor, f"{kind} has only {size} items"


@pytest.mark.parametrize("kind", sorted(cs.KINDS))
def test_a_game_never_repeats_and_play_again_gets_new_items(kind):
    pool = len(cs.all_items(kind))
    per_game = min(8, pool // 3)
    room, _ = room_with()
    spec = cs.KINDS[kind]
    seen: list[str] = []
    for _game in range(3):
        used: set[str] = set()
        for _ in range(per_game):
            item = cs.pick_one(room, kind, avoid=used)
            key = spec.key(item)
            assert key not in used, f"{kind}: repeated inside one game"
            used.add(key)
            seen.append(key)
    assert len(set(seen)) == len(seen), f"{kind}: Play Again repeated an item"


@pytest.mark.parametrize("kind", sorted(cs.KINDS))
def test_a_new_room_with_the_same_phones_gets_new_items(kind):
    pool = len(cs.all_items(kind))
    n = min(12, pool // 3)
    spec = cs.KINDS[kind]
    first, _ = room_with(("phone-a", "phone-b", "x1"))
    a = {spec.key(i) for i in cs.pick(first, kind, n)}
    second, _ = room_with(("phone-a", "y1", "y2"))
    b = {spec.key(i) for i in cs.pick(second, kind, n)}
    assert a.isdisjoint(b), f"{kind}: a phone saw {len(a & b)} items again"


@pytest.mark.parametrize("kind", sorted(k for k in cs.KINDS if len(cs.all_items(k)) <= 200))
def test_an_exhausted_pool_cycles_oldest_first(kind):
    """After everything has been seen, a full lap goes through every item
    once before any item comes round again."""
    pool = len(cs.all_items(kind))
    room, _ = room_with()
    spec = cs.KINDS[kind]
    keys = [spec.key(cs.pick_one(room, kind)) for _ in range(pool * 3)]
    for lap in range(3):
        window = keys[lap * pool:(lap + 1) * pool]
        assert len(set(window)) == pool, f"{kind}: lap {lap + 1} repeated an item early"


# ---------------------------------------------------------------------------
# games
# ---------------------------------------------------------------------------

def _start(game_id, room, roster):
    engine = engine_for(game_id)(room, _Null())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine


def _rounds(engine, phase, read, rounds=None):
    out = []
    for n in range(rounds or getattr(engine, "total_rounds", 5)):
        engine.round = n + 1 if hasattr(engine, "round") else 0
        engine.begin_phase(phase)
        out.append(read(engine))
    return out


def _next_round(read, rounds=5):
    def run(engine):
        out = [read(engine)]
        for _ in range(rounds - 1):
            engine._next_round()
            out.append(read(engine))
        return out
    return run


def _flat(value):
    return value if isinstance(value, list) else [value]


#: game -> function(engine) -> list of what the table was shown this game.
GAMES = {
    "herd": lambda e: _rounds(e, "answer", lambda x: x.prompt),
    "most_likely_to": lambda e: _rounds(e, "vote", lambda x: x.prompt),
    "bluff_it": lambda e: _rounds(e, "write", lambda x: x.prompt),
    "sealed_auction": lambda e: _rounds(e, "bid", lambda x: x.lot[0]),
    "bollywood_charades": lambda e: _rounds(e, "act", lambda x: x.title),
    "wavelength": lambda e: _rounds(e, "clue", lambda x: tuple(x.spectrum)),
    "would_rather": lambda e: _rounds(e, "vote", lambda x: x.a + "|" + x.b),
    "host_lies": lambda e: _rounds(e, "claim", lambda x: x.item[0]),
    "mind_meld": _next_round(lambda x: x.category),
    "speed_sculptor": _next_round(lambda x: x.prompt),
    "hot_takes": lambda e: _rounds(e, "intro", lambda x: x.prompt),
    "twenty_questions": lambda e: _rounds(e, "intro", lambda x: x.secret),
    "npat": lambda e: _rounds(e, "fill", lambda x: x.letter),
    "emoji_movie": lambda e: [t for _ in range(e.total_rounds)
                              for t in (e.begin_phase("compose") or e.assignments.values())],
    "odd_one_out": lambda e: [e.location],
    "cipher_grid": lambda e: list(e.words),
    "atlas": lambda e: [e.chain[0]["place"]],
    "antakshari": lambda e: [e.letter],
}

#: How many games can run back to back before the pool must repeat (Name Place
#: Animal Thing has only 16 letters and a round more than it shows, from start()).
GAMES_TO_PLAY = {"npat": 2, "antakshari": 5, "cipher_grid": 4, "mind_meld": 4,
                 "twenty_questions": 4}


def _play(game_id, room, roster):
    engine = _start(game_id, room, roster)
    return [k if isinstance(k, str) else str(k) for k in GAMES[game_id](engine)]


@pytest.mark.parametrize("game_id", sorted(GAMES))
def test_consecutive_games_in_one_room_never_repeat(game_id):
    room, roster = room_with(game_id=game_id)
    seen: set[str] = set()
    for n in range(GAMES_TO_PLAY.get(game_id, 3)):
        shown = _play(game_id, room, roster)
        keys = [cs.norm_key(s) for s in shown]
        assert len(set(keys)) == len(keys), f"{game_id}: repeated inside game {n + 1}: {shown}"
        assert seen.isdisjoint(keys), f"{game_id}: game {n + 1} repeated something from before"
        seen.update(keys)


@pytest.mark.parametrize("game_id", sorted(GAMES))
def test_a_new_room_with_the_same_phones_never_repeats(game_id):
    ids = ("phone-1", "phone-2", "phone-3", "phone-4")
    first, roster1 = room_with(ids, game_id)
    before = {cs.norm_key(s) for s in _play(game_id, first, roster1)}
    second, roster2 = room_with(ids, game_id)
    after = {cs.norm_key(s) for s in _play(game_id, second, roster2)}
    assert before.isdisjoint(after), f"{game_id}: the same phones saw {before & after} again"


# ---------------------------------------------------------------------------
# trivia / quiz show
# ---------------------------------------------------------------------------

def _text(kind, q):
    return q[1] if kind == "trivia" else q[0]


@pytest.mark.parametrize("kind", ["trivia", "kbc"])
def test_quiz_questions_do_not_repeat_across_many_games(kind):
    room, _ = room_with()
    per_game = 15
    seen: set[str] = set()
    games = 20
    for _ in range(games):
        pool = fresh_questions(room, "en", kind)
        # The engine shuffles and takes the first few.
        import random
        asked = random.sample(pool, per_game)
        texts = [_text(kind, q) for q in asked]
        assert len(set(texts)) == per_game
        assert seen.isdisjoint(texts), f"{kind}: a question came back within {games} games"
        seen.update(texts)
        record_questions(room, "en", kind, asked)


def test_quiz_questions_do_not_repeat_for_the_same_phones_in_a_new_room():
    ids = ("phone-1", "phone-2", "phone-3")
    first, _ = room_with(ids)
    import random
    asked = random.sample(fresh_questions(first, "en", "trivia"), 40)
    record_questions(first, "en", "trivia", asked)
    second, _ = room_with(ids)
    again = fresh_questions(second, "en", "trivia")
    assert {q[1] for q in asked}.isdisjoint(q[1] for q in again)


def test_quiz_banks_cycle_oldest_first_once_everything_is_seen():
    room, _ = room_with()
    bank = fresh_questions(room, "en", "trivia")
    record_questions(room, "en", "trivia", bank)       # the whole bank, in order
    stale = fresh_questions(room, "en", "trivia")
    newest = {q[1] for q in bank[-len(bank) // 4:]}
    assert not any(q[1] in newest for q in stale)


@pytest.mark.parametrize("pack", ["te", "hi"])
def test_non_latin_quiz_packs_remember_every_question(pack):
    """Telugu and Hindi questions used to share one empty comparison key, so
    a table could never be told which of them it had already seen."""
    from games.native_hub.engines.content_packs import questions_for
    bank = questions_for(pack, "trivia")
    keys = {cs.norm_key(q[1]) for q in bank}
    assert "" not in keys and len(keys) == len(bank)
