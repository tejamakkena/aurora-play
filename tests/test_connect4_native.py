"""Native-hub Connect 4 (games/native_hub/engines/legacy_boards.py).

tests/test_connect4.py covers the legacy *browser* game; this file covers the
engine the TV/phone apps play, which now seats 2-4 players on a board that
grows with the table (6x7, 7x9, 8x10) and still wins on four in a row.
"""

import pytest

from games.native_hub.engines.legacy_boards import Connect4Engine
from games.native_hub.registry import ENGINES
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(players):
    registry = RoomRegistry()
    room = registry.create("connect4")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    engine = Connect4Engine(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


def drop(engine, col):
    """Drop for whoever's turn it is; returns that player's id."""
    pid = engine.current_player_id()
    engine.handle_action(pid, "drop", {"column": col})
    return pid


def place(engine, cells_by_color):
    """Paint discs directly (for win-detection tests on big boards)."""
    for color, cells in cells_by_color.items():
        for r, c in cells:
            engine.grid[r][c] = color


def seat_of(engine, color):
    return next(pid for pid, col in engine.colors.items() if col == color)


def force_turn(engine, pid):
    engine.turn_index = engine.order.index(pid)


# ---------------------------------------------------------------------------
# Seating and board size
# ---------------------------------------------------------------------------


class TestSeating:
    def test_player_bounds(self):
        assert ENGINES["connect4"] is Connect4Engine
        assert Connect4Engine.min_players == 2
        assert Connect4Engine.max_players == 4

    @pytest.mark.parametrize("players,rows,cols", [(2, 6, 7), (3, 7, 9), (4, 8, 10)])
    def test_board_size_tracks_player_count(self, players, rows, cols):
        engine, _ = make(players)
        state = engine.public_state()
        assert state["rows"] == rows and state["cols"] == cols
        assert len(state["grid"]) == rows
        assert all(len(row) == cols for row in state["grid"])
        assert all(cell == "" for row in state["grid"] for cell in row)

    @pytest.mark.parametrize("players", [2, 3, 4])
    def test_distinct_colours_in_seat_order(self, players):
        engine, roster = make(players)
        expected = ["red", "yellow", "green", "blue"][:players]
        state = engine.public_state()
        assert state["turnOrder"] == [p.id for p in roster]
        assert [state["colors"][p.id] for p in roster] == expected
        for p, colour in zip(roster, expected):
            assert engine.private_state(p.id)["color"] == colour

    def test_private_state_carries_board_shape_for_the_phone(self):
        engine, roster = make(4)
        private = engine.private_state(roster[0].id)
        assert {"isMyTurn", "color", "fullColumns", "rows", "cols", "colors",
                "turnOrder", "currentPlayerID", "currentPlayerName",
                "currentColor"} <= set(private)
        assert private["cols"] == 10 and private["rows"] == 8
        assert private["isMyTurn"] is True
        assert engine.private_state(roster[1].id)["isMyTurn"] is False


# ---------------------------------------------------------------------------
# Turns
# ---------------------------------------------------------------------------


class TestTurnRotation:
    @pytest.mark.parametrize("players", [3, 4])
    def test_turns_rotate_through_every_player(self, players):
        engine, roster = make(players)
        seen = []
        for i in range(players * 2):
            seen.append(drop(engine, i % engine.cols))
        ids = [p.id for p in roster]
        assert seen == ids + ids

    def test_disc_colour_follows_the_mover(self):
        engine, roster = make(3)
        for col in range(3):
            drop(engine, col)
        bottom = engine.grid[engine.rows - 1]
        assert bottom[:3] == ["red", "yellow", "green"]
        assert engine.public_state()["lastMove"] == {
            "row": engine.rows - 1, "col": 2, "color": "green"}
        assert engine.public_state()["moveCount"] == 3

    def test_out_of_turn_and_bad_columns_are_ignored(self):
        engine, roster = make(4)
        engine.handle_action(roster[2].id, "drop", {"column": 0})
        assert engine.grid[engine.rows - 1][0] == ""
        for bad in (-1, 10, "3", None, True, 2.0):
            engine.handle_action(roster[0].id, "drop", {"column": bad})
        assert engine.move_count == 0
        assert engine.current_player_id() == roster[0].id
        # Column 9 only exists on the 4-player board.
        engine.handle_action(roster[0].id, "drop", {"column": 9})
        assert engine.grid[7][9] == "red"

    def test_full_column_is_rejected_and_reported(self):
        engine, _ = make(3)
        for _ in range(engine.rows):
            drop(engine, 4)
        assert 4 in engine.private_state(engine.order[0])["fullColumns"]
        before = engine.current_player_id()
        engine.handle_action(before, "drop", {"column": 4})
        assert engine.current_player_id() == before


class TestDisconnectedPlayers:
    def test_leaving_on_your_turn_passes_the_turn(self):
        engine, roster = make(3)
        drop(engine, 0)                         # p0 -> p1 to move
        roster[1].connected = False
        engine.on_player_leave(roster[1].id)
        assert engine.current_player_id() == roster[2].id

    def test_absent_seats_are_skipped_in_rotation(self):
        engine, roster = make(4)
        roster[2].connected = False
        engine.on_player_leave(roster[2].id)
        order = [drop(engine, i) for i in range(6)]
        assert roster[2].id not in order
        assert order == [roster[0].id, roster[1].id, roster[3].id] * 2

    def test_silent_disconnect_does_not_stall(self):
        # Seat marked absent with no on_player_leave callback at all.
        engine, roster = make(3)
        drop(engine, 0)
        roster[1].connected = False
        assert engine.current_player_id() == roster[2].id
        assert engine.public_state()["currentPlayerID"] == roster[2].id
        drop(engine, 1)
        assert engine.grid[engine.rows - 1][1] == "green"

    def test_removed_player_is_skipped(self):
        engine, roster = make(4)
        engine.room.remove_player(roster[1].id)
        engine.on_player_leave(roster[1].id)
        order = [drop(engine, i) for i in range(3)]
        assert order == [roster[0].id, roster[2].id, roster[3].id]


# ---------------------------------------------------------------------------
# Winning on the bigger boards
# ---------------------------------------------------------------------------


class TestWins:
    def _finish_with(self, engine, color, setup, last):
        """Paint ``setup``, give ``color`` the move and drop at ``last``."""
        place(engine, {color: setup})
        pid = seat_of(engine, color)
        force_turn(engine, pid)
        engine.handle_action(pid, "drop", {"column": last})
        return pid

    def test_horizontal_win_far_right_on_4_player_board(self):
        engine, _ = make(4)
        bottom = engine.rows - 1
        pid = self._finish_with(engine, "blue",
                                [(bottom, 6), (bottom, 7), (bottom, 8)], 9)
        state = engine.public_state()
        assert engine.is_over()
        assert state["winnerID"] == pid
        assert state["winner"] == engine.player_name(pid)
        assert state["winnerColor"] == "blue"
        assert sorted(state["winCells"]) == sorted(
            f"{bottom},{c}" for c in (6, 7, 8, 9))
        assert state["currentPlayerID"] == ""

    def test_vertical_win_on_tall_3_player_board(self):
        engine, _ = make(3)
        # Fill column 8 from the bottom: three yellows then green on top so
        # the vertical four sits in rows 0-3 of a 7-row board.
        col = 8
        place(engine, {"red": [(6, col), (5, col)], "green": [(4, col)]})
        place(engine, {"yellow": [(3, col), (2, col), (1, col)]})
        pid = seat_of(engine, "yellow")
        force_turn(engine, pid)
        engine.handle_action(pid, "drop", {"column": col})
        assert engine.grid[0][col] == "yellow"
        assert engine.winner == pid
        assert sorted(engine.public_state()["winCells"]) == sorted(
            f"{r},{col}" for r in range(4))

    def test_rising_diagonal_win_on_4_player_board(self):
        engine, _ = make(4)
        # Diagonal (7,5) (6,6) (5,7) (4,8) with supporting discs underneath.
        place(engine, {"red": [(7, 6), (7, 7), (6, 7), (7, 8), (6, 8), (5, 8)]})
        pid = self._finish_with(engine, "green", [(7, 5), (6, 6), (5, 7)], 8)
        assert engine.grid[4][8] == "green"
        assert engine.winner == pid
        assert sorted(engine.public_state()["winCells"]) == sorted(
            ["7,5", "6,6", "5,7", "4,8"])

    def test_falling_diagonal_win_on_3_player_board(self):
        engine, _ = make(3)
        # Diagonal (3,0) (4,1) (5,2) (6,3): the last disc lands top-left.
        place(engine, {"yellow": [(6, 0), (5, 0), (4, 0), (6, 1), (5, 1), (6, 2)]})
        pid = self._finish_with(engine, "red", [(4, 1), (5, 2), (6, 3)], 0)
        assert engine.grid[3][0] == "red"
        assert engine.winner == pid
        assert sorted(engine.public_state()["winCells"]) == sorted(
            ["3,0", "4,1", "5,2", "6,3"])

    def test_three_in_a_row_is_not_a_win(self):
        engine, _ = make(4)
        bottom = engine.rows - 1
        self._finish_with(engine, "yellow", [(bottom, 0), (bottom, 1)], 2)
        assert not engine.is_over()

    def test_five_in_a_row_highlights_four_including_the_new_disc(self):
        engine, _ = make(3)
        bottom = engine.rows - 1
        self._finish_with(engine, "green",
                          [(bottom, 0), (bottom, 1), (bottom, 3), (bottom, 4)], 2)
        cells = engine.public_state()["winCells"]
        assert len(cells) == 4 and f"{bottom},2" in cells

    def test_winning_four_from_real_play(self):
        engine, roster = make(3)
        # red builds the bottom row in columns 0-3; yellow and green stack
        # harmlessly in their own columns.
        moves = [0, 5, 7, 1, 5, 7, 2, 6, 8, 3]
        for col in moves:
            drop(engine, col)
        assert engine.winner == roster[0].id
        assert engine.public_state()["winnerColor"] == "red"
        # The game is over: nobody can drop any more.
        engine.handle_action(roster[1].id, "drop", {"column": 4})
        assert engine.grid[engine.rows - 1][4] == ""
        assert engine.results()[0]["playerID"] == roster[0].id


class TestDraw:
    @pytest.mark.parametrize("players", [2, 3, 4])
    def test_full_board_with_no_four_is_a_draw(self, players):
        engine, roster = make(players)
        rows, cols = engine.rows, engine.cols
        # A pattern with no four anywhere (pairs of columns, flipping colour
        # every row) -- then complete it with a real final drop.
        a, b = engine.COLORS[0], engine.COLORS[1]
        for r in range(rows):
            for c in range(cols):
                engine.grid[r][c] = a if ((c // 2) + r) % 2 == 0 else b
        assert engine._check_winner() == (None, [])
        mover_color = engine.grid[0][0]
        engine.grid[0][0] = ""
        pid = seat_of(engine, mover_color)
        force_turn(engine, pid)
        engine.handle_action(pid, "drop", {"column": 0})
        state = engine.public_state()
        assert engine.is_over()
        assert state["isDraw"] is True
        assert state["winner"] is None and state["winnerID"] is None
        assert state["winCells"] == []


# ---------------------------------------------------------------------------
# 2-player backward compatibility
# ---------------------------------------------------------------------------


class TestTwoPlayerCompatibility:
    def test_classic_keys_and_values(self):
        engine, roster = make(2)
        state = engine.public_state()
        assert {"grid", "currentPlayerID", "currentPlayerName", "winner",
                "winCells", "players", "secondsLeft"} <= set(state)
        assert len(state["grid"]) == 6 and len(state["grid"][0]) == 7
        assert state["currentPlayerID"] == roster[0].id
        assert state["currentPlayerName"] == "P0"
        assert state["winner"] is None
        private = engine.private_state(roster[1].id)
        assert {"isMyTurn", "color", "fullColumns", "secondsLeft",
                "score"} <= set(private)
        assert private["color"] == "yellow"

    def test_classic_vertical_game(self):
        engine, roster = make(2)
        for col in [0, 1, 0, 1, 0, 1, 0]:
            drop(engine, col)
        state = engine.public_state()
        assert state["winner"] == "P0"           # name, as the app has always read
        assert state["winnerID"] == roster[0].id
        assert sorted(state["winCells"]) == ["2,0", "3,0", "4,0", "5,0"]
        assert roster[0].score == 1

    def test_column_7_is_out_of_range_on_the_classic_board(self):
        engine, roster = make(2)
        engine.handle_action(roster[0].id, "drop", {"column": 7})
        assert engine.move_count == 0
