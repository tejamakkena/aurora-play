"""The show host: talk-show banter that runs through a whole Game Night.

A Game Night is a playlist and a scoreboard (games/game_night.py). The show
host turns it into a show: an opener, a teaser before each game, a reaction
when a quiz question stumps the room ("Nobody got that? I expected a third
grader to know this one."), a cheer for each winner, a word on the standings,
and a closer for the champion.

Every spoken line is FIXED text with no names or numbers in it, so the whole
script can be rendered once into the offline voice pack
(tools/render_voice_pack.py) and played in the natural voice. Names go in the
on-screen ``headline`` only ("Asha takes the lead!"), never in the spoken line.

Kids mode (a Game Night with ``kids``) uses gentle, encouraging lines only:
no roasting.

The server only queues lines on the room (``say``); ``broadcast`` sends each one
once as a ``host_line`` event and the TV shows it as a lower third and speaks it
between the game's own lines. Everything is a no-op outside a Game Night.

All text is emoji-free: it is shown on screen and read aloud.
"""

import random

# ---------------------------------------------------------------------------
# the script
# ---------------------------------------------------------------------------

#: moment -> lines. A "<moment>_kids" entry, when present, replaces the moment
#: in Kids mode; a moment with no kids entry is not said in Kids mode at all.
LINES: dict[str, list[str]] = {
    # ---- the night opens (a plain Game Night; a party has its own welcome) ----
    "night_open": [
        "Good evening, and welcome to game night! Phones out, egos in.",
        "Welcome, welcome! Tonight there will be winners, there will be losers, and there will be excuses.",
        "Hello everyone! The snacks are ready, the scoreboard is empty, and friendships are about to be tested.",
        "Welcome to game night, where everyone is a genius until the first question.",
        "Ladies and gentlemen, settle in. Tonight one of you becomes a legend, and the rest of you become the audience.",
        "Welcome! A quick reminder: it is just a game. Unless you win. Then it is everything.",
        "Good evening! I have seen the lineup, and I have seen the players. This is going to be fun to watch.",
        "Welcome to the show! No refunds, no rematches, and absolutely no sulking. Well, a little sulking.",
    ],
    "night_open_kids": [
        "Welcome to game night! Let us play, learn, and have lots of fun.",
        "Hello everyone! Get ready for a night of fun and clever thinking.",
        "Welcome, superstars! Tonight we play, we learn, and we cheer for each other.",
    ],

    # ---- before each game: a teaser by the kind of game ----
    "intro_quiz": [
        "Quiz time! This is where we find out who actually paid attention in school.",
        "Next up, a quiz. Remember, guessing is a strategy. A bad one, but a strategy.",
        "Brains on, everyone. The questions are easy. That is what makes it embarrassing.",
        "Quiz round! Somewhere a school teacher is watching, and hoping.",
        "Time to test those brains. Please do not phone a friend. Your friends are all here.",
    ],
    "intro_social": [
        "Next, a talking game. Secrets will be shared, and nobody is getting them back.",
        "Time to find out what your friends really think of you. Brace yourselves.",
        "This next one is all about the people in this room. Choose your words carefully.",
        "Get comfortable. This one starts friendships, and occasionally ends them.",
        "Next up, the game where everybody learns a little too much about everybody.",
    ],
    "intro_music": [
        "Music round! Remember, singing loudly does not make the answer right.",
        "Warm up those voices. The neighbours have been warned.",
        "Next up, music. Hum if you must, but please, hum in tune.",
        "Time for a song or two. Shower singers, this is your moment.",
    ],
    "intro_words": [
        "Word game next. Spelling counts, unlike in your text messages.",
        "Time for words. Big ones, small ones, and some that may not exist.",
        "Next, a word game. Dictionaries are not allowed. Neither is crying.",
    ],
    "intro_board": [
        "Board game time. Patience, strategy, and a little bit of luck. Mostly luck.",
        "Next, a board game. Please do not flip the table. It is a television.",
        "Board game next. May the dice be kind to you. They will not be.",
    ],
    "intro_strategy": [
        "Strategy round. Think three moves ahead. Or one. One is fine.",
        "Next, a game for the planners. You know who you are.",
        "Time for some strategy. Trust nobody. Especially the quiet one.",
    ],
    "intro_creative": [
        "Next, a creative one. Talent is optional, confidence is required.",
        "Time to perform! The judges are harsh, and also your family.",
        "Creative round next. There are no wrong answers. There are, however, very strange ones.",
    ],
    "intro_action": [
        "Fast fingers, everyone! This one is over before you finish blinking.",
        "Next, a speed game. Reflexes on. Excuses off.",
    ],
    "intro_teams": [
        "Team game next. Remember, there is no I in team. There is one in win, though.",
        "Time to work together. Try not to blame each other. Out loud.",
    ],
    "intro_classic": [
        "Next, a classic. The kind of game your grandparents would play, and win.",
        "A family favourite is up next. Old school, still undefeated.",
    ],
    "intro_any": [
        "Next game coming up. Fresh start, clean slate, same old rivalries.",
        "On to the next one! Whatever happened in the last game stays in the last game.",
        "Next game! Whoever lost the last round, this is your comeback story.",
    ],
    "intro_kids": [
        "Next game! Let us have fun and learn something new.",
        "Get ready, team! Here comes the next challenge.",
        "Brains ready? Here we go!",
        "Here comes another one. Do your best and have fun!",
    ],
    "last_game": [
        "One game left! Everything is still possible. Probably.",
        "Last game coming up. Legends are made here. So are excuses.",
        "This is it, the final game. Leave nothing on the table.",
    ],
    "last_game_kids": [
        "Last game of the night! Let us make it a great one.",
    ],

    # ---- a quiz question is revealed ----
    "answers_none": [
        "Nobody got that? I expected a third grader to know this one.",
        "Zero correct answers. The question would like an apology.",
        "Not a single right answer. I am not angry, just disappointed.",
        "Wow. Not one of you. Somewhere a school principal just felt a disturbance.",
        "Nobody? Let us all agree to never speak of this again.",
        "Everyone got it wrong. At least you are wrong together. That is teamwork.",
        "That one stumped the whole room. I will be telling people about this.",
        "Not one correct answer. Even a coin toss would have done better.",
    ],
    "answers_none_kids": [
        "That was a tricky one! Now you all know something new.",
        "Nobody got it this time. That is how we learn. Next one!",
        "Ooh, a tough question! Great try, everyone.",
    ],
    "answers_all": [
        "Everybody got it! Either that was too easy, or you are all secretly geniuses.",
        "A clean sweep! The person who wrote that question is now crying.",
        "All correct! I will make the next one harder. You have been warned.",
        "Everyone got that one. Beautiful. Enjoy it, it will not last.",
        "One hundred percent! Somebody check the room for cheat sheets.",
    ],
    "answers_all_kids": [
        "Everybody got it! You are all so clever!",
        "Wow, all correct! High fives all around!",
    ],
    "answers_one": [
        "Only one person got that right. The rest of you, take notes.",
        "A lone genius in the room! Everyone else, please applaud and feel bad.",
        "Just one correct answer. That person is now unbearable, and they have earned it.",
        "One right answer. One. The rest of you were so confident, too.",
    ],
    "answers_one_kids": [
        "Only one person got it! Great thinking.",
    ],
    "answers_most_wrong": [
        "Most of you missed that one. Bold choices were made.",
        "The majority went the wrong way. Democracy has failed us.",
        "Lots of wrong answers there. That is okay. Confidence is a kind of talent too.",
        "Most of the room got that wrong. I will pretend I did not see it.",
    ],
    "answers_most_wrong_kids": [
        "A tricky one! Well done to everyone who got it.",
        "Good try, everyone! Learning is the real prize.",
    ],
    "answers_silence": [
        "Nobody answered. I will assume you were all too stunned by the question.",
        "Total silence. Was it the question, or did everyone fall asleep?",
    ],
    "answers_silence_kids": [
        "No answers that time. Get ready, the next one is coming!",
    ],

    # ---- a game in the night has ended ----
    "game_won": [
        "And we have a winner! Take a bow. Everyone else, take notes.",
        "What a performance! The winner would like to thank their fans, and their luck.",
        "A worthy winner! Somebody get them a trophy. Or at least a samosa.",
        "Victory! Please clap. Even if it hurts.",
        "And that is how it is done. For everyone else, the snacks are still available for comfort.",
        "The winner is looking very pleased with themselves. As they should.",
    ],
    "game_won_kids": [
        "Great job to our winner! And well played, everyone!",
        "We have a winner! Give everyone a big round of applause.",
    ],
    "game_tied": [
        "It is a tie! Nobody wins, nobody loses, everybody is annoyed.",
        "A tie at the top! Sharing is caring, apparently.",
    ],
    "game_tied_kids": [
        "It is a tie! Everybody did brilliantly.",
    ],
    "lead_change": [
        "We have a new leader! The old leader is pretending not to care.",
        "And the lead changes hands! This night just got interesting.",
        "New name at the top of the scoreboard! The crown is getting passed around.",
    ],
    "lead_change_kids": [
        "We have a new leader on the scoreboard! Keep going, everyone.",
    ],
    "lead_kept": [
        "Our leader stays on top. Somebody, please, stop them.",
        "Still in the lead! At this point it is getting a little rude.",
    ],
    "close_race": [
        "It is neck and neck at the top. Nobody blink.",
        "The scores are tight! Every single point counts now.",
    ],
    "close_race_kids": [
        "It is very close at the top! Every point counts.",
    ],
    "runaway": [
        "The leader is running away with it. Everyone else, it is time for a miracle.",
        "That lead is getting enormous. The rest of you might need a plan. Any plan.",
    ],
    "last_place": [
        "To whoever is in last place: you are not losing, you are building suspense.",
        "Last place is just first place, seen from the other side.",
        "Bottom of the table. Do not worry, every great comeback starts somewhere.",
    ],

    # ---- the night is over (a plain Game Night; a party has its own finale) ----
    "night_close": [
        "And that is game night! Congratulations to our champion. Everyone else, there is always next time.",
        "That is a wrap! A champion is crowned, and friendships survived. Mostly.",
        "Game night is over! Thank you for playing, laughing, and arguing about the rules.",
    ],
    "night_close_kids": [
        "That is the end of game night! Everyone did a brilliant job.",
        "Game night is over! Thank you for playing, and well done, everyone!",
    ],
}

