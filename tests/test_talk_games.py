"""Talk games (engines/talk.py): Hot Takes and 20 Questions.

Covers the full round flow of each game, scoring (landslides, ties,
questions-remaining scaling, the Answerer's good-game bonus, wrong-guess
penalties), privacy (the 20 Questions secret never reaches public_state
before the reveal), rotation, the timer contract, departures, bots, and
the registry / rules / catalog wiring.
"""

import json
import random
import time

import pytest

from games import content_service, game_night
from games.native_hub import bots
from games.native_hub.engines import talk, travel
from games.native_hub.engines.talk import (
    ARGUMENT_STARTERS,
    HOT_TAKES,
    HOT_TAKES_LANDSLIDE_BONUS,
    HOT_TAKES_POINTS_PER_VOTE,
    HOT_TAKES_SIDE_SECONDS,
    HOT_TAKES_TIE_POINTS,
    HOT_TAKES_WIN_POINTS,
    TWENTY_ANSWERER_BONUS,
    TWENTY_CATEGORY_LABELS,
    TWENTY_GUESS_BASE_POINTS,
    TWENTY_MAX_QUESTIONS,
    TWENTY_POINTS_PER_REMAINING,
    TWENTY_THINGS,
    TWENTY_WRONG_GUESS_PENALTY,
    HotTakesEngine,
    TwentyQuestionsEngine,
    is_either_or,
    side_labels,
    twenty_guess_matches,
)
from games.native_hub.registry import ENGINES, engine_for
from games.native_hub.rules import RULES, rules_for
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(game_id, players=4, seed=7, bots_count=0):
    random.seed(seed)
    cls = ENGINES[game_id]
    registry = RoomRegistry()
    room = registry.create(game_id)
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    roster += [room.add_bot() for _ in range(bots_count)]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(list(room.players))
    return engine, roster


def expire(engine):
    """Run the phase clock out and tick once."""
    engine.deadline = time.time() - 1
    engine.tick(1.0)


# ---------------------------------------------------------------------------
# wiring
# ---------------------------------------------------------------------------

class TestWiring:
    def test_registered(self):
        assert engine_for("hot_takes") is HotTakesEngine
        assert engine_for("twenty_questions") is TwentyQuestionsEngine

    def test_old_travel_import_path_still_works(self):
        assert travel.HotTakesEngine is HotTakesEngine
        assert travel.TwentyQuestionsEngine is TwentyQuestionsEngine
        assert travel.HOT_TAKES is HOT_TAKES
        assert travel.TWENTY_THINGS is TWENTY_THINGS
        assert "hot_takes" not in travel.ENGINES
        assert "twenty_questions" not in travel.ENGINES

    def test_player_limits(self):
        assert (HotTakesEngine.min_players, HotTakesEngine.max_players) == (3, 8)
        assert (TwentyQuestionsEngine.min_players, TwentyQuestionsEngine.max_players) == (3, 8)

    @pytest.mark.parametrize("gid", ["hot_takes", "twenty_questions"])
    def test_contract_and_json(self, gid):
        engine, roster = make(gid)
        assert engine.game_id == gid
        assert not engine.is_over()
        pub = engine.public_state()
        json.dumps(pub)
        for key in ("phase", "deadline", "secondsLeft", "phaseSeconds",
                    "round", "totalRounds", "players", "hostPrompt"):
            assert key in pub, key
        assert pub["phaseSeconds"] > 0
        assert 0 < pub["secondsLeft"] <= pub["phaseSeconds"]
        assert pub["deadline"] > time.time()
        for p in roster:
            priv = engine.private_state(p.id)
            json.dumps(priv)
            for key in ("phase", "deadline", "secondsLeft", "phaseSeconds", "score"):
                assert key in priv, key

    @pytest.mark.parametrize("gid", ["hot_takes", "twenty_questions"])
    def test_rules_entries(self, gid):
        payload = rules_for(gid)
        assert payload["title"] in ("Hot Takes", "20 Questions")
        assert 3 <= len(RULES[gid]["rules"]) <= 6

    def test_catalog_entries(self):
        assert game_night.CATALOG["hot_takes"] == {
            "minutes": 10, "kids": False, "tags": ["social", "debate"]}
        assert game_night.CATALOG["twenty_questions"] == {
            "minutes": 10, "kids": True, "tags": ["brain", "words"]}

    def test_picker_offers_them_to_a_group(self):
        ids = {g["id"] for g in game_night.pick_games(4)}
        assert {"hot_takes", "twenty_questions"} <= ids
        kids = {g["id"] for g in game_night.pick_games(4, kids=True)}
        assert "twenty_questions" in kids
        assert "hot_takes" not in kids
        assert "hot_takes" not in {g["id"] for g in game_night.pick_games(2)}

    def test_bot_policies_registered(self):
        assert "hot_takes" in bots.POLICIES
        assert "twenty_questions" in bots.POLICIES

    def test_content_kind_reads_talk_prompts(self):
        items = content_service.all_items("hot_take")
        for prompt in HOT_TAKES:
            assert prompt in items


