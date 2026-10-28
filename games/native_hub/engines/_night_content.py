"""Static content and pure helpers for Game Night.

Everything the host can choose from lives here -- occasions, voice packs, the
games that can be queued -- along with the config validator and the spoken
scripts. None of it touches a room or a socket, so it is unit-testable alone.

On "voice packs": the TV speaks these lines with the system speech synthesiser,
using the pack's language/rate/pitch. The *words* are scripted here (so names
and game titles can be dropped in); a pack is a voice plus a way of talking.
Swapping in recorded clips later only changes what the TV does with a line.
"""

import random
from typing import Any

from games.native_hub.engines import _nhie_packs as P

# ---- Occasions -----------------------------------------------------------------
# ``title`` / ``cheer`` use {possessive} ("Venkat's") and {name}; the *_noname
# variants are used when the host leaves the name blank.
OCCASIONS = [
    {"id": "birthday", "label": "Birthday Party", "emoji": "🎂",
     "nameLabel": "Birthday person", "needsName": True,
     "title": "{possessive} Birthday Party", "title_noname": "Birthday Party",
     "cheer": "Happy birthday, {name}!", "cheer_noname": "Happy birthday!"},
    {"id": "anniversary", "label": "Anniversary", "emoji": "💞",
     "nameLabel": "Celebrating", "needsName": True,
     "title": "{possessive} Anniversary Party", "title_noname": "Anniversary Party",
     "cheer": "Happy anniversary, {name}!", "cheer_noname": "Happy anniversary!"},
    {"id": "housewarming", "label": "Housewarming", "emoji": "🏡",
     "nameLabel": "Home of", "needsName": True,
     "title": "{possessive} Housewarming", "title_noname": "Housewarming Party",
     "cheer": "Congratulations on the new home, {name}!",
     "cheer_noname": "Congratulations on the new home!"},
    {"id": "festival", "label": "Festival Party", "emoji": "🪔",
     "nameLabel": "Festival (Diwali, Holi, Eid...)", "needsName": True,
     "title": "{name} Party", "title_noname": "Festival Party",
     "cheer": "Happy {name}!", "cheer_noname": "Happy festival!"},
    {"id": "newyear", "label": "New Year's Eve", "emoji": "🎆",
     "nameLabel": "", "needsName": False,
     "title": "New Year's Eve Party", "title_noname": "New Year's Eve Party",
     "cheer": "Happy New Year!", "cheer_noname": "Happy New Year!"},
    {"id": "gathering", "label": "Get-Together", "emoji": "🎉",
     "nameLabel": "Hosted by (optional)", "needsName": False,
     "title": "{possessive} Game Night", "title_noname": "Game Night",
     "cheer": "Let the games begin!", "cheer_noname": "Let the games begin!"},
]
OCCASIONS_BY_ID = {o["id"]: o for o in OCCASIONS}
DEFAULT_OCCASION = "gathering"

MAX_HONOREE_LEN = 30

# ---- Games that can be queued --------------------------------------------------
# A curated set: group games with a clear ending, whose TV boards are plain
# SwiftUI. Player bounds are read from the engines at runtime, not copied here.
CATALOG = [
    {"id": "never_have_i_ever", "name": "Never Have I Ever", "emoji": "🙋",
     "blurb": "Confess to the things you've done. Packs from family-safe to spicy."},
    {"id": "herd", "name": "Herd", "emoji": "🐑",
     "blurb": "Think like the crowd. Match the majority to score."},
    {"id": "bluff_it", "name": "Bluff It", "emoji": "🎭",
     "blurb": "Write a convincing lie, then spot the truth."},
    {"id": "trivia", "name": "Trivia", "emoji": "🧠",
     "blurb": "Fast questions. Quick fingers win."},
    {"id": "emoji_movie", "name": "Emoji Movie", "emoji": "🎬",
     "blurb": "Describe a movie in emoji and see who gets it."},
    {"id": "npat", "name": "Name Place Animal Thing", "emoji": "🅰️",
     "blurb": "One letter, four categories, race the clock."},
    {"id": "antakshari", "name": "Antakshari", "emoji": "🎵",
     "blurb": "Sing a song that starts with the last letter."},
    {"id": "last_tap", "name": "Last Tap Standing", "emoji": "⚡",
     "blurb": "Tap when it turns green. Too early and you're out."},
    {"id": "mind_meld", "name": "Mind Meld", "emoji": "🔮",
     "blurb": "Say the same word at the same time."},
    {"id": "wavelength", "name": "Wavelength", "emoji": "📡",
     "blurb": "Read the clue and find the hidden spot on the dial."},
    {"id": "bollywood_charades", "name": "Bollywood Charades", "emoji": "💃",
     "blurb": "Act it out and guess the film."},
    {"id": "odd_one_out", "name": "Odd One Out", "emoji": "🕶️",
     "blurb": "Everyone knows the place except the spy."},
    {"id": "hot_grid", "name": "Hot Grid", "emoji": "💣",
     "blurb": "Pick tiles and don't hit the bomb."},
]
CATALOG_BY_ID = {g["id"]: g for g in CATALOG}
DEFAULT_GAMES = ["never_have_i_ever", "herd", "trivia"]
MAX_PLAYLIST = 12

