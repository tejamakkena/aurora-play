"""Two phones that send the same player id get two seats, not one.

A phone's player id is a UUID in UserDefaults, and UserDefaults rides along
in an iCloud/iTunes backup, so two phones set up from one backup send the
same id. The join path used to read that as a reconnect and hand the second
phone the first one's seat: one seat, one colour, one turn, one score.
Connect 4 made it visible -- every disc came out the same colour -- and it
broke every turn-based game the same way.
"""

import pytest

from app import create_app
from games.native_hub.engines.legacy_boards import Connect4Engine
from games.native_hub.socket_events import MAX_SEATS_PER_DEVICE, _seat_for
from utils.room_manager import RoomRegistry, RoomState, rooms

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


def join(app, socketio, code, name, player_id):
    phone = socketio.test_client(app, namespace=NS)
    phone.emit("join_room", {"roomCode": code, "playerName": name,
                             "playerID": player_id, "isTV": False}, namespace=NS)
    return phone


def seat_id(phone):
    return latest(phone, "room_joined")["playerID"]


class TestSeatAllocation:
    """_seat_for in isolation."""

    def _room(self):
        return RoomRegistry().create("connect4")

    def test_first_phone_keeps_the_plain_id(self):
        room = self._room()
        assert _seat_for(room, "dev-a", "sock-1") == "dev-a"

    def test_second_live_phone_gets_its_own_seat(self):
        room = self._room()
        room.add_player("dev-a", "A", "sock-1")
        assert _seat_for(room, "dev-a", "sock-2") == "dev-a-2"

    def test_same_socket_reclaims_its_own_seat(self):
        room = self._room()
        room.add_player("dev-a", "A", "sock-1")
        assert _seat_for(room, "dev-a", "sock-1") == "dev-a"

    def test_dropped_seat_is_reclaimable(self):
        room = self._room()
        player = room.add_player("dev-a", "A", "sock-1")
        player.connected = False
        assert _seat_for(room, "dev-a", "sock-9") == "dev-a"

    def test_third_phone_gets_a_third_seat(self):
        room = self._room()
        room.add_player("dev-a", "A", "sock-1")
        room.add_player("dev-a-2", "B", "sock-2")
        assert _seat_for(room, "dev-a", "sock-3") == "dev-a-3"

    def test_exhausted_id_is_refused(self):
        room = self._room()
        for index in range(1, MAX_SEATS_PER_DEVICE + 1):
            seat = "dev-a" if index == 1 else f"dev-a-{index}"
            room.add_player(seat, f"P{index}", f"sock-{index}")
        assert _seat_for(room, "dev-a", "sock-99") is None

    def test_a_different_id_is_never_affected(self):
        room = self._room()
        room.add_player("dev-a", "A", "sock-1")
        assert _seat_for(room, "dev-b", "sock-2") == "dev-b"


class TestJoinWithSharedID:
    """The same thing over the socket, the way the apps do it."""

    def open_room(self, tv):
        tv.emit("create_room", {"gameID": "connect4", "hostName": "TV",
                                "hostID": "tv-1"}, namespace=NS)
        return latest(tv, "room_updated")["code"]

    def test_two_phones_one_id_are_two_players(self, server, tv):
        app, socketio = server
        code = self.open_room(tv)
        first = join(app, socketio, code, "Teja", "same-id")
        second = join(app, socketio, code, "Asha", "same-id")

        assert seat_id(first) == "same-id"
        assert seat_id(second) == "same-id-2"
        room = rooms.get(code)
        assert len(room.players) == 2
        assert [p.name for p in room.players] == ["Teja", "Asha"]

    def test_the_second_phone_keeps_its_seat_across_a_reconnect(self, server, tv):
        app, socketio = server
        code = self.open_room(tv)
        join(app, socketio, code, "Teja", "same-id")
        second = join(app, socketio, code, "Asha", "same-id")
        assert seat_id(second) == "same-id-2"

        # A reconnect arrives on a fresh socket after the old one dropped
        # (GameSocketManager re-sends join_room on every reconnect). The
        # seat in front of it is still held by the other phone, so it lands
        # back on its own rather than minting a third.
        second.disconnect(namespace=NS)
        again = join(app, socketio, code, "Asha", "same-id")
        assert seat_id(again) == "same-id-2"
        assert len(rooms.get(code).players) == 2

    def test_a_single_phone_still_reclaims_its_seat(self, server, tv):
        app, socketio = server
        code = self.open_room(tv)
        phone = join(app, socketio, code, "Teja", "solo-id")
        assert seat_id(phone) == "solo-id"
        phone.disconnect(namespace=NS)

        back = join(app, socketio, code, "Teja", "solo-id")
        assert seat_id(back) == "solo-id"
        assert len(rooms.get(code).players) == 1

    def test_each_seat_plays_its_own_colour(self, server, tv):
        app, socketio = server
        code = self.open_room(tv)
        join(app, socketio, code, "Teja", "same-id")
        join(app, socketio, code, "Asha", "same-id")
        tv.emit("start_game", {"roomCode": code}, namespace=NS)
        tv.emit("begin_game", {"roomCode": code}, namespace=NS)

        room = rooms.get(code)
        assert room.state is RoomState.PLAYING
        colors = room.engine.public_state()["colors"]
        assert sorted(colors) == ["same-id", "same-id-2"]
        assert len(set(colors.values())) == 2


class TestConnect4Colours:
    """No seat ever silently inherits player one's colour."""

    class _NullBroadcaster:
        def state(self): pass
        def room_update(self): pass
        def error(self, *args, **kwargs): pass

    def make(self, count):
        self.room = RoomRegistry().create("connect4")
        room = self.room
        roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(count)]
        engine = Connect4Engine(room, self._NullBroadcaster())
        room.engine = engine
        room.state = RoomState.PLAYING
        engine.start(roster)
        return engine

    @pytest.mark.parametrize("count", [2, 3, 4])
    def test_every_seat_has_a_distinct_colour(self, count):
        engine = self.make(count)
        colors = [engine.colors[pid] for pid in engine.order]
        assert len(set(colors)) == count
        assert colors[0] == "red"

    def test_a_seat_with_no_colour_does_not_drop_red(self):
        engine = self.make(2)
        # A seat that joined the rotation after setup, so the colour map
        # has never seen it. The old code answered red for anything it did
        # not know, which put its discs in with player one's.
        self.room.add_player("late", "Late", "s-late")
        engine.order.append("late")
        engine.turn_index = engine.order.index("late")
        engine.handle_action("late", "drop", {"column": 0})
        assert engine.colors["late"] == "green"
        assert engine.grid[-1][0] == "green"

    def test_dropped_discs_alternate_colour(self):
        engine = self.make(2)
        for col in range(4):
            pid = engine.current_player_id()
            engine.handle_action(pid, "drop", {"column": col})
        assert engine.grid[-1][:4] == ["red", "yellow", "red", "yellow"]

    def test_private_state_never_invents_a_colour(self):
        engine = self.make(2)
        assert engine.private_state("p0")["color"] == "red"
        assert engine.private_state("p1")["color"] == "yellow"
        # A phone that has left is not handed player one's colour.
        assert engine.private_state("gone")["color"] == ""
        assert "gone" not in engine.colors
