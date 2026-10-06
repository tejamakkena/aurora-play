"""The /native namespace, exercised through a real Socket.IO test client.

Payload shapes are asserted key-for-key against the Swift Codable structs. A
mismatch does not raise on the client -- GameSocketManager decodes with `try?`
and drops the message -- so the screen would simply never update.
"""

import pytest

from app import create_app
from utils.room_manager import RoomState, rooms

NS = "/native"


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")   # returns (app, socketio)


@pytest.fixture
def tv(server):
    app, socketio = server
    client = socketio.test_client(app, namespace=NS)
    assert client.is_connected(NS)
    return client


def received(client, name=None):
    events = client.get_received(NS)
    return [e for e in events if name is None or e["name"] == name]


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


def open_room(app, socketio, tv, game_id="cipher_grid", players=4):
    tv.emit("create_room", {"gameID": game_id, "hostName": "TV", "hostID": "tv-1"},
            namespace=NS)
    room = latest(tv, "room_updated")
    phones = []
    for i in range(players):
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": room["code"], "playerName": f"P{i}",
                                 "playerID": f"dev-{i}", "isTV": False}, namespace=NS)
        phone.get_received(NS)
        phones.append(phone)
    tv.get_received(NS)
    return room["code"], phones


def begin_game(tv, code):
    # Since the rules gate landed, start_game alone leaves the engine held:
    # the TV (always authorized, mirroring start_game) lifts the gate here.
    tv.emit("begin_game", {"roomCode": code}, namespace=NS)


class TestNamespaceIsolation:
    def test_default_namespace_no_longer_answers_create_room(self, server):
        # Five browser games (connect4, digit_guess, pong, stickfight,
        # roadfighter) used to all register create_room on '/' -- a real bug
        # found by hand: Flask-SocketIO keeps only the last registration for
        # a given (namespace, event) pair, so roadfighter's handler silently
        # ate every other game's create_room, discarding anything whose
        # game_type wasn't 'roadfighter' with no error at all. See
        # test_default_namespace_collision.py for the full writeup and the
        # per-game regression coverage. Each of the five now has its own
        # dedicated namespace (mirroring /native's own isolation below), so
        # the bare default namespace must not answer create_room for any of
        # them any more, roadfighter included.
        app, socketio = server
        legacy = socketio.test_client(app)
        assert legacy.is_connected()
        legacy.emit("create_room", {"game_type": "roadfighter", "player_name": "Racer"})
        assert not legacy.get_received()

    def test_hub_events_do_not_reach_the_default_namespace(self, server):
        app, socketio = server
        legacy = socketio.test_client(app)
        legacy.get_received()
        legacy.emit("player_ready", {"roomCode": "ABC123", "playerID": "x"})
        assert legacy.get_received() == []


class TestCreateRoom:
    def test_replies_with_room_updated(self, tv):
        # The TV never emits join_room and listens only to room_updated, so
        # that is what has to carry the new room.
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        room = latest(tv, "room_updated")
        assert set(room) == {"code", "gameID", "players", "state", "phase",
                               "contentPack", "topic", "botsAllowed",
                               "usesContentPack", "micPlayerID", "night", "teams"}
        assert room["gameID"] == "trivia" and room["state"] == "lobby"
        assert len(room["code"]) == 6

    def test_tv_is_not_listed_as_a_player(self, tv):
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        assert latest(tv, "room_updated")["players"] == []

    def test_rejects_an_unknown_game(self, tv):
        tv.emit("create_room", {"gameID": "not_a_game", "hostName": "TV", "hostID": "t"},
                namespace=NS)
        error = latest(tv, "error")
        assert set(error) == {"message", "code"}
        assert error["code"] == "INVALID_GAME"


