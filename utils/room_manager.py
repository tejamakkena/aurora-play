"""Shared room + player state for the native iOS/tvOS hub.

Every one of the 17 browser games re-implements this from scratch with its own
module-level ``<game>_rooms = {}`` dict and its own ``generate_room_code()``.
This is the single implementation the native hub uses instead.

Two design points worth stating up front:

1.  **The TV is never in ``players``.** It lives in ``tv_sids`` and is joined to
    the Socket.IO room, so it receives every broadcast without appearing in the
    lobby roster or counting toward the minimum-player gate.

2.  **``to_json()`` emits Swift key names exactly.** The client decodes with a
    default ``JSONDecoder`` (no snake_case conversion), so ``isReady`` and
    ``gameID`` are spelled that way here. A mismatch does not raise -- it makes
    the whole payload decode to nil and the screen silently never updates.
"""

import random
import threading
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable

# O/0 and I/1 are omitted: the TV renders this code at 96pt across a living room
# and a misread character means the phone simply cannot join.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6

EMPTY_GRACE_SECONDS = 120       # room with nobody in it survives this long
ROOM_TTL_SECONDS = 3600         # hard ceiling regardless of activity
RECONNECT_GRACE_SECONDS = 60    # a disconnected player keeps their seat this long


class RoomState(str, Enum):
    LOBBY = "lobby"
    PLAYING = "playing"
    RESULTS = "results"


def generate_room_code(exists: Callable[[str], bool]) -> str:
    """Generate a code that passes ``exists``. Exposed as a free function so the
    legacy games can adopt it later without importing the registry."""
    for _ in range(12):
        code = "".join(random.choices(CODE_ALPHABET, k=CODE_LENGTH))
        if not exists(code):
            return code
    raise RuntimeError("room code space exhausted")


@dataclass
class Player:
    """One phone. ``id`` is the stable device UUID, ``sid`` the current socket.

    A bot (``is_bot=True``) is a seat filler with no socket: it never appears
    in ``player_by_sid``, can never hold the host flag, and does not keep a
    room alive on its own (see ``Room.is_empty``).
    """

    id: str
    name: str
    is_ready: bool = False
    score: int = 0
    is_host: bool = False
    sid: str | None = None
    connected: bool = True
    disconnected_at: float | None = None
    is_bot: bool = False
    # Bot bookkeeping, maintained by games.native_hub.bots: the phase key the
    # bot last scheduled for, and the timestamp after which it may act.
    bot_phase_key: str = ""
    bot_act_at: float = 0.0

    def to_json(self) -> dict:
        """The Swift ``Player`` struct. ``isBot`` is additive -- Swift's
        ``JSONDecoder`` ignores unknown keys, so old clients keep working."""
        return {
            "id": self.id,
            "name": self.name,
            "isReady": self.is_ready,
            "score": self.score,
            "isHost": self.is_host,
            "isBot": self.is_bot,
        }


def _teams_json(room):
    from games import teams
    return teams.to_json(room)


def _night_json(room):
    from games import game_night
    return game_night.to_json(room)


