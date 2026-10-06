"""Teams mode: split the room into 2-4 named teams that score together.

Any game works in teams mode -- the engines still rank players, and the
team scoreboard is built on top: after each game the teams are ranked by
their BEST-placed member and get 10 / 7 / 5 / 3 team points, so a team of
two is never punished for being small. Totals run across games until the
host clears the teams (or the room closes).

Socket side (games/native_hub/socket_events.py): ``set_teams`` (auto
split, or explicit lists), ``move_to_team``, ``clear_teams``. The teams
ride along in ``room_updated`` as an additive ``teams`` key.

room.teams = {"teams": [{"id", "name", "color", "members": [pid]}],
              "points": {tid: total}, "last": {tid: gained}}
"""

from __future__ import annotations

import random

#: (name, colour) pairs. Colours are names the apps map to their palette.
TEAM_STYLES = [
    ("Red Rockets", "red"),
    ("Blue Comets", "blue"),
    ("Green Geckos", "green"),
    ("Gold Lions", "yellow"),
]
TEAM_POINTS = (10, 7, 5, 3)
MAX_NAME = 24


def _clean_name(raw, fallback: str) -> str:
    if not isinstance(raw, str):
        return fallback
    name = " ".join(raw.split())[:MAX_NAME]
    return name or fallback


def set_teams(room, count: int = 2, lists=None, names=None, shuffle: bool = True) -> dict:
    """Create teams. ``lists`` (optional) is [[playerID, ...], ...]; anyone
    in the room not listed is dealt onto the smallest team. Callers hold
    room.lock."""
    count = max(2, min(int(count or 2), len(TEAM_STYLES)))
    if isinstance(lists, list) and 2 <= len(lists) <= len(TEAM_STYLES):
        count = len(lists)
    names = names if isinstance(names, list) else []
    teams = []
    for i in range(count):
        default, color = TEAM_STYLES[i]
        teams.append({"id": f"t{i + 1}", "name": _clean_name(names[i] if i < len(names) else None, default),
                      "color": color, "members": []})
    known = {p.id for p in room.players}
    placed: set[str] = set()
    if isinstance(lists, list):
        for team, ids in zip(teams, lists):
            if not isinstance(ids, list):
                continue
            for pid in ids:
                if isinstance(pid, str) and pid in known and pid not in placed:
                    team["members"].append(pid)
                    placed.add(pid)
    rest = [p.id for p in room.players if p.id not in placed]
    if shuffle:
        random.shuffle(rest)
    for pid in rest:
        min(teams, key=lambda t: len(t["members"]))["members"].append(pid)
    room.teams = {"teams": teams, "points": {t["id"]: 0 for t in teams}, "last": {}}
    return room.teams


def clear(room) -> None:
    room.teams = None


def team_of(room, player_id: str):
    data = getattr(room, "teams", None)
    if not data:
        return None
    for team in data["teams"]:
        if player_id in team["members"]:
            return team
    return None


def move(room, player_id: str, team_id: str) -> bool:
    data = getattr(room, "teams", None)
    if not data or player_id not in {p.id for p in room.players}:
        return False
    target = next((t for t in data["teams"] if t["id"] == team_id), None)
    if target is None:
        return False
    for team in data["teams"]:
        if player_id in team["members"]:
            team["members"].remove(player_id)
    target["members"].append(player_id)
    return True


def sync_members(room) -> None:
    """Drop players who left and deal newcomers onto the smallest team."""
    data = getattr(room, "teams", None)
    if not data:
        return
    present = [p.id for p in room.players]
    present_set = set(present)
    placed = set()
    for team in data["teams"]:
        team["members"] = [pid for pid in team["members"] if pid in present_set]
        placed.update(team["members"])
    for pid in present:
        if pid not in placed:
            min(data["teams"], key=lambda t: len(t["members"]))["members"].append(pid)


def record_game(room, results: list) -> None:
    """Rank teams by their best-placed member and award team points."""
    data = getattr(room, "teams", None)
    if not data or not isinstance(results, list):
        return
    best: dict[str, int] = {}
    for r in results:
        if not isinstance(r, dict):
            continue
        rank = r.get("rank")
        team = team_of(room, r.get("playerID") or "")
        if team is None or not isinstance(rank, int):
            continue
        if team["id"] not in best or rank < best[team["id"]]:
            best[team["id"]] = rank
    ordered = sorted(best.items(), key=lambda kv: kv[1])
    gained: dict[str, int] = {}
    place = 0
    prev_rank = None
    for i, (tid, rank) in enumerate(ordered):
        if rank != prev_rank:          # shared best rank -> shared placing
            place = i
            prev_rank = rank
        gained[tid] = TEAM_POINTS[place] if place < len(TEAM_POINTS) else 1
    for tid, pts in gained.items():
        data["points"][tid] = data["points"].get(tid, 0) + pts
    data["last"] = gained


def to_json(room):
    data = getattr(room, "teams", None)
    if not data:
        return None
    names = {p.id: p.name for p in room.players}
    rows = []
    for team in data["teams"]:
        rows.append({
            "id": team["id"],
            "name": team["name"],
            "color": team["color"],
            "members": [pid for pid in team["members"] if pid in names],
            "points": data["points"].get(team["id"], 0),
            "lastGained": data.get("last", {}).get(team["id"]),
        })
    ranked = sorted(rows, key=lambda t: t["points"], reverse=True)
    for i, row in enumerate(ranked):
        row["rank"] = i + 1
    return {"teams": rows}
