"""A phone signed into Game Center tells the room who it is, so the TV's house
leaderboard can count the same person across rooms and nights.

The phone sends a short hash of Apple's team player id (``gcID``), never the
id itself. The server only passes it on, as ``gcID`` in the player's JSON, and
leaves it out for a guest so every older client sees the same shape as before.
"""

import pytest

from app import create_app
from utils import validators as v
from utils.room_manager import rooms

NS = "/native"
GOOD = "a1b2c3d4e5f60718"


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


def open_room(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"}, namespace=NS)
    return tv, latest(tv, "room_updated")["code"]


def join(server, code, name, pid, **extra):
    app, socketio = server
    phone = socketio.test_client(app, namespace=NS)
    phone.emit("join_room", {"roomCode": code, "playerName": name, "playerID": pid,
                             "isTV": False, **extra}, namespace=NS)
    return phone


class TestValidator:
    def test_accepts_sixteen_hex_characters(self):
        assert v.gc_id(GOOD) == GOOD
        assert v.gc_id(GOOD.upper()) == GOOD

    @pytest.mark.parametrize("bad", [None, 7, "", "short", GOOD + "0", "zzzzzzzzzzzzzzzz",
                                     "A1B2 C3D4E5F60718", "<script>alert(1)</scr"])
    def test_rejects_anything_else(self, bad):
        assert v.gc_id(bad) is None


class TestJoin:
    def test_a_game_center_phone_is_marked_in_the_room(self, server):
        tv, code = open_room(server)
        join(server, code, "Teja", "dev-1", gcID=GOOD)
        players = rooms.get(code).to_json()["players"]
        assert players[0]["gcID"] == GOOD

    def test_a_guest_has_no_gc_key_at_all(self, server):
        tv, code = open_room(server)
        join(server, code, "Guest", "dev-2")
        players = rooms.get(code).to_json()["players"]
        assert "gcID" not in players[0]

    def test_a_bad_id_is_ignored_not_an_error(self, server):
        tv, code = open_room(server)
        phone = join(server, code, "Teja", "dev-1", gcID="not-hex")
        assert "gcID" not in rooms.get(code).to_json()["players"][0]
        assert latest(phone, "room_joined")["room"]["code"] == code

    def test_a_reconnect_can_add_the_id_later(self, server):
        tv, code = open_room(server)
        join(server, code, "Teja", "dev-1", clientID="launch-1")
        assert "gcID" not in rooms.get(code).to_json()["players"][0]
        # The phone signs in to Game Center after joining; its next join_room
        # (same launch, so the same seat) carries the id.
        join(server, code, "Teja", "dev-1", clientID="launch-1", gcID=GOOD)
        players = rooms.get(code).to_json()["players"]
        assert len(players) == 1 and players[0]["gcID"] == GOOD
