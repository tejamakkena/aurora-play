from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string
import time

# Store active pictionary rooms
pictionary_rooms = {}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(
            random.choices(
                string.ascii_uppercase +
                string.digits,
                k=6))
        if code not in pictionary_rooms:
            return code


# Word list for drawing
WORD_CATEGORIES = {
    'easy': [
        'cat', 'dog', 'house', 'tree', 'sun', 'moon', 'star', 'car',
        'boat', 'fish', 'bird', 'apple', 'book', 'chair', 'table', 'bed',
        'flower', 'hat', 'shoe', 'ball', 'cup', 'pizza', 'smile', 'heart'
    ],
    'medium': [
        'elephant', 'guitar', 'telephone', 'computer', 'bicycle', 'helicopter',
        'umbrella', 'sunglasses', 'butterfly', 'rainbow', 'volcano', 'spaceship',
        'dinosaur', 'waterfall', 'snowman', 'lighthouse', 'treasure', 'castle',
        'dragon', 'rocket', 'fountain', 'circus', 'pyramid', 'penguin'
    ],
    'hard': [
        'microscope', 'chandelier', 'silhouette', 'parachute', 'constellation',
        'archaeology', 'submarine', 'kaleidoscope', 'hieroglyphics', 'photosynthesis',
        'skyscraper', 'tornado', 'constellation', 'avalanche', 'metamorphosis',
        'orchestra', 'laboratory', 'architecture', 'biography', 'democracy'
    ]
}


def get_random_word(difficulty='medium'):
    """Get a random word based on difficulty"""
    return random.choice(WORD_CATEGORIES.get(difficulty, WORD_CATEGORIES['medium']))


