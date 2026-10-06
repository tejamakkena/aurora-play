"""Bot players: fill empty seats so a small group can play big-party games.

A bot is a regular :class:`~utils.room_manager.Player` with ``is_bot=True``
and no socket. The room pump calls :func:`maybe_bot_action` once per tick;
each bot waits a short random "thinking" delay after a phase starts, acts at
most once per phase, and then stays quiet. Policies are pure functions of
engine state -- no sockets, no threads -- so they stay unit-testable.

Only round-based party games get policies. A game with no policy simply gets
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
    """Identify the current decision point for "act once per phase" tracking."""
    round_no = getattr(engine, "round", 0)
    phase = getattr(engine, "phase", "")
    return f"{round_no}:{phase}"


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


def _policy_antakshari(engine, bot_id):
    if engine.phase != "sing":
        return None
    # The first valid song takes the round, and a bot "types" in seconds;
    # sitting out about half the rounds leaves the humans something to win.
    if random.random() < 0.5:
        return None
    letter = (getattr(engine, "letter", "") or "").upper()
    songs = getattr(engine, "songs", None) or _ANTAKSHARI_SONGS
    fitting = [s for s in songs if s.upper().startswith(letter)] if letter else []
    pool = fitting or songs
    return ("submit_song", {"song": random.choice(pool)})


_ANTAKSHARI_SONGS = [
    "Aaja Nachle", "Bommarillu", "Chaiyya Chaiyya", "Dhoom Machale",
    "Enna Solla Pogirai", "Gerua", "Hosanna", "Illahi",
    "Jai Ho", "Kabhi Khushi Kabhie Gham", "Lungi Dance", "Maa Tujhe Salaam",
    "Natu Natu", "O Antava", "Pinga", "Que Sera Sera",
    "Radha", "Saami Saami", "Tum Hi Ho", "Udta Punjab",
    "Vaste", "Why This Kolaveri", "Yeh Dosti", "Zinda",
]


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
    "most_likely_to": _policy_most_likely_to,
    "brain_battle": _policy_brain_battle,
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
