"""The party layer of a Game Night: an occasion, a guest of honour, a host style.

A plain Game Night (games/game_night.py) is a playlist and a scoreboard. When the
host also sets up a *party* (a birthday, an anniversary...), the TV shows a welcome
screen until the host begins, then speaks a welcome, the lineup, and at the end the
champion. This module holds the choices, the validator and the scripts. It touches
no room and no socket.

The TV has one consistent voice (see TVVoiceHost); a *style* is a way of talking,
not a different voice. Fixed lines are part of the offline voice pack
(tools/render_voice_pack.py); lines with a name in them are spoken live.

All text is emoji-free: it is shown on screen and read aloud.
"""

import random
from typing import Any

from games.native_hub.engines import _humor as H
from games.native_hub.engines import _nhie_packs as P

MAX_NAME_LEN = 30
NHIE_ROUND_CHOICES = (5, 10, 15, 20)

#: ``symbol`` is an SF Symbol name; ``title`` / ``cheer`` take {name} and {possessive}.
OCCASIONS = [
    {"id": "birthday", "label": "Birthday", "symbol": "gift.fill",
     "nameLabel": "Birthday person",
     "title": "{possessive} Birthday Party", "title_noname": "Birthday Party",
     "cheer": "Happy birthday, {name}!", "cheer_noname": "Happy birthday!"},
    {"id": "anniversary", "label": "Anniversary", "symbol": "heart.fill",
     "nameLabel": "Celebrating",
     "title": "{possessive} Anniversary Party", "title_noname": "Anniversary Party",
     "cheer": "Happy anniversary, {name}!", "cheer_noname": "Happy anniversary!"},
    {"id": "housewarming", "label": "Housewarming", "symbol": "house.fill",
     "nameLabel": "Home of",
     "title": "{possessive} Housewarming", "title_noname": "Housewarming Party",
     "cheer": "Congratulations on the new home, {name}!",
     "cheer_noname": "Congratulations on the new home!"},
    {"id": "festival", "label": "Festival", "symbol": "sparkles",
     "nameLabel": "Festival (Diwali, Holi, Eid...)",
     "title": "{name} Party", "title_noname": "Festival Party",
     "cheer": "Happy {name}!", "cheer_noname": "Happy festival!"},
    {"id": "newyear", "label": "New Year's Eve", "symbol": "moon.stars.fill",
     "nameLabel": "",
     "title": "New Year's Eve Party", "title_noname": "New Year's Eve Party",
     "cheer": "Happy New Year!", "cheer_noname": "Happy New Year!"},
    {"id": "gathering", "label": "Get-together", "symbol": "person.3.fill",
     "nameLabel": "Hosted by (optional)",
     "title": "{possessive} Game Night", "title_noname": "Game Night",
     "cheer": "Let the games begin!", "cheer_noname": "Let the games begin!"},
]
OCCASIONS_BY_ID = {o["id"]: o for o in OCCASIONS}
DEFAULT_OCCASION = "gathering"

#: Host styles: the same facts, said differently. Every style defines every key.
STYLES = {
    "party_host": {
        "name": "Party Host", "symbol": "party.popper.fill", "blurb": "Upbeat and full of energy",
        "welcome": ["Welcome to {title}!", "Hello, hello! Welcome to {title}!"],
        "intro": "Tonight we are playing {count} games.",
        "first": "We kick things off with {game}.", "then": "Then, {game}.",
        "last": "And we finish with {game}.", "only": "Tonight it is all about {game}.",
        "outro": "Let us get this party started!",
        "finale": "That is a wrap on {title}!",
        "champion": "Tonight's champion is {winner}, with {points} points!",
        "nogames": "We did not get to play tonight, and that is okay.",
    },
    "game_show": {
        "name": "Game Show", "symbol": "mic.fill", "blurb": "Big announcer energy",
        "welcome": ["Ladies and gentlemen, welcome to {title}!"],
        "intro": "Tonight's lineup features {count} spectacular games.",
        "first": "First, the one and only {game}!", "then": "Followed by {game}!",
        "last": "And the grand finale, {game}!", "only": "Tonight's main event: {game}!",
        "outro": "Let the games begin!",
        "finale": "That concludes {title}!",
        "champion": "Tonight's grand champion is {winner}, with {points} points!",
        "nogames": "No contests tonight, folks. Better luck next time!",
    },
    "desi_dost": {
        "name": "Desi Dost", "symbol": "hands.sparkles.fill", "blurb": "Warm and friendly, Indian English",
        "welcome": ["Namaste, everyone! Welcome to {title}!"],
        "intro": "Today we have {count} games for you.",
        "first": "First, we will play {game}.", "then": "After that, {game}.",
        "last": "And finally, {game}.", "only": "Today, we will play {game}.",
        "outro": "So, shall we begin?",
        "finale": "And that is the end of {title}!",
        "champion": "Congratulations to {winner}, the champion, with {points} points!",
        "nogames": "We could not play today, but we had a lovely time.",
    },
    "chill": {
        "name": "Chill", "symbol": "cup.and.saucer.fill", "blurb": "Relaxed and easygoing",
        "welcome": ["Hey everyone, welcome to {title}."],
        "intro": "Here is what we have tonight: {count} games.",
        "first": "We will start with {game}.", "then": "Then {game}.",
        "last": "And we will wrap up with {game}.", "only": "Tonight we are playing {game}.",
        "outro": "Grab a drink and get comfortable.",
        "finale": "And that is {title}.",
        "champion": "Tonight's champion is {winner}, with {points} points.",
        "nogames": "We did not play anything tonight. That is fine.",
    },
}
DEFAULT_STYLE = "party_host"


