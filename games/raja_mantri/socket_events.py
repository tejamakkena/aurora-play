"""Raja Mantri Chor Sipahi — Socket.IO events for network multiplayer."""

from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string

raja_rooms = {}


def generate_room_code():
    while True:
        code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        if code not in raja_rooms:
            return code


def register_raja_mantri_events(socketio):
    """Register all Raja Mantri Socket.IO event handlers."""

    @socketio.on('create_raja_room')
    def handle_create_room(data):
        player_name = data.get('player_name', 'Player')
        player_id = request.sid
        room_code = generate_room_code()

        raja_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{'id': player_id, 'name': player_name}],
            'status': 'waiting',
            'roles': {},
            'revealed': set(),
            'sipahi_id': None,
            'chor_id': None,
            'mantri_id': None,
        }

        join_room(room_code)

        emit('raja_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': raja_rooms[room_code]['players']
        })

    @socketio.on('join_raja_room')
    def handle_join_room(data):
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        if room_code not in raja_rooms:
            emit('raja_error', {'message': 'Room not found'})
            return

        room = raja_rooms[room_code]

        if room['status'] != 'waiting':
            emit('raja_error', {'message': 'Game already started'})
            return

        if len(room['players']) >= 4:
            emit('raja_error', {'message': 'Room is full (max 4 players)'})
            return

        room['players'].append({'id': player_id, 'name': player_name})
        join_room(room_code)

        emit('raja_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players']
        }, to=player_id)

        emit('raja_player_joined', {
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('start_raja_game')
    def handle_start_game(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in raja_rooms:
            emit('raja_error', {'message': 'Room not found'})
            return

        room = raja_rooms[room_code]

        if player_id != room['host']:
            emit('raja_error', {'message': 'Only the host can start the game'})
            return

        if len(room['players']) != 4:
            emit('raja_error', {'message': 'Need exactly 4 players to start'})
            return

        # Assign roles randomly server-side for fairness
        roles = ['Raja', 'Mantri', 'Chor', 'Sipahi']
        random.shuffle(roles)

        room['roles'] = {room['players'][i]['id']: roles[i] for i in range(4)}
        room['status'] = 'playing'
        room['revealed'] = set()
        room['sipahi_id'] = next(pid for pid, r in room['roles'].items() if r == 'Sipahi')
        room['chor_id'] = next(pid for pid, r in room['roles'].items() if r == 'Chor')
        room['mantri_id'] = next(pid for pid, r in room['roles'].items() if r == 'Mantri')

        # Send each player their private role
        for player in room['players']:
            pid = player['id']
            emit('raja_game_started', {
                'your_role': room['roles'][pid],
                'your_name': player['name'],
                'players': room['players']
            }, to=pid)

    @socketio.on('raja_reveal_done')
    def handle_reveal_done(data):
        """Called when a player has read their role card and dismissed it."""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in raja_rooms:
            return

        room = raja_rooms[room_code]
        room['revealed'].add(player_id)

        if len(room['revealed']) >= 4:
            mantri_player = next(p for p in room['players'] if p['id'] == room['mantri_id'])
            emit('raja_show_mantri', {
                'mantri_name': mantri_player['name'],
                'mantri_id': room['mantri_id']
            }, room=room_code, include_self=True)

    @socketio.on('raja_sipahi_guess')
    def handle_guess(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid
        guessed_id = data.get('guessed_id')

        if room_code not in raja_rooms:
            return

        room = raja_rooms[room_code]

        if player_id != room['sipahi_id']:
            emit('raja_error', {'message': 'Only Sipahi can guess'})
            return

        if room['status'] != 'playing':
            return

        is_correct = (guessed_id == room['chor_id'])

        scores = {}
        for player in room['players']:
            pid = player['id']
            role = room['roles'][pid]
            if role == 'Raja':
                scores[pid] = 1000
            elif role == 'Mantri':
                scores[pid] = 800
            elif role == 'Sipahi':
                scores[pid] = 500 if is_correct else 0
            elif role == 'Chor':
                scores[pid] = -500 if is_correct else 0

        chor_player = next(p for p in room['players'] if p['id'] == room['chor_id'])
        guessed_player = next((p for p in room['players'] if p['id'] == guessed_id), None)
        room['status'] = 'finished'

        emit('raja_game_result', {
            'is_correct': is_correct,
            'chor_id': room['chor_id'],
            'chor_name': chor_player['name'],
            'guessed_id': guessed_id,
            'guessed_name': guessed_player['name'] if guessed_player else 'Unknown',
            'scores': scores,
            'roles': room['roles'],
            'players': room['players']
        }, room=room_code, include_self=True)

    @socketio.on('leave_raja_room')
    def handle_leave_room(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in raja_rooms:
            return

        leave_room(room_code)
        room = raja_rooms[room_code]

        # A mid-game leave breaks role bookkeeping (the Sipahi guess resolves
        # player lookups that would no longer exist); abort the game instead
        # of leaving the rest stuck or crashing on result.
        if room['status'] == 'playing':
            emit('raja_game_abort', {
                'message': 'A player left the game'
            }, room=room_code, include_self=True)
            del raja_rooms[room_code]
            return

        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        if not room['players']:
            del raja_rooms[room_code]
        else:
            if player_id == room['host']:
                room['host'] = room['players'][0]['id']
            emit('raja_player_left', {'players': room['players']}, room=room_code)

    print("✅ Raja Mantri socket events registered")
