"""Talk games: party games played OUT LOUD in front of the TV.

The phones only carry what a player needs privately (your side and some
argument starters, the secret word, a vote, a guess box); the talking
happens in the room. Both games used to be voice-first Travel Mode games
hosted on one phone in a car; they are now proper TV + phone games.

  hot_takes        -- two players debate a spicy-but-family-friendly prompt,
                      one FOR and one AGAINST, 30 seconds each, then the rest
                      of the room votes for who argued better.
  twenty_questions -- one player (the Answerer) holds a secret word; the room
                      asks yes or no questions out loud and the Answerer taps
                      YES / NO / SOMETIMES. Anyone can tap "I know it!" and
                      type a guess.

Every public_state carries ``phase``, ``deadline`` (epoch seconds, 0 when
untimed), ``secondsLeft`` and ``phaseSeconds`` so the TV can draw smooth
countdowns, plus ``hostPrompt``: a short TTS-clean line the TV may speak.
"""

import difflib
import random
import time

from games import content_service as cs
from games.native_hub.engines._bases import RoundBasedEngine
from games.native_hub.engines._matching import normalise

# ---------------------------------------------------------------------------
# hot_takes content
# ---------------------------------------------------------------------------

#: Bundled debate prompts (content_service kind "hot_take" also reads these,
#: plus games/content_library/hot_take.json). Yes or no questions read best
#: as a FOR / AGAINST debate; either-or prompts are kept for the other modes
#: that use the kind but are avoided here when possible.
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

#: Argument starters shown on the debaters' phones. Three of these are dealt
#: to each debater per round; they are deliberately generic so they fit any
#: prompt.
ARGUMENT_STARTERS = {
    "for": [
        "Think about how much happier everyone would be.",
        "History is clearly on my side here.",
        "Ask anyone who has actually tried it.",
        "Here is something nobody ever talks about.",
        "Imagine a world without it. Sad, right?",
        "My grandmother would agree, and she is always right.",
        "It saves time, money and arguments.",
        "Even scientists secretly agree with me.",
        "Kids love it, and kids are honest.",
        "It is simply the more fun option.",
    ],
    "against": [
        "That sounds nice, but here is the problem.",
        "Let us be honest for a second.",
        "Picture the chaos if everyone did that.",
        "My opponent forgot one tiny detail.",
        "Nobody has ever said that and meant it.",
        "It is a trend, and trends fade.",
        "Think about who has to clean up afterwards.",
        "There is a reason it was never popular.",
        "Ask yourself: who actually benefits?",
        "Just because you can does not mean you should.",
    ],
}

HOT_TAKES_SIDE_SECONDS = 30
HOT_TAKES_INTRO_SECONDS = 8
HOT_TAKES_SWITCH_SECONDS = 3
HOT_TAKES_VOTE_SECONDS = 20
HOT_TAKES_REVEAL_SECONDS = 9

HOT_TAKES_WIN_POINTS = 500
HOT_TAKES_TIE_POINTS = 250
HOT_TAKES_POINTS_PER_VOTE = 50
HOT_TAKES_LANDSLIDE_BONUS = 250
#: A landslide is at least this share of the votes (and at least two votes).
HOT_TAKES_LANDSLIDE_SHARE = 0.75

HOT_TAKES_MIN_ROUNDS = 3
HOT_TAKES_MAX_ROUNDS = 8


def is_either_or(prompt: str) -> bool:
    """True for "X or Y?" prompts, which do not split into FOR / AGAINST."""
    return " or " in f" {str(prompt).lower()} "


def side_labels(prompt: str) -> tuple[str, str]:
    """What each side argues: "YES" / "NO", or the two options of an
    either-or prompt when it cannot be avoided."""
    if is_either_or(prompt):
        return ("FIRST OPTION", "SECOND OPTION")
    return ("YES", "NO")


# ---------------------------------------------------------------------------
# hot_takes engine
# ---------------------------------------------------------------------------

