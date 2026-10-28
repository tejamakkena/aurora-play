"""Never Have I Ever statement packs.

Each statement completes the sentence "Never have I ever ..." so it is stored
without that prefix -- the board and the phones add it, and the TV reads the
whole sentence aloud.

Two packs are marked ``adult``: they cover nights out and dating, and are kept
tasteful (nothing explicit) but are not for a room with kids in it. They are
never part of the default "Surprise Mix" -- a host has to pick them on purpose,
and the picker labels them 18+.
"""

CLASSIC = [
    "pretended to be sick to skip school or work",
    "laughed so hard I cried at the wrong moment",
    "waved back at someone who wasn't waving at me",
    "sent a text to the wrong person",
    "fallen asleep in a movie theatre",
    "walked into a glass door",
    "eaten a whole pizza by myself",
    "forgotten someone's birthday",
    "sung in the shower like nobody could hear me",
    "pretended to know a song I had never heard",
    "stayed up all night binge-watching a series",
    "gotten lost while using GPS",
    "told a waiter \"you too\" when they said enjoy your meal",
    "laughed at a joke I didn't understand",
    "lied about my age",
    "talked to myself in public",
    "regifted a present",
    "cried during a cartoon",
    "googled myself",
    "used a fake name at a coffee shop",
    "locked myself out of my own house",
    "pretended my phone was ringing to escape a conversation",
    "slept through an alarm on an important day",
    "broken something and hidden the evidence",
    "had a nickname I wish I didn't",
    "read the last page of a book first",
    "eaten food that fell on the floor",
    "forgotten why I walked into a room, twice in a row",
]

FUNNY = [
    "tripped in front of a crowd and pretended it was on purpose",
    "accidentally called my teacher or boss \"mom\" or \"dad\"",
    "sent a screenshot to the person it was about",
    "liked a really old photo while checking someone's profile",
    "pretended to read a message so I wouldn't have to talk",
    "laughed at a very serious moment",
    "danced alone in the kitchen",
    "worn my clothes inside out all day",
    "eaten off someone else's plate without asking",
    "walked into the wrong restroom",
    "burped loudly in a very quiet room",
    "gotten the giggles during a presentation",
    "pretended to be on a call to avoid someone",
    "missed my stop because I fell asleep on the bus",
    "mispronounced a word for years",
    "faked a laugh at a joke I didn't get",
    "run for a bus and watched it leave anyway",
    "gotten my head stuck in something",
    "texted \"on my way\" while still in bed",
    "taken a hundred selfies to get one good one",
    "clapped when the plane landed",
    "bought something just because it was on sale and never used it",
    "pretended to love a gift I actually hated",
    "waved at a stranger thinking I knew them",
    "talked back to a GPS voice",
    "tried to push a door that said pull, in front of people",
]

PARTY = [
    "stayed out until sunrise",
    "danced on a table",
    "forgotten how I got home",
    "had a hangover that wrecked a whole day",
    "sung karaoke completely off-key and loved it",
    "snuck into a party I wasn't invited to",
    "left a party without saying goodbye",
    "been asked to leave a venue",
    "drunk-texted someone I shouldn't have",
    "lost my phone on a night out",
    "lost a shoe on a night out",
    "ordered food at 3 a.m. and eaten every bite",
    "pretended to be sober when I wasn't",
    "fallen asleep at a party",
    "done something silly because of a dare",
    "made a toast I don't remember",
    "turned up to a party in the wrong outfit",
    "made a best friend for a night and never saw them again",
    "cried at a party over nothing",
    "kept dancing after the music stopped",
    "told a secret I swore to keep after a few drinks",
    "hidden in the bathroom to escape a party",
    "raided the host's fridge in the middle of the night",
    "broken something at a party and blamed someone else",
    "called in sick the day after a big night",
    "danced with a total stranger",
]

AFTER_DARK = [
    "kissed someone on a first date",
    "sent a flirty text to the wrong person",
    "been caught staring at someone",
    "gone on a date just for the free dinner",
    "ghosted someone",
    "been ghosted and still checked their profile",
    "had a crush on a teacher or a boss",
    "stalked an ex online",
    "kept a photo or a gift from an ex",
    "pretended to love someone's cooking to impress them",
    "flirted my way out of trouble",
    "had a secret admirer",
    "slid into someone's DMs",
    "had a crush on someone in this room",
    "been on two dates in one day",
    "texted an ex at midnight",
    "been rejected in public",
    "faked a phone call to escape a bad date",
    "had a holiday fling",
    "said \"I love you\" first",
    "said \"I love you\" without meaning it",
    "borrowed a hoodie and never given it back",
    "been the third wheel on a date",
    "met someone online and then met them for real",
    "dressed up just to get someone's attention",
    "gone skinny-dipping",
    "had a crush on a friend's sibling",
    "written a love letter and never sent it",
]

WORK = [
    "talked for a full minute while on mute",
    "joined a meeting and realised my camera was on",
    "hit reply-all by mistake",
    "slept at my desk",
    "called in sick when I wasn't",
    "blamed the internet for a missed deadline",
    "pretended to read an email I never opened",
    "taken credit for someone else's idea",
    "cried at work or school",
    "worn pyjama bottoms on a video call",
    "copied someone's homework",
    "crammed for an exam the night before",
    "bunked a class",
    "fallen asleep in a lecture",
    "forgotten a colleague's name right after being introduced",
    "pretended to understand the jargon in a meeting",
    "eaten someone else's lunch from the office fridge",
    "had a secret nickname for my boss",
    "gotten lost in my own office building",
    "sent a message about someone to that very person",
    "stayed late just to look busy",
    "been caught playing a game during work or class",
    "invented an excuse to leave a meeting",
    "exaggerated something on my CV",
]