DEFAULT_NHIE_ROUNDS = 10
NHIE_ROUND_CHOICES = (5, 10, 15, 20)

# ---- Voice packs ----------------------------------------------------------------
# Every key maps to a list of interchangeable variants; one is picked per use.
VOICE_PACKS = {
    "party_host": {
        "name": "Party Host", "emoji": "🎉", "blurb": "Upbeat and full of energy",
        "voice": {"language": "en-US", "rate": 0.52, "pitch": 1.15},
        "lines": {
            "welcome": ["Welcome to {title}!", "Hello, hello! Welcome to {title}!"],
            "lineup_intro": ["Tonight we're playing {count} {games_word}."],
            "lineup_first": ["We're kicking things off with {game}."],
            "lineup_then": ["Then, {game}."],
            "lineup_last": ["And we're finishing with {game}."],
            "lineup_only": ["Tonight it's all about {game}."],
            "lineup_outro": ["Let's get this party started!"],
            "intro_first": ["Let's kick things off with {game}! {blurb}"],
            "intro": ["Up next, {game}! {blurb}"],
            "interlude_winner": ["{winner} takes {game}!"],
            "interlude_none": ["And that's {game} done!"],
            "interlude_leader": ["{leader} leads the night with {points} points."],
            "interlude_skipped": ["Okay, moving on!"],
            "skipped": ["We need a different number of players for {game}, so we're skipping it."],
            "finale_intro": ["That's a wrap on {title}!"],
            "finale_winner": ["Tonight's champion is {winner}, with {points} points!"],
            "finale_nogames": ["We didn't get to play tonight, but that's okay."],
            "sample": ["Hi! I'm your host for tonight. Let's have some fun!"],
        },
    },
    "game_show": {
        "name": "Game Show", "emoji": "🎤", "blurb": "Big announcer energy",
        "voice": {"language": "en-US", "rate": 0.46, "pitch": 0.82},
        "lines": {
            "welcome": ["Ladies and gentlemen... welcome to {title}!"],
            "lineup_intro": ["Tonight's lineup features {count} spectacular {games_word}."],
            "lineup_first": ["First, the one and only {game}!"],
            "lineup_then": ["Followed by {game}!"],
            "lineup_last": ["And the grand finale... {game}!"],
            "lineup_only": ["Tonight's main event: {game}!"],
            "lineup_outro": ["Let the games begin!"],
            "intro_first": ["Our first contest! {game}! {blurb}"],
            "intro": ["Next contest! {game}! {blurb}"],
            "interlude_winner": ["And the winner of {game} is... {winner}!"],
            "interlude_none": ["That's the end of {game}!"],
            "interlude_leader": ["{leader} is out in front tonight with {points} points!"],
            "interlude_skipped": ["Moving swiftly on, folks!"],
            "skipped": ["We can't run {game} with this crowd, so it's off the list."],
            "finale_intro": ["That concludes {title}!"],
            "finale_winner": ["Tonight's grand champion... {winner}, with {points} points!"],
            "finale_nogames": ["No contests tonight, folks. Better luck next time!"],
            "sample": ["Testing, testing. This is your host for tonight!"],
        },
    },
    "desi_dost": {
        "name": "Desi Dost", "emoji": "🪔", "blurb": "A warm, friendly Indian-English host",
        "voice": {"language": "en-IN", "rate": 0.5, "pitch": 1.05},
        "lines": {
            "welcome": ["Namaste, everyone! Welcome to {title}!"],
            "lineup_intro": ["Today we have {count} {games_word} for you."],
            "lineup_first": ["First, we will play {game}."],
            "lineup_then": ["After that, {game}."],
            "lineup_last": ["And finally, {game}."],
            "lineup_only": ["Today, we will play {game}."],
            "lineup_outro": ["So, shall we begin?"],
            "intro_first": ["Let us start with {game}! {blurb}"],
            "intro": ["Next is {game}! {blurb}"],
            "interlude_winner": ["Wah! {winner} has won {game}!"],
            "interlude_none": ["Very good! {game} is finished."],
            "interlude_leader": ["{leader} is leading with {points} points."],
            "interlude_skipped": ["No problem, let us move on."],
            "skipped": ["We cannot play {game} with this many people, so we will skip it."],
            "finale_intro": ["And that is the end of {title}!"],
            "finale_winner": ["Congratulations to {winner}, the champion, with {points} points!"],
            "finale_nogames": ["We could not play today, but we had a lovely time."],
            "sample": ["Namaste! I am your host for tonight. Let us have some fun!"],
        },
    },
    "chill": {
        "name": "Chill", "emoji": "😎", "blurb": "Relaxed and easygoing",
        "voice": {"language": "en-GB", "rate": 0.44, "pitch": 0.95},
        "lines": {
            "welcome": ["Hey everyone, welcome to {title}."],
            "lineup_intro": ["Here's what we've got tonight: {count} {games_word}."],
            "lineup_first": ["We'll start with {game}."],
            "lineup_then": ["Then {game}."],
            "lineup_last": ["And we'll wrap up with {game}."],
            "lineup_only": ["Tonight we're playing {game}."],
            "lineup_outro": ["Grab a drink and get comfortable."],
            "intro_first": ["First up, {game}. {blurb}"],
            "intro": ["Next, {game}. {blurb}"],
            "interlude_winner": ["Nicely done, {winner}. You took {game}."],
            "interlude_none": ["That's {game} done."],
            "interlude_leader": ["{leader} is ahead with {points} points."],
            "interlude_skipped": ["No worries, onwards."],
            "skipped": ["We don't have the right number of people for {game}, so we'll skip it."],
            "finale_intro": ["And that's {title}."],
            "finale_winner": ["Tonight's champion is {winner}, with {points} points."],
            "finale_nogames": ["We didn't play anything tonight. That's fine."],
            "sample": ["Hey. I'm your host for tonight. Nice and easy."],
        },
    },
}
DEFAULT_VOICE_PACK = "party_host"

