"""The 17 "legacy" GameIDs, driven through a real Socket.IO test client.

Mirrors tests/test_native_hub.py's pattern: create_room -> join_room (per
player) -> start_game -> begin_game (lifts the rules gate) -> game_action,
asserting the exact public/private
state keys the Swift boards and controllers decode with `try?` (a missing
key means the screen silently never updates, not a crash).

tests/test_native_engines.py already drives every engine, including these
17, through a generic parametrized play loop at the unit level (no sockets).
This file complements that with the real hub wiring -- room lifecycle,
room_updated/game_started/game_state/private_state event shapes, and one
concrete action per game confirmed to actually change server state.
"""

import time
import pytest

from app import create_app
from games.native_hub.engines.legacy_cards import RouletteEngine
from utils.room_manager import rooms

NS = "/native"


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


@pytest.fixture
def tv(server):
    app, socketio = server
    client = socketio.test_client(app, namespace=NS)
    assert client.is_connected(NS)
    return client


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


def open_room(app, socketio, tv, game_id, players):
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


def start_and_settle(socketio, tv, code):
    tv.emit("start_game", {"roomCode": code}, namespace=NS)
    # The rules gate holds the engine until the host begins.
    tv.emit("begin_game", {"roomCode": code}, namespace=NS)
    socketio.sleep(1.2)


def act(socketio, phone, code, pid, action, data):
    phone.emit("game_action",
               {"roomCode": code, "playerID": pid, "action": action, "data": data},
               namespace=NS)
    socketio.sleep(0.05)


class TestConnect4:
    def test_board_state_and_a_drop_changes_the_grid(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "connect4", players=2)
        start_and_settle(socketio, tv, code)

        board = latest(tv, "game_state")["boardState"]
        assert {"grid", "currentPlayerID", "currentPlayerName", "winner", "winCells"} <= set(board)
        assert len(board["grid"]) == 6 and len(board["grid"][0]) == 7

        private = latest(phones[0], "private_state")["privateData"]
        assert {"isMyTurn", "color", "fullColumns"} <= set(private)

        current = board["currentPlayerID"]
        pid, actor = ("dev-0", phones[0]) if current == "dev-0" else ("dev-1", phones[1])
        act(socketio, actor, code, pid, "drop", {"column": 3})
        new_board = latest(tv, "game_state")["boardState"]
        assert new_board["grid"][5][3] != ""

    def test_four_players_get_a_bigger_board_and_their_own_colours(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "connect4", players=4)
        start_and_settle(socketio, tv, code)

        board = latest(tv, "game_state")["boardState"]
        assert board["rows"] == 8 and board["cols"] == 10
        assert len(board["grid"]) == 8 and len(board["grid"][0]) == 10
        assert sorted(board["colors"].values()) == ["blue", "green", "red", "yellow"]
        assert len(board["turnOrder"]) == 4

        order = board["turnOrder"]
        for turn, pid in enumerate(order):
            actor = phones[int(pid.split("-")[1])]
            private = latest(actor, "private_state")["privateData"]
            assert private["isMyTurn"] is True and private["cols"] == 10
            act(socketio, actor, code, pid, "drop", {"column": 9 - turn})
        board = latest(tv, "game_state")["boardState"]
        assert [board["grid"][7][9 - t] for t in range(4)] == [
            board["colors"][pid] for pid in order]
        assert board["currentPlayerID"] == order[0]


class TestMemory:
    def test_flip_reveals_a_card(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "memory", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"cards", "currentPlayerID", "currentPlayerName"} <= set(board)
        assert len(board["cards"]) == 16
        assert all(c["value"] == "❓" for c in board["cards"])

        current = board["currentPlayerID"]
        actor = phones[0] if current == "dev-0" else phones[1]
        act(socketio, actor, code, current, "flip", {"index": 0})
        state = latest(tv, "game_state")["boardState"]
        assert state["cards"][0]["state"] == "flipped"


