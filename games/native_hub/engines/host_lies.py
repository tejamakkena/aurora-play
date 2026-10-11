"""The Host Is Lying: a quiz where the quizmaster sometimes lies on purpose.

Each round the host states a "fact" with full confidence. Half the time (not
exactly half, and not predictably) the fact is false. Players do not need to
know the answer: they score by working out whether the HOST is bluffing,
using the same tells a person gives off when they are:

    hedging          "As far as anyone knows, ..."
    over-explaining  a justification nobody asked for
    saying it twice "Yes. Exactly that."
    stalling         a longer pause and a thinking-aloud opener
    talking fast     the line is simply delivered quicker

Rounds go: ``claim`` (the host speaks) -> ``grill`` (anyone can press the host,
who defends himself in the same voice, up to three times; the first presser is
the challenger) -> ``vote`` (every player locks in Trust or Liar, in secret) ->
``reveal`` (the truth, the tells that were actually used and who was fooled).

Tells are noisy on purpose. A lying host shows at least one tell most of the
time but not always, and an honest host shows a "decoy" tell some of the time,
so "tell means lie" is a decent guess and never a certainty. Tells also fade as
the game goes on, which makes later rounds harder.

The host's wording and delivery (speaking rate, pause before speaking) are sent
only to the TV, which does the talking. Phones get the statement text and, once
pressed, the defence text, never the delivery or the verdict.
"""

import random

from games import content_service as cs
from games.native_hub.engines import _hostlies as H
from games.native_hub.engines._bases import RoundBasedEngine

#: Scoring
TRUST_RIGHT = 100         # trusted a true claim
CATCH_LIE = 150           # called out a real lie
FALSE_ACCUSATION = -50    # called an honest host a liar
CHALLENGER_HIT = 100      # first to press the host, and it was a lie
CHALLENGER_MISS = -50     # first to press the host, and it was honest

MAX_PRESSES = 3
TELLS = ("hedge", "overexplain", "repeat", "stall", "rushed")


