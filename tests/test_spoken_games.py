"""Atlas and Antakshari as SPOKEN games.

People talk or sing out loud; the TV hosts; phones only tap (Valid / Out!,
Sang it / Missed, and a 26-letter grid for the last letter). Nothing here
accepts typed answers as a move -- the old ``answer`` / ``submit_song``
verbs must be dead.
"""

import json
import random
import string
import time

import pytest

from games import game_night, teams
from games.native_hub import bots
from games.native_hub.bots import maybe_bot_action
from games.native_hub.engines import _content as C
from games.native_hub.engines.spoken import (
    HARD_LETTERS, AntakshariEngine, AtlasEngine,
)
from games.native_hub.registry import ENGINES
from games.native_hub.rules import RULES
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(game_id, players=4, n_bots=0, seed=3, set_teams=None):
    random.seed(seed)
    registry = RoomRegistry()
    room = registry.create(game_id)
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    roster += [room.add_bot() for _ in range(n_bots)]
    if set_teams is not None:
        set_teams(room)
    engine = ENGINES[game_id](room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(list(room.players))
    return engine, roster


def expire(engine):
    """Run the current phase's clock out."""
    engine.deadline = time.time() - 0.01
    engine.tick(1.0)


def judges_of(engine):
    return [pid for pid in engine.judges()]


# ---------------------------------------------------------------------------
# Registry, catalog, rules
# ---------------------------------------------------------------------------

class TestWiring:
    def test_game_ids_are_kept(self):
        assert ENGINES["atlas"] is AtlasEngine
        assert ENGINES["antakshari"] is AntakshariEngine

    def test_catalog_entries(self):
        assert game_night.CATALOG["atlas"] == {
            "minutes": 8, "kids": True, "tags": ["words", "geography"]}
        assert game_night.CATALOG["antakshari"] == {
            "minutes": 15, "kids": False, "tags": ["music"]}

    def test_atlas_is_offered_in_kids_mode_and_antakshari_is_not(self):
        ids = {g["id"] for g in game_night.pick_games(4, kids=True)}
        assert "atlas" in ids
        assert "antakshari" not in ids

    @pytest.mark.parametrize("game_id", ["atlas", "antakshari"])
    def test_rules_describe_a_spoken_game_without_typing(self, game_id):
        entry = RULES[game_id]
        text = " ".join([entry["objective"], entry["controls"], *entry["rules"]]).lower()
        assert "no typing" in entry["controls"].lower()
        assert "type your" not in text
        assert "out loud" in text

    def test_bot_policies_are_registered(self):
        assert "atlas" in bots.POLICIES
        assert "antakshari" in bots.POLICIES


# ---------------------------------------------------------------------------
# Atlas
# ---------------------------------------------------------------------------

class TestAtlasStart:
    def test_everyone_starts_with_three_lives_and_the_first_seat_speaks(self):
        engine, roster = make("atlas", players=4)
        assert engine.phase == "say"
        assert engine.speaker == roster[0].id
        assert all(engine.lives[p.id] == 3 for p in roster)
        assert engine.alive == [p.id for p in roster]

    def test_the_chain_opens_on_a_seed_place_and_its_last_letter(self):
        engine, _ = make("atlas")
        seed = engine.chain[0]
        assert seed["place"] in C.ATLAS_SEEDS and seed["playerID"] is None
        assert engine.letter == seed["place"][-1].upper()

    def test_the_turn_clock_is_about_ten_seconds(self):
        engine, _ = make("atlas")
        assert engine.turn_seconds == 10
        assert 9 <= engine.seconds_left() <= 10

    def test_the_turn_clock_shrinks_each_lap_but_not_below_five(self):
        engine, _ = make("atlas", players=4)
        engine.turns_taken = 4
        assert engine._turn_seconds() == 9
        engine.turns_taken = 8
        assert engine._turn_seconds() == 8
        engine.turns_taken = 400
        assert engine._turn_seconds() == AtlasEngine.MIN_TURN_SECONDS

    def test_min_players_is_two(self):
        # The room judges, so there must be somebody to listen.
        assert AtlasEngine.min_players == 2


class TestAtlasJudging:
    def test_a_majority_of_valid_taps_passes_the_turn(self):
        engine, roster = make("atlas", players=4)
        speaker = engine.speaker
        others = [p.id for p in roster if p.id != speaker]
        assert engine.votes_needed() == 2
        engine.handle_action(others[0], "judge", {"verdict": "valid"})
        assert engine.phase == "say"
        engine.handle_action(others[1], "judge", {"verdict": "valid"})
        assert engine.phase == "letter"
        assert engine.speaker == speaker            # they now tap the letter
        assert engine.verdict["kind"] == "valid"
        assert engine.places[speaker] == 1
        assert engine.room.player(speaker).score == AtlasEngine.POINTS_PER_PLACE

    def test_the_speakers_own_next_tap_passes_the_turn(self):
        engine, _ = make("atlas", players=3)
        engine.handle_action(engine.speaker, "said", {})
        assert engine.phase == "letter"

    def test_only_the_speaker_can_tap_next(self):
        engine, roster = make("atlas", players=3)
        other = next(p.id for p in roster if p.id != engine.speaker)
        engine.handle_action(other, "said", {})
        assert engine.phase == "say"

    def test_the_speaker_cannot_judge_themselves(self):
        engine, _ = make("atlas", players=2)
        engine.handle_action(engine.speaker, "judge", {"verdict": "valid"})
        assert engine.phase == "say" and engine.votes == {}

    def test_a_majority_of_out_taps_costs_a_life_and_keeps_the_letter(self):
        engine, roster = make("atlas", players=4)
        speaker, letter = engine.speaker, engine.letter
        others = [p.id for p in roster if p.id != speaker]
        engine.handle_action(others[0], "judge", {"verdict": "out"})
        engine.handle_action(others[1], "judge", {"verdict": "out"})
        assert engine.phase == "verdict"
        assert engine.lives[speaker] == 2
        assert engine.verdict["kind"] == "out" and engine.verdict["livesLeft"] == 2
        expire(engine)
        assert engine.phase == "say"
        assert engine.speaker == roster[1].id
        assert engine.letter == letter

    def test_a_judge_can_change_their_tap(self):
        engine, roster = make("atlas", players=4)
        judge = next(p.id for p in roster if p.id != engine.speaker)
        engine.handle_action(judge, "judge", {"verdict": "out"})
        engine.handle_action(judge, "judge", {"verdict": "valid"})
        assert engine.votes[judge] == "valid"
        assert engine.public_state()["votes"]["valid"] == 1
        assert engine.public_state()["votes"]["out"] == 0

    def test_two_players_one_judge_decides(self):
        engine, roster = make("atlas", players=2)
        judge = roster[1].id
        engine.handle_action(judge, "judge", {"verdict": "valid"})
        assert engine.phase == "letter"

    def test_junk_verdicts_are_ignored(self):
        engine, roster = make("atlas", players=3)
        judge = roster[1].id
        for junk in (None, "VALID", "maybe", 1, ["valid"]):
            engine.handle_action(judge, "judge", {"verdict": junk})
        engine.handle_action(judge, "judge", "not a dict")
        assert engine.votes == {}

    def test_disconnected_judges_do_not_count_toward_the_majority(self):
        engine, roster = make("atlas", players=4)
        roster[2].connected = False
        roster[3].connected = False
        assert engine.judges() == [roster[1].id]
        engine.handle_action(roster[1].id, "judge", {"verdict": "valid"})
        assert engine.phase == "letter"

    def test_knocked_out_players_still_judge(self):
        engine, roster = make("atlas", players=3)
        engine.lives[roster[2].id] = 0
        engine.alive.remove(roster[2].id)
        assert roster[2].id in engine.judges()

    def test_votes_only_count_while_the_speaker_is_talking(self):
        engine, roster = make("atlas", players=3)
        engine.handle_action(engine.speaker, "said", {})
        engine.handle_action(roster[1].id, "judge", {"verdict": "out"})
        assert engine.phase == "letter" and engine.votes == {}


class TestAtlasClock:
    def test_running_out_of_time_costs_a_life(self):
        engine, _ = make("atlas", players=3)
        speaker = engine.speaker
        expire(engine)
        assert engine.phase == "verdict"
        assert engine.verdict["kind"] == "timeout"
        assert engine.lives[speaker] == 2

    def test_a_room_leaning_valid_at_the_buzzer_still_passes(self):
        engine, roster = make("atlas", players=5)
        judge = next(p.id for p in roster if p.id != engine.speaker)
        engine.handle_action(judge, "judge", {"verdict": "valid"})
        assert engine.phase == "say"                 # 1 of 4 is no majority
        expire(engine)
        assert engine.phase == "letter"

    def test_a_split_room_at_the_buzzer_is_a_timeout(self):
        engine, roster = make("atlas", players=5)
        others = [p.id for p in roster if p.id != engine.speaker]
        engine.handle_action(others[0], "judge", {"verdict": "valid"})
        engine.handle_action(others[1], "judge", {"verdict": "out"})
        expire(engine)
        assert engine.verdict["kind"] == "timeout"

    def test_seconds_left_and_phase_seconds_are_reported(self):
        engine, _ = make("atlas")
        state = engine.public_state()
        assert state["phaseSeconds"] == 10
        engine.handle_action(engine.speaker, "said", {})
        assert engine.public_state()["phaseSeconds"] == AtlasEngine.LETTER_SECONDS


class TestAtlasLetter:
    def _to_letter_phase(self, engine):
        engine.handle_action(engine.speaker, "said", {})
        assert engine.phase == "letter"

    def test_the_speaker_taps_the_last_letter_and_the_next_seat_gets_it(self):
        engine, roster = make("atlas", players=3)
        self._to_letter_phase(engine)
        engine.handle_action(roster[0].id, "pick_letter", {"letter": "m"})
        assert engine.letter == "M"
        assert engine.phase == "say" and engine.speaker == roster[1].id
        assert engine.chain[-1]["endLetter"] == "M"
        assert engine.chain[-1]["playerID"] == roster[0].id
        assert engine.skipped is None

    def test_only_the_speaker_picks_the_letter(self):
        engine, roster = make("atlas", players=3)
        self._to_letter_phase(engine)
        engine.handle_action(roster[1].id, "pick_letter", {"letter": "M"})
        assert engine.phase == "letter"

    def test_junk_letters_are_ignored(self):
        engine, roster = make("atlas", players=3)
        self._to_letter_phase(engine)
        for junk in ("", "AB", "1", None, 5, "é", " "):
            engine.handle_action(roster[0].id, "pick_letter", {"letter": junk})
        assert engine.phase == "letter"

    @pytest.mark.parametrize("hard", list(HARD_LETTERS))
    def test_hard_letters_skip_to_a_new_letter(self, hard):
        engine, roster = make("atlas", players=3)
        self._to_letter_phase(engine)
        engine.handle_action(roster[0].id, "pick_letter", {"letter": hard})
        assert engine.letter in C.ATLAS_EASY_LETTERS
        assert engine.skipped["from"] == hard
        assert engine.skipped["to"] == engine.letter
        assert engine.chain[-1]["endLetter"] == hard

    def test_no_letter_tapped_in_time_picks_a_fresh_one(self):
        engine, roster = make("atlas", players=3)
        self._to_letter_phase(engine)
        expire(engine)
        assert engine.letter in C.ATLAS_EASY_LETTERS
        assert engine.skipped["reason"] == "timeout"
        assert engine.speaker == roster[1].id

    def test_every_letter_of_the_alphabet_is_accepted(self):
        for letter in string.ascii_uppercase:
            engine, roster = make("atlas", players=2)
            self._to_letter_phase(engine)
            engine.handle_action(roster[0].id, "pick_letter", {"letter": letter})
            assert engine.phase == "say"
            if letter not in HARD_LETTERS:
                assert engine.letter == letter


class TestAtlasSpelling:
    def test_there_is_no_typed_answer_verb(self):
        engine, roster = make("atlas", players=3)
        engine.handle_action(engine.speaker, "answer", {"place": "Agra"})
        assert engine.phase == "say" and len(engine.chain) == 1

    def test_spelling_is_off_by_default_and_a_typed_place_is_dropped(self):
        engine, roster = make("atlas", players=3)
        assert engine.spelling is False
        engine.handle_action(engine.speaker, "said", {})
        engine.handle_action(roster[0].id, "pick_letter", {"letter": "A", "place": "Agra"})
        assert engine.chain[-1]["place"] == ""

    def test_the_host_can_turn_on_spelling_for_kids(self):
        engine, roster = make("atlas", players=3)
        assert roster[0].is_host
        engine.handle_action(roster[1].id, "toggle_spelling", {"on": True})
        assert engine.spelling is False
        engine.handle_action(roster[0].id, "toggle_spelling", {"on": True})
        assert engine.spelling is True
        assert engine.public_state()["spelling"] is True
        engine.handle_action(engine.speaker, "said", {})
        engine.handle_action(roster[0].id, "pick_letter",
                             {"letter": "A", "place": "  Agra   " + "x" * 80})
        place = engine.chain[-1]["place"]
        assert place.startswith("Agra x") and len(place) == 40
        engine.handle_action(roster[0].id, "toggle_spelling", {})
        assert engine.spelling is False


class TestAtlasLives:
    def _strike(self, engine):
        expire(engine)                       # say -> verdict (timeout)
        if not engine.is_over():
            expire(engine)                   # verdict -> next turn

    def test_three_strikes_and_you_are_out(self):
        engine, roster = make("atlas", players=3)
        target = roster[0].id
        for _ in range(3):
            while engine.speaker != target:
                engine.handle_action(engine.speaker, "said", {})
                engine.handle_action(engine.speaker, "pick_letter", {"letter": "A"})
            self._strike(engine)
        assert engine.lives[target] == 0
        assert target not in engine.alive
        assert engine.eliminated == [target]
        assert engine.private_state(target)["isOut"] is True

    def test_knocked_out_players_are_skipped(self):
        engine, roster = make("atlas", players=3)
        engine.alive.remove(roster[1].id)
        engine.lives[roster[1].id] = 0
        engine.handle_action(engine.speaker, "said", {})
        engine.handle_action(roster[0].id, "pick_letter", {"letter": "B"})
        assert engine.speaker == roster[2].id

    def test_players_away_from_the_room_are_skipped(self):
        engine, roster = make("atlas", players=3)
        roster[1].connected = False
        engine.handle_action(engine.speaker, "said", {})
        engine.handle_action(roster[0].id, "pick_letter", {"letter": "B"})
        assert engine.speaker == roster[2].id

    def test_last_player_standing_wins(self):
        engine, roster = make("atlas", players=2)
        loser, winner = roster[0].id, roster[1].id
        engine.lives[loser] = 1
        assert engine.speaker == loser
        expire(engine)
        assert engine.verdict["eliminated"] is True
        assert not engine.is_over()          # the verdict flashes first
        expire(engine)
        assert engine.is_over()
        assert engine.winner == winner
        state = engine.public_state()
        assert state["finished"] and state["winnerID"] == winner
        results = engine.results()
        assert results[0]["playerID"] == winner and results[0]["rank"] == 1
        assert results[1]["playerID"] == loser and results[1]["rank"] == 2

    def test_results_rank_by_survival_then_places(self):
        engine, roster = make("atlas", players=4)
        a, b, c, d = (p.id for p in roster)
        engine.places.update({a: 9, b: 1, c: 5, d: 0})
        engine.alive = [d]
        engine.eliminated = [a, c, b]        # a out first, b out last
        engine.winner = d
        order = [r["playerID"] for r in engine.results()]
        assert order == [d, b, c, a]
        assert [r["rank"] for r in engine.results()] == [1, 2, 3, 4]
        for row in engine.results():
            assert {"playerID", "name", "score", "rank"} <= set(row)

    def test_finished_games_ignore_further_taps(self):
        engine, roster = make("atlas", players=2)
        engine._finish()
        engine.handle_action(roster[1].id, "judge", {"verdict": "valid"})
        engine.tick(1.0)
        assert engine.phase == "over"


class TestAtlasState:
    def test_public_state_is_serialisable_and_carries_the_board(self):
        engine, roster = make("atlas", players=3)
        state = engine.public_state()
        json.dumps(state)
        for key in ("letter", "chain", "players", "votes", "verdict", "phaseSeconds",
                    "currentName", "maxLives", "spelling", "skipped"):
            assert key in state
        assert state["players"][0]["lives"] == 3
        assert state["players"][0]["isSpeaker"] is True

    def test_verdicts_carry_an_increasing_sequence_for_the_tv_flash(self):
        engine, roster = make("atlas", players=3)
        engine.handle_action(engine.speaker, "said", {})
        first = engine.verdict["seq"]
        engine.handle_action(roster[0].id, "pick_letter", {"letter": "A"})
        expire(engine)
        assert engine.verdict["seq"] == first + 1

    def test_private_roles(self):
        engine, roster = make("atlas", players=3)
        speaker = engine.speaker
        assert engine.private_state(speaker)["role"] == "speak"
        assert engine.private_state(roster[1].id)["role"] == "judge"
        engine.handle_action(speaker, "said", {})
        assert engine.private_state(speaker)["role"] == "pick"
        assert engine.private_state(roster[1].id)["role"] == "wait"
        for player in roster:
            json.dumps(engine.private_state(player.id))

    def test_private_state_reports_my_vote(self):
        engine, roster = make("atlas", players=4)
        engine.handle_action(roster[1].id, "judge", {"verdict": "out"})
        assert engine.private_state(roster[1].id)["myVote"] == "out"
        assert engine.private_state(roster[2].id)["myVote"] == ""

    def test_the_host_flag_reaches_only_the_host(self):
        engine, roster = make("atlas", players=3)
        assert engine.private_state(roster[0].id)["isHost"] is True
        assert engine.private_state(roster[1].id)["isHost"] is False


# ---------------------------------------------------------------------------
# Antakshari
# ---------------------------------------------------------------------------

def to_sing(engine):
    """From a beat into the next singing turn."""
    assert engine.phase == "beat"
    expire(engine)
    assert engine.phase == "sing"


def member(engine, team):
    return engine.teams[team]["members"][0]


class TestAntakshariTeams:
    def test_auto_split_is_balanced(self):
        engine, roster = make("antakshari", players=5)
        sizes = sorted(len(t["members"]) for t in engine.teams)
        assert sizes == [2, 3]
        assert set(engine.team_of) == {p.id for p in roster}

    def test_room_teams_are_used_when_set(self):
        def fix(room):
            teams.set_teams(room, lists=[["p0", "p3"], ["p1", "p2"]],
                            names=["Lions", "Tigers"], shuffle=False)
        engine, _ = make("antakshari", players=4, set_teams=fix)
        assert engine.teams[0]["members"] == ["p0", "p3"]
        assert engine.teams[1]["members"] == ["p1", "p2"]
        assert engine.teams[0]["name"] == "Lions"
        assert engine.teams[1]["name"] == "Tigers"

    def test_extra_room_teams_fold_onto_two_sides(self):
        def fix(room):
            teams.set_teams(room, lists=[["p0"], ["p1"], ["p2"], ["p3"]], shuffle=False)
        engine, _ = make("antakshari", players=4, set_teams=fix)
        assert sorted(len(t["members"]) for t in engine.teams) == [2, 2]

    def test_no_side_is_left_empty(self):
        def fix(room):
            teams.set_teams(room, lists=[["p0", "p1", "p2"], []], shuffle=False)
        engine, _ = make("antakshari", players=3, set_teams=fix)
        assert all(t["members"] for t in engine.teams)


class TestAntakshariFlow:
    def test_it_opens_on_a_beat_then_team_a_sings(self):
        engine, _ = make("antakshari", players=4)
        assert engine.phase == "beat"
        assert engine.letter in C.ANTAKSHARI_LETTERS
        to_sing(engine)
        assert engine.singing == 0 and engine.round == 1
        assert engine.seconds_left() >= 29
        assert engine.public_state()["phaseSeconds"] == 30

    def test_the_other_team_judges_and_sang_it_scores(self):
        engine, _ = make("antakshari", players=4)
        to_sing(engine)
        engine.handle_action(member(engine, 0), "judge", {"verdict": "sang"})
        assert engine.phase == "sing"        # singers cannot judge themselves
        engine.handle_action(member(engine, 1), "judge", {"verdict": "sang"})
        assert engine.scores == [1, 0]
        assert engine.phase == "letter"
        assert engine.verdict["kind"] == "sang" and engine.verdict["team"] == 0
        for pid in engine.teams[0]["members"]:
            assert engine.room.player(pid).score == 1

    def test_the_singers_tap_the_last_letter_then_the_other_team_sings_it(self):
        engine, _ = make("antakshari", players=4)
        to_sing(engine)
        engine.handle_action(member(engine, 1), "judge", {"verdict": "sang"})
        engine.handle_action(member(engine, 1), "pick_letter", {"letter": "K"})
        assert engine.phase == "letter"      # judges cannot pick
        engine.handle_action(member(engine, 0), "pick_letter", {"letter": "k"})
        assert engine.letter == "K"
        assert engine.phase == "beat"
        assert engine.history[-1]["endLetter"] == "K"
        to_sing(engine)
        assert engine.singing == 1 and engine.letter == "K"

    def test_a_miss_hands_the_same_letter_to_the_other_team(self):
        engine, _ = make("antakshari", players=4)
        to_sing(engine)
        letter = engine.letter
        engine.handle_action(member(engine, 1), "judge", {"verdict": "missed"})
        assert engine.scores == [0, 0]
        assert engine.verdict["kind"] == "missed"
        to_sing(engine)
        assert engine.singing == 1 and engine.letter == letter

    def test_the_buzzer_hands_the_letter_over_too(self):
        engine, _ = make("antakshari", players=4)
        to_sing(engine)
        letter = engine.letter
        expire(engine)
        assert engine.verdict["kind"] == "timeout"
        to_sing(engine)
        assert engine.singing == 1 and engine.letter == letter

    @pytest.mark.parametrize("hard", list(HARD_LETTERS))
    def test_hard_letters_skip_to_a_new_letter(self, hard):
        engine, _ = make("antakshari", players=2)
        to_sing(engine)
        engine.handle_action(member(engine, 1), "judge", {"verdict": "sang"})
        engine.handle_action(member(engine, 0), "pick_letter", {"letter": hard})
        assert engine.letter in C.ANTAKSHARI_LETTERS
        assert engine.skipped == {"from": hard, "to": engine.letter, "reason": "hard"}

    def test_no_letter_tapped_in_time_picks_a_singable_one(self):
        engine, _ = make("antakshari", players=2)
        to_sing(engine)
        engine.handle_action(member(engine, 1), "judge", {"verdict": "sang"})
        expire(engine)
        assert engine.letter in C.ANTAKSHARI_LETTERS
        assert engine.skipped["reason"] == "timeout"
        assert engine.phase == "beat" and engine.singing == 1

    def test_typed_songs_are_not_a_move(self):
        engine, _ = make("antakshari", players=2)
        to_sing(engine)
        engine.handle_action(member(engine, 0), "submit_song", {"song": "Tum Hi Ho"})
        assert engine.phase == "sing" and engine.scores == [0, 0]

    def test_strangers_and_junk_are_ignored(self):
        engine, _ = make("antakshari", players=2)
        to_sing(engine)
        engine.handle_action("ghost", "judge", {"verdict": "sang"})
        engine.handle_action(member(engine, 1), "judge", {"verdict": "yes"})
        engine.handle_action(member(engine, 1), "judge", None)
        assert engine.phase == "sing"


class TestAntakshariEnding:
    def test_first_to_eight_wins_after_the_flash(self):
        engine, _ = make("antakshari", players=4)
        to_sing(engine)
        engine.scores = [7, 3]
        engine.handle_action(member(engine, 1), "judge", {"verdict": "sang"})
        assert engine.scores == [8, 3]
        assert engine.phase == "beat" and not engine.is_over()
        expire(engine)
        assert engine.is_over() and engine.winner_team == 0
        results = engine.results()
        winners = set(engine.teams[0]["members"])
        for row in results:
            assert row["rank"] == (1 if row["playerID"] in winners else 2)
            assert {"playerID", "name", "score", "rank"} <= set(row)
        assert results[0]["playerID"] in winners

    def test_the_fifteen_minute_clock_ends_the_game_between_turns(self):
        engine, _ = make("antakshari", players=4)
        to_sing(engine)
        engine.ends_at = time.time() - 1
        engine.handle_action(member(engine, 1), "judge", {"verdict": "missed"})
        assert not engine.is_over()          # the turn finishes first
        expire(engine)
        assert engine.is_over()

    def test_a_draw_ranks_everyone_first(self):
        engine, roster = make("antakshari", players=4)
        engine.scores = [3, 3]
        engine._finish()
        assert engine.winner_team is None
        assert {r["rank"] for r in engine.results()} == {1}

    def test_game_length_and_target(self):
        assert AntakshariEngine.TARGET_POINTS == 8
        assert AntakshariEngine.GAME_SECONDS == 15 * 60
        assert AntakshariEngine.SING_SECONDS == 30


class TestAntakshariState:
    def test_the_hint_waits_until_the_team_is_stuck(self):
        engine, _ = make("antakshari", players=2)
        to_sing(engine)
        assert engine.public_state()["hint"] == ""
        engine.turn_started = time.time() - AntakshariEngine.HINT_AFTER_SECONDS - 1
        hint = engine.public_state()["hint"]
        assert hint in C.ANTAKSHARI_HINTS and hint.startswith("Hint: try")

    def test_private_roles(self):
        engine, _ = make("antakshari", players=4)
        a, b = member(engine, 0), member(engine, 1)
        assert engine.private_state(a)["role"] == "wait"
        to_sing(engine)
        assert engine.private_state(a)["role"] == "sing"
        assert engine.private_state(b)["role"] == "judge"
        engine.handle_action(b, "judge", {"verdict": "sang"})
        assert engine.private_state(a)["role"] == "pick"
        assert engine.private_state(b)["role"] == "wait"
        mine = engine.private_state(a)
        assert mine["myTeam"] == 0 and mine["teamScores"] == [1, 0]
        assert set(HARD_LETTERS) <= set(mine["hardLetters"])
        assert mine["suggestedLetters"]

    def test_public_state_is_serialisable(self):
        engine, roster = make("antakshari", players=5)
        to_sing(engine)
        state = engine.public_state()
        json.dumps(state)
        assert len(state["teams"]) == 2
        assert state["target"] == 8
        assert 0 < state["gameSecondsLeft"] <= 15 * 60
        for p in roster:
            json.dumps(engine.private_state(p.id))


# ---------------------------------------------------------------------------
# Bots
# ---------------------------------------------------------------------------

def act_now(engine, bot):
    """Skip the thinking delay and return the bot's move for this phase."""
    maybe_bot_action(engine, bot)
    bot.bot_act_at = 0.0
    return maybe_bot_action(engine, bot)


class TestSpokenBots:
    def test_atlas_bot_judges_valid_or_out(self):
        engine, roster = make("atlas", players=1, n_bots=2)
        bot = roster[1]
        verb, payload = act_now(engine, bot)
        assert verb == "judge" and payload["verdict"] in ("valid", "out")

    def test_atlas_bot_speaker_says_it_then_picks_a_matching_letter(self, monkeypatch):
        monkeypatch.setattr(bots.random, "random", lambda: 0.9)
        engine, roster = make("atlas", players=1, n_bots=1)
        bot = roster[1]
        engine.speaker = bot.id
        act = act_now(engine, bot)
        assert act == ("said", {})
        engine.handle_action(bot.id, *act)
        verb, payload = act_now(engine, bot)
        assert verb == "pick_letter"
        assert payload["letter"] in string.ascii_uppercase
        if payload["place"]:
            assert payload["place"][0].upper() == engine.chain[-1]["letter"]
            assert payload["place"][-1].upper() == payload["letter"]
        engine.handle_action(bot.id, verb, payload)
        # A bot cannot say its place out loud, so the TV shows it.
        assert engine.chain[-1]["place"] == payload["place"]

    def test_antakshari_bot_judges_only_for_the_other_team(self):
        engine, roster = make("antakshari", players=1, n_bots=3)
        to_sing(engine)
        for bot in roster[1:]:
            act = act_now(engine, bot)
            if engine.team_of[bot.id] == engine.singing:
                assert act is None            # bots cannot sing
            else:
                assert act[0] == "judge" and act[1]["verdict"] in ("sang", "missed")

    def test_antakshari_bot_picks_a_plausible_letter_for_its_team(self):
        engine, roster = make("antakshari", players=1, n_bots=3)
        to_sing(engine)
        judge = member(engine, 1)
        engine.handle_action(judge, "judge", {"verdict": "sang"})
        singer_bots = [b for b in roster[1:] if engine.team_of[b.id] == 0]
        verb, payload = act_now(engine, singer_bots[0])
        assert verb == "pick_letter" and payload["letter"] in string.ascii_uppercase

    @pytest.mark.parametrize("game_id", ["atlas", "antakshari"])
    def test_an_all_bot_table_plays_to_the_end(self, game_id):
        engine, roster = make(game_id, players=0, n_bots=4, seed=11)
        if game_id == "antakshari":
            engine.TARGET_POINTS = 3
        for _ in range(2000):
            if engine.is_over():
                break
            moved = False
            for bot in roster:
                act = act_now(engine, bot)
                if act is not None:
                    engine.handle_action(bot.id, *act)
                    moved = True
            if not moved:
                expire(engine)
        assert engine.is_over()
        assert engine.results()
