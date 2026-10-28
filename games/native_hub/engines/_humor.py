"""Humor packs: the banter between rounds.

Three kinds of line, per pack:

  guessed  a reaction when the team gets it ("Good job!" plus a joke)
  missed   a reaction when they don't (gentle ridicule, nothing cruel)
  filler   a standalone quip dropped between rounds, and between games in a
           Game Night

All original wording. A host picks a pack (or "mix", the default, which draws
from all of them); the TV reads the line aloud and the phones show it.
"""

import random

PACKS = {
    "desi": {
        "name": "Desi Masala", "symbol": "flame.fill",
        "blurb": "Aunty-approved Bollywood-style banter",
        "guessed": [
            "Shabash! Even the neighbours' aunty would be proud of that one.",
            "Good job! That was faster than a wedding video getting posted on the family group.",
            "Wah wah! Full marks, and a free samosa for the whole team.",
            "Good job! Somewhere a film director just asked you to audition.",
            "Brilliant! You guessed it quicker than Mummy finds out about a bad report card.",
            "Good job, team! Even the Wi-Fi is clapping.",
        ],
        "missed": [
            "Arre yaar! That one was sitting right in front of you like the last gulab jamun.",
            "Not guessed! Time to practise in the bathroom, where your singing is at its best.",
            "Oh no! Your family's playlist is crying quietly in the corner.",
            "Missed it! Don't worry, even the radio didn't know that one.",
            "Not this time! Sharma ji's team would have got it, just saying.",
            "Close... no, actually, not close at all. Moving on with love!",
        ],
        "filler": [
            "Fun fact: every Bollywood hero has run through a field of flowers at least once.",
            "Reminder: if the song has rain in it, someone is definitely wearing white.",
            "Somewhere right now, a hero is changing outfits mid-song for no reason.",
            "Rule of Bollywood: the villain can only be defeated after a long dance number.",
            "Quick tip: if you forget the lyrics, just say 'la la la' with confidence.",
            "Every wedding playlist is just six songs on repeat. You know them all.",
        ],
    },
    "dad": {
        "name": "Dad Jokes", "symbol": "face.smiling",
        "blurb": "Clean, groan-worthy puns",
        "guessed": [
            "Good job! You really hit the right note. I'm sorry. I'm not sorry.",
            "Nailed it! That answer was music to my ears.",
            "Correct! You're on a roll, and not the dinner kind.",
            "Good job! That deserves a round of a-pause. Get it? Applause?",
            "Great guess! Your team is singing from the same hymn sheet.",
            "Bravo! That was no flat answer.",
        ],
        "missed": [
            "Not guessed! Don't worry, that one was a bit off-key.",
            "Swing and a miss! You can't win them all, that's just the way the cookie crumbles.",
            "Nope! The answer is a treble you didn't see coming.",
            "Not this time. That's the way the metronome ticks.",
            "Missed it! Don't be blue, it was a tough one.",
            "No luck! Let's not make a song and dance about it.",
        ],
        "filler": [
            "Why did the singer bring a ladder? To reach the high notes.",
            "What do you call a musician with problems? A trebled soul.",
            "Why can't you trust a stairway to heaven? It always leads you on.",
            "I told my phone a joke about its battery. It didn't get it, it was low-key.",
            "Why did the radio break up with the TV? It wanted more space between the channels.",
            "What's a pirate's favourite song? Anything with a lot of 'arrrr' and B.",
        ],
    },
    "savage": {
        "name": "Savage Roast", "symbol": "bolt.fill",
        "blurb": "Friendly roasting. Thick skin required.",
        "guessed": [
            "Good job! Please enjoy this rare moment of you being right.",
            "Correct! Mark the date, it won't happen again.",
            "Wow, a correct answer. Somebody call the newspapers.",
            "Good job! I'd say that was luck, but I'm in a generous mood.",
            "Right answer! Did anyone check that team for cheat codes?",
            "Good job! Your team has finally earned its snacks.",
        ],
        "missed": [
            "Not guessed! That answer was so wrong it made the speaker wince.",
            "Wrong! I've heard cats on a fence that sounded smarter.",
            "Nope. Your confidence was impressive, your accuracy less so.",
            "Not guessed! Your team has the musical instincts of a doorbell.",
            "Missed! Maybe stick to humming in the shower where nobody keeps score.",
            "Oof. The correct answer is crying somewhere.",
        ],
        "filler": [
            "Reminder: confidence is not the same as being right. Keep going though.",
            "Somebody in this room sings louder than they know the lyrics. We see you.",
            "Fun fact: the best singer here is the one who's currently not singing.",
            "Plot twist: nobody really knows the second verse of anything.",
            "Your playlist says a lot about you. It says 'please stop'.",
            "Quick note: dancing is not a substitute for knowing the answer. But we respect it.",
        ],
    },
}

#: Draws from every pack, so a host who never opens the picker still gets variety.
MIX = "mix"
DEFAULT_PACK = MIX
PACK_IDS = frozenset(list(PACKS) + [MIX])


def _resolve(pack_id: str) -> dict:
    if pack_id in PACKS:
        return PACKS[pack_id]
    return PACKS[random.choice(list(PACKS))]


def reaction(pack_id: str, result: str) -> str:
    """The line after a verdict. ``result`` is "guessed" or "missed"."""
    key = "guessed" if result == "guessed" else "missed"
    return random.choice(_resolve(pack_id)[key])


def filler(pack_id: str) -> str:
    return random.choice(_resolve(pack_id)["filler"])


def pack_options() -> list[dict]:
    """For the host's setup screen. "mix" is listed first, as the default."""
    options = [{"id": MIX, "name": "Surprise Mix", "symbol": "shuffle",
                "blurb": "A bit of every style"}]
    options += [{"id": pid, "name": p["name"], "symbol": p["symbol"], "blurb": p["blurb"]}
                for pid, p in PACKS.items()]
    return options
