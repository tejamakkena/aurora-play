"""What the TV host says at a party, written to be performed rather than read.

A party night (games/night_party.py) opens with a welcome, shouts for the guest
of honour, a lineup that teases each game, and a finale. This module holds the
words. Three rules shape them:

  * Short sentences. The voice pack and the TV speak one sentence at a time, so
    every sentence is either FIXED (no name in it, rendered once into the
    offline pack) or a NAME sentence (the guest of honour or the champion and
    nothing else dynamic), which tools/render_voice_pack.py can render for a
    list of names ahead of the party.
  * Every line has a *cue*: how it is said (games/voice_styles.py), so a shout
    is shouted and a roast is deadpan.
  * Humour is warm: the host teases the room, never one person for real.

All text is emoji-free: it is shown on screen and read aloud.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# a line the host says: text + how
# ---------------------------------------------------------------------------

Line = tuple[str, str]          # (text, cue)

NUMBER_WORDS = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six",
                7: "seven", 8: "eight", 9: "nine", 10: "ten"}

# ---------------------------------------------------------------------------
# a teaser for each game: said when the game comes up, and in the lineup
# ---------------------------------------------------------------------------

TEASERS: dict[str, str] = {
    "trivia": "A quiz where confidence counts almost as much as the answer, and that is bad news for some of you.",
    "brain_battle": "Puzzles against the clock. Calculators are not allowed, and neither is crying.",
    "most_likely_to": "You find out who in this room is most likely to do the thing, and your friends are not shy about it.",
    "truth_or_dare": "Truths, dares, and absolutely no take backs.",
    "would_rather": "Two terrible choices, and you have to pick one in front of everyone.",
    "host_lies": "I read out facts, and sometimes I lie. Catching me is your job. Fooling you is my hobby.",
    "herd": "The winning move is to think exactly like everybody else. Originality gets punished tonight.",
    "never_have_i_ever": "Confessions with a score attached. Your secrets have a very short shelf life in this room.",
    "guess_the_song": "I hum, you guess. Singing out of tune is not just allowed, it is encouraged.",
    "bluff_it": "Lie convincingly, spot the truth, and then pretend you never lied to your best friend.",
    "emoji_movie": "Guess the film from a few tiny pictures. Easier than it sounds, harder than it looks.",
    "npat": "Name, place, animal, thing. One letter, a few seconds, and total panic.",
    "antakshari": "A song battle, last letter to first letter. Aunties and uncles, this is your moment.",
    "atlas": "Name a place that starts with the last letter. Somewhere, a geography teacher is smiling.",
    "bollywood_charades": "Act out the film without a word. The overacting is the entire point.",
    "speed_sculptor": "Draw it fast, draw it badly, and somehow everybody still understands.",
    "mind_meld": "Two minds, one word. Tonight we find out who really knows who.",
    "wavelength": "Read the mind of the psychic. Spoiler: it is mostly guessing.",
    "odd_one_out": "One of you has no idea what is going on. Try to look confident.",
    "cipher_grid": "Teams, secret words, and clues that only make sense to you. Arguments are expected.",
    "sealed_auction": "Secret bids and bad decisions. May the biggest ego win.",
    "last_tap": "Be the last one standing. Thumbs ready, mercy not included.",
    "tambola": "Numbers get called, tickets get marked, and one lucky person screams housie.",
    "connect4": "Four in a row. Simple rules, shocking amounts of trash talk.",
    "ludo": "The game that has ended more friendships than any other. Dice ready.",
    "snake_ladder": "Pure luck and pure drama. Ladders get cheered. Snakes get laughed at.",
    "battleship": "Hide your fleet, sink theirs, and say miss with dignity.",
    "heist": "Plan the perfect robbery. Nobody asks what you were doing at the bank.",
    "heist_escape": "Escape the vault together. Teamwork, or one very loud argument.",
    "defuse": "One bomb, many opinions. Everybody stay very calm.",
    "raja_mantri": "Raja, Rani, Mantri, Chor. Someone has to be the thief, and it might be you.",
    "mafia": "Lies, accusations and dramatic exits. Close your eyes, and trust no one.",
    "poker": "Keep a straight face. Everyone here already knows yours is terrible.",
    "teen_patti": "Three cards, big bluffs, and a lot of playing blind. Auntie rules apply.",
    "hot_takes": "Two sides, one debate. Defend an opinion you might not even believe.",
    "twenty_questions": "Twenty questions to crack the secret. Think like a detective, ask like a child.",
}
#: For a game with no teaser of its own.
TEASER_FALLBACK = "A classic, and it never goes out of style."


def teaser(game_id: str | None) -> str:
    return TEASERS.get(game_id or "", TEASER_FALLBACK)


# ---------------------------------------------------------------------------
# the guest of honour, by occasion
# ---------------------------------------------------------------------------
#
# ``star``     what the host calls them when there is no name.
# ``intro``    NAME sentences, said right after the welcome. {name}
# ``intro_noname``  the same without a name (FIXED).
# ``rules``    FIXED jokes about being the guest of honour.
# ``shouts``   NAME shouts, each a list of sentences, the last one the cheer.
# ``shouts_noname``  FIXED shouts.
# ``toast``    NAME sentence for the end of the night.
# ``toast_noname``   FIXED.

SCRIPTS: dict[str, dict] = {
    "birthday": {
        "star": "the birthday star",
        "intro": [
            "Tonight belongs to one person, and that person is {name}!",
            "Everybody, look at {name}. That is what a legend looks like!",
        ],
        "intro_noname": [
            "Tonight belongs to one person, and you know exactly who you are!",
        ],
        "rules": [
            "Quick rules for the birthday star: you pick the music, you get the first slice of cake, and when you lose, we all agree it was a tactical decision.",
            "A few facts about tonight. The birthday star is always right, always wins, and never has to wash up.",
        ],
        "shouts": [
            ["Everybody, on three!", "One, two, three!", "Happy birthday, {name}!"],
            ["Make some noise for {name}!", "{name}! {name}! {name}!", "Happy birthday, {name}!"],
            ["Hip hip!", "Hooray!", "Hip hip!", "Hooray!", "Happy birthday, {name}!"],
        ],
        "shouts_noname": [
            ["Everybody, on three!", "One, two, three!", "Happy birthday!"],
            ["Hip hip!", "Hooray!", "Hip hip!", "Hooray!", "Happy birthday!"],
        ],
        "toast": "And one more time for the star of the night, happy birthday, {name}!",
        "toast_noname": "And one more time for the star of the night, happy birthday!",
    },
    "anniversary": {
        "star": "the happy couple",
        "intro": [
            "Tonight we celebrate {name}, and a love story that survived every board game!",
        ],
        "intro_noname": [
            "Tonight we celebrate a love story that has survived every board game!",
        ],
        "rules": [
            "A rule for the happy couple: you may play on the same team, but you may not fight about the score. Much.",
        ],
        "shouts": [
            ["Everybody, raise a glass!", "Here is to {name}!", "Happy anniversary, {name}!"],
        ],
        "shouts_noname": [
            ["Everybody, raise a glass!", "Happy anniversary!"],
        ],
        "toast": "One more cheer for {name}, happy anniversary!",
        "toast_noname": "One more cheer for the happy couple, happy anniversary!",
    },
    "housewarming": {
        "star": "the host",
        "intro": [
            "Tonight we warm up the home of {name}!",
        ],
        "intro_noname": [
            "Tonight we warm up a brand new home!",
        ],
        "rules": [
            "House rules, as decided by the host: shoes off, snacks out, and nobody touches the good sofa.",
        ],
        "shouts": [
            ["Everybody, on three!", "One, two, three!", "Congratulations on the new home, {name}!"],
        ],
        "shouts_noname": [
            ["Everybody, on three!", "One, two, three!", "Congratulations on the new home!"],
        ],
        "toast": "One more cheer for {name}, and the new home!",
        "toast_noname": "One more cheer for the new home!",
    },
    "festival": {
        "star": "everyone",
        "intro": [
            "Tonight we celebrate {name} with friends, food and friendly competition!",
        ],
        "intro_noname": [
            "Tonight we celebrate with friends, food and friendly competition!",
        ],
        "rules": [
            "A festival rule: second helpings are mandatory, and the sweets do not count as cheating.",
        ],
        "shouts": [
            ["Everybody, on three!", "One, two, three!", "Happy {name}!"],
        ],
        "shouts_noname": [
            ["Everybody, on three!", "One, two, three!", "Happy festival!"],
        ],
        "toast": "One more time, happy {name}, everybody!",
        "toast_noname": "One more time, happy festival, everybody!",
    },
    "newyear": {
        "star": "everyone",
        "intro": [],
        "intro_noname": [
            "Tonight we say goodbye to the old year, and hello to new excuses for losing!",
        ],
        "rules": [
            "A new year rule: whoever loses makes a resolution, and has to say it out loud.",
        ],
        "shouts": [],
        "shouts_noname": [
            ["Everybody, count it down!", "Three, two, one!", "Happy New Year!"],
        ],
        "toast": "",
        "toast_noname": "One more time, happy New Year, everybody!",
    },
    "gathering": {
        "star": "the host",
        "intro": [
            "Tonight we are in the home of {name}, so please be nice to the furniture!",
        ],
        "intro_noname": [
            "Tonight is about good company, snacks, and a little healthy rivalry!",
        ],
        "rules": [
            "One rule for tonight: it is only a game. Unless you are winning. Then it is everything.",
        ],
        "shouts": [
            ["Everybody, on three!", "One, two, three!", "Thank you for hosting, {name}!"],
        ],
        "shouts_noname": [
            ["Everybody, on three!", "One, two, three!", "Let the games begin!"],
        ],
        "toast": "One more cheer for {name}, our wonderful host!",
        "toast_noname": "One more cheer for our wonderful host!",
    },
}


def script_for(occasion: str | None) -> dict:
    return SCRIPTS.get(occasion or "", SCRIPTS["gathering"])


# ---------------------------------------------------------------------------
# names that need the Indian voice
# ---------------------------------------------------------------------------

#: Common Indian first names (lower case). A guest of honour on this list is
#: spoken in the Indian voice by default; the host can force it either way.
INDIAN_NAMES = frozenset("""
aarav aarti aanya aaditya abhay abhinav abhishek aditi aditya advik ajay ajit akash akhil akshay alok amar amit amita
amrita ananya anil anirudh anita anjali ankit ankita anu anupama anushka anvi arjun arnav aryan asha ashok ashwin
avani ayaan bhavya chandra charan deepa deepak deepika devi dhruv diya divya farah gauri geeta girish gita gopal
govind hari harish harsh harsha hema hemant indira isha ishaan jaya jayesh jyoti kabir kajal kalyan kamal kamala
karan kartik kavita keerthi kiran kishore kishan krishna kumar lakshmi lalitha lata madhavi mahesh manish manoj
meena meera mohan mukesh murali nandini naveen neha neelam nikhil nikita nisha pooja prabhu pradeep prakash pranav
prasad pratik priya priyanka rahul raj rajesh rajiv raju rakesh ram rama ramesh ranjit rashmi ravi rekha riya rohan
rohit roshni sachin sagar sai sakshi samir sandeep sandhya sanjay sanjana sara sarita satish saurabh shanti sharad
shilpa shiva shreya shruti shyam siddharth sita smita sneha sonia srinivas subhash sudha sudhir suhas sunil sunita
suresh surya sushma swati tara teja tejaswi uday uma usha vamsi varun vedant venkat venkatesh vidya vijay vijaya vikas
vikram vinay vineet vishal vivek yash yamini yogesh
""".split())


def is_indian_name(name: str | None) -> bool:
    first = (name or "").strip().lower().split(" ")[0].strip(".,!'")
    return first in INDIAN_NAMES