FOOD_TRAVEL = [
    "eaten something I couldn't identify",
    "missed a flight",
    "left my passport at home",
    "gotten food poisoning on holiday",
    "eaten ice cream for dinner",
    "dropped my phone in water",
    "packed my whole suitcase the morning of a trip",
    "gotten on the wrong train or bus",
    "shared a hotel room with a stranger",
    "eaten street food and regretted it",
    "slept in an airport",
    "gotten sunburnt so badly I looked like a tomato",
    "cooked something so badly it went straight in the bin",
    "set off the smoke alarm while cooking",
    "ordered the most expensive thing on the menu to impress someone",
    "walked out of a shop without paying by accident",
    "eaten dessert before dinner",
    "taken a hotel towel or toiletries home",
    "pretended to speak a language I don't",
    "been scammed while travelling",
    "eaten a whole cake alone",
    "burned toast so badly the whole house knew",
]

DESI = [
    "told my parents I was studying while watching videos",
    "hidden a bad report card from my family",
    "been compared to Sharma ji's kid",
    "eaten Maggi in the middle of the night",
    "pretended to understand the cricket score to fit in",
    "sent a \"Good Morning\" forward to a family WhatsApp group",
    "left a family WhatsApp group",
    "danced at a wedding without knowing the steps",
    "gone to a wedding just for the food",
    "stored something other than food in a steel dabba",
    "kept plastic bags inside a bag of plastic bags",
    "reused an ice-cream tub for leftovers",
    "mixed up the names of my parents' relatives",
    "worried about \"log kya kahenge\"",
    "watched the same Bollywood film three times in a week",
    "sung a Bollywood song badly in front of everyone",
    "lit a Diwali firecracker and ran away screaming",
    "fallen asleep during a long puja or ceremony",
    "hidden food I didn't like under the rice",
    "bargained for something that was already cheap",
    "waited more than twenty minutes in line for chai or pani puri",
    "watched a cricket match with the whole street",
    "sworn I'd never eat something and then asked for seconds",
    "fixed something with jugaad instead of buying the right part",
    "cried at a Karan Johar movie",
    "been asked \"when are you getting married?\" by an aunty at a function",
]

_PACKS = [
    {"id": "classic", "name": "Classic", "symbol": "face.smiling",
     "blurb": "Safe for the whole family", "adult": False, "statements": CLASSIC},
    {"id": "funny", "name": "Funny & Awkward", "symbol": "theatermasks.fill",
     "blurb": "Cringe moments we all share", "adult": False, "statements": FUNNY},
    {"id": "desi", "name": "Desi Edition", "symbol": "sparkles",
     "blurb": "Weddings, aunties and WhatsApp groups", "adult": False,
     "statements": DESI},
    {"id": "work", "name": "Work & School", "symbol": "briefcase.fill",
     "blurb": "Meetings, exams and office crimes", "adult": False,
     "statements": WORK},
    {"id": "foodtravel", "name": "Food & Travel", "symbol": "airplane",
     "blurb": "Kitchen disasters and trip fails", "adult": False,
     "statements": FOOD_TRAVEL},
    {"id": "party", "name": "Party Night", "symbol": "wineglass.fill",
     "blurb": "Late nights and questionable choices", "adult": True,
     "statements": PARTY},
    {"id": "afterdark", "name": "After Dark", "symbol": "moon.stars.fill",
     "blurb": "Dating, crushes and flirty confessions", "adult": True,
     "statements": AFTER_DARK},
]

#: "mix" is built from every non-adult pack, so a host who never opens the
#: picker still gets a safe, varied game.
_MIX_SOURCES = [p for p in _PACKS if not p["adult"]]
_MIX = {
    "id": "mix", "name": "Surprise Mix", "symbol": "shuffle",
    "blurb": "A bit of everything, family-friendly", "adult": False,
    "statements": [s for p in _MIX_SOURCES for s in p["statements"]],
}

#: Mix first -- it is the default and the safe choice.
PACKS = [_MIX] + _PACKS
PACKS_BY_ID = {p["id"]: p for p in PACKS}
PACK_IDS = frozenset(PACKS_BY_ID)
#: What the mix draws from, pack by pack, so each statement still comes from a
#: content-service kind and a table never hears one twice.
MIX_PACK_IDS = [p["id"] for p in _MIX_SOURCES]
DEFAULT_PACK = "mix"


def statements_for(pack_id: str) -> list[str]:
    """The statements in a pack. Unknown ids fall back to the default."""
    return list(PACKS_BY_ID.get(pack_id, PACKS_BY_ID[DEFAULT_PACK])["statements"])


def pack_info(pack_id: str) -> dict:
    """Display fields for one pack (no statements -- those stay server-side)."""
    pack = PACKS_BY_ID.get(pack_id, PACKS_BY_ID[DEFAULT_PACK])
    return {"id": pack["id"], "name": pack["name"], "symbol": pack["symbol"],
            "blurb": pack["blurb"], "adult": pack["adult"],
            "count": len(pack["statements"])}


def pack_options() -> list[dict]:
    return [pack_info(p["id"]) for p in PACKS]
