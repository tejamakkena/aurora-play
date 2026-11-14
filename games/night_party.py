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
import re
from typing import Any

from games import party_script as PS
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

#: Host styles: the same show, said differently. Every style defines every key.
#: Sentences with a {title} or {winner} in them are the only ones that carry a
#: name (see games/party_script.py); the rest are fixed.
STYLES = {
    "party_host": {
        "name": "Party Host", "symbol": "party.popper.fill", "blurb": "Upbeat and full of energy",
        "welcome": ["Ladies and gentlemen, boys and girls, welcome to {title}!",
                    "Welcome, welcome, welcome to {title}!"],
        "banter": "Phones out, snacks ready, and egos on standby.",
        "intro": "Tonight we have {count} lined up, and I picked them with love and a little bit of malice.",
        "first": "First up, {game}!", "then": "Then, {game}!",
        "last": "And to finish, {game}!", "only": "Tonight it is all about {game}!",
        "outro": "Phones ready? Egos ready? Let us go!",
        "finale": "And that, my friends, is a wrap!",
        "champion_lead": "And the champion of the night is...",
        "champion": "{winner}!",
        "champion_after": "Take a bow!",
        "others": "Everyone else, there is always a rematch.",
        "nogames": "We did not get to play tonight, and that is okay. The snacks were great.",
    },
    "game_show": {
        "name": "Game Show", "symbol": "mic.fill", "blurb": "Big announcer energy",
        "welcome": ["Live from the living room, ladies and gentlemen, welcome to {title}!"],
        "banter": "Tonight's prizes include glory, bragging rights, and absolutely nothing else.",
        "intro": "Tonight's show features {count}, each one more spectacular than the last!",
        "first": "First, the one and only {game}!", "then": "Followed by {game}!",
        "last": "And the grand finale, {game}!", "only": "Tonight's main event: {game}!",
        "outro": "Let the games begin!",
        "finale": "That is all from the living room, folks!",
        "champion_lead": "And tonight's grand champion is...",
        "champion": "{winner}!",
        "champion_after": "Come on down!",
        "others": "Everyone else, thank you for playing. Our lawyers say you may not demand a recount.",
        "nogames": "No contests tonight, folks. Better luck next time!",
    },
    "desi_dost": {
        "name": "Desi Dost", "symbol": "hands.sparkles.fill", "blurb": "Warm and friendly, Indian English",
        "welcome": ["Namaste, everyone! Welcome to {title}!"],
        "banter": "First eat something, then lose gracefully. That is the rule of the house.",
        "intro": "Today we have {count} for you, and every one of them will test your friendship!",
        "first": "First, we will play {game}!", "then": "After that, {game}!",
        "last": "And finally, {game}!", "only": "Today, we will play {game}!",
        "outro": "So, shall we begin?",
        "finale": "And that is the end of the party, but not the end of the arguments!",
        "champion_lead": "And the winner of the night is...",
        "champion": "{winner}!",
        "champion_after": "Give them a big round of applause!",
        "others": "Everyone else, no tension, there is always next time. And tea.",
        "nogames": "We could not play today, but we had a lovely time.",
    },
    "chill": {
        "name": "Chill", "symbol": "cup.and.saucer.fill", "blurb": "Relaxed and easygoing",
        "welcome": ["Hey everyone, welcome to {title}."],
        "banter": "No pressure, no rush. Mostly no pressure.",
        "intro": "We have {count} tonight, and every one of them is easy to lose.",
        "first": "We will start with {game}.", "then": "Then {game}.",
        "last": "And we will wrap up with {game}.", "only": "Tonight we are playing {game}.",
        "outro": "Grab a drink and get comfortable.",
        "finale": "And that is a wrap.",
        "champion_lead": "Tonight's champion is...",
        "champion": "{winner}.",
        "champion_after": "Nicely done.",
        "others": "Everyone else, you did great, and we all saw it.",
        "nogames": "We did not play anything tonight. That is fine.",
    },
}
DEFAULT_STYLE = "party_host"


