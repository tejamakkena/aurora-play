"""Board and arcade engines ported from the browser games catalog.

Connect 4, Memory and Pong port their win/physics logic straight from
``games/connect4``, ``games/memory`` and ``games/pong``. Chess and
Snake & Ladder have no working browser backend to port (their old
``games/snake_ladder`` module has an empty ``game_logic.py``/``models.py``),
so both are original implementations built to the Swift controller contract
in ``ClassicGameControllers.swift`` / ``OtherControllerViews.swift``.
"""

import random
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines._bases import TurnBasedEngine

# ---------------------------------------------------------------------------
# Connect 4 -- ported from games/connect4/socket_events.py:check_winner
# ---------------------------------------------------------------------------


class Connect4Engine(TurnBasedEngine):
    """Verified against Connect4BoardState/Connect4ControllerView in
    TVClassicGameBoards.swift and ClassicGameControllers.swift."""

    game_id = "connect4"
    min_players = 2
    max_players = 2

    ROWS, COLS = 6, 7
    COLORS = ("red", "yellow")

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.grid = [["" for _ in range(self.COLS)] for _ in range(self.ROWS)]
        self.colors: dict[str, str] = {}
        self.win_cells: list[tuple[int, int]] = []
        self.draw = False

    def setup(self):
        self.colors = {pid: self.COLORS[i % 2] for i, pid in enumerate(self.order)}

    def _drop(self, col):
        for row in range(self.ROWS - 1, -1, -1):
            if self.grid[row][col] == "":
                return row
        return None

    def _check_winner(self):
        g, R, C = self.grid, self.ROWS, self.COLS
        lines = []
        for r in range(R):
            for c in range(C - 3):
                lines.append([(r, c + i) for i in range(4)])
        for r in range(R - 3):
            for c in range(C):
                lines.append([(r + i, c) for i in range(4)])
        for r in range(R - 3):
            for c in range(C - 3):
                lines.append([(r + i, c + i) for i in range(4)])
        for r in range(R - 3):
            for c in range(3, C):
                lines.append([(r + i, c - i) for i in range(4)])
        for cells in lines:
            first = g[cells[0][0]][cells[0][1]]
            if first and all(g[r][c] == first for r, c in cells):
                return first, cells
        return None, []

    def handle_action(self, player_id, action, data):
        if self._finished or action != "drop" or not self.is_my_turn(player_id):
            return
        col = data.get("column")
        if not isinstance(col, int) or not 0 <= col < self.COLS:
            return
        row = self._drop(col)
        if row is None:
            return
        color = self.colors.get(player_id, "red")
        self.grid[row][col] = color

        winner_color, cells = self._check_winner()
        if winner_color:
            self.win_cells = cells
            self.scores[player_id] = 1
            player = self.room.player(player_id)
            if player is not None:
                player.score = 1
            self.finish(winner=player_id)
            return
        if all(self.grid[0][c] != "" for c in range(self.COLS)):
            self.draw = True
            self.finish(winner=None)
            return
        self.next_turn()

    def _full_columns(self):
        return [c for c in range(self.COLS) if self.grid[0][c] != ""]

    def public_state(self):
        state = self.base_public()
        current = self.current_player_id()
        state.update({
            "grid": [row[:] for row in self.grid],
            "currentPlayerID": current or "",
            "currentPlayerName": self.player_name(current) if current else "",
            "winner": self.player_name(self.winner) if self.winner else None,
            "winCells": [f"{r},{c}" for r, c in self.win_cells],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "color": self.colors.get(player_id, "red"),
            "fullColumns": self._full_columns(),
        })
        return state


# ---------------------------------------------------------------------------
# Memory -- ported from games/memory/game_logic.py:MemoryGame
# ---------------------------------------------------------------------------


