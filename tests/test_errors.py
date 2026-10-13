"""Every error a player can hit has a plain-English message and a next step."""

import re
from pathlib import Path

from games.native_hub import errors


def test_every_code_the_server_sends_has_a_friendly_message():
    source = Path("games/native_hub/socket_events.py").read_text()
    sent = set(re.findall(r'"([A-Z][A-Z_]{4,})"', source))
    missing = sorted(c for c in sent if c not in errors.CATALOG)
    assert sent and not missing, f"no friendly text for {missing}"


def test_a_message_always_says_what_to_do():
    for code, (message, hint, _fatal) in errors.CATALOG.items():
        assert message and hint, code
        assert message[0].isupper() and not message.endswith("."), code
        assert hint.endswith("."), code


def test_a_gone_room_is_fatal_and_a_full_room_is_not():
    assert errors.describe("ROOM_NOT_FOUND")["fatal"] is True
    assert errors.describe("ROOM_CLOSED")["fatal"] is True
    assert errors.describe("NOT_IN_ROOM")["fatal"] is True
    assert errors.describe("ROOM_FULL")["fatal"] is False


def test_unknown_codes_keep_their_own_message_and_the_player_count_survives():
    assert errors.describe("SOMETHING_NEW", "Odd thing")["message"] == "Odd thing"
    assert errors.describe("NOT_ENOUGH_PLAYERS", "Need at least 3 players")["message"] == "Need at least 3 players"


def test_closing_a_room_tells_everyone_in_it():
    from games.native_hub.broadcast import push_error, push_room_closed
    from utils.room_manager import RoomRegistry

    sent = []

    class Fake:
        def emit(self, event, payload, **kwargs):
            sent.append((event, payload, kwargs))

    room = RoomRegistry().create("herd")
    push_room_closed(Fake(), room, "expired")
    event, payload, kwargs = sent[-1]
    assert event == "room_closed" and kwargs["to"] == room.code
    assert payload["roomCode"] == room.code and payload["reason"] == "expired"
    assert payload["fatal"] is True and payload["hint"]
    push_error(Fake(), "sid-1", "Room not found", "ROOM_NOT_FOUND")
    assert sent[-1][1]["message"] == "We can't find that room" and sent[-1][1]["fatal"] is True
