"""Guess the Song: the word bank, the humor packs, and the round flow."""

import json
import random
import time

import pytest

from games.native_hub.engines import _humor as H
from games.native_hub.engines._song_words import DECKS, WORDS
from games.native_hub.engines.guess_the_song import (
    GUESS_POINTS, HINT_POINTS, GuessTheSongEngine,
)
from utils.room_manager import RoomRegistry, RoomState

TV = "tv-device"
ALL_PRAISE = [line for pack in H.PACKS.values() for line in pack["guessed"]]


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(players=4, config=None, seed=5, deck="bollywood"):
    random.seed(seed)
    room = RoomRegistry().create("guess_the_song")
    room.options = {"deck": deck}
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    if config:
        room.night = {"party": config}      # what a Game Night's setup stores
    engine = GuessTheSongEngine(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def expire(engine):
    engine.deadline = time.time() - 1
    engine.tick(0.1)


class TestWordBank:
    @pytest.mark.parametrize("deck", sorted(DECKS))
    def test_each_word_has_one_to_three_songs(self, deck):
        for entry in DECKS[deck]["words"]:
            assert 1 <= len(entry["songs"]) <= 3, entry["word"]

    @pytest.mark.parametrize("deck", sorted(DECKS))
    def test_words_are_unique_and_complete(self, deck):
        words = [e["word"].lower() for e in DECKS[deck]["words"]]
        assert len(set(words)) == len(words)
        needs_hint = bool(DECKS[deck]["hintLabel"])
        for entry in DECKS[deck]["words"]:
            assert entry["word"].strip()
            assert bool(entry["hint"].strip()) == needs_hint, entry["word"]
            assert len(set(entry["songs"])) == len(entry["songs"]), entry["word"]
            for song in entry["songs"]:
                assert song.strip() and "(" in song, song     # "Title (Film or Artist)"

    @pytest.mark.parametrize("deck", sorted(DECKS))
    def test_there_are_enough_words_for_a_long_game(self, deck):
        assert len(DECKS[deck]["words"]) >= 40

    def test_the_train_example_is_there(self):
        train = next(e for e in WORDS if e["hint"] == "Train")
        assert any("Chaiyya Chaiyya" in s for s in train["songs"])

    @pytest.mark.parametrize("deck", ["bollywood", "tollywood"])
    def test_native_decks_show_the_native_word_and_hint_the_english(self, deck):
        """The word on screen is Hindi/Telugu (Latin letters); the hint is English."""
        assert DECKS[deck]["hintLabel"] == "English"
        words = DECKS[deck]["words"]
        rain = next(e for e in words if e["hint"] == "Rain")
        assert rain["word"] != "Rain"
        assert not any(e["word"] == "Rain" for e in words)

    def test_the_lobby_offers_every_deck_and_mixed(self):
        from games.native_hub import options
        choices = [c[0] for c in options.menu("guess_the_song")[0]["choices"]]
        assert choices == ["mix"] + list(DECKS)


class TestDecks:
    @pytest.mark.parametrize("deck", sorted(DECKS))
    def test_a_picked_deck_only_deals_its_own_words(self, deck):
        engine, _ = make(players=4, deck=deck)
        words = {e["word"] for e in DECKS[deck]["words"]}
        for _ in range(6):
            assert engine.deck == deck and engine.entry["word"] in words
            assert engine.public_state()["hintLabel"] == DECKS[deck]["hintLabel"]
            engine.handle_action(engine.judge_id, "judge", {"result": "missed"})
            expire(engine)

    def test_mixed_deals_from_every_deck(self):
        seen = set()
        for seed in range(30):
            engine, _ = make(players=4, deck="mix", seed=seed)
            seen.add(engine.deck)
        assert seen == set(DECKS)

    def test_english_has_no_hint_to_give(self):
        engine, _ = make(players=6, deck="english")
        assert engine.private_state(engine.judge_id)["hindi"] is None
        engine.handle_action(engine.judge_id, "hint", {})
        assert engine.public_state()["hint"] is None
        engine.handle_action(engine.judge_id, "judge", {"result": "guessed"})
        member = engine.team_members[engine.active_team][0]
        assert engine.scores[member] == GUESS_POINTS


class TestHumor:
    def test_every_pack_has_every_kind_of_line(self):
        for pid, pack in H.PACKS.items():
            for kind in ("guessed", "missed", "filler"):
                assert len(pack[kind]) >= 5, (pid, kind)
                assert len(set(pack[kind])) == len(pack[kind]), (pid, kind)

    def test_praise_says_good_job_somewhere(self):
        for pack in H.PACKS.values():
            assert any("good job" in line.lower() for line in pack["guessed"])

    def test_reactions_come_from_the_right_pack(self):
        for _ in range(20):
            assert H.reaction("dad", "guessed") in H.PACKS["dad"]["guessed"]
            assert H.reaction("dad", "missed") in H.PACKS["dad"]["missed"]

    def test_mix_and_unknown_draw_from_the_real_packs(self):
        for pid in ("mix", "nonsense"):
            for _ in range(30):
                assert H.reaction(pid, "guessed") in ALL_PRAISE

    def test_options_list_the_mix_first(self):
        options = H.pack_options()
        assert options[0]["id"] == H.MIX
        assert {o["id"] for o in options} == H.PACK_IDS


class TestTeams:
    def test_four_or_more_split_into_two_teams(self):
        engine, _ = make(players=5)
        assert [len(m) for m in engine.team_members] == [3, 2]
        assert engine.public_state()["mode"] == "teams"

    def test_fewer_than_four_play_as_one_team(self):
        engine, _ = make(players=3)
        assert len(engine.team_members) == 1
        assert engine.public_state()["mode"] == "together"

    def test_the_judge_is_on_the_other_team(self):
        engine, _ = make(players=6)
        assert engine.team_of[engine.judge_id] != engine.active_team

    def test_teams_take_turns_and_the_judge_rotates(self):
        engine, _ = make(players=6)
        teams, judges = [], []
        for _ in range(4):
            teams.append(engine.active_team)
            judges.append(engine.judge_id)
            engine.handle_action(engine.judge_id, "judge", {"result": "missed"})
            expire(engine)                       # reveal -> next round
        assert teams == [0, 1, 0, 1]
        assert judges[0] != judges[2]

    def test_together_mode_the_host_judges(self):
        engine, roster = make(players=3)
        assert engine.judge_id == roster[0].id


class TestRound:
    def test_everyone_sees_the_word_but_only_the_judge_sees_answers(self):
        engine, roster = make(players=6)
        word = engine.entry["word"]
        assert engine.public_state()["word"] == word
        for p in roster:
            state = engine.private_state(p.id)
            assert state["word"] == word
            if p.id == engine.judge_id:
                assert state["answers"] == engine.entry["songs"]
                assert state["isJudge"] is True
            else:
                assert state["answers"] == [] and state["isJudge"] is False

    def test_answers_never_appear_in_the_public_state_before_the_reveal(self):
        engine, _ = make()
        blob = json.dumps(engine.public_state())
        for song in engine.entry["songs"]:
            assert song not in blob
        assert engine.public_state()["answers"] == []

    def test_a_guess_scores_the_whole_team_and_praises_them(self):
        engine, _ = make(players=6)
        team = engine.active_team
        engine.handle_action(engine.judge_id, "judge", {"result": "guessed"})
        assert engine.phase == "reveal"
        for pid in engine.team_members[team]:
            assert engine.scores[pid] == GUESS_POINTS
        assert all(engine.scores[pid] == 0 for pid in engine.team_members[1 - team])
        state = engine.public_state()
        assert state["outcome"] == "guessed"
        assert state["humor"] in ALL_PRAISE
        assert state["answers"] == []            # nothing to reveal when they got it

    def test_a_miss_reveals_the_answers_on_the_tv_and_phones(self):
        engine, _ = make(players=6)
        engine.handle_action(engine.judge_id, "judge", {"result": "missed"})
        state = engine.public_state()
        assert state["outcome"] == "missed"
        assert state["answers"] == engine.entry["songs"]
        assert state["humor"] and state["filler"]
        assert all(v == 0 for v in engine.scores.values())
        guesser = engine.team_members[engine.active_team][0]
        assert engine.private_state(guesser)["answers"] == engine.entry["songs"]

    def test_the_hint_reveals_the_english_meaning_and_costs_points(self):
        engine, _ = make(players=6)
        assert engine.public_state()["hint"] is None
        assert engine.private_state(engine.judge_id)["hindi"] == engine.entry["hint"]
        engine.handle_action(engine.judge_id, "hint", {})
        assert engine.public_state()["hint"] == engine.entry["hint"]
        engine.handle_action(engine.judge_id, "judge", {"result": "guessed"})
        member = engine.team_members[engine.active_team][0]
        assert engine.scores[member] == HINT_POINTS

    def test_hindi_is_only_offered_to_the_judge_until_revealed(self):
        engine, _ = make(players=6)
        guesser = engine.team_members[engine.active_team][0]
        assert engine.private_state(guesser)["hindi"] is None

    def test_only_the_judge_or_the_tv_can_give_a_verdict(self):
        engine, roster = make(players=6)
        for p in roster:
            if p.id != engine.judge_id:
                engine.handle_action(p.id, "judge", {"result": "guessed"})
                engine.handle_action(p.id, "hint", {})
        assert engine.phase == "guess" and engine.hint_used is False
        engine.handle_action(TV, "judge", {"result": "guessed"})
        assert engine.phase == "reveal"

    def test_the_host_steps_in_if_the_judge_drops(self):
        engine, roster = make(players=6)
        host = next(p for p in roster if p.is_host)
        if host.id == engine.judge_id:
            pytest.skip("host is the judge with this seed")
        engine.room.player(engine.judge_id).connected = False
        engine.handle_action(host.id, "judge", {"result": "missed"})
        assert engine.phase == "reveal"

    def test_the_host_cannot_override_a_judge_who_is_still_there(self):
        engine, roster = make(players=6)
        host = next(p for p in roster if p.is_host)
        if host.id == engine.judge_id:
            pytest.skip("host is the judge with this seed")
        engine.handle_action(host.id, "judge", {"result": "guessed"})
        assert engine.phase == "guess"

    def test_junk_verdicts_are_ignored(self):
        engine, _ = make()
        for junk in ("yes", None, 3, {"a": 1}, ""):
            engine.handle_action(engine.judge_id, "judge", {"result": junk})
        assert engine.phase == "guess"

    def test_a_late_verdict_after_the_reveal_changes_nothing(self):
        engine, _ = make(players=6)
        engine.handle_action(engine.judge_id, "judge", {"result": "missed"})
        engine.handle_action(engine.judge_id, "judge", {"result": "guessed"})
        assert engine.outcome == "missed"
        assert all(v == 0 for v in engine.scores.values())

    def test_time_runs_out_into_a_grace_period(self):
        engine, _ = make()
        expire(engine)
        assert engine.phase == "verdict"
        engine.handle_action(engine.judge_id, "judge", {"result": "guessed"})
        assert engine.outcome == "guessed"       # the judge still had time to decide

    def test_a_judge_who_never_answers_counts_as_missed(self):
        engine, _ = make()
        expire(engine)
        expire(engine)
        assert engine.phase == "reveal" and engine.outcome == "missed"

    def test_no_word_repeats_in_a_game(self):
        engine, _ = make(players=6, seed=11)
        seen = []
        for _ in range(engine.total_rounds):
            seen.append(engine.entry["word"])
            engine.handle_action(engine.judge_id, "judge", {"result": "missed"})
            expire(engine)
        assert len(set(seen)) == len(seen)
        assert engine.is_over()

    def test_results_rank_the_winning_team_first(self):
        engine, _ = make(players=4)
        winners = set(engine.team_members[engine.active_team])
        engine.handle_action(engine.judge_id, "judge", {"result": "guessed"})
        expire(engine)
        top = engine.results()[:len(winners)]
        assert {r["playerID"] for r in top} == winners

    def test_a_humor_pack_from_a_game_night_is_used(self):
        engine, _ = make(players=6, config={"humor": "dad"})
        engine.handle_action(engine.judge_id, "judge", {"result": "missed"})
        assert engine.humor_line in H.PACKS["dad"]["missed"]
        assert engine.filler_line in H.PACKS["dad"]["filler"]

    def test_state_is_json_serialisable_in_every_phase(self):
        engine, roster = make(players=5)
        for _ in range(3):
            json.dumps(engine.public_state())
            for p in roster:
                json.dumps(engine.private_state(p.id))
            expire(engine)
