"""Content variety: games/content_service.py and the engines that use it.

The point of the service is that a table doesn't see the same prompt
again -- not after Play Again, not in a new room, not on the next game
night -- and that the supply keeps growing. These tests pin that down.
"""

import json
import random

import pytest

from games import content_service as cs
from games import llm_json
from games.native_hub.engines.content_packs import fresh_questions, record_questions
from games.native_hub.registry import engine_for
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make_room(game_id="herd", ids=("a", "b", "c", "d")):
    room = RoomRegistry().create(game_id)
    roster = [room.add_player(pid, pid.upper(), f"s-{pid}") for pid in ids]
    return room, roster


def start(game_id, room=None, roster=None, players=4):
    if room is None:
        room, roster = make_room(game_id, tuple(f"p{i}" for i in range(players)))
    engine = engine_for(game_id)(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, room, roster


# --------------------------------------------------------------------------
# the library
# --------------------------------------------------------------------------

@pytest.mark.parametrize("kind", [k for k, s in cs.KINDS.items() if s.ask and k != "mc"])
def test_library_files_are_valid_and_add_real_variety(kind):
    raw = json.loads(cs.library_path(kind).read_text(encoding="utf-8"))
    parsed = [cs.KINDS[kind].parse(r) for r in raw]
    assert all(p is not None for p in parsed), [r for r, p in zip(raw, parsed) if p is None]
    keys = [cs.KINDS[kind].key(p) for p in parsed]
    assert len(keys) == len(set(keys)), "duplicate entries in the library file"
    bundled = len(cs.KINDS[kind].bundled())
    assert len(cs.all_items(kind)) >= max(60, 2 * bundled)


def test_every_library_string_is_speech_and_tv_safe():
    for kind, spec in cs.KINDS.items():
        if not spec.ask or kind == "mc":
            continue
        for item in cs.all_items(kind):
            text = json.dumps(spec.dump(item), ensure_ascii=False)
            assert "http" not in text and "**" not in text


# --------------------------------------------------------------------------
# picking: room -> device -> game
# --------------------------------------------------------------------------

def test_pick_never_repeats_in_a_room_across_games():
    room, _ = make_room()
    total = len(cs.all_items("herd"))
    seen = set()
    for _ in range(total):
        item = cs.pick_one(room, "herd")
        assert cs.norm_key(item) not in seen
        seen.add(cs.norm_key(item))


def test_pick_skips_what_a_players_device_saw_in_another_room():
    first, _ = make_room(ids=("phone-1", "x", "y"))
    picked = {cs.norm_key(i) for i in cs.pick(first, "meld_category", 40)}
    # A brand-new room, a different group, one of the same phones.
    second, _ = make_room(ids=("phone-1", "z", "w"))
    again = {cs.norm_key(i) for i in cs.pick(second, "meld_category", 40)}
    assert picked.isdisjoint(again)


def test_bots_do_not_count_as_devices():
    room, roster = make_room(ids=("human", "bot-1"))
    roster[1].is_bot = True
    cs.pick(room, "herd", 5)
    assert "bot-1" not in cs._heard_store()
    assert "human" in cs._heard_store()


def test_pick_relaxes_instead_of_running_dry():
    room, _ = make_room()
    every = cs.all_items("auction")
    cs.pick(room, "auction", len(every))
    more = cs.pick(room, "auction", 3)
    assert len(more) == 3


def test_avoid_wins_even_after_the_pool_is_exhausted():
    room, _ = make_room()
    every = cs.all_items("wavelength")
    cs.pick(room, "wavelength", len(every))
    avoid = {cs.KINDS["wavelength"].key(i) for i in every[:-1]}
    assert cs.pick_one(room, "wavelength", avoid=avoid) == every[-1]


def test_device_history_survives_a_restart(tmp_path):
    room, _ = make_room(ids=("phone-9",))
    got = cs.pick_one(room, "draw_prompt")
    cs.reset_for_tests()     # new process, same data file
    _, devices = cs.seen_keys(make_room(ids=("phone-9",))[0], "draw_prompt")
    assert cs.norm_key(got) in devices


def test_low_supply_requests_a_refill(monkeypatch):
    calls = []
    monkeypatch.setattr(cs, "request_refill", lambda kind: calls.append(kind))
    room, _ = make_room()
    cs.pick(room, "bluff", len(cs.all_items("bluff")) - 5)
    assert calls and calls[-1] == "bluff"


# --------------------------------------------------------------------------
# growing the pool
# --------------------------------------------------------------------------

def test_generate_keeps_only_new_valid_items(monkeypatch):
    existing = cs.all_items("herd")[0]
    raw = [existing, "Name a kind of cloud.", "", "Name a \U0001F600 thing.", "Name a kind of cloud."]
    monkeypatch.setattr(llm_json, "json_items", lambda prompt, system=None: (raw, "openai"))
    assert cs.generate("herd") == ["Name a kind of cloud."]


def test_generation_prompt_lists_what_already_exists():
    prompt = cs.generation_prompt("hot_take", 30, ["Is cereal a soup?"])
    assert "Is cereal a soup?" in prompt and '{"items"' in prompt


def test_refill_adds_to_the_runtime_pool_and_persists(monkeypatch):
    monkeypatch.setattr(llm_json, "json_items",
                        lambda prompt, system=None: (["A dentist on the moon"], "openai"))
    assert cs.refill("spy_location") == 1
    cs.reset_for_tests()
    assert "A dentist on the moon" in cs.all_items("spy_location")


def test_trivia_pool_grows_from_open_trivia_db(monkeypatch):
    from games import topic_gen
    q = {"question": "Which gas do plants breathe in?",
         "options": ["Oxygen", "Carbon dioxide", "Helium", "Neon"], "correct_answer": 1}
    monkeypatch.setattr(topic_gen, "_opentdb_batch", lambda topic, cat, count, exclude=(): [q])
    assert cs.refill("mc") == 1
    assert ("General", q["question"], q["options"], 1) in cs.mc_extra("trivia")


def test_no_refill_threads_during_tests():
    assert cs.request_refill("herd") is False


def test_llm_json_parses_wrapped_and_fenced_output():
    assert llm_json.parse_items('{"items": [1, 2]}') == [1, 2]
    assert llm_json.parse_items('```json\n[3]\n```') == [3]
    with pytest.raises(llm_json.LLMError):
        llm_json.parse_items("not json")


def test_llm_json_without_keys_raises(monkeypatch):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    with pytest.raises(llm_json.LLMError):
        llm_json.json_items("anything")


# --------------------------------------------------------------------------
# engines
# --------------------------------------------------------------------------

def _rounds(engine, attr, rounds, advance):
    seen = [getattr(engine, attr)]
    for _ in range(rounds - 1):
        advance(engine)
        seen.append(getattr(engine, attr))
    return seen


def test_wavelength_no_longer_repeats_a_spectrum_in_one_game():
    random.seed(3)
    engine, _, _ = start("wavelength")
    spectra = []
    for _ in range(engine.total_rounds):
        engine.begin_phase("clue")
        spectra.append(engine.spectrum)
    assert len(set(spectra)) == len(spectra)


def test_mind_meld_and_speed_sculptor_do_not_repeat_within_a_game():
    for game_id, attr in (("mind_meld", "category"), ("speed_sculptor", "prompt")):
        engine, _, _ = start(game_id)
        seen = _rounds(engine, attr, 6, lambda e: e._next_round())
        assert len(set(seen)) == len(seen), game_id


def test_play_again_gets_new_prompts():
    engine, room, roster = start("most_likely_to", players=4)
    first = set()
    for _ in range(engine.total_rounds):
        engine.begin_phase("vote")
        first.add(engine.prompt)
    again, _, _ = start("most_likely_to", room=room, roster=roster)
    second = set()
    for _ in range(again.total_rounds):
        again.begin_phase("vote")
        second.add(again.prompt)
    assert first.isdisjoint(second)


def test_spy_sees_a_short_list_that_contains_the_location():
    engine, _, roster = start("odd_one_out", players=4)
    state = engine.private_state(engine.spy)
    choices = state["allLocations"]
    assert engine.location in choices
    assert len(choices) == engine.SPY_CHOICES
    assert state["location"] is None


def test_bluff_herd_auction_charades_emoji_cipher_still_start():
    for game_id in ("bluff_it", "herd", "sealed_auction", "bollywood_charades",
                    "emoji_movie", "cipher_grid"):
        engine, _, _ = start(game_id, players=4)
        assert engine.public_state() is not None, game_id


def test_cipher_grid_words_are_unique():
    engine, _, _ = start("cipher_grid", players=4)
    assert len(set(engine.words)) == engine.GRID


def test_hot_take_topic_prompts_are_not_repeated(monkeypatch):
    import games.topic_gen as tg
    served = iter(["Is soup a drink?", "Is a cat a liquid?"])
    monkeypatch.setattr(tg, "get_hot_takes",
                        lambda topic, n, session_history=(): [next(served)])
    engine, room, _ = start("hot_takes", players=3)
    room.topic = "food"
    engine.begin_phase("intro")
    assert engine.prompt == "Is soup a drink?"
    assert cs.norm_key("Is soup a drink?") in engine.used
    engine.begin_phase("intro")
    assert engine.prompt == "Is a cat a liquid?"


def test_trivia_skips_questions_a_device_saw_in_another_room():
    room, _ = make_room("trivia", ids=("phone-1", "b"))
    pool = fresh_questions(room, "en", "trivia")
    record_questions(room, "en", "trivia", pool[:50])
    other, _ = make_room("trivia", ids=("phone-1", "c"))
    again = fresh_questions(other, "en", "trivia")
    asked = {q[1] for q in pool[:50]}
    assert asked.isdisjoint({q[1] for q in again})


def test_trivia_pool_also_grows_from_the_llm(monkeypatch):
    q = {"question": "Which city hosted the 2024 Summer Olympics?",
         "options": ["Tokyo", "Paris", "London", "Rio"], "correct_answer": 1}
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setattr(cs.random, "random", lambda: 0.0)       # take the LLM path
    monkeypatch.setattr(llm_json, "json_items", lambda prompt, system=None: ([q], "openai"))
    assert cs.refill("mc") == 1
    assert q["question"] in {i["question"] for i in cs.all_items("mc")}


def test_trivia_falls_back_to_open_trivia_db_when_the_llm_fails(monkeypatch):
    from games import topic_gen
    q = {"question": "What is the boiling point of water at sea level in Celsius?",
         "options": ["90", "100", "110", "120"], "correct_answer": 1}
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setattr(cs.random, "random", lambda: 0.0)

    def boom(prompt, system=None):
        raise llm_json.LLMError("down")
    monkeypatch.setattr(llm_json, "json_items", boom)
    monkeypatch.setattr(topic_gen, "_opentdb_batch", lambda topic, cat, count, exclude=(): [q])
    assert cs.refill("mc") == 1