# ---- Timing ---------------------------------------------------------------------
# Seconds a screen stays up at minimum, even if the TV finishes speaking sooner
# (or cannot speak at all), so people can read it.
MIN_HOLD = {"welcome": 5, "lineup": 6, "intro": 5, "interlude": 9, "finale": 8}
# Estimated speech speed used for the fallback deadline when the TV never
# reports back: a deliberately slow characters-per-second plus a margin.
SPEECH_CHARS_PER_SECOND = 9.0
SPEECH_MARGIN_SECONDS = 4.0
LINE_PAUSE_SECONDS = 0.6

# ---- Night scoring ----------------------------------------------------------------
# Points per finishing position in each hosted game. Everyone who played earns
# something, so a bad game never knocks anybody out of the night.
RANK_POINTS = {1: 10, 2: 7, 3: 5}
PARTICIPATION_POINTS = 2


# ---- Config ---------------------------------------------------------------------

def default_config() -> dict:
    return {
        "occasion": DEFAULT_OCCASION,
        "honoree": "",
        "voicePack": DEFAULT_VOICE_PACK,
        "games": list(DEFAULT_GAMES),
        "nhiePack": P.DEFAULT_PACK,
        "nhieRounds": DEFAULT_NHIE_ROUNDS,
    }


def clean_text(value: Any, limit: int = MAX_HONOREE_LEN) -> str:
    """Collapse whitespace, drop control characters, cap the length."""
    if not isinstance(value, str):
        return ""
    cleaned = " ".join(value.split())
    cleaned = "".join(ch for ch in cleaned if ch.isprintable())
    return cleaned[:limit].strip()


def clean_config(raw: Any, base: dict | None = None) -> dict:
    """Merge a client-supplied config over ``base``, keeping only valid values.

    The client is untrusted, so every field is checked individually and an
    invalid one simply keeps its previous value instead of failing the request.
    """
    cfg = dict(base) if base else default_config()
    if not isinstance(raw, dict):
        return cfg

    occasion = raw.get("occasion")
    if isinstance(occasion, str) and occasion in OCCASIONS_BY_ID:
        cfg["occasion"] = occasion

    if "honoree" in raw:
        cfg["honoree"] = clean_text(raw.get("honoree"))

    voice = raw.get("voicePack")
    if isinstance(voice, str) and voice in VOICE_PACKS:
        cfg["voicePack"] = voice

    games = raw.get("games")
    if isinstance(games, list):
        seen: list[str] = []
        for gid in games:
            if isinstance(gid, str) and gid in CATALOG_BY_ID and gid not in seen:
                seen.append(gid)
        cfg["games"] = seen[:MAX_PLAYLIST]

    pack = raw.get("nhiePack")
    if isinstance(pack, str) and pack in P.PACK_IDS:
        cfg["nhiePack"] = pack

    rounds = raw.get("nhieRounds")
    # bool is an int subclass; True must not become "1 round".
    if isinstance(rounds, int) and not isinstance(rounds, bool) and rounds in NHIE_ROUND_CHOICES:
        cfg["nhieRounds"] = rounds

    return cfg


