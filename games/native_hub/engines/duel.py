"""Duel and co-op engines (2-6 players).

Defuse and Heist Escape are the only co-operative games in the catalog -- every
other game, old and new, is competitive.
"""

import math
import random
import time

from games.native_hub.engines._bases import TurnBasedEngine
from games.native_hub.engine import NativeGameEngine

WIRE_COLOURS = ["red", "blue", "yellow", "black", "white"]
SYMBOLS = ["Ϟ", "Ѭ", "Ω", "Ѯ", "҂", "Ѽ", "Ҩ", "Ω"]


class DefuseEngine(NativeGameEngine):
    """Co-op bomb defusal. The TV shows the bomb; the phones hold the manual.

    The person who can see the bomb cannot read the instructions, and the people
    with the instructions cannot see the bomb. That split is the entire game.
    """

    game_id = "defuse"
    min_players = 2
    max_players = 6

    FUSE_SECONDS = 300
    MAX_STRIKES = 3

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.modules: list[dict] = []
        self.module_index = 0
        self.strikes = 0
        self.deadline = 0.0
        self.defuser: str | None = None
        self.won = False
        self._finished = False
        self.log: list[str] = []

    def start(self, players):
        # Random, so "Play Again" hands the bomb to someone new.
        self.defuser = random.choice(players).id if players else None
        self.deadline = time.time() + self.FUSE_SECONDS
        self.modules = [self._wires(), self._button(), self._symbols(), self._wires()]
        self.module_index = 0

    # ---- module generation -------------------------------------------------

    def _wires(self):
        count = random.randint(3, 5)
        wires = [random.choice(WIRE_COLOURS) for _ in range(count)]
        # Rule: if there is exactly one red, cut it; otherwise cut the last wire.
        reds = [i for i, w in enumerate(wires) if w == "red"]
        answer = reds[0] if len(reds) == 1 else count - 1
        return {
            "type": "wires", "wires": wires, "answer": answer, "solved": False,
            "manual": [
                "WIRES: If there is exactly one RED wire, cut the red wire.",
                "Otherwise, cut the LAST wire.",
            ],
        }

    def _button(self):
        colour = random.choice(["red", "blue", "yellow", "white"])
        label = random.choice(["HOLD", "PRESS", "ABORT", "DETONATE"])
        # Rule: blue+ABORT or red+HOLD means hold; otherwise tap.
        hold = (colour == "blue" and label == "ABORT") or (colour == "red" and label == "HOLD")
        return {
            "type": "button", "colour": colour, "label": label,
            "answer": "hold" if hold else "tap", "solved": False,
            "manual": [
                "BUTTON: If the button is BLUE and says ABORT, HOLD it.",
                "If the button is RED and says HOLD, HOLD it.",
                "Otherwise, TAP it.",
            ],
        }

    def _symbols(self):
        shown = random.sample(SYMBOLS, 4)
        order = sorted(range(4), key=lambda i: SYMBOLS.index(shown[i]))
        return {
            "type": "symbols", "symbols": shown, "answer": order[0], "solved": False,
            "manual": [
                "SYMBOLS: Press the symbol that appears EARLIEST in this list:",
                " ".join(SYMBOLS),
            ],
        }

    # ---- play --------------------------------------------------------------

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def current_module(self):
        if self.module_index < len(self.modules):
            return self.modules[self.module_index]
        return None

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        module = self.current_module()
        if module is None:
            return
        # Only the defuser interacts with the bomb; everyone else reads.
        if player_id != self.defuser:
            return

        correct = False
        if action == "cut" and module["type"] == "wires":
            correct = data.get("index") == module["answer"]
        elif action == "button" and module["type"] == "button":
            correct = data.get("press") == module["answer"]
        elif action == "symbol" and module["type"] == "symbols":
            correct = data.get("index") == module["answer"]
        else:
            return

        if correct:
            module["solved"] = True
            self.log.append(f"Module {self.module_index + 1} defused")
            self.module_index += 1
            if self.module_index >= len(self.modules):
                self.won = True
                self._finished = True
        else:
            self.strikes += 1
            self.log.append(f"Strike {self.strikes}")
            if self.strikes >= self.MAX_STRIKES:
                self._finished = True

    def tick(self, dt):
        if not self._finished and self.deadline and time.time() >= self.deadline:
            self._finished = True

    def public_state(self):
        module = self.current_module()
        return {
            "secondsLeft": self.seconds_left(),
            "strikes": self.strikes,
            "maxStrikes": self.MAX_STRIKES,
            "moduleIndex": self.module_index,
            "moduleCount": len(self.modules),
            # The bomb face: visible to everyone, but useless without the manual.
            "module": {
                k: v for k, v in (module or {}).items()
                if k not in ("answer", "manual")
            },
            "won": self.won,
            "finished": self._finished,
            "log": self.log[-5:],
            "defuserName": self.player_name(self.defuser) if self.defuser else "",
        }

    def private_state(self, player_id):
        module = self.current_module()
        is_defuser = player_id == self.defuser
        return {
            "isDefuser": is_defuser,
            "secondsLeft": self.seconds_left(),
            "strikes": self.strikes,
            # The defuser gets the controls; everyone else gets the instructions.
            "module": {k: v for k, v in (module or {}).items()
                       if k not in ("answer", "manual")} if is_defuser else {},
            "manual": [] if is_defuser else (module or {}).get("manual", []),
            "moduleType": (module or {}).get("type", ""),
            "won": self.won,
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        # Co-op: everyone shares the outcome.
        score = 1000 if self.won else 0
        return self.ranked_results({p.id: score for p in self.room.players})


class BattleshipEngine(TurnBasedEngine):
    """Private fleet on the phone, shared hit/miss grid on the TV."""

    game_id = "battleship"
    min_players = 2
    max_players = 2
    turn_seconds = 45

    SIZE = 8
    FLEET = [4, 3, 3, 2]

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.fleets: dict[str, list[list[int]]] = {}   # player -> ship cell lists
        self.shots: dict[str, dict[int, str]] = {}     # player -> {cell: hit|miss}

    def setup(self):
        for pid in self.order:
            self.fleets[pid] = self._random_fleet()
            self.shots[pid] = {}

    def _random_fleet(self):
        occupied: set[int] = set()
        ships = []
        for length in self.FLEET:
            for _ in range(200):
                horizontal = random.random() < 0.5
                if horizontal:
                    row = random.randrange(self.SIZE)
                    col = random.randrange(self.SIZE - length + 1)
                    cells = [row * self.SIZE + col + i for i in range(length)]
                else:
                    row = random.randrange(self.SIZE - length + 1)
                    col = random.randrange(self.SIZE)
                    cells = [(row + i) * self.SIZE + col for i in range(length)]
                if not occupied.intersection(cells):
                    occupied.update(cells)
                    ships.append(cells)
                    break
        return ships

    def _opponent(self, player_id):
        return next((p for p in self.order if p != player_id), None)

    def handle_action(self, player_id, action, data):
        if self._finished or action != "fire" or not self.is_my_turn(player_id):
            return
        cell = data.get("cell")
        if not isinstance(cell, int) or not 0 <= cell < self.SIZE * self.SIZE:
            return
        if cell in self.shots[player_id]:
            return

        target = self._opponent(player_id)
        if target is None:
            return

        hit = any(cell in ship for ship in self.fleets[target])
        self.shots[player_id][cell] = "hit" if hit else "miss"

        if hit:
            self.scores[player_id] = self.scores.get(player_id, 0) + 1
            if self._all_sunk(target, player_id):
                self.finish(winner=player_id)
                return
            self.reset_turn_clock()
            return          # a hit earns another shot (with a fresh clock)
        self.next_turn()

    def _all_sunk(self, owner, shooter):
        cells = {c for ship in self.fleets[owner] for c in ship}
        return cells.issubset({c for c, r in self.shots[shooter].items() if r == "hit"})

    def _sunk_ships(self, owner, shooter):
        hits = {c for c, r in self.shots[shooter].items() if r == "hit"}
        return sum(1 for ship in self.fleets[owner] if set(ship).issubset(hits))

    def public_state(self):
        state = self.base_public()
        state.update({
            "size": self.SIZE,
            # Only shot results are public -- never ship positions.
            "boards": [
                {
                    "ownerID": pid,
                    "ownerName": self.player_name(pid),
                    "shots": [{"cell": c, "result": r}
                              for c, r in self.shots.get(pid, {}).items()],
                    "sunk": self._sunk_ships(self._opponent(pid), pid)
                            if self._opponent(pid) else 0,
                }
                for pid in self.order
            ],
            "fleetSizes": self.FLEET,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        opponent = self._opponent(player_id)
        state.update({
            "size": self.SIZE,
            # Your own ships, and only yours.
            "myShips": self.fleets.get(player_id, []),
            "incoming": [
                {"cell": c, "result": r}
                for c, r in self.shots.get(opponent, {}).items()
            ] if opponent else [],
            "myShots": [{"cell": c, "result": r}
                        for c, r in self.shots.get(player_id, {}).items()],
            "winner": self.winner,
        })
        return state


class AirHockeyEngine(NativeGameEngine):
    """Real-time two-player puck. Server-authoritative at 30 Hz."""

    game_id = "air_hockey"
    min_players = 2
    max_players = 2
    tick_hz = 30.0
    heavy_state = True          # 30 Hz payloads go to the TV only

    W, H = 100.0, 160.0
    PADDLE_W = 18.0
    PUCK_R = 3.0
    WIN_SCORE = 7
    MAX_SPEED = 90.0

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.paddles: dict[str, float] = {}
        self.scores: dict[str, int] = {}
        self.px = self.W / 2
        self.py = self.H / 2
        self.vx = 0.0
        self.vy = 0.0
        self._finished = False
        self.serve_at = 0.0

    def start(self, players):
        self.paddles = {p.id: self.W / 2 for p in players}
        self.scores = {p.id: 0 for p in players}
        self._serve()

    def _serve(self):
        self.px, self.py = self.W / 2, self.H / 2
        angle = random.uniform(-0.5, 0.5) + random.choice([0, math.pi])
        speed = 45.0
        self.vx = math.sin(angle) * speed
        self.vy = math.cos(angle) * speed
        self.serve_at = time.time() + 1.0        # brief pause before it moves

    def handle_action(self, player_id, action, data):
        if action == "paddle" and player_id in self.paddles:
            x = data.get("x")
            if isinstance(x, (int, float)):
                self.paddles[player_id] = max(self.PADDLE_W / 2,
                                              min(self.W - self.PADDLE_W / 2, float(x)))

    def tick(self, dt):
        if self._finished or time.time() < self.serve_at:
            return
        dt = min(dt, 0.05)          # clamp so a stalled thread can't teleport the puck

        self.px += self.vx * dt
        self.py += self.vy * dt

        # Side walls
        if self.px <= self.PUCK_R:
            self.px, self.vx = self.PUCK_R, abs(self.vx)
        elif self.px >= self.W - self.PUCK_R:
            self.px, self.vx = self.W - self.PUCK_R, -abs(self.vx)

        ids = list(self.paddles.keys())
        if len(ids) < 2:
            return
        top_id, bottom_id = ids[0], ids[1]

        # Paddles sit 6 units in from each end.
        if self.py <= 6 + self.PUCK_R and self.vy < 0:
            if abs(self.px - self.paddles[top_id]) <= self.PADDLE_W / 2:
                self._bounce(top_id, 1)
            elif self.py <= 0:
                self._goal(bottom_id)
        elif self.py >= self.H - 6 - self.PUCK_R and self.vy > 0:
            if abs(self.px - self.paddles[bottom_id]) <= self.PADDLE_W / 2:
                self._bounce(bottom_id, -1)
            elif self.py >= self.H:
                self._goal(top_id)

    def _bounce(self, paddle_id, direction):
        offset = (self.px - self.paddles[paddle_id]) / (self.PADDLE_W / 2)
        speed = min(self.MAX_SPEED, math.hypot(self.vx, self.vy) * 1.06)
        angle = offset * 0.9
        self.vx = math.sin(angle) * speed
        self.vy = direction * abs(math.cos(angle)) * speed
        self.py = 6 + self.PUCK_R if direction > 0 else self.H - 6 - self.PUCK_R

    def _goal(self, scorer):
        self.scores[scorer] = self.scores.get(scorer, 0) + 1
        player = self.room.player(scorer)
        if player is not None:
            player.score = self.scores[scorer]
        if self.scores[scorer] >= self.WIN_SCORE:
            self._finished = True
        else:
            self._serve()

    def public_state(self):
        return {
            "width": self.W, "height": self.H,
            "puck": {"x": round(self.px, 2), "y": round(self.py, 2)},
            "paddles": [
                {"playerID": pid, "name": self.player_name(pid),
                 "x": round(x, 2), "score": self.scores.get(pid, 0)}
                for pid, x in self.paddles.items()
            ],
            "paddleWidth": self.PADDLE_W,
            "winScore": self.WIN_SCORE,
            "finished": self._finished,
        }

    def private_state(self, player_id):
        ids = list(self.paddles.keys())
        return {
            "myX": self.paddles.get(player_id, self.W / 2),
            "width": self.W,
            "isTop": bool(ids) and ids[0] == player_id,
            "score": self.scores.get(player_id, 0),
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.scores)


class HeistEscapeEngine(NativeGameEngine):
    """Co-op vault escape. Each phone holds one fragment of the map.

    No single player can see the route -- they have to describe their piece and
    agree on a path out loud.
    """

    game_id = "heist_escape"
    min_players = 2
    max_players = 4

    SIZE = 7
    ESCAPE_SECONDS = 240

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.walls: set[tuple] = set()
        self.path: list[int] = []
        self.pos = 0
        self.exit_cell = 0
        self.deadline = 0.0
        self.fragments: dict[str, list[int]] = {}
        self.won = False
        self._finished = False
        self.trail: list[int] = []

    def start(self, players):
        self._build_maze()
        self.pos = 0
        self.trail = [0]
        self.exit_cell = self.SIZE * self.SIZE - 1
        self.deadline = time.time() + self.ESCAPE_SECONDS
        self._split_map(players)

    def _build_maze(self):
        # A guaranteed-solvable maze: carve the solution path first, then add
        # walls only where they cannot block it.
        self.walls = set()
        cell = 0
        path = [0]
        while cell != self.SIZE * self.SIZE - 1:
            row, col = divmod(cell, self.SIZE)
            options = []
            if col < self.SIZE - 1:
                options.append(cell + 1)
            if row < self.SIZE - 1:
                options.append(cell + self.SIZE)
            cell = random.choice(options)
            path.append(cell)
        self.path = path

        safe = set(path)
        for _ in range(self.SIZE * 3):
            a = random.randrange(self.SIZE * self.SIZE)
            row, col = divmod(a, self.SIZE)
            neighbours = []
            if col < self.SIZE - 1:
                neighbours.append(a + 1)
            if row < self.SIZE - 1:
                neighbours.append(a + self.SIZE)
            if not neighbours:
                continue
            b = random.choice(neighbours)
            # Never wall off two consecutive cells of the solution.
            if a in safe and b in safe and abs(path.index(a) - path.index(b)) == 1:
                continue
            self.walls.add((min(a, b), max(a, b)))

    def _split_map(self, players):
        """Deal the walls out so no one player can see the whole maze."""
        wall_list = list(self.walls)
        random.shuffle(wall_list)
        self.fragments = {p.id: [] for p in players}
        ids = list(self.fragments)
        for i, wall in enumerate(wall_list):
            self.fragments[ids[i % len(ids)]].append(wall)

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def handle_action(self, player_id, action, data):
        if self._finished or action != "move":
            return
        direction = data.get("direction")
        row, col = divmod(self.pos, self.SIZE)
        target = None
        if direction == "up" and row > 0:
            target = self.pos - self.SIZE
        elif direction == "down" and row < self.SIZE - 1:
            target = self.pos + self.SIZE
        elif direction == "left" and col > 0:
            target = self.pos - 1
        elif direction == "right" and col < self.SIZE - 1:
            target = self.pos + 1
        if target is None:
            return

        if (min(self.pos, target), max(self.pos, target)) in self.walls:
            # Hitting a wall costs time rather than ending the run.
            self.deadline -= 10
            return

        self.pos = target
        self.trail.append(target)
        if self.pos == self.exit_cell:
            self.won = True
            self._finished = True

    def tick(self, dt):
        if not self._finished and self.deadline and time.time() >= self.deadline:
            self._finished = True

    def public_state(self):
        return {
            "size": self.SIZE,
            "position": self.pos,
            "exitCell": self.exit_cell,
            "trail": self.trail[-12:],
            "secondsLeft": self.seconds_left(),
            "won": self.won,
            "finished": self._finished,
            # The maze itself is never public -- only where the team has been.
            "players": [{"id": p.id, "name": p.name} for p in self.room.players],
        }

    def private_state(self, player_id):
        return {
            "size": self.SIZE,
            "position": self.pos,
            "exitCell": self.exit_cell,
            # Only this player's slice of the wall map.
            "myWalls": [list(w) for w in self.fragments.get(player_id, [])],
            "secondsLeft": self.seconds_left(),
            "won": self.won,
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        score = max(0, self.seconds_left()) if self.won else 0
        return self.ranked_results({p.id: score for p in self.room.players})


class LudoEngine(TurnBasedEngine):
    """Four-token Ludo. Shake the phone to roll, tap to choose a token."""

    game_id = "ludo"
    min_players = 2
    max_players = 4
    turn_seconds = 40

    TRACK = 52
    HOME_RUN = 6
    TOKENS = 4
    START_OFFSET = 13           # each colour enters the track 13 cells apart

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.tokens: dict[str, list[int]] = {}   # -1 = in yard, 0..51 track, 100+ home run
        self.die = 0
        self.rolled = False
        self.seats: dict[str, int] = {}

    def setup(self):
        for seat, pid in enumerate(self.order):
            self.tokens[pid] = [-1] * self.TOKENS
            self.seats[pid] = seat

    def _entry(self, player_id):
        return self.seats.get(player_id, 0) * self.START_OFFSET

    def _abs_pos(self, player_id, value):
        """Map a token's own-track value onto the shared board."""
        if value < 0 or value >= 100:
            return None
        return (self._entry(player_id) + value) % self.TRACK

    def handle_action(self, player_id, action, data):
        if self._finished or not self.is_my_turn(player_id):
            return

        if action == "roll" and not self.rolled:
            self.die = random.randint(1, 6)
            self.rolled = True
            legal = self._legal_moves(player_id)
            if not legal:
                # Nothing playable -- pass rather than stalling the table.
                self._end_turn(extra=False)
            elif len({self.tokens[player_id][i] for i in legal}) == 1:
                # Only one real choice (one movable token, or several
                # identical yard tokens on a 6): play it, no extra tap.
                self._move(player_id, legal[0])
            return

        if action == "move" and self.rolled:
            idx = data.get("token")
            if not isinstance(idx, int) or idx not in self._legal_moves(player_id):
                return
            self._move(player_id, idx)

    def _move(self, player_id, idx):
        captured = self._apply_move(player_id, idx)
        if self._has_won(player_id):
            self.finish(winner=player_id)
            return
        self._end_turn(extra=(self.die == 6 or captured))

    def _legal_moves(self, player_id):
        moves = []
        for i, value in enumerate(self.tokens[player_id]):
            if value == -1:
                if self.die == 6:
                    moves.append(i)
            elif value >= 100:
                if value - 100 + self.die < self.HOME_RUN:
                    moves.append(i)
            else:
                if value + self.die <= self.TRACK + self.HOME_RUN:
                    moves.append(i)
        return moves

    def _apply_move(self, player_id, idx):
        value = self.tokens[player_id][idx]
        if value == -1:
            self.tokens[player_id][idx] = 0
            new_value = 0
        elif value >= 100:
            self.tokens[player_id][idx] = value + self.die
            return False
        else:
            new_value = value + self.die
            if new_value >= self.TRACK:
                self.tokens[player_id][idx] = 100 + (new_value - self.TRACK)
                return False
            self.tokens[player_id][idx] = new_value

        # Capture: any opposing token on the same board square goes home.
        landed = self._abs_pos(player_id, self.tokens[player_id][idx])
        captured = False
        for other, toks in self.tokens.items():
            if other == player_id:
                continue
            for j, v in enumerate(toks):
                if v >= 0 and v < 100 and self._abs_pos(other, v) == landed:
                    toks[j] = -1
                    captured = True
        if captured:
            self.scores[player_id] = self.scores.get(player_id, 0) + 1
        return captured

    def _has_won(self, player_id):
        return all(v >= 100 + self.HOME_RUN - 1 for v in self.tokens[player_id])

    def _end_turn(self, extra):
        # `die` keeps the last roll so the TV and phones can still show it;
        # `rolled` is what gates the next roll/move.
        self.rolled = False
        if not extra:
            self.next_turn()
        else:
            self.reset_turn_clock()

    def on_turn_timeout(self):
        self.rolled = False
        self.die = 0
        super().on_turn_timeout()

    def public_state(self):
        state = self.base_public()
        state.update({
            "die": self.die,
            "rolled": self.rolled,
            "track": self.TRACK,
            "homeRun": self.HOME_RUN,
            "seats": [
                {"playerID": pid, "seat": seat, "name": self.player_name(pid),
                 "tokens": self.tokens.get(pid, []),
                 "absolute": [self._abs_pos(pid, v) for v in self.tokens.get(pid, [])]}
                for pid, seat in self.seats.items()
            ],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "die": self.die,
            "rolled": self.rolled,
            "canRoll": self.is_my_turn(player_id) and not self.rolled,
            "myTokens": self.tokens.get(player_id, []),
            "legalMoves": self._legal_moves(player_id) if (
                self.is_my_turn(player_id) and self.rolled) else [],
            "seat": self.seats.get(player_id, 0),
        })
        return state


class CarromEngine(TurnBasedEngine):
    """Flick the striker to pocket coins. Aim and power come from a phone drag."""

    game_id = "carrom"
    min_players = 2
    max_players = 4
    turn_seconds = 45

    BOARD = 100.0
    POCKET_R = 8.0
    COIN_R = 2.5
    STRIKER_R = 3.2
    STRIKER_Y = 88.0
    TARGET_SCORE = 6
    #: How many coins one shot can knock on in a chain.
    MAX_CHAIN = 12
    #: Every game ends: after this many shots each, highest score wins.
    SHOTS_PER_PLAYER = 10

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.coins: list[dict] = []
        self.striker_x = 50.0
        self.last_shot: dict = {}
        self.shots_taken = 0
        self._travel_budget = 0

    def setup(self):
        # Nine white, nine black, one queen, ringed around the centre.
        self.coins = [{"id": 0, "x": 50.0, "y": 50.0, "kind": "queen", "potted": False}]
        cid = 1
        for ring, (count, radius) in enumerate(((6, 6.0), (12, 11.0))):
            for i in range(count):
                angle = 2 * math.pi * i / count
                self.coins.append({
                    "id": cid,
                    "x": 50.0 + math.cos(angle) * radius,
                    "y": 50.0 + math.sin(angle) * radius,
                    "kind": "white" if cid % 2 else "black",
                    "potted": False,
                })
                cid += 1

    def handle_action(self, player_id, action, data):
        if self._finished or not self.is_my_turn(player_id):
            return
        if action == "position":
            x = data.get("x")
            if isinstance(x, (int, float)):
                self.striker_x = max(15.0, min(85.0, float(x)))
            return
        if action != "flick":
            return

        angle = data.get("angle")
        power = data.get("power")
        if not isinstance(angle, (int, float)) or not isinstance(power, (int, float)):
            return
        self._resolve_shot(player_id, float(angle), max(0.0, min(1.0, float(power))))

    def _resolve_shot(self, player_id, angle, power):
        """Deterministic top-down shot: the striker travels until it hits a
        coin, which takes the energy along the contact normal, bounces off
        the cushions, can knock other coins on, and drops if its path
        crosses a pocket. Kept server-side so the TV board is always right.
        """
        self.shots_taken += 1
        self._travel_budget = 80
        dx, dy = math.sin(angle), -math.cos(angle)
        reach = 30.0 + power * 150.0
        potted: list[dict] = []
        striker_potted = self._travel(self.striker_x, self.STRIKER_Y, dx, dy, reach,
                                      self.STRIKER_R, None, 0, potted)

        gained = sum(3 if c["kind"] == "queen" else 1 for c in potted)
        foul = striker_potted
        if foul:
            gained -= 1                       # pocketing the striker costs a point
        if gained:
            self.scores[player_id] = max(0, self.scores.get(player_id, 0) + gained)
            player = self.room.player(player_id)
            if player is not None:
                player.score = self.scores[player_id]

        self.last_shot = {
            "playerID": player_id, "angle": angle, "power": power,
            "potted": [c["id"] for c in potted], "gained": gained, "foul": foul,
        }

        if self.scores.get(player_id, 0) >= self.TARGET_SCORE:
            self.finish(winner=player_id)
            return
        if all(c["potted"] for c in self.coins) or self.shots_taken >= self.max_shots():
            self._finish_on_points()
            return
        if potted and not foul:
            self.reset_turn_clock()           # potting keeps the turn
        else:
            self.next_turn()

    def max_shots(self):
        return self.SHOTS_PER_PLAYER * max(1, len(self.order))

    def _finish_on_points(self):
        best = max(self.order, key=lambda pid: self.scores.get(pid, 0)) if self.order else None
        top = self.scores.get(best, 0) if best else 0
        leaders = [pid for pid in self.order if self.scores.get(pid, 0) == top]
        self.finish(winner=best if len(leaders) == 1 else None)

    def _travel(self, x, y, ux, uy, dist, radius, coin, depth, potted):
        """Move a body along (ux, uy) for ``dist`` units, resolving cushion
        bounces, pockets and equal-mass collisions (the struck coin takes
        the normal component, the hitter carries on along the tangent).
        Returns True if this was the striker and it fell in a pocket."""
        self._travel_budget -= 1
        step = 0.5
        travelled = 0.0
        lo, hi = radius, self.BOARD - radius
        while travelled < dist:
            x += ux * step
            y += uy * step
            travelled += step
            # Cushions: reflect and lose a little energy.
            if x < lo or x > hi:
                x = lo + (lo - x) if x < lo else hi - (x - hi)
                ux = -ux
                dist -= (dist - travelled) * 0.2
            if y < lo or y > hi:
                y = lo + (lo - y) if y < lo else hi - (y - hi)
                uy = -uy
                dist -= (dist - travelled) * 0.2
            if self._in_pocket(x, y):
                if coin is not None:
                    coin["potted"] = True
                    potted.append(coin)
                    return False
                return True
            for other in self.coins:
                if other["potted"] or other is coin:
                    continue
                gap = math.hypot(other["x"] - x, other["y"] - y)
                if gap >= radius + self.COIN_R:
                    continue
                nx, ny = (other["x"] - x) / (gap or 1), (other["y"] - y) / (gap or 1)
                along = nx * ux + ny * uy
                if along <= 0:
                    continue                  # already moving apart
                remaining = (dist - travelled) * 0.92
                if coin is not None:
                    coin["x"], coin["y"] = x, y
                if self._travel_budget <= 0 or depth >= self.MAX_CHAIN:
                    return False
                self._travel(other["x"], other["y"], nx, ny, remaining * along + 1.0,
                             self.COIN_R, other, depth + 1, potted)
                tx, ty = ux - along * nx, uy - along * ny
                tn = math.hypot(tx, ty)
                if tn < 0.05:
                    return False              # head-on: the hitter stops dead
                return self._travel(x, y, tx / tn, ty / tn, remaining * tn,
                                    radius, coin, depth + 1, potted)
        if coin is not None:
            coin["x"], coin["y"] = round(x, 2), round(y, 2)
        return False

    def _in_pocket(self, x, y):
        for px, py in ((0, 0), (0, self.BOARD), (self.BOARD, 0), (self.BOARD, self.BOARD)):
            if math.hypot(x - px, y - py) < self.POCKET_R:
                return True
        return False

    def public_state(self):
        state = self.base_public()
        state.update({
            "board": self.BOARD,
            "coins": [
                {"id": c["id"], "x": round(c["x"], 1), "y": round(c["y"], 1),
                 "kind": c["kind"]}
                for c in self.coins if not c["potted"]
            ],
            "strikerX": round(self.striker_x, 1),
            "lastShot": self.last_shot,
            "targetScore": self.TARGET_SCORE,
            "shotsLeft": max(0, self.max_shots() - self.shots_taken),
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "canFlick": self.is_my_turn(player_id),
            "strikerX": round(self.striker_x, 1),
            "targetScore": self.TARGET_SCORE,
        })
        return state


class TeenPattiEngine(TurnBasedEngine):
    """Three-card Indian poker. Blind play costs half, which is the whole bluff."""

    game_id = "teen_patti"
    min_players = 2
    max_players = 8
    turn_seconds = 40

    ANTE = 10
    MAX_ROUNDS = 20

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.hands: dict[str, list[dict]] = {}
        self.chips: dict[str, int] = {}
        self.stakes: dict[str, int] = {}
        self.folded: set[str] = set()
        self.blind: set[str] = set()
        self.pot = 0
        self.current_stake = self.ANTE
        self.showdown: list[dict] = []
        self.betting_rounds = 0

    def setup(self):
        deck = [{"rank": r, "suit": s}
                for r in range(2, 15)
                for s in ("♠", "♥", "♦", "♣")]
        random.shuffle(deck)
        for pid in self.order:
            self.hands[pid] = [deck.pop() for _ in range(3)]
            self.chips[pid] = 500
            self.stakes[pid] = self.ANTE
            self.chips[pid] -= self.ANTE
            self.pot += self.ANTE
            self.blind.add(pid)          # everyone starts blind

    def _live(self):
        return [p for p in self.order if p not in self.folded]

    def next_turn(self):
        # Folded players are out of the hand: never hand them the turn.
        for _ in range(max(1, len(self.order))):
            super().next_turn()
            if self.current_player_id() not in self.folded:
                break

    def on_turn_timeout(self):
        # Sitting on your turn past the clock packs your hand, like a real
        # table -- otherwise one idle phone stalls everyone for 40s a lap.
        pid = self.current_player_id()
        if pid is not None and pid not in self.folded:
            self.handle_action(pid, "fold", {})
        else:
            self.next_turn()

    def on_player_leave(self, player_id):
        if player_id in self.order and player_id not in self.folded and not self._finished:
            self.folded.add(player_id)
            if len(self._live()) == 1:
                self._award(self._live()[0])
                return
        super().on_player_leave(player_id)

    def handle_action(self, player_id, action, data):
        if self._finished or not self.is_my_turn(player_id):
            return
        if player_id in self.folded:
            return

        if action == "fold":
            self.folded.add(player_id)
            if len(self._live()) == 1:
                self._award(self._live()[0])
                return
            self.next_turn()

        elif action in ("bet", "call"):
            # Playing blind is half price; seeing your cards doubles the stake.
            cost = self.current_stake if player_id in self.blind else self.current_stake * 2
            if action == "bet":
                cost *= 2
            cost = min(cost, self.chips.get(player_id, 0))
            if cost <= 0:
                self.folded.add(player_id)
                self.next_turn()
                return
            self.chips[player_id] -= cost
            self.pot += cost
            self.stakes[player_id] = cost
            if action == "bet":
                self.current_stake = cost if player_id in self.blind else cost // 2
            self.betting_rounds += 1
            if self.betting_rounds >= self.MAX_ROUNDS:
                self._showdown()
                return
            self.next_turn()

        elif action == "see":
            self.blind.discard(player_id)

        elif action == "show":
            if len(self._live()) == 2:
                self._showdown()

    def _hand_rank(self, cards):
        """Teen Patti ranking, high to low: trail, pure seq, seq, colour, pair, high."""
        ranks = sorted((c["rank"] for c in cards), reverse=True)
        suits = [c["suit"] for c in cards]
        same_suit = len(set(suits)) == 1
        distinct = sorted(set(ranks))
        is_seq = len(distinct) == 3 and distinct[2] - distinct[0] == 2
        if set(ranks) == {14, 2, 3}:
            is_seq = True                       # A-2-3 is the second-best run

        if len(set(ranks)) == 1:
            return (6, ranks)
        if is_seq and same_suit:
            return (5, ranks)
        if is_seq:
            return (4, ranks)
        if same_suit:
            return (3, ranks)
        if len(set(ranks)) == 2:
            pair = [r for r in ranks if ranks.count(r) == 2][0]
            kicker = [r for r in ranks if ranks.count(r) == 1][0]
            return (2, [pair, kicker])
        return (1, ranks)

    def _showdown(self):
        live = self._live()
        if not live:
            self._finished = True
            return
        best = max(live, key=lambda p: self._hand_rank(self.hands[p]))
        self.showdown = [
            {"playerID": p, "name": self.player_name(p),
             "cards": self.hands[p], "rank": self._hand_rank(self.hands[p])[0]}
            for p in live
        ]
        self._award(best)

    def _award(self, winner):
        self.chips[winner] = self.chips.get(winner, 0) + self.pot
        for pid in self.order:
            self.scores[pid] = self.chips.get(pid, 0)
            player = self.room.player(pid)
            if player is not None:
                player.score = self.chips.get(pid, 0)
        self.finish(winner=winner)

    def public_state(self):
        state = self.base_public()
        state.update({
            "pot": self.pot,
            "currentStake": self.current_stake,
            "seats": [
                {"playerID": pid, "name": self.player_name(pid),
                 "chips": self.chips.get(pid, 0),
                 "folded": pid in self.folded,
                 "blind": pid in self.blind,
                 "stake": self.stakes.get(pid, 0)}
                for pid in self.order
            ],
            # Cards appear only at showdown.
            "showdown": self.showdown,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        seen = player_id not in self.blind
        state.update({
            "pot": self.pot,
            "chips": self.chips.get(player_id, 0),
            "blind": not seen,
            # Blind players genuinely have not looked -- so the server does not
            # send the cards until they choose to see them.
            "cards": self.hands.get(player_id, []) if seen else [],
            "callCost": self.current_stake if not seen else self.current_stake * 2,
            "folded": player_id in self.folded,
            "canAct": self.is_my_turn(player_id) and player_id not in self.folded,
        })
        return state


ENGINES = {
    "defuse": DefuseEngine,
    "battleship": BattleshipEngine,
    "air_hockey": AirHockeyEngine,
    "heist_escape": HeistEscapeEngine,
    "ludo": LudoEngine,
    "carrom": CarromEngine,
    "teen_patti": TeenPattiEngine,
}
