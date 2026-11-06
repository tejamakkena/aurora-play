"""How the host sounds: acting directions for the cloud voice.

``gpt-4o-mini-tts`` takes an ``instructions`` text next to the line it reads
("sound thrilled", "deadpan"). Without one it reads flat, like text on a page,
which is what the TV sounded like. Each *style* here is one direction; a line
asks for a style by name, and a Game Night host line asks by its *moment*
(``night_open``, ``answers_none``...), which ``for_moment`` maps to a style.

Names are an allow-list: the voice endpoint only accepts these, so a client
cannot send its own prompt to the paid voice.
"""

from __future__ import annotations

#: Heard by every line that names no style: a warm, quick game-show host.
DEFAULT = "host"

STYLES: dict[str, str] = {
    "host": (
        "You are the warm, quick-witted host of a family game night, speaking to a room "
        "of friends. Sound like a person, never like text being read: vary your pitch and "
        "pace, smile as you talk, stress the fun words, and pause naturally at commas. "
        "Keep it clear and easy to follow, at a brisk pace that never drags."
    ),
    "welcome": (
        "You are a thrilled game-show host opening the biggest night of the year. Big, "
        "bright, joyful energy, like greeting a crowd that just walked in. Rise on the "
        "exciting words, laugh a little, and make the guest of honour feel like a star. "
        "Never rushed, never shouting."
    ),
    "hype": (
        "An excited sports commentator calling a close finish. Fast, rising energy, "
        "stressing the key words, with a short breath of suspense before the big news."
    ),
    "playful": (
        "Delighted and teasing, like a host enjoying every moment: warm laughter in the "
        "voice, a cheeky smile, quick and light."
    ),
    "roast": (
        "Dry, deadpan and affectionate, like a talk-show host gently roasting a friend. "
        "Flat delivery with a tiny pause before the punchline, then a hint of a smirk. "
        "Brisk, never dragging. Never mean."
    ),
    "finale": (
        "A grand, warm closing. Slow down a touch, proud and celebratory, like announcing "
        "the champion at an awards night. Let the last words land."
    ),
    "kids": (
        "A cheerful, patient, upbeat presenter for children: bright, clear, a little "
        "slower, delighted by every answer."
    ),
    "narrator": (
        "A calm, dramatic storyteller narrating a game of secrets. Low and measured, "
        "suspenseful, with real pauses between sentences. Quiet menace for the dark "
        "moments, relief for the bright ones."
    ),
    "quiz": (
        "A confident, friendly quiz-show host reading a question clearly to a room. "
        "Upbeat, crisp and brisk, with a short pause before each answer option, and a "
        "small lift of curiosity on the question."
    ),
    "indian": (
        "Speak with a natural Indian English accent, warm and amused. Say any Hindi or "
        "Telugu word or song title the way a native speaker would, with its own "
        "rhythm and stress, never anglicised."
    ),
}

#: Eleven v4 and v3 read square-bracket audio tags as acting ("[laughs]", "[excited]")
#: and does not say them aloud. One short tag opens a line in these styles; the
#: rest rely on the voice itself. Kept to tags the model is known to follow.
ELEVEN_TAGS: dict[str, str] = {
    "welcome": "[excited]",
    "hype": "[excited]",
    "playful": "[giggles]",
    "roast": "[sarcastic]",
    "finale": "[excited]",
    "quiz": "[curious]",
}


def tagged(text: str, style: str | None) -> str:
    """``text`` with the style's audio tag in front (Eleven v4 and v3)."""
    tag = ELEVEN_TAGS.get(style or "", "")
    return f"{tag} {text}" if tag else text


#: Game Night host moments (games/show_host.py LINES keys) -> style.
MOMENTS: dict[str, str] = {
    "night_open": "welcome",
    "last_game": "hype",
    "answers_none": "roast",
    "answers_all": "playful",
    "answers_one": "roast",
    "answers_most_wrong": "roast",
    "answers_silence": "roast",
    "game_won": "playful",
    "game_tied": "hype",
    "lead_change": "hype",
    "lead_kept": "playful",
    "close_race": "hype",
    "runaway": "playful",
    "last_place": "roast",
    "night_close": "finale",
}


def canonical(name: str | None) -> str | None:
    """The style a name stands for: a style itself ("roast") or the style of a
    host moment ("answers_none" -> "roast"). None when the name is neither, so
    a line asking for nothing known is read in the default voice."""
    key = (name or "").strip().lower()
    if key in STYLES:
        return key
    if key in MOMENTS or key.startswith("intro_") or key.endswith("_kids"):
        return for_moment(key)
    return None


def for_moment(moment: str | None) -> str:
    """The style for a host moment; ``_kids`` variants and ``intro_*`` too."""
    key = (moment or "").strip()
    if key.endswith("_kids"):
        return "kids"
    if key.startswith("intro_"):
        return "welcome" if key == "intro_any" else "playful"
    return MOMENTS.get(key, DEFAULT)


def resolve(name: str | None) -> str | None:
    """A known style name or a host moment as the instruction text, else None."""
    key = (name or "").strip().lower()
    if not key:
        return None
    if key in STYLES:
        return STYLES[key]
    style = for_moment(key)
    return STYLES.get(style) if (key in MOMENTS or key.startswith("intro_") or key.endswith("_kids")) else None
