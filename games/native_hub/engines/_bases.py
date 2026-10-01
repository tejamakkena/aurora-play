"""Reusable engine shapes.

Most games in the catalog are one of two things, so the mechanics live here once
rather than being re-derived in twenty-four modules.

``RoundBasedEngine``  -- everyone acts at once inside a deadline, then the round
                         resolves and scores. Party games, Wavelength, auctions.
``TurnBasedEngine``   -- players act one at a time in rotation. Board games.

Both compute ``secondsLeft`` from a stored deadline rather than running a timer
thread, which is what lets the single 1 Hz room pump drive every countdown in
the app.
"""

import time
from abc import abstractmethod

from games.native_hub.engine import NativeGameEngine
from utils.room_manager import Player


class RoundBasedEngine(NativeGameEngine):
    """Simultaneous-submission rounds with a per-phase deadline.

    Subclasses define the phase sequence via ``begin_phase`` / ``resolve_phase``
    and never manage time themselves.
    """

    total_rounds: int = 5
    phase_seconds: dict[str, int] = {}       # phase name -> duration
    first_phase: str = "collect"
    #: Later phases that may also end early once everyone has submitted
    #: (the first phase always may). Only for single-answer phases.
    early_phases: tuple = ()

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.round: int = 0
        self.phase: str = self.first_phase
        self.deadline: float = 0.0
        self.scores: dict[str, int] = {}
        self.submissions: dict[str, object] = {}
        self._finished = False

    # ---- lifecycle ---------------------------------------------------------

    def start(self, players: list[Player]) -> None:
        self.scores = {p.id: 0 for p in players}
        self.round = 1
        self.start_round()

    def start_round(self) -> None:
        self.submissions = {}
        self.enter_phase(self.first_phase)

    def enter_phase(self, phase: str) -> None:
        self.phase = phase
        seconds = self.phase_seconds.get(phase, 0)
        self.deadline = time.time() + seconds if seconds else 0.0
        self.begin_phase(phase)

    def seconds_left(self) -> int:
        if not self.deadline:
            return 0
        return max(0, int(round(self.deadline - time.time())))

    def tick(self, dt: float) -> None:
        if self._finished:
            return
        if self.deadline and time.time() >= self.deadline:
            self.advance()
        elif self.everyone_submitted() and (self.phase == self.first_phase
                                            or self.phase in self.early_phases):
            # Nobody left to wait for -- don't burn the rest of the clock.
            self.advance()

    def advance(self) -> None:
        nxt = self.resolve_phase(self.phase)
        if nxt is None:
            self.end_round()
        else:
            self.enter_phase(nxt)

    def end_round(self) -> None:
        if self.round >= self.total_rounds:
            self._finished = True
            self.phase = "final"
            self.deadline = 0.0
        else:
            self.round += 1
            self.start_round()

    # ---- helpers -----------------------------------------------------------

    def active_players(self) -> list[Player]:
        return self.room.connected_players()

    def everyone_submitted(self) -> bool:
        active = self.active_players()
        if not active:
            return False
        return all(p.id in self.submissions for p in active)

    def submitted_ids(self) -> list[str]:
        return list(self.submissions.keys())

    def award(self, player_id: str, points: int) -> None:
        self.scores[player_id] = self.scores.get(player_id, 0) + points
        player = self.room.player(player_id)
        if player is not None:
            player.score = self.scores[player_id]

    def scoreboard(self) -> list[dict]:
        return [
            {"id": p.id, "name": p.name,
             "score": self.scores.get(p.id, 0), "isHost": p.is_host}
            for p in self.room.players
        ]

    def base_public(self) -> dict:
        """Fields every round-based board needs. Merge into ``public_state``."""
        return {
            "round": self.round,
            "totalRounds": self.total_rounds,
            "phase": self.phase,
            "secondsLeft": self.seconds_left(),
            "submittedPlayerIDs": self.submitted_ids(),
            "players": self.scoreboard(),
        }

    def base_private(self, player_id: str) -> dict:
        return {
            "round": self.round,
            "phase": self.phase,
            "secondsLeft": self.seconds_left(),
            "hasSubmitted": player_id in self.submissions,
            "score": self.scores.get(player_id, 0),
        }

    def is_over(self) -> bool:
        return self._finished

    def results(self) -> list[dict]:
        return self.ranked_results(self.scores)

    def on_player_leave(self, player_id: str) -> None:
        self.submissions.pop(player_id, None)

    # ---- subclass contract -------------------------------------------------

    def begin_phase(self, phase: str) -> None:
        """Set up state for a phase that has just started."""

    @abstractmethod
    def resolve_phase(self, phase: str) -> str | None:
        """Score the finished phase. Return the next phase, or None to end the round."""


