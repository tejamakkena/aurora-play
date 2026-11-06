"""Game Night: a playlist of games with one running scoreboard, plus the
smart picker that chooses games for the group in front of the TV.

    GET /api/picker?players=4&kids=1&minutes=30  -> {"games": [{"id", "minutes", ...}]}

Socket side (games/native_hub/socket_events.py): ``start_night``,
``next_game``, ``end_night``. The night lives on the room as
``room.night`` and rides along in ``room_updated`` (Room.to_json "night").

Scoring: each game's placings become night points, so a party game with 12
players and a 2-player duel weigh the same. The host picks how (``points``):

  classic   1st 10, 2nd 7, 3rd 5, 4th 3, everyone else who played 1.
  fair      1st 10 down to 1 for last, in even steps across the field, so
            every placing counts and a small game is worth as much as a big one.
  comeback  classic, but the last game pays double so the night is never over
            before it ends.

The champion is whoever has the most night points when the playlist ends.
"""

from __future__ import annotations

import random
import time

from flask import Blueprint, jsonify, request

from games.native_hub import scoring

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
    "would_rather":       {"minutes": 8,  "kids": False, "tags": ["social"]},
    "host_lies":          {"minutes": 10, "kids": False, "tags": ["quiz", "social"]},
    "herd":               {"minutes": 8,  "kids": False, "tags": ["social"]},
    "never_have_i_ever":  {"minutes": 10, "kids": False, "tags": ["social"]},
    "guess_the_song":     {"minutes": 12, "kids": False, "tags": ["music"]},
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
TOP_POINTS = NIGHT_POINTS[0]

#: How a night turns placings into points. Order is the order shown to the host.
POINT_MODES: dict[str, dict] = {
    "classic":  {"label": "Classic", "hint": "10, 7, 5, 3 points, 1 for the rest"},
    "fair":     {"label": "Fair share", "hint": "Every place counts, 10 down to 1"},
    "comeback": {"label": "Big finish", "hint": "Classic, with the last game worth double"},
}
DEFAULT_POINTS = "classic"


def game_points(mode: str, rank, field: int) -> int:
    """Night points for finishing ``rank`` among ``field`` players (before any
    last-game bonus). ``rank`` is None or out of range for a non-placing finish."""
    if not isinstance(rank, int) or isinstance(rank, bool) or rank < 1:
        return PARTICIPATION_POINTS
    if mode == "fair":
        if field <= 1:
            return TOP_POINTS
        rank = min(rank, field)
        step = (TOP_POINTS - PARTICIPATION_POINTS) / (field - 1)
        return max(PARTICIPATION_POINTS, round(TOP_POINTS - (rank - 1) * step))
    return NIGHT_POINTS[rank - 1] if rank <= len(NIGHT_POINTS) else PARTICIPATION_POINTS


def multiplier(room) -> int:
    """2 on the last game of a "comeback" night, else 1."""
    night = getattr(room, "night", None) or {}
    if night.get("points") != "comeback":
        return 1
    return 2 if night.get("index", 0) >= len(night.get("playlist", [])) - 1 else 1


def _limits(game_id: str) -> tuple[int, int]:
    from games.native_hub.registry import ENGINES
    cls = ENGINES.get(game_id)
    if cls is None:
        return (0, 0)
    return (getattr(cls, "min_players", 1), getattr(cls, "max_players", 1))


#: Games a party night leads with (games/night_party.py): the two made for
#: it first, then the room-wide talking, singing and acting games.
PARTY_HEADLINERS = ("never_have_i_ever", "guess_the_song")
PARTY_TAGS = {"social", "music", "acting"}


def pick_games(players: int, kids: bool = False, minutes: int | None = None,
               rng: random.Random | None = None, party: bool = False) -> list[dict]:
    """Every game that fits the group, best first.

    Fits = registered engine, player count within its limits, kid-safe
    when kids are present. Ranked by how well the group size suits the game
    (party games love big groups; duels are best at their exact size), then
    shuffled a little so the list isn't identical every night. A party
    night ranks Never Have I Ever and Guess the Song first, then the other
    social, music and acting games, ahead of board games and duels.
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
        if party:
            if gid in PARTY_HEADLINERS:
                score += 2.0
            elif PARTY_TAGS & set(info["tags"]):
                score += 1.0
        out.append({"id": gid, "minutes": info["minutes"], "kids": info["kids"],
                    "tags": info["tags"], "minPlayers": lo, "maxPlayers": hi,
                    "score": round(score, 3)})
    out.sort(key=lambda g: g["score"], reverse=True)
    return out


def all_games(kids: bool = False) -> list[dict]:
    """Every catalog game that has an engine, fit for this group size or not."""
    out = []
    for gid, info in CATALOG.items():
        lo, hi = _limits(gid)
        if not lo or (kids and not info["kids"]):
            continue
        out.append({"id": gid, "minutes": info["minutes"], "kids": info["kids"],
                    "tags": info["tags"], "minPlayers": lo, "maxPlayers": hi, "score": 0})
    return out


def build_playlist(players: int, kids: bool = False, total_minutes: int = 45,
                   rng: random.Random | None = None, party: bool = False) -> list[str]:
    """A balanced playlist: varied tags, about ``total_minutes`` long."""
    rng = rng or random.Random()
    candidates = pick_games(players, kids, rng=rng, party=party)
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


def clean_settings(playlist: list[str], raw) -> dict[str, dict[str, str]]:
    """The host's per-game picks (rounds, decks, chips...) from a client, kept
    only where the game offers that option and that choice."""
    from games.native_hub import options
    out: dict[str, dict[str, str]] = {}
    if not isinstance(raw, dict):
        return out
    for gid in set(playlist):
        picks = raw.get(gid)
        if not isinstance(picks, dict):
            continue
        keep = {str(k): str(v) for k, v in picks.items()
                if isinstance(k, str) and isinstance(v, (str, int))
                and not isinstance(v, bool) and options.valid(gid, k, str(v))}
        if keep:
            out[gid] = keep
    return out


def apply_settings(room) -> None:
    """Give the room the host's picks for the game that is up, and none of the
    previous game's: a "6 rounds" for one game must not leak into the next."""
    night = getattr(room, "night", None) or {}
    room.options = dict((night.get("settings") or {}).get(room.game_id, {}))


