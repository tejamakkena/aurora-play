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
    TVClassicGameBoards.swift and ClassicGameControllers.swift.

    Plays 2-4 players. The board grows with the table so a crowded game
    still has room to manoeuvre (``BOARD_SIZES``); the goal stays four in a
    row. Every player gets their own disc colour in seat order.

    State contract (public -- every key the TV reads):
      grid               rows x cols of colour ids ("" = empty)
      rows, cols         board dimensions (2-player games stay 6 x 7)
      colors             playerID -> colour id
      turnOrder          playerIDs in seat order
      currentPlayerID    whose turn it is ("" once the game is over)
      currentPlayerName
      currentColor       colour id of the player to move
      winner             winning player's *name* (kept for older apps)
      winnerID           winning playerID
      winnerColor        winning colour id
      winCells           ["row,col", ...] for the winning four
      isDraw             board filled with no line of four
      moveCount          discs dropped so far
      lastMove           {"row", "col", "color"} or None
    Private additionally carries: color, fullColumns, rows, cols, colors,
    turnOrder, currentPlayerID, currentPlayerName, currentColor.
    """

    game_id = "connect4"
    min_players = 2
    max_players = 4

    ROWS, COLS = 6, 7                       # the classic 2-player board
    BOARD_SIZES = {2: (6, 7), 3: (7, 9), 4: (8, 10)}
    COLORS = ("red", "yellow", "green", "blue")
    CONNECT = 4

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.rows, self.cols = self.ROWS, self.COLS
        self.grid = self._empty_grid()
        self.colors: dict[str, str] = {}
        self.win_cells: list[tuple[int, int]] = []
        self.draw = False
        self.move_count = 0
        self.last_move: dict | None = None

    def _empty_grid(self):
        return [["" for _ in range(self.cols)] for _ in range(self.rows)]

    def setup(self):
        seats = min(max(len(self.order), 2), 4)
        self.rows, self.cols = self.BOARD_SIZES[seats]
        self.grid = self._empty_grid()
        self.colors = {pid: self.COLORS[i % len(self.COLORS)]
                       for i, pid in enumerate(self.order)}

    def _drop(self, col):
        for row in range(self.rows - 1, -1, -1):
            if self.grid[row][col] == "":
                return row
        return None

    def _line_through(self, row, col):
        """The winning four through (row, col), or []. Only the disc just
        dropped can complete a line, so there is no need to rescan the whole
        (up to 8 x 10) board after every move."""
        g = self.grid
        color = g[row][col]
        if not color:
            return []
        for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
            cells = [(row, col)]
            for sign in (1, -1):
                r, c = row + dr * sign, col + dc * sign
                while 0 <= r < self.rows and 0 <= c < self.cols and g[r][c] == color:
                    cells.append((r, c))
                    r, c = r + dr * sign, c + dc * sign
            if len(cells) >= self.CONNECT:
                cells.sort()
                # Highlight exactly four, always including the new disc so
                # the glow reads as "this move won it".
                idx = cells.index((row, col))
                begin = max(0, min(idx, len(cells) - self.CONNECT))
                return cells[begin:begin + self.CONNECT]
        return []

    def _check_winner(self):
        """Full-board scan; returns (colour, cells) or (None, [])."""
        for r in range(self.rows):
            for c in range(self.cols):
                cells = self._line_through(r, c)
                if cells:
                    return self.grid[r][c], cells
        return None, []

    def handle_action(self, player_id, action, data):
        if self._finished or action != "drop" or not self.is_my_turn(player_id):
            return
        col = data.get("column")
        if isinstance(col, bool) or not isinstance(col, int) or not 0 <= col < self.cols:
            return
        row = self._drop(col)
        if row is None:
            return
        color = self.colors.get(player_id, self.COLORS[0])
        self.grid[row][col] = color
        self.move_count += 1
        self.last_move = {"row": row, "col": col, "color": color}

        cells = self._line_through(row, col)
        if cells:
            self.win_cells = cells
            self.scores[player_id] = 1
            player = self.room.player(player_id)
            if player is not None:
                player.score = 1
            self.finish(winner=player_id)
            return
        if all(self.grid[0][c] != "" for c in range(self.cols)):
            self.draw = True
            self.finish(winner=None)
            return
        self.next_turn()

    def current_player_id(self):
        # The base rotation only skips absent seats when the turn passes, so
        # a seat whose phone dropped without an ``on_player_leave`` (or that
        # left while it was already queued) could otherwise stall a 3-4
        # player table. Hop forward to the next connected player instead.
        current = super().current_player_id()
        if current is None or self._finished or self._is_live(current):
            return current
        for step in range(1, len(self.order) + 1):
            idx = (self.turn_index + step) % len(self.order)
            if self._is_live(self.order[idx]):
                self.turn_index = idx
                self.reset_turn_clock()
                return self.order[idx]
        return current

    def _full_columns(self):
        return [c for c in range(self.cols) if self.grid[0][c] != ""]

    def _shared_state(self):
        current = None if self._finished else self.current_player_id()
        return current, {
            "rows": self.rows,
            "cols": self.cols,
            "colors": dict(self.colors),
            "turnOrder": list(self.order),
            "currentPlayerID": current or "",
            "currentPlayerName": self.player_name(current) if current else "",
            "currentColor": self.colors.get(current, "") if current else "",
        }

    def public_state(self):
        state = self.base_public()
        _current, shared = self._shared_state()
        state.update(shared)
        state.update({
            "grid": [row[:] for row in self.grid],
            "winner": self.player_name(self.winner) if self.winner else None,
            "winnerID": self.winner,
            "winnerColor": self.colors.get(self.winner, "") if self.winner else "",
            "winCells": [f"{r},{c}" for r, c in self.win_cells],
            "isDraw": self.draw,
            "moveCount": self.move_count,
            "lastMove": dict(self.last_move) if self.last_move else None,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        current, shared = self._shared_state()
        state.update(shared)
        state.update({
            "isMyTurn": current is not None and current == player_id,
            "color": self.colors.get(player_id, self.COLORS[0]),
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
    turn_seconds = 30           # an idle phone passes its turn

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

    def on_turn_timeout(self):
        self.flipped = []
        super().on_turn_timeout()

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
# The classic board. An earlier pass cut the board to 3 snakes so each could
# be a big 3D set piece, and players reported the game as "same and easy" --
# nothing like the real thing. This is a classic-style layout again: 10
# snakes and 9 ladders spread over all ten rows, with the end game made tense
# the way the real board is -- a gauntlet of heads at 87/93/95/98, and the
# long 98 -> 39 and 87 -> 24 snakes that can throw a near-winner back into
# the bottom half. A solo game averages ~38 turns with the roll-again rule
# below (~45 without it), in line with the classic board's ~39.
#
# Layout invariants (enforced by tests/test_native_engines.py):
#   * every endpoint (snake head/tail, ladder bottom/top) is a distinct
#     square, so no square is both a snake head and a ladder bottom;
#   * nothing starts or ends on 1 or 100 (the win needs an exact roll);
#   * no chains -- a ladder top is never a snake head and a snake tail is
#     never a ladder bottom, so one roll resolves at most one slide;
#   * every snake/ladder spans at least one row, so the TV board can draw
#     each one as a clearly diagonal/vertical set piece.
# ---------------------------------------------------------------------------

SNAKES = {17: 7, 32: 10, 47: 26, 54: 34, 62: 19, 64: 43, 87: 24, 93: 73, 95: 75, 98: 39}
LADDERS = {4: 14, 9: 31, 21: 42, 28: 84, 36: 44, 51: 67, 57: 76, 71: 91, 80: 99}

# Rolling a 6 earns another roll (the common house rule), capped so a run of
# sixes -- or a phone that always reports 6, since the controller sends the
# value -- can never hold the turn forever: the third six in a row still
# moves, but the turn then passes.
MAX_BONUS_ROLLS = 2


class SnakeLadderEngine(TurnBasedEngine):
    game_id = "snake_ladder"
    min_players = 2
    max_players = 6
    turn_seconds = 30

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.positions: dict[str, int] = {}
        self.last_roll: dict[str, int] = {}
        # The most recent slide per player: {"kind": "snake"|"ladder",
        # "from": <head/bottom square>, "to": <tail/top square>,
        # "seq": <monotonic counter>}. The TV board drives its bite/climb
        # cinematics (and the controller its haptics) off this event rather
        # than re-inferring the slide from positions + the last roll, which
        # breaks when state updates coalesce or arrive out of order.
        self.last_slide: dict[str, dict] = {}
        self.slide_seq = 0
        # Roll-again-on-6 bookkeeping. `bonus_streak` counts the sixes the
        # current turn holder has cashed in as extra rolls this turn;
        # `last_roller`/`last_roll_bonus` describe the most recent roll so
        # the TV/phone can say "Rolled a 6, roll again!".
        self.bonus_streak = 0
        self.last_roller: str | None = None
        self.last_roll_bonus = False
        # Monotonic count of accepted rolls, so the TV can tell a fresh roll
        # (tumble the die, flash the banner) from a re-broadcast -- even one
        # that left every position unchanged (an overshoot near 100).
        self.roll_seq = 0

    def setup(self):
        self.positions = {pid: 0 for pid in self.order}
        self.last_slide = {}
        self.slide_seq = 0
        self.bonus_streak = 0
        self.last_roller = None
        self.last_roll_bonus = False
        self.roll_seq = 0

    def _pass_turn(self):
        self.bonus_streak = 0
        self.last_roll_bonus = False
        self.next_turn()

    def on_turn_timeout(self):
        # A bonus roll that is never taken simply lapses with the clock.
        self._pass_turn()

    def on_player_leave(self, player_id):
        if self.current_player_id() == player_id:
            self._pass_turn()

    def roll_again_pending(self) -> bool:
        """True while the current turn holder is owed a bonus roll for a 6."""
        return (not self._finished and self.last_roll_bonus
                and self.last_roller is not None
                and self.last_roller == self.current_player_id())

    def handle_action(self, player_id, action, data):
        if self._finished or action != "roll" or not self.is_my_turn(player_id):
            return
        value = data.get("value")
        if not isinstance(value, int) or not 1 <= value <= 6:
            value = random.randint(1, 6)
        self.last_roll[player_id] = value

        new_pos = self.positions.get(player_id, 0) + value
        slide = None
        if new_pos > 100:
            new_pos = self.positions.get(player_id, 0)   # overshoot -- stay put
        elif new_pos in SNAKES:
            slide = {"kind": "snake", "from": new_pos, "to": SNAKES[new_pos]}
            new_pos = SNAKES[new_pos]
        elif new_pos in LADDERS:
            slide = {"kind": "ladder", "from": new_pos, "to": LADDERS[new_pos]}
            new_pos = LADDERS[new_pos]
        if slide is not None:
            self.slide_seq += 1
            slide["seq"] = self.slide_seq
            self.last_slide[player_id] = slide
        else:
            # A plain move supersedes any earlier slide event for this
            # player, so a late-joining client never replays a stale one.
            self.last_slide.pop(player_id, None)
        self.positions[player_id] = new_pos

        self.last_roller = player_id
        self.roll_seq += 1
        if new_pos == 100:
            self.last_roll_bonus = False
            self.finish(winner=player_id)
            return
        if value == 6 and self.bonus_streak < MAX_BONUS_ROLLS:
            # Same player rolls again with a fresh clock.
            self.bonus_streak += 1
            self.last_roll_bonus = True
            self.reset_turn_clock()
            return
        self._pass_turn()

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
            # The latest slide per player (see handle_action). The TV uses
            # `seq` to play each cinematic exactly once; keys are player
            # ids, values are {"kind", "from", "to", "seq"} dicts.
            "lastSlide": {pid: dict(slide) for pid, slide in self.last_slide.items()},
            # Roll-again-on-6 (additive keys; older clients ignore them).
            # `lastRollerID` is whoever rolled most recently and
            # `lastRollBonus` is true while that player -- still the
            # current player -- is owed another roll for a 6.
            "lastRollerID": self.last_roller,
            "lastRollBonus": self.roll_again_pending(),
            "rollSeq": self.roll_seq,
            "rollAgainOnSix": True,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        state.update({
            "position": self.positions.get(player_id, 0),
            "lastRoll": self.last_roll.get(player_id, 0),
            # This player's own latest slide (drives the controller
            # haptic); absent/None when their last move was a plain hop.
            "lastSlide": dict(self.last_slide[player_id]) if player_id in self.last_slide else None,
            # True when this player just rolled a 6 and goes again.
            "rollAgain": self.roll_again_pending() and self.last_roller == player_id,
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
