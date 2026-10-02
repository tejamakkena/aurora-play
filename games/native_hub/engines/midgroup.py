"""Mid-group engines (4-12 players).

These lean hardest on the two-screen split: Cipher Grid's key card and Odd One
Out's location are impossible to hide in a single-screen game.
"""

import random
import time

from games.native_hub.engines import _content as C
from games.native_hub.engines._matching import guess_matches
from games.native_hub.engines._bases import RoundBasedEngine
from games.native_hub.engines.content_packs import (
    questions_for,
    fresh_questions,
    record_questions,
)
from games.native_hub.engine import NativeGameEngine


def _norm(text) -> str:
    return " ".join(str(text).strip().lower().split()) if text else ""


class CipherGridEngine(NativeGameEngine):
    """Two teams, one shared 5x5 grid, a colour key only the spymasters hold.

    The grid must be visible to everyone and the key must not be -- which is
    exactly what the TV-plus-phones setup provides and a single screen cannot.
    """

    game_id = "cipher_grid"
    min_players = 4
    max_players = 12

    GRID = 25
    RED, BLUE, NEUTRAL, ASSASSIN = "red", "blue", "neutral", "assassin"

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.words: list[str] = []
        self.key: list[str] = []
        self.revealed: list[bool] = []
        self.teams: dict[str, str] = {}         # player -> "red"/"blue"
        self.spymasters: dict[str, str] = {}    # team -> player id
        self.turn = self.RED
        self.clue = {"word": "", "count": 0}
        self.guesses_left = 0
        self.winner: str | None = None
        self._finished = False
        self.log: list[dict] = []

    def start(self, players):
        self.words = random.sample(C.CIPHER_WORDS, self.GRID)

        # 9 for the starting team, 8 for the other, 7 neutral, 1 assassin.
        key = ([self.RED] * 9 + [self.BLUE] * 8
               + [self.NEUTRAL] * 7 + [self.ASSASSIN])
        random.shuffle(key)
        self.key = key
        self.revealed = [False] * self.GRID

        shuffled = list(players)
        random.shuffle(shuffled)
        for i, player in enumerate(shuffled):
            self.teams[player.id] = self.RED if i % 2 == 0 else self.BLUE

        for team in (self.RED, self.BLUE):
            members = [pid for pid, t in self.teams.items() if t == team]
            if members:
                self.spymasters[team] = members[0]

        self.turn = self.RED
        self.guesses_left = 0

    def _remaining(self, team):
        return sum(1 for i, c in enumerate(self.key)
                   if c == team and not self.revealed[i])

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        team = self.teams.get(player_id)
        if team is None or team != self.turn:
            return

        if action == "give_clue":
            if self.spymasters.get(team) != player_id or self.guesses_left:
                return
            word = str(data.get("word", ""))[:20].strip()
            count = data.get("count")
            if not word or not isinstance(count, int) or not 1 <= count <= 9:
                return
            self.clue = {"word": word, "count": count}
            self.guesses_left = count + 1      # the classic bonus guess

        elif action == "guess":
            if self.spymasters.get(team) == player_id or not self.guesses_left:
                return                          # spymasters never guess
            idx = data.get("index")
            if not isinstance(idx, int) or not 0 <= idx < self.GRID:
                return
            if self.revealed[idx]:
                return
            self._reveal(idx, team)

        elif action == "end_turn":
            self._swap_turn()

    def _reveal(self, idx, team):
        self.revealed[idx] = True
        colour = self.key[idx]
        self.log.append({"word": self.words[idx], "colour": colour, "team": team})

        if colour == self.ASSASSIN:
            self.winner = self.BLUE if team == self.RED else self.RED
            self._finished = True
            return

        if colour == team:
            self.guesses_left -= 1
            if self._remaining(team) == 0:
                self.winner = team
                self._finished = True
                return
            if self.guesses_left <= 0:
                self._swap_turn()
        else:
            # Wrong colour ends the turn immediately.
            other = self.BLUE if team == self.RED else self.RED
            if colour == other and self._remaining(other) == 0:
                self.winner = other
                self._finished = True
                return
            self._swap_turn()

    def _swap_turn(self):
        self.turn = self.BLUE if self.turn == self.RED else self.RED
        self.clue = {"word": "", "count": 0}
        self.guesses_left = 0

    def on_player_leave(self, player_id):
        # A spymaster whose phone drops would leave their team unable to
        # clue ever again; hand the key to a teammate who is still here.
        team = self.teams.get(player_id)
        if team and self.spymasters.get(team) == player_id:
            for p in self.room.connected_players():
                if p.id != player_id and self.teams.get(p.id) == team:
                    self.spymasters[team] = p.id
                    break

    def public_state(self):
        return {
            # Only revealed colours go out publicly. The unrevealed key never
            # appears here -- it is private_state for the spymasters alone.
            "words": self.words,
            "revealed": [
                {"index": i, "colour": self.key[i]}
                for i in range(self.GRID) if self.revealed[i]
            ],
            "turn": self.turn,
            "clue": self.clue,
            "guessesLeft": self.guesses_left,
            "redLeft": self._remaining(self.RED),
            "blueLeft": self._remaining(self.BLUE),
            "winner": self.winner,
            "log": self.log[-6:],
            "spymasterNames": {
                team: self.player_name(pid) for team, pid in self.spymasters.items()
            },
            "players": [
                {"id": p.id, "name": p.name, "team": self.teams.get(p.id),
                 "isSpymaster": self.spymasters.get(self.teams.get(p.id, "")) == p.id}
                for p in self.room.players
            ],
        }

    def private_state(self, player_id):
        team = self.teams.get(player_id)
        is_spymaster = self.spymasters.get(team) == player_id if team else False
        return {
            "team": team,
            "isSpymaster": is_spymaster,
            "isMyTurn": team == self.turn,
            # The colour key -- the one secret in the game.
            "key": self.key if is_spymaster else [],
            "words": self.words,
            "revealed": self.revealed,
            "clue": self.clue,
            "guessesLeft": self.guesses_left,
            "canGuess": team == self.turn and not is_spymaster and self.guesses_left > 0,
            "canClue": team == self.turn and is_spymaster and self.guesses_left == 0,
        }

    def is_over(self):
        return self._finished

    def results(self):
        scores = {p.id: (1 if self.teams.get(p.id) == self.winner else 0)
                  for p in self.room.players}
        return self.ranked_results(scores)


