from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string

# Store active roulette rooms
roulette_rooms = {}

RED_NUMBERS = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}

PAYOUTS = {
    'red': 2, 'black': 2, 'zero': 36,
    'even': 2, 'odd': 2,
    'low': 2, 'high': 2,
    'first12': 3, 'second12': 3, 'third12': 3,
}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        if code not in roulette_rooms:
            return code


def number_color(n):
    if n == 0:
        return 'green'
    return 'red' if n in RED_NUMBERS else 'black'


def bet_wins(bet_type, number, color):
    """Return True if the bet wins for this wheel result."""
    if bet_type == 'red':
        return color == 'red'
    if bet_type == 'black':
        return color == 'black'
    if bet_type == 'zero':
        return number == 0
    if bet_type == 'even':
        return number != 0 and number % 2 == 0
    if bet_type == 'odd':
        return number != 0 and number % 2 == 1
    if bet_type == 'low':
        return 1 <= number <= 18
    if bet_type == 'high':
        return 19 <= number <= 36
    if bet_type == 'first12':
        return 1 <= number <= 12
    if bet_type == 'second12':
        return 13 <= number <= 24
    if bet_type == 'third12':
        return 25 <= number <= 36
    return False


def register_roulette_events(socketio):
    """Register all Roulette socket events"""

    @socketio.on('create_roulette_room')
    def handle_create_room(data):
        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        roulette_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'chips': 1000,
                'is_host': True
            }],
            'status': 'betting',
            'current_bets': {},
            'last_result': None
        }

        join_room(room_code)

        emit('roulette_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': roulette_rooms[room_code]['players']
        })

    @socketio.on('join_roulette_room')
    def handle_join_room(data):
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        if room_code not in roulette_rooms:
            emit('roulette_error', {'message': 'Room not found!'})
            return

        room = roulette_rooms[room_code]

        if any(p['id'] == player_id for p in room['players']):
            emit('roulette_error', {'message': 'Already in this room'})
            return

        room['players'].append({
            'id': player_id,
            'name': player_name,
            'chips': 1000,
            'is_host': False
        })

        join_room(room_code)

        emit('roulette_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players']
        }, to=request.sid)

        emit('roulette_player_joined', {
            'player_name': player_name,
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('get_roulette_rooms')
    def handle_get_rooms(data):
        rooms_list = [
            {
                'code': r['code'],
                'player_count': len(r['players']),
                'status': r['status']
            }
            for r in roulette_rooms.values()
            if r['status'] == 'betting'
        ]
        emit('roulette_rooms_list', {'rooms': rooms_list})

    @socketio.on('place_bet')
    def handle_place_bet(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid
        bet_type = data.get('bet_type')
        try:
            bet_amount = int(data.get('bet_amount', 0))
        except (TypeError, ValueError):
            emit('roulette_error', {'message': 'Invalid bet amount'})
            return

        if room_code not in roulette_rooms:
            return

        room = roulette_rooms[room_code]

        if room['status'] != 'betting':
            emit('roulette_error', {'message': 'Betting phase is closed'})
            return

        # Find player and validate chips
        player = next((p for p in room['players'] if p['id'] == player_id), None)
        if not player:
            return

        if bet_amount <= 0 or bet_amount > player['chips']:
            emit('roulette_error', {'message': 'Invalid bet amount'})
            return

        if bet_type not in PAYOUTS:
            emit('roulette_error', {'message': 'Invalid bet type'})
            return

        # Deduct chips immediately
        player['chips'] -= bet_amount

        if player_id not in room['current_bets']:
            room['current_bets'][player_id] = []

        room['current_bets'][player_id].append({
            'type': bet_type,
            'amount': bet_amount
        })

        emit('bet_placed', {
            'player_id': player_id,
            'bet_type': bet_type,
            'bet_amount': bet_amount,
            'remaining_chips': player['chips'],
            'players': room['players']
        }, room=room_code, include_self=True)

    @socketio.on('spin_wheel')
    def handle_spin_wheel(data):
        room_code = data.get('room_code', '').upper()

        if room_code not in roulette_rooms:
            return

        room = roulette_rooms[room_code]

        if request.sid != room['host']:
            emit('roulette_error', {'message': 'Only the host can spin the wheel'})
            return

        if room['status'] != 'betting':
            emit('roulette_error', {'message': 'Not in betting phase'})
            return

        # Generate result
        result = random.randint(0, 36)
        color = number_color(result)
        room['last_result'] = result
        room['status'] = 'spinning'

        # Resolve bets for every player
        player_results = {}
        for player in room['players']:
            pid = player['id']
            bets = room['current_bets'].get(pid, [])
            total_won = sum(
                bet['amount'] * PAYOUTS[bet['type']]
                for bet in bets
                if bet_wins(bet['type'], result, color)
            )
            player['chips'] += total_won
            player_results[pid] = {
                'won': total_won,
                'chips': player['chips']
            }

        # Clear bets and reopen betting
        room['current_bets'] = {}
        room['status'] = 'betting'

        emit('wheel_result', {
            'result': result,
            'color': color,
            'player_results': player_results,
            'players': room['players']
        }, room=room_code, include_self=True)

    @socketio.on('leave_roulette_room')
    def handle_leave_room(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in roulette_rooms:
            return

        leave_room(room_code)
        room = roulette_rooms[room_code]
        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        # Reassign host if the host left
        if room['players'] and player_id == room['host']:
            room['host'] = room['players'][0]['id']
            room['players'][0]['is_host'] = True

        if not room['players']:
            del roulette_rooms[room_code]
        else:
            emit('roulette_player_left', {'players': room['players']}, room=room_code)

    print("✅ Roulette socket events registered")
