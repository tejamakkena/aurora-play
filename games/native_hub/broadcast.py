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
    from games.native_hub.errors import describe
    socketio.emit("error", {"code": code, **describe(code, message)},
                  to=sid, namespace=NAMESPACE)


def push_room_closed(socketio, room, reason: str) -> None:
    """Tell everyone still attached that this room is gone for good."""
    from games.native_hub.errors import describe
    socketio.emit("room_closed",
                  {"roomCode": room.code, "reason": reason, "code": "ROOM_CLOSED",
                   **describe("ROOM_CLOSED")},
                  to=room.code, namespace=NAMESPACE)


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


def final_results(room, results, forfeit: bool = False) -> list[dict]:
    """The engine's ranking, made safe to show as-is on every results screen.

    Each player appears once, in the engine's order, with an int score and a
    rank that never goes down the list (equal ranks are ties). Phones that
    have a seat but no row (an engine that only ranks the players still in
    at the end) are added below everyone else rather than vanishing. Each
    seat's ``score`` is set to its final score too, so an older app that still
    sorts ``players`` by score shows the right numbers.

    ``forfeit``: the game ended because too few players were left. Whoever
    stayed ranks above whoever walked away (a duel's leaver forfeits instead
    of winning on the points they had when they left).
    """
    rows: list[dict] = []
    seen: set[str] = set()
    for row in results or []:
        if not isinstance(row, dict):
            continue
        pid = row.get("playerID")
        if not isinstance(pid, str) or pid in seen:
            continue
        seen.add(pid)
        player = room.player(pid)
        score = row.get("score", 0)
        try:
            score = int(score)
        except (TypeError, ValueError):
            score = 0
        clean = dict(row)           # keeps game extras (brainTitle, ...)
        clean.update({"playerID": pid,
                      "name": row.get("name") or (player.name if player else "Player"),
                      "score": score,
                      "rank": row.get("rank")})
        if not (isinstance(clean.get("detail"), str) and clean["detail"]):
            clean.pop("detail", None)
        rows.append(clean)
    for player in room.players:
        if player.id not in seen:
            rows.append({"playerID": player.id, "name": player.name,
                         "score": int(player.score or 0), "rank": None})
    if forfeit:
        def stayed(row):
            player = room.player(row["playerID"])
            return player is not None and player.connected
        if any(map(stayed, rows)) and not all(map(stayed, rows)):
            original = {id(r): r["rank"] for r in rows}
            rows.sort(key=lambda r: not stayed(r))      # stable: engine order kept
            for index, row in enumerate(rows):
                prev = rows[index - 1] if index else None
                same = (prev is not None and original[id(row)] is not None
                        and stayed(prev) == stayed(row)
                        and original[id(prev)] == original[id(row)])
                row["rank"] = prev["rank"] if same else (
                    index + 1 if original[id(row)] is not None else None)
    previous = 0
    for index, row in enumerate(rows):
        rank = row["rank"]
        if not isinstance(rank, int) or isinstance(rank, bool) or rank < max(previous, 1):
            tied = index > 0 and rows[index - 1]["score"] == row["score"]
            rank = max(previous if tied else index + 1, 1)
        row["rank"] = rank
        previous = rank
    for row in rows:
        player = room.player(row["playerID"])
        if player is not None:
            player.score = row["score"]
    return rows


def finish_game(socketio, room, forfeit: bool = False) -> None:
    """Move a room to results and publish the final ranking. ``forfeit``:
    ended because too few players were left (see ``final_results``)."""
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
        results = final_results(room, results, forfeit=forfeit)
        room.results = results
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
        try:
            from games import teams
            teams.record_game(room, results)
        except Exception:
            logger.exception("teams record failed room=%s", room.code)
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


#: A running game with no action from anyone for this long is abandoned.
IDLE_END_SECONDS = 20 * 60
#: Fewer than two phones left for this long: the game cannot go on.
UNDERSTAFFED_END_SECONDS = 120


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
    short_since = None
    engine_cls = None

    while True:
        room = rooms.get(code)
        # A stale generation means the game restarted or ended under us.
        if (room is None or room.generation != generation
                or room.state is not RoomState.PLAYING):
            return

        now = time.time()
        dt, last = now - last, now
        if engine_cls is None:
            engine_cls = engine_for(room.game_id)

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

            forfeit = False
            if not over:
                # A table that can no longer play (everyone but one has left
                # or gone dark) must not hold the survivor hostage.
                needs = 1 if (room.solo or engine_cls.min_players <= 1) else 2
                if len(room.connected_players()) < needs:
                    if short_since is None:
                        short_since = time.time()
                    elif time.time() - short_since > UNDERSTAFFED_END_SECONDS:
                        logger.info("room %s understaffed, ending game", code)
                        over = True
                        forfeit = True
                else:
                    short_since = None

            if not over and time.time() - room.last_activity > IDLE_END_SECONDS:
                # Nobody has touched a controller for a long while: the table
                # has walked away. End the game so the room can show results
                # and be reused instead of idling (and ticking) until the TTL.
                logger.info("room %s idle, ending game", code)
                over = True

            if over:
                finish_game(socketio, room, forfeit=forfeit)
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
                push_room_closed(socketio, room, "expired")
                rooms.remove(room.code)
        except Exception:
            logger.exception("reaper error")
