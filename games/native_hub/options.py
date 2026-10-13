"""Per-game lobby options the TV (or the host's phone) picks before a game.

Each option is a small fixed menu, stored on the room as ``room.options``
(``{key: value}``, values are strings). The room JSON carries the whole menu
with the current pick, so a client can draw "Hands: 20" buttons for any game
without knowing the game. Engines read their pick with :func:`get`.
"""

from __future__ import annotations

#: game id -> options, in the order the lobby shows them.
MENUS: dict[str, list[dict]] = {
    "poker": [
        {"key": "hands", "label": "Hands", "default": "20",
         "choices": [["10", "10 hands"], ["20", "20 hands"], ["40", "40 hands"],
                     ["0", "Unlimited"]]},
        {"key": "stack", "label": "Chips", "default": "1000",
         "choices": [["1000", "1,000 chips"], ["2000", "2,000 chips"],
                     ["5000", "5,000 chips"]]},
        {"key": "rebuys", "label": "Re-buys", "default": "off",
         "choices": [["off", "Off"], ["on", "On"]]},
    ],
}


def menu(game_id: str) -> list[dict]:
    return MENUS.get(game_id, [])


def has_options(game_id: str) -> bool:
    return game_id in MENUS


def default(game_id: str, key: str) -> str | None:
    for opt in menu(game_id):
        if opt["key"] == key:
            return opt["default"]
    return None


def valid(game_id: str, key, value) -> bool:
    for opt in menu(game_id):
        if opt["key"] == key:
            return any(value == c[0] for c in opt["choices"])
    return False


def get(room, key: str) -> str:
    """The room's pick for ``key``, or the menu default."""
    picked = (getattr(room, "options", None) or {}).get(key)
    if picked is not None and valid(room.game_id, key, picked):
        return picked
    return default(room.game_id, key) or ""


def to_json(room) -> list[dict]:
    return [
        {"key": opt["key"], "label": opt["label"],
         "value": get(room, opt["key"]),
         "choices": [{"value": c[0], "label": c[1]} for c in opt["choices"]]}
        for opt in menu(room.game_id)
    ]
