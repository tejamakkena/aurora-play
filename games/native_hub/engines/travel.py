"""Travel Mode engines: conversational, voice-first party games.

Travel Mode is one phone hosting in a car: audio plays through the car
speakers, a passenger operates the phone, and the driver plays BY VOICE
ONLY. Every game here is fully playable without looking at a screen --
the host reads the ``hostPrompt`` field of ``public_state()`` aloud (or
AVSpeechSynthesizer speaks it), so all prompt text is written for
text-to-speech: short sentences, no emojis, no abbreviations that read
badly (no "w/"), no stage directions, no markdown, family-friendly.

The ordered queue for a drive is TRAVEL_PLAYLIST; ``next_travel_game()``
advances it. A drive through the whole list is:

    trivia -> most_likely_to -> story_chain -> twenty_questions -> hot_takes

Games in this module:

  story_chain      -- players take turns adding one sentence to a growing
                      story; each player adds two sentences, then everyone
                      votes for the funniest contributor and points are
                      awarded.
  twenty_questions -- the engine picks a secret thing (places, foods,
                      movies, animals); players ask yes or no questions
                      (max 20), the host records yes or no answers, and a
                      correct guess scores. Give up to reveal.
  hot_takes        -- debate prompts with a 90 second discussion timer;
                      the host then awards points to the most convincing
                      arguer.
"""

import random
import time

from games import content_service as cs
from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines._bases import RoundBasedEngine
from utils.room_manager import Player

# ---------------------------------------------------------------------------
# Travel playlist
# ---------------------------------------------------------------------------

#: The ordered queue of games for a drive. Keep this short on purpose: a
#: playlist is a list, not a scheduler. ``next_travel_game`` walks it and
#: wraps around when it reaches the end.
TRAVEL_PLAYLIST = [
    "trivia",
    "most_likely_to",
    "story_chain",
    "twenty_questions",
    "hot_takes",
]


def next_travel_game(current_id: str | None = None) -> str:
    """Return the game that follows ``current_id`` in the travel playlist.

    ``None`` (or an id not in the playlist) starts at the beginning; the
    end wraps back to the start.
    """
    if current_id in TRAVEL_PLAYLIST:
        idx = (TRAVEL_PLAYLIST.index(current_id) + 1) % len(TRAVEL_PLAYLIST)
    else:
        idx = 0
    return TRAVEL_PLAYLIST[idx]


# ---------------------------------------------------------------------------
# story_chain
# ---------------------------------------------------------------------------

STORY_SENTENCES_PER_PLAYER = 2
STORY_TURN_SECONDS = 60
STORY_POINTS_PER_VOTE = 100
STORY_FUNNIEST_BONUS = 250
STORY_POINTS_PER_SENTENCE = 50


