"""Room and player model for the native hub.

The JSON shape assertions are the important ones: the Swift client decodes with
a default JSONDecoder, so a renamed key does not raise anywhere -- it makes the
whole payload decode to nil and the screen silently stops updating.
"""

import time

import pytest

from utils.room_manager import (
    CODE_ALPHABET, RECONNECT_GRACE_SECONDS, Player, Room, RoomRegistry,
    RoomState, generate_room_code,
)


@pytest.fixture
def registry():
    return RoomRegistry()


class TestRoomCode:
    def test_shape(self, registry):
        code = registry.new_code()
        assert len(code) == 6
        assert set(code) <= set(CODE_ALPHABET)

    def test_omits_ambiguous_characters(self):
        # The TV renders this at 96pt across a room; O/0 and I/1 misread.
        for ch in "O0I1":
            assert ch not in CODE_ALPHABET

    def test_avoids_collisions(self):
        taken = {"AAAAAA"}
        seen = {generate_room_code(lambda c: c in taken) for _ in range(50)}
        assert "AAAAAA" not in seen

    def test_raises_when_space_exhausted(self):
        with pytest.raises(RuntimeError):
            generate_room_code(lambda c: True)


class TestJSONShape:
    def test_player_matches_swift_struct(self):
        p = Player(id="dev-1", name="Teja", is_ready=True, score=7, is_host=True)
        assert p.to_json() == {
            "id": "dev-1", "name": "Teja",
            "isReady": True, "score": 7, "isHost": True, "isBot": False,
        }

    def test_room_matches_swift_struct(self, registry):
        room = registry.create("trivia")
        room.add_player("dev-1", "Teja", "sid-1")
        payload = room.to_json()
        assert set(payload) == {"code", "gameID", "players", "state",
                               "contentPack", "botsAllowed", "usesContentPack"}
        assert payload["gameID"] == "trivia"
        assert payload["state"] == "lobby"

    def test_state_values_match_swift_raw_values(self):
        assert [s.value for s in RoomState] == ["lobby", "playing", "results"]


class TestPlayers:
    def test_first_player_is_host(self, registry):
        room = registry.create("trivia")
        first = room.add_player("a", "A", "s1")
        second = room.add_player("b", "B", "s2")
        assert first.is_host and not second.is_host

    def test_host_transfers_when_host_leaves(self, registry):
        room = registry.create("trivia")
        room.add_player("a", "A", "s1")
        room.add_player("b", "B", "s2")
        room.remove_player("a")
        assert room.player("b").is_host

    def test_exactly_one_host_after_reassignment(self, registry):
        room = registry.create("trivia")
        for i in range(4):
            room.add_player(f"p{i}", f"P{i}", f"s{i}")
        room.remove_player("p0")
        assert sum(p.is_host for p in room.players) == 1


class TestTVIsNotAPlayer:
    def test_tv_absent_from_roster(self, registry):
        room = registry.create("trivia")
        room.attach_tv("tv-sid")
        assert room.to_json()["players"] == []
        assert "tv-sid" in room.tv_sids

    def test_tv_does_not_count_toward_minimum(self, registry):
        room = registry.create("mafia")
        room.attach_tv("tv-sid")
        room.add_player("a", "A", "s1")
        assert len(room.connected_players()) == 1


class TestDisconnect:
    def test_lobby_disconnect_drops_the_seat(self, registry):
        room = registry.create("trivia")
        room.add_player("a", "A", "s1")
        assert room.detach_sid("s1") == "a"
        assert room.player("a") is None

    def test_mid_game_disconnect_keeps_the_seat(self, registry):
        room = registry.create("trivia")
        room.add_player("a", "A", "s1")
        room.state = RoomState.PLAYING
        room.detach_sid("s1")
        held = room.player("a")
        assert held is not None and not held.connected and held.sid is None

    def test_tv_disconnect_reported_separately(self, registry):
        room = registry.create("trivia")
        room.attach_tv("tv-sid")
        assert room.detach_sid("tv-sid") == "__tv__"

    def test_solo_room_detaches_both_tv_and_player_from_one_sid(self, registry):
        # A solo room's synthetic player is created with the TV's own sid
        # (games/native_hub/socket_events.py's handle_create_room), so one
        # sid is simultaneously a tv_sid and a player's sid. Detaching it
        # must clean up both halves, not just whichever the old
        # tv_sids-checked-first order happened to see.
        room = registry.create("trivia", solo=True)
        room.attach_tv("tv-and-player-sid")
        room.add_player("host", "Player 1", "tv-and-player-sid")

        assert room.detach_sid("tv-and-player-sid") == "host"

        assert "tv-and-player-sid" not in room.tv_sids
        assert room.player("host") is None
        assert room.is_empty()

    def test_stale_player_evicted_after_grace(self, registry):
        room = registry.create("trivia")
        room.add_player("a", "A", "s1")
        room.state = RoomState.PLAYING
        room.detach_sid("s1")
        assert room.evict_stale_players(time.time()) == []
        later = time.time() + RECONNECT_GRACE_SECONDS + 1
        assert room.evict_stale_players(later) == ["a"]


class TestRegistry:
    def test_lookup_by_sid(self, registry):
        room = registry.create("trivia")
        registry.bind_sid("s1", room.code)
        assert registry.get_by_sid("s1") is room
        registry.unbind_sid("s1")
        assert registry.get_by_sid("s1") is None

    def test_remove_bumps_generation_to_kill_the_pump(self, registry):
        room = registry.create("trivia")
        before = room.generation
        registry.remove(room.code)
        assert room.generation > before
        assert registry.get(room.code) is None

    def test_empty_room_is_reapable_after_grace(self, registry):
        room = registry.create("trivia")
        room.attach_tv("tv")
        room.detach_sid("tv")
        assert room.empty_since is not None
        assert registry.reapable(time.time()) == []
        assert room in registry.reapable(time.time() + 10_000)
