"""Bot players: fill empty seats so a small group can play big-party games.

A bot is a regular :class:`~utils.room_manager.Player` with ``is_bot=True``
and no socket. The room pump calls :func:`maybe_bot_action` once per tick;
each bot waits a short random "thinking" delay after a phase starts, acts at
most once per phase, and then stays quiet. Policies are pure functions of
engine state -- no sockets, no threads -- so they stay unit-testable.

Only party games and the spoken games get policies. A game with no policy simply gets
no bot actions (bots abstain) rather than a wrong guess at its protocol.
"""

import logging
import random
import time

logger = logging.getLogger(__name__)

#: Display names handed out to bots. The host can add several; names are
#: de-duplicated per room by ``Room.add_bot``.
BOT_NAMES = [
    "Chitti", "Bujji", "Robo Ravi", "Auto Arjun",
    "Byte Bhavani", "CPU Chinni", "Digi Divya", "Bot Balu",
]

#: Seconds a bot "thinks" after a phase starts before acting. Staggered so
#: four bots do not answer in the same tick.
THINK_MIN_SECONDS = 2.0
THINK_MAX_SECONDS = 7.0

_LIES = [
    "yesterday's lunch", "a missing sock", "my neighbour's goat",
    "extra homework", "a haunted auto-rickshaw", "cold coffee",
    "the last slice of pizza", "a talking parrot",
]


def _phase_key(engine) -> str:
    """Identify the current decision point for "act once per phase" tracking.

    An engine whose single phase holds many decisions (the 20 Questions
    Answerer replies once per question) exposes ``bot_step`` so each one
    counts as a fresh decision point.
    """
    round_no = getattr(engine, "round", 0)
    phase = getattr(engine, "phase", "")
    step = getattr(engine, "bot_step", None)
    if step is None:
        return f"{round_no}:{phase}"
    return f"{round_no}:{phase}:{step}"


#: How often a trivia bot knows the answer: a fair opponent, not a wall.
TRIVIA_BOT_ACCURACY = 0.6


def _policy_trivia(engine, bot_id):
    """Trivia game show (trivia_show.py): vote a category door, throw a
    random power at a random rival, and answer with TRIVIA_BOT_ACCURACY."""
    phase = getattr(engine, "phase", "")
    if phase == "category_vote":
        categories = getattr(engine, "categories", []) or []
        if not categories:
            return None
        return ("vote_category", {"index": random.randrange(len(categories))})
    if phase == "power_pick":
        rivals = [p.id for p in engine.room.players
                  if p.id != bot_id and p.connected]
        power = random.choice(["freeze", "scramble", "fog", "shield"])
        if power == "shield" or not rivals:
            return ("pick_power", {"power": "shield"})
        return ("pick_power", {"power": power, "targetID": random.choice(rivals)})
    if phase not in ("question", "finale_question"):
        return None
    question = getattr(engine, "question", None)
    if not question:
        return None
    choices = question[2]
    if not choices:
        return None
    correct = question[3]
    if 0 <= correct < len(choices) and random.random() < TRIVIA_BOT_ACCURACY:
        index = correct
    else:
        index = random.randrange(len(choices))
    return ("answer", {"choiceIndex": index, "questionID": engine.question_id})


def _policy_kbc(engine, bot_id):
    phase = getattr(engine, "phase", "")
    choices = getattr(engine, "choices", []) or []
    if not choices:
        return None
    if phase == "poll":
        return ("poll_vote", {"index": random.randrange(len(choices))})
    if phase == "answer" and getattr(engine, "hot_seat", None) == bot_id:
        hidden = set(getattr(engine, "hidden", []) or [])
        options = [i for i in range(len(choices)) if i not in hidden] or list(range(len(choices)))
        return ("answer", {"index": random.choice(options)})
    return None


def _policy_bluff_it(engine, bot_id):
    if engine.phase == "write":
        return ("submit_lie", {"text": random.choice(_LIES)})
    if engine.phase == "pick":
        options = getattr(engine, "options", [])
        if not options:
            return None
        choices = [i for i, o in enumerate(options)
                   if o.get("ownerID") != bot_id]
        if not choices:
            return None
        return ("pick", {"index": random.choice(choices)})
    return None


# ---- Spoken games (spoken.py) ------------------------------------------------
# A bot cannot talk or sing, so in Atlas and Antakshari it only does what a
# phone does: judge the speaker (mostly generously) and, after its own turn,
# tap a plausible last letter.

#: How often a bot judge waves a turn through.
SPOKEN_BOT_GENEROSITY = 0.8
#: How often a bot speaker is stumped and lets the Atlas clock run out.
ATLAS_BOT_STUMPED = 0.15

#: Common last letters of place names and of (transliterated) Hindi songs,
#: weighted by repetition.
_PLACE_ENDINGS = "AAAAANNNYYLLDOESRIK"
_SONG_ENDINGS = "AAAEEIIINNHHRRMKLY"


def _atlas_bot_place(engine):
    """A real place for the letter the bot was asked for, or ''."""
    from games.native_hub.engines import _content as C
    chain = getattr(engine, "chain", None) or []
    letter = (chain[-1].get("letter") if chain else "") or getattr(engine, "letter", "")
    used = {(e.get("place") or "").lower() for e in chain}
    pool = sorted(p for p in C.ATLAS_PLACES
                  if letter and p.startswith(letter.lower()) and p not in used)
    return random.choice(pool).title() if pool else ""