# ---------------------------------------------------------------------------
# Hot Takes
# ---------------------------------------------------------------------------

def run_to(engine, phase):
    for _ in range(12):
        if engine.phase == phase:
            return
        engine.advance()
    raise AssertionError(f"never reached {phase}, stuck at {engine.phase}")


class TestHotTakesContent:
    def test_prompts_are_tts_clean(self):
        assert len(HOT_TAKES) >= 20
        for prompt in HOT_TAKES:
            assert prompt == prompt.strip() and prompt.endswith("?")
            for bad in ("w/", "*", "_", "#", "http"):
                assert bad not in prompt

    def test_side_labels(self):
        assert side_labels("Is cereal a soup?") == ("YES", "NO")
        assert is_either_or("Are cats or dogs better pets?")
        assert not is_either_or("Is a hot dog a sandwich?")
        assert side_labels("Are cats or dogs better pets?") == ("FIRST OPTION", "SECOND OPTION")

    def test_argument_starters(self):
        for side in ("for", "against"):
            assert len(ARGUMENT_STARTERS[side]) >= 6
            assert all(s.strip() for s in ARGUMENT_STARTERS[side])


class TestHotTakesRounds:
    @pytest.mark.parametrize("players,rounds", [(3, 3), (4, 4), (6, 6), (8, 8)])
    def test_rounds_equal_players_clamped(self, players, rounds):
        engine, _ = make("hot_takes", players=players)
        assert engine.total_rounds == rounds
        assert engine.public_state()["totalRounds"] == rounds

    def test_intro_picks_a_prompt_and_two_debaters(self):
        engine, roster = make("hot_takes")
        pub = engine.public_state()
        assert engine.phase == "intro"
        assert pub["prompt"] in content_service.all_items("hot_take")
        assert pub["forID"] and pub["againstID"] and pub["forID"] != pub["againstID"]
        assert pub["forName"] and pub["againstName"]
        assert pub["forLabel"] and pub["againstLabel"]
        assert pub["debateSecondsLeft"] == 2 * HOT_TAKES_SIDE_SECONDS
        assert pub["roundResult"] is None

    def test_prefers_yes_no_prompts(self):
        engine, _ = make("hot_takes", players=8)
        for _ in range(8):
            assert not is_either_or(engine.prompt), engine.prompt
            run_to(engine, "reveal")
            engine.advance()
            if engine.is_over():
                break

    def test_phase_sequence_and_switch_beat(self):
        engine, _ = make("hot_takes")
        seen = [engine.phase]
        for _ in range(5):
            expire(engine)
            seen.append(engine.phase)
        assert seen == ["intro", "for", "switch", "against", "vote", "reveal"]

    def test_phase_seconds(self):
        engine, _ = make("hot_takes")
        expected = {"intro": 8, "for": 30, "switch": 3, "against": 30, "vote": 20, "reveal": 9}
        for phase in ("intro", "for", "switch", "against", "vote", "reveal"):
            run_to(engine, phase)
            assert engine.public_state()["phaseSeconds"] == expected[phase]

    def test_speaking_side_and_debate_clock(self):
        engine, _ = make("hot_takes")
        run_to(engine, "for")
        pub = engine.public_state()
        assert pub["speakingSide"] == "for"
        assert HOT_TAKES_SIDE_SECONDS < pub["debateSecondsLeft"] <= 2 * HOT_TAKES_SIDE_SECONDS
        assert engine.private_state(engine.for_id)["isSpeaking"] is True
        assert engine.private_state(engine.against_id)["isSpeaking"] is False
        run_to(engine, "switch")
        assert engine.public_state()["speakingSide"] is None
        assert engine.public_state()["debateSecondsLeft"] == HOT_TAKES_SIDE_SECONDS
        run_to(engine, "against")
        pub = engine.public_state()
        assert pub["speakingSide"] == "against"
        assert 0 < pub["debateSecondsLeft"] <= HOT_TAKES_SIDE_SECONDS
        assert engine.private_state(engine.against_id)["isSpeaking"] is True

    def test_private_roles_and_hints(self):
        engine, roster = make("hot_takes")
        f, a = engine.for_id, engine.against_id
        pf, pa = engine.private_state(f), engine.private_state(a)
        assert pf["role"] == "for" and pf["stance"] == pf["forLabel"]
        assert pa["role"] == "against" and pa["stance"] == pa["againstLabel"]
        assert len(pf["hints"]) == 3 and set(pf["hints"]) <= set(ARGUMENT_STARTERS["for"])
        assert len(pa["hints"]) == 3 and set(pa["hints"]) <= set(ARGUMENT_STARTERS["against"])
        others = [p.id for p in roster if p.id not in (f, a)]
        for pid in others:
            priv = engine.private_state(pid)
            assert priv["role"] == "voter"
            assert priv["hints"] == []
            assert priv["canVote"] is False   # not until the vote phase
        run_to(engine, "vote")
        assert all(engine.private_state(pid)["canVote"] for pid in others)
        assert not engine.private_state(f)["canVote"]

    def test_done_speaking_ends_a_side_early(self):
        engine, _ = make("hot_takes")
        run_to(engine, "for")
        engine.handle_action(engine.against_id, "done_speaking", {})
        assert engine.phase == "for"          # not their turn
        engine.handle_action(engine.for_id, "done_speaking", {})
        assert engine.phase == "switch"
        engine.handle_action(engine.for_id, "done_speaking", {})
        assert engine.phase == "switch"       # nothing to end during the beat
        run_to(engine, "against")
        engine.handle_action(engine.against_id, "done_speaking", {})
        assert engine.phase == "vote"

    def test_debaters_cannot_vote_and_votes_only_in_vote_phase(self):
        engine, roster = make("hot_takes")
        voter = next(p.id for p in roster if p.id not in (engine.for_id, engine.against_id))
        engine.handle_action(voter, "vote", {"side": "for"})
        assert engine.votes == {}
        run_to(engine, "vote")
        engine.handle_action(engine.for_id, "vote", {"side": "for"})
        engine.handle_action(engine.against_id, "vote", {"side": "for"})
        engine.handle_action("nobody", "vote", {"side": "for"})
        engine.handle_action(voter, "vote", {"side": "sideways"})
        assert engine.votes == {}
        engine.handle_action(voter, "vote", {"targetID": engine.against_id})
        assert engine.votes == {voter: "against"}
        engine.handle_action(voter, "vote", {"side": "for"})   # can change their mind
        assert engine.votes == {voter: "for"}
        assert engine.private_state(voter)["myVote"] == "for"
        assert engine.private_state(voter)["hasVoted"] is True

    def test_votes_stay_secret_until_reveal(self):
        engine, roster = make("hot_takes", players=5)
        run_to(engine, "vote")
        voter = engine.voters()[0]
        engine.handle_action(voter, "vote", {"side": "against"})
        pub = engine.public_state()
        assert pub["votesSoFar"] == 1
        assert pub["voterCount"] == 3
        assert pub["roundResult"] is None
        assert "against" not in json.dumps(pub).replace("againstID", "").replace(
            "againstName", "").replace("againstLabel", "").replace('"speakingSide"', "")

    def test_vote_ends_early_once_everyone_voted(self):
        engine, _ = make("hot_takes", players=5)
        run_to(engine, "vote")
        for vid in engine.voters():
            engine.handle_action(vid, "vote", {"side": "for"})
        engine.tick(1.0)
        assert engine.phase == "reveal"

    def _vote_round(self, engine, sides):
        run_to(engine, "vote")
        voters = engine.voters()
        assert len(voters) == len(sides)
        for vid, side in zip(voters, sides):
            engine.handle_action(vid, "vote", {"side": side})
        engine.advance()
        assert engine.phase == "reveal"
        return engine.public_state()["roundResult"]

    def test_landslide_win(self):
        engine, _ = make("hot_takes", players=6)   # four voters
        f, a = engine.for_id, engine.against_id
        result = self._vote_round(engine, ["for", "for", "for", "against"])
        assert result["winnerSide"] == "for" and result["winnerID"] == f
        assert result["landslide"] is True
        assert result["forVotes"] == 3 and result["againstVotes"] == 1
        assert engine.scores[f] == (HOT_TAKES_WIN_POINTS + HOT_TAKES_LANDSLIDE_BONUS
                                    + 3 * HOT_TAKES_POINTS_PER_VOTE)
        assert engine.scores[a] == HOT_TAKES_POINTS_PER_VOTE
        assert result["forPoints"] == engine.scores[f]
        assert len(result["voters"]) == 4

    def test_narrow_win_has_no_landslide_bonus(self):
        engine, _ = make("hot_takes", players=7)   # five voters
        a = engine.against_id
        result = self._vote_round(engine, ["against", "against", "against", "for", "for"])
        assert result["winnerSide"] == "against"
        assert result["landslide"] is False
        assert engine.scores[a] == HOT_TAKES_WIN_POINTS + 3 * HOT_TAKES_POINTS_PER_VOTE

    def test_single_vote_is_never_a_landslide(self):
        engine, _ = make("hot_takes", players=3)   # one voter
        result = self._vote_round(engine, ["for"])
        assert result["winnerSide"] == "for"
        assert result["landslide"] is False

    def test_tie_splits_points(self):
        engine, _ = make("hot_takes", players=4)   # two voters
        f, a = engine.for_id, engine.against_id
        result = self._vote_round(engine, ["for", "against"])
        assert result["tie"] is True and result["winnerID"] is None
        expected = HOT_TAKES_TIE_POINTS + HOT_TAKES_POINTS_PER_VOTE
        assert engine.scores[f] == expected and engine.scores[a] == expected

    def test_no_votes_scores_nothing(self):
        engine, _ = make("hot_takes")
        run_to(engine, "vote")
        expire(engine)
        assert engine.phase == "reveal"
        assert engine.public_state()["roundResult"]["totalVotes"] == 0
        assert sum(engine.scores.values()) == 0

    @pytest.mark.parametrize("players", [3, 4, 5, 6, 7, 8])
    def test_everyone_debates(self, players):
        engine, roster = make("hot_takes", players=players, seed=players)
        debated = set()
        pairs = []
        while not engine.is_over():
            assert engine.for_id != engine.against_id
            debated.update((engine.for_id, engine.against_id))
            pairs.append(frozenset((engine.for_id, engine.against_id)))
            run_to(engine, "reveal")
            engine.advance()
        assert debated == {p.id for p in roster}
        # Nobody debates more than once more than anyone else.
        counts = [sum(1 for pair in pairs if p.id in pair) for p in roster]
        assert max(counts) - min(counts) <= 1

    def test_sides_alternate_for_repeat_debaters(self):
        engine, roster = make("hot_takes", players=4)
        a, b, c, d = (p.id for p in roster)
        engine.debates = {a: 1, b: 1, c: 1, d: 1}
        engine.last_side = {a: "for", b: "against", c: "for", d: "against"}
        engine.order = [a, b, c, d]
        engine.faced = {}
        engine.round = 1
        for_id, against_id = engine._pick_debaters()
        assert {for_id, against_id} == {a, b}
        assert (for_id, against_id) == (b, a)     # both switch sides
        assert engine.last_side[a] == "against" and engine.last_side[b] == "for"

    def test_sides_are_balanced_over_a_game(self):
        engine, roster = make("hot_takes", players=4)
        fors = {p.id: 0 for p in roster}
        while not engine.is_over():
            fors[engine.for_id] += 1
            run_to(engine, "reveal")
            engine.advance()
        # Four rounds, four players, two debates each: one FOR and one AGAINST.
        assert set(fors.values()) == {1}

    def test_prompts_do_not_repeat(self):
        engine, _ = make("hot_takes", players=8)
        seen = []
        while not engine.is_over():
            seen.append(engine.prompt)
            run_to(engine, "reveal")
            engine.advance()
        assert len(seen) == 8 and len(set(seen)) == 8

    def test_full_game_results(self):
        engine, roster = make("hot_takes", players=4)
        while not engine.is_over():
            run_to(engine, "vote")
            for vid in engine.voters():
                engine.handle_action(vid, "vote", {"side": "for"})
            engine.advance()
            engine.advance()
        assert engine.phase == "final"
        results = engine.results()
        assert [r["rank"] for r in results] == [1, 2, 3, 4]
        assert results[0]["score"] >= results[-1]["score"]
        assert {r["playerID"] for r in results} == {p.id for p in roster}
        json.dumps(results)
        assert len(engine.history) == 4

    def test_debater_leaving_skips_their_turn(self):
        engine, roster = make("hot_takes")
        run_to(engine, "for")
        engine.room.player(engine.for_id).connected = False
        engine.on_player_leave(engine.for_id)
        engine.tick(1.0)
        assert engine.phase == "switch"

    def test_voter_leaving_drops_their_vote(self):
        engine, _ = make("hot_takes", players=5)
        run_to(engine, "vote")
        v = engine.voters()[0]
        engine.handle_action(v, "vote", {"side": "for"})
        engine.room.player(v).connected = False
        engine.on_player_leave(v)
        assert v not in engine.votes
        assert v not in engine.voters()

    def test_left_players_are_not_drawn_to_debate(self):
        engine, roster = make("hot_takes", players=5)
        gone = roster[4]
        gone.connected = False
        engine.on_player_leave(gone.id)
        while not engine.is_over():
            assert gone.id not in (engine.for_id, engine.against_id)
            run_to(engine, "reveal")
            engine.advance()

    def test_host_prompt_is_tts_clean(self):
        engine, _ = make("hot_takes")
        for phase in ("intro", "for", "switch", "against", "vote", "reveal"):
            run_to(engine, phase)
            line = engine.public_state()["hostPrompt"]
            assert line and "*" not in line and "#" not in line

    def test_junk_actions_ignored(self):
        engine, _ = make("hot_takes")
        engine.handle_action("p0", "explode", {})
        engine.handle_action("p0", "vote", None)
        engine.handle_action("ghost", "done_speaking", {})
        assert engine.phase == "intro"


