"""Big-party engines (8-20+ players).

Everyone acts at the same time inside a deadline -- nobody waits for a turn,
which is what keeps these playable with twenty people in a room.
"""

import random
import time

from games import content_service as cs
from games.native_hub.engines import _content as C
from games.native_hub.engines._matching import guess_matches
from games.native_hub.engines._bases import RoundBasedEngine
from games.native_hub.engine import NativeGameEngine
from utils.room_manager import Player


def _norm(text) -> str:
    """Loose normalisation so 'Idli ' and 'idli' count as the same answer."""
    return " ".join(str(text).strip().lower().split()) if text else ""


def _within_one_edit(a: str, b: str) -> bool:
    if a == b:
        return True
    if len(a) > len(b):
        a, b = b, a
    i = j = edits = 0
    while i < len(a) and j < len(b):
        if a[i] != b[j]:
            edits += 1
            if edits > 1:
                return False
            if len(a) == len(b):
                i += 1
            j += 1
        else:
            i += 1
            j += 1
    return edits + (len(b) - j) <= 1


class BluffItEngine(RoundBasedEngine):
    """Write a convincing fake answer, then spot the real one.

    Scoring rewards both halves: points for every player your lie catches, and
    points for finding the truth yourself.
    """

    game_id = "bluff_it"
    min_players = 3
    max_players = 16
    total_rounds = 5
    first_phase = "write"
    phase_seconds = {"write": 45, "pick": 30, "reveal": 8}
    early_phases = ("pick",)         # reveal as soon as everyone has picked

    POINTS_FOR_TRUTH = 1000
    POINTS_PER_FOOL = 500

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.prompt = ""
        self.truth = ""
        self.options: list[dict] = []      # [{text, ownerID}] shuffled, truth ownerID=None
        self.picks: dict[str, int] = {}    # player -> option index
        self.used: set[str] = set()       # content keys picked this game
        self.round_log: list[dict] = []

    def begin_phase(self, phase):
        if phase == "write":
            # Fresh for this table across games and nights (content_service).
            fact = cs.pick_one(self.room, "bluff", avoid=self.used)
            self.used.add(cs.KINDS["bluff"].key(fact))
            self.prompt, self.truth = fact
            self.options = []
            self.picks = {}
            self.round_log = []
        elif phase == "pick":
            self._build_options()
            self.submissions = {}

    def _build_options(self):
        """Mix the lies with the truth, dropping duplicates and accidental hits."""
        seen = {_norm(self.truth)}
        opts = []
        for pid, lie in self.submissions.items():
            key = _norm(lie)
            if not key or key in seen:
                # An empty or duplicate lie would be unpickable; skip it.
                continue
            seen.add(key)
            opts.append({"text": str(lie)[:60], "ownerID": pid})
        opts.append({"text": self.truth, "ownerID": None})
        random.shuffle(opts)
        self.options = opts

    def handle_action(self, player_id, action, data):
        if action == "submit_lie" and self.phase == "write":
            text = str(data.get("text", ""))[:60].strip()
            if text and _norm(text) != _norm(self.truth):
                self.submissions[player_id] = text
        elif action == "pick" and self.phase == "pick":
            idx = data.get("index")
            if isinstance(idx, int) and 0 <= idx < len(self.options):
                if self.options[idx]["ownerID"] == player_id:
                    return           # can't pick your own lie
                self.picks[player_id] = idx
                self.submissions[player_id] = idx

    def resolve_phase(self, phase):
        if phase == "write":
            return "pick"
        if phase == "pick":
            self._score()
            return "reveal"
        return None

    def _score(self):
        for voter, idx in self.picks.items():
            if idx >= len(self.options):
                continue
            opt = self.options[idx]
            if opt["ownerID"] is None:
                self.award(voter, self.POINTS_FOR_TRUTH)
                self.round_log.append({"playerID": voter, "found": True})
            else:
                self.award(opt["ownerID"], self.POINTS_PER_FOOL)
                self.round_log.append({"playerID": voter, "found": False,
                                       "fooledBy": opt["ownerID"]})

    def public_state(self):
        state = self.base_public()
        state.update({
            "prompt": self.prompt,
            "options": [{"text": o["text"]} for o in self.options]
            if self.phase in ("pick", "reveal") else [],
            "truth": self.truth if self.phase == "reveal" else None,
            "truthIndex": next(
                (i for i, o in enumerate(self.options) if o["ownerID"] is None), None
            ) if self.phase == "reveal" else None,
            "optionOwners": [
                {"index": i, "ownerID": o["ownerID"],
                 "ownerName": self.player_name(o["ownerID"]) if o["ownerID"] else "TRUTH"}
                for i, o in enumerate(self.options)
            ] if self.phase == "reveal" else [],
            "roundLog": self.round_log if self.phase == "reveal" else [],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "prompt": self.prompt,
            "myLie": self.submissions.get(player_id) if self.phase == "write" else None,
            # The truth is never sent to a phone before the reveal.
            "options": [
                {"index": i, "text": o["text"],
                 "isMine": o["ownerID"] == player_id}
                for i, o in enumerate(self.options)
            ] if self.phase == "pick" else [],
            "myPick": self.picks.get(player_id),
        })
        return state


