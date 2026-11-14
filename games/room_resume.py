"""Bringing a room back after the server restarts.

A free host sleeps when idle and restarts on every deploy, and a restart loses
every room held in memory: mid-party, the TV and every phone used to see "This
room has closed". Now each room update carries a small ``resume`` blob (the
game, its options and the Game Night: playlist, where we are, the scoreboard,
the party). The TV keeps the latest one. When its connection comes back and
the room is gone, it sends ``restore_room`` with the blob; the server makes the
room again under the SAME code, in the lobby of the game that was on, with the
night's scores intact. Phones that were seated keep retrying their rejoin for a
while, so they land back in it on their own.

The game that was being played when the server stopped cannot be resumed
mid-round (its engine state is gone); the room comes back to that game's lobby.

The blob comes back from a client, so everything in it is validated again as if
it were new input.
"""

from __future__ import annotations

import json
import time

#: The most bytes a resume blob may be (a full night with 50 players is ~6 KB).
MAX_BLOB = 24_000
MAX_PLAYERS = 60


def blob(room) -> str:
    """The compact JSON a TV keeps to rebuild ``room``."""
    data = {
        "v": 1,
        "game": room.game_id,
        "pack": getattr(room, "content_pack", "en") or "en",
        "topic": getattr(room, "topic", "") or "",
        "options": dict(getattr(room, "options", None) or {}),
        "night": _night_part(getattr(room, "night", None)),
    }
    return json.dumps(data, separators=(",", ":"), ensure_ascii=False)


def _night_part(night) -> dict | None:
    if not isinstance(night, dict):
        return None
    party = night.get("party")
    return {
        "playlist": list(night.get("playlist", [])),
        "index": int(night.get("index", 0)),
        "totals": dict(night.get("totals", {})),
        "names": dict(night.get("names", {})),
        "played": len(night.get("history", [])),
        "finished": bool(night.get("finished")),
        "kids": bool(night.get("kids")),
        "settings": dict(night.get("settings") or {}),
        "points": night.get("points"),
        "party": None if not party else {
            k: party.get(k) for k in ("occasion", "honoree", "honoreeSaid", "style", "humor",
                                      "nhiePack", "nhieRounds", "accent", "welcomed")
        },
    }


def parse(raw) -> dict | None:
    """The blob as a dict, or None when it is missing, too big or not ours."""
    if not isinstance(raw, str) or not raw or len(raw) > MAX_BLOB:
        return None
    try:
        data = json.loads(raw)
    except ValueError:
        return None
    return data if isinstance(data, dict) and data.get("v") == 1 else None


def restore(room, data: dict) -> None:
    """Fill a freshly made room (callers hold its lock) from a parsed blob."""
    from games.native_hub import options
    from games.native_hub.engines.content_packs import SUPPORTED_PACKS

    pack = data.get("pack")
    if isinstance(pack, str) and pack in {code for code, _ in SUPPORTED_PACKS}:
        room.content_pack = pack
    topic = data.get("topic")
    if isinstance(topic, str):
        room.topic = topic.strip()[:80]
    picks = data.get("options")
    if isinstance(picks, dict):
        room.options = {k: v for k, v in picks.items()
                        if isinstance(k, str) and isinstance(v, str) and options.valid(room.game_id, k, v)}
    night = data.get("night")
    if isinstance(night, dict):
        _restore_night(room, night)


def _restore_night(room, raw: dict) -> None:
    from games import game_night, night_party
    from games.native_hub.registry import ENGINES

    playlist = [g for g in raw.get("playlist", []) if isinstance(g, str) and g in ENGINES][:10]
    if not playlist:
        return
    index = raw.get("index")
    index = index if isinstance(index, int) and not isinstance(index, bool) else 0
    index = max(0, min(index, len(playlist) - 1))
    totals, names = {}, {}
    for pid, pts in list((raw.get("totals") or {}).items())[:MAX_PLAYERS]:
        if isinstance(pid, str) and 0 < len(pid) <= 80 and isinstance(pts, int) \
                and not isinstance(pts, bool) and 0 <= pts <= 10_000:
            totals[pid] = pts
    for pid, name in list((raw.get("names") or {}).items())[:MAX_PLAYERS]:
        if pid in totals and isinstance(name, str):
            names[pid] = night_party.clean_text(name) or "Player"
    played = raw.get("played")
    played = played if isinstance(played, int) and not isinstance(played, bool) else index
    played = max(0, min(played, len(playlist)))
    points = raw.get("points")

    room.night = {
        "playlist": playlist, "index": index, "totals": totals, "names": names,
        "history": [{"gameID": playlist[i], "points": {}, "x": 1} for i in range(played)],
        "finished": bool(raw.get("finished")), "startedAt": time.time(),
        "kids": bool(raw.get("kids")), "kidsSeed": 0,
        "settings": game_night.clean_settings(playlist, raw.get("settings")),
        "points": points if points in game_night.POINT_MODES else game_night.DEFAULT_POINTS,
        "restored": True,
    }
    party = raw.get("party")
    if isinstance(party, dict):
        cleaned = night_party.clean_party(party)
        lineup = night_party.lineup_script(cleaned, playlist)
        welcome = night_party.welcome_script(cleaned)
        cleaned.update({
            # A party that already began does not start over with its welcome.
            "welcomed": bool(party.get("welcomed", True)),
            "title": night_party.title_for(cleaned),
            "cheer": night_party.cheer_for(cleaned),
            "welcomeLines": [t for t, _ in welcome], "welcomeCues": [c for _, c in welcome],
            "lineupLines": [t for t, _ in lineup], "lineupCues": [c for _, c in lineup],
            "finaleLines": [], "finaleCues": [],
            "indianVoice": night_party.indian_voice(cleaned),
        })
        room.night["party"] = cleaned
    room.game_id = playlist[index]
    game_night.apply_settings(room)