#: games/game_night.CATALOG tags -> the teaser moment, first match wins.
INTRO_FOR_TAG = [
    ("quiz", "intro_quiz"), ("brain", "intro_quiz"), ("music", "intro_music"),
    ("acting", "intro_creative"), ("creative", "intro_creative"),
    ("words", "intro_words"), ("geography", "intro_words"),
    ("board", "intro_board"), ("strategy", "intro_strategy"),
    ("teams", "intro_teams"), ("action", "intro_action"),
    ("classic", "intro_classic"), ("social", "intro_social"),
]

#: Lines kept on the room between pushes; older unsent ones are dropped.
MAX_QUEUED = 4
#: A runaway lead, in Game Night points.
RUNAWAY_POINTS = 8


def all_lines() -> list[str]:
    """Every line the host can say, for the voice pack."""
    return [line for lines in LINES.values() for line in lines]


# ---------------------------------------------------------------------------
# saying a line
# ---------------------------------------------------------------------------

def _night(room) -> dict | None:
    night = getattr(room, "night", None)
    return night if isinstance(night, dict) else None


def _pick(night: dict, moment: str, rng: random.Random) -> str | None:
    """A line for ``moment`` (the kids variant in Kids mode), avoiding lines
    already said tonight until the moment's pool runs out."""
    key = f"{moment}_kids" if night.get("kids") else moment
    pool = LINES.get(key)
    if not pool:
        return None
    used = night.setdefault("hostUsed", [])
    fresh = [line for line in pool if line not in used]
    if not fresh:
        used[:] = [line for line in used if line not in pool]
        fresh = list(pool)
    line = rng.choice(fresh)
    used.append(line)
    return line