class LastTapEngine(NativeGameEngine):
    """Reflex elimination. Random countdown, then GO -- slowest players drop out.

    Not round-based in the submission sense: the whole game is one clock, so it
    manages its own phases rather than using RoundBasedEngine.
    """

    game_id = "last_tap"
    min_players = 2
    max_players = 20
    # GO has to reach the phones the moment it happens: at the 1 Hz baseline
    # pump it landed up to a second late and that lag was counted in
    # everyone's reaction time.
    tick_hz = 10.0

    ARM_MIN, ARM_MAX = 2.0, 6.0
    REVEAL_SECONDS = 5.0
    FALSE_START_PENALTY = 9.999

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.phase = "arming"
        self.go_at = 0.0
        self.go_shown_at = 0.0
        self.phase_until = 0.0
        self.alive: list[str] = []
        self.times: dict[str, float] = {}
        self.eliminated_this_round: list[str] = []
        self.round = 0
        self._finished = False

    def start(self, players):
        self.alive = [p.id for p in players]
        self.round = 1
        self._arm()

    def _arm(self):
        self.phase = "arming"
        self.times = {}
        self.eliminated_this_round = []
        self.go_at = time.time() + random.uniform(self.ARM_MIN, self.ARM_MAX)
        self.phase_until = 0.0

    def handle_action(self, player_id, action, data):
        if action != "tap" or player_id not in self.alive:
            return
        if player_id in self.times:
            return
        now = time.time()
        if self.phase == "arming":
            # Tapped before GO -- recorded as a false start, not ignored, so the
            # player still sees a result instead of silence.
            self.times[player_id] = self.FALSE_START_PENALTY
        elif self.phase == "go":
            self.times[player_id] = max(0.0, now - self.go_shown_at)

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        if self.phase == "arming" and now >= self.go_at:
            self.phase = "go"
            # Timed from when GO is actually published, not when it was due.
            self.go_shown_at = now
        elif self.phase == "go":
            everyone_in = all(pid in self.times for pid in self.alive)
            if everyone_in or now - self.go_at > 5.0:
                self._resolve()
        elif self.phase == "reveal" and now >= self.phase_until:
            if len(self.alive) <= 1:
                self._finished = True
                self.phase = "final"
            else:
                self.round += 1
                self._arm()

    def _resolve(self):
        # Anyone who never tapped is treated as slowest.
        for pid in self.alive:
            self.times.setdefault(pid, self.FALSE_START_PENALTY)

        ranked = sorted(self.alive, key=lambda p: self.times[p])
        # Drop the slowest 20%, but always at least one and never everyone.
        cut = max(1, round(len(ranked) * 0.2))
        cut = min(cut, len(ranked) - 1)
        survivors, dropped = ranked[:-cut], ranked[-cut:]

        for rank, pid in enumerate(survivors):
            player = self.room.player(pid)
            if player is not None:
                player.score += max(1, len(survivors) - rank)

        self.eliminated_this_round = dropped
        self.alive = survivors
        self.phase = "reveal"
        self.phase_until = time.time() + self.REVEAL_SECONDS

    def public_state(self):
        return {
            "phase": self.phase,
            "round": self.round,
            "aliveCount": len(self.alive),
            "alivePlayerIDs": self.alive,
            "eliminatedPlayerIDs": self.eliminated_this_round,
            "winner": self.alive[0] if self._finished and self.alive else None,
            "results": [
                {"playerID": pid, "name": self.player_name(pid),
                 "ms": int(self.times[pid] * 1000),
                 "falseStart": self.times[pid] >= self.FALSE_START_PENALTY}
                for pid in sorted(self.times, key=lambda p: self.times[p])
            ] if self.phase in ("reveal", "final") else [],
            "players": [
                {"id": p.id, "name": p.name, "score": p.score,
                 "isAlive": p.id in self.alive}
                for p in self.room.players
            ],
        }

    def private_state(self, player_id):
        return {
            "phase": self.phase,
            "isAlive": player_id in self.alive,
            "canTap": self.phase in ("arming", "go") and player_id in self.alive
                      and player_id not in self.times,
            "myMs": int(self.times[player_id] * 1000) if player_id in self.times else None,
            "falseStart": self.times.get(player_id, 0) >= self.FALSE_START_PENALTY,
            "round": self.round,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})

    def on_player_leave(self, player_id):
        if player_id in self.alive:
            self.alive.remove(player_id)


