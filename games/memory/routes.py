from flask import Blueprint, render_template, jsonify, request, session
from .game_logic import MemoryGame
import random
import string
import uuid

memory_bp = Blueprint('memory', __name__)

# Store active games (in production, use Redis or database)
active_games = {}


@memory_bp.route('/')
def lobby():
    return render_template('games/memory.html')


@memory_bp.route('/rooms', methods=['GET'])
def list_rooms():
    """Get list of active game rooms"""
    rooms_list = []
    for room_code, game in active_games.items():
        rooms_list.append({
            'room_code': room_code,
            'player_count': len(game.players),
            'max_players': 4,
            'status': game.state,
            'is_full': len(game.players) >= 4
        })

    return jsonify({
        'success': True,
        'rooms': rooms_list
    })


@memory_bp.route('/create', methods=['POST'])
def create_game():
    """Create a new game room"""
    room_code = ''.join(
        random.choices(
            string.ascii_uppercase +
            string.digits,
            k=6))
    
    # Get grid size from request (default 16 for 4x4)
    data = request.json or {}
    grid_size = data.get('grid_size', 16)
    
    game = MemoryGame(room_code, grid_size=grid_size)
    active_games[room_code] = game

    # Generate player ID if not exists
    if 'player_id' not in session:
        session['player_id'] = str(uuid.uuid4())

    player_id = session['player_id']
    player_name = session.get('user', {}).get('name', f'Player 1')

    # Automatically add creator as first player
    player_info = game.add_player(player_id, player_name)

    return jsonify({
        'success': True,
        'room_code': room_code,
        'player_id': player_id,
        'player_info': player_info
    })


@memory_bp.route('/join/<room_code>', methods=['POST'])
def join_game(room_code):
    """Join an existing game room"""
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]

    # Generate player ID if not exists
    if 'player_id' not in session:
        session['player_id'] = str(uuid.uuid4())

    player_id = session['player_id']
    player_name = session.get('user', {}).get('name', f'Player {len(game.players) + 1}')

    # Check if player already in game
    if player_id in game.players:
        return jsonify({
            'success': True,
            'player_info': game.players[player_id],
            'player_id': player_id,
            'game_state': game.get_game_state()
        })

    # Add new player
    if len(game.players) < 4:
        player_info = game.add_player(player_id, player_name)
        return jsonify({
            'success': True,
            'player_info': player_info,
            'player_id': player_id,
            'game_state': game.get_game_state()
        })
    else:
        return jsonify({'success': False, 'error': 'Game is full (max 4 players)'}), 400


@memory_bp.route('/flip/<room_code>', methods=['POST'])
def flip_card(room_code):
    """Flip a card"""
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]
    data = request.json or {}
    player_id = session.get('player_id')

    if not player_id:
        return jsonify({'success': False, 'error': 'Player not found'}), 400

    card_index = data.get('card_index')
    if (not isinstance(card_index, int) or isinstance(card_index, bool)
            or not 0 <= card_index < len(game.cards)):
        return jsonify({'success': False, 'error': 'Invalid card index'}), 400

    result = game.flip_card(player_id, card_index)
    return jsonify(result)


@memory_bp.route('/reset-flipped/<room_code>', methods=['POST'])
def reset_flipped(room_code):
    """Reset flipped cards (after viewing non-matching pair)"""
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]
    result = game.reset_flipped_cards()
    
    return jsonify({
        'success': True,
        'game_state': game.get_game_state()
    })


@memory_bp.route('/state/<room_code>', methods=['GET'])
def get_state(room_code):
    """Get current game state"""
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]
    player_id = session.get('player_id')

    return jsonify({
        'success': True,
        'game_state': game.get_game_state(),
        'player_id': player_id
    })


@memory_bp.route('/leave/<room_code>', methods=['POST'])
def leave_game(room_code):
    """Leave a game room"""
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    player_id = session.get('player_id')
    if not player_id:
        return jsonify({'success': False, 'error': 'Player not found'}), 400

    game = active_games[room_code]
    
    # Remove player (also fixes the turn pointer for the players left behind)
    game.remove_player(player_id)
    
    # If no players left, delete room
    if len(game.players) == 0:
        del active_games[room_code]
    
    return jsonify({'success': True})
