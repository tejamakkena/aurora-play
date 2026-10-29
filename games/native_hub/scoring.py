"""What a game's ``score`` means, so results never say "1 pts" or "1000 pts".

Every engine ranks players by an int ``score``, but for many games that number
is not points: a chess win is 1, a Mafia win is 1000, a Snakes and Ladders
score is the square you stand on. Showing "pts" for them is noise, and ranking
the party games that have no winner (Truth or Dare, Would You Rather) into
Game Night points is worse.

Each game has a *kind*:

  points  the default: "12 pts".
  unit    the score counts something: "42 chips", "square 87".
  winner  one winner, no running score: "Winner" on the first row, nothing on
          the rest. Chess, Connect 4.
  side    one side wins or loses and the score is only a win flag: "Won" or
          "Lost". Mafia, Heist.
  coop    everyone wins or loses together: "Won" or "Lost". Defuse, Heist Escape.
  social  no winner at all, just play: no score shown, and Game Night gives
          everyone the same small participation point. Truth or Dare, Would
          You Rather, Most Likely To, Never Have I Ever.

``label`` is what a results row shows next to the player's name; an empty
string means show no score at all. The apps and the browser controller show
``scoreLabel`` when the server sends it and fall back to "N pts" for an older
server.
"""

from __future__ import annotations

POINTS = "points"
UNIT = "unit"
WINNER = "winner"
SIDE = "side"
COOP = "coop"
SOCIAL = "social"

#: game id -> (kind, unit template). The template uses ``{n}``.
SCORING: dict[str, tuple[str, str]] = {
    "chess": (WINNER, ""),
    "connect4": (WINNER, ""),
    "mafia": (SIDE, ""),
    "heist": (SIDE, ""),
    "defuse": (COOP, ""),
    "heist_escape": (COOP, ""),
    "would_rather": (SOCIAL, ""),
    "truth_or_dare": (SOCIAL, ""),
    "most_likely_to": (SOCIAL, ""),
    "never_have_i_ever": (SOCIAL, ""),
    "poker": (UNIT, "{n} chips"),
    "teen_patti": (UNIT, "{n} chips"),
    "snake_ladder": (UNIT, "square {n}"),
    "ludo": (UNIT, "{n} steps"),
    "memory": (UNIT, "{n} pairs"),
    "battleship": (UNIT, "{n} hits"),
}


def kind(game_id: str | None) -> str:
    return SCORING.get(game_id or "", (POINTS, ""))[0]


def label(game_id: str | None, score: int) -> str:
    """The text for one results row; "" means show no score."""
    what, unit = SCORING.get(game_id or "", (POINTS, ""))
    if what == SOCIAL:
        return ""
    if what == WINNER:
        return "Winner" if score > 0 else ""
    if what in (SIDE, COOP):
        return "Won" if score > 0 else "Lost"
    if what == UNIT:
        return unit.format(n=score)
    return f"{score} pts"


def is_social(game_id: str | None) -> bool:
    return kind(game_id) == SOCIAL


def is_coop(game_id: str | None) -> bool:
    return kind(game_id) == COOP
