"""Social-deduction and trivia engines ported from the browser catalog.

Mafia ports role assignment and win-condition checking from
games/mafia/game_logic.py:MafiaGame, collapsed from its five phases
(lobby/night/day/voting/finished) to the two phases MafiaBoardState/
MafiaControllerView actually know about (day/night) -- discussion and
voting both happen inside the "day" phase on the TV, so there's no
separate voting phase to preserve in the native contract. Raja Mantri
ports role assignment and scoring straight from
games/raja_mantri/socket_events.py. Trivia has no reusable browser logic
(the browser game calls out to a Gemini API for questions), so its
question bank and round loop are original, built to
TVTriviaBoardView/TriviaControllerView's contract.
"""

import random
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines.content_packs import questions_for

# ---------------------------------------------------------------------------
# Mafia -- verified against MafiaBoardState/MafiaControllerView. Role names
# follow the Swift side (`"mafia"`, `"sheriff"`, `"doctor"`, default/"town"),
# not the browser's Role enum (which used "detective").
# ---------------------------------------------------------------------------


class MafiaEngine(NativeGameEngine):
    game_id = "mafia"
    min_players = 5
    max_players = 15

    DAY_SECONDS = 60
    NIGHT_SECONDS = 30

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.roles: dict[str, str] = {}
        self.alive: dict[str, bool] = {}
        self.phase = "night"
        self.round = 1
        self.deadline = 0.0
        self.night_actions: dict[str, dict] = {}
        self.day_votes: dict[str, str] = {}
        self.investigate_results: dict[str, str] = {}
        self.last_eliminated: str | None = None
        self.winner: str | None = None
        self._finished = False

    def start(self, players):
        ids = [p.id for p in players]
        random.shuffle(ids)
        n = len(ids)
        num_mafia = max(1, n // 4)
        roles = ["mafia"] * num_mafia + ["doctor", "sheriff"] + ["villager"] * (n - num_mafia - 2)
        roles = roles[:n]
        while len(roles) < n:
            roles.append("villager")
        for pid, role in zip(ids, roles):
            self.roles[pid] = role
            self.alive[pid] = True
        self.deadline = time.time() + self.NIGHT_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def _alive_ids(self):
        return [pid for pid, ok in self.alive.items() if ok]

    def handle_action(self, player_id, action, data):
        if self._finished or not self.alive.get(player_id):
            return
        role = self.roles.get(player_id)
        target = data.get("targetID")

        if self.phase == "night":
            if action == "eliminate" and role == "mafia" and target in self.alive and self.alive[target]:
                self.night_actions[player_id] = {"action": "eliminate", "target": target}
            elif action == "save" and role == "doctor" and target in self.alive and self.alive[target]:
                self.night_actions[player_id] = {"action": "save", "target": target}
            elif action == "investigate" and role == "sheriff" and target in self.alive and self.alive[target]:
                self.night_actions[player_id] = {"action": "investigate", "target": target}
                target_role = self.roles.get(target)
                name = self.player_name(target)
                self.investigate_results[player_id] = (
                    f"{name} is Mafia!" if target_role == "mafia" else f"{name} is not Mafia.")
        elif self.phase == "day":
            if action == "vote" and target in self.alive and self.alive[target]:
                self.day_votes[player_id] = target

    def tick(self, dt):
        if self._finished:
            return
        if self.deadline and time.time() >= self.deadline:
            self._resolve_phase()

    def _resolve_phase(self):
        if self.phase == "night":
            self._resolve_night()
            if self._check_winner():
                return
            self.phase = "day"
            self.day_votes = {}
            self.deadline = time.time() + self.DAY_SECONDS
        else:
            self._resolve_day()
            if self._check_winner():
                return
            self.phase = "night"
            self.round += 1
            self.night_actions = {}
            self.deadline = time.time() + self.NIGHT_SECONDS

    def _resolve_night(self):
        kills: dict[str, int] = {}
        saved = None
        for pid, act in self.night_actions.items():
            if act["action"] == "eliminate":
                kills[act["target"]] = kills.get(act["target"], 0) + 1
            elif act["action"] == "save":
                saved = act["target"]
        self.last_eliminated = None
        if kills:
            victim = max(kills, key=kills.get)
            if victim != saved:
                self.alive[victim] = False
                self.last_eliminated = self.player_name(victim)

    def _resolve_day(self):
        self.last_eliminated = None
        if self.day_votes:
            counts: dict[str, int] = {}
            for target in self.day_votes.values():
                counts[target] = counts.get(target, 0) + 1
            eliminated = max(counts, key=counts.get)
            self.alive[eliminated] = False
            self.last_eliminated = self.player_name(eliminated)

    def _check_winner(self):
        alive_mafia = [pid for pid in self._alive_ids() if self.roles[pid] == "mafia"]
        alive_others = [pid for pid in self._alive_ids() if self.roles[pid] != "mafia"]
        if not alive_mafia:
            self.winner = "villagers"
        elif len(alive_mafia) >= len(alive_others):
            self.winner = "mafia"
        else:
            return False
        self._finished = True
        for pid in self.roles:
            on_winning_team = (self.roles[pid] == "mafia") == (self.winner == "mafia")
            player = self.room.player(pid)
            if player is not None:
                player.score = 1000 if on_winning_team else 0
        return True

    def _vote_tally_by_name(self):
        counts: dict[str, int] = {}
        for target in self.day_votes.values():
            name = self.player_name(target)
            counts[name] = counts.get(name, 0) + 1
        return counts

    def public_state(self):
        return {
            "phase": self.phase,
            "round": self.round,
            "secondsLeft": self.seconds_left(),
            "lastEliminated": self.last_eliminated,
            "votes": self._vote_tally_by_name(),
            "players": [
                {"id": p.id, "name": p.name, "isAlive": self.alive.get(p.id, True),
                 "revealedRole": self.roles.get(p.id) if not self.alive.get(p.id, True) else None}
                for p in self.room.players
            ],
            "winner": self.winner,
        }

    def private_state(self, player_id):
        return {
            "myID": player_id,
            "role": self.roles.get(player_id, "villager"),
            "phase": self.phase,
            "isAlive": self.alive.get(player_id, True),
            "secondsLeft": self.seconds_left(),
            "players": [
                {"id": p.id, "name": p.name, "isAlive": self.alive.get(p.id, True)}
                for p in self.room.players
            ],
            "myVote": self.day_votes.get(player_id),
            "investigateResult": self.investigate_results.get(player_id),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Raja Mantri -- verified against RajaMantriState/RajaMantriControllerView.
# Scoring ported from games/raja_mantri/socket_events.py:handle_guess.
# ---------------------------------------------------------------------------


class RajaMantriEngine(NativeGameEngine):
    game_id = "raja_mantri"
    min_players = 4
    max_players = 4

    TOTAL_ROUNDS = 4
    REVEAL_SECONDS = 6

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.round = 0
        self.phase = "guess"
        self.roles: dict[str, str] = {}
        self.chor_id: str | None = None
        self.sipahi_id: str | None = None
        self.accused_id: str | None = None
        self.round_result: str | None = None
        self.reveal_until = 0.0
        self._finished = False

    def start(self, players):
        self.order = [p.id for p in players]
        self.round = 0
        self._deal_round()

    def _deal_round(self):
        self.round += 1
        roles = ["Raja", "Mantri", "Chor", "Sipahi"]
        random.shuffle(roles)
        self.roles = {pid: roles[i] for i, pid in enumerate(self.order)}
        self.chor_id = next(pid for pid, r in self.roles.items() if r == "Chor")
        self.sipahi_id = next(pid for pid, r in self.roles.items() if r == "Sipahi")
        self.accused_id = None
        self.round_result = None
        self.phase = "guess"

    def handle_action(self, player_id, action, data):
        if self._finished or action != "accuse" or self.phase != "guess":
            return
        if player_id != self.sipahi_id:
            return
        target = data.get("targetID")
        if target not in self.roles:
            return

        self.accused_id = target
        is_correct = target == self.chor_id
        awards = {
            self.sipahi_id: 500 if is_correct else 0,
            self.chor_id: 0 if is_correct else 500,
        }
        for pid, role in self.roles.items():
            if role == "Raja":
                awards[pid] = 1000
            elif role == "Mantri":
                awards[pid] = 800
        for pid, amount in awards.items():
            player = self.room.player(pid)
            if player is not None:
                player.score += amount

        chor_name = self.player_name(self.chor_id)
        sipahi_name = self.player_name(self.sipahi_id)
        self.round_result = (
            f"{sipahi_name} correctly caught {chor_name}!" if is_correct
            else f"{sipahi_name} guessed wrong! {chor_name} got away!")
        self.phase = "reveal"
        self.reveal_until = time.time() + self.REVEAL_SECONDS

    def tick(self, dt):
        if self._finished or self.phase != "reveal" or time.time() < self.reveal_until:
            return
        if self.round >= self.TOTAL_ROUNDS:
            self._finished = True
        else:
            self._deal_round()

    def public_state(self):
        revealed = self.phase == "reveal"
        return {
            "round": self.round,
            "phase": self.phase,
            "roundResult": self.round_result,
            "players": [
                {"id": pid, "name": self.player_name(pid),
                 "role": self.roles.get(pid) if revealed else None,
                 "isAccused": pid == self.accused_id}
                for pid in self.order
            ],
        }

    def private_state(self, player_id):
        player = self.room.player(player_id)
        return {
            "role": self.roles.get(player_id, ""),
            "phase": self.phase,
            "players": [{"id": pid, "name": self.player_name(pid)} for pid in self.order],
            "score": player.score if player else 0,
            "hasGuessed": self.accused_id is not None,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Trivia -- no reusable server logic in games/trivia (it calls a Gemini API
# for questions); question bank and round loop are original, built to
# TVTriviaBoardView/TriviaControllerView's contract.
# ---------------------------------------------------------------------------

TRIVIA_QUESTIONS = [
    ("Science", "What planet is known as the Red Planet?",
     ["Mars", "Venus", "Jupiter", "Saturn"], 0),
    ("Science", "What gas do plants absorb from the atmosphere?",
     ["Oxygen", "Carbon Dioxide", "Nitrogen", "Hydrogen"], 1),
    ("Geography", "What is the longest river in the world?",
     ["Amazon", "Nile", "Yangtze", "Mississippi"], 1),
    ("Geography", "Which country has the most population?",
     ["USA", "Indonesia", "India", "Brazil"], 2),
    ("History", "In what year did World War II end?",
     ["1943", "1945", "1947", "1950"], 1),
    ("History", "Who was the first President of the United States?",
     ["Lincoln", "Jefferson", "Washington", "Adams"], 2),
    ("Sports", "How many players are on a football (soccer) team on the field?",
     ["9", "10", "11", "12"], 2),
    ("Sports", "In which sport would you perform a slam dunk?",
     ["Tennis", "Basketball", "Golf", "Cricket"], 1),
    ("Movies", "Which movie features a character named Jack Dawson?",
     ["Titanic", "Avatar", "Inception", "Gladiator"], 0),
    ("Music", "How many strings does a standard guitar have?",
     ["4", "5", "6", "7"], 2),
    ("General", "What is the capital of Japan?",
     ["Seoul", "Beijing", "Tokyo", "Bangkok"], 2),
    ("General", "How many continents are there on Earth?",
     ["5", "6", "7", "8"], 2),
    ("Science", "What is the chemical symbol for gold?",
     ["Au", "Ag", "Gd", "Go"], 0),
    ("Science", "What force pulls objects toward the Earth?",
     ["Magnetism", "Gravity", "Friction", "Tension"], 1),
    ("Geography", "Mount Everest is located in which mountain range?",
     ["Andes", "Alps", "Himalayas", "Rockies"], 2),
]


class TriviaEngine(NativeGameEngine):
    game_id = "trivia"
    min_players = 2
    max_players = 10

    # Reported directly: only 8 of the bank's 15 questions were ever played
    # per game. Using the whole bank means every question gets a turn
    # instead of the game always cutting off partway through it.
    TOTAL_ROUNDS = len(TRIVIA_QUESTIONS)
    ROUND_SECONDS = 20
    REVEAL_DELAY_SECONDS = 1.3
    # How long the correct answer stays up before the next question loads --
    # a real reveal beat, not an instant cut. See `phase` below for why this
    # exists at all.
    REVEAL_HOLD_SECONDS = 3.0

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.round = 0
        self.pool: list[tuple] = []
        self.question: tuple | None = None
        self.question_id = ""
        self.deadline = 0.0
        self.choices_at = 0.0
        self.answered: dict[str, int] = {}
        self.scores: dict[str, int] = {}
        # "answering" while the round timer is live, "reveal" for the beat
        # after it ends where the correct choice is shown. public_state()
        # only includes correctIndex during "reveal" -- it used to be sent
        # unconditionally on every single push, including the very first
        # one for a brand new question, so the TV painted the correct
        # answer green the instant the choices appeared, well before anyone
        # had answered or the timer had run down. Reported directly as
        # "answers are getting revealed way before the questions."
        self.phase = "answering"
        self.reveal_until = 0.0
        self._finished = False

    def start(self, players):
        self.scores = {p.id: 0 for p in players}
        pool = questions_for(getattr(self.room, "content_pack", "en"), "trivia")
        self.pool = random.sample(pool, min(self.TOTAL_ROUNDS, len(pool)))
        self.round = 0
        self._next_question()

    def _next_question(self):
        self.round += 1
        self.question = self.pool[(self.round - 1) % len(self.pool)]
        self.question_id = f"q{self.round}"
        self.answered = {}
        self.phase = "answering"
        now = time.time()
        self.deadline = now + self.ROUND_SECONDS
        self.choices_at = now + self.REVEAL_DELAY_SECONDS

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def handle_action(self, player_id, action, data):
        if self._finished or action != "answer" or player_id in self.answered:
            return
        if data.get("questionID") != self.question_id:
            return
        idx = data.get("choiceIndex")
        if not isinstance(idx, int):
            return
        self.answered[player_id] = idx
        _, _, _, correct_index = self.question
        if idx == correct_index:
            elapsed = time.time() - (self.deadline - self.ROUND_SECONDS)
            points = max(20, 100 - int(elapsed * 4))
            self.scores[player_id] = self.scores.get(player_id, 0) + points
            player = self.room.player(player_id)
            if player is not None:
                player.score = self.scores[player_id]

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        if self.phase == "reveal":
            # Holding here, rather than advancing the instant the timer or
            # every answer comes in, is what actually gives the reveal beat
            # above a duration to be seen for.
            if now >= self.reveal_until:
                if self.round >= self.TOTAL_ROUNDS:
                    self._finished = True
                else:
                    self._next_question()
            return

        active = self.room.connected_players()
        everyone_answered = bool(active) and all(p.id in self.answered for p in active)
        if now >= self.deadline or everyone_answered:
            self.phase = "reveal"
            self.reveal_until = now + self.REVEAL_HOLD_SECONDS

    def public_state(self):
        category, text, choices, correct_index = self.question
        state = {
            "secondsLeft": self.seconds_left(),
            "showChoices": time.time() >= self.choices_at,
            "questionID": self.question_id,
            "questionText": text,
            "choices": choices,
            "category": category,
            "phase": self.phase,
            "answeredPlayerIDs": list(self.answered.keys()),
            "players": [
                {"id": p.id, "name": p.name, "score": self.scores.get(p.id, 0), "isHost": p.is_host}
                for p in self.room.players
            ],
            "finished": self._finished,
        }
        # Only present once the reveal phase actually starts -- see the
        # `phase` doc comment in __init__ for why this can't just be sent
        # unconditionally.
        if self.phase == "reveal":
            state["correctIndex"] = correct_index
        return state

    def private_state(self, player_id):
        _, _, choices, _ = self.question
        return {
            "choices": choices,
            "questionID": self.question_id,
            "score": self.scores.get(player_id, 0),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.scores)


ENGINES = {
    "mafia": MafiaEngine,
    "raja_mantri": RajaMantriEngine,
    "trivia": TriviaEngine,
}