def _policy_atlas(engine, bot_id):
    phase = getattr(engine, "phase", "")
    speaker = getattr(engine, "speaker", None)
    if phase == "say":
        if bot_id == speaker:
            if random.random() < ATLAS_BOT_STUMPED:
                return None
            return ("said", {})
        speaker_player = engine.room.player(speaker) if speaker else None
        if speaker_player is not None and speaker_player.is_bot:
            # Nothing was said out loud: leave a bot's turn to its own
            # "said" (or the clock), and to any human who calls Out!.
            return None
        verdict = "valid" if random.random() < SPOKEN_BOT_GENEROSITY else "out"
        return ("judge", {"verdict": verdict})
    if phase == "letter" and bot_id == speaker:
        place = _atlas_bot_place(engine)
        letter = place[-1].upper() if place else random.choice(_PLACE_ENDINGS)
        return ("pick_letter", {"letter": letter, "place": place})
    return None


def _policy_antakshari(engine, bot_id):
    phase = getattr(engine, "phase", "")
    team = getattr(engine, "team_of", {}).get(bot_id)
    singing = getattr(engine, "singing", 0)
    if team is None:
        return None
    if phase == "sing" and team != singing:
        verdict = "sang" if random.random() < SPOKEN_BOT_GENEROSITY else "missed"
        return ("judge", {"verdict": verdict})
    if phase == "letter" and team == singing:
        return ("pick_letter", {"letter": random.choice(_SONG_ENDINGS)})
    return None


def _policy_most_likely_to(engine, bot_id):
    if getattr(engine, "phase", "") != "vote":
        return None
    others = [p.id for p in engine.room.players
              if p.id != bot_id and p.connected]
    if not others:
        return None
    return ("vote", {"targetID": random.choice(others)})


def _policy_brain_battle(engine, bot_id):
    if getattr(engine, "phase", "") != "answer":
        return None
    puzzle = getattr(engine, "puzzle", None) or {}
    options = list(puzzle.get("options") or [])
    if not options:
        return None
    # A decent but beatable opponent: right a bit more than half the time.
    if puzzle.get("answer") in options and random.random() < 0.55:
        return ("answer", {"choice": puzzle["answer"]})
    return ("answer", {"choice": random.choice(options)})


def _policy_hot_takes(engine, bot_id):
    """A bot cannot argue out loud: as a debater it hands the floor back
    straight away (so the room is not left with 30 s of silence); as a
    voter it votes for a random side."""
    phase = getattr(engine, "phase", "")
    if phase in ("for", "against"):
        speaker = engine.for_id if phase == "for" else engine.against_id
        if speaker == bot_id:
            return ("done_speaking", {})
        return None
    if phase == "vote" and engine.is_voter(bot_id) and bot_id not in engine.votes:
        return ("vote", {"side": random.choice(["for", "against"])})
    return None


def _policy_twenty_questions(engine, bot_id):
    """As the Answerer, answer yes or no at random (it cannot hear the
    question). Never guesses."""
    if getattr(engine, "phase", "") != "ask":
        return None
    if getattr(engine, "answerer_id", None) != bot_id:
        return None
    if str(getattr(engine, "bot_step", "")).endswith("wait"):
        return None                       # give the room time to ask
    return ("answer", {"value": random.choice(["yes", "no"])})


#: game_id -> policy. Deliberately explicit: adding a game here is a
#: conscious decision that the bot understands that game's protocol.
#: NOTE: emoji_movie is intentionally excluded -- bot emoji output would be
#: app-generated emoji content, which the no-emoji policy forbids. Human
#: players' own emoji submissions are user-generated and remain allowed.
POLICIES = {
    "trivia": _policy_trivia,
    "kbc": _policy_kbc,
    "bluff_it": _policy_bluff_it,
    "antakshari": _policy_antakshari,
    "atlas": _policy_atlas,
    "most_likely_to": _policy_most_likely_to,
    "brain_battle": _policy_brain_battle,
    "hot_takes": _policy_hot_takes,
    "twenty_questions": _policy_twenty_questions,
}


def maybe_bot_action(engine, player):
    """Return ``(action, data)`` for a bot, or ``None`` if it should wait.

    Must be called with the room lock held, like every other engine call.
    Never raises: a bot bug must not break the pump for real players.
    """
    try:
        return _maybe_bot_action(engine, player)
    except Exception:
        logger.exception("bot action failed game=%s",
                         getattr(engine, "game_id", "?"))
        return None


def _maybe_bot_action(engine, player):
    policy = POLICIES.get(getattr(engine, "game_id", ""))
    if policy is None:
        return None

    key = _phase_key(engine)
    now = time.time()
    if player.bot_phase_key != key:
        # New phase: schedule a staggered thinking delay, act on a later tick.
        player.bot_phase_key = key
        player.bot_act_at = now + random.uniform(THINK_MIN_SECONDS,
                                                THINK_MAX_SECONDS)
        return None
    if now < player.bot_act_at:
        return None
    # Act at most once per phase.
    player.bot_act_at = float("inf")
    return policy(engine, player.id)