class HotTakesEngine(RoundBasedEngine):
    """A debate party game.

    Round flow:
      intro   -- the TV shows the prompt and the two debaters; their phones
                 show their side and argument starters.
      for     -- the FOR debater argues out loud (30 s).
      switch  -- a short "Switch!" beat on the TV.
      against -- the AGAINST debater argues out loud (30 s).
      vote    -- everyone except the debaters votes for who argued better.
      reveal  -- the TV reveals the votes; the winner scores, with a bonus
                 for a landslide.

    A debater may tap "Done" on the phone to end their 30 seconds early.
    Debaters rotate so everyone debates; rounds = players, clamped to 3..8.
    """

    game_id = "hot_takes"
    min_players = 3
    max_players = 8
    first_phase = "intro"
    phase_seconds = {
        "intro": HOT_TAKES_INTRO_SECONDS,
        "for": HOT_TAKES_SIDE_SECONDS,
        "switch": HOT_TAKES_SWITCH_SECONDS,
        "against": HOT_TAKES_SIDE_SECONDS,
        "vote": HOT_TAKES_VOTE_SECONDS,
        "reveal": HOT_TAKES_REVEAL_SECONDS,
    }
    early_phases = ("vote",)

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.total_rounds = HOT_TAKES_MIN_ROUNDS
        self.order: list[str] = []
        self.prompt = ""
        self.used: set[str] = set()
        self.for_id: str | None = None
        self.against_id: str | None = None
        self.hints: dict[str, list[str]] = {}
        self.votes: dict[str, str] = {}          # voter_id -> "for" | "against"
        self.round_result: dict | None = None
        self.history: list[dict] = []
        self.debates: dict[str, int] = {}        # player_id -> debates so far
        self.last_side: dict[str, str] = {}      # player_id -> "for" | "against"
        self.faced: dict[frozenset, int] = {}    # pair -> times matched

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players) -> None:
        self.order = [p.id for p in players]
        random.shuffle(self.order)
        self.debates = {pid: 0 for pid in self.order}
        self.total_rounds = max(HOT_TAKES_MIN_ROUNDS,
                                min(HOT_TAKES_MAX_ROUNDS, len(self.order)))
        super().start(players)

    def begin_phase(self, phase: str) -> None:
        if phase == "intro":
            self._new_round()
        elif phase == "vote":
            self.votes = {}
            self.submissions = {}

    def _new_round(self) -> None:
        self.prompt = self._pick_prompt()
        self.used.add(cs.norm_key(self.prompt))
        self.for_id, self.against_id = self._pick_debaters()
        self.votes = {}
        self.submissions = {}
        self.round_result = None
        self.hints = {}
        if self.for_id:
            self.hints[self.for_id] = random.sample(ARGUMENT_STARTERS["for"], 3)
        if self.against_id:
            self.hints[self.against_id] = random.sample(ARGUMENT_STARTERS["against"], 3)

    def _pick_prompt(self) -> str:
        """A fresh yes or no prompt; either-or prompts only as a last resort.

        With a room topic set (the host's free-text topic), a freshly
        generated prompt on that topic comes first.
        """
        topical = self._topic_prompt()
        if topical:
            return topical
        items = cs.all_items("hot_take")
        avoid = set(self.used) | {cs.norm_key(p) for p in items if is_either_or(p)}
        prompt = cs.pick_one(self.room, "hot_take", avoid=avoid)
        if not prompt:
            pool = [p for p in HOT_TAKES if cs.norm_key(p) not in self.used] or HOT_TAKES
            prompt = random.choice(pool)
        return prompt

    def _topic_prompt(self) -> str | None:
        """A generated yes or no prompt on the room's topic, or None (no
        topic, generation failed, or it came back either-or / repeated)."""
        topic = (getattr(self.room, "topic", "") or "").strip()
        if not topic:
            return None
        try:
            from games import topic_gen
            takes = topic_gen.get_hot_takes(topic, 1, session_history=list(self.used))
        except Exception:
            return None
        for take in takes or []:
            if take and not is_either_or(take) and cs.norm_key(take) not in self.used:
                return take
        return None

    def _is_live(self, player_id: str | None) -> bool:
        if not player_id:
            return False
        player = self.room.player(player_id)
        return player is not None and player.connected

    def _pick_debaters(self) -> tuple[str | None, str | None]:
        """The two live players who have debated least, preferring a pairing
        that has not happened yet, and alternating sides where possible."""
        live = [pid for pid in self.order if self._is_live(pid)]
        if len(live) < 2:
            return (live[0] if live else None, None)
        rank = {pid: i for i, pid in enumerate(self.order)}
        # Rotate the tie-break by round so the same seat does not always lead.
        offset = (self.round - 1) % len(self.order)

        def seat(pid: str) -> int:
            return (rank[pid] - offset) % len(self.order)

        # Alternate sides where possible: whoever argued FOR last time
        # should argue AGAINST now, and vice versa.
        def repeats(f: str, a: str) -> int:
            return int(self.last_side.get(f) == "for") + int(self.last_side.get(a) == "against")

        def side_cost(x: str, y: str) -> int:
            return min(repeats(x, y), repeats(y, x))

        first = min(live, key=lambda pid: (self.debates.get(pid, 0), seat(pid)))
        second = min((pid for pid in live if pid != first),
                     key=lambda pid: (self.debates.get(pid, 0),
                                      self.faced.get(frozenset((first, pid)), 0),
                                      side_cost(first, pid),
                                      seat(pid)))
        for_id, against_id = first, second
        if repeats(second, first) < repeats(first, second):
            for_id, against_id = second, first
        for pid, side in ((for_id, "for"), (against_id, "against")):
            self.debates[pid] = self.debates.get(pid, 0) + 1
            self.last_side[pid] = side
        pair = frozenset((for_id, against_id))
        self.faced[pair] = self.faced.get(pair, 0) + 1
        return for_id, against_id

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if self._finished or self.room.player(player_id) is None:
            return
        data = data if isinstance(data, dict) else {}
        if action == "vote":
            self._vote(player_id, data)
        elif action == "done_speaking":
            self._done_speaking(player_id)

    def is_voter(self, player_id: str) -> bool:
        return (player_id not in (self.for_id, self.against_id)
                and player_id in self.scores)

    def voters(self) -> list[str]:
        return [p.id for p in self.room.players
                if p.connected and self.is_voter(p.id)]

    def _vote(self, player_id: str, data: dict) -> None:
        if self.phase != "vote" or not self.is_voter(player_id):
            return
        side = data.get("side")
        target = data.get("targetID")
        if side not in ("for", "against"):
            if target and target == self.for_id:
                side = "for"
            elif target and target == self.against_id:
                side = "against"
            else:
                return
        self.votes[player_id] = side
        self.submissions[player_id] = side

    def _done_speaking(self, player_id: str) -> None:
        if self.phase == "for" and player_id == self.for_id:
            self.advance()
        elif self.phase == "against" and player_id == self.against_id:
            self.advance()

    # ---- phases ------------------------------------------------------------

    def everyone_submitted(self) -> bool:
        if self.phase != "vote":
            return False
        return all(pid in self.votes for pid in self.voters())

    def tick(self, dt: float) -> None:
        if self._finished:
            return
        # A debater who left forfeits their turn rather than leaving 30 s of
        # dead air on the TV.
        if self.phase == "for" and not self._is_live(self.for_id):
            self.advance()
            return
        if self.phase == "against" and not self._is_live(self.against_id):
            self.advance()
            return
        super().tick(dt)

    def resolve_phase(self, phase: str) -> str | None:
        if phase == "intro":
            return "for"
        if phase == "for":
            return "switch"
        if phase == "switch":
            return "against"
        if phase == "against":
            return "vote"
        if phase == "vote":
            self._tally()
            return "reveal"
        return None

    def _tally(self) -> None:
        for_votes = sum(1 for side in self.votes.values() if side == "for")
        against_votes = sum(1 for side in self.votes.values() if side == "against")
        total = for_votes + against_votes
        points = {"for": 0, "against": 0}
        winner_side: str | None = None
        landslide = False
        if for_votes > against_votes:
            winner_side = "for"
        elif against_votes > for_votes:
            winner_side = "against"
        if winner_side is not None:
            top = max(for_votes, against_votes)
            landslide = total >= 2 and top / total >= HOT_TAKES_LANDSLIDE_SHARE
            points[winner_side] += HOT_TAKES_WIN_POINTS
            if landslide:
                points[winner_side] += HOT_TAKES_LANDSLIDE_BONUS
        elif total > 0:
            points["for"] += HOT_TAKES_TIE_POINTS
            points["against"] += HOT_TAKES_TIE_POINTS
        points["for"] += HOT_TAKES_POINTS_PER_VOTE * for_votes
        points["against"] += HOT_TAKES_POINTS_PER_VOTE * against_votes
        for side, pid in (("for", self.for_id), ("against", self.against_id)):
            if pid and pid in self.scores and points[side]:
                self.award(pid, points[side])
        winner_id = {"for": self.for_id, "against": self.against_id}.get(winner_side or "")
        self.round_result = {
            "forVotes": for_votes,
            "againstVotes": against_votes,
            "totalVotes": total,
            "winnerSide": winner_side,
            "winnerID": winner_id,
            "winnerName": self.player_name(winner_id) if winner_id else "",
            "tie": winner_side is None,
            "landslide": landslide,
            "forPoints": points["for"],
            "againstPoints": points["against"],
            "voters": [{"playerID": vid, "name": self.player_name(vid), "side": side}
                       for vid, side in self.votes.items()],
        }
        self.history.append({
            "round": self.round,
            "prompt": self.prompt,
            "forID": self.for_id,
            "againstID": self.against_id,
            "winnerID": winner_id,
            "landslide": landslide,
        })

    # ---- state -------------------------------------------------------------

    def speaking_side(self) -> str | None:
        return self.phase if self.phase in ("for", "against") else None

    def debate_seconds_left(self) -> int:
        """Seconds left in the whole 60 s debate (both sides)."""
        if self.phase in ("intro",):
            return 2 * HOT_TAKES_SIDE_SECONDS
        if self.phase == "for":
            return self.seconds_left() + HOT_TAKES_SIDE_SECONDS
        if self.phase == "switch":
            return HOT_TAKES_SIDE_SECONDS
        if self.phase == "against":
            return self.seconds_left()
        return 0

    def _host_prompt(self) -> str:
        names = (self.player_name(self.for_id or ""), self.player_name(self.against_id or ""))
        if self.phase == "intro":
            return (f"Round {self.round}. The hot take: {self.prompt} "
                    f"{names[0]} argues for. {names[1]} argues against.")
        if self.phase == "for":
            return f"{names[0]}, make your case."
        if self.phase == "switch":
            return f"Switch! {names[1]}, your turn."
        if self.phase == "against":
            return f"{names[1]}, fight back."
        if self.phase == "vote":
            return "Time to vote. Who argued better?"
        if self.phase == "reveal":
            result = self.round_result or {}
            if result.get("tie"):
                return "It is a tie!" if result.get("totalVotes") else "No votes this round."
            if result.get("landslide"):
                return f"A landslide for {result.get('winnerName', '')}!"
            return f"{result.get('winnerName', '')} wins the debate!"
        return "That is the last debate. Here are the final scores."

    def scoreboard(self) -> list[dict]:
        return [
            {"id": p.id, "name": p.name, "score": self.scores.get(p.id, 0),
             "isHost": p.is_host, "isBot": p.is_bot, "connected": p.connected}
            for p in self.room.players
        ]

    def public_state(self) -> dict:
        for_label, against_label = side_labels(self.prompt)
        state = self.base_public()
        state.update({
            "deadline": self.deadline,
            "phaseSeconds": self.phase_seconds.get(self.phase, 0),
            "prompt": self.prompt,
            "forLabel": for_label,
            "againstLabel": against_label,
            "forID": self.for_id,
            "forName": self.player_name(self.for_id) if self.for_id else "",
            "againstID": self.against_id,
            "againstName": self.player_name(self.against_id) if self.against_id else "",
            "speakingSide": self.speaking_side(),
            "debateSecondsLeft": self.debate_seconds_left(),
            "debateSeconds": 2 * HOT_TAKES_SIDE_SECONDS,
            "sideSeconds": HOT_TAKES_SIDE_SECONDS,
            # Count only: who voted for whom stays secret until the reveal.
            "votesSoFar": len(self.votes),
            "voterCount": len(self.voters()),
            "roundResult": self.round_result if self.phase == "reveal" else None,
            "hostPrompt": self._host_prompt(),
        })
        return state

    def role_for(self, player_id: str) -> str:
        if player_id == self.for_id:
            return "for"
        if player_id == self.against_id:
            return "against"
        return "voter"

    def private_state(self, player_id: str) -> dict:
        for_label, against_label = side_labels(self.prompt)
        role = self.role_for(player_id)
        state = self.base_private(player_id)
        state.update({
            "deadline": self.deadline,
            "phaseSeconds": self.phase_seconds.get(self.phase, 0),
            "totalRounds": self.total_rounds,
            "myPlayerID": player_id,
            "prompt": self.prompt,
            "role": role,
            "stance": for_label if role == "for" else (against_label if role == "against" else ""),
            "forLabel": for_label,
            "againstLabel": against_label,
            "hints": list(self.hints.get(player_id, [])),
            "isSpeaking": self.speaking_side() is not None and self.speaking_side() == role,
            "forName": self.player_name(self.for_id) if self.for_id else "",
            "againstName": self.player_name(self.against_id) if self.against_id else "",
            "canVote": self.phase == "vote" and self.is_voter(player_id),
            "hasVoted": player_id in self.votes,
            "myVote": self.votes.get(player_id),
            "roundResult": self.round_result if self.phase == "reveal" else None,
        })
        return state

    def on_player_leave(self, player_id: str) -> None:
        super().on_player_leave(player_id)
        self.votes.pop(player_id, None)


