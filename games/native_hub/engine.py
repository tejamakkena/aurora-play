"""The game-engine plugin contract.

An engine is pure game logic. It never touches a socket and never sleeps -- it
mutates its own state and lets the broadcaster publish. That keeps every engine
unit-testable without an app context or a socket connection.

All six required methods are called with ``room.lock`` already held by the
caller, so implementations must not re-acquire it and must not block.
"""

import time
from abc import ABC, abstractmethod
from typing import ClassVar

from utils.room_manager import Player, Room


#: The most players a room-wide game seats. These games have no seat limit of
#: their own (everyone answers on their own phone), so the number is only a
#: safety ceiling for a small server. Games with a table or a board (poker,
#: Ludo, chess...) keep their real limits.
ROOM_CAP = 50


class NativeGameEngine(ABC):
    """One instance per active game."""

    game_id: ClassVar[str] = ""
    min_players: ClassVar[int] = 1
    max_players: ClassVar[int] = 8

    #: >0 makes the room pump call ``tick(dt)`` at this rate. Real-time games
    #: (pong, air hockey) use 30; everything else leaves it at 0 and relies on
    #: the 1 Hz baseline pump for countdowns.
    tick_hz: ClassVar[float] = 0.0

    #: True when the host may change how many rounds the game plays (the
    #: lobby's "Rounds" pick, games/native_hub/options.py). Round-based party
    #: games set it; board and solo games, and games whose rounds follow the
    #: player count so everybody gets a turn, leave it off.
    rounds_adjustable: ClassVar[bool] = False

    #: True when the host may cut the game off at a time (the "Time limit"
    #: pick). Real-time score games set it and implement ``time_up``.
    timed_adjustable: ClassVar[bool] = False

    #: True routes ``game_state`` to the TV sockets only rather than the whole
    #: room. Use for high-frequency or large payloads the phones do not need.
    heavy_state: ClassVar[bool] = False

    def __init__(self, room: Room, broadcaster) -> None:
        self.room = room
        self.bc = broadcaster
        # The host's time limit, counted from when the game is made.
        from games.native_hub import options
        self.began_at = time.time()
        self.time_limit = options.time_limit_seconds(room) if self.timed_adjustable else 0

    # ---- required ----------------------------------------------------------

    @abstractmethod
    def start(self, players: list[Player]) -> None:
        """Deal roles, seed the board, stamp any deadlines."""

    @abstractmethod
    def handle_action(self, player_id: str, action: str, data: dict) -> None:
        """Apply one player action. Invalid actions should be ignored, not raise."""

    @abstractmethod
    def public_state(self) -> dict:
        """The shared board -- becomes ``GameStateResponse.boardState``.

        Everything here is visible to the whole room, so never put secrets in it.
        """

    @abstractmethod
    def private_state(self, player_id: str) -> dict:
        """What only this player may see -- becomes ``PrivateStateResponse.privateData``.

        This must return a dict for every player even when the game has no
        secrets: the phone leaves its waiting screen on the first
        ``private_state`` it receives, not on ``game_started``.
        """

    @abstractmethod
    def is_over(self) -> bool:
        """True once results should be shown."""

    @abstractmethod
    def results(self) -> list[dict]:
        """Final ranking: ``[{"playerID", "name", "score", "rank"}, ...]``."""

    # ---- optional hooks ----------------------------------------------------

    def tick(self, dt: float) -> None:
        """Advance time-driven state. Only called when ``tick_hz > 0``."""

    def time_left(self) -> int | None:
        """Whole seconds left of the host's time limit, or None when there is none."""
        if not self.time_limit:
            return None
        return max(0, int(round(self.began_at + self.time_limit - time.time())))

    def time_expired(self) -> bool:
        return bool(self.time_limit) and time.time() >= self.began_at + self.time_limit

    def time_up(self) -> None:
        """The time limit ran out: finish with the scores as they stand."""
        if hasattr(self, "_finished"):
            self._finished = True

    def on_player_join(self, player: Player) -> None:
        """A player joined or reclaimed a seat mid-game."""

    def on_player_leave(self, player_id: str) -> None:
        """A player left or dropped."""

    def stop(self) -> None:
        """Release anything held. Called when the room finishes or is reaped."""

    # ---- helpers for subclasses -------------------------------------------

    def player_name(self, player_id: str) -> str:
        player = self.room.player(player_id)
        return player.name if player else "Player"

    def winner_first(self, ranked: list[dict], winner: str | None = None) -> list[dict]:
        """Put the winner (default ``self.winner``) alone at 1st; everyone
        else keeps shared ranks for equal scores, counted from 2nd."""
        winner = winner if winner is not None else getattr(self, "winner", None)
        if winner:
            ranked.sort(key=lambda r: r["playerID"] != winner)
            for index, row in enumerate(ranked):
                tied = index > 1 and row["score"] == ranked[index - 1]["score"]
                row["rank"] = ranked[index - 1]["rank"] if tied else index + 1
        return ranked

    def ranked_results(self, scores: dict[str, int]) -> list[dict]:
        """Build a standard results list from a ``{player_id: score}`` map.

        Equal scores share a rank (1, 1, 3): a tie is a tie, never decided by
        who happened to join the room first."""
        ordered = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
        rows: list[dict] = []
        for index, (pid, score) in enumerate(ordered):
            tied = index > 0 and score == ordered[index - 1][1]
            rows.append({
                "playerID": pid,
                "name": self.player_name(pid),
                "score": score,
                "rank": rows[-1]["rank"] if tied else index + 1,
            })
        return rows