class TurnBasedEngine(NativeGameEngine):
    """Rotation-based play with an ``isMyTurn`` gate."""

    turn_seconds: int = 0        # 0 = no clock

    def __init__(self, room, broadcaster) -> None:
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.turn_index: int = 0
        self.deadline: float = 0.0
        self.scores: dict[str, int] = {}
        self.winner: str | None = None
        self._finished = False

    def start(self, players: list[Player]) -> None:
        self.order = [p.id for p in players]
        self.scores = {p.id: 0 for p in players}
        self.turn_index = 0
        self.reset_turn_clock()
        self.setup()

    def setup(self) -> None:
        """Seed the board. Called once after the turn order is fixed."""

    def reset_turn_clock(self) -> None:
        self.deadline = time.time() + self.turn_seconds if self.turn_seconds else 0.0

    def seconds_left(self) -> int:
        if not self.deadline:
            return 0
        return max(0, int(round(self.deadline - time.time())))

    def current_player_id(self) -> str | None:
        live = [pid for pid in self.order if self._is_live(pid)]
        if not live:
            return None
        if self.turn_index >= len(self.order):
            self.turn_index = 0
        return self.order[self.turn_index % len(self.order)]

    def _is_live(self, player_id: str) -> bool:
        player = self.room.player(player_id)
        return player is not None and player.connected

    def next_turn(self) -> None:
        if not self.order:
            return
        for _ in range(len(self.order)):
            self.turn_index = (self.turn_index + 1) % len(self.order)
            if self._is_live(self.order[self.turn_index]):
                break
        self.reset_turn_clock()

    def is_my_turn(self, player_id: str) -> bool:
        return self.current_player_id() == player_id

    def tick(self, dt: float) -> None:
        if not self._finished and self.deadline and time.time() >= self.deadline:
            self.on_turn_timeout()

    def on_turn_timeout(self) -> None:
        self.next_turn()

    def finish(self, winner: str | None = None) -> None:
        self.winner = winner
        self._finished = True
        self.deadline = 0.0

    def scoreboard(self) -> list[dict]:
        return [
            {"id": p.id, "name": p.name,
             "score": self.scores.get(p.id, 0), "isHost": p.is_host}
            for p in self.room.players
        ]

    def base_public(self) -> dict:
        return {
            "currentPlayerID": self.current_player_id(),
            "secondsLeft": self.seconds_left(),
            "winner": self.winner,
            "players": self.scoreboard(),
        }

    def base_private(self, player_id: str) -> dict:
        return {
            "isMyTurn": self.is_my_turn(player_id),
            "secondsLeft": self.seconds_left(),
            "score": self.scores.get(player_id, 0),
        }

    def is_over(self) -> bool:
        return self._finished

    def results(self) -> list[dict]:
        # Many board games only record a winner (no running score), so a
        # plain score sort would leave every player tied at 0 and could rank
        # the loser first. The winner always tops the table.
        ranked = self.ranked_results(self.scores)
        if self.winner:
            ranked.sort(key=lambda r: r["playerID"] != self.winner)
            for rank, row in enumerate(ranked, start=1):
                row["rank"] = rank
        return ranked

    def on_player_leave(self, player_id: str) -> None:
        if self.current_player_id() == player_id:
            self.next_turn()