class TestJoinRoom:
    def test_room_joined_matches_the_swift_struct(self, server, tv):
        app, socketio = server
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        code = latest(tv, "room_updated")["code"]

        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code, "playerName": "Teja",
                                 "playerID": "dev-1", "isTV": False}, namespace=NS)
        payload = latest(phone, "room_joined")
        assert set(payload) == {"room", "playerID"}
        assert payload["playerID"] == "dev-1"
        assert set(payload["room"]["players"][0]) == {
            "id", "name", "isReady", "score", "isHost", "isBot"}

    def test_first_phone_becomes_host(self, server, tv):
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "trivia", players=3)
        tv.emit("player_ready", {"roomCode": code, "playerID": "dev-0"}, namespace=NS)
        roster = latest(tv, "room_updated")["players"]
        assert [p["isHost"] for p in roster] == [True, False, False]

    def test_accepts_a_lowercase_code(self, server, tv):
        app, socketio = server
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        code = latest(tv, "room_updated")["code"]
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code.lower(), "playerName": "Late",
                                 "playerID": "dev-late", "isTV": False}, namespace=NS)
        assert latest(phone, "room_joined")["playerID"] == "dev-late"

    def test_unknown_room_is_rejected(self, server):
        app, socketio = server
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": "ZZZZZZ", "playerName": "x",
                                 "playerID": "d", "isTV": False}, namespace=NS)
        assert latest(phone, "error")["code"] == "ROOM_NOT_FOUND"

    def test_room_is_capped_at_max_players(self, server, tv):
        # TVLobbyView builds a range from players.count to maxPlayers, which
        # traps if the server ever reports more players than the cap.
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "battleship", players=2)
        extra = socketio.test_client(app, namespace=NS)
        extra.emit("join_room", {"roomCode": code, "playerName": "Third",
                                 "playerID": "dev-3", "isTV": False}, namespace=NS)
        assert latest(extra, "error")["code"] == "ROOM_FULL"

    def test_a_second_tv_joins_without_taking_a_seat(self, server, tv):
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "trivia", players=2)
        board = socketio.test_client(app, namespace=NS)
        board.emit("join_room", {"roomCode": code, "playerName": "", "playerID": "",
                                 "isTV": True}, namespace=NS)
        assert len(latest(board, "room_joined")["room"]["players"]) == 2


