"""Daily Brain Challenge: scores and leaderboards.

The phone generates the day's five puzzles itself (seeded by the date,
so everyone gets the same set, offline). The server only keeps scores:

    POST /api/daily/score {"device", "name", "date": "YYYY-MM-DD", "score", "seconds"}
    GET  /api/daily/leaderboard?date=YYYY-MM-DD[&device=ID]
         -> {"everyone": [...top 20], "friends": [...the device's friends + itself]}

One score per device per day: the first submission counts (no
replaying for a better score). The last 14 days are kept.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import threading
from pathlib import Path

from flask import Blueprint, jsonify, request

_lock = threading.RLock()
_KEEP_DAYS = 14
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_DEVICE_RE = re.compile(r"^[A-Za-z0-9._-]{4,64}$")


def _path() -> Path:
    override = os.environ.get("DAILY_SCORES_PATH")
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1] / "data" / "daily_scores.json"


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
        path.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass


def _valid_date(date: str) -> bool:
    if not _DATE_RE.match(date or ""):
        return False
    try:
        day = dt.date.fromisoformat(date)
    except ValueError:
        return False
    today = dt.date.today()
    # Time zones: allow a day either side of the server's today.
    return abs((day - today).days) <= 1


def submit(device: str, name: str, date: str, score: int, seconds: float) -> bool:
    """Record a score; False if invalid or already submitted today."""
    if not _DEVICE_RE.match(device or "") or not _valid_date(date):
        return False
    if not isinstance(score, int) or isinstance(score, bool) or not 0 <= score <= 5:
        return False
    try:
        seconds = float(seconds)
    except (TypeError, ValueError):
        return False
    if not 0 < seconds < 24 * 3600:
        return False
    with _lock:
        data = _load()
        day = data.setdefault(date, {})
        if device in day:
            return False
        day[device] = {"name": " ".join(str(name or "Player").split())[:24] or "Player",
                       "score": score, "seconds": round(seconds, 1)}
        for old in sorted(data)[:-_KEEP_DAYS]:
            data.pop(old, None)
        _save(data)
        return True


def _ranked(rows: dict) -> list[dict]:
    ordered = sorted(rows.items(), key=lambda kv: (-kv[1]["score"], kv[1]["seconds"]))
    return [{"device": d, "name": r["name"], "score": r["score"], "seconds": r["seconds"],
             "rank": i + 1} for i, (d, r) in enumerate(ordered)]


def leaderboard(date: str, device: str | None = None) -> dict:
    with _lock:
        day = _load().get(date, {})
    everyone = _ranked(day)
    friends = []
    if device:
        from games import profiles
        circle = {device} | {f["id"] for f in profiles.friends_of(device)}
        friends = _ranked({d: r for d, r in day.items() if d in circle})
    return {"everyone": everyone[:20], "friends": friends}


daily_bp = Blueprint("daily", __name__)


@daily_bp.route("/daily/score", methods=["POST"])
def daily_score():
    body = request.get_json(force=True, silent=True) or {}
    ok = submit(str(body.get("device") or ""), str(body.get("name") or ""),
                str(body.get("date") or ""), body.get("score"), body.get("seconds"))
    return jsonify({"success": ok}), (200 if ok else 400)


@daily_bp.route("/daily/leaderboard", methods=["GET"])
def daily_leaderboard():
    date = request.args.get("date") or dt.date.today().isoformat()
    if not _DATE_RE.match(date):
        return jsonify({"success": False, "error": "bad date"}), 400
    device = request.args.get("device") or None
    if device and not _DEVICE_RE.match(device):
        device = None
    return jsonify({"success": True, "date": date, **leaderboard(date, device)})
