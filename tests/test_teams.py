"""Teams mode (games/teams.py): splitting, moving, syncing and scoring."""

import pytest

from app import create_app
from games import teams
from games.native_hub.broadcast import finish_game
from utils.room_manager import RoomRegistry, RoomState, rooms

NS = "/native"


def make_room(ids=("a", "b", "c", "d", "e")):
    room = RoomRegistry().create("trivia")
    for pid in ids:
        room.add_player(pid, pid.upper(), f"s-{pid}")
    return room


def results(*order):
    return [{"playerID": pid, "name": pid.upper(), "score": 10 - i, "rank": i + 1}
            for i, pid in enumerate(order)]


def members(room):
    return [t["members"] for t in room.teams["teams"]]


def test_auto_split_is_balanced_and_covers_everyone():
    room = make_room()
    teams.set_teams(room, 2)
    sizes = sorted(len(m) for m in members(room))
    assert sizes == [2, 3]
    assert sorted(p for m in members(room) for p in m) == ["a", "b", "c", "d", "e"]


def test_count_is_clamped():
    room = make_room()
    teams.set_teams(room, 9)
    assert len(room.teams["teams"]) == 4
    teams.set_teams(room, 1)
    assert len(room.teams["teams"]) == 2


def test_explicit_lists_and_unknown_ids():
    room = make_room()
    teams.set_teams(room, lists=[["a", "zzz"], ["b", "a"]], names=["  Us  ", ""])
    t1, t2 = room.teams["teams"]
    assert t1["name"] == "Us" and t2["name"] == "Blue Comets"
    assert "a" in t1["members"] and "a" not in t2["members"]
    assert "zzz" not in t1["members"]
    placed = sorted(t1["members"] + t2["members"])
    assert placed == ["a", "b", "c", "d", "e"]


def test_newcomers_and_leavers_are_synced():
    room = make_room(("a", "b"))
    teams.set_teams(room, 2)
    room.add_player("c", "C", "s-c")
    assert sorted(p for m in members(room) for p in m) == ["a", "b", "c"]
    room.remove_player("a")
    assert "a" not in [p for m in members(room) for p in m]


def test_move():
    room = make_room(("a", "b"))
    teams.set_teams(room, 2, lists=[["a"], ["b"]])
    assert teams.move(room, "a", "t2")
    assert members(room) == [[], ["b", "a"]]
    assert not teams.move(room, "a", "t9")
    assert not teams.move(room, "ghost", "t1")


def test_best_member_decides_team_placing():
    room = make_room(("a", "b", "c", "d"))
    teams.set_teams(room, 2, lists=[["a", "b", "c"], ["d"]])
    teams.record_game(room, results("d", "a", "b", "c"))
    assert room.teams["points"] == {"t1": 7, "t2": 10}
    teams.record_game(room, results("b", "d", "a", "c"))
    assert room.teams["points"] == {"t1": 17, "t2": 17}
    rows = room.to_json()["teams"]["teams"]
    assert {r["id"]: r["lastGained"] for r in rows} == {"t1": 10, "t2": 7}


def test_shared_best_rank_shares_the_placing():
    room = make_room(("a", "b"))
    teams.set_teams(room, 2, lists=[["a"], ["b"]])
    tied = [{"playerID": "a", "rank": 1}, {"playerID": "b", "rank": 1}]
    teams.record_game(room, tied)
    assert room.teams["points"] == {"t1": 10, "t2": 10}


def test_room_json_without_teams():
    assert make_room().to_json()["teams"] is None


def test_finish_game_awards_team_points():
    class FakeEngine:
        def results(self):
            return results("b", "a")

        def stop(self):
            pass

    class FakeIO:
        def emit(self, *a, **k):
            pass

    room = make_room(("a", "b"))
    teams.set_teams(room, 2, lists=[["a"], ["b"]])
    room.state = RoomState.PLAYING
    room.engine = FakeEngine()
    finish_game(FakeIO(), room)
    assert room.teams["points"] == {"t1": 7, "t2": 10}


# --------------------------------------------------------------------------
# sockets
# --------------------------------------------------------------------------

@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


def test_teams_over_sockets(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
            namespace=NS)
    code = latest(tv, "room_updated")["code"]
    phones = []
    for i in range(4):
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code, "playerName": f"P{i}",
                                 "playerID": f"dev-{i}", "isTV": False}, namespace=NS)
        phones.append(phone)
    tv.get_received(NS)

    tv.emit("set_teams", {"roomCode": code, "count": 2}, namespace=NS)
    data = latest(tv, "room_updated")["teams"]["teams"]
    assert [len(t["members"]) for t in data] == [2, 2]

    # A guest may move themselves but not someone else.
    guest = phones[1]
    guest.get_received(NS)
    other = next(t for t in data if "dev-1" not in t["members"])
    guest.emit("move_to_team", {"roomCode": code, "playerID": "dev-1",
                                "teamID": other["id"]}, namespace=NS)
    moved = latest(tv, "room_updated")["teams"]["teams"]
    assert "dev-1" in next(t for t in moved if t["id"] == other["id"])["members"]
    guest.emit("move_to_team", {"roomCode": code, "playerID": "dev-2",
                                "teamID": "t1"}, namespace=NS)
    assert latest(guest, "error")["code"] == "NOT_HOST"

    guest.emit("set_teams", {"roomCode": code}, namespace=NS)
    assert latest(guest, "error")["code"] == "NOT_HOST"

    tv.emit("clear_teams", {"roomCode": code}, namespace=NS)
    assert latest(tv, "room_updated")["teams"] is None
