from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string

# Store active Connect4 rooms
connect4_rooms = {}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(
            random.choices(
                string.ascii_uppercase +
                string.digits,
                k=6))
        if code not in connect4_rooms:
            return code


def check_winner(board):
    """Check if there's a winner on the board"""
    # Check horizontal
    for row in range(6):
        for col in range(4):
            if board[row][col] and board[row][col] == board[row][col +
                                                                 1] == board[row][col + 2] == board[row][col + 3]:
                return board[row][col], [
                    (row, col), (row, col + 1), (row, col + 2), (row, col + 3)]

    # Check vertical
    for row in range(3):
        for col in range(7):
            if board[row][col] and board[row][col] == board[row +
                                                            1][col] == board[row + 2][col] == board[row + 3][col]:
                return board[row][col], [
                    (row, col), (row + 1, col), (row + 2, col), (row + 3, col)]

    # Check diagonal (down-right)
    for row in range(3):
        for col in range(4):
            if board[row][col] and board[row][col] == board[row + 1][col +
                                                                     1] == board[row + 2][col + 2] == board[row + 3][col + 3]:
                return board[row][col], [
                    (row, col), (row + 1, col + 1), (row + 2, col + 2), (row + 3, col + 3)]

    # Check diagonal (down-left)
    for row in range(3):
        for col in range(3, 7):
            if board[row][col] and board[row][col] == board[row + 1][col -
                                                                     1] == board[row + 2][col - 2] == board[row + 3][col - 3]:
                return board[row][col], [
                    (row, col), (row + 1, col - 1), (row + 2, col - 2), (row + 3, col - 3)]

    return None, []


