"""Plain-English errors for every way joining or playing can go wrong.

The sockets carry a short ``code``; this turns each one into a headline
(``message``), what to do about it (``hint``) and whether the room is gone
for good (``fatal`` -- the client should leave the game screen instead of
sitting on a dead controller).
"""

from __future__ import annotations

#: code -> (message, hint, fatal)
CATALOG: dict[str, tuple[str, str, bool]] = {
    "INVALID_CODE": (
        "That room code doesn't look right",
        "Room codes are 6 letters and numbers, shown big on the TV.", False),
    "ROOM_NOT_FOUND": (
        "We can't find that room",
        "Check the code on the TV. If the TV was closed or sat idle for a while, "
        "start a new game there and join again.", True),
    "ROOM_CLOSED": (
        "This room has closed",
        "The TV left or the game sat idle for too long. Start a new game on the TV "
        "and join again with its code.", True),
    "ROOM_FULL": (
        "This room is full",
        "Ask the host to make space, or join the next game.", False),
    "GAME_IN_PROGRESS": (
        "This game has already started",
        "Wait for it to finish, then join again with the same code.", False),
    "NOT_HOST": (
        "Only the host can do that",
        "The host is the first phone that joined the room.", False),
    "NOT_ENOUGH_PLAYERS": (
        "Not enough players yet",
        "Ask more people to join with the room code, or add a bot.", False),
    "DEVICE_SEATS_EXHAUSTED": (
        "Too many phones are using this device's seat",
        "Close the extra tabs or apps, then try again.", False),
    "INVALID_PLAYER": (
        "Something went wrong with your seat",
        "Close the app, open it again and rejoin.", False),
    "NOT_IN_ROOM": (
        "You're not in this room any more",
        "Rejoin with the code on the TV.", True),
    "ENGINE_ERROR": (
        "That game couldn't start",
        "Try again, or pick a different game.", False),
    "INVALID_GAME": (
        "That game isn't available",
        "Pick another game from the list.", False),
    "NO_GAMES": (
        "No games fit this group",
        "Try a different group size or turn off kids mode.", False),
    "INVALID_OPTION": (
        "That setting isn't available",
        "Pick one of the choices shown.", False),
    "BOTS_UNSUPPORTED": (
        "Bots can't play this game yet",
        "This one needs real players.", False),
}


def describe(code: str | None, message: str = "") -> dict:
    """``{message, hint, fatal}`` for a code; unknown codes keep their own message."""
    entry = CATALOG.get(code or "")
    if entry is None:
        return {"message": message, "hint": "", "fatal": False}
    headline, hint, fatal = entry
    # Keep a specific message the engine wrote ("Need at least 3 players")
    # when it says more than the generic headline.
    if code == "NOT_ENOUGH_PLAYERS" and message:
        headline = message
    return {"message": headline, "hint": hint, "fatal": fatal}
