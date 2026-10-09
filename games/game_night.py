"""Game Night: a playlist of games with one running scoreboard, plus the
smart picker that chooses games for the group in front of the TV.

    GET /api/picker?players=4&kids=1&minutes=30  -> {"games": [{"id", "minutes", ...}]}

Socket side (games/native_hub/socket_events.py): ``start_night``,
``next_game``, ``end_night``. The night lives on the room as
``room.night`` and rides along in ``room_updated`` (Room.to_json "night").

Scoring: each game's placings become night points (1st 10, 2nd 7,
3rd 5, 4th 3, everyone else who played 1), so a party game with 12
players and a 2-player duel weigh the same. The champion is whoever has
the most night points when the playlist ends.
"""

from __future__ import annotations

import random
import time

from flask import Blueprint, jsonify, request

#: Per-game facts the picker needs beyond min/max players (which come from
#: the engine classes). minutes = a typical round; kids = part of Kids
#: mode, which is LEARNING mode: only games that build knowledge or brain
#: skills (quizzes, puzzles, words and spelling, memory, logic, counting),
#: never social, bluffing, acting, casino or pure-action games; tags shape a
#: balanced night.
CATALOG: dict[str, dict] = {
    "trivia":             {"minutes": 10, "kids": True,  "tags": ["quiz"]},
    "brain_battle":       {"minutes": 12, "kids": True,  "tags": ["quiz", "brain"]},
    "most_likely_to":     {"minutes": 8,  "kids": False, "tags": ["social"]},
    "truth_or_dare":      {"minutes": 15, "kids": False, "tags": ["social"]},
    "herd":               {"minutes": 8,  "kids": False, "tags": ["social"]},
    "bluff_it":           {"minutes": 10, "kids": False, "tags": ["social", "words"]},
    "emoji_movie":        {"minutes": 10, "kids": False, "tags": ["creative"]},
    "npat":               {"minutes": 10, "kids": True,  "tags": ["words"]},
    "antakshari":         {"minutes": 15, "kids": False, "tags": ["music"]},
    "atlas":              {"minutes": 8,  "kids": True,  "tags": ["words", "geography"]},
    "bollywood_charades": {"minutes": 12, "kids": False, "tags": ["acting"]},
    "speed_sculptor":     {"minutes": 8,  "kids": False, "tags": ["creative"]},
    "mind_meld":          {"minutes": 8,  "kids": False, "tags": ["social"]},
    "wavelength":         {"minutes": 10, "kids": False, "tags": ["social"]},
    "odd_one_out":        {"minutes": 10, "kids": False, "tags": ["social"]},
    "cipher_grid":        {"minutes": 15, "kids": True,  "tags": ["words", "teams"]},
    "sealed_auction":     {"minutes": 8,  "kids": False, "tags": ["strategy"]},
    "last_tap":           {"minutes": 4,  "kids": False, "tags": ["action"]},
    "tambola":            {"minutes": 20, "kids": False, "tags": ["classic"]},
    "connect4":           {"minutes": 6,  "kids": True,  "tags": ["board"]},
    "ludo":               {"minutes": 20, "kids": False, "tags": ["board"]},
    "snake_ladder":       {"minutes": 12, "kids": True,  "tags": ["board"]},
    "battleship":         {"minutes": 12, "kids": True,  "tags": ["strategy"]},
    "heist":              {"minutes": 15, "kids": False, "tags": ["strategy"]},
    "heist_escape":       {"minutes": 10, "kids": False, "tags": ["action"]},
    "defuse":             {"minutes": 8,  "kids": False, "tags": ["teams"]},
    "raja_mantri":        {"minutes": 8,  "kids": False, "tags": ["classic"]},
    "mafia":              {"minutes": 20, "kids": False, "tags": ["social"]},
    "poker":              {"minutes": 25, "kids": False, "tags": ["cards"]},
    "teen_patti":         {"minutes": 15, "kids": False, "tags": ["cards"]},
    "hot_takes":          {"minutes": 10, "kids": False, "tags": ["social", "debate"]},
    "twenty_questions":   {"minutes": 10, "kids": True,  "tags": ["brain", "words"]},
}

NIGHT_POINTS = (10, 7, 5, 3)
PARTICIPATION_POINTS = 1


def _limits(game_id: str) -> tuple[int, int]:
    from games.native_hub.registry import ENGINES
    cls = ENGINES.get(game_id)
    if cls is None:
        return (0, 0)
    return (getattr(cls, "min_players", 1), getattr(cls, "max_players", 1))


def pick_games(players: int, kids: bool = False, minutes: int | None = None,
               rng: random.Random | None = None) -> list[dict]:
    """Every game that fits the group, best first.

    Fits = registered engine, player count within its limits, kid-safe
    when kids are present. Ranked by how well the group size suits the game
    (party games love big groups; duels are best at their exact size), then
    shuffled a little so the list isn't identical every night.
    """
    rng = rng or random.Random()
    out = []
    for gid, info in CATALOG.items():
        lo, hi = _limits(gid)
        if not lo or not lo <= players <= hi:
            continue
        if kids and not info["kids"]:
            continue
        if minutes is not None and info["minutes"] > max(minutes, 4):
            continue
        # 1.0 when the group fills the game well, lower at the edges.
        fill = players / hi if hi < 50 else 1.0
        score = 0.6 + 0.4 * min(1.0, fill) + rng.uniform(0, 0.25)
        out.append({"id": gid, "minutes": info["minutes"], "kids": info["kids"],
                    "tags": info["tags"], "minPlayers": lo, "maxPlayers": hi,
                    "score": round(score, 3)})
    out.sort(key=lambda g: g["score"], reverse=True)
    return out