def default_party() -> dict:
    return {"occasion": DEFAULT_OCCASION, "honoree": "", "style": DEFAULT_STYLE,
            "humor": H.DEFAULT_PACK, "nhiePack": P.DEFAULT_PACK, "nhieRounds": 10,
            "accent": "auto"}


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
    if "honoreeSaid" in raw:
        party["honoreeSaid"] = clean_text(raw.get("honoreeSaid"))
    if raw.get("style") in STYLES:
        party["style"] = raw["style"]
    if isinstance(raw.get("humor"), str) and raw["humor"] in H.PACK_IDS:
        party["humor"] = raw["humor"]
    if isinstance(raw.get("nhiePack"), str) and raw["nhiePack"] in P.PACK_IDS:
        party["nhiePack"] = raw["nhiePack"]
    if raw.get("accent") in ("auto", "indian", "standard"):
        party["accent"] = raw["accent"]
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


#: Said to everyone who did not win, on a Kids night (instead of a roast).
KIDS_OTHERS = "Everybody played brilliantly tonight. Give yourselves a big clap!"


def say_as(party: dict) -> dict[str, str]:
    """``{name on screen: how to say it}`` when the host typed a "Say it as"
    spelling for the guest of honour ("Venkat" -> "Ven-kut"), else empty."""
    name, said = clean_text(party.get("honoree")), clean_text(party.get("honoreeSaid"))
    return {name: said} if name and said and said != name else {}


def spoken(text: str, party: dict | None) -> str:
    """``text`` as the voice should say it: every "Say it as" name swapped in.
    The screen keeps the real spelling; only the voice uses this."""
    for name, said in say_as(party or {}).items():
        text = re.sub(rf"\b{re.escape(name)}\b", said, text)
    return text


def indian_voice(party: dict) -> bool:
    """True when the guest of honour's name should be said the Indian way: the
    host asked for it, or (on "auto") the name is a common Indian one."""
    accent = party.get("accent", "auto")
    if accent == "indian":
        return True
    return accent == "auto" and PS.is_indian_name(party.get("honoree"))


def _name_cue(party: dict, cue: str) -> str:
    """How a sentence with the guest of honour's name in it is said."""
    return "indian" if indian_voice(party) else cue


def _script(party: dict) -> dict:
    return PS.script_for(party.get("occasion"))


def _fill(text: str, party: dict) -> str:
    name = clean_text(party.get("honoree"))
    return text.format(name=name, possessive=possessive(name))


def welcome_script(party: dict) -> list[PS.Line]:
    """The opening: welcome, a joke, the guest of honour, a shout. [(text, cue)]."""
    style, script, name = _style(party), _script(party), clean_text(party.get("honoree"))
    out: list[PS.Line] = []
    welcome = random.choice(style["welcome"]).format(title=title_for(party))
    out.append((welcome, _name_cue(party, "welcome") if name else "welcome"))
    out.append((style["banter"], "playful"))
    for sentence in (script["intro"] if name else script["intro_noname"])[:1]:
        out.append((_fill(sentence, party), _name_cue(party, "welcome") if name else "welcome"))
    if not party.get("kids"):                   # a Kids night skips the teasing
        for sentence in script["rules"][:1]:
            out.append((sentence, "roast"))
    shouts = script["shouts"] if name and script["shouts"] else script["shouts_noname"]
    if shouts:
        for sentence in random.choice(shouts):
            has_name = "{name}" in sentence
            out.append((_fill(sentence, party), _name_cue(party, "cheer") if has_name else "cheer"))
    return out


def lineup_script(party: dict, playlist: list[str]) -> list[PS.Line]:
    """The lineup: how many games, a tease of the first and last, the rest by name."""
    style = _style(party)
    names = [_game_name(g) for g in playlist]
    if not names:
        return [(style["nogames"], "host")]
    out: list[PS.Line] = []
    if len(names) == 1:
        out.append((style["only"].format(game=names[0]), "playful"))
        out.append((PS.teaser(playlist[0]), "playful"))
    else:
        count = f"{PS.NUMBER_WORDS.get(len(names), str(len(names)))} games"
        out.append((style["intro"].format(count=count), "playful"))
        for i, (gid, game) in enumerate(zip(playlist, names)):
            key = "first" if i == 0 else "last" if i == len(names) - 1 else "then"
            out.append((style[key].format(game=game), "playful"))
            if key != "then":
                out.append((PS.teaser(gid), "playful"))
    out.append((style["outro"], "hype"))
    return out


