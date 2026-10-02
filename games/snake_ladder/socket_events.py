from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string
import threading

# Store active rooms
snake_rooms = {}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(
            random.choices(
                string.ascii_uppercase +
                string.digits,
                k=6))
        if code not in snake_rooms:
            return code


def cleanup_room(socketio_instance, room_code):
    """Clean up room after delay"""
    import time
    time.sleep(30)
    if room_code in snake_rooms:
        del snake_rooms[room_code]
        print(f"🗑️ Room {room_code} cleaned up")


def register_snake_events(socketio):
    """Register all Snake & Ladder socket events"""

    @socketio.on('create_snake_room')
    def handle_create_room(data):
        """Create a new game room"""
        print(f"🎮 Creating Snake room...")

        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        # Create room
        snake_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'is_host': True,
                'position': 0
            }],
            'status': 'waiting',
            'max_players': 6,
            'current_player': 0,
            'game_started': False
        }

        # Join socket room
        join_room(room_code)

        print(f"✅ Room created: {room_code} by {player_name}")
        print(f"📊 Room state: {snake_rooms[room_code]}")

        emit('snake_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': snake_rooms[room_code]['players']
        })

    @socketio.on('join_snake_room')
    def handle_join_room(data):
        """Join an existing game room"""
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        print(
            f"🎮 {player_name} (ID: {player_id}) trying to join room {room_code}...")
        print(f"📋 Available rooms: {list(snake_rooms.keys())}")

        # Validate room exists
        if room_code not in snake_rooms:
            print(f"❌ Room {room_code} not found!")
            emit('snake_error', {'message': f'Room {room_code} not found!'})
            return

        room = snake_rooms[room_code]

        # Check if player already in room
        if any(p['id'] == player_id for p in room['players']):
            print(f"⚠️ Player already in room {room_code}")
            emit('snake_room_joined', {
                'room_code': room_code,
                'player_id': player_id,
                'players': room['players']
            })
            return

        # Check if room is full
        if len(room['players']) >= room['max_players']:
            print(f"❌ Room {room_code} is full!")
            emit('snake_error', {'message': 'Room is full!'})
            return

        # Check if game already started
        if room['game_started']:
            print(f"❌ Game already started in room {room_code}")
            emit('snake_error', {'message': 'Game already in progress!'})
            return

        # Add player to room
        room['players'].append({
            'id': player_id,
            'name': player_name,
            'is_host': False,
            'position': 0
        })

        # Join socket room
        join_room(room_code)

        print(f"✅ {player_name} joined room {room_code}")
        print(
            f"📊 Room now has {len(room['players'])} players: {[p['name'] for p in room['players']]}")

        # Notify the joining player
        emit('snake_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players']
        }, to=request.sid)

        # Notify ALL players in the room (including host) with updated player
        # list
        emit('snake_player_joined', {
            'player_name': player_name,
            'players': room['players'],
            'player_count': len(room['players'])
        }, room=room_code, include_self=True)

        print(
            f"📤 Broadcasted player join to all {len(room['players'])} players in room {room_code}")

    @socketio.on('leave_snake_room')
    def handle_leave_room(data):
        """Leave a game room"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in snake_rooms:
            return

        room = snake_rooms[room_code]

        # Find player name before removing
        player = next(
            (p for p in room['players'] if p['id'] == player_id),
            None)
        player_name = player['name'] if player else 'Unknown'

        # Remove player
        removed_index = next(
            (i for i, p in enumerate(room['players']) if p['id'] == player_id),
            None)
        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        # Keep the turn pointer valid after a mid-game leave
        if removed_index is not None and room['players']:
            if removed_index < room['current_player']:
                room['current_player'] -= 1
            elif removed_index == room['current_player']:
                # The player whose turn it was left; the next player in line
                # (now sitting at this index) keeps the turn.
                pass
            room['current_player'] %= len(room['players'])

        # Leave socket room
        leave_room(room_code)

        print(f"👋 {player_name} left room {room_code}")

        # If room is empty, delete it
        if len(room['players']) == 0:
            del snake_rooms[room_code]
            print(f"🗑️ Empty room {room_code} deleted")
            return

        # If host left, assign new host
        if room['host'] == player_id and len(room['players']) > 0:
            room['host'] = room['players'][0]['id']
            room['players'][0]['is_host'] = True
            print(
                f"👑 New host assigned in room {room_code}: "
                f"{room['players'][0]['name']}")

        # Notify remaining players
        emit('snake_player_left', {
            'player_name': player_name,
            'players': room['players']
        }, room=room_code)

    @socketio.on('get_snake_rooms')
    def handle_get_rooms():
        """Get list of available rooms"""
        print(f"📋 Getting rooms list... Total rooms: {len(snake_rooms)}")

        rooms_list = [{
            'code': room['code'],
            'player_count': len(room['players']),
            'max_players': room['max_players'],
            'status': room['status']
        } for room in snake_rooms.values() if not room['game_started']]

        print(f"📋 Sending {len(rooms_list)} available rooms")
        emit('snake_rooms_list', {'rooms': rooms_list})

    @socketio.on('start_snake_game')
    def handle_start_game(data):
        """Start the game"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        print(
            f"🎮 Start game request for room {room_code} by player {player_id}")

        if room_code not in snake_rooms:
            print(f"❌ Room {room_code} not found!")
            emit('snake_error', {'message': 'Room not found!'})
            return

        room = snake_rooms[room_code]

        # Only host can start
        if room['host'] != player_id:
            print(
                f"❌ Player {player_id} is not the host. Host is "
                f"{room['host']}")
            emit('snake_error', {'message': 'Only host can start the game!'})
            return

        # Need at least 2 players
        if len(room['players']) < 2:
            print(f"❌ Not enough players. Current: {len(room['players'])}")
            emit(
                'snake_error', {
                    'message': 'Need at least 2 players to start!'})
            return

        # Mark game as started
        room['game_started'] = True
        room['status'] = 'playing'
        room['current_player'] = 0

        print(
            f"🎮 Game started in room {room_code} with {len(room['players'])} players")
        print(f"📊 Players: {[p['name'] for p in room['players']]}")

        # Notify all players
        emit('snake_game_started', {
            'players': room['players'],
            'current_player': room['players'][0]['id']
        }, room=room_code, include_self=True)

    @socketio.on('snake_roll_dice')
    def handle_roll_dice(data):
        """Handle dice roll"""
        room_code = data.get('room_code', '').upper()
        roll = data.get('roll')
        player_id = request.sid

        if room_code not in snake_rooms:
            return

        room = snake_rooms[room_code]

        if not isinstance(roll, int) or isinstance(roll, bool) or not 1 <= roll <= 6:
            emit('snake_error', {'message': 'Invalid dice roll'})
            return

        if not room['players'] or room['current_player'] >= len(room['players']):
            emit('snake_error', {'message': 'Game is not in a playable state'})
            return

        current_player = room['players'][room['current_player']]

        # Verify it's the player's turn
        if current_player['id'] != player_id:
            emit('snake_error', {'message': 'Not your turn!'})
            return

        print(f"🎲 {current_player['name']} rolled {roll} in room {room_code}")

        # Broadcast dice roll
        emit('snake_dice_rolled', {
            'player_id': player_id,
            'roll': roll
        }, room=room_code, include_self=True)

        # Calculate new position
        old_position = current_player['position']
        new_position = old_position + roll

        # Can't exceed 100
        if new_position > 100:
            new_position = old_position

        # Check for snakes and ladders
        SNAKES = {
            99: 5, 95: 24, 92: 51, 87: 13, 85: 17, 80: 40,
            73: 28, 69: 33, 64: 16, 62: 18, 54: 31, 48: 9,
            36: 6, 32: 10
        }
        LADDERS = {
            4: 56, 12: 50, 14: 55, 22: 58, 41: 79, 54: 88,
            63: 81, 70: 90, 78: 98
        }

        snake_or_ladder = None
        if new_position in SNAKES:
            snake_or_ladder = {
                'type': 'snake',
                'from': new_position,
                'to': SNAKES[new_position]}
            new_position = SNAKES[new_position]
        elif new_position in LADDERS:
            snake_or_ladder = {
                'type': 'ladder',
                'from': new_position,
                'to': LADDERS[new_position]}
            new_position = LADDERS[new_position]

        # Update position
        current_player['position'] = new_position

        # Broadcast move
        emit('snake_player_moved', {
            'player_id': player_id,
            'old_position': old_position,
            'new_position': new_position,
            'snake_or_ladder': snake_or_ladder
        }, room=room_code, include_self=True)

        # Check for winner
        if new_position == 100:
            room['status'] = 'finished'
            emit('snake_game_ended', {
                'winner_id': player_id,
                'winner_name': current_player['name'],
                'final_positions': [(p['name'], p['position']) for p in room['players']]
            }, room=room_code, include_self=True)

            # Clean up room after 30 seconds (in background)
            cleanup_thread = threading.Thread(
                target=cleanup_room, args=(
                    socketio, room_code))
            cleanup_thread.daemon = True
            cleanup_thread.start()
            return

        # Next turn
        room['current_player'] = (
            room['current_player'] + 1) % len(room['players'])
        next_player = room['players'][room['current_player']]

        emit('snake_turn_changed', {
            'current_player': next_player['id'],
            'current_player_name': next_player['name']
        }, room=room_code, include_self=True)

    @socketio.on('disconnect')
    def handle_disconnect():
        """Handle player disconnect"""
        player_id = request.sid

        # Find and remove player from any room
        for room_code, room in list(snake_rooms.items()):
            player = next(
                (p for p in room['players'] if p['id'] == player_id), None)
            if player:
                print(
                    f"🔌 Player {player['name']} disconnected from room "
                    f"{room_code}")
                handle_leave_room({'room_code': room_code})
                break

    print("✅ Snake & Ladder socket events registered")
