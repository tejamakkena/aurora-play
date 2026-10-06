"""Trivia, rebuilt as a TV game show.

An original party-quiz format built for the TV-plus-phones setup:

``intro``            title card.
``category_vote``    three category doors on the TV, phones vote (random
                     tie-break). Skipped for custom quizzes.
``category_reveal``  the winning door swings open.
``power_pick``       before every second question: each player throws one
                     power at a rival (freeze / scramble / fog) or raises a
                     shield. Powers only change the target's PHONE answer
                     screen for the next question.
``power_reveal``     the TV announces who hit whom (only when powers flew).
``question``         four options, 15 seconds once the choices show, 500
                     points for a right answer plus up to 500 speed bonus.
                     Correctness never reaches the TV before the reveal:
                     points are held back until then.
``reveal``           the right answer, who got it and the points.
``standings``        between rounds of three questions.
``finale_intro``     "Final Climb": everyone gets a tower position, leaders
                     start a rung or two up.
``finale_question``  rapid-fire questions: right climbs a rung, wrong slips
``finale_reveal``    one. First to the top wins, otherwise the highest after
                     the last finale question.
``summary``          winner celebration, then the game ends.

Every phase carries a ``deadline`` (epoch seconds) and ``secondsLeft`` in
both public and private state. The engine never blocks: phases advance on
the 1 Hz pump through ``tick``.

Question sources, in priority order (same as before the rebuild):
``room.seed_questions`` (the phone's make-your-own quiz), ``room.topic``
(topic_gen), then the room's content pack (content_packs.fresh_questions,
which also mixes in content_service's live pool for English) with the
room/device no-repeat history.
"""

import random
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines.content_packs import (
    fresh_questions,
    record_questions,
)

#: Powers a player can pick. Attack powers need a rival target; the shield
#: protects the picker. ``detail`` is shown on the phone picker.
POWERS = [
    {"id": "freeze", "name": "Freeze", "kind": "attack",
     "detail": "They must tap 5 times to break the ice."},
    {"id": "scramble", "name": "Scramble", "kind": "attack",
     "detail": "Their answers keep jumping around."},
    {"id": "fog", "name": "Fog", "kind": "attack",
     "detail": "Their answers start blurry and clear slowly."},
    {"id": "shield", "name": "Shield", "kind": "shield",
     "detail": "Blocks one power thrown at you."},
]
ATTACK_POWERS = {p["id"] for p in POWERS if p["kind"] == "attack"}
POWER_IDS = {p["id"] for p in POWERS}

#: Shown on the extra door when the pack has fewer than three categories
#: with questions left. It deals a mixed set.
MIXED_CATEGORY = "Surprise Mix"