class HostLiesEngine(RoundBasedEngine):
    game_id = "host_lies"
    min_players = 2
    max_players = 20
    total_rounds = 8
    first_phase = "claim"
    phase_seconds = {"claim": 14, "grill": 16, "vote": 14, "reveal": 12}
    early_phases = ("vote",)

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.rng = random.Random()
        self.schedule: list[bool] = []       # per round: is the host lying?
        self.used: set[str] = set()
        self.item: tuple = ("", "", "")
        self.is_lie = False
        self.statement = ""
        self.tells_used: list[str] = []
        self.defences: list[dict] = []       # {"seq", "text", "rate", "preDelay"}
        self.pressers: list[str] = []
        self.votes: dict[str, str] = {}
        self.speech: dict = {"seq": 0, "text": "", "rate": 1.0, "preDelay": 0.0}
        self.reveal: dict | None = None
        self.fooled_total = 0
        self.rounds_lied = 0
        self.round_deltas: dict[str, int] = {}

    # ---- lifecycle ---------------------------------------------------------

    #: The TV does the speaking and the delivery numbers are not for phones.
    heavy_state = True

    def start(self, players):
        total = self.total_rounds
        lies = self.rng.choice([total // 2 - 1, total // 2, total // 2, total // 2 + 1])
        self.schedule = [True] * lies + [False] * (total - lies)
        self._shuffle_schedule()
        super().start(players)

    def _shuffle_schedule(self):
        """Random order, but never more than three of the same in a row."""
        for _ in range(50):
            self.rng.shuffle(self.schedule)
            run = 1
            ok = True
            for a, b in zip(self.schedule, self.schedule[1:]):
                run = run + 1 if a == b else 1
                if run > 3:
                    ok = False
                    break
            if ok:
                return

    # ---- tells -------------------------------------------------------------

    def tell_odds(self) -> tuple[float, float]:
        """(chance the host shows ANY tell when lying, when honest) this
        round. Lies get subtler and honest decoys more common as the game
        goes on, so later rounds are genuinely harder to read."""
        r = max(1, self.round) - 1
        return max(0.50, 0.85 - 0.05 * r), min(0.35, 0.15 + 0.03 * r)

    def pick_tells(self, lying: bool) -> list[str]:
        p_lie, p_true = self.tell_odds()
        if self.rng.random() >= (p_lie if lying else p_true):
            return []
        count = 2 if lying and self.rng.random() < 0.4 else 1
        return self.rng.sample(TELLS, count)

    def deliver(self, base: str, tells: list[str]) -> dict:
        """Turn plain text plus tells into spoken text and delivery numbers."""
        text = base
        rate, pre = 0.97, 0.5
        if "hedge" in tells:
            # Spoken aloud, so lower-casing a proper noun costs nothing; the
            # first person "I" is the one word that must keep its capital.
            keep = text.startswith("I ") or text.startswith("I'")
            first = text if keep or not text[:1].isupper() else text[0].lower() + text[1:]
            text = f"{self.rng.choice(H.HEDGES)} {first}"
        if "stall" in tells:
            text = f"{self.rng.choice(H.STALLS)} {text}"
            pre = 1.6
        if "repeat" in tells:
            text = f"{text} {self.rng.choice(H.REPEATS)}"
        if "overexplain" in tells:
            text = f"{text} {self.rng.choice(H.OVEREXPLAIN)}"
        if "rushed" in tells:
            rate, pre = 1.28, 0.0
        return {"text": text, "rate": rate, "preDelay": pre}

    def _say(self, base: str, tells: list[str], opener: str = "") -> dict:
        d = self.deliver(base, tells)
        if opener:
            d["text"] = f"{opener} {d['text']}"
        self.speech = {"seq": self.speech["seq"] + 1, **d}
        return self.speech

    # ---- phases --------------------------------------------------------------

    def begin_phase(self, phase):
        if phase == "claim":
            self._deal()
        elif phase == "reveal":
            self._reveal_speech()

    def _deal(self):
        self.votes = {}
        self.pressers = []
        self.defences = []
        self.reveal = None
        self.round_deltas = {}
        idx = min(self.round, len(self.schedule)) - 1
        self.is_lie = self.schedule[idx]
        card = cs.pick_one(self.room, "host_fact", avoid=self.used)
        self.item = card if card else H.FACTS[0]
        self.used.add(cs.norm_key(self.item[0]))
        self.statement = self.item[1] if self.is_lie else self.item[0]
        self.tells_used = self.pick_tells(self.is_lie)
        self._say(self.statement, self.tells_used, opener=self.rng.choice(H.OPENERS))

    def handle_action(self, player_id, action, data):
        if self.room.player(player_id) is None:
            return
        if action == "press" and self.phase == "grill":
            self._press(player_id)
        elif action == "vote" and self.phase == "vote":
            side = data.get("side") if isinstance(data, dict) else None
            if side in ("trust", "liar"):
                self.votes[player_id] = side
                self.submissions[player_id] = side

    def _press(self, player_id):
        if len(self.defences) >= MAX_PRESSES:
            return
        if self.pressers and self.pressers.count(player_id) >= 1:
            return                         # one press each
        self.pressers.append(player_id)
        tells = self.pick_tells(self.is_lie)
        self.tells_used = list(dict.fromkeys(self.tells_used + tells))
        line = self.rng.choice(H.DEFENCES)
        speech = self._say(line, tells)
        self.defences.append({"seq": speech["seq"], "text": speech["text"],
                              "by": self.player_name(player_id)})

    def resolve_phase(self, phase):
        if phase == "claim":
            return "grill"
        if phase == "grill":
            return "vote"
        if phase == "vote":
            self._score()
            return "reveal"
        return None

    def _score(self):
        fooled = 0
        liars = trusters = 0
        names = {"liar": [], "trust": []}
        for pid, side in self.votes.items():
            names[side].append(self.player_name(pid))
            liars += side == "liar"
            trusters += side == "trust"
            right = (side == "liar") == self.is_lie
            if right:
                delta = CATCH_LIE if self.is_lie else TRUST_RIGHT
            else:
                delta = FALSE_ACCUSATION if side == "liar" else 0
                fooled += 1
            self._pay(pid, delta)
        if self.pressers:
            first = self.pressers[0]
            self._pay(first, CHALLENGER_HIT if self.is_lie else CHALLENGER_MISS)
        self.fooled_total += fooled
        self.rounds_lied += 1 if self.is_lie else 0
        self.reveal = {
            "isLie": self.is_lie,
            "statement": self.statement,
            "truth": self.item[0],
            "why": self.item[2],
            "tells": [H.TELL_LABELS[t] for t in TELLS if t in self.tells_used],
            "liar": liars, "trust": trusters, "fooled": fooled,
            "liarNames": names["liar"], "trustNames": names["trust"],
            "challenger": self.player_name(self.pressers[0]) if self.pressers else "",
        }

    def _pay(self, pid, delta):
        if delta >= 0:
            self.award(pid, delta)
        else:
            self.scores[pid] = max(0, self.scores.get(pid, 0) + delta)
            player = self.room.player(pid)
            if player is not None:
                player.score = self.scores[pid]
        self.round_deltas[pid] = self.round_deltas.get(pid, 0) + delta

    def _reveal_speech(self):
        # Runs as the reveal phase begins, after the votes were scored.
        if self.reveal is None:
            return
        r = self.reveal
        if r["isLie"]:
            base = f"I lied! The truth is: {r['truth']} {r['why']}"
        else:
            base = f"That one was true! {r['why']}"
        self._say(base, [])

    # ---- state ---------------------------------------------------------------

    def public_state(self):
        state = self.base_public()
        state.update({
            "statement": self.statement if self.phase != "final" else "",
            "speech": dict(self.speech),
            "defences": [dict(d) for d in self.defences],
            "pressesLeft": MAX_PRESSES - len(self.defences),
            "votesSoFar": len(self.votes),
            "reveal": self.reveal if self.phase == "reveal" else None,
            "hostFooled": self.fooled_total,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "statement": self.statement,
            "defences": [{"seq": d["seq"], "text": d["text"], "by": d["by"]}
                         for d in self.defences],
            "canPress": (self.phase == "grill" and len(self.defences) < MAX_PRESSES
                         and player_id not in self.pressers),
            "pressesLeft": MAX_PRESSES - len(self.defences),
            "hasVoted": player_id in self.votes,
            "myVote": self.votes.get(player_id),
            "reveal": None,
        })
        if self.phase == "reveal" and self.reveal is not None:
            state["reveal"] = {**self.reveal,
                               "delta": self.round_deltas.get(player_id, 0)}
        return state

    def on_player_leave(self, player_id):
        super().on_player_leave(player_id)
        self.votes.pop(player_id, None)


ENGINES = {
    "host_lies": HostLiesEngine,
}
