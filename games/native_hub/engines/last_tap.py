"""Last Tap Standing: a run of quick-fire reflex rounds, each a different kind.

Every round is one of:

* ``reaction`` -- wait for a random countdown, tap the instant GO appears
  (tapping early is a false start);
* ``pump``     -- keep tapping: the most taps in a few seconds wins;
* ``colour``   -- the TV names a colour, tap that tile on your phone;
* ``grey``     -- tap every coloured tile, never a grey one;
* ``numbers``  -- tap 1, 2, 3 ... in order.

Everyone plays every round. The weakest player(s) lose a life; out of lives,
out of the game. Kinds are dealt from a shuffled bag, so a game never plays
the same kind twice in a row and every kind turns up before any repeats.

Tiles for colour / grey / numbers rounds are laid out per player (private
state), so nobody can copy the next phone's screen.
"""

from __future__ import annotations

import random
import time

from games.native_hub.engine import NativeGameEngine

KINDS = ("reaction", "pump", "colour", "grey", "numbers")

#: name, hex. Distinct enough for colour-blind players to rely on the name
#: written on the TV as well as the swatch.
COLOURS = [
    ("Red", "E53935"), ("Blue", "1E88E5"), ("Green", "43A047"),
    ("Yellow", "FDD835"), ("Orange", "FB8C00"), ("Purple", "8E24AA"),
    ("Pink", "EC407A"), ("Teal", "00ACC1"), ("Brown", "6D4C41"),
]
GREYS = ["9E9E9E", "757575", "BDBDBD", "616161", "A7A7A7"]

#: Headline and how-to line the TV and phones show for each kind.
TITLES = {
    "reaction": ("Fastest finger", "Wait for GO, then tap!"),
    "pump": ("Keep tapping!", "Tap as many times as you can"),
    "colour": ("Find the colour", "Tap the matching tile"),
    "grey": ("No greys!", "Tap every colour. Never tap a grey"),
    "numbers": ("Count up", "Tap 1, 2, 3 ... in order"),
}