class TriviaEngine(NativeGameEngine):
    game_id = "trivia"
    min_players = 2
    max_players = 10

    # ---- tuning -------------------------------------------------------------
    INTRO_SECONDS = 4
    VOTE_SECONDS = 10
    CATEGORY_REVEAL_SECONDS = 3
    POWER_SECONDS = 12
    POWER_REVEAL_SECONDS = 4
    #: Reading beat before the four options appear.
    READ_SECONDS = 1.5
    QUESTION_SECONDS = 15
    REVEAL_SECONDS = 5
    STANDINGS_SECONDS = 5
    FINALE_INTRO_SECONDS = 6
    FINALE_READ_SECONDS = 1.0
    FINALE_QUESTION_SECONDS = 10
    FINALE_REVEAL_SECONDS = 3
    SUMMARY_SECONDS = 9

    QUESTIONS_PER_ROUND = 3
    MAIN_ROUNDS = 3
    MAIN_QUESTIONS = QUESTIONS_PER_ROUND * MAIN_ROUNDS
    FINALE_QUESTIONS = 8
    #: Rungs on the finale tower; reaching this rung wins.
    TOWER_HEIGHT = 7
    #: Head start in rungs by score placing (1st, 2nd).
    HEAD_START = (2, 1)

    BASE_POINTS = 500
    SPEED_BONUS = 500
    FINALE_POINTS = 250

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        #: Increments on every phase entry. Bots key "act once" on
        #: (round, phase), so this is what lets a bot answer each of the
        #: finale questions, which all share one phase name.
        self.round = 0
        self.phase = "intro"
        self.deadline = 0.0
        self.phase_seconds = 0
        self.scores: dict[str, int] = {}
        self._finished = False

        # Question supply.
        self._pack = "en"
        self.custom = False
        self.quiz_name = ""
        self.pool: list[tuple] = []          # every question available
        self._used: set[str] = set()         # question texts already dealt
        self.plan: list[tuple] = []          # custom quizzes: main questions in order
        self.round_questions: list[tuple] = []
        self.finale_pool: list[tuple] = []
        self.total_rounds = 0                # main questions this game
        self.total_round_groups = 0

        # Current question.
        self.question: tuple | None = None
        self.question_id = ""
        self.question_no = 0                 # 1-based main question number
        self.round_no = 0                    # 1-based round (group of three)
        self.choices_at = 0.0
        self.answered: dict[str, int] = {}
        self.answer_times: dict[str, float] = {}
        self.pending_points: dict[str, int] = {}
        self.last_results: list[dict] = []

        # Category vote.
        self.categories: list[str] = []
        self.votes: dict[str, int] = {}
        self.chosen_category = ""
        self.chosen_index = -1

        # Powers.
        self.power_picks: dict[str, dict] = {}
        self.power_events: list[dict] = []
        self.hits: dict[str, list[dict]] = {}       # target -> landed powers
        self.shield_blocks: dict[str, list[str]] = {}  # shielded -> attacker names

        # Standings.
        self.prev_ranks: dict[str, int] = {}

        # Finale.
        self.rungs: dict[str, int] = {}
        self.finale_no = 0
        self.finale_total = 0
        self.finale_moves: dict[str, int] = {}
        self.winner_id: str | None = None

    # ======================================================================
    # Setup
    # ======================================================================

    def start(self, players):
        self.scores = {p.id: 0 for p in players}
        self.rungs = {p.id: 0 for p in players}
        if not self._start_from_seeds():
            topic = (getattr(self.room, "topic", "") or "").strip()
            if not (topic and self._start_from_topic(topic)):
                self._start_from_pack()
        self._enter("intro", self.INTRO_SECONDS)

    def _start_from_seeds(self) -> bool:
        """Custom quiz from room.seed_questions (create_room "seedQuestions")."""
        seeds = list(getattr(self.room, "seed_questions", None) or [])
        if not seeds:
            return False
        try:
            from games import topic_gen
            topic = (getattr(self.room, "topic", "") or "").strip()
            pool = [topic_gen.question_dict_to_tuple(topic or "Your quiz", q)
                    for q in seeds]
        except Exception:
            return False
        if not pool:
            return False
        self._pack = "seeded"
        self._setup_custom(pool, topic or "Your quiz")
        return True

    def _start_from_topic(self, topic: str) -> bool:
        """Custom quiz from live topic generation (games/topic_gen.py).

        Returns False when only the bundled fallback answered, so the room's
        language pack plays instead.
        """
        try:
            from games import topic_gen
            key = topic_gen.norm_topic(topic)
            pack_key = f"topic:{key}"
            history = getattr(self.room, "question_history", {}).get(
                (pack_key, "trivia"), [])
            items, source = topic_gen._fetch(
                "questions", topic,
                min(self.MAIN_QUESTIONS + self.FINALE_QUESTIONS, 20),
                session_history=history)
            if source == "bundled":
                return False
            pool = [topic_gen.question_dict_to_tuple(topic, q) for q in items]
        except Exception:
            return False
        if not pool:
            return False
        self._pack = pack_key
        self._setup_custom(pool, topic)
        return True

    def _setup_custom(self, pool: list[tuple], name: str) -> None:
        self.custom = True
        self.quiz_name = name
        self.pool = list(pool)
        main = min(self.MAIN_QUESTIONS, len(self.pool))
        self.plan = self.pool[:main]
        self.finale_pool = self.pool[main:main + self.FINALE_QUESTIONS]
        self.total_rounds = main
        self.total_round_groups = max(1, -(-main // self.QUESTIONS_PER_ROUND))
        self.chosen_category = name
        # The first question is known up front for a custom quiz.
        self.question = self.plan[0]

    def _start_from_pack(self) -> None:
        pack = getattr(self.room, "content_pack", "en") or "en"
        self._pack = pack
        pool = list(fresh_questions(self.room, pack, "trivia"))
        random.shuffle(pool)
        # De-duplicate by question text so nothing repeats in a session.
        seen: set[str] = set()
        self.pool = []
        for q in pool:
            if q[1] not in seen:
                seen.add(q[1])
                self.pool.append(q)
        self.custom = False
        self.quiz_name = ""
        self.total_rounds = min(self.MAIN_QUESTIONS, len(self.pool))
        self.total_round_groups = max(1, -(-self.total_rounds // self.QUESTIONS_PER_ROUND))

    # ======================================================================
    # Question supply
    # ======================================================================

    def _unused(self) -> list[tuple]:
        return [q for q in self.pool if q[1] not in self._used]

    def _offer_categories(self) -> list[str]:
        counts: dict[str, int] = {}
        for q in self._unused():
            counts[q[0]] = counts.get(q[0], 0) + 1
        need = self.QUESTIONS_PER_ROUND
        rich = [c for c, n in counts.items() if n >= need and c != MIXED_CATEGORY]
        random.shuffle(rich)
        offer = rich[:3]
        if len(offer) < 3:
            thin = [c for c, n in counts.items() if c not in offer and n > 0]
            random.shuffle(thin)
            offer += thin[:3 - len(offer)]
        if len(offer) < 3:
            offer.append(MIXED_CATEGORY)
        return offer[:3]

    def _deal_round(self, category: str) -> None:
        """Pick this round's questions: the voted category first, then mixed."""
        remaining = self.total_rounds - self.question_no
        count = min(self.QUESTIONS_PER_ROUND, max(0, remaining))
        unused = self._unused()
        picked = [q for q in unused if q[0] == category][:count]
        if len(picked) < count:
            rest = [q for q in unused if q not in picked]
            picked += rest[:count - len(picked)]
        self.round_questions = picked

    def _take_main_question(self) -> tuple | None:
        if self.custom:
            idx = self.question_no      # already incremented by caller
            return self.plan[idx - 1] if 0 < idx <= len(self.plan) else None
        if self.round_questions:
            return self.round_questions.pop(0)
        unused = self._unused()
        if unused:
            return unused[0]
        return random.choice(self.pool) if self.pool else None

    def _take_finale_question(self) -> tuple | None:
        if self.custom:
            if self.finale_no <= len(self.finale_pool):
                return self.finale_pool[self.finale_no - 1]
            return None
        unused = self._unused()
        if unused:
            return unused[0]
        return random.choice(self.pool) if self.pool else None

    def _finale_available(self) -> int:
        if self.custom:
            return len(self.finale_pool)
        return self.FINALE_QUESTIONS if self.pool else 0

    def _mark_asked(self, q: tuple) -> None:
        self._used.add(q[1])
        record_questions(self.room, self._pack, "trivia", [q])

    # ======================================================================
    # Phase machine
    # ======================================================================

    def _enter(self, phase: str, seconds: float) -> None:
        self.round += 1
        self.phase = phase
        self.phase_seconds = int(round(seconds))
        self.deadline = time.time() + seconds if seconds else 0.0

    def seconds_left(self) -> int:
        if not self.deadline:
            return 0
        return max(0, int(round(self.deadline - time.time())))

    def active_ids(self) -> list[str]:
        return [p.id for p in self.room.connected_players()]

    def tick(self, dt=0.0):
        if self._finished:
            return
        now = time.time()
        if self.deadline and now >= self.deadline:
            self._advance()
            return
        active = self.active_ids()
        if not active:
            return
        if self.phase == "category_vote" and all(p in self.votes for p in active):
            self._advance()
        elif self.phase == "power_pick" and all(p in self.power_picks for p in active):
            self._advance()
        elif self.phase in ("question", "finale_question") and all(
                p in self.answered for p in active):
            self._advance()

    def _advance(self) -> None:
        phase = self.phase
        if phase == "intro":
            self._begin_round()
        elif phase == "category_vote":
            self._resolve_vote()
        elif phase == "category_reveal":
            self._deal_round(self.chosen_category)
            self._before_question()
        elif phase == "power_pick":
            self._resolve_powers()
        elif phase == "power_reveal":
            self._next_question()
        elif phase == "question":
            self._reveal()
        elif phase == "reveal":
            self._after_reveal()
        elif phase == "standings":
            if self.question_no >= self.total_rounds:
                self._begin_finale()
            else:
                self._begin_round()
        elif phase == "finale_intro":
            self._next_finale_question()
        elif phase == "finale_question":
            self._finale_reveal()
        elif phase == "finale_reveal":
            self._after_finale_reveal()
        elif phase == "summary":
            self._finished = True
            self.deadline = 0.0
        else:
            self._finished = True

    # ---- rounds and category vote ------------------------------------------

    def _begin_round(self) -> None:
        if self.question_no >= self.total_rounds:
            self._begin_finale()
            return
        self.round_no += 1
        self.prev_ranks = self._ranks()
        if self.custom:
            self._before_question()
            return
        self.categories = self._offer_categories()
        self.votes = {}
        self.chosen_category = ""
        self.chosen_index = -1
        self._enter("category_vote", self.VOTE_SECONDS)

    def _vote_counts(self) -> list[int]:
        counts = [0] * len(self.categories)
        for idx in self.votes.values():
            if 0 <= idx < len(counts):
                counts[idx] += 1
        return counts

    def _resolve_vote(self) -> None:
        counts = self._vote_counts()
        if not counts:
            self.chosen_index = -1
            self.chosen_category = MIXED_CATEGORY
        else:
            top = max(counts)
            leaders = [i for i, n in enumerate(counts) if n == top]
            self.chosen_index = random.choice(leaders)
            self.chosen_category = self.categories[self.chosen_index]
        self._enter("category_reveal", self.CATEGORY_REVEAL_SECONDS)

    # ---- powers ---------------------------------------------------------------

    def _powers_due(self) -> bool:
        """Powers come before every second question, with a rival to hit."""
        upcoming = self.question_no + 1
        return upcoming % 2 == 0 and len(self.active_ids()) >= 2

    def _before_question(self) -> None:
        if self._powers_due():
            self.power_picks = {}
            self._enter("power_pick", self.POWER_SECONDS)
        else:
            self._next_question()

    def _resolve_powers(self) -> None:
        self.power_events = []
        self.hits = {}
        self.shield_blocks = {}
        shields = {pid for pid, pick in self.power_picks.items()
                   if pick.get("power") == "shield"}
        # Submission order (dicts keep insertion order): a shield blocks the
        # first power thrown at its owner, and only that one.
        for attacker, pick in self.power_picks.items():
            power = pick.get("power")
            target = pick.get("targetID")
            if power not in ATTACK_POWERS or not target:
                continue
            blocked = target in shields
            if blocked:
                shields.discard(target)
                self.shield_blocks.setdefault(target, []).append(
                    self.player_name(attacker))
            else:
                self.hits.setdefault(target, []).append(
                    {"power": power, "fromID": attacker,
                     "fromName": self.player_name(attacker)})
            self.power_events.append({
                "power": power,
                "fromID": attacker, "fromName": self.player_name(attacker),
                "toID": target, "toName": self.player_name(target),
                "blocked": blocked,
            })
        if self.power_events:
            self._enter("power_reveal", self.POWER_REVEAL_SECONDS)
        else:
            self._next_question()

    # ---- main questions -------------------------------------------------------

    def _next_question(self) -> None:
        """Deal the next main question and open the answer window."""
        self.question_no += 1
        q = self._take_main_question()
        if q is None:
            self.question_no -= 1
            self.total_rounds = self.question_no
            self._begin_finale()
            return
        self.question = q
        self.question_id = f"q{self.question_no}"
        self._mark_asked(q)
        self.answered = {}
        self.answer_times = {}
        self.pending_points = {}
        self.last_results = []
        now = time.time()
        self.choices_at = now + self.READ_SECONDS
        self._enter("question", self.READ_SECONDS + self.QUESTION_SECONDS)

    def points_for(self, answered_at: float) -> int:
        """500 for a right answer plus a speed bonus that drains over the
        15-second answer window (full bonus inside the reading beat)."""
        elapsed = max(0.0, answered_at - self.choices_at)
        frac = max(0.0, 1.0 - elapsed / float(self.QUESTION_SECONDS))
        return self.BASE_POINTS + int(round(self.SPEED_BONUS * frac))

    def _reveal(self) -> None:
        correct = self.question[3] if self.question else -1
        rows = []
        for p in self.room.players:
            choice = self.answered.get(p.id)
            ok = choice is not None and choice == correct
            pts = self.pending_points.get(p.id, 0) if ok else 0
            if pts:
                self._award(p.id, pts)
            rows.append({"playerID": p.id, "name": p.name,
                         "choice": choice, "correct": ok, "points": pts})
        self.last_results = rows
        self._enter("reveal", self.REVEAL_SECONDS)

    def _after_reveal(self) -> None:
        # Powers only last for the question they were thrown at.
        self.hits = {}
        self.shield_blocks = {}
        self.power_events = []
        self.power_picks = {}
        end_of_round = (self.question_no % self.QUESTIONS_PER_ROUND == 0
                        or self.question_no >= self.total_rounds)
        if end_of_round:
            self._enter("standings", self.STANDINGS_SECONDS)
        else:
            self._before_question()

    # ---- finale -----------------------------------------------------------------

    def _begin_finale(self) -> None:
        self.prev_ranks = self._ranks()
        self.finale_total = min(self.FINALE_QUESTIONS, self._finale_available())
        if self.finale_total <= 0:
            self.winner_id = self._leader_by_score()
            self._enter("summary", self.SUMMARY_SECONDS)
            return
        # Head start: the best score starts two rungs up, the next one up
        # (dense ranking, so ties share; nobody gets one for scoring zero).
        distinct = sorted({s for s in self.scores.values() if s > 0}, reverse=True)
        self.rungs = {}
        for pid in self.scores:
            score = self.scores.get(pid, 0)
            start = 0
            if score > 0:
                placing = distinct.index(score)
                if placing < len(self.HEAD_START):
                    start = self.HEAD_START[placing]
            self.rungs[pid] = start
        self.finale_no = 0
        self.finale_moves = {}
        self.question = None
        self.question_id = ""
        self._enter("finale_intro", self.FINALE_INTRO_SECONDS)

    def _next_finale_question(self) -> None:
        self.finale_no += 1
        q = self._take_finale_question()
        if q is None:
            self._end_finale()
            return
        self.question = q
        self.question_id = f"f{self.finale_no}"
        self._mark_asked(q)
        self.answered = {}
        self.answer_times = {}
        self.pending_points = {}
        self.finale_moves = {}
        self.choices_at = time.time() + self.FINALE_READ_SECONDS
        self._enter("finale_question",
                    self.FINALE_READ_SECONDS + self.FINALE_QUESTION_SECONDS)

    def _finale_reveal(self) -> None:
        correct = self.question[3] if self.question else -1
        self.finale_moves = {}
        for pid in list(self.scores):
            if pid not in self.answered:
                self.finale_moves[pid] = 0
                continue
            if self.answered[pid] == correct:
                self.rungs[pid] = min(self.TOWER_HEIGHT, self.rungs.get(pid, 0) + 1)
                self.finale_moves[pid] = 1
                self._award(pid, self.FINALE_POINTS)
            else:
                before = self.rungs.get(pid, 0)
                self.rungs[pid] = max(0, before - 1)
                self.finale_moves[pid] = -1 if before > 0 else 0
        self.last_results = [
            {"playerID": p.id, "name": p.name,
             "choice": self.answered.get(p.id),
             "correct": self.answered.get(p.id) == correct and p.id in self.answered,
             "points": self.FINALE_POINTS if self.finale_moves.get(p.id) == 1 else 0}
            for p in self.room.players
        ]
        top = [pid for pid, r in self.rungs.items() if r >= self.TOWER_HEIGHT]
        if top:
            # Several reached the top on the same question: fastest wins.
            top.sort(key=lambda pid: self.answer_times.get(pid, float("inf")))
            self.winner_id = top[0]
        self._enter("finale_reveal", self.FINALE_REVEAL_SECONDS)

    def _after_finale_reveal(self) -> None:
        if self.winner_id is not None or self.finale_no >= self.finale_total:
            self._end_finale()
        else:
            self._next_finale_question()

    def _end_finale(self) -> None:
        if self.winner_id is None:
            order = self._placement()
            self.winner_id = order[0] if order else None
        self._enter("summary", self.SUMMARY_SECONDS)

    # ======================================================================
    # Actions
    # ======================================================================

    def handle_action(self, player_id, action, data):
        if self._finished or not isinstance(data, dict):
            return
        if self.room.player(player_id) is None:
            return
        if action == "answer":
            self._on_answer(player_id, data)
        elif action == "vote_category":
            self._on_vote(player_id, data)
        elif action == "pick_power":
            self._on_power(player_id, data)

    def _on_answer(self, player_id, data):
        if self.phase not in ("question", "finale_question"):
            return
        if player_id in self.answered or self.question is None:
            return
        if data.get("questionID") != self.question_id:
            return
        idx = data.get("choiceIndex")
        if not isinstance(idx, int) or isinstance(idx, bool):
            return
        if not 0 <= idx < len(self.question[2]):
            return
        now = time.time()
        self.answered[player_id] = idx
        self.answer_times[player_id] = now
        if self.phase == "question" and idx == self.question[3]:
            # Held until the reveal so the TV scoreboard can't give the
            # answer away.
            self.pending_points[player_id] = self.points_for(now)
        self.scores.setdefault(player_id, 0)

    def _on_vote(self, player_id, data):
        if self.phase != "category_vote" or player_id in self.votes:
            return
        idx = data.get("index")
        if not isinstance(idx, int) or isinstance(idx, bool):
            return
        if 0 <= idx < len(self.categories):
            self.votes[player_id] = idx

    def _on_power(self, player_id, data):
        if self.phase != "power_pick" or player_id in self.power_picks:
            return
        power = data.get("power")
        if power not in POWER_IDS:
            return
        if power == "shield":
            self.power_picks[player_id] = {"power": "shield"}
            return
        target = data.get("targetID")
        if not isinstance(target, str) or target == player_id:
            return
        if self.room.player(target) is None:
            return
        self.power_picks[player_id] = {"power": power, "targetID": target}

    # ======================================================================
    # Scoring helpers
    # ======================================================================

    def _award(self, player_id: str, points: int) -> None:
        self.scores[player_id] = self.scores.get(player_id, 0) + points
        player = self.room.player(player_id)
        if player is not None:
            player.score = self.scores[player_id]

    def _ranks(self) -> dict[str, int]:
        ordered = sorted(self.scores.items(), key=lambda kv: kv[1], reverse=True)
        return {pid: i + 1 for i, (pid, _) in enumerate(ordered)}

    def _leader_by_score(self) -> str | None:
        ranks = self._ranks()
        for pid, rank in ranks.items():
            if rank == 1:
                return pid
        return None

    def _placement(self) -> list[str]:
        """Final order: finale winner, then tower height, then score."""
        ids = list(self.scores)
        order = {pid: i for i, pid in enumerate(ids)}
        ids.sort(key=lambda pid: (pid != self.winner_id,
                                  -self.rungs.get(pid, 0),
                                  -self.scores.get(pid, 0),
                                  order[pid]))
        return ids

    # ======================================================================
    # State
    # ======================================================================

    def _player_rows(self) -> list[dict]:
        ranks = self._ranks()
        return [
            {"id": p.id, "name": p.name,
             "score": self.scores.get(p.id, 0),
             "isHost": p.is_host, "isBot": p.is_bot,
             "connected": p.connected,
             "rank": ranks.get(p.id, 0),
             "prevRank": self.prev_ranks.get(p.id, ranks.get(p.id, 0)),
             "rung": self.rungs.get(p.id, 0)}
            for p in self.room.players
        ]

    def _question_visible(self) -> bool:
        return self.phase in ("question", "reveal", "finale_question",
                              "finale_reveal") and self.question is not None

    def _show_choices(self) -> bool:
        return self._question_visible() and (
            self.phase in ("reveal", "finale_reveal") or time.time() >= self.choices_at)

    def _is_reveal(self) -> bool:
        return self.phase in ("reveal", "finale_reveal")

    def public_state(self):
        visible = self._question_visible()
        category, text, choices = "", "", []
        if visible:
            category, text, choices, _ = self.question
        state = {
            "phase": self.phase,
            "deadline": self.deadline,
            "secondsLeft": self.seconds_left(),
            "phaseSeconds": self.phase_seconds,
            "round": self.round_no,
            "totalRounds": self.total_round_groups,
            "questionNumber": self.question_no,
            "totalQuestions": self.total_rounds,
            "custom": self.custom,
            "quizName": self.quiz_name,
            # Question (empty outside the question/reveal phases). These
            # keys are what the TV voice host speaks.
            "questionID": self.question_id if visible else "",
            "questionText": text,
            "choices": list(choices),
            "category": category if visible else self.chosen_category,
            "showChoices": self._show_choices(),
            "answeredPlayerIDs": list(self.answered.keys()) if visible else [],
            # Category vote.
            "categories": [{"name": c, "votes": n}
                           for c, n in zip(self.categories, self._vote_counts())],
            "votedPlayerIDs": list(self.votes.keys()),
            "chosenCategory": self.chosen_category,
            "chosenIndex": self.chosen_index,
            # Powers.
            "pickedPowerPlayerIDs": list(self.power_picks.keys()),
            "powerEvents": list(self.power_events),
            # Finale.
            "towerHeight": self.TOWER_HEIGHT,
            "finaleNumber": self.finale_no,
            "finaleTotal": self.finale_total,
            "finaleMoves": dict(self.finale_moves) if self._is_reveal() else {},
            "winnerID": self.winner_id if self.phase == "summary" else None,
            "players": self._player_rows(),
            "finished": self._finished,
        }
        if self._is_reveal() and self.question is not None:
            state["correctIndex"] = self.question[3]
            state["lastResults"] = list(self.last_results)
        if self.phase == "summary":
            state["results"] = self.results()
        return state

    def private_state(self, player_id):
        visible = self._question_visible()
        ranks = self._ranks()
        state = {
            "phase": self.phase,
            "deadline": self.deadline,
            "secondsLeft": self.seconds_left(),
            "phaseSeconds": self.phase_seconds,
            "round": self.round_no,
            "totalRounds": self.total_round_groups,
            "questionNumber": self.question_no,
            "totalQuestions": self.total_rounds,
            "score": self.scores.get(player_id, 0),
            "rank": ranks.get(player_id, 0),
            "playerCount": len(self.room.players),
            "custom": self.custom,
            "quizName": self.quiz_name,
            # Category vote.
            "categories": list(self.categories),
            "myVote": self.votes.get(player_id),
            "chosenCategory": self.chosen_category,
            # Powers.
            "powers": [dict(p) for p in POWERS],
            "rivals": [{"id": p.id, "name": p.name}
                       for p in self.room.players
                       if p.id != player_id and p.connected],
            "myPower": dict(self.power_picks[player_id])
            if player_id in self.power_picks else None,
            "hitBy": [dict(h) for h in self.hits.get(player_id, [])],
            "shieldBlocked": list(self.shield_blocks.get(player_id, [])),
            # Question.
            "questionID": self.question_id if visible else "",
            "questionText": self.question[1] if visible else "",
            "choices": list(self.question[2]) if visible else [],
            "category": self.question[0] if visible else self.chosen_category,
            "showChoices": self._show_choices(),
            "myAnswer": self.answered.get(player_id) if visible else None,
            "locked": visible and player_id in self.answered,
            # Finale.
            "rung": self.rungs.get(player_id, 0),
            "towerHeight": self.TOWER_HEIGHT,
            "finaleNumber": self.finale_no,
            "finaleTotal": self.finale_total,
            "winnerID": self.winner_id if self.phase == "summary" else None,
            "winnerName": (self.player_name(self.winner_id)
                           if self.phase == "summary" and self.winner_id else ""),
        }
        if self._is_reveal() and self.question is not None:
            correct = self.question[3]
            mine = self.answered.get(player_id)
            state["correctIndex"] = correct
            state["wasCorrect"] = mine is not None and mine == correct
            row = next((r for r in self.last_results
                        if r["playerID"] == player_id), None)
            state["pointsEarned"] = row["points"] if row else 0
            state["rungMove"] = self.finale_moves.get(player_id, 0)
        return state

    def is_over(self):
        return self._finished

    def results(self):
        rows = []
        for rank, pid in enumerate(self._placement(), start=1):
            rows.append({"playerID": pid, "name": self.player_name(pid),
                         "score": self.scores.get(pid, 0), "rank": rank,
                         "rung": self.rungs.get(pid, 0)})
        return rows

    def on_player_join(self, player):
        self.scores.setdefault(player.id, 0)
        self.rungs.setdefault(player.id, 0)

    def on_player_leave(self, player_id):
        # Their pending vote/pick stays (it was cast fairly); the early-end
        # checks only look at connected players, so nobody waits on them.
        pass