class StoryChainEngine(NativeGameEngine):
    """Build a story one sentence at a time, then vote for the funniest.

    Play: players rotate, each adding one spoken sentence per turn (the
    passenger taps it into the phone for the driver). After every player
    has added STORY_SENTENCES_PER_PLAYER sentences the vote phase opens:
    everyone votes for the funniest contributor, secret ballot until
    reveal. Each vote is worth points and the top-voted player gets a
    bonus.

    Car play: the host reads the story so far aloud before each turn, so
    the driver can follow the whole tale by ear.
    """

    game_id = "story_chain"
    min_players = 2
    max_players = 8

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.turn_index = 0
        self.story: list[dict] = []        # {"playerID", "name", "text"}
        self.votes: dict[str, str] = {}   # voter_id -> target_id
        self.round_results: list[dict] = []
        self.scores: dict[str, int] = {}
        self.phase = "adding"
        self.deadline = 0.0
        self._finished = False

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players: list[Player]) -> None:
        self.order = [p.id for p in players]
        self.scores = {p.id: 0 for p in players}
        self.turn_index = 0
        self.story = []
        self.votes = {}
        self.round_results = []
        self.phase = "adding"
        self._finished = False
        self._reset_turn_clock()

    @property
    def target_sentences(self) -> int:
        return len(self.order) * STORY_SENTENCES_PER_PLAYER

    def _reset_turn_clock(self) -> None:
        self.deadline = time.time() + STORY_TURN_SECONDS

    def seconds_left(self) -> int:
        if not self.deadline:
            return 0
        return max(0, int(round(self.deadline - time.time())))

    # ---- turns -------------------------------------------------------------

    def _is_live(self, player_id: str) -> bool:
        player = self.room.player(player_id)
        return player is not None and player.connected

    def current_player_id(self) -> str | None:
        live = [pid for pid in self.order if self._is_live(pid)]
        if not live:
            return None
        return self.order[self.turn_index % len(self.order)]

    def is_my_turn(self, player_id: str) -> bool:
        return self.current_player_id() == player_id

    def _advance_turn(self) -> None:
        for _ in range(len(self.order)):
            self.turn_index = (self.turn_index + 1) % len(self.order)
            if self._is_live(self.order[self.turn_index]):
                break
        self._reset_turn_clock()

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if self._finished:
            return
        if action == "add_sentence":
            self._add_sentence(player_id, data)
        elif action == "vote":
            self._vote(player_id, data)
        elif action == "reveal":
            self._reveal(player_id)

    def _add_sentence(self, player_id: str, data: dict) -> None:
        if self.phase != "adding":
            return
        if not self.is_my_turn(player_id):
            return
        text = str(data.get("sentence", "")).strip()
        if not text or len(text) > 300:
            return
        player = self.room.player(player_id)
        self.story.append({
            "playerID": player_id,
            "name": player.name if player else "Player",
            "text": text,
        })
        self.scores[player_id] = self.scores.get(player_id, 0) + STORY_POINTS_PER_SENTENCE
        if player is not None:
            player.score = self.scores[player_id]
        if len(self.story) >= self.target_sentences:
            self.phase = "vote"
            self.deadline = 0.0
        else:
            self._advance_turn()

    def _vote(self, player_id: str, data: dict) -> None:
        if self.phase != "vote":
            return
        if self.room.player(player_id) is None:
            return
        target = data.get("targetID")
        if target == player_id:
            return                             # no self-votes
        if target not in self.scores:
            return                             # unknown or departed player
        self.votes[player_id] = target

    def _reveal(self, player_id: str) -> None:
        if self.phase != "vote":
            return
        player = self.room.player(player_id)
        everyone_voted = all(
            pid in self.votes
            for pid in self.order if self._is_live(pid)
        )
        if player is not None and (player.is_host or everyone_voted):
            self._tally_and_finish()

    def _tally_and_finish(self) -> None:
        counts: dict[str, int] = {}
        for target in self.votes.values():
            if target not in self.scores:
                continue                       # target left mid-vote
            counts[target] = counts.get(target, 0) + 1
        top = max(counts.values()) if counts else 0
        self.round_results = [
            {"playerID": tid, "name": self.player_name(tid),
             "votes": n, "funniest": n == top and n > 0}
            for tid, n in sorted(counts.items(), key=lambda kv: kv[1], reverse=True)
        ]
        for tid, n in counts.items():
            self._award(tid, STORY_POINTS_PER_VOTE * n)
            if n == top and n > 0:
                self._award(tid, STORY_FUNNIEST_BONUS)
        self.phase = "final"
        self.deadline = 0.0
        self._finished = True

    def _award(self, player_id: str, points: int) -> None:
        self.scores[player_id] = self.scores.get(player_id, 0) + points
        player = self.room.player(player_id)
        if player is not None:
            player.score = self.scores[player_id]

    # ---- timer -------------------------------------------------------------

    def tick(self, dt: float) -> None:
        if self._finished or self.phase != "adding":
            return
        if self.deadline and time.time() >= self.deadline:
            # A slow turn should not stall the drive: skip to the next player.
            self._advance_turn()

    # ---- state -------------------------------------------------------------

    def _host_prompt(self) -> str:
        if self.phase == "adding":
            name = self.player_name(self.current_player_id() or "")
            story_text = " ".join(s["text"] for s in self.story)
            if story_text:
                return (f"It is {name}'s turn. The story so far: {story_text} "
                        f"Add one sentence.")
            return f"It is {name}'s turn. Start the story with one sentence."
        if self.phase == "vote":
            return ("The story is done. Vote for the funniest contributor. "
                    "No voting for yourself.")
        return "The votes are in. Here are the results."

    def _scoreboard(self) -> list[dict]:
        return [
            {"id": p.id, "name": p.name,
             "score": self.scores.get(p.id, 0), "isHost": p.is_host}
            for p in self.room.players
        ]

    def public_state(self) -> dict:
        return {
            "phase": self.phase,
            "story": self.story,
            "storyText": " ".join(s["text"] for s in self.story),
            "sentenceCount": len(self.story),
            "targetSentences": self.target_sentences,
            "currentPlayerID": self.current_player_id(),
            "currentPlayerName": self.player_name(self.current_player_id() or ""),
            "secondsLeft": self.seconds_left(),
            "votesSoFar": len(self.votes),
            "roundResults": self.round_results if self.phase == "final" else [],
            "hostPrompt": self._host_prompt(),
            "players": self._scoreboard(),
        }

    def private_state(self, player_id: str) -> dict:
        return {
            "phase": self.phase,
            "isMyTurn": self.is_my_turn(player_id),
            "hasVoted": player_id in self.votes,
            "myVoteTargetID": self.votes.get(player_id),
            "secondsLeft": self.seconds_left(),
            "score": self.scores.get(player_id, 0),
        }

    def is_over(self) -> bool:
        return self._finished

    def results(self) -> list[dict]:
        return self.ranked_results(self.scores)

    def on_player_leave(self, player_id: str) -> None:
        self.votes.pop(player_id, None)
        if self.current_player_id() == player_id and self.phase == "adding":
            self._advance_turn()