# ---- Wording --------------------------------------------------------------------

def possessive(name: str) -> str:
    if not name:
        return ""
    return f"{name}'" if name.lower().endswith("s") else f"{name}'s"


def occasion_for(cfg: dict) -> dict:
    return OCCASIONS_BY_ID.get(cfg.get("occasion"), OCCASIONS_BY_ID[DEFAULT_OCCASION])


def title_for(cfg: dict) -> str:
    occasion = occasion_for(cfg)
    name = clean_text(cfg.get("honoree"))
    if name:
        return occasion["title"].format(name=name, possessive=possessive(name))
    return occasion["title_noname"]


def cheer_for(cfg: dict) -> str:
    occasion = occasion_for(cfg)
    name = clean_text(cfg.get("honoree"))
    return occasion["cheer"].format(name=name) if name else occasion["cheer_noname"]


def pack_for(cfg: dict) -> dict:
    return VOICE_PACKS.get(cfg.get("voicePack"), VOICE_PACKS[DEFAULT_VOICE_PACK])


def say(cfg: dict, key: str, **fmt: Any) -> str:
    """One scripted line from the config's voice pack, with values dropped in."""
    variants = pack_for(cfg)["lines"][key]
    return random.choice(variants).format(**fmt)


def speech_seconds(lines: list[str]) -> float:
    """A generous estimate of how long the TV needs to read these aloud."""
    chars = sum(len(line) for line in lines)
    return SPEECH_MARGIN_SECONDS + chars / SPEECH_CHARS_PER_SECOND + LINE_PAUSE_SECONDS * len(lines)


def welcome_lines(cfg: dict) -> list[str]:
    lines = [say(cfg, "welcome", title=title_for(cfg))]
    cheer = cheer_for(cfg)
    # The generic get-together cheer would just repeat the welcome.
    if cfg.get("occasion") != "gathering":
        lines.append(cheer)
    return lines


def lineup_lines(cfg: dict, games: list[dict]) -> list[str]:
    """``games`` are catalog entries in play order."""
    if not games:
        return [say(cfg, "finale_nogames")]
    if len(games) == 1:
        return [say(cfg, "lineup_only", game=games[0]["name"]),
                say(cfg, "lineup_outro")]
    lines = [say(cfg, "lineup_intro", count=len(games),
                 games_word="games")]
    for i, game in enumerate(games):
        if i == 0:
            key = "lineup_first"
        elif i == len(games) - 1:
            key = "lineup_last"
        else:
            key = "lineup_then"
        lines.append(say(cfg, key, game=game["name"]))
    lines.append(say(cfg, "lineup_outro"))
    return lines


def intro_lines(cfg: dict, game: dict, first: bool, notes: list[str]) -> list[str]:
    key = "intro_first" if first else "intro"
    return notes + [say(cfg, key, game=game["name"], blurb=game["blurb"])]


def interlude_lines(cfg: dict, game: dict, winner: str | None,
                    leader: str | None, points: int, skipped: bool) -> list[str]:
    if skipped:
        return [say(cfg, "interlude_skipped")]
    lines = [say(cfg, "interlude_winner", game=game["name"], winner=winner)
             if winner else say(cfg, "interlude_none", game=game["name"])]
    if leader:
        lines.append(say(cfg, "interlude_leader", leader=leader, points=points))
    return lines


def finale_lines(cfg: dict, winner: str | None, points: int,
                 notes: list[str]) -> list[str]:
    lines = notes + [say(cfg, "finale_intro", title=title_for(cfg))]
    if winner:
        lines.append(say(cfg, "finale_winner", winner=winner, points=points))
    else:
        lines.append(say(cfg, "finale_nogames"))
    if cfg.get("occasion") != "gathering":
        lines.append(cheer_for(cfg))
    return lines


# ---- Options sent to the host's setup screen -----------------------------------------

def occasion_options() -> list[dict]:
    return [{"id": o["id"], "label": o["label"], "emoji": o["emoji"],
             "nameLabel": o["nameLabel"], "needsName": o["needsName"]}
            for o in OCCASIONS]


def voice_pack_options() -> list[dict]:
    return [{"id": pid, "name": p["name"], "emoji": p["emoji"], "blurb": p["blurb"]}
            for pid, p in VOICE_PACKS.items()]


def voice_params(cfg: dict) -> dict:
    return dict(pack_for(cfg)["voice"])
