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

twenty_questions and hot_takes started here too; they are now TV + phone
party games in ``talk.py``. Their names are re-exported below so older
imports (``from ...engines.travel import HOT_TAKES``) keep working.
"""

import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines.talk import (  # noqa: F401  (re-exported)
    HOT_TAKES,
    TWENTY_MAX_QUESTIONS,
    TWENTY_THINGS,
    HotTakesEngine,
    TwentyQuestionsEngine,
)
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


ENGINES = {
    "story_chain": StoryChainEngine,
}
