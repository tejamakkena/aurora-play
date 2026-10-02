"""Pure validation helpers for the native Socket.IO hub.

No Flask imports here on purpose: every function is a plain transform so the
whole module is trivially unit-testable without an app context.

The ``GAME_IDS`` allowlist is load-bearing. ``Room.gameID`` on the Swift side is
a non-optional ``GameID`` enum, so a single unrecognised string makes the entire
``room_updated`` payload fail to decode -- and ``GameSocketManager.on`` swallows
decode failures with ``try?``. An unknown game id must therefore be rejected at
the door, not passed through.
"""

import json
import re
from typing import Any

# Every raw value declared by GameID in ios/Shared/Models/Game.swift.
# Keep this in sync with that enum -- it is the contract between the two.
GAME_IDS = frozenset({
    # Originals
    "trivia", "poker", "tambola", "mafia", "heist", "stock_panic",
    "mind_meld", "hot_grid", "speed_sculptor", "pong", "connect4",
    "chess", "snake_ladder", "roulette", "raja_mantri", "memory",
    "digit_guess",
    # Party (8-20+)
    "bluff_it", "last_tap", "herd", "emoji_movie", "npat", "antakshari",
    "most_likely_to",
    # Mid group (4-12)
    "cipher_grid", "odd_one_out", "sealed_auction", "wavelength",
    "kbc", "bollywood_charades",
    # Duel / co-op (2-6)
    "defuse", "battleship", "air_hockey", "heist_escape",
    "ludo", "carrom", "teen_patti",
    # Solo / Siri Remote
    "neon_snake", "twenty48", "brick_breaker", "simon_says", "atlas",
    # Co-op
    "blast_runners",
    # Travel Mode (voice-first, one phone, car speakers)
    "story_chain", "twenty_questions", "hot_takes",
})

ROOM_CODE_RE = re.compile(r"^[A-Z0-9]{6}$")
ACTION_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")

MAX_PLAYER_ID_LEN = 64
MAX_ACTION_DATA_BYTES = 32 * 1024


def as_dict(value: Any) -> dict:
    """Coerce a Socket.IO payload to a dict. Clients can send anything."""
    return value if isinstance(value, dict) else {}


def room_code(value: Any) -> str | None:
    """Normalise and validate a 6-char room code, or None if malformed."""
    if not isinstance(value, str):
        return None
    code = value.strip().upper()
    return code if ROOM_CODE_RE.match(code) else None


def player_id(value: Any) -> str | None:
    """Validate a client-supplied device UUID."""
    if not isinstance(value, str):
        return None
    pid = value.strip()
    if not pid or len(pid) > MAX_PLAYER_ID_LEN:
        return None
    return pid


def game_id(value: Any) -> str | None:
    """Validate a GameID raw value against the allowlist."""
    if not isinstance(value, str):
        return None
    gid = value.strip()
    return gid if gid in GAME_IDS else None


def action(value: Any) -> str | None:
    """Validate a game action verb (lowercase snake_case, <= 32 chars)."""
    if not isinstance(value, str):
        return None
    verb = value.strip()
    return verb if ACTION_RE.match(verb) else None


def action_data(value: Any) -> dict:
    """Return the action payload, or {} if it is malformed or oversized."""
    if not isinstance(value, dict):
        return {}
    try:
        if len(json.dumps(value)) > MAX_ACTION_DATA_BYTES:
            return {}
    except (TypeError, ValueError):
        return {}
    return value
