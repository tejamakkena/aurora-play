"""Mid-group engines (4-12 players).

These lean hardest on the two-screen split: Cipher Grid's key card and Odd One
Out's location are impossible to hide in a single-screen game.
"""

import random
import time

from games.native_hub.engines import _content as C
from games.native_hub.engines._bases import RoundBasedEngine
from games.native_hub.engines.content_packs import questions_for
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
    """Everyone shares a secret location -- except the Spy, who must bluff."""

    game_id = "odd_one_out"
    min_players = 4
    max_players = 10

    ROUND_SECONDS = 300
    VOTE_SECONDS = 60

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.location = ""
        self.spy: str | None = None
        self.phase = "question"
        self.deadline = 0.0
        self.votes: dict[str, str] = {}
        self.winner: str | None = None
        self.spy_guess: str | None = None
        self._finished = False

    def start(self, players):
        self.location = random.choice(C.SPY_LOCATIONS)
        self.spy = random.choice(players).id
        self.phase = "question"
        self.deadline = time.time() + self.ROUND_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        if action == "call_vote" and self.phase == "question":
            self.phase = "vote"
            self.deadline = time.time() + self.VOTE_SECONDS
        elif action == "vote" and self.phase == "vote":
            target = data.get("targetID")
            if isinstance(target, str) and self.room.player(target):
                self.votes[player_id] = target
                if len(self.votes) >= len(self.room.connected_players()):
                    self._resolve_vote()
        elif action == "spy_guess" and player_id == self.spy:
            guess = str(data.get("location", ""))[:40]
            self.spy_guess = guess
            # The spy guessing correctly wins outright, at any point.
            self.winner = "spy" if _norm(guess) == _norm(self.location) else "players"
            self._finished = True

    def tick(self, dt):
        if self._finished or not self.deadline:
            return
        if time.time() >= self.deadline:
            if self.phase == "question":
                self.phase = "vote"
                self.deadline = time.time() + self.VOTE_SECONDS
            else:
                self._resolve_vote()

    def _resolve_vote(self):
        tally: dict[str, int] = {}
        for target in self.votes.values():
            tally[target] = tally.get(target, 0) + 1
        accused = max(tally, key=tally.get) if tally else None
        self.winner = "players" if accused == self.spy else "spy"
        self._finished = True
        self.phase = "reveal"

    def public_state(self):
        tally: dict[str, int] = {}
        for target in self.votes.values():
            tally[target] = tally.get(target, 0) + 1
        return {
            "phase": self.phase,
            "secondsLeft": self.seconds_left(),
            "votedPlayerIDs": list(self.votes.keys()),
            "tally": [
                {"playerID": pid, "name": self.player_name(pid), "votes": n}
                for pid, n in sorted(tally.items(), key=lambda kv: -kv[1])
            ],
            # Never revealed until the game is over.
            "location": self.location if self._finished else None,
            "spyID": self.spy if self._finished else None,
            "spyName": self.player_name(self.spy) if self._finished and self.spy else None,
            "spyGuess": self.spy_guess,
            "winner": self.winner,
            "players": [
                {"id": p.id, "name": p.name, "hasVoted": p.id in self.votes}
                for p in self.room.players
            ],
        }

    def private_state(self, player_id):
        is_spy = player_id == self.spy
        return {
            "phase": self.phase,
            "isSpy": is_spy,
            # The spy is simply never told the location -- that is the game.
            "location": None if is_spy else self.location,
            "secondsLeft": self.seconds_left(),
            "canVote": self.phase == "vote" and player_id not in self.votes,
            "myVote": self.votes.get(player_id),
            "allLocations": C.SPY_LOCATIONS if is_spy else [],
            "players": [
                {"id": p.id, "name": p.name}
                for p in self.room.players if p.id != player_id
            ],
        }

    def is_over(self):
        return self._finished

    def results(self):
        scores = {}
        for p in self.room.players:
            is_spy = p.id == self.spy
            won = (self.winner == "spy") if is_spy else (self.winner == "players")
            scores[p.id] = 1 if won else 0
        return self.ranked_results(scores)


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

    That lifeline is only possible because everyone is already holding a phone.
    """

    game_id = "kbc"
    min_players = 1
    max_players = 20

    ANSWER_SECONDS = 45
    POLL_SECONDS = 20
    REVEAL_SECONDS = 8

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.hot_seat: str | None = None
        self.rung = 0
        self.questions: list[tuple] = []
        self.phase = "answer"
        self.deadline = 0.0
        self.choices: list[str] = []
        self.hidden: list[int] = []            # indices removed by 50:50
        self.lifelines = {"fifty": True, "poll": True, "skip": True}
        self.poll_votes: dict[str, int] = {}
        self.answer: int | None = None
        self.correct: int | None = None
        self._finished = False
        self.banked = 0

    def start(self, players):
        self.order = [p.id for p in players]
        self.hot_seat = self.order[0] if self.order else None
        pool = questions_for(getattr(self.room, "content_pack", "en"), "kbc")
        self.questions = random.sample(pool,
                                       min(len(C.KBC_LADDER), len(pool)))
        self._load_question()

    def _load_question(self):
        text, choices, correct = self.questions[self.rung]
        # Shuffle so the answer is not always at index 0 in the content table.
        pairs = list(enumerate(choices))
        random.shuffle(pairs)
        self.choices = [c for _, c in pairs]
        self.correct = next(i for i, (orig, _) in enumerate(pairs) if orig == correct)
        self.hidden = []
        self.poll_votes = {}
        self.answer = None
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
            if isinstance(idx, int) and 0 <= idx < len(self.choices):
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
            self.lifelines["skip"] = False
            self._next_question()
        elif action == "walk_away":
            self.banked = C.KBC_LADDER[self.rung - 1] if self.rung else 0
            self._finished = True

    def _resolve(self):
        player = self.room.player(self.hot_seat) if self.hot_seat else None
        if self.answer == self.correct:
            self.banked = C.KBC_LADDER[self.rung]
            if player is not None:
                player.score = self.banked
            self.phase = "reveal"
            self.deadline = time.time() + self.REVEAL_SECONDS
        else:
            # Wrong answer drops to the last guaranteed milestone.
            self.banked = C.KBC_LADDER[4] if self.rung > 4 else 0
            if player is not None:
                player.score = self.banked
            self.phase = "reveal"
            self.deadline = time.time() + self.REVEAL_SECONDS
            self._finished = True

    def _next_question(self):
        self.rung += 1
        if self.rung >= len(self.questions) or self.rung >= len(C.KBC_LADDER):
            self._finished = True
            self.phase = "final"
        else:
            self._load_question()

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
            self._next_question()

    def _poll_tally(self):
        counts = [0] * len(self.choices)
        for idx in self.poll_votes.values():
            if 0 <= idx < len(counts):
                counts[idx] += 1
        total = sum(counts) or 1
        return [round(100 * c / total) for c in counts]

    def public_state(self):
        text = self.questions[self.rung][0] if self.rung < len(self.questions) else ""
        return {
            "phase": self.phase,
            "rung": self.rung,
            "ladder": C.KBC_LADDER,
            "prize": C.KBC_LADDER[self.rung] if self.rung < len(C.KBC_LADDER) else 0,
            "banked": self.banked,
            "question": text,
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
            "hotSeatID": self.hot_seat,
            "hotSeatName": self.player_name(self.hot_seat) if self.hot_seat else "",
        }

    def private_state(self, player_id):
        is_hot = player_id == self.hot_seat
        return {
            "phase": self.phase,
            "isHotSeat": is_hot,
            "question": self.questions[self.rung][0] if self.rung < len(self.questions) else "",
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
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


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
        if _norm(guess) == _norm(self.title):
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