class TestHotTakesBots:
    def test_bot_voter_votes_a_side(self):
        engine, roster = make("hot_takes", players=3, bots_count=2)
        run_to(engine, "vote")
        bot_voters = [p.id for p in roster if p.is_bot and engine.is_voter(p.id)]
        for bid in bot_voters:
            act = bots._policy_hot_takes(engine, bid)
            assert act[0] == "vote" and act[1]["side"] in ("for", "against")

    def test_bot_debater_hands_the_floor_back(self):
        engine, roster = make("hot_takes", players=3, bots_count=1)
        run_to(engine, "for")
        assert bots._policy_hot_takes(engine, engine.for_id) == ("done_speaking", {})
        assert bots._policy_hot_takes(engine, engine.against_id) is None

    def test_bot_never_acts_outside_its_phases(self):
        engine, roster = make("hot_takes", players=3, bots_count=1)
        bot = roster[-1]
        assert bots._policy_hot_takes(engine, bot.id) is None   # intro


# ---------------------------------------------------------------------------
# 20 Questions
# ---------------------------------------------------------------------------

def to_ask(engine):
    run_to(engine, "ask")


def others(engine, roster):
    return [p.id for p in roster if p.id != engine.answerer_id]


class TestTwentyContent:
    def test_five_categories(self):
        assert set(TWENTY_THINGS) == set(TWENTY_CATEGORY_LABELS)
        assert set(TWENTY_CATEGORY_LABELS.values()) == {
            "Animal", "Food", "Place", "Movie", "Famous object"}
        for items in TWENTY_THINGS.values():
            assert len(items) >= 15
            assert all(i and len(i) < 40 for i in items)

    @pytest.mark.parametrize("guess,secret", [
        ("eiffel tower", "Eiffel Tower"),
        ("  EIFFEL TOWER!! ", "Eiffel Tower"),
        ("colosseum", "The Colosseum"),
        ("taco", "Tacos"),
        ("pancake", "Pancakes"),
        ("spiderman", "Spider-Man"),
        ("et", "E.T."),
        ("kangaroo", "Kangarooo"),
        ("crocodle", "Crocodile"),
    ])
    def test_guess_matching_is_forgiving(self, guess, secret):
        assert twenty_guess_matches(guess, secret)

    @pytest.mark.parametrize("guess,secret", [
        ("tiger", "Lion"), ("", "Lion"), ("horse", "House"), ("gwoc", "Great Wall of China"),
        ("mango", "Tango"),
    ])
    def test_guess_matching_rejects_wrong(self, guess, secret):
        assert not twenty_guess_matches(guess, secret)