class TestStartGame:
    def test_moves_the_room_to_playing(self, server, tv):
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        room = latest(tv, "room_updated")
        assert room["state"] == "playing"
        # The engine is held until the host taps Begin (the rules gate).
        assert room["phase"] == "rules"

    def test_rejects_too_few_players(self, server, tv):
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "cipher_grid", players=1)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        assert latest(tv, "error")["code"] == "NOT_ENOUGH_PLAYERS"

    def test_a_non_host_phone_cannot_start(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        phones[2].emit("start_game", {"roomCode": code}, namespace=NS)
        assert latest(phones[2], "error")["code"] == "NOT_HOST"

    def test_every_phone_receives_private_state(self, server, tv):
        # The phone leaves its waiting screen on private_state, not on
        # game_started, which has no listener in the Swift app.
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        socketio.sleep(1.2)
        for i, phone in enumerate(phones):
            payload = latest(phone, "private_state")
            assert set(payload) == {"roomCode", "playerID", "privateData"}
            assert payload["playerID"] == f"dev-{i}"

    def test_board_state_reaches_the_tv_without_the_secret(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        socketio.sleep(1.2)
        board = latest(tv, "game_state")
        assert set(board) == {"roomCode", "boardState"}
        assert len(board["boardState"]["words"]) == 25
        assert "key" not in board["boardState"]

    def test_exactly_two_spymasters_hold_the_key(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        socketio.sleep(1.2)
        with_key = [i for i, p in enumerate(phones)
                    if latest(p, "private_state")["privateData"].get("key")]
        assert len(with_key) == 2

    def test_game_started_carries_the_rules_payload(self, server, tv):
        # The how-to-play interstitial on the TV and the phones is driven by
        # this one broadcast; the backend is the single source of truth for
        # the rules text (see games/native_hub/rules.py).
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "trivia", players=2)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        payload = latest(tv, "game_started")
        assert set(payload) == {"roomCode", "gameID", "rules"}
        assert payload["gameID"] == "trivia"
        rules = payload["rules"]
        assert set(rules) == {"gameID", "title", "objective", "rules", "controls"}
        assert rules["title"] == "Trivia"
        assert 3 <= len(rules["rules"]) <= 6
        # Phones get the same event, so the controller card shows the same text.
        assert latest(phones[0], "game_started")["rules"] == rules

    def test_rematch_restarts_a_finished_room_and_resets_scores(self, server, tv):
        # "Play Again" (TVRootViewModel.playAgain) sends exactly this same
        # start_game event against a room already sitting in RESULTS --
        # finish_game only ever changes room.state, it never clears
        # room.players or room.engine, so the same handler that starts a
        # fresh room from LOBBY has to also handle being called again from
        # RESULTS for a genuine rematch instead of erroring out.
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        room = rooms.get(code)
        room.players[0].score = 40   # as if they'd just finished a round
        room.state = RoomState.RESULTS

        tv.emit("start_game", {"roomCode": code}, namespace=NS)

        assert latest(tv, "room_updated")["state"] == "playing"
        assert all(p.score == 0 for p in room.players)

    def test_the_pump_keeps_publishing(self, server, tv):
        # Board view models subscribe only after room_updated builds them, and
        # there is no request_state event, so the pump is the recovery path.
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        socketio.sleep(1.2)
        tv.get_received(NS)
        socketio.sleep(1.4)
        assert received(tv, "game_state")


class TestBeginGame:
    """The host-gated rules phase: start_game holds the engine, begin_game
    starts it. Regression cover for the clock-already-running flaw (the
    engine used to start server-side the moment Start Game was pressed,
    while the rules interstitial was still up on every screen)."""

    def test_start_game_holds_the_engine_until_begin(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        socketio.sleep(1.2)
        assert received(tv, "game_state") == []
        for phone in phones:
            assert received(phone, "private_state") == []
        # received() drains the client's queue, so read the phase off the room.
        assert rooms.get(code).phase == "rules"

    def test_begin_game_emits_game_begun_and_starts_the_pump(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        tv.emit("begin_game", {"roomCode": code}, namespace=NS)
        begun = latest(tv, "game_begun")
        assert set(begun) == {"roomCode", "gameID"}
        assert begun["gameID"] == "cipher_grid"
        # latest() drains the client's queue, so read the phase off the room.
        assert rooms.get(code).phase == "play"
        socketio.sleep(1.2)
        assert received(tv, "game_state")
        for phone in phones:
            assert received(phone, "private_state")

    def test_a_non_host_phone_cannot_begin(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        phones[2].emit("begin_game", {"roomCode": code}, namespace=NS)
        assert latest(phones[2], "error")["code"] == "NOT_HOST"
        # Still gated: nothing began (phase read off the room because
        # latest() drains the client's queue).
        assert rooms.get(code).phase == "rules"
        assert received(tv, "game_begun") == []

    def test_the_host_phone_can_begin(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        phones[0].emit("begin_game", {"roomCode": code, "playerID": "dev-0"},
                       namespace=NS)
        assert latest(tv, "game_begun")["roomCode"] == code

    def test_begin_game_is_idempotent(self, server, tv):
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        tv.emit("begin_game", {"roomCode": code}, namespace=NS)
        tv.emit("begin_game", {"roomCode": code}, namespace=NS)
        assert len(received(tv, "game_begun")) == 1

    def test_host_leaving_mid_rules_promotes_the_oldest_remaining_player(self, server, tv):
        # dev-0 joined first, so it holds the host flag; when it leaves
        # mid-rules, reassign_host promotes dev-1 and the gate survives.
        # trivia (min 2) so the room still has enough players to begin.
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "trivia", players=3)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        hosts = [p for p in latest(tv, "room_updated")["players"] if p["isHost"]]
        assert [p["id"] for p in hosts] == ["dev-0"]
        phones[0].emit("leave_room", {"roomCode": code, "playerID": "dev-0"},
                       namespace=NS)
        hosts = [p for p in latest(tv, "room_updated")["players"] if p["isHost"]]
        assert [p["id"] for p in hosts] == ["dev-1"]
        phones[1].emit("begin_game", {"roomCode": code, "playerID": "dev-1"},
                       namespace=NS)
        assert latest(tv, "game_begun")["roomCode"] == code

    def test_a_player_joining_mid_rules_gets_the_rules_screen(self, server, tv):
        # The gate is still open, so the join is allowed; the joiner gets
        # the rules payload re-sent to it directly and room_updated reports
        # the rules phase.
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "trivia", players=2)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        late = socketio.test_client(app, namespace=NS)
        late.emit("join_room", {"roomCode": code, "playerName": "Late",
                                "playerID": "dev-late", "isTV": False},
                  namespace=NS)
        # get_received drains the queue, so read every event from one batch.
        batch = {e["name"]: e["args"][0] for e in late.get_received(NS)}
        assert batch["room_joined"]["room"]["state"] == "playing"
        assert batch["room_joined"]["room"]["phase"] == "rules"
        assert batch["game_started"]["rules"]["title"] == "Trivia"

    def test_begin_with_too_few_players_stays_gated(self, server, tv):
        # Everyone left while the rules were up: refusing to begin beats
        # starting a game nobody can play.
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        for i, phone in enumerate(phones):
            phone.emit("leave_room", {"roomCode": code, "playerID": f"dev-{i}"},
                       namespace=NS)
        tv.emit("begin_game", {"roomCode": code}, namespace=NS)
        # Phase read off the room: latest() below drains the client's queue.
        assert rooms.get(code).phase == "rules"
        assert latest(tv, "error")["code"] == "NOT_ENOUGH_PLAYERS"

    def test_actions_during_the_rules_phase_are_ignored(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        phones[0].emit("game_action", {"roomCode": code, "playerID": "dev-0",
                                       "action": "guess", "data": {"index": 0}},
                       namespace=NS)
        socketio.sleep(0.5)
        assert received(tv, "game_state") == []
        assert received(phones[0], "error") == []


class TestGameAction:
    def test_a_phone_cannot_act_as_another_player(self, server, tv):
        # playerID is a client-supplied device UUID, so it has to be checked
        # against the socket it arrived on.
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        socketio.sleep(1.2)
        phones[1].get_received(NS)
        phones[1].emit("game_action", {"roomCode": code, "playerID": "dev-0",
                                       "action": "guess", "data": {"index": 0}},
                       namespace=NS)
        assert latest(phones[1], "error")["code"] == "NOT_IN_ROOM"

    def test_actions_before_the_game_starts_are_ignored(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        phones[0].get_received(NS)
        phones[0].emit("game_action", {"roomCode": code, "playerID": "dev-0",
                                       "action": "guess", "data": {"index": 0}},
                       namespace=NS)
        assert received(phones[0], "game_state") == []


class TestSoloRoom:
    def test_placeholder_player_is_deferred_until_start_not_created_immediately(self, tv):
        # Reported directly: a solo game (Atlas, whose only input is typed
        # text) had no way to ever bring in a phone, because this player
        # used to be created immediately on create_room and the room
        # auto-started before a phone could join it. The room must sit with
        # zero players right up until start_game, so its lobby (and real
        # room code) stays genuinely open for one to join in the meantime.
        tv.emit("create_room", {"gameID": "neon_snake", "hostName": "Solo",
                                "hostID": "tv-solo", "solo": True}, namespace=NS)
        room = latest(tv, "room_updated")
        assert room["players"] == []

        tv.emit("start_game", {"roomCode": room["code"]}, namespace=NS)
        started = latest(tv, "room_updated")
        assert started["state"] == "playing"
        assert len(started["players"]) == 1

    def test_a_phone_joining_before_start_replaces_the_placeholder_entirely(self, server, tv):
        # The other half of the same fix: once a phone joins for real, the
        # placeholder must never appear at all -- otherwise a game like
        # Atlas would seat a ghost "Player 1" that can never answer
        # alongside the real player, breaking turn order instead of fixing
        # it. See AtlasEngine.tick's own elimination-on-timeout rule for why
        # that combination is actively harmful, not just redundant.
        app, socketio = server
        tv.emit("create_room", {"gameID": "atlas", "hostName": "Solo",
                                "hostID": "tv-solo", "solo": True}, namespace=NS)
        code = latest(tv, "room_updated")["code"]

        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code, "playerName": "Real Player",
                                 "playerID": "dev-real", "isTV": False}, namespace=NS)
        phone.get_received(NS)

        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        started = latest(tv, "room_updated")
        assert started["state"] == "playing"
        assert [p["id"] for p in started["players"]] == ["dev-real"]

    def test_the_tv_can_send_actions_for_itself(self, server, tv):
        app, socketio = server
        tv.emit("create_room", {"gameID": "neon_snake", "hostName": "Solo",
                                "hostID": "tv-solo", "solo": True}, namespace=NS)
        code = latest(tv, "room_updated")["code"]
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        tv.emit("game_action", {"roomCode": code, "playerID": "tv-solo",
                                "action": "turn", "data": {"direction": "down"}},
                namespace=NS)
        socketio.sleep(0.9)
        assert latest(tv, "game_state")["boardState"]["snakes"][0]["body"]

    def test_solo_bypasses_the_minimum_player_gate(self, tv):
        # cipher_grid needs four players normally.
        tv.emit("create_room", {"gameID": "cipher_grid", "hostName": "Solo",
                                "hostID": "tv-solo", "solo": True}, namespace=NS)
        code = latest(tv, "room_updated")["code"]
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        assert latest(tv, "room_updated")["state"] == "playing"


class TestLeaveAndReconnect:
    def test_leaving_removes_the_player(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "trivia", players=3)
        phones[1].emit("leave_room", {"roomCode": code, "playerID": "dev-1"},
                       namespace=NS)
        roster = latest(tv, "room_updated")["players"]
        assert [p["id"] for p in roster] == ["dev-0", "dev-2"]

    def test_rejoining_mid_game_resumes_the_same_seat(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        socketio.sleep(1.2)
        phones[1].disconnect(namespace=NS)

        again = socketio.test_client(app, namespace=NS)
        again.emit("join_room", {"roomCode": code, "playerName": "P1",
                                 "playerID": "dev-1", "isTV": False}, namespace=NS)
        # get_received drains the queue, so read both events from one batch.
        batch = {e["name"]: e["args"][0] for e in again.get_received(NS)}
        assert batch["room_joined"]["playerID"] == "dev-1"
        # Resumed immediately rather than waiting for the next pump cycle.
        assert batch["private_state"]["playerID"] == "dev-1"

    def test_a_new_player_cannot_join_a_game_in_progress(self, server, tv):
        # Past the rules gate, the room is closed to newcomers; while the
        # gate is still up (phase "rules") a late joiner is seated instead
        # (see TestBeginGame).
        app, socketio = server
        code, _ = open_room(app, socketio, tv, "cipher_grid", players=4)
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        begin_game(tv, code)
        latecomer = socketio.test_client(app, namespace=NS)
        latecomer.emit("join_room", {"roomCode": code, "playerName": "Late",
                                     "playerID": "dev-late", "isTV": False},
                       namespace=NS)
        assert latest(latecomer, "error")["code"] == "GAME_IN_PROGRESS"


class TestLobbyOptions:
    """Bots and question language, set from the TV or host lobby."""

    def test_room_reports_bot_and_pack_support(self, tv):
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        room = latest(tv, "room_updated")
        assert room["botsAllowed"] is True
        assert room["usesContentPack"] is True
        assert room["contentPack"] == "en"

    def test_create_room_honors_topic(self, tv):
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV",
                                "hostID": "tv-1", "topic": "Tollywood movies"},
                namespace=NS)
        room = latest(tv, "room_updated")
        assert room["topic"] == "Tollywood movies"
        assert rooms.get(room["code"]).topic == "Tollywood movies"

    def test_create_room_topic_defaults_empty(self, tv):
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV",
                                "hostID": "tv-1"},
                namespace=NS)
        room = latest(tv, "room_updated")
        assert room["topic"] == ""

    def test_create_room_validates_seed_questions(self, tv):
        seeds = [
            {"question": "Good one?", "options": ["A", "B", "C", "D"],
             "correct_answer": 1},
            {"question": "Bad: only three", "options": ["A", "B", "C"],
             "correct_answer": 0},
            "not a dict",
            {"question": "Emoji \U0001F600 no", "options": ["A", "B", "C", "D"],
             "correct_answer": 0},
        ]
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV",
                                "hostID": "tv-1", "seedQuestions": seeds},
                namespace=NS)
        room = latest(tv, "room_updated")
        stored = rooms.get(room["code"]).seed_questions
        assert len(stored) == 1
        assert stored[0]["question"] == "Good one?"
        assert stored[0]["correct_answer"] == 1

    def test_create_room_seed_questions_default_empty(self, tv):
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV",
                                "hostID": "tv-1"},
                namespace=NS)
        room = latest(tv, "room_updated")
        assert rooms.get(room["code"]).seed_questions == []

    def test_tv_can_switch_content_pack(self, tv):
        tv.emit("create_room", {"gameID": "kbc", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        code = latest(tv, "room_updated")["code"]
        tv.emit("set_content_pack", {"roomCode": code, "contentPack": "te"}, namespace=NS)
        assert latest(tv, "room_updated")["contentPack"] == "te"
        assert rooms.get(code).content_pack == "te"
        tv.emit("set_content_pack", {"roomCode": code, "contentPack": "xx"}, namespace=NS)
        assert latest(tv, "room_updated")["contentPack"] == "en"

    def test_non_host_phone_cannot_switch_pack(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "trivia", players=2)
        phones[1].emit("set_content_pack", {"roomCode": code, "contentPack": "hi"},
                       namespace=NS)
        assert latest(phones[1], "error")["code"] == "NOT_HOST"
        assert rooms.get(code).content_pack == "en"

    def test_bots_refused_for_games_without_a_policy(self, tv):
        tv.emit("create_room", {"gameID": "chess", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        room = latest(tv, "room_updated")
        assert room["botsAllowed"] is False
        tv.emit("add_bot", {"roomCode": room["code"]}, namespace=NS)
        assert latest(tv, "error")["code"] == "BOTS_UNSUPPORTED"
        assert rooms.get(room["code"]).players == []

    def test_tv_adds_and_removes_bot(self, tv):
        tv.emit("create_room", {"gameID": "most_likely_to", "hostName": "TV",
                                "hostID": "tv-1"}, namespace=NS)
        code = latest(tv, "room_updated")["code"]
        tv.emit("add_bot", {"roomCode": code}, namespace=NS)
        players = latest(tv, "room_updated")["players"]
        assert len(players) == 1 and players[0]["isBot"] is True
        tv.emit("remove_bot", {"roomCode": code, "botID": players[0]["id"]}, namespace=NS)
        assert latest(tv, "room_updated")["players"] == []