def finale_script(party: dict, winner: str | None, points: int = 0) -> list[PS.Line]:
    style, script, name = _style(party), _script(party), clean_text(party.get("honoree"))
    out: list[PS.Line] = [(style["finale"], "finale")]
    if winner:
        out.append((style["champion_lead"], "hype"))
        out.append((style["champion"].format(winner=winner), "cheer"))
        out.append((style["champion_after"], "finale"))
        if party.get("kids"):
            out.append((KIDS_OTHERS, "kids"))
        else:
            out.append((style["others"], "roast"))
    else:
        out.append((style["nogames"], "finale"))
    toast = script["toast"] if name else script["toast_noname"]
    if toast:
        out.append((_fill(toast, party), _name_cue(party, "cheer") if "{name}" in toast else "cheer"))
    return out


def shout_script(party: dict) -> list[PS.Line]:
    """A cheer for the guest of honour, on demand (the host taps Shout)."""
    script, name = _script(party), clean_text(party.get("honoree"))
    shouts = script["shouts"] if name and script["shouts"] else script["shouts_noname"]
    if not shouts:
        return [("Everybody, make some noise!", "cheer")]
    out = []
    for sentence in random.choice(shouts):
        has_name = "{name}" in sentence
        out.append((_fill(sentence, party), _name_cue(party, "cheer") if has_name else "cheer"))
    return out


def welcome_lines(party: dict) -> list[str]:
    return [t for t, _ in welcome_script(party)]


def lineup_lines(party: dict, playlist: list[str]) -> list[str]:
    return [t for t, _ in lineup_script(party, playlist)]


def finale_lines(party: dict, winner: str | None, points: int) -> list[str]:
    return [t for t, _ in finale_script(party, winner, points)]


# ---------------------------------------------------------------------------
# every sentence a party can say, for the offline voice pack
# ---------------------------------------------------------------------------

def pack_lines(names=(), occasions=("birthday",)) -> list[PS.Line]:
    """Every sentence a party can say, as ``(text, cue)``, for
    tools/render_voice_pack.py: the fixed ones once, and the ones with a name in
    them for each of ``names`` (and each of ``occasions``). The app plays a
    sentence from the pack when it has it and says the rest live, so a name that
    is in this list is said in the pack's own voice, with no wait."""
    from games.game_night import CATALOG
    out: list[PS.Line] = []

    def add(text: str, cue: str) -> None:
        if text and text.strip():
            out.append((text.strip(), cue))

    for sid, style in STYLES.items():
        add(style["banter"], "playful")
        add(style["outro"], "hype")
        add(style["finale"], "finale")
        add(style["champion_lead"], "hype")
        add(style["champion_after"], "finale")
        add(style["others"], "roast")
        add(style["nogames"], "finale")
        for count in range(2, 11):
            add(style["intro"].format(count=f"{PS.NUMBER_WORDS[count]} games"), "playful")
        for gid in CATALOG:
            game = _game_name(gid)
            for key in ("first", "then", "last", "only"):
                add(style[key].format(game=game), "playful")
            add(PS.teaser(gid), "playful")
        # Without a guest of honour.
        for occasion in OCCASIONS_BY_ID:
            base = {"occasion": occasion, "style": sid, "honoree": ""}
            for template in style["welcome"]:
                add(template.format(title=title_for(base)), "welcome")
            script = PS.script_for(occasion)
            for sentence in script["intro_noname"]:
                add(sentence, "welcome")
            for shout in script["shouts_noname"]:
                for sentence in shout:
                    add(sentence, "cheer")
            add(script["toast_noname"], "cheer")
        # With one.
        for name in names:
            name = clean_text(name)
            if not name:
                continue
            for occasion in occasions:
                if occasion not in OCCASIONS_BY_ID:
                    continue
                base = {"occasion": occasion, "style": sid, "honoree": name}
                said = lambda cue: _name_cue(base, cue)        # noqa: E731
                for template in style["welcome"]:
                    add(template.format(title=title_for(base)), said("welcome"))
                script = PS.script_for(occasion)
                for sentence in script["intro"]:
                    add(_fill(sentence, base), said("welcome"))
                for shout in script["shouts"]:
                    for sentence in shout:
                        add(_fill(sentence, base), said("cheer") if "{name}" in sentence else "cheer")
                add(_fill(script["toast"], base), said("cheer"))
                add(style["champion"].format(winner=name), said("cheer"))
        for sentence in ("Hip hip!", "Hooray!"):
            add(sentence, "cheer")
    add(KIDS_OTHERS, "kids")
    for occasion, script in PS.SCRIPTS.items():
        for sentence in script["rules"]:
            add(sentence, "roast")
    seen, unique = set(), []
    for text, cue in out:
        if (text, cue) not in seen:
            seen.add((text, cue))
            unique.append((text, cue))
    return unique
