from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string
from .game_logic import HangmanGame

hangman_rooms = {}  # room_code -> HangmanGame


def _generate_room_code():
    while True:
        code = ''.join(random.choices(string.ascii_uppercase + string.digits, k=6))
        if code not in hangman_rooms:
            return code


def _players_payload(game):
    return [
        {'id': p['id'], 'name': p['name'], 'is_host': p['is_host']}
        for p in game.players.values()
    ]


def register_hangman_events(socketio):

    @socketio.on('hangman_create_room')
    def handle_create_room(data):
        player_name = data.get('player_name', 'Host')
        player_id = request.sid

        room_code = _generate_room_code()
        game = HangmanGame(room_code)
        game.add_player(player_id, player_name, is_host=True)
        hangman_rooms[room_code] = game

        join_room(room_code)

        emit('hangman_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': _players_payload(game),
            'is_host': True,
        })

    @socketio.on('hangman_join_room')
    def handle_join_room(data):
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        if room_code not in hangman_rooms:
            emit('hangman_error', {'message': 'Room not found!'})
            return

        game = hangman_rooms[room_code]

        if game.state != 'WAITING':
            emit('hangman_error', {'message': 'Game already in progress!'})
            return

        game.add_player(player_id, player_name, is_host=False)
        join_room(room_code)

        emit('hangman_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': _players_payload(game),
            'is_host': False,
        }, to=player_id)

        socketio.emit('hangman_player_joined', {
            'players': _players_payload(game),
        }, room=room_code, include_self=False)

    @socketio.on('hangman_start_game')
    def handle_start_game(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in hangman_rooms:
            emit('hangman_error', {'message': 'Room not found!'})
            return

        game = hangman_rooms[room_code]

        if player_id != game.host_id:
            emit('hangman_error', {'message': 'Only the host can start the game!'})
            return

        if game.state != 'WAITING':
            emit('hangman_error', {'message': 'Game already started!'})
            return

        if len(game.players) < 2:
            emit('hangman_error', {'message': 'Need at least 2 players to start!'})
            return

        # Host now needs to set a word
        game.state = 'SETTING_WORD'

        # Tell host to enter a word; tell others to wait
        emit('hangman_enter_word', {}, to=game.host_id)
        socketio.emit('hangman_waiting_for_word', {}, room=room_code, include_self=False)

    @socketio.on('hangman_set_word')
    def handle_set_word(data):
        room_code = data.get('room_code', '').upper()
        word = data.get('word', '').strip()
        hint = data.get('hint', '').strip()
        player_id = request.sid

        if room_code not in hangman_rooms:
            emit('hangman_error', {'message': 'Room not found!'})
            return

        game = hangman_rooms[room_code]

        if player_id != game.host_id:
            emit('hangman_error', {'message': 'Only the host sets the word!'})
            return

        if game.state != 'SETTING_WORD':
            emit('hangman_error', {'message': 'Not waiting for a word right now!'})
            return

        if not word or not any(c.isalpha() for c in word):
            emit('hangman_error', {'message': 'Word must contain at least one letter!'})
            return

        if len(word) > 30:
            emit('hangman_error', {'message': 'Word must be 30 characters or fewer!'})
            return

        game.set_word(word, hint)
        state = game.get_public_state(reveal_word=False)

        socketio.emit('hangman_game_started', state, room=room_code)

    @socketio.on('hangman_guess')
    def handle_guess(data):
        room_code = data.get('room_code', '').upper()
        letter = data.get('letter', '')
        player_id = request.sid

        if room_code not in hangman_rooms:
            emit('hangman_error', {'message': 'Room not found!'})
            return

        game = hangman_rooms[room_code]

        if game.state != 'PLAYING':
            emit('hangman_error', {'message': 'Game is not in progress!'})
            return

        if player_id not in game.players:
            emit('hangman_error', {'message': 'You are not in this game!'})
            return

        if player_id == game.host_id:
            emit('hangman_error', {'message': 'The host cannot guess!'})
            return

        outcome, used_letter = game.guess_letter(letter)

        if outcome == 'invalid':
            emit('hangman_error', {'message': 'Invalid letter!'})
            return

        if outcome == 'already_guessed':
            emit('hangman_error', {'message': f'"{used_letter}" was already guessed!'})
            return

        guesser_name = game.players[player_id]['name']

        if outcome in ('win', 'lose'):
            state = game.get_public_state(reveal_word=True)
            state['guesser_name'] = guesser_name
            state['last_letter'] = used_letter
            state['outcome'] = outcome
            socketio.emit('hangman_game_over', state, room=room_code)
        else:
            state = game.get_public_state(reveal_word=False)
            state['guesser_name'] = guesser_name
            state['last_letter'] = used_letter
            state['outcome'] = outcome
            socketio.emit('hangman_letter_guessed', state, room=room_code)

    @socketio.on('hangman_play_again')
    def handle_play_again(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in hangman_rooms:
            emit('hangman_error', {'message': 'Room not found!'})
            return

        game = hangman_rooms[room_code]

        if player_id != game.host_id:
            emit('hangman_error', {'message': 'Only the host can start a new round!'})
            return

        game.state = 'SETTING_WORD'
        game.secret_word = None
        game.hint = ''
        game.guessed_letters = set()
        game.wrong_guesses = []
        game.winner = None

        emit('hangman_enter_word', {}, to=game.host_id)
        socketio.emit('hangman_waiting_for_word', {}, room=room_code, include_self=False)

    @socketio.on('hangman_leave_room')
    def handle_leave_room(data):
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in hangman_rooms:
            return

        game = hangman_rooms[room_code]
        game.remove_player(player_id)
        leave_room(room_code)

        if not game.players:
            del hangman_rooms[room_code]
            return

        # If host left, assign a new host
        if player_id == game.host_id:
            new_host_id = next(iter(game.players))
            game.host_id = new_host_id
            game.players[new_host_id]['is_host'] = True
            if game.state in ('PLAYING', 'SETTING_WORD'):
                # Reset to waiting if game was in progress
                game.state = 'WAITING'
                game.secret_word = None
                game.guessed_letters = set()
                game.wrong_guesses = []

        socketio.emit('hangman_player_left', {
            'players': _players_payload(game),
            'host_id': game.host_id,
            'state': game.state,
        }, room=room_code)

    @socketio.on('disconnect')
    def handle_disconnect():
        player_id = request.sid
        for room_code in list(hangman_rooms.keys()):
            if player_id in hangman_rooms[room_code].players:
                handle_leave_room({'room_code': room_code})
                break

    print('✅ Hangman socket events registered')
