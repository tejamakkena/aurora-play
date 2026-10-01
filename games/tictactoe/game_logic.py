class TicTacToeGame:
    """Tic Tac Toe Game Logic - NOT inheriting from BaseGame to avoid abstract issues"""

    def __init__(self, room_code):
        self.room_code = room_code
        self.board = [''] * 9
        self.players = {}
        self.current_turn = '⭕'  # Changed from 'X' to neon circle
        self.winner = None
        self.is_draw = False
        self.state = "WAITING"

    def initialize_game(self):
        """Initialize game state"""
        self.board = [''] * 9
        self.current_turn = '⭕'
        self.winner = None
        self.is_draw = False
        self.state = "WAITING"

    def add_player(self, player_id):
        """Add a player to the game"""
        if len(self.players) == 0:
            self.players[player_id] = '⭕'  # First player gets circle
        elif len(self.players) == 1:
            self.players[player_id] = '❌'  # Second player gets X
            self.state = "PLAYING"
        return self.players.get(player_id)

    def make_move(self, player_id, position):
        """Process a player's move"""
        if self.winner or self.is_draw:
            return {'success': False, 'error': 'Game over'}

        if self.players.get(player_id) != self.current_turn:
            return {'success': False, 'error': 'Not your turn'}

        if self.board[position] != '':
            return {'success': False, 'error': 'Position already taken'}

        self.board[position] = self.current_turn

        winner = self.check_winner()
        if winner:
            self.winner = winner
            self.state = "FINISHED"
        elif '' not in self.board:
            self.is_draw = True
            self.state = "FINISHED"
        else:
            self.current_turn = '❌' if self.current_turn == '⭕' else '⭕'

        return {
            'success': True,
            'game_state': self.get_game_state()
        }

    def check_winner(self):
        """Check if there's a winner"""
        winning_combinations = [
            [0, 1, 2], [3, 4, 5], [6, 7, 8],  # rows
            [0, 3, 6], [1, 4, 7], [2, 5, 8],  # columns
            [0, 4, 8], [2, 4, 6]              # diagonals
        ]

        for combo in winning_combinations:
            if (self.board[combo[0]] and self.board[combo[0]] ==
                    self.board[combo[1]] == self.board[combo[2]]):
                return self.board[combo[0]]

        return None

    def get_game_state(self):
        """Get current game state"""
        return {
            'board': self.board,
            'current_turn': self.current_turn,
            'winner': self.winner,
            'is_draw': self.is_draw,
            'state': self.state,
            'players': self.players
        }


_WINNING_COMBINATIONS = (
    (0, 1, 2), (3, 4, 5), (6, 7, 8),
    (0, 3, 6), (1, 4, 7), (2, 5, 8),
    (0, 4, 8), (2, 4, 6),
)


def _cell(board, i):
    v = board[i]
    return v if v not in (None, "") else None


def check_winner(board):
    """Return the winning mark ('X'/'O'/...), or None. Module-level helper."""
    for a, b, c in _WINNING_COMBINATIONS:
        ca, cb, cc = _cell(board, a), _cell(board, b), _cell(board, c)
        if ca and ca == cb == cc:
            return ca
    return None


def check_draw(board):
    """True when the board is full and nobody won."""
    return all(_cell(board, i) for i in range(9)) and check_winner(board) is None


def get_ai_move(board, symbol):
    """Pick a move: win if possible, block if needed, else first open cell."""
    import random
    open_cells = [i for i in range(9) if not _cell(board, i)]
    if not open_cells:
        raise ValueError("no moves left")
    for i in open_cells:
        trial = list(board)
        trial[i] = symbol
        if check_winner(trial) == symbol:
            return i
    opponent = "O" if symbol == "X" else "X"
    for i in open_cells:
        trial = list(board)
        trial[i] = opponent
        if check_winner(trial) == opponent:
            return i
    return random.choice(open_cells)