class HerdEngine(RoundBasedEngine):
    """Score by matching the majority. Thinking like the crowd beats being clever."""

    game_id = "herd"
    min_players = 3
    max_players = 20
    total_rounds = 6
    first_phase = "answer"
    phase_seconds = {"answer": 30, "reveal": 10}

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.prompt = ""
        self.used: set[str] = set()
        self.clusters: list[dict] = []

    def begin_phase(self, phase):
        if phase == "answer":
            self.prompt = cs.pick_one(self.room, "herd", avoid=self.used)
            self.used.add(cs.norm_key(self.prompt))
            self.clusters = []

    def handle_action(self, player_id, action, data):
        if action == "answer" and self.phase == "answer":
            text = str(data.get("text", ""))[:30].strip()
            if text:
                self.submissions[player_id] = text

    def resolve_phase(self, phase):
        if phase == "answer":
            self._cluster_and_score()
            return "reveal"
        return None

    @staticmethod
    def _same_answer(a, b):
        """'Idli', 'idly' and 'idlis' are one herd, not three."""
        na, nb = _norm(a).rstrip("s"), _norm(b).rstrip("s")
        if na == nb or guess_matches(a, b, threshold=0.8):
            return True
        # One-letter spelling variants of short words ("idly"/"idli").
        if min(len(na), len(nb)) >= 4 and abs(len(na) - len(nb)) <= 1:
            return _within_one_edit(na, nb)
        return False

    def _cluster_and_score(self):
        groups: dict[str, list[str]] = {}
        labels: dict[str, str] = {}
        for pid, text in self.submissions.items():
            key = next((k for k in groups if self._same_answer(text, labels[k])), _norm(text))
            groups.setdefault(key, []).append(pid)
            labels.setdefault(key, str(text))

        self.clusters = sorted(
            ({"text": labels[k], "playerIDs": v, "size": len(v)}
             for k, v in groups.items()),
            key=lambda c: c["size"], reverse=True,
        )
        if not self.clusters:
            return
        top = self.clusters[0]["size"]
        for cluster in self.clusters:
            if cluster["size"] < 2:
                continue            # nobody matched you: you're not in a herd
            # Everyone in a matching group scores; the biggest herd scores most.
            points = 100 * cluster["size"] + (50 if cluster["size"] == top else 0)
            for pid in cluster["playerIDs"]:
                self.award(pid, points)

    def public_state(self):
        state = self.base_public()
        state.update({
            "prompt": self.prompt,
            "clusters": [
                {"text": c["text"], "size": c["size"],
                 "names": [self.player_name(p) for p in c["playerIDs"]]}
                for c in self.clusters
            ] if self.phase == "reveal" else [],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "prompt": self.prompt,
            "myAnswer": self.submissions.get(player_id),
        })
        return state


