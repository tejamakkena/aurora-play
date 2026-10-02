"""The six Socket.IO handlers the native apps talk to.

All of them live on the ``/native`` namespace. python-socketio keys handlers by
``(namespace, event)``, so these cannot collide with the five browser games that
each register ``create_room``/``join_room``/``start_game``/``leave_room`` on the
default namespace.

``flask_socketio.join_room`` is imported under an alias because this module
defines a handler function named ``join_room``; without the alias the handler
would shadow the helper it needs to call.
"""

import logging
import threading
import time

from flask import request
from flask_socketio import join_room as socket_join_room
from flask_socketio import leave_room as socket_leave_room

from games.native_hub import NAMESPACE
from games.native_hub.bots import POLICIES as BOT_POLICIES
from games.native_hub.broadcast import (
    Broadcaster, broadcast_state, finish_game, push_error, push_room,
    start_pump, start_reaper,
)
from games.native_hub.registry import engine_for
from games.native_hub.rules import rules_for
from utils import validators as v
from utils.player_manager import sanitize_name
from utils.room_manager import RoomState, rooms

logger = logging.getLogger(__name__)

# Flask-Limiter does not see Socket.IO events, so game_action is throttled here.
ACTION_BURST = 30
ACTION_WINDOW_SECONDS = 2.0

_action_buckets: dict[str, list[float]] = {}
_bucket_lock = threading.Lock()


def _rate_limited(sid: str) -> bool:
    now = time.time()
    with _bucket_lock:
        hits = [t for t in _action_buckets.get(sid, []) if now - t < ACTION_WINDOW_SECONDS]
        if len(hits) >= ACTION_BURST:
            _action_buckets[sid] = hits
            return True
        hits.append(now)
        _action_buckets[sid] = hits
    return False


def _valid_pack(raw) -> str:
    """Sanitize the client-supplied content-pack id. Unknown -> 'en'."""
    pack = str(raw or "en").strip().lower()[:8]
    try:
        from games.native_hub.engines.content_packs import PACKS
        allowed = set(PACKS)
    except Exception:
        allowed = {"en", "te", "hi"}
    return pack if pack in allowed else "en"