class TestTwentyRounds:
    @pytest.mark.parametrize("players,rounds", [(3, 3), (4, 4), (6, 6), (8, 6)])
    def test_rounds_equal_players_clamped(self, players, rounds):
        engine, _ = make("twenty_questions", players=players)
        assert engine.total_rounds == rounds

    def test_secret_is_private_until_reveal(self):
        engine, roster = make("twenty_questions")
        for phase in ("intro", "ask"):
            run_to(engine, phase)
            pub = engine.public_state()
            assert "secret" not in pub
            assert engine.secret not in json.dumps(pub)
            assert engine.private_state(engine.answerer_id)["secret"] == engine.secret
            for pid in others(engine, roster):
                assert "secret" not in engine.private_state(pid)
        engine.advance()
        assert engine.phase == "reveal"
        assert engine.public_state()["secret"] == engine.secret
        assert engine.public_state()["roundResult"]["secret"] == engine.secret

    def test_category_is_public(self):
        engine, _ = make("twenty_questions")
        pub = engine.public_state()
        assert pub["category"] in TWENTY_CATEGORY_LABELS.values()
        assert engine.secret in TWENTY_THINGS[pub["categoryKey"]]
        assert pub["category"] in pub["hostPrompt"]

    def test_phases_and_seconds(self):
        engine, _ = make("twenty_questions")
        assert engine.phase == "intro"
        assert engine.public_state()["phaseSeconds"] == 8
        expire(engine)
        assert engine.phase == "ask"
        assert engine.public_state()["phaseSeconds"] == 300
        expire(engine)
        assert engine.phase == "reveal"
        assert engine.public_state()["roundResult"]["solved"] is False
        expire(engine)
        assert engine.phase == "intro" and engine.round == 2

    def test_only_answerer_answers_and_only_in_ask(self):
        engine, roster = make("twenty_questions")
        a = engine.answerer_id
        engine.handle_action(a, "answer", {"value": "yes"})
        assert engine.questions_used == 0          # intro
        to_ask(engine)
        engine.handle_action(others(engine, roster)[0], "answer", {"value": "yes"})
        engine.handle_action(a, "answer", {"value": "maybe"})
        assert engine.questions_used == 0
        for value in ("yes", "NO", "sometimes"):
            engine.handle_action(a, "answer", {"value": value})
        pub = engine.public_state()
        assert pub["questionsUsed"] == 3
        assert pub["questionsLeft"] == TWENTY_MAX_QUESTIONS - 3
        assert pub["tally"] == {"yes": 1, "no": 1, "sometimes": 1, "wrongGuesses": 0}
        assert [e["answer"] for e in pub["log"]] == ["yes", "no", "sometimes"]
        assert [e["n"] for e in pub["log"]] == [1, 2, 3]
        assert engine.private_state(a)["lastAnswer"] == "sometimes"

    def test_twenty_answers_end_the_round_unsolved(self):
        engine, _ = make("twenty_questions")
        to_ask(engine)
        for _ in range(TWENTY_MAX_QUESTIONS):
            engine.handle_action(engine.answerer_id, "answer", {"value": "no"})
        assert engine.phase == "reveal"
        result = engine.public_state()["roundResult"]
        assert result["solved"] is False and result["questionNumber"] == 20
        assert sum(engine.scores.values()) == 0
        engine.handle_action(engine.answerer_id, "answer", {"value": "no"})
        assert engine.questions_used == TWENTY_MAX_QUESTIONS

    def test_answerer_cannot_guess(self):
        engine, _ = make("twenty_questions")
        to_ask(engine)
        engine.handle_action(engine.answerer_id, "guess", {"text": engine.secret})
        assert engine.phase == "ask"

    def test_guess_rejected_outside_ask(self):
        engine, roster = make("twenty_questions")
        engine.handle_action(others(engine, roster)[0], "guess", {"text": engine.secret})
        assert engine.phase == "intro"

    def test_quick_correct_guess_scores_most(self):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        g = others(engine, roster)[0]
        engine.handle_action(g, "guess", {"text": engine.secret})
        assert engine.phase == "reveal"
        result = engine.public_state()["roundResult"]
        assert result["solved"] and result["solverID"] == g
        assert result["questionNumber"] == 1
        expected = TWENTY_GUESS_BASE_POINTS + TWENTY_POINTS_PER_REMAINING * (TWENTY_MAX_QUESTIONS - 1)
        assert engine.scores[g] == expected == result["solverPoints"]
        # Too easy for the Answerer's bonus.
        assert engine.scores[engine.answerer_id] == 0
        assert result["goodGame"] is False

    def test_points_scale_with_questions_remaining(self):
        e1, r1 = make("twenty_questions", seed=3)
        e2, r2 = make("twenty_questions", seed=3)
        for e in (e1, e2):
            to_ask(e)
        for _ in range(3):
            e1.handle_action(e1.answerer_id, "answer", {"value": "yes"})
        for _ in range(12):
            e2.handle_action(e2.answerer_id, "answer", {"value": "yes"})
        g1, g2 = others(e1, r1)[0], others(e2, r2)[0]
        e1.handle_action(g1, "guess", {"text": e1.secret})
        e2.handle_action(g2, "guess", {"text": e2.secret})
        assert e1.scores[g1] > e2.scores[g2]
        assert e2.scores[g2] == TWENTY_GUESS_BASE_POINTS + TWENTY_POINTS_PER_REMAINING * (20 - 13)

    @pytest.mark.parametrize("asked,bonus", [(8, False), (9, True), (15, True), (19, True)])
    def test_answerer_good_game_bonus(self, asked, bonus):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        for _ in range(asked):
            engine.handle_action(engine.answerer_id, "answer", {"value": "no"})
        engine.handle_action(others(engine, roster)[0], "guess", {"text": engine.secret})
        result = engine.public_state()["roundResult"]
        assert result["questionNumber"] == asked + 1
        assert result["goodGame"] is bonus
        assert engine.scores[engine.answerer_id] == (TWENTY_ANSWERER_BONUS if bonus else 0)

    def test_solved_on_the_twentieth_question(self):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        for _ in range(19):
            engine.handle_action(engine.answerer_id, "answer", {"value": "no"})
        g = others(engine, roster)[0]
        engine.handle_action(g, "guess", {"text": engine.secret})
        result = engine.public_state()["roundResult"]
        assert result["solved"] and result["questionNumber"] == 20
        assert engine.scores[g] == TWENTY_GUESS_BASE_POINTS
        assert result["goodGame"] is True

    def test_wrong_guess_costs_points_and_a_question(self):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        g = others(engine, roster)[0]
        engine.scores[g] = 120
        engine.handle_action(g, "buzz", {})
        assert engine.public_state()["typingNames"] == [engine.player_name(g)]
        engine.handle_action(g, "guess", {"text": "a flying toaster"})
        pub = engine.public_state()
        assert engine.phase == "ask"
        assert engine.scores[g] == 120 - TWENTY_WRONG_GUESS_PENALTY
        assert pub["questionsUsed"] == 1
        assert pub["tally"]["wrongGuesses"] == 1
        assert pub["log"][-1]["kind"] == "guess"
        assert pub["log"][-1]["text"] == "a flying toaster"
        assert pub["typingNames"] == []
        priv = engine.private_state(g)
        assert priv["wrongGuesses"] == 1 and priv["lastWrongGuess"] == "a flying toaster"

    def test_penalty_never_drops_below_zero(self):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        g = others(engine, roster)[0]
        engine.handle_action(g, "guess", {"text": "nope"})
        assert engine.scores[g] == 0

    def test_wrong_guess_on_the_last_question_ends_the_round(self):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        for _ in range(19):
            engine.handle_action(engine.answerer_id, "answer", {"value": "yes"})
        engine.handle_action(others(engine, roster)[0], "guess", {"text": "nope"})
        assert engine.phase == "reveal"
        assert engine.public_state()["roundResult"]["solved"] is False

    def test_buzz_cancel(self):
        engine, roster = make("twenty_questions")
        to_ask(engine)
        g = others(engine, roster)[0]
        engine.handle_action(g, "buzz", {})
        assert engine.private_state(g)["isTyping"]
        engine.handle_action(g, "cancel_buzz", {})
        assert not engine.private_state(g)["isTyping"]
        engine.handle_action(engine.answerer_id, "buzz", {})
        assert engine.public_state()["typingIDs"] == []

    def test_can_guess_flags(self):
        engine, roster = make("twenty_questions")
        g = others(engine, roster)[0]
        assert not engine.private_state(g)["canGuess"]
        to_ask(engine)
        assert engine.private_state(g)["canGuess"]
        assert not engine.private_state(engine.answerer_id)["canGuess"]
        assert engine.private_state(engine.answerer_id)["isAnswerer"]

    def test_answerer_rotates_through_everyone(self):
        engine, roster = make("twenty_questions", players=5)
        answerers = []
        while not engine.is_over():
            answerers.append(engine.answerer_id)
            run_to(engine, "reveal")
            engine.advance()
        assert sorted(answerers) == sorted(p.id for p in roster)

    def test_secrets_and_categories_vary(self):
        engine, _ = make("twenty_questions", players=6)
        seen, cats = [], []
        while not engine.is_over():
            seen.append(engine.secret)
            cats.append(engine.category)
            run_to(engine, "reveal")
            engine.advance()
        assert len(set(seen)) == 6
        assert all(a != b for a, b in zip(cats, cats[1:]))

    def test_answerer_leaving_reveals(self):
        engine, _ = make("twenty_questions")
        to_ask(engine)
        a = engine.answerer_id
        engine.room.player(a).connected = False
        engine.on_player_leave(a)
        engine.tick(1.0)
        assert engine.phase == "reveal"
        assert engine.public_state()["secret"] == engine.secret

    def test_full_game_results(self):
        engine, roster = make("twenty_questions", players=4)
        while not engine.is_over():
            to_ask(engine)
            for _ in range(10):
                engine.handle_action(engine.answerer_id, "answer", {"value": "yes"})
            engine.handle_action(others(engine, roster)[0], "guess", {"text": engine.secret})
            engine.advance()
        assert engine.phase == "final"
        results = engine.results()
        assert {r["playerID"] for r in results} == {p.id for p in roster}
        assert results[0]["score"] > 0
        json.dumps(results)

    def test_host_prompt_names_the_category_and_reveal(self):
        engine, _ = make("twenty_questions")
        assert engine.category_label() in engine.public_state()["hostPrompt"]
        run_to(engine, "reveal")
        assert engine.secret in engine.public_state()["hostPrompt"]


