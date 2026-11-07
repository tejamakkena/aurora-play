"""The TV remembers what its family has seen, so a server whose disk was wiped
(free hosting sleeps and redeploys) does not repeat questions."""

import pytest

from app import create_app
from games import content_service as cs
from games.native_hub.engines import content_packs as C
from utils.room_manager import RoomRegistry, rooms

NS = "/native"


def make_room(game="trivia"):
    room = RoomRegistry().create(game)
    room.add_player("p1", "P1", "s1")
    return room


class TestSeenSet:
    def test_hashes_are_short_stable_hex(self):
        h = cs.key_hash("what gas do plants absorb")
        assert len(h) == 10 and h == cs.key_hash("what gas do plants absorb")
        assert int(h, 16) >= 0

    def test_a_remembered_hash_counts_as_seen(self):
        room = make_room()
        key = cs.norm_key("Which tree produces acorns?")
        cs.restore_seen(room, {"mc": [cs.key_hash(key)]})
        _, seen = cs.seen_keys(room, "mc")
        assert key in seen and "something else entirely" not in seen
        assert key in (seen | {"x"})                       # unions keep the memory
        assert key not in cs.seen_keys(room, "wyr")[1]      # per kind

    def test_junk_from_a_client_is_dropped(self):
        room = make_room()
        for junk in (None, "x", [], {"mc": "no"}, {"mc": [1, None, "short", "G" * 10]},
                     {7: ["abcdef0123"]}, {"k" * 99: ["abcdef0123"]}):
            assert cs.restore_seen(room, junk) == 0

    def test_huge_lists_are_capped(self):
        room = make_room()
        hashes = [cs.key_hash(str(i)) for i in range(5000)]
        assert cs.restore_seen(room, {"mc": hashes}) <= cs.TV_SYNC_CAP * 2


class TestQuestionsSkipWhatTheTVHasSeen:
    def test_trivia_does_not_offer_questions_the_tv_remembered(self):
        room = make_room()
        bank = list(C.questions_for("en", "trivia"))
        remembered = bank[:150]
        cs.restore_seen(room, {"mc": [cs.key_hash(cs.norm_key(C._question_text("trivia", q)))
                                      for q in remembered]})
        offered = C.fresh_questions(room, "en", "trivia")
        texts = {C._question_text("trivia", q) for q in offered}
        assert not texts & {C._question_text("trivia", q) for q in remembered}
        assert len(texts) >= 50

    def test_pick_avoids_them_too(self):
        room = make_room()
        items = cs.all_items("herd")
        spec = cs.KINDS["herd"]
        cs.restore_seen(room, {"herd": [cs.key_hash(spec.key(i)) for i in items[:-3]]})
        got = cs.pick(room, "herd", 3)
        assert {spec.key(g) for g in got} <= {spec.key(i) for i in items[-3:]}

    def test_when_everything_was_seen_the_game_still_plays(self):
        room = make_room()
        spec = cs.KINDS["herd"]
        cs.restore_seen(room, {"herd": [cs.key_hash(spec.key(i)) for i in cs.all_items("herd")]})
        assert len(cs.pick(room, "herd", 3)) == 3


class TestSnapshot:
    def test_what_a_room_used_is_handed_back_as_hashes(self):
        room = make_room()
        cs.record(room, "mc", ["alpha", "beta"])
        snap = cs.snapshot_for_tv(room)
        assert snap == {"mc": [cs.key_hash("alpha"), cs.key_hash("beta")]}

    def test_the_snapshot_is_capped_most_recent_last(self):
        room = make_room()
        cs.record(room, "mc", [f"k{i}" for i in range(700)])
        snap = cs.snapshot_for_tv(room)["mc"]
        assert len(snap) == min(cs.TV_SYNC_CAP, cs.ROOM_HISTORY_CAP) and snap[-1] == cs.key_hash("k699")


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


class TestOverSockets:
    def test_only_the_tv_can_restore_and_it_gets_the_new_ones_back(self, server):
        from games.native_hub import broadcast
        app, socketio = server
        tv = socketio.test_client(app, namespace=NS)
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"}, namespace=NS)
        code = latest(tv, "room_updated")["code"]
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code, "playerName": "P", "playerID": "dev-p",
                                 "isTV": False}, namespace=NS)
        h = cs.key_hash("which tree produces acorns")
        phone.emit("restore_seen", {"roomCode": code, "seen": {"mc": [h]}}, namespace=NS)
        assert not getattr(rooms.get(code), "tv_seen", None)           # a phone cannot
        tv.emit("restore_seen", {"roomCode": code, "seen": {"mc": [h]}}, namespace=NS)
        assert h in rooms.get(code).tv_seen["mc"]

        room = rooms.get(code)
        cs.record(room, "mc", ["one", "two"])
        tv.get_received(NS)
        broadcast.send_seen_state(socketio, room)
        got = latest(tv, "seen_state")
        assert got["roomCode"] == code and got["seen"]["mc"][-1] == cs.key_hash("two")