class OddOneOutEngine(NativeGameEngine):
    """Everyone shares a secret location -- except the Spy, who must bluff.

    Three rounds, a new spy and location each time. The spy scores 2 for
    escaping (or naming the location); everyone else scores 1 for catching
    them. A tied vote has no consensus, so the spy escapes.
    """

    game_id = "odd_one_out"
    min_players = 4
    max_players = 10

    TOTAL_ROUNDS = 3
    ROUND_SECONDS = 240
    VOTE_SECONDS = 60
    REVEAL_SECONDS = 10

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.location = ""
        self.spy: str | None = None
        self.phase = "question"
        self.deadline = 0.0
        self.votes: dict[str, str] = {}
        self.winner: str | None = None
        self.spy_guess: str | None = None
        self.round = 0
        self.scores: dict[str, int] = {}
        self.used_locations: set[str] = set()
        self.past_spies: list[str] = []
        self._finished = False

    def start(self, players):
        self.scores = {p.id: 0 for p in players}
        self._new_round()

    def _new_round(self):
        self.round += 1
        pool = [loc for loc in C.SPY_LOCATIONS if loc not in self.used_locations] \
            or list(C.SPY_LOCATIONS)
        self.location = random.choice(pool)
        self.used_locations.add(self.location)
        people = [p.id for p in self.room.connected_players()] or list(self.scores)
        fresh = [pid for pid in people if pid not in self.past_spies] or people
        self.spy = random.choice(fresh)
        self.past_spies.append(self.spy)
        self.phase = "question"
        self.votes = {}
        self.winner = None
        self.spy_guess = None
        self.deadline = time.time() + self.ROUND_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def handle_action(self, player_id, action, data):
        if self._finished or self.phase == "reveal":
            return
        if action == "call_vote" and self.phase == "question":
            self.phase = "vote"
            self.deadline = time.time() + self.VOTE_SECONDS
        elif action == "vote" and self.phase == "vote":
            target = data.get("targetID")
            if isinstance(target, str) and target != player_id and self.room.player(target):
                self.votes[player_id] = target
                if len(self.votes) >= len(self.room.connected_players()):
                    self._resolve_vote()
        elif action == "spy_guess" and player_id == self.spy:
            guess = str(data.get("location", ""))[:40]
            self.spy_guess = guess
            # The spy naming the location wins the round outright.
            self._end_round("spy" if _norm(guess) == _norm(self.location) else "players")

    def tick(self, dt):
        if self._finished or not self.deadline:
            return
        if time.time() >= self.deadline:
            if self.phase == "question":
                self.phase = "vote"
                self.deadline = time.time() + self.VOTE_SECONDS
            elif self.phase == "vote":
                self._resolve_vote()
            elif self.phase == "reveal":
                if self.round >= self.TOTAL_ROUNDS:
                    self._finished = True
                    self.deadline = 0.0
                else:
                    self._new_round()

    def _resolve_vote(self):
        tally: dict[str, int] = {}
        for target in self.votes.values():
            tally[target] = tally.get(target, 0) + 1
        accused = None
        if tally:
            top = max(tally.values())
            leaders = [t for t, n in tally.items() if n == top]
            accused = leaders[0] if len(leaders) == 1 else None   # tie: no consensus
        self._end_round("players" if accused == self.spy else "spy")

    def _end_round(self, winner):
        self.winner = winner
        if winner == "spy" and self.spy:
            self._award(self.spy, 2)
        else:
            for pid in self.scores:
                if pid != self.spy:
                    self._award(pid, 1)
        self.phase = "reveal"
        self.deadline = time.time() + self.REVEAL_SECONDS

    def _award(self, pid, points):
        self.scores[pid] = self.scores.get(pid, 0) + points
        player = self.room.player(pid)
        if player is not None:
            player.score = self.scores[pid]

    def public_state(self):
        tally: dict[str, int] = {}
        for target in self.votes.values():
            tally[target] = tally.get(target, 0) + 1
        revealed = self.phase == "reveal" or self._finished
        return {
            "phase": self.phase,
            "round": self.round,
            "totalRounds": self.TOTAL_ROUNDS,
            "secondsLeft": self.seconds_left(),
            "votedPlayerIDs": list(self.votes.keys()),
            "tally": [
                {"playerID": pid, "name": self.player_name(pid), "votes": n}
                for pid, n in sorted(tally.items(), key=lambda kv: -kv[1])
            ],
            # Never revealed until the round is over.
            "location": self.location if revealed else None,
            "spyID": self.spy if revealed else None,
            "spyName": self.player_name(self.spy) if revealed and self.spy else None,
            "spyGuess": self.spy_guess,
            "winner": self.winner,
            "players": [
                {"id": p.id, "name": p.name, "score": self.scores.get(p.id, 0),
                 "hasVoted": p.id in self.votes}
                for p in self.room.players
            ],
        }

    def private_state(self, player_id):
        is_spy = player_id == self.spy
        return {
            "phase": self.phase,
            "round": self.round,
            "isSpy": is_spy,
            # The spy is simply never told the location -- that is the game.
            "location": None if is_spy else self.location,
            "secondsLeft": self.seconds_left(),
            "canVote": self.phase == "vote" and player_id not in self.votes,
            "myVote": self.votes.get(player_id),
            "allLocations": C.SPY_LOCATIONS if is_spy else [],
            "score": self.scores.get(player_id, 0),
            "players": [
                {"id": p.id, "name": p.name}
                for p in self.room.players if p.id != player_id
            ],
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(dict(self.scores))


class SealedAuctionEngine(RoundBasedEngine):
    """Blind bidding against a private budget. Overspend early and you're broke."""

    game_id = "sealed_auction"
    min_players = 2
    max_players = 8
    total_rounds = 8
    first_phase = "bid"
    phase_seconds = {"bid": 25, "reveal": 8}

    STARTING_BUDGET = 100

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.budgets: dict[str, int] = {}
        self.lot = ("", 0)
        self.used: set[int] = set()
        self.last_result: dict = {}

    def start(self, players):
        self.budgets = {p.id: self.STARTING_BUDGET for p in players}
        super().start(players)

    def begin_phase(self, phase):
        if phase == "bid":
            pool = [i for i in range(len(C.AUCTION_LOTS)) if i not in self.used]
            if not pool:
                self.used.clear()
                pool = list(range(len(C.AUCTION_LOTS)))
            idx = random.choice(pool)
            self.used.add(idx)
            self.lot = C.AUCTION_LOTS[idx]
            self.last_result = {}

    def handle_action(self, player_id, action, data):
        if action == "bid" and self.phase == "bid":
            amount = data.get("amount")
            budget = self.budgets.get(player_id, 0)
            if isinstance(amount, int) and 0 <= amount <= budget:
                self.submissions[player_id] = amount

    def resolve_phase(self, phase):
        if phase == "bid":
            self._settle()
            return "reveal"
        return None

    def _settle(self):
        if not self.submissions:
            return
        top = max(self.submissions.values())
        winners = [pid for pid, amt in self.submissions.items() if amt == top]
        # A tie means nobody wins the lot but everyone still pays nothing --
        # keeps bidding honest without needing a tiebreak round.
        if len(winners) == 1 and top > 0:
            winner = winners[0]
            self.budgets[winner] -= top
            self.award(winner, self.lot[1] * 10)
            self.last_result = {
                "winnerID": winner, "winnerName": self.player_name(winner),
                "amount": top, "tied": False,
            }
        else:
            self.last_result = {"winnerID": None, "amount": top,
                                "tied": len(winners) > 1}

        self.last_result["bids"] = [
            {"playerID": pid, "name": self.player_name(pid), "amount": amt}
            for pid, amt in sorted(self.submissions.items(), key=lambda kv: -kv[1])
        ]

    def public_state(self):
        state = self.base_public()
        state.update({
            "lotName": self.lot[0],
            "lotValue": self.lot[1],
            # Bids stay hidden until the reveal -- that is what "sealed" means.
            "result": self.last_result if self.phase == "reveal" else {},
            "budgets": [
                {"playerID": pid, "name": self.player_name(pid), "budget": b}
                for pid, b in self.budgets.items()
            ],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "lotName": self.lot[0],
            "lotValue": self.lot[1],
            "budget": self.budgets.get(player_id, 0),
            "myBid": self.submissions.get(player_id),
        })
        return state


class WavelengthEngine(RoundBasedEngine):
    """One player sees a hidden target on a dial and must describe where it is."""

    game_id = "wavelength"
    min_players = 3
    max_players = 10
    total_rounds = 6
    first_phase = "clue"
    phase_seconds = {"clue": 45, "dial": 45, "reveal": 10}

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.spectrum = ("", "")
        self.target = 50
        self.clue = ""
        self.psychic: str | None = None
        self.dial = 50
        self.order: list[str] = []
        self.last_points = 0

    def start(self, players):
        self.order = [p.id for p in players]
        super().start(players)

    def begin_phase(self, phase):
        if phase == "clue":
            self.spectrum = random.choice(C.WAVELENGTH_SPECTRA)
            self.target = random.randint(8, 92)
            self.clue = ""
            self.dial = 50
            self.last_points = 0
            if self.order:
                self.psychic = self.order[(self.round - 1) % len(self.order)]

    def handle_action(self, player_id, action, data):
        if action == "give_clue" and self.phase == "clue" and player_id == self.psychic:
            text = str(data.get("clue", ""))[:40].strip()
            if text:
                self.clue = text
                self.submissions[player_id] = text
                self.advance()
        elif action == "set_dial" and self.phase == "dial" and player_id != self.psychic:
            value = data.get("value")
            if isinstance(value, int) and 0 <= value <= 100:
                self.dial = value
                self.submissions[player_id] = value

    def everyone_submitted(self):
        if self.phase != "dial":
            return super().everyone_submitted()
        guessers = [p for p in self.active_players() if p.id != self.psychic]
        return bool(guessers) and all(p.id in self.submissions for p in guessers)

    def resolve_phase(self, phase):
        if phase == "clue":
            self.submissions = {}
            return "dial"
        if phase == "dial":
            self._score()
            return "reveal"
        return None

    def _score(self):
        distance = abs(self.dial - self.target)
        if distance <= 3:
            points = 400
        elif distance <= 8:
            points = 300
        elif distance <= 15:
            points = 200
        elif distance <= 25:
            points = 100
        else:
            points = 0
        self.last_points = points
        if points:
            # Team game: the psychic and every guesser share the score.
            for player in self.active_players():
                self.award(player.id, points)

    def public_state(self):
        state = self.base_public()
        state.update({
            "leftLabel": self.spectrum[0],
            "rightLabel": self.spectrum[1],
            "clue": self.clue,
            "dial": self.dial if self.phase in ("dial", "reveal") else None,
            # The target is the secret; it appears only at reveal.
            "target": self.target if self.phase == "reveal" else None,
            "pointsAwarded": self.last_points if self.phase == "reveal" else None,
            "psychicID": self.psychic,
            "psychicName": self.player_name(self.psychic) if self.psychic else "",
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        is_psychic = player_id == self.psychic
        state.update({
            "isPsychic": is_psychic,
            "leftLabel": self.spectrum[0],
            "rightLabel": self.spectrum[1],
            # Only the psychic ever sees the target.
            "target": self.target if is_psychic else None,
            "clue": self.clue,
            "dial": self.dial,
            "canClue": is_psychic and self.phase == "clue",
            "canDial": not is_psychic and self.phase == "dial",
        })
        return state


class KBCEngine(NativeGameEngine):
    """Prize-ladder quiz. The Audience Poll lifeline polls the actual room.

    The hot seat rotates: each player (up to ``MAX_SEATS``) gets their own
    run up the ladder with fresh lifelines, and the final ranking is what
    each of them banked. That lifeline is only possible because everyone is
    already holding a phone.
    """

    game_id = "kbc"
    min_players = 1
    max_players = 20

    ANSWER_SECONDS = 45
    POLL_SECONDS = 20
    REVEAL_SECONDS = 8
    MAX_SEATS = 6
    SAFE_RUNG = 4                   # answering this rung locks in a milestone

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.seat_index = 0
        self.hot_seat: str | None = None
        self.rung = 0
        self.pool: list[tuple] = []
        self.used: set[str] = set()
        self.question: tuple = ("", [], 0)
        self.phase = "answer"
        self.deadline = 0.0
        self.choices: list[str] = []
        self.hidden: list[int] = []            # indices removed by 50:50
        self.lifelines = {"fifty": True, "poll": True, "skip": True}
        self.poll_votes: dict[str, int] = {}
        self.answer: int | None = None
        self.correct: int | None = None
        self.outcome: str | None = None        # correct / wrong / walked / won
        self.seat_over = False
        self.banked_by: dict[str, int] = {}
        self._finished = False
        self.banked = 0

    def start(self, players):
        self.order = [p.id for p in players][: self.MAX_SEATS]
        self.banked_by = {p.id: 0 for p in players}
        pack = getattr(self.room, "content_pack", "en")
        self._pack = pack
        pool = [tuple(q) for q in questions_for(pack, "kbc")]
        # Trivia questions widen the pool so later seats don't replay the
        # questions everyone just watched. Skip any whose text is already in
        # the KBC pool -- a few questions exist in both banks.
        have = {q[0] for q in pool}
        for q in questions_for(pack, "trivia"):
            if len(q) == 4 and q[1] not in have:
                have.add(q[1])
                pool.append((q[1], list(q[2]), q[3]))
        # Skip what this room asked recently; the `used` set in
        # _draw_question already prevents repeats within a session.
        self.pool = fresh_questions(self.room, pack, "kbc", pool=pool)
        self.seat_index = 0
        self._start_seat()

    def _start_seat(self):
        self.hot_seat = self.order[self.seat_index] if self.order else None
        self.rung = 0
        self.banked = 0
        self.lifelines = {"fifty": True, "poll": True, "skip": True}
        self.seat_over = False
        self._load_question()

    def _draw_question(self):
        fresh = [q for q in self.pool if q[0] not in self.used]
        if not fresh:
            self.used.clear()
            fresh = list(self.pool)
        q = random.choice(fresh)
        self.used.add(q[0])
        # Remember the question in the room's rolling history so the next
        # session in this room skips it.
        record_questions(self.room, self._pack, "kbc", [q])
        return q

    def _load_question(self):
        self.question = self._draw_question()
        text, choices, correct = self.question
        # Shuffle so the answer is not always at index 0 in the content table.
        pairs = list(enumerate(choices))
        random.shuffle(pairs)
        self.choices = [c for _, c in pairs]
        self.correct = next(i for i, (orig, _) in enumerate(pairs) if orig == correct)
        self.hidden = []
        self.poll_votes = {}
        self.answer = None
        self.outcome = None
        self.phase = "answer"
        self.deadline = time.time() + self.ANSWER_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def handle_action(self, player_id, action, data):
        if self._finished:
            return

        if action == "poll_vote" and self.phase == "poll":
            idx = data.get("index")
            if isinstance(idx, int) and 0 <= idx < len(self.choices):
                self.poll_votes[player_id] = idx
            return

        if player_id != self.hot_seat:
            return                      # only the hot seat plays

        if action == "answer" and self.phase == "answer":
            idx = data.get("index")
            if isinstance(idx, int) and 0 <= idx < len(self.choices) and idx not in self.hidden:
                self.answer = idx
                self._resolve()
        elif action == "lifeline_fifty" and self.lifelines["fifty"] and self.phase == "answer":
            self.lifelines["fifty"] = False
            wrong = [i for i in range(len(self.choices)) if i != self.correct]
            random.shuffle(wrong)
            self.hidden = wrong[:2]
        elif action == "lifeline_poll" and self.lifelines["poll"] and self.phase == "answer":
            self.lifelines["poll"] = False
            self.phase = "poll"
            self.deadline = time.time() + self.POLL_SECONDS
        elif action == "lifeline_skip" and self.lifelines["skip"] and self.phase == "answer":
            # Flip the question: a new one at the same rung, not a free climb.
            self.lifelines["skip"] = False
            self._load_question()
        elif action == "walk_away" and self.phase in ("answer", "poll"):
            self.outcome = "walked"
            self._end_seat()

    def _set_banked(self, amount):
        self.banked = amount
        if self.hot_seat:
            self.banked_by[self.hot_seat] = amount
            player = self.room.player(self.hot_seat)
            if player is not None:
                player.score = amount

    def _resolve(self):
        if self.answer == self.correct:
            self._set_banked(C.KBC_LADDER[self.rung])
            self.outcome = "correct"
            if self.rung + 1 >= len(C.KBC_LADDER):
                self.outcome = "won"
                self.seat_over = True
        else:
            # Wrong answer drops to the last guaranteed milestone.
            self._set_banked(C.KBC_LADDER[self.SAFE_RUNG] if self.rung > self.SAFE_RUNG else 0)
            self.outcome = "wrong"
            self.seat_over = True
        self.phase = "reveal"
        self.deadline = time.time() + self.REVEAL_SECONDS

    def _end_seat(self):
        self.seat_over = True
        self.phase = "reveal"
        self.deadline = time.time() + self.REVEAL_SECONDS

    def tick(self, dt):
        if self._finished or not self.deadline:
            return
        if time.time() < self.deadline:
            return
        if self.phase == "poll":
            self.phase = "answer"
            self.deadline = time.time() + self.ANSWER_SECONDS
        elif self.phase == "answer":
            self.answer = -1              # timed out counts as wrong
            self._resolve()
        elif self.phase == "reveal":
            if self.seat_over:
                self.seat_index += 1
                if self.seat_index >= len(self.order):
                    self._finished = True
                    self.phase = "final"
                    self.deadline = 0.0
                else:
                    self._start_seat()
            else:
                self.rung += 1
                self._load_question()

    def on_player_leave(self, player_id):
        if player_id == self.hot_seat and self.phase in ("answer", "poll"):
            self.outcome = "walked"
            self._end_seat()

    def _poll_tally(self):
        counts = [0] * len(self.choices)
        for idx in self.poll_votes.values():
            if 0 <= idx < len(counts):
                counts[idx] += 1
        total = sum(counts) or 1
        return [round(100 * c / total) for c in counts]

    def _standings(self):
        return [
            {"playerID": pid, "name": self.player_name(pid), "banked": amt}
            for pid, amt in sorted(self.banked_by.items(), key=lambda kv: -kv[1])
        ]

    def public_state(self):
        return {
            "phase": self.phase,
            "rung": self.rung,
            "ladder": C.KBC_LADDER,
            "prize": C.KBC_LADDER[self.rung] if self.rung < len(C.KBC_LADDER) else 0,
            "banked": self.banked,
            "question": self.question[0],
            "choices": [
                {"index": i, "text": c, "hidden": i in self.hidden}
                for i, c in enumerate(self.choices)
            ],
            "secondsLeft": self.seconds_left(),
            "lifelines": self.lifelines,
            "pollTally": self._poll_tally() if self.phase in ("poll", "reveal") else [],
            "pollCount": len(self.poll_votes),
            # correctIndex is withheld until reveal: the TV highlights it the
            # moment the key is present, so sending it early spoils the answer.
            "correctIndex": self.correct if self.phase == "reveal" else None,
            "answerIndex": self.answer if self.phase == "reveal" else None,
            "outcome": self.outcome if self.phase == "reveal" else None,
            "hotSeatID": self.hot_seat,
            "hotSeatName": self.player_name(self.hot_seat) if self.hot_seat else "",
            "seat": self.seat_index + 1,
            "totalSeats": len(self.order),
            "standings": self._standings(),
        }

    def private_state(self, player_id):
        is_hot = player_id == self.hot_seat
        return {
            "phase": self.phase,
            "isHotSeat": is_hot,
            "hotSeatName": self.player_name(self.hot_seat) if self.hot_seat else "",
            "question": self.question[0],
            "choices": [
                {"index": i, "text": c, "hidden": i in self.hidden}
                for i, c in enumerate(self.choices)
            ],
            "secondsLeft": self.seconds_left(),
            "lifelines": self.lifelines if is_hot else {},
            "canAnswer": is_hot and self.phase == "answer",
            "canPoll": not is_hot and self.phase == "poll" and player_id not in self.poll_votes,
            "myPollVote": self.poll_votes.get(player_id),
            "prize": C.KBC_LADDER[self.rung] if self.rung < len(C.KBC_LADDER) else 0,
            "banked": self.banked_by.get(player_id, 0),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(dict(self.banked_by))


class BollywoodCharadesEngine(RoundBasedEngine):
    """Act out a film; the room types guesses. Faster guesses score more."""

    game_id = "bollywood_charades"
    min_players = 3
    max_players = 16
    total_rounds = 6
    first_phase = "act"
    phase_seconds = {"act": 90, "reveal": 8}

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.title = ""
        self.actor: str | None = None
        self.order: list[str] = []
        self.correct_ids: list[str] = []
        self.used: set[str] = set()
        self.started_at = 0.0

    def start(self, players):
        self.order = [p.id for p in players]
        super().start(players)

    def begin_phase(self, phase):
        if phase == "act":
            pool = [t for t in C.CHARADES_TITLES if t not in self.used]
            if not pool:
                self.used.clear()
                pool = list(C.CHARADES_TITLES)
            self.title = random.choice(pool)
            self.used.add(self.title)
            if self.order:
                self.actor = self.order[(self.round - 1) % len(self.order)]
            self.correct_ids = []
            self.started_at = time.time()

    def handle_action(self, player_id, action, data):
        if action != "guess" or self.phase != "act" or player_id == self.actor:
            return
        if player_id in self.correct_ids:
            return
        guess = str(data.get("text", ""))[:60]
        if guess_matches(guess, self.title):
            elapsed = time.time() - self.started_at
            # Decays from 500 to 100 across the 90-second round.
            points = max(100, int(500 - elapsed * 4))
            self.award(player_id, points)
            if self.actor:
                self.award(self.actor, 100)
            self.correct_ids.append(player_id)
            self.submissions[player_id] = guess

    def everyone_submitted(self):
        guessers = [p for p in self.active_players() if p.id != self.actor]
        return bool(guessers) and all(p.id in self.correct_ids for p in guessers)

    def resolve_phase(self, phase):
        return "reveal" if phase == "act" else None

    def public_state(self):
        state = self.base_public()
        state.update({
            "actorID": self.actor,
            "actorName": self.player_name(self.actor) if self.actor else "",
            # The title is on the actor's phone only, until the reveal.
            "title": self.title if self.phase == "reveal" else None,
            "correctPlayerIDs": self.correct_ids,
            "correctNames": [self.player_name(p) for p in self.correct_ids],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        is_actor = player_id == self.actor
        state.update({
            "isActor": is_actor,
            "title": self.title if (is_actor or self.phase == "reveal") else None,
            "gotIt": player_id in self.correct_ids,
            "canGuess": not is_actor and self.phase == "act"
                        and player_id not in self.correct_ids,
        })
        return state


ENGINES = {
    "cipher_grid": CipherGridEngine,
    "odd_one_out": OddOneOutEngine,
    "sealed_auction": SealedAuctionEngine,
    "wavelength": WavelengthEngine,
    "kbc": KBCEngine,
    "bollywood_charades": BollywoodCharadesEngine,
}
