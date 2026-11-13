"""A server restart no longer ends the party: the TV brings its room back
under the same code, in the lobby, with the Game Night scores intact."""

import json

import pytest

from app import create_app
from games import game_night, room_resume
from utils.room_manager import RoomRegistry, RoomState, rooms

NS = "/native"


def results(*ids):
    return [{"playerID": pid, "name": pid.upper(), "score": 10 - i, "rank": i + 1}
            for i, pid in enumerate(ids)]


def night_room():
    room = RoomRegistry().create("herd")
    for pid in ("a", "b", "c"):
        room.add_player(pid, pid.upper(), f"s-{pid}")
    game_night.start(room, ["herd", "trivia", "ludo"], points="fair",
                     settings={"trivia": {"rounds": "4"}},
                     party={"occasion": "birthday", "honoree": "Venkat", "honoreeSaid": "Ven-kut"})
    game_night.begin_party(room)
    game_night.record_game(room, results("a", "b", "c"))
    game_night.advance(room)
    return room


class TestBlob:
    def test_it_is_small_json_carrying_the_night(self):
        room = night_room()
        raw = room.to_json()["resume"]
        assert isinstance(raw, str) and len(raw) < 2000
        data = json.loads(raw)
        assert data["game"] == "trivia" and data["night"]["index"] == 1
        assert data["night"]["totals"] == {"a": 10, "b": 6, "c": 1}

    def test_a_round_trip_rebuilds_the_night(self):
        old = night_room()
        new = RoomRegistry().create_with_code("ZZZZZZ", "herd")
        room_resume.restore(new, room_resume.parse(old.to_json()["resume"]))
        assert new.game_id == "trivia" and new.options == {"rounds": "4"}
        night = game_night.to_json(new)
        assert night["playlist"] == ["herd", "trivia", "ludo"] and night["index"] == 1
        assert [s["points"] for s in night["standings"]] == [10, 6, 1]
        assert night["points"] == "fair" and night["gamesPlayed"] == 1
        party = night["party"]
        assert party["welcomed"] is True and party["title"] == "Venkat's Birthday Party"
        assert party["sayAs"] == {"Venkat": "Ven-kut"}

    @pytest.mark.parametrize("raw", [None, 7, "", "not json", "[]", json.dumps({"v": 2}),
                                     "x" * (room_resume.MAX_BLOB + 1)])
    def test_junk_is_refused(self, raw):
        assert room_resume.parse(raw) is None

    def test_hostile_values_are_cleaned(self):
        room = RoomRegistry().create_with_code("QQQQQQ", "herd")
        room_resume.restore(room, {"v": 1, "game": "herd", "pack": "xx", "options": {"rounds": "999"},
                                   "night": {"playlist": ["nope", "herd", "trivia"], "index": 99,
                                             "totals": {"a": 5, "b": -3, "c": "9", 4: 1},
                                             "names": {"a": "A\\x00" * 50, "zzz": "Ghost"},
                                             "points": "chaos", "party": "nope"}})
        assert room.options == {}
        assert room.night["playlist"] == ["herd", "trivia"] and room.night["index"] == 1
        assert room.night["totals"] == {"a": 5} and list(room.night["names"]) == ["a"]
        assert room.night["points"] == "classic" and "party" not in room.night

    def test_a_taken_code_is_not_overwritten(self):
        reg = RoomRegistry()
        assert reg.create_with_code("AAAAAA", "herd") is not None
        assert reg.create_with_code("AAAAAA", "trivia") is None


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def events(client, name):
    return [e["args"][0] for e in client.get_received(NS) if e["name"] == name]


class TestOverSockets:
    def test_the_tv_brings_the_room_back_and_phones_rejoin(self, server):
        app, socketio = server
        tv = socketio.test_client(app, namespace=NS)
        tv.emit("create_room", {"gameID": "herd", "hostName": "TV", "hostID": "tv-1"}, namespace=NS)
        code = events(tv, "room_updated")[-1]["code"]
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code, "playerName": "Asha", "playerID": "dev-a",
                                 "isTV": False}, namespace=NS)
        tv.emit("start_night", {"roomCode": code, "playlist": ["herd", "trivia"]}, namespace=NS)
        room = rooms.get(code)
        game_night.record_game(room, results("dev-a"))
        game_night.advance(room)
        saved = room.to_json()["resume"]

        rooms.clear()                                         # the server restarted
        tv2 = socketio.test_client(app, namespace=NS)
        tv2.emit("restore_room", {"roomCode": code, "resume": saved}, namespace=NS)
        got = events(tv2, "room_joined")[-1]
        assert got["restored"] is True and got["room"]["code"] == code
        back = rooms.get(code)
        assert back.state is RoomState.LOBBY and back.game_id == "trivia"
        assert game_night.standings(back)[0]["points"] == 10

        phone2 = socketio.test_client(app, namespace=NS)
        phone2.emit("join_room", {"roomCode": code, "playerName": "Asha", "playerID": "dev-a",
                                  "isTV": False}, namespace=NS)
        assert events(phone2, "room_joined")
        standings = game_night.standings(rooms.get(code))
        assert standings[0]["playerID"] == "dev-a"

    def test_an_existing_room_is_just_rejoined(self, server):
        app, socketio = server
        tv = socketio.test_client(app, namespace=NS)
        tv.emit("create_room", {"gameID": "herd", "hostName": "TV", "hostID": "tv-1"}, namespace=NS)
        code = events(tv, "room_updated")[-1]["code"]
        tv2 = socketio.test_client(app, namespace=NS)
        tv2.emit("restore_room", {"roomCode": code, "resume": "garbage"}, namespace=NS)
        assert events(tv2, "room_joined")[-1]["restored"] is False

    def test_without_a_blob_the_room_is_not_found(self, server):
        app, socketio = server
        tv = socketio.test_client(app, namespace=NS)
        tv.emit("restore_room", {"roomCode": "ABCDEF", "resume": "nope"}, namespace=NS)
        assert events(tv, "error")[-1]["code"] == "ROOM_NOT_FOUND"
        assert rooms.get("ABCDEF") is None
