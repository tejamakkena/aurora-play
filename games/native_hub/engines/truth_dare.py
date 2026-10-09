"""Truth or Dare for the TV: one phone runs the table, the TV reads it out.

Nobody else needs the app. The host scans the QR code once, types everyone's
name into the setup screen (phones that did join are added automatically), picks
a tone and taps Start. After that the TV is the show:

    choose   the TV asks "Priya, truth or dare?"; the host (or Priya's own
             phone) taps one
    prompt   the TV reads the card aloud; Priya answers or performs it; the
             host judges: Done / Skip, or "Caught lying" on a Truth
    punish   caught lying: a bigger forfeit dare, read out the same way

The deck never repeats: cards come from the content service, which remembers
what this table and these devices have already heard, and the engine also
keeps its own used list for the night. Turns are a shuffled bag, so everyone
goes once before anyone goes twice, and nobody gets two turns in a row.

The host can end the game at any time from the setup or play screen.
"""

import random

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines import _truthdare as D
from games import content_service as cs

MAX_NAME_LEN = 20
MAX_PARTICIPANTS = 12
MIN_PARTICIPANTS = 2

#: Points. Lying costs a point on top of the forfeit; skipping a forfeit costs
#: two, so "just take the punishment" is always the better move.
TRUTH_POINTS = 1
DARE_POINTS = 2
CAUGHT_PENALTY = 1
SKIP_PENALTY = 1
SKIP_PUNISH_PENALTY = 2


def _clean_name(raw) -> str:
    if not isinstance(raw, str):
        return ""
    return " ".join(raw.split())[:MAX_NAME_LEN]


def _payload(data) -> dict:
    return data if isinstance(data, dict) else {}