def build_playlist(players: int, kids: bool = False, total_minutes: int = 45,
                   rng: random.Random | None = None) -> list[str]:
    """A balanced playlist: varied tags, about ``total_minutes`` long."""
    rng = rng or random.Random()
    candidates = pick_games(players, kids, rng=rng)
    playlist, used_tags, spent = [], set(), 0
    for g in candidates:
        if spent >= total_minutes or len(playlist) >= 8:
            break
        fresh_tag = not (set(g["tags"]) & used_tags)
        if fresh_tag or len(playlist) >= len(candidates) // 2:
            playlist.append(g["id"])
            used_tags.update(g["tags"])
            spent += g["minutes"]
    return playlist or [g["id"] for g in candidates[:3]]


# ---------------------------------------------------------------------------
# the night itself (callers hold room.lock)
# ---------------------------------------------------------------------------

#: Kids mode quiz topics: school-age learning, rotated game by game. The
#: quiz engines write fresh questions on room.topic (games/topic_gen.py).
KIDS_TOPICS = [
    "Science for kids", "Animals and nature for kids", "Space and planets for kids",
    "World geography for kids", "The human body for kids", "Maths puzzles for kids",
    "Inventions and how things work for kids", "Oceans and sea life for kids",
    "Dinosaurs and fossils for kids", "Weather and the seasons for kids",
]


def _apply_kids_topic(room) -> None:
    """In Kids mode, give the next quiz a learning topic -- unless the host
    chose their own topic, which always wins."""
    night = room.night or {}
    if not night.get("kids"):
        return
    if room.topic and room.topic != night.get("kidsTopic"):
        return                      # a topic the host set themselves
    topic = KIDS_TOPICS[(night.get("index", 0) + night.get("kidsSeed", 0)) % len(KIDS_TOPICS)]
    room.topic = topic
    night["kidsTopic"] = topic


def start(room, playlist: list[str], kids: bool = False) -> dict:
    room.night = {
        "playlist": list(playlist), "index": 0, "totals": {}, "names": {},
        "history": [], "finished": False, "startedAt": time.time(),
        "kids": bool(kids), "kidsSeed": random.randrange(len(KIDS_TOPICS)),
    }
    room.game_id = playlist[0]
    _apply_kids_topic(room)
    return room.night


def record_game(room, results: list) -> None:
    """Fold a finished game's placings into the night's totals."""
    night = getattr(room, "night", None)
    if not night or night.get("finished") or not isinstance(results, list):
        return
    gained = {}
    for r in results:
        if not isinstance(r, dict) or not r.get("playerID"):
            continue
        rank = r.get("rank")
        pts = NIGHT_POINTS[rank - 1] if isinstance(rank, int) and 1 <= rank <= len(NIGHT_POINTS) \
            else PARTICIPATION_POINTS
        pid = r["playerID"]
        gained[pid] = pts
        night["totals"][pid] = night["totals"].get(pid, 0) + pts
        night["names"][pid] = r.get("name") or night["names"].get(pid, "Player")
    night["history"].append({"gameID": room.game_id, "points": gained})


def advance(room) -> str | None:
    """Move to the next game; returns its id, or None when the night ends."""
    night = getattr(room, "night", None)
    if not night or night.get("finished"):
        return None
    night["index"] += 1
    if night["index"] >= len(night["playlist"]):
        night["finished"] = True
        return None
    room.game_id = night["playlist"][night["index"]]
    _apply_kids_topic(room)
    return room.game_id


def standings(room) -> list[dict]:
    night = getattr(room, "night", None) or {}
    bots = {p.id for p in getattr(room, "players", []) if getattr(p, "is_bot", False)}
    rows = sorted(night.get("totals", {}).items(), key=lambda kv: kv[1], reverse=True)
    return [{"playerID": pid, "name": night.get("names", {}).get(pid, "Player"),
             "points": pts, "rank": i + 1, "isBot": pid in bots}
            for i, (pid, pts) in enumerate(rows)]


def to_json(room) -> dict | None:
    night = getattr(room, "night", None)
    if not night:
        return None
    playlist = night["playlist"]
    idx = night["index"]
    return {
        "playlist": playlist,
        "index": idx,
        "current": playlist[idx] if idx < len(playlist) else None,
        "next": playlist[idx + 1] if idx + 1 < len(playlist) else None,
        "finished": night["finished"],
        "standings": standings(room),
        "gamesPlayed": len(night["history"]),
        "kids": bool(night.get("kids")),
    }


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

game_night_bp = Blueprint("game_night", __name__)


@game_night_bp.route("/picker", methods=["GET"])
def picker():
    try:
        players = max(1, min(20, int(request.args.get("players") or 4)))
    except ValueError:
        players = 4
    kids = (request.args.get("kids") or "").lower() in ("1", "true", "yes")
    try:
        minutes = int(request.args["minutes"]) if request.args.get("minutes") else None
    except ValueError:
        minutes = None
    return jsonify({"success": True, "players": players,
                    "games": pick_games(players, kids, minutes)})