def say(room, moment: str, headline: str | None = None,
        rng: random.Random | None = None) -> str | None:
    """Queue one host line for the TV. Only during a Game Night; returns the
    spoken text, or None when nothing was queued."""
    night = _night(room)
    if night is None or night.get("finished") and moment != "night_close":
        return None
    line = _pick(night, moment, rng or random.Random())
    if line is None:
        return None
    room.host_seq = getattr(room, "host_seq", 0) + 1
    queue = getattr(room, "host_queue", None)
    if queue is None:
        queue = room.host_queue = []
    queue.append({"seq": room.host_seq, "moment": moment, "text": line,
                  "headline": headline or ""})
    del queue[:-MAX_QUEUED]
    return line


def pending(room) -> list[dict]:
    """Lines not yet sent, oldest first; marks them sent."""
    sent = getattr(room, "host_sent", 0)
    out = [dict(entry) for entry in getattr(room, "host_queue", None) or [] if entry["seq"] > sent]
    if out:
        room.host_sent = out[-1]["seq"]
    return out


# ---------------------------------------------------------------------------
# the moments
# ---------------------------------------------------------------------------

def _game_title(game_id: str | None) -> str:
    from games.native_hub.rules import rules_for
    return (rules_for(game_id).get("title") if game_id else None) or "the game"


def intro_moment(game_id: str | None) -> str:
    from games.game_night import CATALOG
    tags = (CATALOG.get(game_id or "") or {}).get("tags", [])
    for tag, moment in INTRO_FOR_TAG:
        if tag in tags:
            return moment
    return "intro_any"


