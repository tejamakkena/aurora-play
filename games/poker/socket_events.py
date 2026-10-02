from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string

# Store active poker rooms
poker_rooms = {}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(
            random.choices(
                string.ascii_uppercase +
                string.digits,
                k=6))
        if code not in poker_rooms:
            return code


def create_deck():
    """Create a standard 52-card deck"""
    suits = ['♠', '♥', '♦', '♣']
    values = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
    deck = [{'value': v, 'suit': s} for s in suits for v in values]
    random.shuffle(deck)
    return deck


def get_public_player_data(players, requesting_player_id=None):
    """Get public player data (hide hole cards except for requesting player)"""
    return [{
        'id': p['id'],
        'name': p['name'],
        'chips': p['chips'],
        'bet': p['bet'],
        'folded': p['folded'],
        'position': p['position'],
        'is_me': p['id'] == requesting_player_id if requesting_player_id else False
    } for p in players]


def register_poker_events(socketio):
    """Register all Poker socket events"""

    def deal_new_hand(room_code):
        """Deal a new hand"""
        room = poker_rooms[room_code]

        # Drop players who left mid-hand; keep index-based pointers valid
        left_ids = [p['id'] for p in room['players'] if p.get('left')]
        if left_ids:
            room['players'] = [p for p in room['players'] if not p.get('left')]
            room['dealer'] %= max(1, len(room['players']))

        print(f"\n{'=' * 60}")
        print(f"🎴 DEALING NEW HAND - Room: {room_code}")

        # Reset hand state
        room['deck'] = create_deck()
        room['community_cards'] = []
        room['pot'] = 0
        room['current_bet'] = 0
        room['phase'] = 'preflop'
        room['last_raiser'] = -1
        room['players_acted'] = set()  # NEW: Track who has acted

        # Reset players
        for player in room['players']:
            player['hand'] = []
            player['bet'] = 0
            player['folded'] = False
            player['acted_after_raise'] = False

        # Deal hole cards (2 cards per player)
        for _ in range(2):
            for player in room['players']:
                if room['deck']:
                    player['hand'].append(room['deck'].pop())

        # Post blinds
        num_players = len(room['players'])
        small_blind_pos = (room['dealer'] + 1) % num_players
        big_blind_pos = (room['dealer'] + 2) % num_players

        # Small blind
        room['players'][small_blind_pos]['chips'] -= room['small_blind']
        room['players'][small_blind_pos]['bet'] = room['small_blind']
        room['pot'] += room['small_blind']

        # Big blind
        room['players'][big_blind_pos]['chips'] -= room['big_blind']
        room['players'][big_blind_pos]['bet'] = room['big_blind']
        room['pot'] += room['big_blind']

        room['current_bet'] = room['big_blind']
        room['current_turn'] = (big_blind_pos + 1) % num_players
        room['hand_in_progress'] = True

        print(f"Dealer: {room['dealer']}")
        print(
            f"Small blind (${room['small_blind']}): Player {small_blind_pos}")
        print(f"Big blind (${room['big_blind']}): Player {big_blind_pos}")
        print(f"First to act: Player {room['current_turn']}")
        print(f"Pot: ${room['pot']}")
        print(f"Current bet: ${room['current_bet']}")

        # Send game state to each player individually with their correct index
        for i, player in enumerate(room['players']):
            player_data = {
                'hand': player['hand'],
                'dealer': room['dealer'],
                'pot': room['pot'],
                'current_bet': room['current_bet'],
                'current_turn': room['current_turn'],
                'players': get_public_player_data(
                    room['players'],
                    player['id']),
                'phase': 'preflop',
                'your_position': i,
                'player_id': player['id']}

            print(
                f"📤 Sending to {player['name']}: Position={i}, "
                f"Turn={room['current_turn']}, "
                f"IsYourTurn={i == room['current_turn']}")

            socketio.emit('hand_dealt', player_data, to=player['id'])

        print(f"{'=' * 60}\n")

    def next_phase(room_code):
        """Move to the next betting phase"""
        room = poker_rooms[room_code]

        print(f"\n{'=' * 50}")
        print(f"🎴 NEXT PHASE - Room: {room_code}")
        print(f"Current phase: {room['phase']}")

        # Reset bets and tracking for new round
        for player in room['players']:
            player['bet'] = 0
            player['acted_after_raise'] = False

        room['current_bet'] = 0
        room['last_raiser'] = -1
        room['players_acted'] = set()

        if room['phase'] == 'preflop':
            # Deal flop (3 cards)
            for _ in range(3):
                if room['deck']:
                    room['community_cards'].append(room['deck'].pop())
            room['phase'] = 'flop'

        elif room['phase'] == 'flop':
            # Deal turn (1 card)
            if room['deck']:
                room['community_cards'].append(room['deck'].pop())
            room['phase'] = 'turn'

        elif room['phase'] == 'turn':
            # Deal river (1 card)
            if room['deck']:
                room['community_cards'].append(room['deck'].pop())
            room['phase'] = 'river'

        elif room['phase'] == 'river':
            # Showdown
            room['phase'] = 'showdown'
            determine_winner(room_code)
            return

        # Start betting with player after dealer
        room['current_turn'] = (room['dealer'] + 1) % len(room['players'])

        # Skip folded players
        attempts = 0
        while room['players'][room['current_turn']
                              ]['folded'] and attempts < len(room['players']):
            room['current_turn'] = (
                room['current_turn'] + 1) % len(room['players'])
            attempts += 1

        print(f"New phase: {room['phase']}")
        print(f"Community cards: {len(room['community_cards'])}")
        print(f"Starting with player {room['current_turn']}")
        print(f"{'=' * 50}\n")

        socketio.emit('next_phase', {
            'phase': room['phase'],
            'community_cards': room['community_cards'],
            'pot': room['pot'],
            'current_bet': room['current_bet'],
            'current_turn': room['current_turn'],
            'players': get_public_player_data(room['players'])
        }, room=room_code)

    def determine_winner(room_code):
        """Determine the winner at showdown"""
        room = poker_rooms[room_code]
        active_players = [p for p in room['players'] if not p['folded']]

        print(f"\n{'=' * 50}")
        print(f"🏆 SHOWDOWN - Room: {room_code}")
        print(f"Active players: {[p['name'] for p in active_players]}")

        # Simple winner determination (first active player wins for now)
        # TODO: Implement proper hand evaluation
        winner = active_players[0]
        winner['chips'] += room['pot']

        print(f"Winner: {winner['name']} wins ${room['pot']}")
        print(f"{'=' * 50}\n")

        # Reveal all hands
        all_hands = {p['name']: p['hand'] for p in active_players}

        socketio.emit('showdown', {
            'winner': winner['name'],
            'pot': room['pot'],
            'hands': all_hands,
            'players': get_public_player_data(room['players'])
        }, room=room_code)

        room['dealer'] = (room['dealer'] + 1) % len(room['players'])
        room['hand_in_progress'] = False

    def advance_game(room_code):
        """Advance to next player or next phase"""
        room = poker_rooms[room_code]

        print(f"\n{'=' * 50}")
        print(f"🔄 ADVANCING GAME - Room: {room_code}")

        # Find active players
        active_players = [p for p in room['players'] if not p['folded']]

        print(f"Active players: {len(active_players)}")

        # Check if only one player left
        if len(active_players) == 1:
            winner = active_players[0]
            winner['chips'] += room['pot']

            print(f"🏆 {winner['name']} wins ${room['pot']} (only player left)")

            socketio.emit('hand_complete', {
                'winner': winner['name'],
                'pot': room['pot'],
                'players': get_public_player_data(room['players'])
            }, room=room_code)

            room['dealer'] = (room['dealer'] + 1) % len(room['players'])
            room['hand_in_progress'] = False
            return

        # NEW LOGIC: Track who has acted this round
        if 'players_acted' not in room:
            room['players_acted'] = set()

        # Mark current player as acted
        room['players_acted'].add(room['current_turn'])

        # Find next active player
        next_player = (room['current_turn'] + 1) % len(room['players'])
        attempts = 0

        while attempts < len(room['players']):
            player = room['players'][next_player]

            # Skip folded or all-in players
            if player['folded'] or player['chips'] == 0:
                next_player = (next_player + 1) % len(room['players'])
                attempts += 1
                continue

            # Check if this player needs to act
            needs_to_act = False

            # 1. Player hasn't acted yet this round
            if next_player not in room['players_acted']:
                needs_to_act = True
                print(f"  ➡️ Player {next_player} hasn't acted yet")

            # 2. Player's bet is less than current bet
            elif player['bet'] < room['current_bet']:
                needs_to_act = True
                print(
                    f"  ➡️ Player {next_player} needs to match bet "
                    f"(${player['bet']} < ${room['current_bet']})")

            # 3. Someone raised after this player acted
            elif room.get('last_raiser', -1) >= 0 and not player.get('acted_after_raise', False):
                needs_to_act = True
                print(f"  ➡️ Player {next_player} needs to act after raise")

            if needs_to_act:
                break

            next_player = (next_player + 1) % len(room['players'])
            attempts += 1

        # If we've gone through all players and no one needs to act
        if attempts >= len(room['players']):
            print("✅ Betting round complete - all players acted")

            # Reset tracking for next round
            room['players_acted'] = set()
            for p in room['players']:
                p['acted_after_raise'] = False
            room['last_raiser'] = -1

            next_phase(room_code)
            return

        # Move to next player
        room['current_turn'] = next_player

        print(
            f"⏭️ Moving to player {next_player} "
            f"({room['players'][next_player]['name']})")
        print(f"Players acted so far: {room['players_acted']}")
        print(f"{'=' * 50}\n")

        socketio.emit('next_turn', {
            'current_turn': next_player,
            'pot': room['pot'],
            'current_bet': room['current_bet'],
            'players': get_public_player_data(room['players'])
        }, room=room_code)

    @socketio.on('create_poker_room')
    def handle_create_room(data):
        """Create a new poker room"""
        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player')
        starting_chips = data.get('starting_chips', 1000)
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print("🎲 CREATING POKER ROOM")
        print(f"Room code: {room_code}")
        print(f"Host: {player_name}")
        print(f"Starting chips: ${starting_chips}")

        poker_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'chips': starting_chips,
                'hand': [],
                'bet': 0,
                'folded': False,
                'is_host': True,
                'position': 0,
                'acted_after_raise': False
            }],
            'status': 'waiting',
            'deck': [],
            'community_cards': [],
            'pot': 0,
            'current_bet': 0,
            'dealer': 0,
            'current_turn': 0,
            'phase': 'waiting',
            'small_blind': 10,
            'big_blind': 20,
            'starting_chips': starting_chips,
            'last_raiser': -1
        }

        join_room(room_code)

        print("✅ Room created successfully")
        print(f"{'=' * 60}\n")

        emit('poker_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': poker_rooms[room_code]['players'],
            'starting_chips': starting_chips
        })

    @socketio.on('join_poker_room')
    def handle_join_room(data):
        """Join an existing poker room"""
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print("🚪 JOINING POKER ROOM")
        print(f"Room code: {room_code}")
        print(f"Player: {player_name}")

        if room_code not in poker_rooms:
            print("❌ Room not found")
            print(f"{'=' * 60}\n")
            emit('poker_error', {'message': 'Room not found!'})
            return

        room = poker_rooms[room_code]

        if room['status'] != 'waiting':
            print("❌ Game already in progress")
            print(f"{'=' * 60}\n")
            emit('poker_error', {'message': 'Game already in progress!'})
            return

        if len(room['players']) >= 6:
            print("❌ Room is full")
            print(f"{'=' * 60}\n")
            emit('poker_error', {'message': 'Room is full! (Max 6 players)'})
            return

        position = len(room['players'])
        room['players'].append({
            'id': player_id,
            'name': player_name,
            'chips': room['starting_chips'],
            'hand': [],
            'bet': 0,
            'folded': False,
            'is_host': False,
            'position': position,
            'acted_after_raise': False
        })

        join_room(room_code)

        print(f"✅ Player joined (Position: {position})")
        print(f"Total players: {len(room['players'])}")
        print(f"{'=' * 60}\n")

        emit('poker_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players']
        }, to=request.sid)

        emit('poker_player_joined', {
            'player_name': player_name,
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('start_poker_game')
    def handle_start_game(data):
        """Start the poker game"""
        room_code = data.get('room_code', '').upper()

        print(f"\n{'=' * 60}")
        print(f"🎮 STARTING POKER GAME - Room: {room_code}")

        if room_code not in poker_rooms:
            print("❌ Room not found")
            print(f"{'=' * 60}\n")
            return

        room = poker_rooms[room_code]

        if request.sid != room['host']:
            print("❌ Only host can start")
            print(f"{'=' * 60}\n")
            emit('poker_error', {'message': 'Only host can start the game!'})
            return

        if len(room['players']) < 2:
            print("❌ Need at least 2 players")
            print(f"{'=' * 60}\n")
            emit(
                'poker_error', {
                    'message': 'Need at least 2 players to start!'})
            return

        room['status'] = 'playing'

        print(f"✅ Game starting with {len(room['players'])} players")
        print(f"{'=' * 60}\n")

        deal_new_hand(room_code)

    @socketio.on('poker_action')
    def handle_poker_action(data):
        """Handle player actions"""
        room_code = data.get('room_code', '').upper()
        action = data.get('action')
        player_id = request.sid

        print(f"\n{'=' * 40}")
        print(f"🎮 PLAYER ACTION - Room: {room_code}")
        print(f"Action: {action}")

        if room_code not in poker_rooms:
            emit('poker_error', {'message': 'Room not found'})
            return

        room = poker_rooms[room_code]

        # Find player
        player_index = None
        for i, p in enumerate(room['players']):
            if p['id'] == player_id:
                player_index = i
                break

        if player_index is None:
            emit('poker_error', {'message': 'Player not found'})
            return

        player = room['players'][player_index]

        # Verify it's player's turn
        if room['current_turn'] != player_index:
            print(
                f"❌ Not player's turn (current: {room['current_turn']}, "
                f"player: {player_index})")
            print(f"{'=' * 40}\n")
            emit('poker_error', {'message': 'Not your turn!'})
            return

        print(f"Player: {player['name']} (Position: {player_index})")
        print(
            f"Current bet: ${room['current_bet']}, "
            f"Player bet: ${player['bet']}, Chips: ${player['chips']}")

        # Process action
        if action == 'fold':
            player['folded'] = True
            print(f"🚫 {player['name']} folded")

        elif action == 'check':
            if player['bet'] < room['current_bet']:
                emit(
                    'poker_error', {
                        'message': 'Cannot check, you must call or raise'})
                return
            print(f"✓ {player['name']} checked")
            player['acted_after_raise'] = True

        elif action == 'call':
            call_amount = room['current_bet'] - player['bet']

            if call_amount > player['chips']:
                # All-in call
                call_amount = player['chips']

            player['chips'] -= call_amount
            player['bet'] += call_amount
            room['pot'] += call_amount

            print(f"📞 {player['name']} called ${call_amount}")
            player['acted_after_raise'] = True

        elif action == 'raise':
            raise_amount = data.get('raise_amount', room['current_bet'] * 2)
            total_needed = raise_amount - player['bet']

            if total_needed > player['chips']:
                emit('poker_error', {'message': 'Not enough chips'})
                return

            player['chips'] -= total_needed
            player['bet'] = raise_amount
            room['pot'] += total_needed
            room['current_bet'] = raise_amount
            room['last_raiser'] = player_index

            # Reset acted_after_raise for all other players
            for p in room['players']:
                if not p['folded']:
                    p['acted_after_raise'] = False
            player['acted_after_raise'] = True

            print(f"📈 {player['name']} raised to ${raise_amount}")

        elif action == 'allin':
            all_in_amount = player['chips']
            player['bet'] += all_in_amount
            room['pot'] += all_in_amount
            player['chips'] = 0

            if player['bet'] > room['current_bet']:
                room['current_bet'] = player['bet']
                room['last_raiser'] = player_index
                # Reset acted_after_raise for all other players
                for p in room['players']:
                    if not p['folded']:
                        p['acted_after_raise'] = False
                player['acted_after_raise'] = True

            print(f"🔥 {player['name']} went all-in with ${all_in_amount}")

        # Broadcast action
        socketio.emit('player_action', {
            'player': player['name'],
            'action': action,
            'amount': player['bet'] if action in ['raise', 'call', 'allin'] else None,
            'pot': room['pot'],
            'players': get_public_player_data(room['players'])
        }, room=room_code)

        print(f"Pot: ${room['pot']}, Current bet: ${room['current_bet']}")
        print(f"{'=' * 40}\n")

        # Advance game
        advance_game(room_code)

    @socketio.on('deal_new_hand')
    def handle_deal_new_hand(data):
        """Deal a new hand (host only, between hands)"""
        room_code = data.get('room_code', '').upper()

        if room_code not in poker_rooms:
            return

        room = poker_rooms[room_code]

        if request.sid != room['host']:
            emit('poker_error', {'message': 'Only the host can deal a new hand'})
            return

        if room.get('hand_in_progress'):
            emit('poker_error', {'message': 'Hand already in progress!'})
            return

        if len(room['players']) < 2:
            emit('poker_error', {'message': 'Need at least 2 players to deal!'})
            return

        deal_new_hand(room_code)

    @socketio.on('leave_poker_room')
    def handle_leave_poker_room(data):
        """Leave a poker room. The client emits this but no handler existed,
        so departed players stayed in the room forever."""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in poker_rooms:
            return

        room = poker_rooms[room_code]
        removed_index = next(
            (i for i, p in enumerate(room['players']) if p['id'] == player_id),
            None)
        if removed_index is None:
            return

        leave_room(room_code)

        if room['status'] == 'playing' and room.get('hand_in_progress'):
            # Mid-hand: fold the player out but keep them in the seat list so
            # index-based turn/dealer pointers stay valid; they are purged at
            # the next deal.
            player = room['players'][removed_index]
            player['folded'] = True
            player['left'] = True
            if room['current_turn'] == removed_index:
                advance_game(room_code)
        else:
            room['players'].pop(removed_index)
            # Fix seat positions
            for i, p in enumerate(room['players']):
                p['position'] = i

        # Reassign host if the host left
        if room['players'] and player_id == room['host']:
            room['host'] = room['players'][0]['id']
            room['players'][0]['is_host'] = True

        if not room['players']:
            del poker_rooms[room_code]
        else:
            socketio.emit('poker_player_left', {
                'players': get_public_player_data(room['players'])
            }, room=room_code)

    print("✅ Poker socket events registered")
