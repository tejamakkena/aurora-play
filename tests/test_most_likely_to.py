"""Most Likely To engine: secret-ballot voting, scoring, and privacy.

The ballot is the whole game here: during the vote phase public_state must
reveal only how many votes are in, never who voted for whom. The per-target
tally appears only at reveal.
"""

import json
import random
import time

import pytest

from games.native_hub.engines import _content as C
from games.native_hub.engines.party import MostLikelyToEngine
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(players=4, seed=7):
    """Start a Most Likely To game with a null broadcaster."""
    random.seed(seed)
    registry = RoomRegistry()
    room = registry.create("most_likely_to")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    engine = MostLikelyToEngine(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def _ids(roster):
    return [p.id for p in roster]


def _vote_all(engine, roster, targets):
    """targets: voter index -> target index."""
    for voter_i, target_i in targets.items():
        engine.handle_action(roster[voter_i].id, "vote",
                             {"targetID": roster[target_i].id})


def _force_advance(engine):
    """Push past the current phase deadline the way the room pump would."""
    engine.deadline = time.time() - 1
    engine.tick(0)


class TestRegistration:
    def test_registered_in_registry(self):
        assert ENGINES["most_likely_to"] is MostLikelyToEngine
        assert MostLikelyToEngine.game_id == "most_likely_to"

    def test_player_bounds(self):
        assert MostLikelyToEngine.min_players == 3
        assert MostLikelyToEngine.max_players == 20


class TestStart:
    def test_starts_in_vote_phase_with_prompt(self):
        engine, roster = make()
        assert engine.phase == "vote"
        assert engine.prompt
        assert engine.prompt in C.MOST_LIKELY_PROMPTS

    def test_content_pool_has_enough_clean_prompts(self):
        assert len(C.MOST_LIKELY_PROMPTS) >= 24
        for prompt in C.MOST_LIKELY_PROMPTS:
            assert isinstance(prompt, str) and prompt.strip()
            assert "Most likely to" in prompt

    def test_prompts_do_not_repeat_within_a_game(self):
        engine, roster = make()
        seen = {engine.prompt}
        for _ in range(engine.total_rounds - 1):
            _vote_all(engine, roster, {i: (i + 1) % len(roster) for i in range(len(roster))})
            _force_advance(engine)   # vote -> reveal
            _force_advance(engine)   # reveal -> next round
            seen.add(engine.prompt)
        assert len(seen) == engine.total_rounds


class TestVoting:
    def test_accepts_valid_votes(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1, 1: 2, 2: 3, 3: 1})
        assert engine.public_state()["votesSoFar"] == 4
        assert engine.private_state("p0")["hasVoted"] is True
        assert engine.private_state("p2")["hasVoted"] is True

    def test_rejects_self_vote(self):
        engine, roster = make()
        engine.handle_action("p0", "vote", {"targetID": "p0"})
        assert engine.public_state()["votesSoFar"] == 0
        assert engine.private_state("p0")["hasVoted"] is False

    def test_rejects_unknown_target(self):
        engine, roster = make()
        engine.handle_action("p0", "vote", {"targetID": "ghost"})
        engine.handle_action("p0", "vote", {"targetID": None})
        engine.handle_action("p0", "vote", {})
        assert engine.public_state()["votesSoFar"] == 0

    def test_rejects_unknown_voter(self):
        engine, roster = make()
        engine.handle_action("ghost", "vote", {"targetID": "p1"})
        assert engine.public_state()["votesSoFar"] == 0

    def test_revote_changes_target(self):
        engine, roster = make()
        engine.handle_action("p0", "vote", {"targetID": "p1"})
        engine.handle_action("p0", "vote", {"targetID": "p2"})
        assert engine.public_state()["votesSoFar"] == 1
        assert engine.private_state("p0")["myVoteTargetID"] == "p2"

    def test_votes_ignored_outside_vote_phase(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1})
        _force_advance(engine)   # vote -> reveal
        assert engine.phase == "reveal"
        engine.handle_action("p1", "vote", {"targetID": "p2"})
        assert engine.public_state()["votesSoFar"] == 1

    def test_player_leaving_drops_their_vote(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1, 1: 2})
        assert engine.public_state()["votesSoFar"] == 2
        engine.on_player_leave("p0")
        assert engine.public_state()["votesSoFar"] == 1