def start(room, playlist: list[str], kids: bool = False, party: dict | None = None,
          settings: dict | None = None, points: str | None = None) -> dict:
    room.night = {
        "playlist": list(playlist), "index": 0, "totals": {}, "names": {},
        "history": [], "finished": False, "startedAt": time.time(),
        "kids": bool(kids), "kidsSeed": random.randrange(len(KIDS_TOPICS)),
        "settings": clean_settings(playlist, settings),
        "points": points if points in POINT_MODES else DEFAULT_POINTS,
    }
    if party is not None:
        # A party (games/night_party.py): the TV holds a welcome screen until
        # the host begins. The spoken lines are fixed here so every push of the
        # room says the same thing.
        from games import night_party
        cleaned = night_party.clean_party(party)
        cleaned.update({
            "welcomed": False,
            "title": night_party.title_for(cleaned),
            "cheer": night_party.cheer_for(cleaned),
            "welcomeLines": night_party.welcome_lines(cleaned),
            "lineupLines": night_party.lineup_lines(cleaned, playlist),
            "finaleLines": [],
        })
        room.night["party"] = cleaned
    room.game_id = playlist[0]
    apply_settings(room)
    _apply_kids_topic(room)
    from games import show_host
    show_host.night_opened(room)
    return room.night


def record_game(room, results: list) -> None:
    """Fold a finished game's placings into the night's totals."""
    night = getattr(room, "night", None)
    if not night or night.get("finished") or not isinstance(results, list):
        return
    gained = {}
    # A game with no winner (Truth or Dare) or one the team lost (Defuse)
    # gives everyone the same small point; placings only count when someone won.
    no_winner = scoring.is_social(room.game_id) or (
        scoring.is_coop(room.game_id)
        and not any(isinstance(r, dict) and (r.get("score") or 0) > 0 for r in results))
    mode = night.get("points", DEFAULT_POINTS)
    bonus = multiplier(room)
    field = sum(1 for r in results if isinstance(r, dict) and r.get("playerID"))
    for r in results:
        if not isinstance(r, dict) or not r.get("playerID"):
            continue
        pts = PARTICIPATION_POINTS if no_winner else game_points(mode, r.get("rank"), field)
        pts *= bonus
        pid = r["playerID"]
        gained[pid] = pts
        night["totals"][pid] = night["totals"].get(pid, 0) + pts
        night["names"][pid] = r.get("name") or night["names"].get(pid, "Player")
    night["history"].append({"gameID": room.game_id, "points": gained, "x": bonus})


def advance(room) -> str | None:
    """Move to the next game; returns its id, or None when the night ends."""
    night = getattr(room, "night", None)
    if not night or night.get("finished"):
        return None
    night["index"] += 1
    if night["index"] >= len(night["playlist"]):
        night["finished"] = True
        party = night.get("party")
        if party:
            from games import night_party
            top = standings(room)[:1]
            winner = top[0]["name"] if top and top[0]["points"] > 0 else None
            party["finaleLines"] = night_party.finale_lines(
                party, winner, top[0]["points"] if top else 0)
        from games import show_host
        show_host.night_closed(room)
        return None
    room.game_id = night["playlist"][night["index"]]
    apply_settings(room)
    _apply_kids_topic(room)
    from games import show_host
    show_host.game_up_next(room)
    return room.game_id


def begin_party(room) -> bool:
    """The host starts the show: the TV stops holding the welcome screen."""
    party = (getattr(room, "night", None) or {}).get("party")
    if not party or party.get("welcomed"):
        return False
    party["welcomed"] = True
    return True


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
        "party": _party_json(night.get("party")),
        "points": night.get("points", DEFAULT_POINTS),
        "pointsLabel": POINT_MODES[night.get("points", DEFAULT_POINTS)]["label"],
        "multiplier": multiplier(room),
        "rounds": {gid: picks["rounds"] for gid, picks in (night.get("settings") or {}).items()
                   if "rounds" in picks},
    }


def _party_json(party: dict | None) -> dict | None:
    if not party:
        return None
    return {k: party.get(k) for k in (
        "occasion", "honoree", "title", "cheer", "welcomed",
        "welcomeLines", "lineupLines", "finaleLines")}


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
    party = (request.args.get("party") or "").lower() in ("1", "true", "yes")
    games = pick_games(players, kids, minutes, party=party)
    for g in games:
        g["fits"] = True
    if (request.args.get("all") or "").lower() in ("1", "true", "yes"):
        # The host builder shows every game, with a flag for the ones that do
        # not fit this group, so the host can still choose them.
        fits = {g["id"] for g in games}
        games = games + [dict(g, fits=False) for g in all_games(kids) if g["id"] not in fits]
    from games.native_hub import options
    for g in games:
        g["options"] = [{"key": o["key"], "label": o["label"], "default": o["default"],
                         "choices": [{"value": c[0], "label": c[1]} for c in o["choices"]]}
                        for o in options.menu(g["id"])]
    return jsonify({"success": True, "players": players, "games": games,
                    "pointModes": [{"id": k, **v} for k, v in POINT_MODES.items()]})