class TestTwentyBots:
    def _bot_answerer_engine(self):
        for seed in range(40):
            engine, roster = make("twenty_questions", players=3, bots_count=1, seed=seed)
            if engine.room.player(engine.answerer_id).is_bot:
                return engine, roster
        raise AssertionError("no seed gave the bot the first round")

    def test_bot_answerer_answers_yes_or_no_after_a_pause(self):
        engine, _ = self._bot_answerer_engine()
        to_ask(engine)
        bot_id = engine.answerer_id
        assert engine.bot_step.endswith("wait")
        assert bots._policy_twenty_questions(engine, bot_id) is None
        engine.last_event_at = time.time() - 10
        assert not engine.bot_step.endswith("wait")
        act = bots._policy_twenty_questions(engine, bot_id)
        assert act[0] == "answer" and act[1]["value"] in ("yes", "no")

    def test_bot_answerer_acts_once_per_question_through_the_pump(self):
        engine, roster = self._bot_answerer_engine()
        to_ask(engine)
        bot = engine.room.player(engine.answerer_id)
        engine.last_event_at = time.time() - 10
        assert bots.maybe_bot_action(engine, bot) is None    # schedules
        bot.bot_act_at = 0
        verb, payload = bots.maybe_bot_action(engine, bot)
        engine.handle_action(bot.id, verb, payload)
        assert engine.questions_used == 1
        # A new question is a new decision point (after the pause).
        engine.last_event_at = time.time() - 10
        assert bots.maybe_bot_action(engine, bot) is None    # schedules again
        bot.bot_act_at = 0
        assert bots.maybe_bot_action(engine, bot) is not None

    def test_bots_never_guess(self):
        engine, roster = make("twenty_questions", players=3, bots_count=2)
        to_ask(engine)
        engine.last_event_at = time.time() - 10
        for p in roster:
            if p.is_bot and p.id != engine.answerer_id:
                assert bots._policy_twenty_questions(engine, p.id) is None