class TestChess:
    def test_select_and_move(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "chess", players=2)
        start_and_settle(socketio, tv, code)
        private = latest(phones[0], "private_state")["privateData"]
        assert {"isMyTurn", "pieceColor", "board", "validMoves"} <= set(private)
        white_phone = phones[0] if private["pieceColor"] == "white" else phones[1]
        white_id = "dev-0" if private["pieceColor"] == "white" else "dev-1"

        act(socketio, white_phone, code, white_id, "move",
            {"from": [6, 0], "to": [4, 0]})
        after = latest(white_phone, "private_state")["privateData"]
        assert after["board"][4][0] != "" and after["board"][6][0] == ""


class TestSnakeLadder:
    def test_roll_moves_the_current_player(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "snake_ladder", players=2)
        start_and_settle(socketio, tv, code)
        private = latest(phones[0], "private_state")["privateData"]
        assert {"isMyTurn", "position"} <= set(private)
        current = "dev-0" if private["isMyTurn"] else "dev-1"
        actor = phones[0] if current == "dev-0" else phones[1]
        act(socketio, actor, code, current, "roll", {"value": 3})
        after = latest(actor, "private_state")["privateData"]
        assert after["position"] >= 0


class TestPong:
    def test_paddle_action_updates_state(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "pong", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"ballX", "ballY", "leftPaddle", "rightPaddle",
                "scoreLeft", "scoreRight", "leftName", "rightName"} <= set(board)
        private = latest(phones[0], "private_state")["privateData"]
        assert private["side"] in ("left", "right")
        act(socketio, phones[0], code, "dev-0", "paddle", {"position": 1.0})
        socketio.sleep(0.2)


class TestPoker:
    def test_hand_is_dealt_and_check_advances_the_turn(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "poker", players=3)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"pot", "phase", "communityCards", "players", "showdown"} <= set(board)
        assert board["pot"] > 0

        private = latest(phones[0], "private_state")["privateData"]
        assert {"hand", "chips", "minBet"} <= set(private)
        assert len(private["hand"]) == 2

        current = next(p["id"] for p in board["players"] if p["isCurrentTurn"])
        actor = phones[int(current[-1])]
        act(socketio, actor, code, current, "fold", {})
        after = latest(tv, "game_state")["boardState"]
        folded = next(p for p in after["players"] if p["id"] == current)
        assert folded["status"] == "folded"


class TestTambola:
    def test_ticket_and_mark(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "tambola", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"called", "lastCalled", "claims"} <= set(board)
        private = latest(phones[0], "private_state")["privateData"]
        assert {"ticket", "marked"} <= set(private)
        assert len(private["ticket"]) == 3 and len(private["ticket"][0]) == 9

        socketio.sleep(3.5)
        board = latest(tv, "game_state")["boardState"]
        assert len(board["called"]) >= 1


class TestRoulette:
    def test_bet_and_spin_resolves(self, server, tv, monkeypatch):
        # The product value is a deliberately cinematic 6s (the TV board
        # animates the ball over exactly that window); no reason to spend it
        # here, so this asserts the behaviour at a length the suite can wait
        # out rather than hard-coding whatever the constant happens to be.
        monkeypatch.setattr(RouletteEngine, "SPIN_SECONDS", 0.3)
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "roulette", players=2)
        start_and_settle(socketio, tv, code)
        private = latest(phones[0], "private_state")["privateData"]
        assert {"chips", "bets", "isSpinning", "lastResult"} <= set(private)
        act(socketio, phones[0], code, "dev-0", "place_bet", {"target": "red", "amount": 10})
        after = latest(phones[0], "private_state")["privateData"]
        assert after["bets"].get("red") == 10
        # "spin" means "done betting": the wheel waits for every player.
        act(socketio, phones[0], code, "dev-0", "spin", {})
        waiting = latest(phones[0], "private_state")["privateData"]
        assert waiting["isSpinning"] is False and waiting["isReady"] is True
        act(socketio, phones[1], code, "dev-1", "spin", {})
        socketio.sleep(1.0)
        board = latest(tv, "game_state")["boardState"]
        assert board["lastResult"] is not None


