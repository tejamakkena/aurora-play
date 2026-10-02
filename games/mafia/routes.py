"""
Mafia game routes and Socket.IO handlers
"""

from flask import Blueprint, render_template, request
from flask_socketio import emit, join_room, leave_room
from .game_logic import MafiaGame

# Game instances
mafia_games = {}

# Blueprint
mafia_bp = Blueprint('mafia', __name__)


@mafia_bp.route('/mafia')
def mafia_game():
    """Render the Mafia game page"""
    return render_template('games/mafia.html')


def register_mafia_handlers(socketio):
    """Register Socket.IO event handlers for Mafia game"""

    @socketio.on('mafia_join')
    def handle_join(data):
        """Join a Mafia game room"""
        room_code = data.get('room_code')
        player_name = data.get('player_name')
        player_id = request.sid
        
        if not room_code or not player_name:
            emit('mafia_error', {'error': 'Missing room code or name'})
            return
        
        # Create game if doesn't exist
        if room_code not in mafia_games:
            mafia_games[room_code] = MafiaGame(room_code)
        
        game = mafia_games[room_code]
        result = game.add_player(player_id, player_name)
        
        if not result['success']:
            emit('mafia_error', {'error': result['error']})
            return
        
        join_room(room_code)
        
        # Send state to everyone
        emit('mafia_state', game.get_game_state(), room=room_code)
        emit('mafia_joined', {'room_code': room_code})

    @socketio.on('mafia_start')
    def handle_start(data):
        """Start the game and assign roles"""
        room_code = data.get('room_code')
        player_id = request.sid
        
        if room_code not in mafia_games:
            emit('mafia_error', {'error': 'Game not found'})
            return
        
        game = mafia_games[room_code]
        result = game.start_game()
        
        if not result['success']:
            emit('mafia_error', {'error': result['error']})
            return
        
        # Send role to each player privately
        for pid in game.players:
            player_state = game.get_game_state(pid)
            socketio.emit('mafia_state', player_state, room=pid)
        
        # Notify all that game started
        emit('mafia_started', {}, room=room_code)

    @socketio.on('mafia_night_action')
    def handle_night_action(data):
        """Handle night actions (kill, save, investigate)"""
        room_code = data.get('room_code')
        action_type = data.get('action')
        target_id = data.get('target')
        player_id = request.sid
        
        if room_code not in mafia_games:
            emit('mafia_error', {'error': 'Game not found'})
            return
        
        game = mafia_games[room_code]
        result = game.submit_night_action(player_id, action_type, target_id)
        
        if not result['success']:
            emit('mafia_error', {'error': result['error']})
            return
        
        # Confirm action to player
        emit('mafia_action_confirmed', {'action': action_type})

        # Check if all actions submitted
        if game.night_actions_complete():
            # Auto-resolve night
            game.resolve_night()
            
            # Send updated state to everyone
            for pid in game.players:
                player_state = game.get_game_state(pid)
                socketio.emit('mafia_state', player_state, room=pid)

    @socketio.on('mafia_start_voting')
    def handle_start_voting(data):
        """Start the voting phase"""
        room_code = data.get('room_code')
        player_id = request.sid
        
        if room_code not in mafia_games:
            emit('mafia_error', {'error': 'Game not found'})
            return
        
        game = mafia_games[room_code]
        result = game.start_voting()
        
        if not result['success']:
            emit('mafia_error', {'error': result['error']})
            return
        
        # Update state
        emit('mafia_state', game.get_game_state(), room=room_code)

    @socketio.on('mafia_vote')
    def handle_vote(data):
        """Submit a vote to eliminate"""
        room_code = data.get('room_code')
        target_id = data.get('target')
        player_id = request.sid
        
        if room_code not in mafia_games:
            emit('mafia_error', {'error': 'Game not found'})
            return
        
        game = mafia_games[room_code]
        result = game.submit_vote(player_id, target_id)
        
        if not result['success']:
            emit('mafia_error', {'error': result['error']})
            return
        
        emit('mafia_vote_confirmed', {})
        
        # Check if all alive players voted
        alive_count = sum(1 for p in game.players.values() if p['alive'])
        
        if len(game.day_votes) >= alive_count:
            # Auto-resolve voting
            result = game.resolve_voting()
            
            if 'winner' in result:
                emit('mafia_game_over', {'winner': result['winner']}, room=room_code)
            
            # Send updated state
            for pid in game.players:
                player_state = game.get_game_state(pid)
                socketio.emit('mafia_state', player_state, room=pid)

    @socketio.on('mafia_leave')
    def handle_leave(data):
        """Leave the game"""
        room_code = data.get('room_code')
        player_id = request.sid
        
        if room_code in mafia_games:
            leave_room(room_code)
            
            # Optionally clean up empty games
            game = mafia_games[room_code]
            if player_id in game.players:
                game.remove_player_actions(player_id)
                del game.players[player_id]
            
            if not game.players:
                del mafia_games[room_code]
            else:
                # A departed special role must not keep the night locked
                if game.night_actions_complete():
                    game.resolve_night()
                for pid in game.players:
                    socketio.emit('mafia_state', game.get_game_state(pid), room=pid)

    @socketio.on('disconnect')
    def handle_disconnect():
        """Handle player disconnect"""
        player_id = request.sid
        
        # Find and remove player from any games
        for room_code, game in list(mafia_games.items()):
            if player_id in game.players:
                player_name = game.players[player_id]['name']
                game.log_event(f"{player_name} disconnected")
                game.remove_player_actions(player_id)
                del game.players[player_id]
                
                # A departed special role must not keep the night locked
                if game.night_actions_complete():
                    game.resolve_night()

                # Notify room
                emit('mafia_state', game.get_game_state(), room=room_code)
                
                # Clean up empty games
                if not game.players:
                    del mafia_games[room_code]
