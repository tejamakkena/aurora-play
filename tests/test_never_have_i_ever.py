"""Never Have I Ever: the packs, and the round flow driven through its engine."""

import json
import random
import time

import pytest

from games.native_hub.engines import _nhie_packs as P
from games.native_hub.engines.never_have_i_ever import NeverHaveIEverEngine
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(players=4, config=None, seed=3):
    random.seed(seed)
    room = RoomRegistry().create("never_have_i_ever")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    if config:
        room.night = {"party": config}      # what a Game Night's setup stores
    engine = NeverHaveIEverEngine(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def expire(engine):
    """Let the current phase's clock run out."""
    engine.deadline = time.time() - 1
    engine.tick(0.1)


class TestPacks:
    def test_every_pack_has_enough_statements(self):
        for pack in P.PACKS:
            assert len(pack["statements"]) >= 20, pack["id"]

    def test_statements_are_unique_within_a_pack(self):
        for pack in P.PACKS:
            assert len(set(pack["statements"])) == len(pack["statements"]), pack["id"]

    def test_statements_complete_the_sentence(self):
        # The board prepends "Never have I ever", so a statement must not.
        for pack in P.PACKS:
            for s in pack["statements"]:
                assert not s.lower().startswith("never have i ever"), s
                assert s == s.strip() and not s.endswith("."), s

    def test_adult_packs_are_flagged_and_kept_out_of_the_mix(self):
        adult = {p["id"] for p in P.PACKS if p["adult"]}
        assert adult == {"party", "afterdark"}
        mix = set(P.statements_for("mix"))
        for pid in adult:
            assert not mix & set(P.statements_for(pid)), pid

    def test_default_pack_is_the_safe_mix(self):
        assert P.DEFAULT_PACK == "mix"
        assert not P.pack_info(P.DEFAULT_PACK)["adult"]

    def test_unknown_pack_falls_back_to_the_mix(self):
        assert P.statements_for("nope") == P.statements_for("mix")

    def test_pack_options_do_not_leak_statements(self):
        for option in P.pack_options():
            assert "statements" not in option
            assert option["count"] > 0
        json.dumps(P.pack_options())


class TestRoundFlow:
    def test_starts_on_the_pack_screen_without_a_preset(self):
        engine, _ = make()
        assert engine.phase == "pack"
        assert engine.public_state()["statement"] == ""

    def test_a_preset_pack_skips_straight_to_the_first_statement(self):
        engine, _ = make(config={"nhiePack": "desi"})
        assert engine.phase == "answer"
        assert engine.pack_id == "desi"
        assert engine.statement in P.statements_for("desi")

    def test_only_the_host_can_choose_the_pack(self):
        engine, roster = make()
        engine.handle_action(roster[1].id, "choose_pack", {"pack": "funny"})
        assert engine.phase == "pack"
        engine.handle_action(roster[0].id, "choose_pack", {"pack": "funny"})
        assert engine.phase == "answer"
        assert engine.pack_id == "funny"

    def test_unknown_pack_is_ignored(self):
        engine, roster = make()
        engine.handle_action(roster[0].id, "choose_pack", {"pack": "../etc"})
        assert engine.phase == "pack"

    def test_pack_screen_times_out_to_the_default(self):
        engine, _ = make()
        expire(engine)
        assert engine.phase == "answer"
        assert engine.pack_id == P.DEFAULT_PACK

    def test_confessions_score_and_are_revealed(self):
        engine, roster = make(config={"nhiePack": "classic"})
        engine.handle_action(roster[0].id, "answer", {"choice": "have"})
        engine.handle_action(roster[1].id, "answer", {"choice": "have"})
        engine.handle_action(roster[2].id, "answer", {"choice": "never"})
        engine.handle_action(roster[3].id, "answer", {"choice": "never"})
        engine.tick(0.1)                    # everyone answered -> resolves early
        assert engine.phase == "reveal"
        state = engine.public_state()
        assert state["haveCount"] == 2 and state["neverCount"] == 2
        assert sorted(state["confessors"]) == ["P0", "P1"]
        assert state["spotlight"] in ("P0", "P1")
        assert engine.scores["p0"] == 1 and engine.scores["p2"] == 0

    def test_answers_are_hidden_while_the_round_is_open(self):
        engine, roster = make(config={"nhiePack": "classic"})
        engine.handle_action(roster[0].id, "answer", {"choice": "have"})
        state = engine.public_state()
        assert state["confessors"] == []
        assert state["haveCount"] is None
        # Nobody else's phone is told what P0 said.
        assert engine.private_state(roster[1].id)["myChoice"] is None
        assert engine.private_state(roster[0].id)["myChoice"] == "have"
        # The room can see *that* P0 answered, never *what* they said.
        assert state["submittedPlayerIDs"] == ["p0"]

    def test_first_answer_stands(self):
        engine, roster = make(config={"nhiePack": "classic"})
        engine.handle_action(roster[0].id, "answer", {"choice": "never"})
        engine.handle_action(roster[0].id, "answer", {"choice": "have"})
        assert engine.submissions[roster[0].id] == "never"

    def test_junk_choices_are_ignored(self):
        engine, roster = make(config={"nhiePack": "classic"})
        for junk in ("yes", "", None, 7, {"x": 1}):
            engine.handle_action(roster[0].id, "answer", {"choice": junk})
        assert engine.submissions == {}

    def test_nobody_confessing_gets_a_verdict(self):
        engine, roster = make(config={"nhiePack": "classic"})
        for p in roster:
            engine.handle_action(p.id, "answer", {"choice": "never"})
        engine.tick(0.1)
        assert engine.public_state()["spotlight"] is None
        assert "Nobody" in engine.public_state()["verdict"]

    def test_runs_the_configured_number_of_rounds_then_finishes(self):
        engine, roster = make(config={"nhiePack": "classic", "nhieRounds": 3})
        seen = []
        for _ in range(3):
            seen.append(engine.statement)
            engine.handle_action(roster[0].id, "answer", {"choice": "have"})
            expire(engine)                  # answer -> reveal
            assert engine.phase == "reveal"
            expire(engine)                  # reveal -> next round / finish
        assert engine.is_over()
        assert len(set(seen)) == 3          # no repeats within a game
        ranking = engine.results()
        assert ranking[0]["playerID"] == "p0" and ranking[0]["score"] == 3

    def test_state_is_json_serialisable_in_every_phase(self):
        engine, roster = make()
        for _ in range(3):
            json.dumps(engine.public_state())
            for p in roster:
                json.dumps(engine.private_state(p.id))
            expire(engine)

    def test_only_the_host_is_offered_the_pack_list(self):
        engine, roster = make()
        assert engine.private_state(roster[0].id)["packChoices"]
        assert engine.private_state(roster[1].id)["packChoices"] == []
        assert engine.public_state()["packChoices"]     # the TV shows them to the room
