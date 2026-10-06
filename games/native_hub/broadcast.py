"""Everything that pushes state out to the TV and the phones.

Modeled on the cleanest pattern already in the repo -- poker's per-player deal
loop (games/poker/socket_events.py:104) -- generalised so every engine gets the
same public/private split for free.

Two rules hold throughout:

*   Every emit passes ``namespace='/native'``. ``socketio.emit`` defaults to
    ``'/'``, and an emit to the wrong namespace fails silently.
*   Payloads are built under ``room.lock`` and emitted outside it. Socket writes
    can block, and holding the room lock across one would stall every handler.
"""

import logging
import time

from games.native_hub import NAMESPACE
from games.native_hub import bots
from games.native_hub.registry import engine_for
from utils.room_manager import RoomState, rooms

logger = logging.getLogger(__name__)

# The TV registers its game_state handler only after TVGameBoardView is built,
# which happens in response to room_updated. Emitting the first board frame in
# that same tick loses it, and the client has no way to ask for a resend -- so
# the pump waits before its first push.
PUMP_LEAD_IN_SECONDS = 0.35
BASE_PUMP_HZ = 1.0
REAPER_INTERVAL_SECONDS = 30


class Broadcaster:
    """Handed to each engine so it can force a push without importing socketio."""

    def __init__(self, socketio, room) -> None:
        self.socketio = socketio
        self.room = room

    def state(self) -> None:
        broadcast_state(self.socketio, self.room)

    def room_update(self) -> None:
        push_room(self.socketio, self.room)

    def error(self, message: str, sid: str, code: str | None = None) -> None:
        push_error(self.socketio, sid, message, code)


def push_room(socketio, room) -> None:
    """Send the bare Room object. This is what drives every TV screen change."""
    socketio.emit("room_updated", room.to_json(), to=room.code, namespace=NAMESPACE)


def push_error(socketio, sid: str, message: str, code: str | None = None) -> None:
    socketio.emit("error", {"message": message, "code": code},
                  to=sid, namespace=NAMESPACE)


def broadcast_state(socketio, room) -> None:
    """Publish the shared board and each player's private slice.

    ``private_state`` goes to every connected player even when the game has no
    secrets -- the phone leaves its waiting screen on the first one it receives.
    """
    engine = room.engine
    if engine is None:
        return

    try:
        with room.lock:
            public = {"roomCode": room.code, "boardState": engine.public_state()}
            privates = [
                (p.sid, {"roomCode": room.code, "playerID": p.id,
                         "privateData": engine.private_state(p.id)})
                for p in room.connected_players() if p.sid
            ]
            heavy = engine.heavy_state
            tv_sids = list(room.tv_sids)
    except Exception:
        logger.exception("state build failed room=%s", room.code)
        return

    if heavy:
        for sid in tv_sids:
            socketio.emit("game_state", public, to=sid, namespace=NAMESPACE)
    else:
        socketio.emit("game_state", public, to=room.code, namespace=NAMESPACE)

    for sid, payload in privates:
        socketio.emit("private_state", payload, to=sid, namespace=NAMESPACE)


def finish_game(socketio, room) -> None:
    """Move a room to results and publish the final ranking."""
    with room.lock:
        if room.state is RoomState.RESULTS:
            return
        engine = room.engine
        results = []
        if engine is not None:
            try:
                results = engine.results()
            except Exception:
                logger.exception("results failed room=%s", room.code)
            try:
                engine.stop()
            except Exception:
                logger.exception("engine stop failed room=%s", room.code)
        room.state = RoomState.RESULTS
        room.generation += 1          # stop the pump
        room.touch()
        # Game Night totals and player profiles (best-effort: neither may
        # ever break the end of a game).
        try:
            from games import game_night
            game_night.record_game(room, results)
        except Exception:
            logger.exception("game night record failed room=%s", room.code)
        players = list(room.players)
        game_id = room.game_id

    try:
        from games import profiles
        profiles.record_results(game_id, results, players)
    except Exception:
        logger.exception("profile record failed room=%s", room.code)

    broadcast_state(socketio, room)
    socketio.emit("game_ended", {"roomCode": room.code, "results": results},
                  to=room.code, namespace=NAMESPACE)
    push_room(socketio, room)


def start_pump(socketio, room) -> None:
    """Spawn the state pump for a room that has just started playing."""
    engine_cls = engine_for(room.game_id)
    socketio.start_background_task(
        _pump, socketio, room.code, room.generation, engine_cls.tick_hz
    )


def _pump(socketio, code: str, generation: int, tick_hz: float) -> None:
    """One background task per active room; drives countdowns and simulation.

    Countdowns are not separate threads -- an engine stores a deadline and
    reports ``secondsLeft`` from ``public_state()``, so this single loop is what
    makes every clock in the app move.
    """
    interval = 1.0 / max(BASE_PUMP_HZ, tick_hz)
    socketio.sleep(PUMP_LEAD_IN_SECONDS)
    last = time.time()

    while True:
        room = rooms.get(code)
        # A stale generation means the game restarted or ended under us.
        if (room is None or room.generation != generation
                or room.state is not RoomState.PLAYING):
            return

        now = time.time()
        dt, last = now - last, now

        try:
            with room.lock:
                if room.engine is not None:
                    if tick_hz:
                        room.engine.tick(dt)
                    else:
                        # Even without simulation, time-driven engines need a
                        # nudge to roll phases over when a deadline passes.
                        room.engine.tick(dt)
                    # Bot seats act here, on the same lock and through the
                    # same handle_action path as real players.
                    for bot in room.players:
                        if bot.is_bot and bot.connected:
                            act = bots.maybe_bot_action(room.engine, bot)
                            if act is not None:
                                verb, payload = act
                                try:
                                    room.engine.handle_action(bot.id, verb, payload)
                                except Exception:
                                    logger.exception("bot action failed room=%s",
                                                     code)
                    over = room.engine.is_over()
                else:
                    over = False

            if over:
                finish_game(socketio, room)
                return

            broadcast_state(socketio, room)
        except Exception:
            logger.exception("pump error room=%s", code)

        socketio.sleep(interval)


def start_reaper(socketio) -> None:
    socketio.start_background_task(_reaper, socketio)


def _reaper(socketio) -> None:
    """Drop abandoned rooms and evict players past their reconnect grace."""
    while True:
        socketio.sleep(REAPER_INTERVAL_SECONDS)
        try:
            now = time.time()
            for room in rooms.all_rooms():
                with room.lock:
                    evicted = room.evict_stale_players(now)
                if evicted:
                    push_room(socketio, room)
            for room in rooms.reapable(now):
                logger.info("reaping room %s", room.code)
                rooms.remove(room.code)
        except Exception:
            logger.exception("reaper error")