class TestHotTakesTopic:
    def test_topic_prompt_comes_first(self, monkeypatch):
        import games.topic_gen as tg
        monkeypatch.setattr(tg, "get_hot_takes",
                            lambda topic, n, session_history=(): ["Is cricket better than football?"])
        engine, _ = make("hot_takes")
        engine.room.topic = "cricket"
        engine.begin_phase("intro")
        assert engine.prompt == "Is cricket better than football?"

    def test_either_or_topic_prompt_falls_back(self, monkeypatch):
        import games.topic_gen as tg
        monkeypatch.setattr(tg, "get_hot_takes",
                            lambda topic, n, session_history=(): ["Tea or coffee?"])
        engine, _ = make("hot_takes")
        engine.room.topic = "drinks"
        engine.begin_phase("intro")
        assert engine.prompt != "Tea or coffee?"
        assert engine.prompt in content_service.all_items("hot_take")

    def test_topic_failure_falls_back(self, monkeypatch):
        import games.topic_gen as tg

        def boom(*args, **kwargs):
            raise RuntimeError("offline")
        monkeypatch.setattr(tg, "get_hot_takes", boom)
        engine, _ = make("hot_takes")
        engine.room.topic = "anything"
        engine.begin_phase("intro")
        assert engine.prompt in content_service.all_items("hot_take")