def night_opened(room, rng: random.Random | None = None) -> None:
    """The night starts: an opener (unless a party welcome covers it) and the
    first game's teaser."""
    night = _night(room)
    if night is None:
        return
    rng = rng or random.Random()
    if not night.get("party"):
        say(room, "night_open", rng=rng)
        game_up_next(room, rng=rng)


def game_up_next(room, rng: random.Random | None = None) -> None:
    """The lobby for the night's next game is up."""
    night = _night(room)
    if night is None or night.get("finished"):
        return
    rng = rng or random.Random()
    game = room.game_id
    headline = f"Up next: {_game_title(game)}"
    last = night.get("index", 0) == len(night.get("playlist", [])) - 1 and night.get("index", 0) > 0
    say(room, "last_game" if last else
        ("intro_kids" if night.get("kids") else intro_moment(game)), headline, rng=rng)


def answers_revealed(room, answered: list[str], right: list[str], players: int,
                     rng: random.Random | None = None) -> str | None:
    """A quiz question's answer is on screen. ``answered``/``right`` are player
    ids; ``players`` is how many could have answered. Big moments always get a
    line; an ordinary split only sometimes, so the host does not talk over
    every question."""
    if _night(room) is None or players <= 0:
        return None
    rng = rng or random.Random()
    answered_set, right_set = set(answered), set(right) & set(answered)
    if not answered_set:
        moment, chance = "answers_silence", 1.0
    elif not right_set:
        moment, chance = "answers_none", 1.0
    elif len(right_set) == len(answered_set) and len(answered_set) >= max(2, players // 2):
        moment, chance = "answers_all", 0.6
    elif len(right_set) == 1 and len(answered_set) >= 3:
        moment, chance = "answers_one", 0.9
    elif len(right_set) * 2 < len(answered_set):
        moment, chance = "answers_most_wrong", 0.5
    else:
        return None
    if rng.random() >= chance:
        return None
    headline = ""
    if moment == "answers_one":
        pid = next(iter(right_set))
        player = room.player(pid) if hasattr(room, "player") else None
        headline = f"Only {player.name} got it!" if player else ""
    elif moment == "answers_none":
        headline = "Nobody got it!"
    elif moment == "answers_all":
        headline = "Everybody got it!"
    return say(room, moment, headline, rng=rng)


def game_finished(room, results: list, before: list[dict],
                  rng: random.Random | None = None) -> None:
    """A game of the night ended. ``before`` is the night's standings before
    this game's points were added (games/game_night.standings)."""
    night = _night(room)
    if night is None or not isinstance(results, list) or not results:
        return
    rng = rng or random.Random()
    from games import game_night
    title = _game_title(room.game_id)
    top = [r for r in results if isinstance(r, dict) and r.get("rank") == 1]
    if len(top) == 1:
        say(room, "game_won", f"{top[0].get('name') or 'Player'} wins {title}!", rng=rng)
    elif len(top) > 1:
        say(room, "game_tied", f"A tie in {title}!", rng=rng)

    after = game_night.standings(room)
    if len(after) < 2:
        return
    leader, second, bottom = after[0], after[1], after[-1]
    old_leader = before[0]["playerID"] if before and before[0]["points"] > 0 else None
    games_played = len(night.get("history", []))
    if leader["points"] == second["points"]:
        say(room, "close_race", "All square at the top!", rng=rng)
    elif old_leader and old_leader != leader["playerID"]:
        say(room, "lead_change", f"{leader['name']} takes the lead!", rng=rng)
    elif games_played >= 2 and leader["points"] - second["points"] >= RUNAWAY_POINTS:
        say(room, "runaway", f"{leader['name']} is way out in front!", rng=rng)
    elif games_played >= 2 and leader["points"] - second["points"] <= 2:
        say(room, "close_race", f"{leader['name']} leads by a whisker!", rng=rng)
    elif games_played >= 2 and len(after) >= 3 and bottom["points"] < second["points"] \
            and rng.random() < 0.5:
        say(room, "last_place", f"Hang in there, {bottom['name']}!", rng=rng)
    elif games_played >= 2:
        say(room, "lead_kept", f"{leader['name']} is still on top!", rng=rng)


def night_closed(room, rng: random.Random | None = None) -> None:
    """The last game is done. A party says its own finale instead."""
    night = _night(room)
    if night is None or night.get("party"):
        return
    from games import game_night
    top = game_night.standings(room)[:1]
    headline = f"{top[0]['name']} is tonight's champion!" if top and top[0]["points"] > 0 else ""
    say(room, "night_close", headline, rng=rng)