# ---------------------------------------------------------------------------
# twenty_questions
# ---------------------------------------------------------------------------

TWENTY_MAX_QUESTIONS = 20
TWENTY_BASE_POINTS = 200
TWENTY_POINTS_PER_UNUSED = 10

#: The secret things. Short names that read well aloud and are familiar to
#: every age group. Four categories of fifteen each. This is the OFFLINE
#: fallback; with a Travel Mode topic set, secrets are generated fresh by
#: games/topic_gen.py instead.
TWENTY_THINGS: dict[str, list[str]] = {
    "places": [
        "Eiffel Tower", "Statue of Liberty", "Great Wall of China",
        "Taj Mahal", "Pyramids of Giza", "Sydney Opera House",
        "Big Ben", "Grand Canyon", "Niagara Falls", "Mount Everest",
        "Sahara Desert", "Amazon Rainforest", "Golden Gate Bridge",
        "Burj Khalifa", "The Colosseum",
    ],
    "foods": [
        "Pizza", "Ice cream", "Popcorn", "Mango", "Watermelon",
        "Chocolate cake", "Pancakes", "Spaghetti", "Hamburger",
        "Apple pie", "French fries", "Sushi", "Tacos", "Donuts",
        "Sandwich",
    ],
    "movies": [
        "Frozen", "Toy Story", "The Lion King", "Harry Potter",
        "Titanic", "Jaws", "E.T.", "Jurassic Park", "Star Wars",
        "Avatar", "Finding Nemo", "Spider-Man", "The Avengers",
        "Home Alone", "Shrek",
    ],
    "animals": [
        "Elephant", "Kangaroo", "Penguin", "Giraffe", "Lion",
        "Tiger", "Dolphin", "Polar bear", "Owl", "Parrot",
        "Monkey", "Horse", "Octopus", "Crocodile", "Sloth",
    ],
}


def _normalize(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum())