class TruthOrDareEngine(NativeGameEngine):
    game_id = "truth_or_dare"
    min_players = 1           # one phone can run the whole table
    max_players = 20

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.phase = "setup"                 # setup | choose | prompt | punish | over
        self.level = "family"
        self.participants: list[dict] = []   # {"id", "name", "score", "guest"}
        self.bag: list[str] = []             # ids still to go this lap
        self.current: str | None = None
        self.last_id: str | None = None
        self.kind: str | None = None         # truth | dare | punish
        self.prompt = ""
        self.switched = False                # one swap per turn
        self.turns = 0
        self.laps = 0
        self.used: set[str] = set()
        self.last_result: dict | None = None
        self.say_seq = 0
        self.say_text = ""
        self._guest_seq = 0
        self._ended = False

    # ---- lifecycle ----------------------------------------------------------

    def start(self, players):
        self.participants = []
        for p in players:
            if not p.is_bot:
                self._add_participant(p.id, p.name, guest=False)
        if len(self.participants) >= MIN_PARTICIPANTS:
            self.say("Add everyone's name, pick a level and press start.")
        else:
            self.say("Add everyone's name on the host phone, pick a level and press start.")

    def on_player_join(self, player):
        if self.phase in ("over",) or player.is_bot:
            return
        if not any(p["id"] == player.id for p in self.participants):
            self._add_participant(player.id, player.name, guest=False)

    def on_player_leave(self, player_id):
        self._remove_participant(player_id)

    def is_over(self):
        return self._ended

    def results(self):
        rows = sorted(self.participants, key=lambda p: -p["score"])
        out, rank, prev = [], 0, None
        for i, p in enumerate(rows, start=1):
            if p["score"] != prev:
                rank, prev = i, p["score"]
            out.append({"playerID": p["id"], "name": p["name"],
                        "score": p["score"], "rank": rank})
        return out

    # ---- participants --------------------------------------------------------

    def _name_taken(self, name: str) -> bool:
        key = name.casefold()
        return any(p["name"].casefold() == key for p in self.participants)

    def _add_participant(self, pid: str, name: str, guest: bool) -> bool:
        name = _clean_name(name)
        if not name or self._name_taken(name) or len(self.participants) >= MAX_PARTICIPANTS:
            return False
        self.participants.append({"id": pid, "name": name, "score": 0, "guest": guest})
        if self.phase in ("choose", "prompt", "punish") and pid not in self.bag:
            self.bag.append(pid)             # joins this lap, not the current turn
        return True

    def _remove_participant(self, pid: str) -> None:
        if not any(p["id"] == pid for p in self.participants):
            return
        self.participants = [p for p in self.participants if p["id"] != pid]
        if pid in self.bag:
            self.bag.remove(pid)
        if self.last_id == pid:
            self.last_id = None
        if self.current == pid and self.phase in ("choose", "prompt", "punish"):
            self.current = None
            self.kind, self.prompt = None, ""
            if len(self.participants) < MIN_PARTICIPANTS:
                self.phase = "setup"
                self.say("Not enough players. Add a name to carry on.")
            else:
                self._next_turn("")

    def _name(self, pid) -> str:
        for p in self.participants:
            if p["id"] == pid:
                return p["name"]
        return "Player"

    def _score(self, pid, delta: int) -> None:
        for p in self.participants:
            if p["id"] == pid:
                p["score"] = max(0, p["score"] + delta)

    # ---- speech --------------------------------------------------------------

    def say(self, text: str) -> None:
        """What the TV reads aloud. The sequence number lets it speak each
        line exactly once, even if the same text repeats."""
        self.say_seq += 1
        self.say_text = text

    # ---- deck ----------------------------------------------------------------

    def _draw(self, kind: str) -> str:
        """A card of ``kind`` (truth | dare | punish) at or below the level."""
        levels = D.LEVELS[: D.LEVELS.index(self.level) + 1]
        kinds = [f"td_{kind}_{lvl}" for lvl in levels]
        weights = [max(1, len(cs.all_items(k))) for k in kinds]
        order = random.choices(kinds, weights=weights, k=len(kinds) * 2)
        seen: set[str] = set()
        for k in order + kinds:
            if k in seen:
                continue
            seen.add(k)
            card = cs.pick_one(self.room, k, avoid=self.used)
            if card and cs.norm_key(card) not in self.used:
                self.used.add(cs.norm_key(card))
                return card
        # Everything at this level has been used this night: start over
        # rather than run dry, but still prefer what the table has not heard.
        self.used.clear()
        card = cs.pick_one(self.room, kinds[0]) or "Make everyone laugh in ten seconds."
        self.used.add(cs.norm_key(card))
        return card

    # ---- turns ---------------------------------------------------------------

    def _next_turn(self, lead_in: str) -> None:
        live = [p["id"] for p in self.participants]
        if len(live) < MIN_PARTICIPANTS:
            self.phase = "setup"
            self.current = None
            self.say("Not enough players. Add a name to carry on.")
            return
        self.bag = [pid for pid in self.bag if pid in live]
        if not self.bag:
            self.laps += 1
            self.bag = live[:]
            random.shuffle(self.bag)
            # No back-to-back turns across a lap boundary.
            if len(self.bag) > 1 and self.bag[0] == self.last_id:
                self.bag.append(self.bag.pop(0))
        self.current = self.bag.pop(0)
        self.last_id = self.current
        self.phase = "choose"
        self.kind, self.prompt = None, ""
        self.switched = False
        self.turns += 1
        self.say((lead_in + " " if lead_in else "") +
                 f"{self._name(self.current)}, truth or dare?")

    def _finish_turn(self, outcome: str, lead_in: str) -> None:
        self.last_result = {"playerID": self.current, "name": self._name(self.current),
                            "outcome": outcome}
        self._next_turn(lead_in)

    # ---- actions -------------------------------------------------------------

    def _is_host(self, player_id) -> bool:
        player = self.room.player(player_id)
        return bool(player and player.is_host)

    def handle_action(self, player_id, action, data):
        data = _payload(data)
        if self._ended:
            return
        if action == "end":
            if self._is_host(player_id):
                self._end()
            return
        if self.phase == "setup":
            self._setup_action(player_id, action, data)
            return
        if self.phase == "choose":
            if action == "choose" and self._may_act_for_current(player_id):
                self._choose(data.get("kind"))
            return
        if self.phase in ("prompt", "punish"):
            if action == "switch" and self._may_act_for_current(player_id):
                self._switch()
            elif action in ("done", "skip", "caught") and self._is_host(player_id):
                self._judge(action)

    def _may_act_for_current(self, player_id) -> bool:
        return self._is_host(player_id) or player_id == self.current

    def _setup_action(self, player_id, action, data):
        if not self._is_host(player_id):
            return
        if action == "add_names":
            raw = data.get("names", data.get("name"))
            names = raw if isinstance(raw, list) else [raw]
            for item in names:
                if not isinstance(item, str):
                    continue
                for part in item.replace("\n", ",").split(","):
                    self._guest_seq += 1
                    self._add_participant(f"g{self._guest_seq}", part, guest=True)
        elif action == "remove_name":
            self._remove_participant(str(data.get("id", "")))
        elif action == "set_level":
            level = data.get("level")
            if level in D.LEVELS:
                self.level = level
        elif action == "start_play":
            if len(self.participants) >= MIN_PARTICIPANTS:
                self._next_turn("Let's play truth or dare.")

    def _choose(self, kind):
        if kind not in ("truth", "dare"):
            return
        self.kind = kind
        self.prompt = self._draw(kind)
        self.phase = "prompt"
        self.say(f"{self._name(self.current)} chose {kind}. {self.prompt}")

    def _switch(self):
        if self.switched or self.kind not in ("truth", "dare"):
            return
        self.switched = True
        self.kind = "dare" if self.kind == "truth" else "truth"
        self.prompt = self._draw(self.kind)
        self.say(f"Switching to {self.kind}. {self.prompt}")

    def _judge(self, action):
        pid = self.current
        if pid is None:
            return
        name = self._name(pid)
        if self.phase == "punish":
            if action == "done":
                self._finish_turn("punished", f"{name} took the punishment.")
            elif action == "skip":
                self._score(pid, -SKIP_PUNISH_PENALTY)
                self._finish_turn("refused", f"{name} chickened out of the punishment.")
            return
        if self.kind == "truth":
            if action == "done":
                self._score(pid, TRUTH_POINTS)
                self._finish_turn("truth", f"Thank you {name}.")
            elif action == "caught":
                self._score(pid, -CAUGHT_PENALTY)
                self.kind = "punish"
                self.phase = "punish"
                self.prompt = self._draw("punish")
                self.say(f"Caught lying! {name}, your punishment. {self.prompt}")
            elif action == "skip":
                self._score(pid, -SKIP_PENALTY)
                self._finish_turn("skipped", f"{name} passed.")
        elif self.kind == "dare":
            if action == "done":
                self._score(pid, DARE_POINTS)
                self._finish_turn("dare", f"Well done {name}.")
            elif action == "skip":
                self._score(pid, -SKIP_PENALTY)
                self._finish_turn("skipped", f"{name} chickened out.")

    def _end(self):
        self.phase = "over"
        self._ended = True
        top = self.results()
        if top and top[0]["score"] > 0:
            winners = [r["name"] for r in top if r["rank"] == 1]
            self.say("Game over. " + " and ".join(winners) +
                     (" wins!" if len(winners) == 1 else " win!"))
        else:
            self.say("Game over. Thanks for playing!")

    # ---- state ---------------------------------------------------------------

    def _roster(self) -> list[dict]:
        return [{"id": p["id"], "name": p["name"], "score": p["score"], "guest": p["guest"]}
                for p in self.participants]

    def public_state(self):
        return {
            "phase": self.phase,
            "level": self.level,
            "levels": list(D.LEVELS),
            "participants": self._roster(),
            "minPlayers": MIN_PARTICIPANTS,
            "maxPlayers": MAX_PARTICIPANTS,
            "currentID": self.current,
            "currentName": self._name(self.current) if self.current else "",
            "kind": self.kind,
            "prompt": self.prompt,
            "canSwitch": self.phase == "prompt" and not self.switched
                         and self.kind in ("truth", "dare"),
            "turn": self.turns,
            "laps": self.laps,
            "lastResult": self.last_result,
            "say": {"seq": self.say_seq, "text": self.say_text},
        }

    def private_state(self, player_id):
        state = self.public_state()
        state.update({
            "isHost": self._is_host(player_id),
            "isMyTurn": self.current == player_id and self.phase in ("choose", "prompt", "punish"),
            "myPlayerID": player_id,
        })
        return state


ENGINES = {
    "truth_or_dare": TruthOrDareEngine,
}
