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


def _song_decks() -> list[dict]:
    """Guess the Song's themes, from the word file: adding a deck there adds it here."""
    from games.native_hub.engines._song_words import DECKS, MIX
    choices = [[MIX, "Mixed"]] + [[deck_id, deck["title"]] for deck_id, deck in DECKS.items()]
    return [{"key": "deck", "label": "Songs", "default": MIX, "choices": choices}]


MENUS["guess_the_song"] = _song_decks()

#: Snake: a crash takes you out, or you come back after a short wait. With a
#: time limit and "come back", everyone plays the whole time and the best score wins.
MENUS["neon_snake"] = [
    {"key": "crash", "label": "After a crash", "default": "out",
     "choices": [["out", "Out for the round"], ["respawn", "Back after 3 seconds"]]},
]

#: Time limits for real-time score games, in minutes ("0" = play to the end).
TIME_STEPS = (2, 3, 5, 10)
#: With "come back after a crash" and no time limit, the game still needs an end.
RESPAWN_DEFAULT_MINUTES = 5


#: Fraction steps around a game's own round count: about half, as it is,
#: half again as many, twice as many.
ROUND_STEPS = (0.5, 1.0, 1.5, 2.0)


def rounds_base(game_id: str) -> int | None:
    """A game's own round count, or None when its length is not set in rounds
    (a board game, a solo game, or one whose rounds follow the player count so
    everybody gets a turn)."""
    from games.native_hub.registry import ENGINES
    cls = ENGINES.get(game_id)
    if cls is None or not getattr(cls, "rounds_adjustable", False):
        return None
    base = getattr(cls, "ROUNDS_BASE", None) or getattr(cls, "total_rounds", None)
    return base if isinstance(base, int) and not isinstance(base, bool) and base > 0 else None


def rounds_menu(game_id: str) -> list[dict]:
    """The "Rounds" pick for a game whose length is counted in rounds."""
    base = rounds_base(game_id)
    if base is None:
        return []
    counts = sorted({max(1, round(base * step)) for step in ROUND_STEPS})
    return [{"key": "rounds", "label": "Rounds", "default": str(base),
             "choices": [[str(n), f"{n} rounds"] for n in counts]}]


def time_menu(game_id: str) -> list[dict]:
    """The "Time limit" pick for a game that can be cut off at a time: when it
    runs out the best score so far wins."""
    from games.native_hub.registry import ENGINES
    cls = ENGINES.get(game_id)
    if cls is None or not getattr(cls, "timed_adjustable", False):
        return []
    return [{"key": "minutes", "label": "Time limit", "default": "0",
             "choices": [["0", "No limit"]] + [[str(m), f"{m} minutes"] for m in TIME_STEPS]}]


def menu(game_id: str) -> list[dict]:
    return MENUS.get(game_id, []) + rounds_menu(game_id) + time_menu(game_id)


def time_limit_seconds(room) -> int:
    """The time limit the host picked for this game, in seconds (0 = none)."""
    picked = (getattr(room, "options", None) or {}).get("minutes")
    if picked is not None and valid(room.game_id, "minutes", picked):
        return int(picked) * 60
    return 0


def explicit_rounds(room) -> int | None:
    """The round count the host picked for this game, or None when nobody did
    (the game then keeps its own length)."""
    picked = (getattr(room, "options", None) or {}).get("rounds")
    if picked is not None and valid(room.game_id, "rounds", picked):
        return int(picked)
    return None


def has_options(game_id: str) -> bool:
    return bool(menu(game_id))


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
