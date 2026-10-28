"""Game Night: the config rules, the wording, and the host engine's show flow."""

import json
import time

import pytest

from games.native_hub.engines import _night_content as N
from games.native_hub.engines.game_night import GameNightEngine
from utils.room_manager import RoomRegistry, RoomState

TV = "tv-device"          # a non-player id, as sent by the TV's own socket


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(players=4, config=None):
    room = RoomRegistry().create("game_night")
    if config is not None:
        room.night_config = config
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    engine = GameNightEngine(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, room, roster


def start_night(engine, host="p0", **config):
    engine.handle_action(host, "night_start", {"config": config})


def skip_ahead(engine, times=1, host="p0"):
    for _ in range(times):
        engine.handle_action(host, "night_next", {})


class TestConfig:
    def test_defaults_are_valid(self):
        cfg = N.default_config()
        assert cfg == N.clean_config(cfg)
        assert cfg["occasion"] in N.OCCASIONS_BY_ID
        assert cfg["voicePack"] in N.VOICE_PACKS
        assert set(cfg["games"]) <= set(N.CATALOG_BY_ID)

    def test_invalid_fields_keep_their_previous_value(self):
        base = N.clean_config({"occasion": "birthday", "honoree": "Asha"})
        cfg = N.clean_config({"occasion": "nonsense", "voicePack": 5,
                              "nhiePack": "x", "nhieRounds": 99}, base)
        assert cfg["occasion"] == "birthday"
        assert cfg["voicePack"] == base["voicePack"]
        assert cfg["nhiePack"] == base["nhiePack"]
        assert cfg["nhieRounds"] == base["nhieRounds"]
        assert cfg["honoree"] == "Asha"

    @pytest.mark.parametrize("junk", [None, "x", 7, [], [1, 2]])
    def test_non_dict_config_is_ignored(self, junk):
        base = N.default_config()
        assert N.clean_config(junk, base) == base

    def test_bool_is_not_accepted_as_a_round_count(self):
        assert N.clean_config({"nhieRounds": True})["nhieRounds"] == N.DEFAULT_NHIE_ROUNDS

    def test_name_is_cleaned_and_capped(self):
        cfg = N.clean_config({"honoree": "  Ve\x00nkat\n\n  Teja  " + "x" * 80})
        assert "\x00" not in cfg["honoree"] and "\n" not in cfg["honoree"]
        assert cfg["honoree"].startswith("Venkat Teja")
        assert len(cfg["honoree"]) <= N.MAX_HONOREE_LEN

    def test_games_are_filtered_deduplicated_and_ordered(self):
        cfg = N.clean_config({"games": ["herd", "nope", "trivia", "herd", 3, None]})
        assert cfg["games"] == ["herd", "trivia"]

    def test_playlist_is_capped(self):
        cfg = N.clean_config({"games": [g["id"] for g in N.CATALOG] * 3})
        assert len(cfg["games"]) <= N.MAX_PLAYLIST


class TestWording:
    def test_birthday_title_and_cheer(self):
        cfg = N.clean_config({"occasion": "birthday", "honoree": "Venkat"})
        assert N.title_for(cfg) == "Venkat's Birthday Party"
        assert N.cheer_for(cfg) == "Happy birthday, Venkat!"

    def test_name_ending_in_s_takes_a_bare_apostrophe(self):
        cfg = N.clean_config({"occasion": "birthday", "honoree": "James"})
        assert N.title_for(cfg) == "James' Birthday Party"

    def test_blank_name_falls_back_to_a_generic_title(self):
        cfg = N.clean_config({"occasion": "birthday", "honoree": ""})
        assert N.title_for(cfg) == "Birthday Party"
        assert N.cheer_for(cfg) == "Happy birthday!"

    def test_festival_uses_the_festival_name(self):
        cfg = N.clean_config({"occasion": "festival", "honoree": "Diwali"})
        assert N.title_for(cfg) == "Diwali Party"
        assert N.cheer_for(cfg) == "Happy Diwali!"

    def test_welcome_names_the_party_for_every_voice_pack(self):
        for pack in N.VOICE_PACKS:
            cfg = N.clean_config({"occasion": "birthday", "honoree": "Venkat",
                                  "voicePack": pack})
            lines = N.welcome_lines(cfg)
            assert "Venkat's Birthday Party" in lines[0], pack
            assert "Happy birthday, Venkat!" in lines

    def test_get_together_does_not_repeat_itself(self):
        lines = N.welcome_lines(N.clean_config({"occasion": "gathering"}))
        assert len(lines) == 1

    def test_lineup_names_every_game_in_order(self):
        cfg = N.default_config()
        games = [N.CATALOG_BY_ID[g] for g in ("herd", "trivia", "bluff_it")]
        text = " ".join(N.lineup_lines(cfg, games))
        positions = [text.index(g["name"]) for g in games]
        assert positions == sorted(positions)

    def test_a_single_game_lineup_reads_naturally(self):
        lines = N.lineup_lines(N.default_config(), [N.CATALOG_BY_ID["herd"]])
        assert "Herd" in lines[0]

    def test_every_voice_pack_defines_every_line(self):
        keys = set(N.VOICE_PACKS["party_host"]["lines"])
        for pid, pack in N.VOICE_PACKS.items():
            assert set(pack["lines"]) == keys, pid
            for variants in pack["lines"].values():
                assert variants and all(isinstance(v, str) for v in variants)

    def test_every_voice_pack_line_can_be_spoken(self):
        # Catches a template that references a placeholder nobody supplies.
        for pid in N.VOICE_PACKS:
            cfg = N.clean_config({"voicePack": pid, "occasion": "birthday",
                                  "honoree": "Asha"})
            game = N.CATALOG_BY_ID["herd"]
            assert N.intro_lines(cfg, game, first=True, notes=[])
            assert N.intro_lines(cfg, game, first=False, notes=[])
            assert N.interlude_lines(cfg, game, "Asha", "Asha", 10, False)
            assert N.interlude_lines(cfg, game, None, None, 0, False)
            assert N.interlude_lines(cfg, game, None, None, 0, True)
            assert N.finale_lines(cfg, "Asha", 20, [])
            assert N.finale_lines(cfg, None, 0, [])
            assert N.say(cfg, "skipped", game="Herd")
            assert N.say(cfg, "sample")

    def test_voice_params_are_within_what_the_tv_accepts(self):
        for pack in N.VOICE_PACKS.values():
            voice = pack["voice"]
            assert 0.0 < voice["rate"] <= 1.0
            assert 0.5 <= voice["pitch"] <= 2.0
            assert voice["language"]

    def test_speech_estimate_grows_with_the_script(self):
        assert N.speech_seconds(["hi"]) < N.speech_seconds(["hi" * 100])
        assert N.speech_seconds(["a", "b"]) > N.speech_seconds(["ab"])

    def test_catalog_ids_are_real_engines(self):
        from games.native_hub.registry import ENGINES
        for game in N.CATALOG:
            assert game["id"] in ENGINES, game["id"]


class TestSetup:
    def test_starts_in_setup_with_the_config_ready_for_the_host(self):
        engine, _, roster = make()
        assert engine.phase == "setup"
        host = engine.private_state(roster[0].id)["night"]
        assert host["isHost"] and host["catalog"] and host["occasions"]
        assert host["voicePacks"] and host["nhiePacks"]
        guest = engine.private_state(roster[1].id)["night"]
        assert not guest["isHost"] and "catalog" not in guest and "config" not in guest

    def test_host_configures_and_it_is_remembered_on_the_room(self):
        engine, room, _ = make()
        engine.handle_action("p0", "night_configure",
                             {"config": {"occasion": "birthday", "honoree": "Venkat"}})
        assert engine.config["honoree"] == "Venkat"
        assert room.night_config["honoree"] == "Venkat"
        assert engine.night_state()["title"] == "Venkat's Birthday Party"

    def test_a_rematch_comes_back_with_the_same_details(self):
        engine, room, roster = make()
        engine.handle_action("p0", "night_configure",
                             {"config": {"occasion": "birthday", "honoree": "Venkat"}})
        again = GameNightEngine(room, _NullBroadcaster())
        again.start(roster)
        assert again.config["honoree"] == "Venkat"
        assert again.phase == "setup"

    def test_a_guest_cannot_configure_or_start(self):
        engine, _, _ = make()
        engine.handle_action("p1", "night_configure", {"config": {"honoree": "Hacker"}})
        engine.handle_action("p1", "night_start", {})
        assert engine.config["honoree"] == ""
        assert engine.phase == "setup"

    def test_the_tv_can_start_as_a_fallback(self):
        engine, _, _ = make()
        engine.handle_action(TV, "night_start", {})
        assert engine.phase == "welcome"

    def test_a_guest_can_claim_host_during_setup_only(self):
        engine, room, _ = make()
        engine.handle_action("p2", "night_claim_host", {})
        assert [p.id for p in room.players if p.is_host] == ["p2"]
        assert engine.private_state("p2")["night"]["catalog"]
        start_night(engine, host="p2")
        engine.handle_action("p1", "night_claim_host", {})
        assert [p.id for p in room.players if p.is_host] == ["p2"]

    def test_voice_preview_speaks_without_leaving_setup(self):
        engine, _, _ = make()
        engine.handle_action("p0", "night_preview", {"config": {"voicePack": "game_show"}})
        assert engine.phase == "setup"
        assert engine.announce["preview"] is True
        assert engine.announce["voice"] == N.VOICE_PACKS["game_show"]["voice"]

    def test_verbs_of_the_hosted_game_never_reach_the_host_controls(self):
        engine, _, _ = make()
        engine.handle_action("p0", "start_night", {})       # missing the prefix
        assert engine.phase == "setup"


class TestShow:
    def test_welcome_then_lineup_then_the_first_game(self):
        engine, _, _ = make()
        start_night(engine, occasion="birthday", honoree="Venkat", games=["herd"])
        assert engine.phase == "welcome"
        first = engine.announce
        assert "Venkat's Birthday Party" in first["lines"][0]
        assert first["voice"]["language"]

        skip_ahead(engine)
        assert engine.phase == "lineup"
        assert engine.announce["id"] > first["id"]
        assert any("Herd" in line for line in engine.announce["lines"])

        skip_ahead(engine)
        assert engine.phase == "intro"
        assert engine.night_state()["currentGame"]["id"] == "herd"

        skip_ahead(engine)
        assert engine.phase == "playing"
        assert engine.inner is not None and engine.inner.game_id == "herd"

    def test_the_hosted_game_owns_the_public_and_private_state(self):
        engine, _, roster = make()
        start_night(engine, games=["herd"])
        skip_ahead(engine, 3)
        assert "prompt" in engine.public_state()
        private = engine.private_state(roster[1].id)
        assert "prompt" in private                   # Herd's own phone data
        assert private["night"]["phase"] == "playing"
        assert engine.night_state()["phase"] == "playing"

    def test_hosted_actions_are_forwarded(self):
        engine, _, roster = make()
        start_night(engine, games=["herd"])
        skip_ahead(engine, 3)
        engine.handle_action(roster[1].id, "answer", {"text": "idli"})
        assert roster[1].id in engine.inner.submissions

    def test_announce_done_waits_for_the_minimum_hold(self):
        engine, _, _ = make()
        start_night(engine, games=["herd"])
        said = engine.announce["id"]
        engine.handle_action(TV, "night_announce_done", {"id": said})
        assert engine.phase == "welcome"             # spoken too fast to read
        assert engine.deadline == engine.hold_until
        engine.hold_until = time.time() - 1
        engine.handle_action(TV, "night_announce_done", {"id": said})
        assert engine.phase == "lineup"

    def test_announce_done_must_match_the_current_announcement(self):
        engine, _, _ = make()
        start_night(engine, games=["herd"])
        engine.hold_until = 0
        engine.handle_action(TV, "night_announce_done", {"id": engine.announce["id"] - 1})
        engine.handle_action(TV, "night_announce_done", {})
        assert engine.phase == "welcome"

    def test_a_guest_cannot_skip_the_hosts_announcement(self):
        engine, _, _ = make()
        start_night(engine, games=["herd"])
        engine.hold_until = 0
        engine.handle_action("p1", "night_announce_done", {"id": engine.announce["id"]})
        assert engine.phase == "welcome"

    def test_the_fallback_deadline_moves_the_show_on(self):
        engine, _, _ = make()
        start_night(engine, games=["herd"])
        engine.deadline = time.time() - 1            # the TV never reported back
        engine.tick(0.1)
        assert engine.phase == "lineup"

    def test_a_finished_game_scores_the_night_and_goes_to_the_interlude(self):
        engine, _, roster = make(players=2)
        start_night(engine, games=["never_have_i_ever"], nhiePack="classic")
        skip_ahead(engine, 3)
        inner = engine.inner
        assert inner.game_id == "never_have_i_ever" and inner.phase == "answer"
        inner.total_rounds = 1
        engine.handle_action("p0", "answer", {"choice": "have"})
        engine.handle_action("p1", "answer", {"choice": "never"})
        engine.tick(0.1)                              # reveal
        inner.deadline = time.time() - 1
        engine.tick(0.1)                              # round over -> game over -> interlude
        assert engine.phase == "interlude"
        assert engine.inner is None
        assert engine.night_scores == {"p0": 10, "p1": 7}
        recap = engine.night_state()["lastGame"]
        assert recap["winner"] == "P0" and recap["skipped"] is False
        assert [p.score for p in roster] == [10, 7]
        assert any("P0" in line for line in engine.announce["lines"])

    def test_the_tick_rate_follows_the_hosted_game(self):
        engine, _, _ = make()
        start_night(engine, games=["herd"])
        skip_ahead(engine, 3)
        engine.inner.tick_hz = 30.0                   # pretend it is a real-time game
        engine.tick_hz = engine.inner.tick_hz
        assert engine.tick_hz == 30.0
        engine.handle_action("p0", "night_skip", {})
        assert engine.tick_hz == 0.0

    def test_skipping_a_game_awards_nothing(self):
        engine, _, _ = make()
        start_night(engine, games=["herd", "trivia"])
        skip_ahead(engine, 3)
        engine.handle_action("p0", "night_skip", {})
        assert engine.phase == "interlude" and engine.inner is None
        assert all(v == 0 for v in engine.night_scores.values())
        assert engine.night_state()["lastGame"]["skipped"] is True

    def test_a_game_that_does_not_fit_the_room_is_skipped_with_a_note(self):
        engine, _, _ = make(players=2)               # Herd needs three
        start_night(engine, games=["herd"])
        skip_ahead(engine, 2)                        # welcome -> lineup -> next game
        assert engine.phase == "finale"
        assert any("Herd" in line and "skip" in line.lower()
                   for line in engine.announce["lines"])
        assert engine.log[0]["skipped"] is True

    def test_the_night_runs_to_a_ranked_finish(self):
        engine, room, roster = make(players=2)
        start_night(engine, occasion="birthday", honoree="Venkat",
                    games=["never_have_i_ever"], nhiePack="classic")
        skip_ahead(engine, 3)
        engine.inner.total_rounds = 1
        engine.handle_action("p1", "answer", {"choice": "have"})
        engine.handle_action("p0", "answer", {"choice": "never"})
        engine.tick(0.1)
        engine.inner.deadline = time.time() - 1
        engine.tick(0.1)
        skip_ahead(engine)                           # interlude -> finale
        assert engine.phase == "finale"
        lines = " ".join(engine.announce["lines"])
        assert "Venkat's Birthday Party" in lines and "P1" in lines
        assert not engine.is_over()
        skip_ahead(engine)                           # finale -> done
        assert engine.is_over()
        ranking = engine.results()
        assert [r["playerID"] for r in ranking] == ["p1", "p0"]
        assert ranking[0]["score"] == 10

    def test_ending_the_night_early_goes_straight_to_the_finale(self):
        engine, _, _ = make()
        start_night(engine, games=["herd", "trivia"])
        skip_ahead(engine, 3)
        engine.handle_action("p0", "night_end", {})
        assert engine.phase == "finale" and engine.inner is None

    def test_a_guest_cannot_drive_the_show(self):
        engine, _, _ = make()
        start_night(engine, games=["herd"])
        for verb in ("night_next", "night_skip", "night_end"):
            engine.handle_action("p1", verb, {})
        assert engine.phase == "welcome"

    def test_the_show_waits_if_every_phone_drops(self):
        engine, room, _ = make()
        start_night(engine, games=["herd"])
        skip_ahead(engine)                           # -> lineup
        for p in room.players:
            p.connected = False
        skip_ahead(engine, host=TV)
        assert engine.phase == "lineup"              # did not skip the evening


class TestLateGuests:
    def test_a_guest_who_arrives_mid_game_spectates(self):
        engine, room, _ = make()
        start_night(engine, games=["herd"])
        skip_ahead(engine, 3)
        late = room.add_player("late", "Late", "sx")
        engine.on_player_join(late)
        state = engine.private_state("late")
        assert state["night"]["spectating"] is True
        assert set(state) == {"night"}               # none of the game's data
        engine.handle_action("late", "answer", {"text": "idli"})
        assert "late" not in engine.inner.submissions

    def test_they_are_dealt_into_the_next_game(self):
        engine, room, _ = make(players=3)
        start_night(engine, games=["herd", "bluff_it"])
        skip_ahead(engine, 3)
        late = room.add_player("late", "Late", "sx")
        engine.on_player_join(late)
        engine.handle_action("p0", "night_skip", {})
        skip_ahead(engine, 2)                        # interlude -> intro -> playing
        assert "late" in engine.inner_roster
        assert engine.private_state("late")["night"]["spectating"] is False

    def test_a_guest_does_not_hold_up_a_hosted_round(self):
        engine, room, roster = make(players=3)
        start_night(engine, games=["herd"])
        skip_ahead(engine, 3)
        room.add_player("late", "Late", "sx")
        for p in roster:
            engine.handle_action(p.id, "answer", {"text": "idli"})
        engine.tick(0.1)
        assert engine.inner.phase == "reveal"


class TestStateShape:
    def test_every_phase_is_json_serialisable(self):
        engine, room, roster = make(players=3)
        start_night(engine, occasion="birthday", honoree="Venkat",
                    games=["herd", "never_have_i_ever"], nhiePack="classic")
        phases = []
        for _ in range(12):
            phases.append(engine.phase)
            json.dumps(engine.public_state())
            json.dumps(engine.night_state())
            for p in roster:
                state = engine.private_state(p.id)
                assert state
                json.dumps(state)
            if engine.phase == "playing":
                engine.handle_action("p0", "night_skip", {})
            else:
                skip_ahead(engine)
        assert {"welcome", "lineup", "intro", "playing", "interlude"} <= set(phases)

    def test_the_tv_channel_carries_what_the_board_needs(self):
        engine, room, _ = make()
        state = engine.night_state()
        for key in ("phase", "roomCode", "title", "lineup", "standings", "guests",
                    "announce", "gameCount", "occasion", "emoji"):
            assert key in state
        assert state["roomCode"] == room.code
        assert state["announce"] is None             # nothing said before the host starts

    def test_the_lineup_marks_progress(self):
        engine, _, _ = make()
        start_night(engine, games=["herd", "trivia"])
        skip_ahead(engine, 3)
        assert [g["state"] for g in engine.night_state()["lineup"]] == ["current", "next"]
        engine.handle_action("p0", "night_skip", {})
        skip_ahead(engine, 2)
        assert [g["state"] for g in engine.night_state()["lineup"]] == ["done", "current"]