def register_native_events(socketio):
    """Attach every ``/native`` handler and start the room reaper."""

    # ---- create_room ---------------------------------------------------
    # Sent only by the TV. Note it replies with room_updated, not room_joined:
    # room_updated is the TV's only listener and drives all its screen changes.
    @socketio.on("create_room", namespace=NAMESPACE)
    def handle_create_room(data):
        data = v.as_dict(data)
        sid = request.sid
        if _rate_limited(sid):
            return

        gid = v.game_id(data.get("gameID"))
        if gid is None:
            push_error(socketio, sid, "Unknown game", "INVALID_GAME")
            return

        solo = bool(data.get("solo"))
        room = rooms.create(gid, solo=solo)
        room.content_pack = _valid_pack(data.get("contentPack"))
        socket_join_room(room.code, namespace=NAMESPACE)
        rooms.bind_sid(sid, room.code)

        with room.lock:
            room.attach_tv(sid)
            host_id = v.player_id(data.get("hostID"))
            if solo and host_id:
                # Not added to room.players yet -- reported directly that
                # solo games (e.g. Atlas, which needs typed answers) had no
                # way to bring in a phone at all, because this player used to
                # be created immediately and the room auto-started before a
                # phone could ever join it. Held here instead, and only
                # materialized in handle_start_game -- and only if nobody
                # real has joined by then -- so the lobby (with its real
                # room code) stays genuinely open for a phone to join
                # normally in the meantime.
                room.pending_host_id = host_id
                room.pending_host_name = sanitize_name(data.get("hostName"), "Player 1")

        socketio.emit("room_joined",
                      {"room": room.to_json(), "playerID": host_id or ""},
                      to=sid, namespace=NAMESPACE)
        push_room(socketio, room)
        logger.info("room %s created game=%s solo=%s", room.code, gid, solo)

    # ---- join_room -----------------------------------------------------
    @socketio.on("join_room", namespace=NAMESPACE)
    def handle_join_room(data):
        data = v.as_dict(data)
        sid = request.sid
        if _rate_limited(sid):
            return

        code = v.room_code(data.get("roomCode"))
        if code is None:
            push_error(socketio, sid, "Invalid room code", "INVALID_CODE")
            return

        room = rooms.get(code)
        if room is None:
            push_error(socketio, sid, "Room not found", "ROOM_NOT_FOUND")
            return

        # A second TV or a spectator board.
        if bool(data.get("isTV")):
            socket_join_room(code, namespace=NAMESPACE)
            rooms.bind_sid(sid, code)
            with room.lock:
                room.attach_tv(sid)
            socketio.emit("room_joined", {"room": room.to_json(), "playerID": ""},
                          to=sid, namespace=NAMESPACE)
            push_room(socketio, room)
            return

        pid = v.player_id(data.get("playerID"))
        if pid is None:
            push_error(socketio, sid, "Invalid player", "INVALID_PLAYER")
            return

        engine_cls = engine_for(room.game_id)
        resumed = False

        with room.lock:
            existing = room.player(pid)
            if existing is not None:
                # Same device reclaiming its seat after a drop.
                existing.sid = sid
                existing.connected = True
                existing.disconnected_at = None
                room.reassign_host()
                room.touch()
                resumed = True
            else:
                if room.state is not RoomState.LOBBY:
                    push_error(socketio, sid, "Game already in progress",
                               "GAME_IN_PROGRESS")
                    return
                # TVLobbyView does ForEach(players.count..<maxPlayers), which
                # traps if the server ever reports more players than the cap.
                if len(room.players) >= engine_cls.max_players:
                    push_error(socketio, sid, "Room is full", "ROOM_FULL")
                    return
                room.add_player(pid, sanitize_name(data.get("playerName")), sid)

        socket_join_room(code, namespace=NAMESPACE)
        rooms.bind_sid(sid, code)

        socketio.emit("room_joined", {"room": room.to_json(), "playerID": pid},
                      to=sid, namespace=NAMESPACE)
        push_room(socketio, room)

        if resumed and room.state is RoomState.PLAYING and room.engine is not None:
            # Get this phone back onto the game screen immediately rather than
            # making it wait up to a second for the next pump cycle.
            with room.lock:
                payload = {"roomCode": code, "playerID": pid,
                           "privateData": room.engine.private_state(pid)}
            socketio.emit("private_state", payload, to=sid, namespace=NAMESPACE)

    # ---- add_bot / remove_bot --------------------------------------------
    # The host (or the TV) can fill empty seats with bots while still in the
    # lobby, so a group of three can play an eight-player party game.
    @socketio.on("add_bot", namespace=NAMESPACE)
    def handle_add_bot(data):
        data = v.as_dict(data)
        sid = request.sid
        if _rate_limited(sid):
            return
        code = v.room_code(data.get("roomCode"))
        room = rooms.get(code) if code else None
        if room is None:
            return
        with room.lock:
            if sid not in room.tv_sids:
                actor = room.player_by_sid(sid)
                if actor is None or not actor.is_host:
                    push_error(socketio, sid, "Only the host can add bots",
                               "NOT_HOST")
                    return
            if room.state is not RoomState.LOBBY:
                push_error(socketio, sid, "Bots can only join the lobby",
                           "GAME_IN_PROGRESS")
                return
            if room.game_id not in BOT_POLICIES:
                # A bot with no policy never acts: it would stall a turn-based
                # game on its turn and make every round wait out the clock.
                push_error(socketio, sid, "Bots can't play this game yet",
                           "BOTS_UNSUPPORTED")
                return
            if len(room.players) >= engine_for(room.game_id).max_players:
                push_error(socketio, sid, "Room is full", "ROOM_FULL")
                return
            bot = room.add_bot()
        push_room(socketio, room)
        logger.info("room %s bot %s added", code, bot.id)

    @socketio.on("remove_bot", namespace=NAMESPACE)
    def handle_remove_bot(data):
        data = v.as_dict(data)
        sid = request.sid
        if _rate_limited(sid):
            return
        code = v.room_code(data.get("roomCode"))
        bot_id = v.player_id(data.get("botID"))
        room = rooms.get(code) if code else None
        if room is None or bot_id is None:
            return
        with room.lock:
            if sid not in room.tv_sids:
                actor = room.player_by_sid(sid)
                if actor is None or not actor.is_host:
                    push_error(socketio, sid, "Only the host can remove bots",
                               "NOT_HOST")
                    return
            if room.remove_bot(bot_id) is None:
                return
        push_room(socketio, room)
        logger.info("room %s bot %s removed", code, bot_id)

    # ---- set_content_pack ----------------------------------------------
    # The TV (or the host's phone) picks the question language in the lobby.
    @socketio.on("set_content_pack", namespace=NAMESPACE)
    def handle_set_content_pack(data):
        data = v.as_dict(data)
        sid = request.sid
        if _rate_limited(sid):
            return
        code = v.room_code(data.get("roomCode"))
        room = rooms.get(code) if code else None
        if room is None:
            return
        with room.lock:
            if sid not in room.tv_sids:
                actor = room.player_by_sid(sid)
                if actor is None or not actor.is_host:
                    push_error(socketio, sid, "Only the host can change the language",
                               "NOT_HOST")
                    return
            if room.state is RoomState.PLAYING:
                return
            room.content_pack = _valid_pack(data.get("contentPack"))
            room.touch()
        push_room(socketio, room)

    # ---- player_ready --------------------------------------------------
    @socketio.on("player_ready", namespace=NAMESPACE)
    def handle_player_ready(data):
        data = v.as_dict(data)
        code = v.room_code(data.get("roomCode"))
        pid = v.player_id(data.get("playerID"))
        room = rooms.get(code) if code else None
        if room is None or pid is None:
            return
        with room.lock:
            room.set_ready(pid, bool(data.get("ready", True)))
        push_room(socketio, room)

    # ---- start_game ----------------------------------------------------
    # The TV sends only roomCode (no playerID), so authorization is by socket:
    # either a board socket for this room, or the host's phone.
    @socketio.on("start_game", namespace=NAMESPACE)
    def handle_start_game(data):
        data = v.as_dict(data)
        sid = request.sid
        code = v.room_code(data.get("roomCode"))
        room = rooms.get(code) if code else None
        if room is None:
            push_error(socketio, sid, "Room not found", "ROOM_NOT_FOUND")
            return

        with room.lock:
            if room.state is RoomState.PLAYING:
                return                                  # idempotent
            is_tv = sid in room.tv_sids
            actor = room.player_by_sid(sid)
            if not is_tv and (actor is None or not actor.is_host):
                push_error(socketio, sid, "Only the host can start", "NOT_HOST")
                return

            # The solo placeholder is only materialized here, at the moment
            # the game is actually starting -- and only if nobody real
            # joined the lobby in the meantime (see handle_create_room). A
            # phone that did join takes its place entirely; the placeholder
            # is never created in that case. start_game for a solo room is
            # only ever sent by the TV itself (TVRootViewModel; the phone's
            # own lobby screen has no start action), so `sid` here is
            # reliably the TV's own -- exactly what the placeholder needs so
            # the TV can act on its behalf via game_action's tv_sids bypass.
            if room.solo and not room.players and room.pending_host_id:
                room.add_player(room.pending_host_id, room.pending_host_name, sid)
                room.pending_host_id = None

            engine_cls = engine_for(room.game_id)
            minimum = 1 if room.solo else engine_cls.min_players
            players = room.connected_players()
            if len(players) < minimum:
                push_error(socketio, sid,
                           f"Need at least {minimum} players", "NOT_ENOUGH_PLAYERS")
                return

            # This same handler is what "Play Again" now calls on a room
            # sitting in RESULTS (see TVRootViewModel.playAgain) -- the room
            # and its player list never actually go away when a round ends
            # (finish_game only changes room.state), so starting again here
            # reuses the same Player objects a fresh LOBBY start would have
            # used for the first time. Resetting score before every start,
            # not just a detected rematch, keeps this one code path correct
            # for both: a brand-new game's players are already at zero, so
            # this is a no-op there, and a rematch's players actually get
            # the clean slate "Play Again" implies instead of carrying last
            # round's total into the new one.
            for p in room.players:
                p.score = 0

            room.engine = engine_cls(room, Broadcaster(socketio, room))
            room.state = RoomState.PLAYING
            room.generation += 1
            room.touch()
            try:
                room.engine.start(players)
            except Exception:
                logger.exception("engine start failed room=%s", code)
                room.engine = None
                room.state = RoomState.LOBBY
                push_error(socketio, sid, "Could not start game", "ENGINE_ERROR")
                return

        # The rules interstitial (TV + phone) is driven by this one event: the
        # backend is the single source of truth for how-to-play text, so it
        # rides along on the broadcast both clients already receive.
        socketio.emit("game_started",
                      {"roomCode": code, "gameID": room.game_id,
                       "rules": rules_for(room.game_id)},
                      to=code, namespace=NAMESPACE)
        push_room(socketio, room)
        start_pump(socketio, room)
        logger.info("room %s started game=%s", code, room.game_id)

    # ---- game_action ---------------------------------------------------
    @socketio.on("game_action", namespace=NAMESPACE)
    def handle_game_action(data):
        data = v.as_dict(data)
        sid = request.sid
        if _rate_limited(sid):
            return

        code = v.room_code(data.get("roomCode"))
        pid = v.player_id(data.get("playerID"))
        verb = v.action(data.get("action"))
        payload = v.action_data(data.get("data"))

        room = rooms.get(code) if code else None
        if room is None or pid is None or verb is None:
            return
        if room.state is not RoomState.PLAYING or room.engine is None:
            return

        with room.lock:
            actor = room.player(pid)
            # playerID is a client-supplied device UUID. Without this check any
            # phone could submit actions as any other player.
            if actor is None or actor.sid != sid:
                if sid not in room.tv_sids:
                    push_error(socketio, sid, "Not in this room", "NOT_IN_ROOM")
                    return
            try:
                room.engine.handle_action(pid, verb, payload)
            except Exception:
                logger.exception("action failed room=%s action=%s", code, verb)
                return
            room.touch()
            over = room.engine.is_over()

        broadcast_state(socketio, room)
        if over:
            finish_game(socketio, room)

    # ---- leave_room ----------------------------------------------------
    @socketio.on("leave_room", namespace=NAMESPACE)
    def handle_leave_room(data):
        data = v.as_dict(data)
        sid = request.sid
        code = v.room_code(data.get("roomCode"))
        pid = v.player_id(data.get("playerID"))
        room = rooms.get(code) if code else None
        if room is None:
            return

        with room.lock:
            if pid:
                room.remove_player(pid)
            else:
                room.detach_sid(sid)
            if room.engine is not None and pid:
                try:
                    room.engine.on_player_leave(pid)
                except Exception:
                    logger.exception("on_player_leave failed room=%s", code)

        socket_leave_room(code, namespace=NAMESPACE)
        rooms.unbind_sid(sid)
        push_room(socketio, room)

    # ---- disconnect ----------------------------------------------------
    @socketio.on("disconnect", namespace=NAMESPACE)
    def handle_disconnect():
        sid = request.sid
        with _bucket_lock:
            _action_buckets.pop(sid, None)

        room = rooms.get_by_sid(sid)
        rooms.unbind_sid(sid)
        if room is None:
            return

        with room.lock:
            who = room.detach_sid(sid)
            if who and who != "__tv__" and room.engine is not None:
                try:
                    room.engine.on_player_leave(who)
                except Exception:
                    logger.exception("on_player_leave failed room=%s", room.code)

        push_room(socketio, room)

    start_reaper(socketio)
    print("✅ Native hub events registered on /native")