# ---------------------------------------------------------------------------
# twenty_questions content
# ---------------------------------------------------------------------------

TWENTY_MAX_QUESTIONS = 20
TWENTY_GUESS_BASE_POINTS = 200
TWENTY_POINTS_PER_REMAINING = 25
TWENTY_WRONG_GUESS_PENALTY = 50
TWENTY_ANSWERER_BONUS = 300
#: The Answerer's "good game": solved somewhere between these questions.
TWENTY_GOOD_GAME_RANGE = (10, 20)

TWENTY_INTRO_SECONDS = 8
TWENTY_ASK_SECONDS = 300
TWENTY_REVEAL_SECONDS = 10

TWENTY_MIN_ROUNDS = 3
TWENTY_MAX_ROUNDS = 6

TWENTY_ANSWERS = ("yes", "no", "sometimes")

#: A bot Answerer waits at least this long after each question is used.
TWENTY_BOT_PACE_SECONDS = 5.0

#: The secret things, by category. Short names that read well aloud and
#: are familiar to every age group.
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
    "objects": [
        "Umbrella", "Toothbrush", "Bicycle", "Telescope", "Guitar",
        "Candle", "Compass", "Hot air balloon", "Rubber duck", "Kite",
        "Alarm clock", "Treasure chest", "Magnifying glass", "Trophy",
        "Light bulb",
    ],
}

