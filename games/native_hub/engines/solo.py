"""Solo engines, all playable with the Siri Remote alone.

These accept the same ``game_action`` events as every other game -- the tvOS app
sends them on the player's behalf when the remote is used, so no separate input
path is needed on the server.
"""

import math
import random
import time

from games.native_hub.engine import NativeGameEngine

DIRECTIONS = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}


class NeonSnakeEngine(NativeGameEngine):
    """Classic snake, driven by the remote's D-pad.

    The grid used to be a square 20x20 -- which, like BrickBreakerEngine's
    old portrait arena, can never fill a 16:9 TV: whichever screen dimension
    the square's edge is bound by, the other runs out early and leaves huge
    black margins no matter how the client scales the cell size. Widening the
    grid to roughly match a 16:9 screen (32x18) is the same fix already
    applied to the brick breaker arena, so the board the client draws is
    actually screen-shaped instead of a letterboxed square.
    """

    game_id = "neon_snake"
    min_players = 1
    max_players = 4
    # The snake's step rate, not a render rate -- a turn sent mid-tick is
    # buffered in `pending` and only actually applied at the next tick
    # boundary (see handle_action/tick below), so this rate is also the
    # floor on how long a turn can take to visibly land: up to 1/tick_hz,
    # ~62ms on average at 8Hz. Reported directly as "turn left and right
    # has little delay" -- raised to 10Hz to shrink that worst case to
    # 100ms/50ms average, without spinning the snake's overall pace up as
    # much as a bigger jump would. True zero-latency turning would need
    # turns applied off the tick entirely (a continuous heading/position
    # model instead of a discrete grid step), which is a bigger engine
    # change than this round's scope.
    tick_hz = 10.0

    W, H = 32, 18

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.snakes: dict[str, dict] = {}
        self.food: tuple = (10, 10)
        self._finished = False

    def start(self, players):
        for i, player in enumerate(players):
            start = (3 + i * 4, 10)
            self.snakes[player.id] = {
                "body": [start], "dir": (1, 0), "pending": (1, 0),
                "alive": True, "score": 0,
            }
        self._place_food()

    def _place_food(self):
        occupied = {cell for s in self.snakes.values() for cell in s["body"]}
        free = [(x, y) for x in range(self.W) for y in range(self.H)
                if (x, y) not in occupied]
        self.food = random.choice(free) if free else (0, 0)

    def handle_action(self, player_id, action, data):
        if action != "turn":
            return
        snake = self.snakes.get(player_id)
        if snake is None or not snake["alive"]:
            return
        vector = DIRECTIONS.get(data.get("direction"))
        if vector is None:
            return
        # Reversing straight into your own neck is an instant loss, so ignore it.
        if (vector[0] == -snake["dir"][0] and vector[1] == -snake["dir"][1]):
            return
        snake["pending"] = vector

    def tick(self, dt):
        if self._finished:
            return
        for snake in self.snakes.values():
            if not snake["alive"]:
                continue
            snake["dir"] = snake["pending"]
            head = snake["body"][0]
            nxt = (head[0] + snake["dir"][0], head[1] + snake["dir"][1])

            if not (0 <= nxt[0] < self.W and 0 <= nxt[1] < self.H):
                snake["alive"] = False
                continue
            if any(nxt in s["body"] for s in self.snakes.values()):
                snake["alive"] = False
                continue

            snake["body"].insert(0, nxt)
            if nxt == self.food:
                snake["score"] += 10
                self._place_food()
            else:
                snake["body"].pop()

        for pid, snake in self.snakes.items():
            player = self.room.player(pid)
            if player is not None:
                player.score = snake["score"]

        if not any(s["alive"] for s in self.snakes.values()):
            self._finished = True

    def public_state(self):
        return {
            "width": self.W, "height": self.H,
            "food": {"x": self.food[0], "y": self.food[1]},
            "snakes": [
                {"playerID": pid, "name": self.player_name(pid),
                 "body": [{"x": x, "y": y} for x, y in s["body"]],
                 "alive": s["alive"], "score": s["score"]}
                for pid, s in self.snakes.items()
            ],
            "finished": self._finished,
        }

    def private_state(self, player_id):
        snake = self.snakes.get(player_id, {})
        alive = snake.get("alive", False)
        return {
            "alive": alive,
            "isOut": not alive,  # read by the phone DPad "You're out" subtitle
            "score": snake.get("score", 0),
            "finished": self._finished,
            "controls": "dpad",
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({pid: s["score"] for pid, s in self.snakes.items()})


class Twenty48Engine(NativeGameEngine):
    """2048. The remote's touch surface swipes the tiles.

    ``boards`` stays exactly what it always was -- a flat list of cell
    values, in row-major order -- because that is the only representation a
    swipe actually needs to compute. But a flat value array has no memory: a
    client that only ever sees "the value at index 0 became 0 and the value
    at index 3 changed" cannot tell a tile *sliding* from column 0 to column
    3 apart from a merge or a fresh spawn happening to land on 3, which is
    exactly why the TV board used to just snap to each new grid of numbers
    instead of sliding tiles.

    ``tile_ids`` is a parallel array (same shape as ``boards``, 0 meaning
    "no tile") giving each occupied cell a stable id that survives a slide
    and is carried by the surviving tile through a merge, so a client that
    keeps the id from one push to the next can animate the actual movement
    instead of guessing at it. ``last_move_merged``/``last_move_spawned``
    call out, for the one push right after a swipe, which ids were the
    result of a merge (for a pop) or a brand new spawn (for a fade-in).
    """

    game_id = "twenty48"
    min_players = 1
    max_players = 4

    N = 4

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.boards: dict[str, list[int]] = {}
        self.tile_ids: dict[str, list[int]] = {}
        self.next_tile_id: dict[str, int] = {}
        self.scores: dict[str, int] = {}
        self.done: set[str] = set()
        self.best_tile: dict[str, int] = {}
        self.last_move_merged: dict[str, list[int]] = {}
        self.last_move_spawned: dict[str, int | None] = {}

    def start(self, players):
        for player in players:
            board = [0] * (self.N * self.N)
            self.boards[player.id] = board
            self.tile_ids[player.id] = [0] * (self.N * self.N)
            self.next_tile_id[player.id] = 1
            self._spawn(player.id, board)
            self._spawn(player.id, board)
            self.scores[player.id] = 0
            self.best_tile[player.id] = 2
            self.last_move_merged[player.id] = []
            self.last_move_spawned[player.id] = None

    def _mint_id(self, player_id):
        tid = self.next_tile_id.get(player_id, 1)
        self.next_tile_id[player_id] = tid + 1
        return tid

    def _spawn(self, player_id, board):
        empty = [i for i, v in enumerate(board) if v == 0]
        if not empty:
            return None
        cell = random.choice(empty)
        board[cell] = 4 if random.random() < 0.1 else 2
        ids = self.tile_ids.setdefault(player_id, [0] * len(board))
        tid = self._mint_id(player_id)
        ids[cell] = tid
        return tid

    def _rows(self, board, direction):
        """Return the board as lists of indices, oriented so a merge is leftward."""
        n = self.N
        if direction == "left":
            return [[r * n + c for c in range(n)] for r in range(n)]
        if direction == "right":
            return [[r * n + c for c in reversed(range(n))] for r in range(n)]
        if direction == "up":
            return [[r * n + c for r in range(n)] for c in range(n)]
        return [[r * n + c for r in reversed(range(n))] for c in range(n)]

    def handle_action(self, player_id, action, data):
        if action != "swipe" or player_id in self.done:
            return
        direction = data.get("direction")
        if direction not in DIRECTIONS:
            return
        board = self.boards.get(player_id)
        if board is None:
            return
        ids = self.tile_ids.get(player_id)
        if ids is None or len(ids) != len(board):
            ids = [0] * len(board)
            self.tile_ids[player_id] = ids

        moved = False
        gained = 0
        merged_ids: list[int] = []
        for line in self._rows(board, direction):
            # (value, id) pairs for the occupied cells of this row/column, in
            # slide order. A cell whose value survived from before this
            # engine tracked ids (or was poked directly, e.g. by a test) has
            # no id yet -- mint one on the spot rather than losing identity
            # for that tile forever.
            occupied = [(board[i], ids[i]) for i in line if board[i]]
            occupied = [(v, tid if tid else self._mint_id(player_id)) for v, tid in occupied]

            merged: list[tuple[int, int]] = []
            skip = False
            for i, (value, tid) in enumerate(occupied):
                if skip:
                    skip = False
                    continue
                if i + 1 < len(occupied) and occupied[i + 1][0] == value:
                    # The surviving tile keeps the *leading* id (the one
                    # further along in the slide direction) so a client
                    # tracking ids sees one tile continue and one vanish,
                    # which is exactly what a merge is.
                    merged.append((value * 2, tid))
                    merged_ids.append(tid)
                    gained += value * 2
                    skip = True
                else:
                    merged.append((value, tid))
            merged += [(0, 0)] * (self.N - len(merged))
            for slot, cell in enumerate(line):
                new_value, new_id = merged[slot]
                if board[cell] != new_value:
                    moved = True
                board[cell] = new_value
                ids[cell] = new_id

        if not moved:
            return

        self.scores[player_id] += gained
        self.best_tile[player_id] = max(board) if board else 0
        player = self.room.player(player_id)
        if player is not None:
            player.score = self.scores[player_id]
        self.last_move_merged[player_id] = merged_ids
        self.last_move_spawned[player_id] = self._spawn(player_id, board)

        if not self._has_move(board):
            self.done.add(player_id)

    def _has_move(self, board):
        if any(v == 0 for v in board):
            return True
        n = self.N
        for r in range(n):
            for c in range(n):
                v = board[r * n + c]
                if c + 1 < n and board[r * n + c + 1] == v:
                    return True
                if r + 1 < n and board[(r + 1) * n + c] == v:
                    return True
        return False

    def _tile_entities(self, player_id, board):
        """Occupied cells as {id, value, row, col} objects instead of a flat
        value array, so a client can track a tile's identity from one push to
        the next and animate its actual slide instead of re-rendering numbers
        in place."""
        ids = self.tile_ids.get(player_id) or [0] * len(board)
        return [
            {"id": ids[i] or i + 1, "value": v, "row": i // self.N, "col": i % self.N}
            for i, v in enumerate(board) if v
        ]

    def public_state(self):
        return {
            "size": self.N,
            "boards": [
                {"playerID": pid, "name": self.player_name(pid),
                 "tiles": self._tile_entities(pid, board),
                 "merged": self.last_move_merged.get(pid, []),
                 "spawned": self.last_move_spawned.get(pid),
                 "score": self.scores.get(pid, 0), "best": self.best_tile.get(pid, 0),
                 "done": pid in self.done}
                for pid, board in self.boards.items()
            ],
            "finished": self.is_over(),
        }

    def private_state(self, player_id):
        board = self.boards.get(player_id, [])
        return {
            "size": self.N,
            "tiles": self._tile_entities(player_id, board),
            "merged": self.last_move_merged.get(player_id, []),
            "spawned": self.last_move_spawned.get(player_id),
            "score": self.scores.get(player_id, 0),
            "done": player_id in self.done,
            "controls": "swipe",
        }

    def is_over(self):
        return bool(self.boards) and len(self.done) >= len(self.boards)

    def results(self):
        return self.ranked_results(self.scores)


class BrickBreakerEngine(NativeGameEngine):
    """Paddle and bricks. Slide a thumb on the Siri Remote, or on a phone.

    The arena is deliberately *landscape*. It used to be 100 wide by 140 tall
    -- portrait content on a 16:9 living-room TV -- which is why the board
    could never fill the screen no matter how the Swift side scaled it: the
    height ran out long before the width did, leaving most of an Apple TV
    screen as black margin. ``W`` stays at exactly 100.0 because the phone
    controller derives its own 0..W drag range from
    ``private_state["width"]`` (ios/GameLabController/.../DuelControllers.swift).

    Every geometry constant the TV needs in order to draw the arena is
    published in ``public_state`` rather than hard-coded on the Swift side, so
    the picture and the physics cannot drift apart.
    """

    game_id = "brick_breaker"
    min_players = 1
    max_players = 2
    tick_hz = 30.0
    heavy_state = True

    W, H = 100.0, 62.0
    PADDLE_W = 16.0
    PADDLE_H = 1.8
    PADDLE_Y = 56.0              # top edge of the paddle
    BALL_R = 1.1
    COLS, ROWS = 10, 5
    BRICK_H = 3.0
    ROW_PITCH = 4.0
    TOP_MARGIN = 9.0             # clear band the TV overlays its HUD on
    SIDE_MARGIN = 3.0
    LIVES = 3
    SERVE_DELAY = 1.2            # ready-set-go pause before each launch
    BASE_SPEED = 34.0
    MAX_SPEED = 62.0
    SUBSTEPS = 2                 # so a fast ball cannot tunnel through a brick

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.bricks: list[dict] = []
        self.paddle = self.W / 2
        self.bx, self.by = self.W / 2, self.PADDLE_Y - self.BALL_R
        self.speed = self.BASE_SPEED
        self.vx, self.vy = 0.0, -self.BASE_SPEED
        self.lives = self.LIVES
        self.score = 0
        self.serving = True
        self.serve_at = 0.0
        self.won = False
        self._finished = False

    def start(self, players):
        cell = (self.W - self.SIDE_MARGIN * 2) / self.COLS
        self.bricks = [
            {"id": r * self.COLS + c,
             "row": r,
             "x": self.SIDE_MARGIN + c * cell,
             "y": self.TOP_MARGIN + r * self.ROW_PITCH,
             "w": cell - 1.0,
             "h": self.BRICK_H,
             "alive": True}
            for r in range(self.ROWS) for c in range(self.COLS)
        ]
        self._serve()

    def _serve(self):
        """Park the ball on the paddle and start the pre-launch countdown."""
        self.serving = True
        self.serve_at = time.time() + self.SERVE_DELAY
        self.speed = self.BASE_SPEED
        angle = random.uniform(-0.5, 0.5)          # radians away from straight up
        self.vx = math.sin(angle) * self.speed
        self.vy = -math.cos(angle) * self.speed
        self.bx = self.paddle
        self.by = self.PADDLE_Y - self.BALL_R

    def handle_action(self, player_id, action, data):
        if action == "paddle":
            x = data.get("x")
            if isinstance(x, (int, float)) and not isinstance(x, bool):
                self.paddle = max(self.PADDLE_W / 2,
                                  min(self.W - self.PADDLE_W / 2, float(x)))

    def tick(self, dt):
        if self._finished:
            return

        if self.serving:
            # The ball rides the paddle until it launches, so the board is
            # never a still picture and steering is visible before the serve.
            self.bx = self.paddle
            self.by = self.PADDLE_Y - self.BALL_R
            if time.time() < self.serve_at:
                return
            self.serving = False

        step = min(dt, 0.05) / self.SUBSTEPS
        for _ in range(self.SUBSTEPS):
            if self._finished or self.serving:
                break
            self._advance(step)

        for player in self.room.players:
            player.score = self.score

    def _advance(self, dt):
        self.bx += self.vx * dt
        self.by += self.vy * dt

        # Walls
        if self.bx <= self.BALL_R:
            self.bx, self.vx = self.BALL_R, abs(self.vx)
        elif self.bx >= self.W - self.BALL_R:
            self.bx, self.vx = self.W - self.BALL_R, -abs(self.vx)
        if self.by <= self.BALL_R:
            self.by, self.vy = self.BALL_R, abs(self.vy)

        # Paddle. The contact point sets the outgoing angle, so the player
        # aims with the paddle's edges rather than only blocking with it.
        if (self.vy > 0
                and self.PADDLE_Y - self.BALL_R <= self.by <= self.PADDLE_Y + self.PADDLE_H
                and abs(self.bx - self.paddle) <= self.PADDLE_W / 2 + self.BALL_R):
            offset = max(-1.0, min(1.0, (self.bx - self.paddle) / (self.PADDLE_W / 2)))
            self.speed = min(self.MAX_SPEED, self.speed * 1.02)
            angle = offset * 1.05                  # up to ~60 degrees off vertical
            self.vx = math.sin(angle) * self.speed
            self.vy = -abs(math.cos(angle)) * self.speed
            self.by = self.PADDLE_Y - self.BALL_R

        # Bricks
        for brick in self.bricks:
            if not brick["alive"]:
                continue
            if not (brick["x"] - self.BALL_R <= self.bx <= brick["x"] + brick["w"] + self.BALL_R
                    and brick["y"] - self.BALL_R <= self.by <= brick["y"] + brick["h"] + self.BALL_R):
                continue
            brick["alive"] = False
            self.score += 10 * (self.ROWS - brick["row"])   # top rows are worth more
            self.speed = min(self.MAX_SPEED, self.speed * 1.01)
            # Bounce off whichever face was actually crossed, not always vertically.
            dx = min(abs(self.bx - brick["x"]), abs(self.bx - (brick["x"] + brick["w"])))
            dy = min(abs(self.by - brick["y"]), abs(self.by - (brick["y"] + brick["h"])))
            if dx < dy:
                self.vx = -self.vx
            else:
                self.vy = -self.vy
            self._renormalise()
            break

        if self.by - self.BALL_R > self.H:
            self.lives -= 1
            if self.lives <= 0:
                self._finished = True
            else:
                self._serve()
            return

        if not any(b["alive"] for b in self.bricks):
            self.score += 200
            self.won = True
            self._finished = True

    def _renormalise(self):
        """Keep the speed constant across an axis flip."""
        magnitude = math.hypot(self.vx, self.vy)
        if magnitude < 1e-6:
            self.vx, self.vy = 0.0, -self.speed
            return
        factor = self.speed / magnitude
        self.vx *= factor
        self.vy *= factor

    def public_state(self):
        return {
            "width": self.W, "height": self.H,
            "ball": {"x": round(self.bx, 2), "y": round(self.by, 2)},
            "ballR": self.BALL_R,
            "paddle": round(self.paddle, 2),
            "paddleWidth": self.PADDLE_W,
            "paddleY": self.PADDLE_Y,
            "paddleHeight": self.PADDLE_H,
            "bricks": [
                {"id": b["id"], "row": b["row"],
                 "x": round(b["x"], 2), "y": round(b["y"], 2),
                 "w": round(b["w"], 2), "h": b["h"]}
                for b in self.bricks if b["alive"]
            ],
            "rows": self.ROWS,
            "lives": self.lives, "score": self.score,
            "serving": self.serving,
            "won": self.won,
            "finished": self._finished,
        }

    def private_state(self, player_id):
        return {
            "score": self.score, "lives": self.lives,
            "finished": self._finished, "controls": "swipe",
            "width": self.W,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: self.score for p in self.room.players})


class SimonSaysEngine(NativeGameEngine):
    """Repeat a growing four-colour sequence with the remote's D-pad."""

    game_id = "simon_says"
    min_players = 1
    max_players = 4

    PADS = ["up", "right", "down", "left"]
    SHOW_MS_PER_STEP = 700

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.sequence: list[str] = []
        self.order: list[str] = []
        self.turn_index = 0
        self.progress = 0
        self.phase = "show"
        self.phase_until = 0.0
        self.round = 0
        self._finished = False
        self.last_wrong: str | None = None

    def start(self, players):
        self.order = [p.id for p in players]
        self._next_round()

    def _next_round(self):
        self.sequence.append(random.choice(self.PADS))
        self.round = len(self.sequence)
        self.progress = 0
        self.phase = "show"
        self.phase_until = time.time() + len(self.sequence) * self.SHOW_MS_PER_STEP / 1000 + 0.5

    def current_player(self):
        return self.order[self.turn_index % len(self.order)] if self.order else None

    def handle_action(self, player_id, action, data):
        if self._finished or self.phase != "input":
            return
        if player_id != self.current_player():
            return
        if action != "pad":
            return
        pad = data.get("pad")
        if pad not in self.PADS:
            return

        if pad == self.sequence[self.progress]:
            self.progress += 1
            if self.progress >= len(self.sequence):
                player = self.room.player(player_id)
                if player is not None:
                    player.score += len(self.sequence) * 10
                # Pass the remote on in a group game.
                self.turn_index += 1
                self._next_round()
        else:
            self.last_wrong = player_id
            if len(self.order) <= 1:
                self._finished = True
            else:
                self.order.remove(player_id)
                if not self.order:
                    self._finished = True
                else:
                    self.turn_index %= len(self.order)
                    self.sequence = []
                    self._next_round()

    def tick(self, dt):
        if self._finished:
            return
        if self.phase == "show" and time.time() >= self.phase_until:
            self.phase = "input"
            self.phase_until = 0.0

    def public_state(self):
        return {
            "pads": self.PADS,
            "phase": self.phase,
            "round": self.round,
            # The sequence is only shown during the show phase -- it must not be
            # readable off the TV while the player is being tested.
            "sequence": self.sequence if self.phase == "show" else [],
            "progress": self.progress,
            "currentPlayerID": self.current_player(),
            "currentName": self.player_name(self.current_player()) if self.current_player() else "",
            "finished": self._finished,
            "players": [
                {"id": p.id, "name": p.name, "score": p.score,
                 "isOut": p.id not in self.order}
                for p in self.room.players
            ],
        }

    def private_state(self, player_id):
        return {
            "isMyTurn": player_id == self.current_player(),
            "phase": self.phase,
            "round": self.round,
            "progress": self.progress,
            "pads": self.PADS,
            "isOut": player_id not in self.order,
            "controls": "dpad",
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


ENGINES = {
    "neon_snake": NeonSnakeEngine,
    "twenty48": Twenty48Engine,
    "brick_breaker": BrickBreakerEngine,
    "simon_says": SimonSaysEngine,
}