class EmojiMovieEngine(RoundBasedEngine):
    """Describe a secret title in emoji; everyone else guesses which is which."""

    game_id = "emoji_movie"
    min_players = 3
    max_players = 16
    total_rounds = 4
    first_phase = "compose"
    phase_seconds = {"compose": 60, "guess": 45, "reveal": 10}

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.assignments: dict[str, str] = {}   # player -> secret title
        self.entries: list[dict] = []           # [{ownerID, emoji, title}]
        self.guesses: dict[str, dict[int, str]] = {}
        self.used: set[str] = set()

    def begin_phase(self, phase):
        if phase == "compose":
            picks = cs.pick(self.room, "emoji_movie", len(self.active_players()),
                            avoid=self.used)
            self.assignments = {}
            for player, title in zip(self.active_players(), picks):
                self.assignments[player.id] = title
                self.used.add(cs.norm_key(title))
            self.entries = []
            self.guesses = {}
        elif phase == "guess":
            self.entries = [
                {"ownerID": pid, "emoji": em, "title": self.assignments.get(pid, "")}
                for pid, em in self.submissions.items()
            ]
            random.shuffle(self.entries)
            self.submissions = {}

    def handle_action(self, player_id, action, data):
        if action == "submit_emoji" and self.phase == "compose":
            emoji = str(data.get("emoji", ""))[:20].strip()
            if emoji:
                self.submissions[player_id] = emoji
        elif action == "guess" and self.phase == "guess":
            idx, text = data.get("index"), str(data.get("text", ""))[:40].strip()
            if isinstance(idx, int) and 0 <= idx < len(self.entries) and text:
                if self.entries[idx]["ownerID"] == player_id:
                    return
                self.guesses.setdefault(player_id, {})[idx] = text
                self.submissions[player_id] = self.guesses[player_id]

    def resolve_phase(self, phase):
        if phase == "compose":
            return "guess"
        if phase == "guess":
            self._score()
            return "reveal"
        return None

    def _score(self):
        for guesser, per_entry in self.guesses.items():
            for idx, text in per_entry.items():
                if idx >= len(self.entries):
                    continue
                entry = self.entries[idx]
                if guess_matches(text, entry["title"]):
                    self.award(guesser, 300)
                    self.award(entry["ownerID"], 200)   # your clue worked

    def public_state(self):
        state = self.base_public()
        state.update({
            "entries": [
                {"index": i, "emoji": e["emoji"],
                 "ownerName": self.player_name(e["ownerID"]),
                 "title": e["title"] if self.phase == "reveal" else None}
                for i, e in enumerate(self.entries)
            ] if self.phase in ("guess", "reveal") else [],
            "composedCount": len(self.submissions) if self.phase == "compose" else 0,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            # Your own title is private during compose -- that's the whole game.
            "myTitle": self.assignments.get(player_id) if self.phase == "compose" else None,
            "myEmoji": self.submissions.get(player_id) if self.phase == "compose" else None,
            "entries": [
                {"index": i, "emoji": e["emoji"], "isMine": e["ownerID"] == player_id}
                for i, e in enumerate(self.entries)
            ] if self.phase == "guess" else [],
            "myGuesses": [
                {"index": k, "text": val}
                for k, val in self.guesses.get(player_id, {}).items()
            ],
        })
        return state


class NPATEngine(RoundBasedEngine):
    """Name, Place, Animal, Thing -- the Indian classroom classic.

    Unique answers score double, which is the rule that makes it competitive
    rather than a typing race.
    """

    game_id = "npat"
    min_players = 2
    max_players = 20
    total_rounds = 5
    first_phase = "fill"
    phase_seconds = {"fill": 60, "reveal": 12}

    UNIQUE_POINTS = 10
    SHARED_POINTS = 5

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.letter = ""
        self.used: set[str] = set()
        self.breakdown: list[dict] = []

    def begin_phase(self, phase):
        if phase == "fill":
            pool = [c for c in C.NPAT_LETTERS if c not in self.used]
            if not pool:
                self.used.clear()
                pool = list(C.NPAT_LETTERS)
            self.letter = random.choice(pool)
            self.used.add(self.letter)
            self.breakdown = []

    def handle_action(self, player_id, action, data):
        if action == "submit" and self.phase == "fill":
            entry = {
                field: str(data.get(field, ""))[:24].strip()
                for field in C.NPAT_FIELDS
            }
            self.submissions[player_id] = entry

    def resolve_phase(self, phase):
        if phase == "fill":
            self._score()
            return "reveal"
        return None

    def _score(self):
        self.breakdown = []
        for field in C.NPAT_FIELDS:
            counts: dict[str, int] = {}
            for entry in self.submissions.values():
                val = _norm(entry.get(field))
                if val and val.startswith(self.letter.lower()):
                    counts[val] = counts.get(val, 0) + 1

            for pid, entry in self.submissions.items():
                val = _norm(entry.get(field))
                if not val or not val.startswith(self.letter.lower()):
                    points = 0
                elif counts.get(val, 0) == 1:
                    points = self.UNIQUE_POINTS
                else:
                    points = self.SHARED_POINTS
                if points:
                    self.award(pid, points)
                self.breakdown.append({
                    "playerID": pid, "field": field,
                    "value": entry.get(field, ""), "points": points,
                })

    def public_state(self):
        state = self.base_public()
        state.update({
            "letter": self.letter,
            "fields": C.NPAT_FIELDS,
            "breakdown": self.breakdown if self.phase == "reveal" else [],
            "answers": [
                {"playerID": pid, "name": self.player_name(pid), **entry}
                for pid, entry in self.submissions.items()
            ] if self.phase == "reveal" else [],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "letter": self.letter,
            "fields": C.NPAT_FIELDS,
            "myEntry": self.submissions.get(player_id, {}),
        })
        return state


