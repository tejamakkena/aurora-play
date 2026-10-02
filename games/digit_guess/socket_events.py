from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string
from .game_logic import validate_number, calculate_feedback, check_winner

# Store active Digit Guess rooms
digit_guess_rooms = {}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(
            random.choices(
                string.ascii_uppercase +
                string.digits,
                k=6))
        if code not in digit_guess_rooms:
            return code


def register_digit_guess_events(socketio):
    """Register all Digit Guess socket events"""

    @socketio.on('create_room', namespace='/digit_guess')
    def handle_create_room(data):
        """Create a new Digit Guess room"""
        if data.get('game_type') != 'digit_guess':
            return

        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player 1')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"🔢 CREATING DIGIT GUESS ROOM")
        print(f"Room code: {room_code}")
        print(f"Host: {player_name}")
        print(f"Player ID: {player_id}")

        digit_guess_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'is_host': True,
                'secret_number': None,
                'ready': False
            }],
            'status': 'waiting',  # waiting, setting_numbers, playing, finished
            'current_turn': None,  # player_id of whose turn it is
            'guesses': {player_id: []},  # player_id -> list of {guess, feedback}
            'game_started': False
        }

        join_room(room_code)

        print(f"✅ Room created successfully")
        print(f"{'=' * 60}\n")

        emit('room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': digit_guess_rooms[room_code]['players'],
            'is_host': True
        })

    @socketio.on('join_room', namespace='/digit_guess')
    def handle_join_room(data):
        """Join an existing Digit Guess room"""
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player 2')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"🔢 JOINING DIGIT GUESS ROOM")
        print(f"Room code: {room_code}")
        print(f"Player: {player_name}")

        if room_code not in digit_guess_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            emit('error', {'message': 'Room not found!'})
            return

        room = digit_guess_rooms[room_code]

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
            'is_host': False,
            'secret_number': None,
            'ready': False
        })
        
        room['guesses'][player_id] = []

        join_room(room_code)

        print(f"✅ Player joined")
        print(f"Total players: {len(room['players'])}")
        print(f"{'=' * 60}\n")

        emit('room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players'],
            'is_host': False
        }, to=player_id)

        emit('player_joined', {
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('start_game', namespace='/digit_guess')
    def handle_start_game(data):
        """Start the Digit Guess game - move to number setting phase"""
        room_code = data.get('room_code', '').upper()

        print(f"\n{'=' * 60}")
        print(f"🎮 STARTING DIGIT GUESS GAME")
        print(f"Room: {room_code}")

        if room_code not in digit_guess_rooms:
            emit('error', {'message': 'Room not found'})
            return

        room = digit_guess_rooms[room_code]

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

        room['status'] = 'setting_numbers'
        room['game_started'] = True

        print(f"✅ Game started - players setting numbers")
        print(f"{'=' * 60}\n")

        socketio.emit('game_started', {
            'status': 'setting_numbers'
        }, room=room_code)

    @socketio.on('set_secret_number', namespace='/digit_guess')
    def handle_set_secret_number(data):
        """Player sets their secret number"""
        room_code = data.get('room_code', '').upper()
        secret_number = str(data.get('secret_number') or '').strip()
        player_id = request.sid

        print(f"\n{'=' * 40}")
        print(f"🔒 SET SECRET NUMBER")
        print(f"Room: {room_code}")
        print(f"Player: {player_id}")

        if room_code not in digit_guess_rooms:
            emit('error', {'message': 'Room not found'})
            return

        room = digit_guess_rooms[room_code]

        if room['status'] != 'setting_numbers':
            emit('error', {'message': 'Numbers are not being set right now'})
            return

        # Validate number
        is_valid, error_msg = validate_number(secret_number)
        if not is_valid:
            print(f"❌ Invalid number: {error_msg}")
            emit('error', {'message': error_msg})
            return

        # Find player and set their secret number
        player = None
        for p in room['players']:
            if p['id'] == player_id:
                player = p
                break

        if not player:
            emit('error', {'message': 'Player not found'})
            return

        player['secret_number'] = secret_number
        player['ready'] = True

        print(f"✅ Secret number set")

        # Check if both players are ready
        all_ready = all(p['ready'] for p in room['players'])

        emit('number_set', {
            'success': True,
            'all_ready': all_ready
        }, to=player_id)

        if all_ready:
            # Start the guessing phase
            room['status'] = 'playing'
            # First player (host) goes first
            room['current_turn'] = room['players'][0]['id']

            print(f"✅ Both players ready - starting guessing phase")
            print(f"First turn: {room['current_turn']}")
            print(f"{'=' * 40}\n")

            socketio.emit('guessing_phase_started', {
                'current_turn': room['current_turn'],
                'players': room['players']
            }, room=room_code)

    @socketio.on('make_guess', namespace='/digit_guess')
    def handle_make_guess(data):
        """Player makes a guess at opponent's number"""
        room_code = data.get('room_code', '').upper()
        guess = str(data.get('guess') or '').strip()
        player_id = request.sid

        print(f"\n{'=' * 40}")
        print(f"🎯 MAKE GUESS")
        print(f"Room: {room_code}")
        print(f"Guess: {guess}")

        if room_code not in digit_guess_rooms:
            emit('error', {'message': 'Room not found'})
            return

        room = digit_guess_rooms[room_code]

        # Ignore guesses outside the guessing phase (e.g. a late or double
        # guess after the game already ended).
        if room['status'] != 'playing':
            emit('error', {'message': 'Game is not in the guessing phase'})
            return

        # Check if it's player's turn
        if room['current_turn'] != player_id:
            print(f"❌ Not player's turn")
            emit('error', {'message': 'Not your turn!'})
            return

        # Validate guess
        is_valid, error_msg = validate_number(guess)
        if not is_valid:
            print(f"❌ Invalid guess: {error_msg}")
            emit('error', {'message': error_msg})
            return

        # Find opponent
        opponent = None
        current_player = None
        for p in room['players']:
            if p['id'] == player_id:
                current_player = p
            else:
                opponent = p

        if not opponent or not current_player:
            emit('error', {'message': 'Opponent not found'})
            return

        # Calculate feedback
        feedback = calculate_feedback(opponent['secret_number'], guess)

        # Store guess in history
        room['guesses'][player_id].append({
            'guess': guess,
            'feedback': feedback
        })

        print(f"✅ Guess processed")
        print(f"Feedback: {feedback}")

        # Check if player won
        if check_winner(guess, opponent['secret_number']):
            print(f"🏆 Winner: {current_player['name']}")
            print(f"{'=' * 40}\n")

            room['status'] = 'finished'

            socketio.emit('game_over', {
                'winner_id': player_id,
                'winner_name': current_player['name'],
                'secret_numbers': {
                    p['id']: p['secret_number'] for p in room['players']
                }
            }, room=room_code)
            return

        # Switch turn
        room['current_turn'] = opponent['id']

        print(f"Next turn: {opponent['name']}")
        print(f"{'=' * 40}\n")

        socketio.emit('guess_made', {
            'player_id': player_id,
            'player_name': current_player['name'],
            'guess': guess,
            'feedback': feedback,
            'current_turn': room['current_turn'],
            'guess_history': room['guesses']
        }, room=room_code)

    @socketio.on('leave_room', namespace='/digit_guess')
    def handle_leave_room(data):
        """Handle player leaving room"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        print(f"\n{'=' * 40}")
        print(f"🚪 PLAYER LEAVING")
        print(f"Room: {room_code}")

        if room_code not in digit_guess_rooms:
            return

        room = digit_guess_rooms[room_code]

        # Remove player
        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        leave_room(room_code)

        if len(room['players']) == 0:
            # Delete empty room
            del digit_guess_rooms[room_code]
            print(f"🗑️ Room deleted (empty)")
        else:
            # Notify remaining players
            socketio.emit('player_left', {
                'players': room['players']
            }, room=room_code)
            print(f"✅ Player left, {len(room['players'])} remaining")

        print(f"{'=' * 40}\n")

    print("✅ Digit Guess socket events registered")
