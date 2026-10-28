"""Game Night through the real /native Socket.IO namespace.

The engine's own rules are covered in test_game_night.py; this checks the parts
that only exist at the socket layer: guests joining after the show has started,
who may drive it, the TV-only ``night_state`` channel, and the long room life.
"""

import time

import pytest

from app import create_app
from utils.room_manager import (
    NIGHT_ROOM_TTL_SECONDS, ROOM_TTL_SECONDS, RoomState, rooms,
)

NS = "/native"


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")      # returns (app, socketio)


def events(client, name):
    return [e["args"][0] for e in client.get_received(NS) if e["name"] == name]


def join(app, socketio, code, pid, name):
    phone = socketio.test_client(app, namespace=NS)
    phone.emit("join_room", {"roomCode": code, "playerName": name,
                             "playerID": pid, "isTV": False}, namespace=NS)
    return phone


def act(client, code, pid, action, data=None):
    client.emit("game_action", {"roomCode": code, "playerID": pid,
                                "action": action, "data": data or {}}, namespace=NS)


@pytest.fixture
def night(server):
    """A TV, an iPad (host) and one guest, with the night already started."""
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "game_night", "hostName": "TV",
                            "hostID": "tv-1"}, namespace=NS)
    code = events(tv, "room_updated")[-1]["code"]
    ipad = join(app, socketio, code, "ipad-1", "iPad")
    # The TV auto-starts the night as soon as the first phone is in.
    tv.emit("start_game", {"roomCode": code}, namespace=NS)
    tv.get_received(NS)
    ipad.get_received(NS)
    room = rooms.get(code)
    return {"app": app, "socketio": socketio, "tv": tv, "ipad": ipad,
            "code": code, "room": room}


class TestStarting:
    def test_the_night_starts_with_a_single_phone(self, night):
        room = night["room"]
        assert room.state is RoomState.PLAYING
        assert room.engine.phase == "setup"

    def test_the_first_phone_in_is_the_host(self, night):
        assert night["room"].host().id == "ipad-1"

    def test_the_room_outlives_a_normal_game(self, night):
        assert night["room"].ttl_seconds == NIGHT_ROOM_TTL_SECONDS > ROOM_TTL_SECONDS
        assert rooms.reapable(time.time() + ROOM_TTL_SECONDS + 60) == []

    def test_ordinary_rooms_keep_the_one_hour_ceiling(self, server):
        room = rooms.create("herd")
        assert room.ttl_seconds == ROOM_TTL_SECONDS


class TestGuestsArriveAllEvening:
    def test_a_guest_can_join_after_the_show_has_started(self, night):
        app, socketio, code = night["app"], night["socketio"], night["code"]
        act(night["ipad"], code, "ipad-1", "night_start",
            {"config": {"games": ["herd"]}})
        assert night["room"].engine.phase == "welcome"

        guest = join(app, socketio, code, "guest-1", "Asha")
        received = guest.get_received(NS)
        names = [e["name"] for e in received]
        assert "error" not in names
        assert "room_joined" in names
        # Put straight onto the night screen, not left waiting on the lobby.
        private = [e["args"][0] for e in received if e["name"] == "private_state"]
        assert private and private[-1]["privateData"]["night"]["phase"] == "welcome"
        assert private[-1]["privateData"]["night"]["isHost"] is False
        assert night["room"].player("guest-1") is not None

    def test_ordinary_games_still_lock_the_door(self, server):
        app, socketio = server
        tv = socketio.test_client(app, namespace=NS)
        tv.emit("create_room", {"gameID": "herd", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        code = events(tv, "room_updated")[-1]["code"]
        phones = [join(app, socketio, code, f"d{i}", f"P{i}") for i in range(3)]
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        late = join(app, socketio, code, "late", "Late")
        errors = events(late, "error")
        assert errors and errors[-1]["code"] == "GAME_IN_PROGRESS"
        assert phones


class TestWhoMayDrive:
    def test_the_host_phone_configures_and_it_reaches_the_room(self, night):
        act(night["ipad"], night["code"], "ipad-1", "night_configure",
            {"config": {"occasion": "birthday", "honoree": "Venkat"}})
        assert night["room"].night_config["honoree"] == "Venkat"
        assert night["room"].engine.night_state()["title"] == "Venkat's Birthday Party"

    def test_a_guest_phone_cannot_start_the_night(self, night):
        guest = join(night["app"], night["socketio"], night["code"], "guest-1", "Asha")
        guest.get_received(NS)
        act(guest, night["code"], "guest-1", "night_start")
        assert night["room"].engine.phase == "setup"

    def test_a_phone_cannot_act_as_another_player(self, night):
        guest = join(night["app"], night["socketio"], night["code"], "guest-1", "Asha")
        guest.get_received(NS)
        # Claims to be the host. The hub rejects a sid that does not match.
        act(guest, night["code"], "ipad-1", "night_start")
        assert night["room"].engine.phase == "setup"

    def test_a_phone_cannot_pose_as_the_tv(self, night):
        guest = join(night["app"], night["socketio"], night["code"], "guest-1", "Asha")
        guest.get_received(NS)
        # An id that is not a player is only honoured from a TV socket.
        act(guest, night["code"], "not-a-player", "night_start")
        assert night["room"].engine.phase == "setup"

    def test_the_tv_can_start_the_night_with_the_remote(self, night):
        act(night["tv"], night["code"], "tv-1", "night_start")
        assert night["room"].engine.phase == "welcome"

    def test_the_tv_reports_that_it_has_finished_speaking(self, night):
        code, tv = night["code"], night["tv"]
        act(night["ipad"], code, "ipad-1", "night_start", {"config": {"games": ["herd"]}})
        engine = night["room"].engine
        engine.hold_until = 0
        act(tv, code, "tv-1", "night_announce_done", {"id": engine.announce["id"]})
        assert engine.phase == "lineup"


class TestChannels:
    def test_the_tv_gets_night_state_and_phones_do_not(self, night):
        from games.native_hub.broadcast import broadcast_state
        broadcast_state(night["socketio"], night["room"])
        tv_events = events(night["tv"], "night_state")
        assert tv_events and tv_events[-1]["night"]["phase"] == "setup"
        assert tv_events[-1]["night"]["roomCode"] == night["code"]
        assert events(night["ipad"], "night_state") == []

    def test_the_host_phone_gets_the_setup_options_privately(self, night):
        from games.native_hub.broadcast import broadcast_state
        broadcast_state(night["socketio"], night["room"])
        private = events(night["ipad"], "private_state")
        assert private
        data = private[-1]["privateData"]["night"]
        assert data["isHost"] is True and data["catalog"]
        # ...and the TV is never sent them.
        tv_night = events(night["tv"], "night_state")[-1]["night"]
        assert "catalog" not in tv_night and "config" not in tv_night