def default_party() -> dict:
    return {"occasion": DEFAULT_OCCASION, "honoree": "", "style": DEFAULT_STYLE,
            "humor": H.DEFAULT_PACK, "nhiePack": P.DEFAULT_PACK, "nhieRounds": 10}


def clean_text(value: Any, limit: int = MAX_NAME_LEN) -> str:
    """Collapse whitespace, drop control characters, cap the length."""
    if not isinstance(value, str):
        return ""
    cleaned = " ".join(value.split())
    cleaned = "".join(ch for ch in cleaned if ch.isprintable())
    return cleaned[:limit].strip()


def clean_party(raw: Any, base: dict | None = None) -> dict:
    """Merge client-supplied settings over ``base``, keeping only valid values.
    The client is untrusted: an invalid field keeps its previous value."""
    party = dict(base) if base else default_party()
    if not isinstance(raw, dict):
        return party
    if raw.get("occasion") in OCCASIONS_BY_ID:
        party["occasion"] = raw["occasion"]
    if "honoree" in raw:
        party["honoree"] = clean_text(raw.get("honoree"))
    if raw.get("style") in STYLES:
        party["style"] = raw["style"]
    if isinstance(raw.get("humor"), str) and raw["humor"] in H.PACK_IDS:
        party["humor"] = raw["humor"]
    if isinstance(raw.get("nhiePack"), str) and raw["nhiePack"] in P.PACK_IDS:
        party["nhiePack"] = raw["nhiePack"]
    rounds = raw.get("nhieRounds")
    if isinstance(rounds, int) and not isinstance(rounds, bool) and rounds in NHIE_ROUND_CHOICES:
        party["nhieRounds"] = rounds
    return party


def possessive(name: str) -> str:
    if not name:
        return ""
    return f"{name}'" if name.lower().endswith("s") else f"{name}'s"


def _occasion(party: dict) -> dict:
    return OCCASIONS_BY_ID.get(party.get("occasion"), OCCASIONS_BY_ID[DEFAULT_OCCASION])


def title_for(party: dict) -> str:
    occasion, name = _occasion(party), clean_text(party.get("honoree"))
    if name:
        return occasion["title"].format(name=name, possessive=possessive(name))
    return occasion["title_noname"]


def cheer_for(party: dict) -> str:
    occasion, name = _occasion(party), clean_text(party.get("honoree"))
    return occasion["cheer"].format(name=name) if name else occasion["cheer_noname"]


def _style(party: dict) -> dict:
    return STYLES.get(party.get("style"), STYLES[DEFAULT_STYLE])


def _game_name(game_id: str) -> str:
    from games.native_hub.rules import rules_for
    return rules_for(game_id).get("title") or game_id


def welcome_lines(party: dict) -> list[str]:
    lines = [random.choice(_style(party)["welcome"]).format(title=title_for(party))]
    if party.get("occasion") != "gathering":      # the generic cheer would repeat the welcome
        lines.append(cheer_for(party))
    return lines


def lineup_lines(party: dict, playlist: list[str]) -> list[str]:
    style = _style(party)
    names = [_game_name(g) for g in playlist]
    if not names:
        return [style["nogames"]]
    if len(names) == 1:
        return [style["only"].format(game=names[0]), style["outro"]]
    lines = [style["intro"].format(count=len(names))]
    for i, name in enumerate(names):
        key = "first" if i == 0 else "last" if i == len(names) - 1 else "then"
        lines.append(style[key].format(game=name))
    lines.append(style["outro"])
    return lines


def finale_lines(party: dict, winner: str | None, points: int) -> list[str]:
    style = _style(party)
    lines = [style["finale"].format(title=title_for(party))]
    lines.append(style["champion"].format(winner=winner, points=points) if winner
                 else style["nogames"])
    if party.get("occasion") != "gathering":
        lines.append(cheer_for(party))
    return lines