class TestSecrecy:
    def test_ballot_stays_secret_during_vote(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1, 1: 2})
        public = engine.public_state()
        assert public["votesSoFar"] == 2
        assert public["roundResults"] == []
        dumped = json.dumps(public)
        assert "myVoteTargetID" not in dumped
        # No voter-to-target pairing is derivable: the tally must be absent.
        assert '"votes":' not in dumped

    def test_private_state_reveals_only_own_vote(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1, 1: 2})
        mine = engine.private_state("p0")
        assert mine["myVoteTargetID"] == "p1"
        assert mine["prompt"] == engine.prompt
        other = engine.private_state("p2")
        assert other["hasVoted"] is False
        assert other["myVoteTargetID"] is None
        # Roster (id/name/score) is visible; no vote mapping may leak.
        assert "votes" not in other
        assert other["players"] == [
            {"id": pid, "name": f"P{pid[1]}", "score": 0, "isHost": pid == "p0"}
            for pid in ("p0", "p1", "p2", "p3")
        ]

    def test_reveal_publishes_per_target_counts(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1, 1: 2, 2: 1, 3: 1})
        _force_advance(engine)   # vote -> reveal
        results = engine.public_state()["roundResults"]
        assert results
        by_id = {r["playerID"]: r for r in results}
        assert by_id["p1"]["votes"] == 3
        assert by_id["p1"]["topVoted"] is True
        assert by_id["p2"]["votes"] == 1
        assert by_id["p2"]["topVoted"] is False
        # Unvoted players do not appear in the tally.
        assert "p0" not in by_id and "p3" not in by_id


class TestScoring:
    def _to_reveal(self, engine, roster, targets):
        _vote_all(engine, roster, targets)
        _force_advance(engine)
        assert engine.phase == "reveal"

    def test_points_per_vote_plus_top_bonus(self):
        engine, roster = make()
        # p1 gets 3 votes, p2 gets 1.
        self._to_reveal(engine, roster, {0: 1, 1: 2, 2: 1, 3: 1})
        assert engine.scores["p1"] == 3 * 100 + 250
        assert engine.scores["p2"] == 1 * 100
        assert engine.scores["p0"] == 0
        assert engine.scores["p3"] == 0

    def test_tied_top_voters_both_get_bonus(self):
        engine, roster = make()
        # p1 and p2 each get 2 votes.
        self._to_reveal(engine, roster, {0: 1, 1: 2, 2: 1, 3: 2})
        assert engine.scores["p1"] == 2 * 100 + 250
        assert engine.scores["p2"] == 2 * 100 + 250

    def test_no_votes_means_no_points(self):
        engine, roster = make()
        _force_advance(engine)   # vote -> reveal with zero votes
        assert engine.public_state()["roundResults"] == []
        assert all(s == 0 for s in engine.scores.values())

    def test_scores_accumulate_across_rounds(self):
        engine, roster = make()
        self._to_reveal(engine, roster, {0: 1, 1: 2, 2: 1, 3: 1})
        first = engine.scores["p1"]
        assert first == 3 * 100 + 250
        _force_advance(engine)   # reveal -> round 2 vote
        assert engine.phase == "vote"
        assert engine.public_state()["votesSoFar"] == 0
        self._to_reveal(engine, roster, {0: 2, 1: 2, 2: 3, 3: 2})
        # p2 carried 100 from round 1, then 3 votes + top bonus in round 2.
        assert engine.scores["p2"] == 100 + 3 * 100 + 250
        assert engine.scores["p1"] == first   # untouched this round


class TestFullGame:
    def test_plays_to_completion_and_ranks_by_score(self):
        engine, roster = make(players=5)
        for _ in range(engine.total_rounds):
            assert engine.phase == "vote"
            _vote_all(engine, roster,
                      {i: (i + 1) % len(roster) for i in range(len(roster))})
            _force_advance(engine)   # vote -> reveal
            assert engine.phase == "reveal"
            _force_advance(engine)   # reveal -> next round or final
        assert engine.is_over()
        assert engine.phase == "final"
        results = engine.results()
        assert len(results) == len(roster)
        for row in results:
            assert {"playerID", "name", "score", "rank"} <= set(row)
        scores = [r["score"] for r in results]
        assert scores == sorted(scores, reverse=True)
        assert [r["rank"] for r in results] == list(range(1, len(roster) + 1))

    def test_state_stays_json_serialisable(self):
        engine, roster = make()
        _vote_all(engine, roster, {0: 1, 1: 2})
        json.dumps(engine.public_state())
        for player in roster:
            json.dumps(engine.private_state(player.id))
        _force_advance(engine)
        json.dumps(engine.public_state())

    def test_ignores_junk_actions(self):
        engine, roster = make()
        for verb in ("not_a_verb", "tap", "move"):
            engine.handle_action(roster[0].id, verb, {"garbage": object()})
            engine.handle_action("ghost-player", verb, {})
        assert engine.public_state()["votesSoFar"] == 0