class MostLikelyToEngine(RoundBasedEngine):
    """Vote for who in the room fits the prompt. Secret ballot until reveal.

    Everyone votes at once, nobody can vote for themselves, and the tally
    stays hidden until the reveal phase. Points go to the players who
    received votes, with a bonus for the top-voted player(s).
    """

    game_id = "most_likely_to"
    min_players = 3
    max_players = 20
    total_rounds = 5
    first_phase = "vote"
    phase_seconds = {"vote": 30, "reveal": 10}

    POINTS_PER_VOTE = 100
    TOP_VOTE_BONUS = 250

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.prompt = ""
        self.votes: dict[str, str] = {}      # voter_id -> target_id
        self.used: set[str] = set()
        self.round_results: list[dict] = []  # per-target counts, reveal only

    def begin_phase(self, phase):
        if phase == "vote":
            self.prompt = cs.pick_one(self.room, "most_likely", avoid=self.used)
            self.used.add(cs.norm_key(self.prompt))
            self.votes = {}
            self.round_results = []

    def handle_action(self, player_id, action, data):
        if action != "vote" or self.phase != "vote":
            return
        if self.room.player(player_id) is None:
            return                            # unknown voter
        target = data.get("targetID")
        if target == player_id:
            return                            # no self-votes
        if self.room.player(target) is None:
            return                            # unknown target
        self.votes[player_id] = target
        # Mirror into submissions so the room fast-forwards once everyone
        # has voted instead of burning the rest of the clock.
        self.submissions[player_id] = target

    def resolve_phase(self, phase):
        if phase == "vote":
            self._tally_and_score()
            return "reveal"
        return None

    def _tally_and_score(self):
        counts: dict[str, int] = {}
        for target in self.votes.values():
            if target not in self.scores:
                continue                      # target left mid-round
            counts[target] = counts.get(target, 0) + 1
        if not counts:
            self.round_results = []
            return
        top = max(counts.values())
        self.round_results = [
            {"playerID": tid, "name": self.player_name(tid),
             "votes": n, "topVoted": n == top}
            for tid, n in sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
        ]
        for tid, n in counts.items():
            self.award(tid, self.POINTS_PER_VOTE * n)
            if n == top:
                self.award(tid, self.TOP_VOTE_BONUS)

    def public_state(self):
        state = self.base_public()
        state.update({
            "prompt": self.prompt,
            # Count only -- who voted for whom stays secret until reveal.
            "votesSoFar": len(self.votes),
            "roundResults": self.round_results if self.phase == "reveal" else [],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "prompt": self.prompt,
            "hasVoted": player_id in self.votes,
            "myVoteTargetID": self.votes.get(player_id),
            # The phone needs the roster to vote; everyone sees everyone
            # here, so there is nothing secret to hide.
            "players": self.scoreboard(),
            "myPlayerID": player_id,
        })
        return state

    def on_player_leave(self, player_id):
        super().on_player_leave(player_id)
        self.votes.pop(player_id, None)


ENGINES = {
    "bluff_it": BluffItEngine,
    "last_tap": LastTapEngine,
    "herd": HerdEngine,
    "emoji_movie": EmojiMovieEngine,
    "npat": NPATEngine,
    "most_likely_to": MostLikelyToEngine,
}