class TwentyQuestionsEngine(NativeGameEngine):
    """Twenty questions, voice-first.

    Play: the engine picks a secret thing and each round a different
    player is the answerer -- they see the secret on the phone and the
    car speakers read the questions. Everyone else takes turns asking yes
    or no questions (the driver asks by voice, the passenger taps the
    question in). The host records each answer with the yes or no
    buttons. Anyone can guess at any time; a correct guess scores more
    when fewer questions were asked. Give up to reveal the answer.

    Answers are limited to yes or no -- the host says "I do not know"
    out loud for anything else and does not press a button.
    """

    game_id = "twenty_questions"
    min_players = 2
    max_players = 8

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.scores: dict[str, int] = {}
        self.total_rounds = 0
        self.round = 0
        self.answerer_id: str | None = None
        self.category = ""
        self.secret = ""
        self.used: set[tuple[str, str]] = set()
        self.questions: list[dict] = []     # {"text", "answer": "yes"/"no"/None}
        self.phase = "play"                 # "play" | "reveal"
        self.revealed = False
        self._finished = False

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players: list[Player]) -> None:
        self.order = [p.id for p in players]
        self.scores = {p.id: 0 for p in players}
        self.total_rounds = len(self.order)
        self.round = 0
        self.used = set()
        self._finished = False
        self._next_round()

    def _pick_secret(self) -> tuple[str, str]:
        # Travel Mode topic: generate a fresh secret on the passenger's
        # topic. Any failure drops through to the bundled things.
        topic = (getattr(self.room, "topic", "") or "").strip()
        if topic:
            try:
                from games import topic_gen
                seen = [item for _cat, item in self.used]
                secrets = topic_gen.get_secrets(topic, 1, session_history=seen)
                if secrets:
                    secret = secrets[0]
                    # A bundled fallback secret belongs to its real
                    # category; only fresh generations use the topic.
                    category = topic
                    for cat, items in TWENTY_THINGS.items():
                        if secret in items:
                            category = cat
                            break
                    self.used.add((category, secret))
                    return category, secret
            except Exception:
                pass
        pool = [(cat, item)
                for cat, items in TWENTY_THINGS.items()
                for item in items
                if (cat, item) not in self.used]
        if not pool:
            self.used.clear()
            pool = [(cat, item)
                    for cat, items in TWENTY_THINGS.items()
                    for item in items]
        category, secret = random.choice(pool)
        self.used.add((category, secret))
        return category, secret

    def _next_round(self) -> None:
        if self.round >= self.total_rounds:
            self._finished = True
            self.phase = "final"
            self.secret = ""
            return
        self.round += 1
        self.answerer_id = self.order[self.round - 1]
        self.category, self.secret = self._pick_secret()
        self.questions = []
        self.phase = "play"
        self.revealed = False

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if self._finished:
            return
        if action == "question":
            self._ask(player_id, data)
        elif action == "answer":
            self._answer(player_id, data)
        elif action == "guess":
            self._guess(player_id, data)
        elif action == "give_up":
            self._give_up(player_id)
        elif action == "next_round":
            self._host_next(player_id)

    def _ask(self, player_id: str, data: dict) -> None:
        if self.phase != "play":
            return
        if player_id == self.answerer_id:
            return                            # the answerer does not ask
        if self.room.player(player_id) is None:
            return
        if len(self.questions) >= TWENTY_MAX_QUESTIONS:
            return
        if self.questions and self.questions[-1]["answer"] is None:
            return                            # wait for the pending answer
        text = str(data.get("text", "")).strip()
        if not text or len(text) > 200:
            return
        self.questions.append({"text": text, "answer": None,
                               "playerID": player_id,
                               "name": self.player_name(player_id)})

    def _answer(self, player_id: str, data: dict) -> None:
        if self.phase != "play":
            return
        if player_id != self.answerer_id:
            return                            # only the answerer answers
        if not self.questions or self.questions[-1]["answer"] is not None:
            return
        value = str(data.get("value", "")).lower().strip()
        if value not in ("yes", "no"):
            return
        self.questions[-1]["answer"] = value
        if len(self.questions) >= TWENTY_MAX_QUESTIONS:
            # Out of questions with no correct guess: reveal the answer.
            self.phase = "reveal"
            self.revealed = True

    def _guess(self, player_id: str, data: dict) -> None:
        if self.phase != "play":
            return
        if player_id == self.answerer_id:
            return                            # the answerer cannot guess
        if self.room.player(player_id) is None:
            return
        text = str(data.get("text", "")).strip()
        if not text:
            return
        if _normalize(text) == _normalize(self.secret):
            asked = len(self.questions)
            points = TWENTY_BASE_POINTS + TWENTY_POINTS_PER_UNUSED * (TWENTY_MAX_QUESTIONS - asked)
            self.scores[player_id] = self.scores.get(player_id, 0) + points
            player = self.room.player(player_id)
            if player is not None:
                player.score = self.scores[player_id]
            self.phase = "reveal"
            self.revealed = True

    def _give_up(self, player_id: str) -> None:
        if self.phase != "play":
            return
        if self.room.player(player_id) is None:
            return
        self.phase = "reveal"
        self.revealed = True

    def _host_next(self, player_id: str) -> None:
        if self.phase != "reveal":
            return
        player = self.room.player(player_id)
        if player is not None and player.is_host:
            self._next_round()

    # ---- state -------------------------------------------------------------

    def _host_prompt(self) -> str:
        if self.phase == "play":
            n = len(self.questions)
            return (f"Round {self.round}. The category is {self.category}. "
                    f"{TWENTY_MAX_QUESTIONS - n} questions left. "
                    f"{self.player_name(self.answerer_id or '')} knows the answer. "
                    "Ask a yes or no question.")
        if self.phase == "reveal":
            return (f"The secret was {self.secret}. "
                    "Host, move to the next round when ready.")
        return "Game over. Here are the final scores."

    def _scoreboard(self) -> list[dict]:
        return [
            {"id": p.id, "name": p.name,
             "score": self.scores.get(p.id, 0), "isHost": p.is_host}
            for p in self.room.players
        ]

    def public_state(self) -> dict:
        state = {
            "phase": self.phase,
            "round": self.round,
            "totalRounds": self.total_rounds,
            "answererID": self.answerer_id,
            "answererName": self.player_name(self.answerer_id or ""),
            "category": self.category,
            "questions": [{"text": q["text"], "answer": q["answer"]}
                          for q in self.questions],
            "questionsAsked": len(self.questions),
            "questionsLeft": max(0, TWENTY_MAX_QUESTIONS - len(self.questions)),
            "hostPrompt": self._host_prompt(),
            "players": self._scoreboard(),
        }
        # The secret only goes public once the round is revealed.
        if self.phase == "reveal":
            state["secret"] = self.secret
        return state

    def private_state(self, player_id: str) -> dict:
        state = {
            "phase": self.phase,
            "round": self.round,
            "category": self.category,
            "isAnswerer": player_id == self.answerer_id,
            "questionsLeft": max(0, TWENTY_MAX_QUESTIONS - len(self.questions)),
            "score": self.scores.get(player_id, 0),
        }
        # Only the answerer ever sees the secret.
        if player_id == self.answerer_id:
            state["secret"] = self.secret
        return state

    def is_over(self) -> bool:
        return self._finished

    def results(self) -> list[dict]:
        return self.ranked_results(self.scores)

    def on_player_leave(self, player_id: str) -> None:
        if self.phase == "play" and player_id == self.answerer_id:
            # The answerer left: reveal the answer so the round can move on.
            self.phase = "reveal"
            self.revealed = True


