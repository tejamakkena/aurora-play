"""Player profiles: one per phone, kept across rooms and game nights.

A phone's player id is its stable device UUID, so a profile needs no
login: the phone just reads and writes its own id.

    GET  /api/profile/<device>          -> {"profile": {...}}
    PUT  /api/profile/<device>          {"name", "color", "avatar"} -> {"profile": {...}}
    GET  /api/profile/<device>/friends  -> {"friends": [{"id", "name", "color", "avatar"}]}

Stats are recorded server-side whenever a native-hub game finishes
(broadcast.finish_game -> record_results): games played, wins, podiums,
per-game counts and best scores, and who you played with (the "friends"
list that family leaderboards use).

Storage is a best-effort JSON file (PROFILES_PATH, default
data/profiles.json). On a free host that file resets on restart; the
phone keeps its own copy of name/colour/avatar and re-sends it, so the
profile itself is never lost, only server-side stats.
"""

from __future__ import annotations

import json
import os
import re
import threading
import time
from pathlib import Path

from flask import Blueprint, jsonify, request

_lock = threading.RLock()
_FRIENDS_CAP = 60
_COLORS = ("red", "orange", "yellow", "green", "teal", "blue", "indigo",
           "purple", "pink", "brown")
_AVATAR_RE = re.compile(r"^[a-z0-9.]{1,40}$")      # an SF Symbol name


def _path() -> Path:
    override = os.environ.get("PROFILES_PATH")
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1] / "data" / "profiles.json"


def _load() -> dict:
    try:
        data = json.loads(_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _save(data: dict) -> None:
    try:
        path = _path()
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)
    except OSError:
        pass


def _blank(device: str) -> dict:
    return {
        "id": device, "name": "", "color": _COLORS[sum(map(ord, device)) % len(_COLORS)],
        "avatar": "person.fill",
        "stats": {"played": 0, "wins": 0, "podiums": 0, "nights": 0, "nightWins": 0,
                  "byGame": {}, "lastPlayed": None},
        "friends": [],
    }


def get(device: str) -> dict:
    with _lock:
        return _load().get(device) or _blank(device)


def update(device: str, fields: dict) -> dict:
    """Set name / color / avatar (validated); returns the profile."""
    with _lock:
        data = _load()
        prof = data.get(device) or _blank(device)
        name = fields.get("name")
        if isinstance(name, str) and name.strip():
            prof["name"] = " ".join(name.split())[:24]
        color = fields.get("color")
        if color in _COLORS:
            prof["color"] = color
        avatar = fields.get("avatar")
        if isinstance(avatar, str) and _AVATAR_RE.match(avatar):
            prof["avatar"] = avatar
        data[device] = prof
        _save(data)
        return prof


def record_results(game_id: str, results: list, players: list) -> None:
    """Fold one finished game into every human player's profile."""
    humans = {p.id: p for p in players if not getattr(p, "is_bot", False)}
    if not humans or not isinstance(results, list):
        return
    ranks = {}
    for r in results:
        if isinstance(r, dict) and r.get("playerID") in humans:
            ranks[r["playerID"]] = (r.get("rank"), r.get("score"))
    now = time.time()
    with _lock:
        data = _load()
        for pid, player in humans.items():
            prof = data.get(pid) or _blank(pid)
            if not prof.get("name"):
                prof["name"] = getattr(player, "name", "")[:24]
            stats = prof.setdefault("stats", _blank(pid)["stats"])
            stats["played"] = stats.get("played", 0) + 1
            rank, score = ranks.get(pid, (None, None))
            if rank == 1:
                stats["wins"] = stats.get("wins", 0) + 1
            if isinstance(rank, int) and rank <= 3:
                stats["podiums"] = stats.get("podiums", 0) + 1
            game = stats.setdefault("byGame", {}).setdefault(
                game_id, {"played": 0, "wins": 0, "best": None})
            game["played"] += 1
            if rank == 1:
                game["wins"] += 1
            if isinstance(score, (int, float)) and (game["best"] is None or score > game["best"]):
                game["best"] = score
            stats["lastPlayed"] = now
            friends = [f for f in prof.get("friends", []) if f not in humans]
            friends = [f for f in humans if f != pid] + friends
            prof["friends"] = friends[:_FRIENDS_CAP]
            data[pid] = prof
        _save(data)


def record_night(standings: list[dict]) -> None:
    """A Game Night finished: count it for everyone, a win for the champion."""
    with _lock:
        data = _load()
        for i, row in enumerate(standings):
            pid = row.get("playerID")
            if not pid or row.get("isBot"):
                continue
            prof = data.get(pid) or _blank(pid)
            stats = prof.setdefault("stats", _blank(pid)["stats"])
            stats["nights"] = stats.get("nights", 0) + 1
            if i == 0:
                stats["nightWins"] = stats.get("nightWins", 0) + 1
            data[pid] = prof
        _save(data)


def friends_of(device: str) -> list[dict]:
    with _lock:
        data = _load()
        prof = data.get(device) or _blank(device)
        out = []
        for fid in prof.get("friends", []):
            f = data.get(fid)
            if f:
                out.append({k: f.get(k) for k in ("id", "name", "color", "avatar")})
        return out


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

profiles_bp = Blueprint("profiles", __name__)
_DEVICE_RE = re.compile(r"^[A-Za-z0-9._-]{4,64}$")


def _device_ok(device: str) -> bool:
    return bool(_DEVICE_RE.match(device or ""))


@profiles_bp.route("/profile/<device>", methods=["GET"])
def profile_get(device):
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device id"}), 400
    return jsonify({"success": True, "profile": get(device)})


@profiles_bp.route("/profile/<device>", methods=["PUT", "POST"])
def profile_put(device):
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device id"}), 400
    body = request.get_json(force=True, silent=True) or {}
    return jsonify({"success": True, "profile": update(device, body)})


@profiles_bp.route("/profile/<device>/friends", methods=["GET"])
def profile_friends(device):
    if not _device_ok(device):
        return jsonify({"success": False, "error": "bad device id"}), 400
    return jsonify({"success": True, "friends": friends_of(device)})