class MemoryEngine(TurnBasedEngine):
    """Verified against MemoryBoardState/MemoryControllerView."""

    game_id = "memory"
    min_players = 2
    max_players = 4

    SYMBOLS = ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
               '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔']
    PAIRS = 8

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.cards: list[str] = []
        self.matched: set[int] = set()
        self.flipped: list[int] = []
        # A mismatched pair stays face-up this long so everyone can see
        # (and memorise) it before the turn passes.
        self.hide_at: float = 0.0

    MISMATCH_SHOW_SECONDS = 1.6

    def setup(self):
        symbols = random.sample(self.SYMBOLS, self.PAIRS)
        deck = symbols * 2
        random.shuffle(deck)
        self.cards = deck

    def handle_action(self, player_id, action, data):
        if self._finished or action != "flip" or not self.is_my_turn(player_id):
            return
        if self.hide_at:
            return                          # mismatched pair still showing
        idx = data.get("index")
        if not isinstance(idx, int) or not 0 <= idx < len(self.cards):
            return
        if idx in self.matched or idx in self.flipped or len(self.flipped) >= 2:
            return

        self.flipped.append(idx)
        if len(self.flipped) < 2:
            return

        a, b = self.flipped
        if self.cards[a] == self.cards[b]:
            self.matched.update({a, b})
            self.scores[player_id] = self.scores.get(player_id, 0) + 1
            player = self.room.player(player_id)
            if player is not None:
                player.score = self.scores[player_id]
            self.flipped = []
            if len(self.matched) == len(self.cards):
                self.finish()
            # A match keeps the turn.
        else:
            self.hide_at = time.time() + self.MISMATCH_SHOW_SECONDS

    def on_player_leave(self, player_id):
        if self.hide_at and self.is_my_turn(player_id):
            self.hide_at = 0.0
            self.flipped = []
        super().on_player_leave(player_id)

    def tick(self, dt):
        if self.hide_at and time.time() >= self.hide_at:
            self.hide_at = 0.0
            self.flipped = []
            self.next_turn()
            return
        super().tick(dt)

    def public_state(self):
        state = self.base_public()
        current = self.current_player_id()
        state.update({
            "currentPlayerID": current or "",
            "currentPlayerName": self.player_name(current) if current else "",
            "cards": [
                {"value": self.cards[i] if (i in self.matched or i in self.flipped) else "❓",
                 "state": "matched" if i in self.matched
                          else "flipped" if i in self.flipped else "hidden"}
                for i in range(len(self.cards))
            ],
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "myScore": self.scores.get(player_id, 0),
            "flipped": list(self.flipped),
            "matched": sorted(self.matched),
            "cardCount": len(self.cards),
            "cardValues": [
                self.cards[i] if (i in self.matched or i in self.flipped) else "❓"
                for i in range(len(self.cards))
            ],
        })
        return state


# ---------------------------------------------------------------------------
# Chess -- no working browser backend to port (games/tictactoe is a
# different game). Original implementation: pseudo-legal piece movement,
# captures, no check/checkmate detection -- the game ends when a king is
# captured, a common simplification for casual implementations. Verified
# against ChessControllerView's board/validMoves/pieceColor/isMyTurn keys.
# The TV board (TVChessBoardView) reads board/pieceColors/turnColor/
# lastMove/captured/inCheck from public_state. Pawns auto-promote to queens.
# ---------------------------------------------------------------------------

WHITE_PIECES = {"K": "♔", "Q": "♕", "R": "♖", "B": "♗", "N": "♘", "P": "♙"}
BLACK_PIECES = {"K": "♚", "Q": "♛", "R": "♜", "B": "♝", "N": "♞", "P": "♟"}