def register_connect4_events(socketio):
    """Register all Connect4 socket events"""

    @socketio.on('create_room', namespace='/connect4')
    def handle_create_room(data):
        """Create a new Connect4 room"""
        if data.get('game_type') != 'connect4':
            return

        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player 1')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"🔴 CREATING CONNECT4 ROOM")
        print(f"Room code: {room_code}")
        print(f"Host: {player_name}")
        print(f"Player ID: {player_id}")

        connect4_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'color': 'red',
                'is_host': True
            }],
            'status': 'waiting',
            'board': [[None for _ in range(7)] for _ in range(6)],
            'current_turn': 'red',
            'game_started': False
        }

        join_room(room_code)

        print(f"✅ Room created successfully")
        print(f"{'=' * 60}\n")

        # FIXED: Include players array in response
        emit('room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': connect4_rooms[room_code]['players'],  # ADD THIS
            'your_color': 'red',
            'is_host': True
        })

    @socketio.on('join_room', namespace='/connect4')
    def handle_join_room(data):
        """Join an existing Connect4 room"""
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player 2')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"🟡 JOINING CONNECT4 ROOM")
        print(f"Room code: {room_code}")
        print(f"Player: {player_name}")

        if room_code not in connect4_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            emit('error', {'message': 'Room not found!'})
            return

        room = connect4_rooms[room_code]

        if room['status'] != 'waiting':
            print(f"❌ Game already in progress")
            print(f"{'=' * 60}\n")
            emit('error', {'message': 'Game already in progress!'})
            return

        if len(room['players']) >= 2:
            print(f"❌ Room is full")
            print(f"{'=' * 60}\n")
            emit('error', {'message': 'Room is full!'})
            return

        room['players'].append({
            'id': player_id,
            'name': player_name,
            'color': 'yellow',
            'is_host': False
        })

        join_room(room_code)

        print(f"✅ Player joined")
        print(f"Total players: {len(room['players'])}")
        print(f"{'=' * 60}\n")

        emit('room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players'],
            'your_color': 'yellow',
            'is_host': False
        }, to=player_id)

        emit('player_joined', {
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('start_game', namespace='/connect4')
    def handle_start_game(data):
        """Start the Connect4 game"""
        room_code = data.get('room_code', '').upper()

        print(f"\n{'=' * 60}")
        print(f"🎮 STARTING CONNECT4 GAME")
        print(f"Room: {room_code}")

        if room_code not in connect4_rooms:
            emit('error', {'message': 'Room not found'})
            return

        room = connect4_rooms[room_code]

        if request.sid != room['host']:
            print(f"❌ Only host can start")
            print(f"{'=' * 60}\n")
            emit('error', {'message': 'Only host can start the game!'})
            return

        if len(room['players']) != 2:
            print(f"❌ Need exactly 2 players")
            print(f"{'=' * 60}\n")
            emit('error', {'message': 'Need 2 players to start!'})
            return

        if room['status'] == 'playing':
            emit('error', {'message': 'Game already in progress!'})
            return

        room['status'] = 'playing'
        room['game_started'] = True
        room['current_turn'] = 'red'
        # Reset the board: play-again returns to the waiting room and calls
        # start again, so a stale board would desync the second game.
        room['board'] = [[None for _ in range(7)] for _ in range(6)]

        print(f"✅ Game started")
        print(f"{'=' * 60}\n")

        socketio.emit('game_started', {
            'board': room['board'],
            'current_turn': room['current_turn']
        }, room=room_code)

    @socketio.on('make_move', namespace='/connect4')
    def handle_make_move(data):
        """Handle a player's move"""
        room_code = data.get('room_code', '').upper()
        column = data.get('column')
        player_id = request.sid

        if not isinstance(column, int) or isinstance(column, bool) or not 0 <= column <= 6:
            emit('error', {'message': 'Invalid column!'})
            return

        print(f"\n{'=' * 40}")
        print(f"🎯 MAKE MOVE")
        print(f"Room: {room_code}")
        print(f"Column: {column}")

        if room_code not in connect4_rooms:
            emit('error', {'message': 'Room not found'})
            return

        room = connect4_rooms[room_code]

        # Find player
        player = None
        for p in room['players']:
            if p['id'] == player_id:
                player = p
                break

        if not player:
            print(f"❌ Player not found")
            emit('error', {'message': 'Player not found'})
            return

        if player['color'] != room['current_turn']:
            print(f"❌ Not player's turn")
            emit('error', {'message': 'Not your turn!'})
            return

        # Find lowest empty row in column
        row = None
        for r in range(5, -1, -1):
            if room['board'][r][column] is None:
                row = r
                break

        if row is None:
            print(f"❌ Column is full")
            emit('error', {'message': 'Column is full!'})
            return

        # Place piece
        room['board'][row][column] = player['color']

        print(f"✅ Piece placed at ({row}, {column})")

        # Check for winner
        winner, winning_cells = check_winner(room['board'])

        if winner:
            print(f"🏆 Winner: {winner}")
            print(f"{'=' * 40}\n")

            room['status'] = 'finished'

            socketio.emit('game_over', {
                'winner': winner,
                'winning_cells': winning_cells,
                'reason': 'connect4'
            }, room=room_code)
            return

        # Check for draw
        is_full = all(room['board'][0][c] is not None for c in range(7))
        if is_full:
            print(f"🤝 Draw!")
            print(f"{'=' * 40}\n")

            room['status'] = 'finished'

            socketio.emit('game_over', {
                'winner': 'draw',
                'winning_cells': [],
                'reason': 'board_full'
            }, room=room_code)
            return

        # Switch turn
        room['current_turn'] = 'yellow' if room['current_turn'] == 'red' else 'red'

        print(f"Next turn: {room['current_turn']}")
        print(f"{'=' * 40}\n")

        socketio.emit('move_made', {
            'board': room['board'],
            'current_turn': room['current_turn']
        }, room=room_code)

    @socketio.on('leave_room', namespace='/connect4')
    def handle_leave_room(data):
        """Handle player leaving room"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        print(f"\n{'=' * 40}")
        print(f"🚪 PLAYER LEAVING")
        print(f"Room: {room_code}")

        if room_code not in connect4_rooms:
            return

        room = connect4_rooms[room_code]

        # Remove player
        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        leave_room(room_code)

        if len(room['players']) == 0:
            # Delete empty room
            del connect4_rooms[room_code]
            print(f"🗑️ Room deleted (empty)")
        else:
            # Notify remaining players
            socketio.emit('player_left', {
                'players': room['players']
            }, room=room_code)
            print(f"✅ Player left, {len(room['players'])} remaining")

        print(f"{'=' * 40}\n")

    print("✅ Connect4 socket events registered")