class LastTapEngine(NativeGameEngine):
    game_id = "last_tap"
    min_players = 2
    max_players = 20
    # GO has to reach the phones the moment it happens, and the pump bars on
    # the TV want to move smoothly.
    tick_hz = 10.0

    ARM_MIN, ARM_MAX = 2.0, 5.0       # reaction countdown
    INTRO_SECONDS = 3.5               # the title card for the other kinds
    REVEAL_SECONDS = 5.0
    FALSE_START_PENALTY = 9.999
    #: How long the "go" phase lasts at most, per kind.
    LIMITS = {"reaction": 5.0, "pump": 8.0, "colour": 6.0, "grey": 12.0, "numbers": 15.0}
    MIN_TAP_GAP = 0.04                # a human cannot out-tap 25/s; macros can
    NUMBER_COUNT = 9
    GREY_COUNT = 4
    COLOUR_TILE_COUNT = 8
    NUMBERS_MISTAKE_SECONDS = 0.6

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.phase = "arming"
        self.kind = "reaction"
        self.round = 0
        self.go_at = 0.0
        self.go_shown_at = 0.0
        self.phase_until = 0.0
        self.alive: list[str] = []
        self.lives: dict[str, int] = {}
        self.max_lives = 2
        self._bag: list[str] = []
        self._last_kind = ""
        self.score_value: dict[str, float] = {}   # lower is better
        self.detail: dict[str, str] = {}
        self.finished_ids: set[str] = set()
        self.taps: dict[str, int] = {}
        self.last_tap_at: dict[str, float] = {}
        self.target: tuple[str, str] = COLOURS[0]
        self.tiles: dict[str, list[dict]] = {}
        self.cleared: dict[str, set[int]] = {}
        self.next_number: dict[str, int] = {}
        self.mistakes: dict[str, int] = {}
        self.failed: set[str] = set()
        self.eliminated_this_round: list[str] = []
        self.lost_life_this_round: list[str] = []
        self.out_order: list[str] = []
        self._finished = False

    # ---- lifecycle -----------------------------------------------------

    def start(self, players):
        self.alive = [p.id for p in players]
        self.max_lives = 3 if len(self.alive) <= 3 else 2
        self.lives = {pid: self.max_lives for pid in self.alive}
        self.round = 0
        self._next_round()

    def _next_kind(self) -> str:
        if not self._bag:
            bag = list(KINDS)
            random.shuffle(bag)
            if bag[0] == self._last_kind and len(bag) > 1:
                bag.append(bag.pop(0))
            self._bag = bag
        self._last_kind = self._bag.pop(0)
        return self._last_kind

    def _next_round(self):
        self.round += 1
        self.kind = self._next_kind()
        self.phase = "arming"
        self.score_value = {}
        self.detail = {}
        self.finished_ids = set()
        self.taps = {pid: 0 for pid in self.alive}
        self.last_tap_at = {}
        self.tiles = {}
        self.cleared = {}
        self.next_number = {}
        self.mistakes = {}
        self.failed = set()
        self.eliminated_this_round = []
        self.lost_life_this_round = []
        now = time.time()
        if self.kind == "reaction":
            self.go_at = now + random.uniform(self.ARM_MIN, self.ARM_MAX)
        else:
            self.go_at = now + self.INTRO_SECONDS
        if self.kind == "colour":
            self.target = random.choice(COLOURS)
        self.phase_until = 0.0

    def _go(self, now):
        self.phase = "go"
        # Timed from when GO is actually published, not when it was due.
        self.go_shown_at = now
        for pid in self.alive:
            self._deal_tiles(pid)

    def _deal_tiles(self, pid):
        if self.kind == "colour":
            names = [c for c in COLOURS if c[0] != self.target[0]]
            random.shuffle(names)
            chosen = names[:8] + [self.target]
            random.shuffle(chosen)
            self.tiles[pid] = [{"hex": hx, "name": nm, "ok": nm == self.target[0]}
                               for nm, hx in chosen]
        elif self.kind == "grey":
            colours = random.sample(COLOURS, self.COLOUR_TILE_COUNT)
            tiles = [{"hex": hx, "name": nm, "grey": False} for nm, hx in colours]
            tiles += [{"hex": random.choice(GREYS), "name": "Grey", "grey": True}
                      for _ in range(self.GREY_COUNT)]
            random.shuffle(tiles)
            self.tiles[pid] = tiles
            self.cleared[pid] = set()
        elif self.kind == "numbers":
            numbers = list(range(1, self.NUMBER_COUNT + 1))
            random.shuffle(numbers)
            self.tiles[pid] = [{"label": str(n), "n": n} for n in numbers]
            self.cleared[pid] = set()
            self.next_number[pid] = 1
            self.mistakes[pid] = 0

    # ---- actions ---------------------------------------------------------

    def handle_action(self, player_id, action, data):
        if action != "tap" or player_id not in self.alive:
            return
        if player_id in self.score_value:
            return
        now = time.time()
        data = data if isinstance(data, dict) else {}
        if self.kind == "reaction":
            if self.phase == "arming":
                # Tapped before GO -- recorded as a false start, not ignored,
                # so the player still sees a result instead of silence.
                self._record(player_id, self.FALSE_START_PENALTY, "too early")
            elif self.phase == "go":
                elapsed = max(0.0, now - self.go_shown_at)
                self._record(player_id, elapsed, f"{int(elapsed * 1000)} ms")
            return
        if self.phase != "go":
            return                        # taps before the round starts are free
        if self.kind == "pump":
            if now - self.last_tap_at.get(player_id, 0.0) < self.MIN_TAP_GAP:
                return
            self.last_tap_at[player_id] = now
            self.taps[player_id] = self.taps.get(player_id, 0) + 1
            return
        index = data.get("tile")
        tiles = self.tiles.get(player_id) or []
        if not isinstance(index, int) or isinstance(index, bool) or not 0 <= index < len(tiles):
            return
        tile = tiles[index]
        elapsed = max(0.0, now - self.go_shown_at)
        if self.kind == "colour":
            if tile["ok"]:
                self._record(player_id, elapsed, f"{elapsed:.2f} s")
            else:
                self._record(player_id, 50.0, f"tapped {tile['name'].lower()}")
                self.failed.add(player_id)
        elif self.kind == "grey":
            if tile["grey"]:
                self._record(player_id, 50.0, "tapped a grey")
                self.failed.add(player_id)
                return
            self.cleared[player_id].add(index)
            if len(self.cleared[player_id]) >= self.COLOUR_TILE_COUNT:
                self._record(player_id, elapsed, f"{elapsed:.2f} s")
        elif self.kind == "numbers":
            if index in self.cleared[player_id]:
                return
            if tile["n"] == self.next_number[player_id]:
                self.cleared[player_id].add(index)
                self.next_number[player_id] += 1
                if self.next_number[player_id] > self.NUMBER_COUNT:
                    total = elapsed + self.mistakes[player_id] * self.NUMBERS_MISTAKE_SECONDS
                    self._record(player_id, total, f"{total:.2f} s")
            else:
                self.mistakes[player_id] += 1

    def _record(self, pid, value, label):
        self.score_value[pid] = value
        self.detail[pid] = label
        self.finished_ids.add(pid)

    # ---- time ------------------------------------------------------------

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        if self.phase == "arming" and now >= self.go_at:
            self._go(now)
        elif self.phase == "go":
            limit = self.LIMITS[self.kind]
            everyone_in = self.kind != "pump" and all(p in self.score_value for p in self.alive)
            if everyone_in or now - self.go_shown_at > limit:
                self._resolve()
        elif self.phase == "reveal" and now >= self.phase_until:
            if len(self.alive) <= 1:
                self._finished = True
                self.phase = "final"
                self._crown_winner()
            else:
                self._next_round()

    def _crown_winner(self):
        """The last one standing ranks first, whatever the round points say."""
        if not self.alive:
            return
        top = max((p.score for p in self.room.players), default=0)
        winner = self.room.player(self.alive[0])
        if winner is not None:
            winner.score = top + 1

    def _unfinished_value(self, pid) -> tuple[float, str]:
        """Score for someone who ran out of time without finishing."""
        if self.kind == "reaction":
            return self.FALSE_START_PENALTY, "no tap"
        if self.kind == "colour":
            return 60.0, "no tap"
        if self.kind == "grey":
            left = self.COLOUR_TILE_COUNT - len(self.cleared.get(pid, ()))
            return 20.0 + left, f"{left} colours left"
        left = self.NUMBER_COUNT - len(self.cleared.get(pid, ()))
        return 30.0 + left + self.mistakes.get(pid, 0) * 0.1, f"stuck on {self.next_number.get(pid, 1)}"

    def _resolve(self):
        if self.kind == "pump":
            for pid in self.alive:
                taps = self.taps.get(pid, 0)
                self.score_value[pid] = 1000.0 - taps
                self.detail[pid] = f"{taps} taps"
        else:
            for pid in self.alive:
                if pid not in self.score_value:
                    value, label = self._unfinished_value(pid)
                    self.score_value[pid] = value
                    self.detail[pid] = label

        ranked = sorted(self.alive, key=lambda p: self.score_value[p])
        # The weakest 20% lose a life: at least one, never everyone.
        cut = max(1, round(len(ranked) * 0.2))
        cut = min(cut, len(ranked) - 1)
        survivors_rank, weakest = ranked[:-cut], ranked[-cut:]

        for rank, pid in enumerate(survivors_rank):
            player = self.room.player(pid)
            if player is not None:
                player.score += max(1, len(survivors_rank) - rank)

        self.lost_life_this_round = list(weakest)
        out = []
        for pid in weakest:
            self.lives[pid] = self.lives.get(pid, 1) - 1
            if self.lives[pid] <= 0:
                out.append(pid)
        self.eliminated_this_round = out
        self.out_order.extend(out)
        self.alive = [p for p in self.alive if p not in out]
        self.phase = "reveal"
        self.phase_until = time.time() + self.REVEAL_SECONDS

    # ---- state -----------------------------------------------------------

    def _progress(self) -> dict[str, float]:
        if self.kind == "pump":
            top = max(self.taps.values(), default=0)
            return {pid: (self.taps.get(pid, 0) / max(top, 20)) for pid in self.alive}
        if self.kind == "grey":
            return {pid: len(self.cleared.get(pid, ())) / self.COLOUR_TILE_COUNT
                    for pid in self.alive}
        if self.kind == "numbers":
            return {pid: len(self.cleared.get(pid, ())) / self.NUMBER_COUNT
                    for pid in self.alive}
        return {}

    def _seconds_left(self) -> float:
        if self.phase != "go":
            return 0.0
        return max(0.0, self.LIMITS[self.kind] - (time.time() - self.go_shown_at))

    def public_state(self):
        title, how = TITLES[self.kind]
        show_results = self.phase in ("reveal", "final")
        return {
            "phase": self.phase,
            "round": self.round,
            "kind": self.kind,
            "title": title,
            "howTo": how,
            "target": {"name": self.target[0], "hex": self.target[1]} if self.kind == "colour" else None,
            "secondsLeft": round(self._seconds_left(), 1),
            "introSeconds": max(0.0, round(self.go_at - time.time(), 1))
            if self.phase == "arming" and self.kind != "reaction" else 0.0,
            "aliveCount": len(self.alive),
            "alivePlayerIDs": self.alive,
            "eliminatedPlayerIDs": self.eliminated_this_round,
            "lostLifePlayerIDs": self.lost_life_this_round,
            "winner": self.alive[0] if self._finished and self.alive else None,
            "progress": self._progress() if self.phase == "go" else {},
            "results": [
                {"playerID": pid, "name": self.player_name(pid),
                 "detail": self.detail.get(pid, ""),
                 "ms": int(self.score_value[pid] * 1000) if self.kind == "reaction" else 0,
                 "falseStart": self.kind == "reaction"
                 and self.score_value[pid] >= self.FALSE_START_PENALTY,
                 "lives": self.lives.get(pid, 0)}
                for pid in sorted(self.score_value, key=lambda p: self.score_value[p])
            ] if show_results else [],
            "players": [
                {"id": p.id, "name": p.name, "score": p.score,
                 "isAlive": p.id in self.alive, "lives": self.lives.get(p.id, 0)}
                for p in self.room.players
            ],
            "maxLives": self.max_lives,
        }

    def private_state(self, player_id):
        alive = player_id in self.alive
        mine = self.score_value.get(player_id)
        can_tap = (alive and player_id not in self.score_value
                   and (self.phase == "go" or (self.phase == "arming" and self.kind == "reaction")))
        title, how = TITLES[self.kind]
        state = {
            "phase": self.phase,
            "kind": self.kind,
            "title": title,
            "howTo": how,
            "isAlive": alive,
            "canTap": can_tap,
            "round": self.round,
            "lives": self.lives.get(player_id, 0),
            "maxLives": self.max_lives,
            "secondsLeft": round(self._seconds_left(), 1),
            "myDetail": self.detail.get(player_id),
            "myMs": int(mine * 1000) if mine is not None and self.kind == "reaction" else None,
            "falseStart": self.kind == "reaction" and mine is not None
            and mine >= self.FALSE_START_PENALTY,
            "failed": player_id in self.failed,
            "target": {"name": self.target[0], "hex": self.target[1]} if self.kind == "colour" else None,
            "myTaps": self.taps.get(player_id, 0),
            "tiles": [],
        }
        if self.phase == "go" and alive and player_id not in self.score_value:
            cleared = self.cleared.get(player_id, set())
            if self.kind == "colour":
                state["tiles"] = [{"hex": t["hex"], "label": ""} for t in self.tiles.get(player_id, [])]
            elif self.kind == "grey":
                state["tiles"] = [{"hex": t["hex"], "label": "", "done": i in cleared}
                                  for i, t in enumerate(self.tiles.get(player_id, []))]
            elif self.kind == "numbers":
                state["tiles"] = [{"hex": "3949AB", "label": t["label"], "done": i in cleared}
                                  for i, t in enumerate(self.tiles.get(player_id, []))]
                state["nextNumber"] = self.next_number.get(player_id, 1)
        return state

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})