class ChessEngine(TurnBasedEngine):
    game_id = "chess"
    min_players = 2
    max_players = 2

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.board: list[list[str]] = []
        self.piece_color: dict[str, str] = {}
        self.selected: dict[str, tuple] = {}
        self.captured_king = False
        self.last_move: list[list[int]] | None = None
        self.captured: dict[str, list[str]] = {"white": [], "black": []}
        self.draw = False

    def setup(self):
        back = ["R", "N", "B", "Q", "K", "B", "N", "R"]
        self.board = [["" for _ in range(8)] for _ in range(8)]
        for c, p in enumerate(back):
            self.board[0][c] = BLACK_PIECES[p]
            self.board[7][c] = WHITE_PIECES[p]
        for c in range(8):
            self.board[1][c] = BLACK_PIECES["P"]
            self.board[6][c] = WHITE_PIECES["P"]
        colors = ["white", "black"]
        self.piece_color = {pid: colors[i % 2] for i, pid in enumerate(self.order)}

    def _is_white(self, piece):
        return piece != "" and piece in WHITE_PIECES.values()

    def _is_black(self, piece):
        return piece != "" and piece in BLACK_PIECES.values()

    def _owner_color(self, piece):
        if self._is_white(piece):
            return "white"
        if self._is_black(piece):
            return "black"
        return None

    def _piece_kind(self, piece):
        for kind, sym in WHITE_PIECES.items():
            if sym == piece:
                return kind
        for kind, sym in BLACK_PIECES.items():
            if sym == piece:
                return kind
        return None

    def _valid_moves(self, row, col):
        piece = self.board[row][col]
        color = self._owner_color(piece)
        if color is None:
            return []
        kind = self._piece_kind(piece)
        moves = []

        def add(r, c):
            if 0 <= r < 8 and 0 <= c < 8:
                target = self.board[r][c]
                if self._owner_color(target) != color:
                    moves.append((r, c))

        def slide(directions):
            for dr, dc in directions:
                r, c = row + dr, col + dc
                while 0 <= r < 8 and 0 <= c < 8:
                    target = self.board[r][c]
                    if target == "":
                        moves.append((r, c))
                    else:
                        if self._owner_color(target) != color:
                            moves.append((r, c))
                        break
                    r, c = r + dr, c + dc

        if kind == "P":
            direction = -1 if color == "white" else 1
            start_row = 6 if color == "white" else 1
            one = row + direction
            if 0 <= one < 8 and self.board[one][col] == "":
                moves.append((one, col))
                two = row + 2 * direction
                if row == start_row and self.board[two][col] == "":
                    moves.append((two, col))
            for dc in (-1, 1):
                r, c = row + direction, col + dc
                if 0 <= r < 8 and 0 <= c < 8 and self._owner_color(self.board[r][c]) not in (None, color):
                    moves.append((r, c))
        elif kind == "N":
            for dr, dc in ((1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)):
                add(row + dr, col + dc)
        elif kind == "K":
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr or dc:
                        add(row + dr, col + dc)
        elif kind == "R":
            slide([(1, 0), (-1, 0), (0, 1), (0, -1)])
        elif kind == "B":
            slide([(1, 1), (1, -1), (-1, 1), (-1, -1)])
        elif kind == "Q":
            slide([(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)])
        return moves

    def handle_action(self, player_id, action, data):
        if self._finished or not self.is_my_turn(player_id):
            return
        color = self.piece_color.get(player_id)

        if action == "select":
            row, col = data.get("row"), data.get("col")
            if not (isinstance(row, int) and isinstance(col, int) and 0 <= row < 8 and 0 <= col < 8):
                return
            if self._owner_color(self.board[row][col]) != color:
                return
            self.selected[player_id] = (row, col)

        elif action == "move":
            frm, to = data.get("from"), data.get("to")
            if not (isinstance(frm, list) and isinstance(to, list)
                    and len(frm) == 2 and len(to) == 2):
                return
            fr, fc = frm
            tr, tc = to
            if not all(isinstance(v, int) and 0 <= v < 8 for v in (fr, fc, tr, tc)):
                return
            if self._owner_color(self.board[fr][fc]) != color:
                return
            if (tr, tc) not in self._valid_moves(fr, fc):
                return
            target = self.board[tr][tc]
            if self._piece_kind(target) == "K":
                self.captured_king = True
            if target:
                self.captured[color].append(target)
            moving = self.board[fr][fc]
            # Auto-promote a pawn reaching the far rank to a queen.
            if self._piece_kind(moving) == "P" and tr in (0, 7):
                moving = WHITE_PIECES["Q"] if color == "white" else BLACK_PIECES["Q"]
            self.board[tr][tc] = moving
            self.board[fr][fc] = ""
            self.last_move = [[fr, fc], [tr, tc]]
            self.selected.pop(player_id, None)
            if self.captured_king:
                self.scores[player_id] = 1
                player = self.room.player(player_id)
                if player is not None:
                    player.score = 1
                self.finish(winner=player_id)
                return
            self.next_turn()
            nxt = self.current_player_id()
            if nxt and not self._has_any_move(self.piece_color.get(nxt)):
                self.draw = True                  # stalemate: nothing can move
                self.finish(winner=None)

    def _has_any_move(self, color):
        for r in range(8):
            for c in range(8):
                if self._owner_color(self.board[r][c]) == color and self._valid_moves(r, c):
                    return True
        return False

    def _king_attacked(self, color):
        """True when ``color``'s king could be taken on the opponent's next move."""
        king = WHITE_PIECES["K"] if color == "white" else BLACK_PIECES["K"]
        pos = next(((r, c) for r in range(8) for c in range(8)
                    if self.board[r][c] == king), None)
        if pos is None:
            return False
        for r in range(8):
            for c in range(8):
                owner = self._owner_color(self.board[r][c])
                if owner and owner != color and pos in self._valid_moves(r, c):
                    return True
        return False

    def _turn_color(self):
        pid = self.current_player_id()
        return self.piece_color.get(pid) if pid else None

    def public_state(self):
        state = self.base_public()
        turn_color = self._turn_color()
        state.update({
            "board": [row[:] for row in self.board],
            "pieceColors": dict(self.piece_color),
            "turnColor": turn_color,
            "lastMove": self.last_move,
            "captured": {k: v[:] for k, v in self.captured.items()},
            "inCheck": bool(turn_color) and not self._finished and self._king_attacked(turn_color),
            "draw": self.draw,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        sel = self.selected.get(player_id)
        state.update({
            "pieceColor": self.piece_color.get(player_id, "white"),
            "board": [row[:] for row in self.board],
            "validMoves": [[r, c] for r, c in self._valid_moves(*sel)] if sel else [],
            "lastMove": self.last_move,
            "inCheck": (self.is_my_turn(player_id) and not self._finished
                        and self._king_attacked(self.piece_color.get(player_id, "white"))),
        })
        return state


# ---------------------------------------------------------------------------
# Snake & Ladder -- games/snake_ladder's game_logic.py/models.py are empty,
# so this is an original implementation of the classic board. Verified
# against ShakeToRollControllerView's isMyTurn/position keys. The TV board
# is now TVSnakeLadderBoardView -- a native cinematic 3D SceneKit board
# (ios/GameLabTV/Views/Games/TVSnakeLadderBoardView.swift) that renders the
# snakes/ladders below straight from the `snakes`/`ladders` maps exposed on
# public_state(), rather than hardcoding its own possibly-drifting copy.
#
# Only 3 snakes on purpose (down from an earlier 10): the user asked for a
# real 3D board with "3 snakes resting with some animation", where each
# snake is a full serpentine model with its own idle loop plus a one-shot
# eat/swallow animation -- fewer, more prominent snakes reads better
# cinematically than a crowded board of thin ones. Ladders are left at 10;
# only the snake count was asked to shrink. Spaced across the board (one in
# the high 80s, one in the low 60s, one in the low 30s) so each is a
# distinct, well-separated set piece rather than clustered together.
# ---------------------------------------------------------------------------

SNAKES = {89: 53, 62: 22, 32: 10}
LADDERS = {2: 38, 7: 14, 8: 31, 15: 26, 21: 42, 28: 84, 36: 44, 51: 67, 71: 91, 78: 98}


class SnakeLadderEngine(TurnBasedEngine):
    game_id = "snake_ladder"
    min_players = 2
    max_players = 6
    turn_seconds = 30

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.positions: dict[str, int] = {}
        self.last_roll: dict[str, int] = {}

    def setup(self):
        self.positions = {pid: 0 for pid in self.order}

    def handle_action(self, player_id, action, data):
        if self._finished or action != "roll" or not self.is_my_turn(player_id):
            return
        value = data.get("value")
        if not isinstance(value, int) or not 1 <= value <= 6:
            value = random.randint(1, 6)
        self.last_roll[player_id] = value

        new_pos = self.positions.get(player_id, 0) + value
        if new_pos > 100:
            new_pos = self.positions.get(player_id, 0)   # overshoot -- stay put
        elif new_pos in SNAKES:
            new_pos = SNAKES[new_pos]
        elif new_pos in LADDERS:
            new_pos = LADDERS[new_pos]
        self.positions[player_id] = new_pos

        if new_pos == 100:
            self.finish(winner=player_id)
            return
        self.next_turn()

    def public_state(self):
        state = self.base_public()
        state.update({
            "positions": [
                {"playerID": pid, "name": self.player_name(pid), "position": pos}
                for pid, pos in self.positions.items()
            ],
            "lastRoll": self.last_roll,
            # Static board layout, included every call (cheap, unchanging)
            # so the Swift client has one authoritative source for where
            # the snakes/ladders are instead of hardcoding its own copy
            # that could silently drift from SNAKES/LADDERS above.
            "snakes": {str(head): tail for head, tail in SNAKES.items()},
            "ladders": {str(bottom): top for bottom, top in LADDERS.items()},
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "position": self.positions.get(player_id, 0),
            "lastRoll": self.last_roll.get(player_id, 0),
        })
        return state


# ---------------------------------------------------------------------------
# Pong -- ported the win/serve shape from games/pong's client-authoritative
# model into a server-authoritative simulation (the browser game trusted the
# host's phone for ball physics; the native hub can't since there's no host
# concept for a live simulation loop). Verified against PongState/
# PongControllerView's ballX/ballY/leftPaddle/rightPaddle/side keys.
# ---------------------------------------------------------------------------


class PongEngine(NativeGameEngine):
    game_id = "pong"
    min_players = 2
    max_players = 2
    tick_hz = 30.0
    heavy_state = True

    PADDLE_HALF = 0.12
    WIN_SCORE = 7

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.order: list[str] = []
        self.paddles: dict[str, float] = {}
        self.scores: dict[str, int] = {}
        self.bx = self.by = 0.5
        self.vx = self.vy = 0.0
        self._finished = False
        self.serve_at = 0.0

    def start(self, players):
        self.order = [p.id for p in players][:2]
        self.paddles = {pid: 0.5 for pid in self.order}
        self.scores = {pid: 0 for pid in self.order}
        self._serve()

    def _serve(self):
        self.bx, self.by = 0.5, 0.5
        angle = random.uniform(-0.6, 0.6) + random.choice([0, 3.14159])
        speed = 0.5
        self.vx = speed * 0.6 * (1 if random.random() < 0.5 else -1)
        self.vy = speed * (1 if angle < 1.5 else -1)
        self.serve_at = time.time() + 1.0

    def handle_action(self, player_id, action, data):
        if action != "paddle" or player_id not in self.paddles:
            return
        position = data.get("position")
        if not isinstance(position, (int, float)):
            return
        y = (float(position) + 1) / 2
        self.paddles[player_id] = max(0.0, min(1.0, y))

    def tick(self, dt):
        if self._finished or time.time() < self.serve_at or len(self.order) < 2:
            return
        dt = min(dt, 0.05)
        self.by += self.vy * dt
        self.bx += self.vx * dt

        if self.by <= 0.0:
            self.by, self.vy = 0.0, abs(self.vy)
        elif self.by >= 1.0:
            self.by, self.vy = 1.0, -abs(self.vy)

        left_id, right_id = self.order[0], self.order[1]
        if self.bx <= 0.06 and self.vx < 0:
            if abs(self.by - self.paddles.get(left_id, 0.5)) <= self.PADDLE_HALF:
                self.vx = abs(self.vx) * 1.05
            elif self.bx <= 0.0:
                self._goal(right_id)
                return
        elif self.bx >= 0.94 and self.vx > 0:
            if abs(self.by - self.paddles.get(right_id, 0.5)) <= self.PADDLE_HALF:
                self.vx = -abs(self.vx) * 1.05
            elif self.bx >= 1.0:
                self._goal(left_id)
                return

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
        left_id = self.order[0] if self.order else None
        right_id = self.order[1] if len(self.order) > 1 else None
        return {
            "ballX": round(self.bx, 4),
            "ballY": round(self.by, 4),
            "leftPaddle": round(self.paddles.get(left_id, 0.5), 4) if left_id else 0.5,
            "rightPaddle": round(self.paddles.get(right_id, 0.5), 4) if right_id else 0.5,
            "scoreLeft": self.scores.get(left_id, 0) if left_id else 0,
            "scoreRight": self.scores.get(right_id, 0) if right_id else 0,
            "leftName": self.player_name(left_id) if left_id else "Player 1",
            "rightName": self.player_name(right_id) if right_id else "Player 2",
            "finished": self._finished,
        }

    def private_state(self, player_id):
        side = "left" if self.order[:1] == [player_id] else "right"
        return {
            "side": side,
            "myY": self.paddles.get(player_id, 0.5),
            "score": self.scores.get(player_id, 0),
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.scores)


ENGINES = {
    "connect4": Connect4Engine,
    "memory": MemoryEngine,
    "chess": ChessEngine,
    "snake_ladder": SnakeLadderEngine,
    "pong": PongEngine,
}
