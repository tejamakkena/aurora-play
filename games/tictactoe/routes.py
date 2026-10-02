from flask import Blueprint, render_template, jsonify, request, session
from .game_logic import TicTacToeGame
import random
import string
import uuid

tictactoe_bp = Blueprint('tictactoe', __name__)

# Store active games (in production, use Redis or database)
active_games = {}


@tictactoe_bp.route('/')
def lobby():
    return render_template('games/tictactoe.html')


@tictactoe_bp.route('/rooms', methods=['GET'])
def list_rooms():
    """Get list of active game rooms"""
    rooms_list = []
    for room_code, game in active_games.items():
        rooms_list.append({
            'room_code': room_code,
            'player_count': len(game.players),
            'max_players': 2,
            'status': game.state,
            'is_full': len(game.players) >= 2
        })

    return jsonify({
        'success': True,
        'rooms': rooms_list
    })


@tictactoe_bp.route('/create', methods=['POST'])
def create_game():
    room_code = ''.join(
        random.choices(
            string.ascii_uppercase +
            string.digits,
            k=6))
    game = TicTacToeGame(room_code)
    active_games[room_code] = game

    # Generate player ID if not exists
    if 'player_id' not in session:
        session['player_id'] = str(uuid.uuid4())

    player_id = session['player_id']

    # Automatically add creator as first player
    symbol = game.add_player(player_id)

    return jsonify({
        'success': True,
        'room_code': room_code,
        'player_id': player_id,
        'symbol': symbol
    })


@tictactoe_bp.route('/join/<room_code>', methods=['POST'])
def join_game(room_code):
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]

    # Generate player ID if not exists
    if 'player_id' not in session:
        session['player_id'] = str(uuid.uuid4())

    player_id = session['player_id']

    # Check if player already in game
    if player_id in game.players:
        return jsonify({
            'success': True,
            'symbol': game.players[player_id],
            'player_id': player_id,
            'game_state': game.get_game_state()
        })

    # Add new player
    if len(game.players) < 2:
        symbol = game.add_player(player_id)
        return jsonify({
            'success': True,
            'symbol': symbol,
            'player_id': player_id,
            'game_state': game.get_game_state()
        })
    else:
        return jsonify({'success': False, 'error': 'Game is full'}), 400


@tictactoe_bp.route('/move/<room_code>', methods=['POST'])
def make_move(room_code):
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]
    data = request.json or {}
    player_id = session.get('player_id')

    if not player_id:
        return jsonify({'success': False, 'error': 'Player not found'}), 400

    result = game.make_move(player_id, data.get('position'))
    return jsonify(result)


@tictactoe_bp.route('/state/<room_code>', methods=['GET'])
def get_state(room_code):
    if room_code not in active_games:
        return jsonify({'success': False, 'error': 'Game not found'}), 404

    game = active_games[room_code]
    player_id = session.get('player_id')

    return jsonify({
        'success': True,
        'game_state': game.get_game_state(),
        'player_id': player_id
    })