# ---------------------------------------------------------------------------
# hot_takes
# ---------------------------------------------------------------------------

#: The bundled debate prompts. These are the OFFLINE fallback; with a
#: Travel Mode topic set, prompts are generated fresh by games/topic_gen.py.
HOT_TAKES = [
    "Is a hot dog a sandwich?",
    "Does pineapple belong on pizza?",
    "Is cereal a soup?",
    "Should the toilet paper roll hang over or under?",
    "Is a tomato a fruit or a vegetable in your kitchen?",
    "Are you a morning person or a night owl?",
    "Is it ever okay to put ketchup on a steak?",
    "Are road trips better than flights?",
    "Should you text or call when running late?",
    "Is the best seat in the car the driver seat or the back seat?",
    "Does money buy happiness?",
    "Are cats or dogs better pets?",
    "Should everyone learn to cook?",
    "Is winter or summer the better season?",
    "Is it better to be early or fashionably late?",
    "Do leftovers taste better the next day?",
    "Should phones be banned at the dinner table?",
    "Is a nap better than coffee?",
    "Are movie theaters better than streaming at home?",
    "Does the driver always pick the music?",
]

HOT_TAKES_ROUNDS = 5
HOT_TAKES_AWARD_POINTS = 200


class HotTakesEngine(RoundBasedEngine):
    """Debate prompts with a 90 second timer.

    Play: each round the host reads the hot take aloud (the car speakers
    read it too), then everyone argues their side for 90 seconds. When
    the timer ends, the host awards points to the most convincing
    arguer. Five rounds, no repeated prompts, highest score wins.

    Car play: the driver argues by voice; the passenger holds the phone
    and the host taps the winner when time is up.
    """

    game_id = "hot_takes"
    min_players = 2
    max_players = 8
    total_rounds = HOT_TAKES_ROUNDS
    first_phase = "discuss"
    phase_seconds = {"discuss": 90, "award": 60}

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.prompt = ""
        self.used: set[str] = set()       # normalized prompts asked this game
        self.awarded_to: str | None = None

    def begin_phase(self, phase: str) -> None:
        if phase == "discuss":
            prompt = self._topic_prompt()
            if prompt is None:
                prompt = cs.pick_one(self.room, "hot_take", avoid=self.used)
            self.prompt = prompt
            # Topic prompts count too: they used to be left out, so the
            # topic cache handed back the same first prompt every round.
            self.used.add(cs.norm_key(prompt))
            self.awarded_to = None
        elif phase == "award":
            self.awarded_to = None

    def _topic_prompt(self) -> str | None:
        """A fresh debate prompt on the room's Travel Mode topic.

        Returns None when there is no topic or generation yields nothing,
        so begin_phase falls back to the bundled prompts.
        """
        topic = (getattr(self.room, "topic", "") or "").strip()
        if not topic:
            return None
        try:
            from games import topic_gen
            seen = list(self.used)
            takes = topic_gen.get_hot_takes(topic, 1, session_history=seen)
            return takes[0] if takes else None
        except Exception:
            return None

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if self._finished or action != "award" or self.phase != "award":
            return
        if self.awarded_to is not None:
            return                            # one award per round
        player = self.room.player(player_id)
        if player is None:
            return
        # The host awards; if nobody is flagged host, anyone may award.
        hosts = [p for p in self.room.players if p.is_host]
        if hosts and player_id != hosts[0].id:
            return
        target = data.get("targetID")
        if target not in self.scores:
            return                            # unknown or departed player
        self.awarded_to = target
        self.award(target, HOT_TAKES_AWARD_POINTS)
        # Do not wait out the rest of the clock once the winner is picked.
        self.advance()

    def resolve_phase(self, phase: str) -> str | None:
        if phase == "discuss":
            return "award"
        return None

    def _host_prompt(self) -> str:
        if self.phase == "discuss":
            return (f"Round {self.round}. The hot take: {self.prompt} "
                    "You have 90 seconds. Argue your case.")
        if self.phase == "award":
            return "Time is up. Host, award 200 points to the most convincing arguer."
        return "All rounds are done. Here are the final scores."

    def public_state(self) -> dict:
        state = self.base_public()
        state.update({
            "prompt": self.prompt,
            "awardedToID": self.awarded_to,
            "awardedToName": self.player_name(self.awarded_to) if self.awarded_to else "",
            "awardPoints": HOT_TAKES_AWARD_POINTS,
            "hostPrompt": self._host_prompt(),
        })
        return state

    def private_state(self, player_id: str) -> dict:
        state = self.base_private(player_id)
        state.update({
            "prompt": self.prompt,
            "awardedToID": self.awarded_to,
        })
        return state


ENGINES = {
    "story_chain": StoryChainEngine,
    "twenty_questions": TwentyQuestionsEngine,
    "hot_takes": HotTakesEngine,
}