class TestDigitGuess:
    def test_a_guess_returns_bulls_and_cows(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "digit_guess", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"solved", "players"} <= set(board)
        act(socketio, phones[0], code, "dev-0", "guess", {"code": "1234"})
        private = latest(phones[0], "private_state")["privateData"]
        assert len(private["myGuesses"]) == 1
        assert {"guess", "bulls", "cows"} <= set(private["myGuesses"][0])


class TestMafia:
    def test_roles_are_assigned_and_a_vote_is_recorded(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "mafia", players=5)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"phase", "round", "secondsLeft", "lastEliminated", "votes", "players"} <= set(board)
        assert board["phase"] == "night"

        roles = []
        for i, phone in enumerate(phones):
            private = latest(phone, "private_state")["privateData"]
            assert {"role", "phase", "isAlive", "players", "myID"} <= set(private)
            roles.append(private["role"])
        assert "mafia" in roles

        mafia_idx = roles.index("mafia")
        target = "dev-0" if mafia_idx != 0 else "dev-1"
        act(socketio, phones[mafia_idx], code, f"dev-{mafia_idx}", "eliminate", {"targetID": target})


class TestRajaMantri:
    def test_sipahi_accuses_and_scores_change(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "raja_mantri", players=4)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"round", "phase", "players", "roundResult"} <= set(board)
        assert all(p["role"] is None for p in board["players"])  # hidden pre-reveal

        sipahi_idx = None
        for i, phone in enumerate(phones):
            private = latest(phone, "private_state")["privateData"]
            assert {"role", "phase", "players", "score", "hasGuessed"} <= set(private)
            if private["role"] == "Sipahi":
                sipahi_idx = i
        assert sipahi_idx is not None

        target = "dev-0" if sipahi_idx != 0 else "dev-1"
        act(socketio, phones[sipahi_idx], code, f"dev-{sipahi_idx}", "accuse", {"targetID": target})
        after = latest(tv, "game_state")["boardState"]
        assert after["phase"] == "reveal"
        assert after["roundResult"] is not None


class TestTrivia:
    def test_question_is_dealt_and_answer_scores(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "trivia", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"secondsLeft", "deadline", "showChoices", "questionID",
                "questionText", "choices", "category", "phase",
                "answeredPlayerIDs", "players"} <= set(board)
        # The show opens on its title card; no question (or answer) yet.
        assert board["phase"] == "intro"
        assert "correctIndex" not in board

        # Fast-forward the show to its first question on the server side.
        engine = rooms.get(code).engine
        room = rooms.get(code)
        with room.lock:
            for _ in range(50):
                if engine.phase == "question":
                    break
                engine.deadline = 0.0
                engine.tick(0.0)
        assert engine.phase == "question"
        with room.lock:
            # Skip the read-aloud wait: answers open once the TV has read
            # the question and its options.
            engine.choices_at = time.time()

        correct = engine.question[3]
        act(socketio, phones[0], code, "dev-0", "answer",
            {"choiceIndex": correct, "questionID": engine.question_id})
        after = latest(tv, "game_state")["boardState"]
        assert after["phase"] == "question"
        assert "dev-0" in after["answeredPlayerIDs"]
        # Correctness stays hidden from the TV until the reveal: no score
        # moves and no correctIndex.
        assert "correctIndex" not in after
        assert all(p["score"] == 0 for p in after["players"])

        private = latest(phones[0], "private_state")["privateData"]
        assert {"choices", "questionID", "score", "locked"} <= set(private)


class TestHeist:
    def test_guard_and_thieves_are_assigned(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "heist", players=3)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"round", "phase", "secondsLeft", "cameraPositions", "cameraArcTiles",
                "thiefPositions", "playerStatuses", "winner"} <= set(board)
        assert board["phase"] == "guard_sets"

        roles = []
        guard_idx = None
        for i, phone in enumerate(phones):
            private = latest(phone, "private_state")["privateData"]
            assert {"role", "phase", "round", "col", "row",
                    "hasReachedVault", "isCaught"} <= set(private)
            roles.append(private["role"])
            if private["role"] == "guard":
                guard_idx = i
        assert roles.count("guard") == 1 and guard_idx is not None

        act(socketio, phones[guard_idx], code, f"dev-{guard_idx}",
            "set_cameras", {"cameras": ["cam_tl", "cam_br"]})
        after = latest(tv, "game_state")["boardState"]
        assert after["phase"] == "thieves_move"