@dataclass
class Room:
    code: str
    game_id: str
    state: RoomState = RoomState.LOBBY
    #: Sub-phase within PLAYING. "rules" while the room waits for the host to
    #: tap Begin after Start Game -- the engine is constructed but not
    #: started, so no clocks run and nothing is dealt. "play" once the host
    #: begins (or for any room that never passed through the gate).
    phase: str = "play"
    players: list[Player] = field(default_factory=list)   # phones only
    tv_sids: set[str] = field(default_factory=set)        # TV / board sockets
    solo: bool = False
    #: Content-pack id ("en", "te", "hi", ...) chosen at room creation.
    #: Engines read it via ``getattr(room, "content_pack", "en")``.
    content_pack: str = "en"
    #: Free-text Travel Mode topic ("Tollywood movies", "cricket", ...),
    #: set by the host/passenger in the lobby. Quiz engines read it via
    #: ``getattr(room, "topic", "")``; when non-empty they generate fresh
    #: questions from games/topic_gen.py instead of the fixed packs.
    topic: str = ""
    #: Externally fetched questions injected at room creation: the iOS
    #: client calls GET /api/travel/questions (or legacy POST
    #: /trivia/generate) and passes the result as "seedQuestions" in
    #: create_room. TriviaEngine prefers these over topic generation and
    #: the content packs. Each item is {"question", "options"[4],
    #: "correct_answer" 0-3}, validated on the way in.
    seed_questions: list = field(default_factory=list)
    #: The player currently holding the microphone for the cross-device
    #: voice loop (TV speaks, this phone listens). Set via the claim_mic
    #: socket event; None means no phone has claimed it yet.
    mic_player_id: str | None = None
    # The solo placeholder's identity, held here rather than added to
    # `players` immediately at create_room time -- deferred until start_game
    # actually fires, and only materialized then if nobody real has joined by
    # that point. Lets a solo room's lobby (with its real room code) sit open
    # long enough for a phone to join it normally, in which case the real
    # phone player is used instead and this placeholder is never created at
    # all. See games/native_hub/socket_events.py's handle_start_game.
    pending_host_id: str | None = None
    pending_host_name: str = "Player 1"
    engine: Any = None
    # Rolling per-(pack, question-kind) history of recently asked question
    # texts, maintained by content_packs.record_questions(). Quiz engines
    # skip these when sampling a new session's pool so back-to-back games
    # in the same room don't replay the same questions. Additive only --
    # safe for any engine that never heard of it.
    question_history: dict = field(default_factory=dict)
    #: Game Night (games/game_night.py): the playlist, which game is up,
    #: and the running night scoreboard. None outside a Game Night.
    night: dict | None = None
    #: Teams mode (games/teams.py): 2-4 named teams scoring together.
    #: None when everyone plays for themselves.
    teams: dict | None = None
    # Bumped on start and on finish. A background pump captures the value it was
    # spawned with and exits as soon as it no longer matches, so a pump from a
    # previous round can never double-broadcast into the next one.
    generation: int = 0
    created_at: float = field(default_factory=time.time)
    last_activity: float = field(default_factory=time.time)
    empty_since: float | None = None
    lock: threading.RLock = field(default_factory=threading.RLock, repr=False)

    # ---- queries -----------------------------------------------------------

    def player(self, player_id: str) -> Player | None:
        return next((p for p in self.players if p.id == player_id), None)

    def player_by_sid(self, sid: str) -> Player | None:
        return next((p for p in self.players if p.sid == sid), None)

    def connected_players(self) -> list[Player]:
        return [p for p in self.players if p.connected]

    def host(self) -> Player | None:
        return next((p for p in self.players if p.is_host), None)

    def is_empty(self) -> bool:
        # Bots do not count: a room with only bots and no TV is dead weight
        # and should be reaped like any other empty room.
        return not self.tv_sids and not any(
            p.connected and not p.is_bot for p in self.players)

    def to_json(self) -> dict:
        """Exactly the Swift ``Room`` struct. ``contentPack``/``botsAllowed``/
        ``usesContentPack``/``phase`` are additive optionals on the Swift side."""
        from games.native_hub.bots import POLICIES
        from games.native_hub.engines.content_packs import PACK_GAMES
        return {
            "code": self.code,
            "gameID": self.game_id,
            "players": [p.to_json() for p in self.players],
            "state": self.state.value,
            "phase": self.phase,
            "contentPack": self.content_pack,
            "topic": self.topic,
            "micPlayerID": self.mic_player_id,
            "botsAllowed": self.game_id in POLICIES,
            "usesContentPack": self.game_id in PACK_GAMES,
            "night": _night_json(self),
            "teams": _teams_json(self),
        }

    # ---- mutations (callers hold self.lock) --------------------------------

    def touch(self) -> None:
        self.last_activity = time.time()
        self.empty_since = None
        if self.teams:
            from games import teams
            teams.sync_members(self)

    def add_player(self, player_id: str, name: str, sid: str) -> Player:
        """Add a phone. The first phone to arrive becomes host."""
        player = Player(
            id=player_id,
            name=name,
            sid=sid,
            is_host=not any(p.is_host for p in self.players),
        )
        self.players.append(player)
        self.touch()
        return player

    def add_bot(self, name: str | None = None) -> Player:
        """Add a bot seat filler. Bots never become host and have no socket."""
        from games.native_hub.bots import BOT_NAMES
        if name is None:
            taken = {p.name for p in self.players}
            name = next((n for n in BOT_NAMES if n not in taken),
                        f"Bot {len(self.players) + 1}")
        player = Player(
            id=f"bot-{uuid.uuid4().hex[:8]}",
            name=name,
            is_host=False,
            is_bot=True,
        )
        self.players.append(player)
        self.touch()
        return player

    def remove_bot(self, player_id: str) -> Player | None:
        """Remove a bot. Refuses to remove human players."""
        player = self.player(player_id)
        if player is None or not player.is_bot:
            return None
        self.players.remove(player)
        self.touch()
        return player

    def remove_player(self, player_id: str) -> Player | None:
        player = self.player(player_id)
        if player is None:
            return None
        self.players.remove(player)
        self.reassign_host()
        self.mark_empty_if_needed()
        if self.teams:
            from games import teams
            teams.sync_members(self)
        return player

    def attach_tv(self, sid: str) -> None:
        self.tv_sids.add(sid)
        self.touch()

    def detach_sid(self, sid: str) -> str | None:
        """Detach whatever this socket was. Returns a player id (including a
        solo room's synthetic player, whose sid doubles as its own TV's --
        see below), '__tv__' (a TV/spectator board with no matching player),
        or None.

        A solo room's one synthetic player is created with the TV's own sid
        (``handle_create_room``), so that single sid is in *both* ``tv_sids``
        and ``players`` at once. Checking ``tv_sids`` first and returning
        immediately -- the original shape of this method -- meant a solo
        room's TV could never actually detach its player half: the seat, and
        its now-dead sid, stayed in ``players`` forever, ``connected`` still
        ``True``, so ``is_empty()`` (and therefore the reaper's empty-grace
        cleanup) could never see the room as empty. Checking for a matching
        player unconditionally, before deciding what to return, detaches
        both halves of a solo room's combined sid in one call.
        """
        was_tv = sid in self.tv_sids
        if was_tv:
            self.tv_sids.discard(sid)

        player = self.player_by_sid(sid)
        if player is None:
            if was_tv:
                self.mark_empty_if_needed()
                return "__tv__"
            return None

        if self.state is RoomState.LOBBY:
            # Nothing to preserve yet -- drop the seat outright.
            self.players.remove(player)
            self.reassign_host()
        else:
            # Mid-game: keep the seat so the same device can reclaim it.
            player.connected = False
            player.sid = None
            player.disconnected_at = time.time()
            self.reassign_host()

        self.mark_empty_if_needed()
        return player.id

    def set_ready(self, player_id: str, ready: bool = True) -> bool:
        player = self.player(player_id)
        if player is None:
            return False
        player.is_ready = ready
        self.touch()
        return True

    def reassign_host(self) -> None:
        """Ensure exactly one connected human player holds the host flag."""
        if any(p.is_host and p.connected and not p.is_bot for p in self.players):
            return
        for p in self.players:
            p.is_host = False
        nxt = next((p for p in self.players if p.connected and not p.is_bot),
                   None)
        if nxt is not None:
            nxt.is_host = True

    def mark_empty_if_needed(self) -> None:
        if self.is_empty():
            if self.empty_since is None:
                self.empty_since = time.time()
        else:
            self.empty_since = None

    def evict_stale_players(self, now: float | None = None) -> list[str]:
        """Drop players whose reconnect grace has expired. Returns their ids."""
        now = now or time.time()
        evicted = []
        for p in list(self.players):
            if (not p.connected and p.disconnected_at is not None
                    and now - p.disconnected_at > RECONNECT_GRACE_SECONDS):
                self.players.remove(p)
                evicted.append(p.id)
        if evicted:
            self.reassign_host()
            self.mark_empty_if_needed()
        return evicted