#: What the TV shows (and says) for each category.
TWENTY_CATEGORY_LABELS = {
    "animals": "Animal",
    "foods": "Food",
    "places": "Place",
    "movies": "Movie",
    "objects": "Famous object",
}


def twenty_guess_matches(guess, secret) -> bool:
    """Forgiving match for a typed guess: case, punctuation, a leading
    article, spaces, a plural "s" and a small typo are all forgiven."""
    g, a = normalise(guess), normalise(secret)
    if not g or not a:
        return False
    gs, as_ = g.replace(" ", ""), a.replace(" ", "")
    if gs == as_:
        return True
    if gs.rstrip("s") == as_.rstrip("s") and gs.rstrip("s"):
        return True
    if len(as_) >= 5 and difflib.SequenceMatcher(None, gs, as_).ratio() >= 0.85:
        return True
    return False


# ---------------------------------------------------------------------------
# twenty_questions engine
# ---------------------------------------------------------------------------

class TwentyQuestionsEngine(RoundBasedEngine):
    """Twenty yes or no questions, asked out loud.

    Round flow:
      intro  -- the TV names the Answerer and shows the category; only the
                Answerer's phone shows the secret.
      ask    -- players ask yes or no questions OUT LOUD; the Answerer taps
                YES / NO / SOMETIMES. Each tap uses one of 20 questions.
                Anyone else can tap "I know it!" and type a guess: right
                ends the round, wrong costs a small penalty and a question.
      reveal -- the TV reveals the secret.

    Scoring: a correct guess scores TWENTY_GUESS_BASE_POINTS plus
    TWENTY_POINTS_PER_REMAINING for every question left; the Answerer earns
    TWENTY_ANSWERER_BONUS for a "good game" (solved on questions 10 to 20).
    The Answerer rotates; rounds = players, clamped to 3..6.
    """

    game_id = "twenty_questions"
    min_players = 3
    max_players = 8
    first_phase = "intro"
    phase_seconds = {
        "intro": TWENTY_INTRO_SECONDS,
        "ask": TWENTY_ASK_SECONDS,
        "reveal": TWENTY_REVEAL_SECONDS,
    }

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.total_rounds = TWENTY_MIN_ROUNDS
        self.order: list[str] = []
        self.answerer_id: str | None = None
        self.category = ""
        self.secret = ""
        self.used: set[tuple[str, str]] = set()
        self.log: list[dict] = []              # one entry per question used
        self.typing: dict[str, float] = {}     # player_id -> when they buzzed
        self.wrong_guesses: dict[str, int] = {}
        self.round_result: dict | None = None
        self.answered_count: dict[str, int] = {}
        self._last_category: str | None = None
        self.last_event_at = 0.0               # when the last question was used

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players) -> None:
        self.order = [p.id for p in players]
        random.shuffle(self.order)
        self.answered_count = {pid: 0 for pid in self.order}
        self.total_rounds = max(TWENTY_MIN_ROUNDS,
                                min(TWENTY_MAX_ROUNDS, len(self.order)))
        super().start(players)

    def begin_phase(self, phase: str) -> None:
        if phase == "intro":
            self._new_round()
        elif phase == "ask":
            self.last_event_at = time.time()

    def _new_round(self) -> None:
        self.answerer_id = self._pick_answerer()
        self.category, self.secret = self._pick_secret()
        self.log = []
        self.typing = {}
        self.wrong_guesses = {}
        self.round_result = None

    def _is_live(self, player_id: str | None) -> bool:
        if not player_id:
            return False
        player = self.room.player(player_id)
        return player is not None and player.connected

    def _pick_answerer(self) -> str | None:
        """Rotate through the shuffled seat order, skipping anyone who left
        and preferring whoever has answered least."""
        live = [pid for pid in self.order if self._is_live(pid)]
        if not live:
            return None
        rank = {pid: i for i, pid in enumerate(self.order)}
        offset = (self.round - 1) % len(self.order)
        pid = min(live, key=lambda p: (self.answered_count.get(p, 0),
                                       (rank[p] - offset) % len(self.order)))
        self.answered_count[pid] = self.answered_count.get(pid, 0) + 1
        return pid

    def _pick_secret(self) -> tuple[str, str]:
        pool = [(cat, item)
                for cat, items in TWENTY_THINGS.items()
                for item in items
                if (cat, item) not in self.used]
        if not pool:
            self.used.clear()
            pool = [(cat, item) for cat, items in TWENTY_THINGS.items() for item in items]
        # Vary the category round to round: prefer one not used last time.
        fresh = [pair for pair in pool if pair[0] != self._last_category] or pool
        category, secret = random.choice(fresh)
        self.used.add((category, secret))
        self._last_category = category
        return category, secret

    # ---- helpers -----------------------------------------------------------

    @property
    def questions_used(self) -> int:
        return len(self.log)

    @property
    def questions_left(self) -> int:
        return max(0, TWENTY_MAX_QUESTIONS - self.questions_used)

    @property
    def bot_step(self) -> str:
        """Lets a bot Answerer act once per question, not once per phase.

        A bot cannot hear the question, so it is paced: for the first
        TWENTY_BOT_PACE_SECONDS after a question is used the step reads
        "<n>:wait" (the bot policy passes), then "<n>" (the bot answers).
        """
        if time.time() - self.last_event_at < TWENTY_BOT_PACE_SECONDS:
            return f"{self.questions_used}:wait"
        return str(self.questions_used)

    def tally(self) -> dict:
        counts = {a: 0 for a in TWENTY_ANSWERS}
        for entry in self.log:
            if entry["kind"] == "answer":
                counts[entry["answer"]] += 1
        counts["wrongGuesses"] = sum(1 for e in self.log if e["kind"] == "guess")
        return counts

    # ---- actions -----------------------------------------------------------

    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        if self._finished or self.room.player(player_id) is None:
            return
        data = data if isinstance(data, dict) else {}
        if action == "answer":
            self._answer(player_id, data)
        elif action == "buzz":
            self._buzz(player_id)
        elif action == "cancel_buzz":
            self.typing.pop(player_id, None)
        elif action == "guess":
            self._guess(player_id, data)

    def _answer(self, player_id: str, data: dict) -> None:
        if self.phase != "ask" or player_id != self.answerer_id:
            return
        value = str(data.get("value", "")).lower().strip()
        if value not in TWENTY_ANSWERS:
            return
        self.log.append({"n": self.questions_used + 1, "kind": "answer", "answer": value})
        self.last_event_at = time.time()
        if self.questions_used >= TWENTY_MAX_QUESTIONS:
            self._finish_round(solver_id=None)

    def _buzz(self, player_id: str) -> None:
        if self.phase != "ask" or player_id == self.answerer_id:
            return
        self.typing[player_id] = time.time()

    def _guess(self, player_id: str, data: dict) -> None:
        if self.phase != "ask" or player_id == self.answerer_id:
            return
        if player_id not in self.scores:
            return
        text = str(data.get("text", "")).strip()[:60]
        if not text:
            return
        self.typing.pop(player_id, None)
        number = self.questions_used + 1
        if twenty_guess_matches(text, self.secret):
            self._finish_round(solver_id=player_id, number=number, text=text)
            return
        self.log.append({"n": number, "kind": "guess", "text": text,
                         "playerID": player_id, "name": self.player_name(player_id)})
        self.last_event_at = time.time()
        self.wrong_guesses[player_id] = self.wrong_guesses.get(player_id, 0) + 1
        penalty = min(TWENTY_WRONG_GUESS_PENALTY, self.scores.get(player_id, 0))
        if penalty:
            self.award(player_id, -penalty)
        if self.questions_used >= TWENTY_MAX_QUESTIONS:
            self._finish_round(solver_id=None)

    def _finish_round(self, solver_id: str | None, number: int = 0, text: str = "") -> None:
        """Score the round and move to the reveal."""
        self._score_round(solver_id, number, text)
        self.enter_phase("reveal")

    def _score_round(self, solver_id: str | None, number: int = 0, text: str = "") -> None:
        solver_points = 0
        answerer_points = 0
        if solver_id is not None:
            remaining = max(0, TWENTY_MAX_QUESTIONS - number)
            solver_points = TWENTY_GUESS_BASE_POINTS + TWENTY_POINTS_PER_REMAINING * remaining
            self.award(solver_id, solver_points)
            low, high = TWENTY_GOOD_GAME_RANGE
            if (low <= number <= high and self.answerer_id
                    and self.answerer_id in self.scores):
                answerer_points = TWENTY_ANSWERER_BONUS
                self.award(self.answerer_id, answerer_points)
        self.round_result = {
            "secret": self.secret,
            "category": TWENTY_CATEGORY_LABELS.get(self.category, self.category.title()),
            "solved": solver_id is not None,
            "solverID": solver_id,
            "solverName": self.player_name(solver_id) if solver_id else "",
            "guessText": text,
            "questionNumber": number if solver_id else self.questions_used,
            "solverPoints": solver_points,
            "answererID": self.answerer_id,
            "answererName": self.player_name(self.answerer_id) if self.answerer_id else "",
            "answererPoints": answerer_points,
            "goodGame": answerer_points > 0,
        }
        self.typing = {}

    # ---- phases ------------------------------------------------------------

    def everyone_submitted(self) -> bool:
        return False                    # nothing here ends early by consensus

    def tick(self, dt: float) -> None:
        if self._finished:
            return
        if self.phase in ("intro", "ask") and not self._is_live(self.answerer_id):
            # The Answerer left: reveal so the game moves on.
            self._finish_round(solver_id=None)
            return
        # "I know it!" fades if nobody types anything for a while.
        now = time.time()
        for pid, since in list(self.typing.items()):
            if now - since > 30:
                self.typing.pop(pid, None)
        super().tick(dt)

    def resolve_phase(self, phase: str) -> str | None:
        if phase == "intro":
            return "ask"
        if phase == "ask":
            # The round clock ran out with nobody solving it.
            self._score_round(solver_id=None)
            return "reveal"
        return None

    # ---- state -------------------------------------------------------------

    def category_label(self) -> str:
        return TWENTY_CATEGORY_LABELS.get(self.category, self.category.title())

    def _host_prompt(self) -> str:
        name = self.player_name(self.answerer_id) if self.answerer_id else "Someone"
        if self.phase == "intro":
            return (f"Round {self.round}. {name} is thinking of something. "
                    f"The category is: {self.category_label()}.")
        if self.phase == "ask":
            return (f"{self.questions_left} questions left. "
                    "Ask yes or no questions out loud.")
        if self.phase == "reveal":
            result = self.round_result or {}
            if result.get("solved"):
                return (f"{result.get('solverName', '')} got it! "
                        f"It was {self.secret}.")
            return f"Nobody got it. It was {self.secret}."
        return "That is the last round. Here are the final scores."

    def scoreboard(self) -> list[dict]:
        return [
            {"id": p.id, "name": p.name, "score": self.scores.get(p.id, 0),
             "isHost": p.is_host, "isBot": p.is_bot, "connected": p.connected}
            for p in self.room.players
        ]

    def public_state(self) -> dict:
        state = self.base_public()
        state.update({
            "deadline": self.deadline,
            "phaseSeconds": self.phase_seconds.get(self.phase, 0),
            "answererID": self.answerer_id,
            "answererName": self.player_name(self.answerer_id) if self.answerer_id else "",
            "category": self.category_label(),
            "categoryKey": self.category,
            "maxQuestions": TWENTY_MAX_QUESTIONS,
            "questionsUsed": self.questions_used,
            "questionsLeft": self.questions_left,
            "log": [dict(entry) for entry in self.log],
            "tally": self.tally(),
            "typingNames": [self.player_name(pid) for pid in self.typing],
            "typingIDs": list(self.typing),
            "roundResult": self.round_result if self.phase == "reveal" else None,
            "hostPrompt": self._host_prompt(),
        })
        # The secret only goes public once the round is revealed.
        if self.phase == "reveal":
            state["secret"] = self.secret
        return state

    def private_state(self, player_id: str) -> dict:
        is_answerer = player_id == self.answerer_id
        state = self.base_private(player_id)
        state.update({
            "deadline": self.deadline,
            "phaseSeconds": self.phase_seconds.get(self.phase, 0),
            "totalRounds": self.total_rounds,
            "myPlayerID": player_id,
            "isAnswerer": is_answerer,
            "answererName": self.player_name(self.answerer_id) if self.answerer_id else "",
            "category": self.category_label(),
            "questionsUsed": self.questions_used,
            "questionsLeft": self.questions_left,
            "maxQuestions": TWENTY_MAX_QUESTIONS,
            "tally": self.tally(),
            "lastAnswer": next((e["answer"] for e in reversed(self.log)
                                if e["kind"] == "answer"), None),
            "canGuess": self.phase == "ask" and not is_answerer,
            "isTyping": player_id in self.typing,
            "wrongGuesses": self.wrong_guesses.get(player_id, 0),
            "lastWrongGuess": next((e["text"] for e in reversed(self.log)
                                    if e["kind"] == "guess" and e.get("playerID") == player_id),
                                   None),
            "penalty": TWENTY_WRONG_GUESS_PENALTY,
            "roundResult": self.round_result if self.phase == "reveal" else None,
        })
        # Only the Answerer ever sees the secret before the reveal.
        if is_answerer or self.phase == "reveal":
            state["secret"] = self.secret
        return state

    def on_player_leave(self, player_id: str) -> None:
        super().on_player_leave(player_id)
        self.typing.pop(player_id, None)


ENGINES = {
    "hot_takes": HotTakesEngine,
    "twenty_questions": TwentyQuestionsEngine,
}