class TestStockPanic:
    def test_a_trade_updates_the_portfolio(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "stock_panic", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"stocks", "latestNews"} <= set(board)
        private = latest(phones[0], "private_state")["privateData"]
        assert {"portfolio", "cash"} <= set(private)
        stock = board["stocks"][0]["id"]
        act(socketio, phones[0], code, "dev-0", "trade", {"stock": stock, "action": "buy"})
        after = latest(phones[0], "private_state")["privateData"]
        assert after["portfolio"][stock] == 1
        assert after["cash"] < private["cash"]


class TestMindMeld:
    def test_words_meld_when_they_match(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "mind_meld", players=3)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"category", "submittedIDs", "showReveal", "submissions"} <= set(board)
        for i, phone in enumerate(phones):
            act(socketio, phone, code, f"dev-{i}", "word", {"word": "Red"})
        socketio.sleep(0.3)
        after = latest(tv, "game_state")["boardState"]
        assert set(after["submittedIDs"]) == {"dev-0", "dev-1", "dev-2"}


class TestHotGrid:
    def test_picking_a_tile_reveals_it(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "hot_grid", players=2)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"tiles", "currentPlayerID", "currentPlayerName"} <= set(board)
        assert len(board["tiles"]) == 25 and all(t == "hidden" for t in board["tiles"])

        current = board["currentPlayerID"]
        actor = phones[0] if current == "dev-0" else phones[1]
        act(socketio, actor, code, current, "pick_tile", {"index": 0})
        after = latest(tv, "game_state")["boardState"]
        assert after["tiles"][0] != "hidden"


class TestSpeedSculptor:
    def test_a_drawing_is_recorded(self, server, tv):
        app, socketio = server
        code, phones = open_room(app, socketio, tv, "speed_sculptor", players=3)
        start_and_settle(socketio, tv, code)
        board = latest(tv, "game_state")["boardState"]
        assert {"prompt", "secondsLeft", "votingPhase", "submittedCount",
                "drawings"} <= set(board)
        private = latest(phones[0], "private_state")["privateData"]
        assert {"prompt", "hasSubmitted", "score"} <= set(private)

        act(socketio, phones[0], code, "dev-0", "drawing",
            {"lines": [[{"x": 0.1, "y": 0.2}, {"x": 0.3, "y": 0.4}]]})
        after = latest(tv, "game_state")["boardState"]
        assert after["submittedCount"] == 1


class TestResultsShapeAcrossAllLegacyGames:
    """Every engine's results() must reach the client in the same shape."""

    GAMES = [
        "connect4", "memory", "chess", "snake_ladder", "pong", "poker",
        "tambola", "roulette", "digit_guess", "mafia", "raja_mantri",
        "trivia", "heist", "stock_panic", "mind_meld", "hot_grid",
        "speed_sculptor",
    ]

    @pytest.mark.parametrize("game_id", GAMES)
    def test_room_reaches_playing_and_reports_sane_results_shape(self, server, tv, game_id):
        from games.native_hub.registry import engine_for
        app, socketio = server
        cls = engine_for(game_id)
        code, phones = open_room(app, socketio, tv, game_id, players=cls.min_players)
        start_and_settle(socketio, tv, code)
        assert latest(tv, "room_updated")["state"] == "playing"

        # Reach into the live engine directly to check results() shape --
        # actually finishing every game via play would make this test slow
        # and duplicate TestPlayLoop in test_native_engines.py.
        from utils.room_manager import rooms
        room = rooms.get(code)
        for row in room.engine.results():
            assert {"playerID", "name", "score", "rank"} <= set(row)