class RoomRegistry:
    """Process-wide room store. Thread-safe."""

    def __init__(self) -> None:
        self._rooms: dict[str, Room] = {}
        self._sid_index: dict[str, str] = {}   # sid -> room code
        self._lock = threading.RLock()

    def new_code(self) -> str:
        with self._lock:
            return generate_room_code(lambda c: c in self._rooms)

    def create(self, game_id: str, *, solo: bool = False) -> Room:
        with self._lock:
            room = Room(code=self.new_code(), game_id=game_id, solo=solo)
            self._rooms[room.code] = room
            return room

    def get(self, code: str) -> Room | None:
        with self._lock:
            return self._rooms.get(code)

    def get_by_sid(self, sid: str) -> Room | None:
        with self._lock:
            code = self._sid_index.get(sid)
            return self._rooms.get(code) if code else None

    def bind_sid(self, sid: str, code: str) -> None:
        with self._lock:
            self._sid_index[sid] = code

    def unbind_sid(self, sid: str) -> str | None:
        with self._lock:
            return self._sid_index.pop(sid, None)

    def remove(self, code: str) -> None:
        with self._lock:
            room = self._rooms.pop(code, None)
            if room is not None:
                room.generation += 1   # kill any pump still running for it
            for sid in [s for s, c in self._sid_index.items() if c == code]:
                del self._sid_index[sid]

    def all_rooms(self) -> list[Room]:
        with self._lock:
            return list(self._rooms.values())

    def reapable(self, now: float | None = None) -> list[Room]:
        """Rooms that have been empty past the grace period or exceeded the TTL."""
        now = now or time.time()
        with self._lock:
            return [
                r for r in self._rooms.values()
                if (r.empty_since is not None
                    and now - r.empty_since > EMPTY_GRACE_SECONDS)
                or now - r.created_at > ROOM_TTL_SECONDS
            ]

    def clear(self) -> None:
        """Test helper."""
        with self._lock:
            self._rooms.clear()
            self._sid_index.clear()

    def __len__(self) -> int:
        with self._lock:
            return len(self._rooms)


# Module-level singleton used by the hub.
rooms = RoomRegistry()