def register_pictionary_events(socketio):
    """Register all Pictionary socket events"""

    @socketio.on('create_pictionary_room')
    def handle_create_room(data):
        """Create a new pictionary room"""
        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid
        time_limit = data.get('time_limit', 60)  # seconds per turn
        max_rounds = data.get('max_rounds', 3)
        difficulty = data.get('difficulty', 'medium')

        print(f"\n{'=' * 60}")
        print(f"🎨 CREATING PICTIONARY ROOM")
        print(f"Room code: {room_code}")
        print(f"Host: {player_name}")
        print(f"Time limit: {time_limit}s")
        print(f"Difficulty: {difficulty}")

        pictionary_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'is_host': True,
                'ready': False,
                'score': 0,
                'is_drawing': False
            }],
            'status': 'waiting',  # waiting, playing, finished
            'time_limit': time_limit,
            'round': 0,
            'max_rounds': max_rounds,
            'difficulty': difficulty,
            'current_word': None,
            'current_drawer': None,
            'drawer_index': 0,
            'round_start_time': None,
            'guessed_players': [],
            'drawing_data': []
        }

        join_room(room_code)

        print(f"✅ Pictionary room created")
        print(f"{'=' * 60}\n")

        emit('pictionary_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': pictionary_rooms[room_code]['players'],
            'time_limit': time_limit,
            'max_rounds': max_rounds,
            'difficulty': difficulty
        })

    @socketio.on('join_pictionary_room')
    def handle_join_room(data):
        """Join an existing pictionary room"""
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"🚪 JOINING PICTIONARY ROOM")
        print(f"Room code: {room_code}")
        print(f"Player: {player_name}")

        if room_code not in pictionary_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            emit('pictionary_error', {'message': 'Room not found!'})
            return

        room = pictionary_rooms[room_code]

        if room['status'] != 'waiting':
            print(f"❌ Game already in progress")
            print(f"{'=' * 60}\n")
            emit('pictionary_error', {'message': 'Game already in progress!'})
            return

        if len(room['players']) >= 8:
            print(f"❌ Room is full")
            print(f"{'=' * 60}\n")
            emit('pictionary_error', {'message': 'Room is full! (Max 8 players)'})
            return

        room['players'].append({
            'id': player_id,
            'name': player_name,
            'is_host': False,
            'ready': False,
            'score': 0,
            'is_drawing': False
        })

        join_room(room_code)

        print(f"✅ Player joined")
        print(f"Total players: {len(room['players'])}")
        print(f"{'=' * 60}\n")

        emit('pictionary_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players']
        }, to=request.sid)

        emit('pictionary_player_joined', {
            'player_name': player_name,
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('pictionary_player_ready')
    def handle_player_ready(data):
        """Mark player as ready"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in pictionary_rooms:
            return

        room = pictionary_rooms[room_code]

        for player in room['players']:
            if player['id'] == player_id:
                player['ready'] = True
                break

        socketio.emit('pictionary_ready_update', {
            'players': room['players']
        }, room=room_code)

    @socketio.on('start_pictionary_game')
    def handle_start_game(data):
        """Start the pictionary game"""
        room_code = data.get('room_code', '').upper()

        print(f"\n{'=' * 60}")
        print(f"🎮 STARTING PICTIONARY - Room: {room_code}")

        if room_code not in pictionary_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            return

        room = pictionary_rooms[room_code]

        if request.sid != room['host']:
            print(f"❌ Only host can start")
            print(f"{'=' * 60}\n")
            emit('pictionary_error', {'message': 'Only host can start the game!'})
            return

        if len(room['players']) < 2:
            print(f"❌ Need at least 2 players")
            print(f"{'=' * 60}\n")
            emit('pictionary_error', {'message': 'Need at least 2 players to start!'})
            return

        print(f"✅ Game starting with {len(room['players'])} players")
        print(f"{'=' * 60}\n")

        start_turn(room_code, socketio)

    def start_turn(room_code, socketio):
        """Start a new drawing turn"""
        room = pictionary_rooms[room_code]
        room['round'] += 1
        room['status'] = 'playing'
        room['round_start_time'] = time.time()
        room['guessed_players'] = []
        room['drawing_data'] = []

        # Rotate drawer
        drawer_index = room['drawer_index']
        current_drawer = room['players'][drawer_index]
        room['current_drawer'] = current_drawer['id']

        # Set drawing status
        for player in room['players']:
            player['is_drawing'] = (player['id'] == current_drawer['id'])

        # Get word to draw
        room['current_word'] = get_random_word(room['difficulty'])

        # Move to next drawer for next turn
        room['drawer_index'] = (drawer_index + 1) % len(room['players'])

        print(f"\n🎨 Round {room['round']} - {current_drawer['name']} is drawing: {room['current_word']}")

        # Send word to drawer only
        socketio.emit('turn_start_drawer', {
            'round': room['round'],
            'max_rounds': room['max_rounds'],
            'word': room['current_word'],
            'time_limit': room['time_limit'],
            'drawer_name': current_drawer['name']
        }, room=current_drawer['id'])

        # Send masked info to guessers
        word_hint = '_' * len(room['current_word'])
        socketio.emit('turn_start_guesser', {
            'round': room['round'],
            'max_rounds': room['max_rounds'],
            'word_hint': word_hint,
            'word_length': len(room['current_word']),
            'time_limit': room['time_limit'],
            'drawer_name': current_drawer['name']
        }, room=room_code, skip_sid=current_drawer['id'])

    @socketio.on('draw_action')
    def handle_draw_action(data):
        """Handle drawing actions (pen strokes)"""
        room_code = data.get('room_code', '').upper()
        action = data.get('action')  # 'draw', 'erase', 'clear'
        
        if room_code not in pictionary_rooms:
            return

        room = pictionary_rooms[room_code]
        player_id = request.sid

        # Only current drawer can draw
        if room['current_drawer'] != player_id:
            return

        # Store drawing action
        room['drawing_data'].append(action)

        # Broadcast to all other players in room
        socketio.emit('drawing_update', {
            'action': action
        }, room=room_code, skip_sid=player_id)

    @socketio.on('submit_guess')
    def handle_guess(data):
        """Handle guess submission"""
        room_code = data.get('room_code', '').upper()
        guess = data.get('guess', '').strip().lower()
        player_id = request.sid

        if room_code not in pictionary_rooms:
            return

        room = pictionary_rooms[room_code]

        # Ignore guesses when there is no live turn (between rounds, or a
        # late guess for a turn that already ended).
        if room['status'] != 'playing' or not room['current_word']:
            return

        # Can't guess if you're the drawer
        if room['current_drawer'] == player_id:
            return

        # Can't guess if already guessed correctly
        if player_id in room['guessed_players']:
            return

        correct_word = room['current_word'].lower()

        # Find player
        player_name = None
        for player in room['players']:
            if player['id'] == player_id:
                player_name = player['name']
                break

        # Broadcast guess to room
        socketio.emit('player_guessed', {
            'player_name': player_name,
            'guess': guess
        }, room=room_code)

        # Check if correct
        if guess == correct_word:
            # Calculate points based on time and order
            elapsed = time.time() - room['round_start_time']
            time_bonus = max(0, int((room['time_limit'] - elapsed) / 10))
            position_bonus = max(0, 10 - len(room['guessed_players']) * 2)
            points = 10 + time_bonus + position_bonus

            # Award points to guesser
            for player in room['players']:
                if player['id'] == player_id:
                    player['score'] += points
                    break

            # Award points to drawer
            for player in room['players']:
                if player['id'] == room['current_drawer']:
                    player['score'] += 5
                    break

            # Mark as guessed
            room['guessed_players'].append(player_id)

            print(f"✅ {player_name} guessed correctly! +{points} points")

            socketio.emit('correct_guess', {
                'player_name': player_name,
                'points': points,
                'players': room['players']
            }, room=room_code)

            # If all players guessed, end turn
            if len(room['guessed_players']) >= len(room['players']) - 1:
                end_turn(room_code, socketio)

    @socketio.on('time_up')
    def handle_time_up(data):
        """Handle time running out"""
        room_code = data.get('room_code', '').upper()

        if room_code not in pictionary_rooms:
            return

        room = pictionary_rooms[room_code]

        # Only drawer can trigger time up
        if request.sid == room['current_drawer']:
            end_turn(room_code, socketio)

    def end_turn(room_code, socketio):
        """End current turn"""
        room = pictionary_rooms[room_code]

        print(f"\n⏰ Turn ended - Word was: {room['current_word']}")

        socketio.emit('turn_end', {
            'word': room['current_word'],
            'players': room['players'],
            'guessed_count': len(room['guessed_players'])
        }, room=room_code)

        # No live word anymore, so guesses between turns are ignored
        room['current_word'] = None

        # Check if game is over
        if room['round'] >= room['max_rounds'] * len(room['players']):
            end_game(room_code, socketio)

    @socketio.on('next_turn')
    def handle_next_turn(data):
        """Start next turn"""
        room_code = data.get('room_code', '').upper()

        if room_code not in pictionary_rooms:
            return

        room = pictionary_rooms[room_code]

        # Only host can start next turn
        if request.sid != room['host']:
            return

        # Game is over; only a fresh start can revive it
        if room['status'] != 'playing':
            emit('pictionary_error', {'message': 'Game is over'})
            return

        start_turn(room_code, socketio)

    def end_game(room_code, socketio):
        """End the game and show final results"""
        room = pictionary_rooms[room_code]
        room['status'] = 'finished'

        # Sort by score
        final_results = sorted(
            room['players'],
            key=lambda p: p['score'],
            reverse=True
        )

        print(f"\n🎉 GAME OVER - Final Results:")
        for i, player in enumerate(final_results):
            print(f"{i + 1}. {player['name']}: {player['score']} points")

        socketio.emit('game_over', {
            'final_results': [{
                'name': p['name'],
                'score': p['score'],
                'rank': i + 1
            } for i, p in enumerate(final_results)]
        }, room=room_code)

    @socketio.on('leave_pictionary_room')
    def handle_leave_room(data):
        """Leave pictionary room"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in pictionary_rooms:
            return

        room = pictionary_rooms[room_code]

        # Remove player
        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        leave_room(room_code)

        if len(room['players']) == 0:
            # Delete empty room
            del pictionary_rooms[room_code]
            print(f"🗑️ Room {room_code} deleted (empty)")
        else:
            # If host left, assign new host
            if room['host'] == player_id and len(room['players']) > 0:
                room['host'] = room['players'][0]['id']
                room['players'][0]['is_host'] = True

            # If drawer left during game, end turn
            if room['current_drawer'] == player_id and room['status'] == 'playing':
                end_turn(room_code, socketio)
            else:
                socketio.emit('pictionary_player_left', {
                    'players': room['players']
                }, room=room_code)

    print("✅ Pictionary socket events registered")
