from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string

# Store active trivia rooms
trivia_rooms = {}


def generate_room_code():
    """Generate a unique 4-letter room code"""
    while True:
        code = ''.join(random.choices(string.ascii_uppercase, k=4))
        if code not in trivia_rooms:
            return code


def register_trivia_events(socketio):
    """Register all trivia-related Socket.IO events"""

    @socketio.on('create_trivia_room')
    def handle_create_room(data):
        """Create a new trivia room"""
        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player')

        trivia_rooms[room_code] = {
            'code': room_code,
            'host': player_name,
            'host_sid': request.sid,
            'players': {
                player_name: {
                    'name': player_name,
                    'score': 0,
                    'is_host': True,
                    'ready': False,
                    'sid': request.sid
                }
            },
            'status': 'waiting',
            'settings': {
                'topic': 'Science',
                'difficulty': 'medium',
                'question_count': 5
            },
            'questions': [],
            'current_question': 0
        }

        join_room(room_code)

        emit('room_created', {
            'room_code': room_code,
            'players': list(trivia_rooms[room_code]['players'].values())
        })

        print(f"✅ Room {room_code} created by {player_name}")

    @socketio.on('join_trivia_room')
    def handle_join_room(data):
        """Join an existing trivia room"""
        room_code = data.get('room_code', '').upper()
        player_name = data.get('player_name', 'Player')

        if room_code not in trivia_rooms:
            emit('error', {'message': 'Room not found!'})
            return

        room = trivia_rooms[room_code]

        if len(room['players']) >= 4:
            emit('error', {'message': 'Room is full!'})
            return

        if room['status'] != 'waiting':
            emit('error', {'message': 'Game already started!'})
            return

        # Add player to room
        room['players'][player_name] = {
            'name': player_name,
            'score': 0,
            'is_host': False,
            'ready': False,
            'sid': request.sid
        }

        join_room(room_code)

        # Notify the player who joined
        emit('room_joined', {
            'room_code': room_code,
            'players': list(room['players'].values())
        })

        # Notify all other players in the room
        emit('player_joined', {
            'players': list(room['players'].values())
        }, room=room_code, skip_sid=request.sid)

        print(f"✅ {player_name} joined room {room_code}")

    @socketio.on('leave_trivia_room')
    def handle_leave_room(data):
        """Leave a trivia room"""
        room_code = data.get('room_code', '').upper()

        if room_code not in trivia_rooms:
            return

        room = trivia_rooms[room_code]

        # Find and remove the player
        player_to_remove = None
        for player_name, player_data in room['players'].items():
            if player_data.get('sid') == request.sid:
                player_to_remove = player_name
                break

        if player_to_remove:
            was_host = room['players'][player_to_remove]['is_host']
            del room['players'][player_to_remove]

            # If host left and there are still players, assign new host
            if was_host and room['players']:
                new_host = list(room['players'].keys())[0]
                room['players'][new_host]['is_host'] = True
                room['host'] = new_host
                room['host_sid'] = room['players'][new_host].get('sid')

            leave_room(room_code)

            # If room is empty, delete it
            if not room['players']:
                del trivia_rooms[room_code]
                print(f"🗑️ Room {room_code} deleted (empty)")
            else:
                # Notify remaining players
                emit('player_left', {
                    'players': list(room['players'].values())
                }, room=room_code)

                print(f"👋 {player_to_remove} left room {room_code}")

    @socketio.on('start_trivia_game')
    def handle_start_game(data):
        """Start the trivia game (host only)"""
        room_code = data.get('room_code', '').upper()

        if room_code not in trivia_rooms:
            emit('error', {'message': 'Room not found!'})
            return

        room = trivia_rooms[room_code]

        # Only the host can start the game
        if request.sid != room.get('host_sid'):
            emit('error', {'message': 'Only the host can start the game!'})
            return

        # Update game settings
        room['settings'] = {
            'topic': data.get('topic', 'Science'),
            'difficulty': data.get('difficulty', 'medium'),
            'question_count': data.get('question_count', 5)
        }

        room['status'] = 'playing'

        # Generate questions (you'll need to call your Gemini API here)
        # For now, using a placeholder - you should integrate with your
        # generate route
        from games.trivia.routes import generate_questions_sync

        try:
            questions = generate_questions_sync(
                room['settings']['topic'],
                room['settings']['difficulty'],
                room['settings']['question_count']
            )
            room['questions'] = questions

            # Start the game for all players
            emit('game_starting', {
                'topic': room['settings']['topic'],
                'difficulty': room['settings']['difficulty'],
                'question_count': room['settings']['question_count'],
                'questions': questions
            }, room=room_code)

            print(f"🎮 Game started in room {room_code}")

        except Exception as e:
            print(f"Error generating questions in room {room_code}: {e}")
            emit(
                'error', {
                    'message': 'Failed to generate questions. Please try again.'}, room=room_code)
            room['status'] = 'waiting'

    @socketio.on('answer_submitted')
    def handle_answer(data):
        """Handle player answer submission"""
        room_code = data.get('room_code', '').upper()
        score = data.get('score', 0)

        if room_code not in trivia_rooms:
            return

        room = trivia_rooms[room_code]

        # Update player score
        for player_name, player_data in room['players'].items():
            if player_data.get('sid') == request.sid:
                room['players'][player_name]['score'] = score
                break

        # Send updated scores to all players
        scores = {name: player['score']
                  for name, player in room['players'].items()}
        emit('score_update', {'scores': scores}, room=room_code)

    @socketio.on('game_finished')
    def handle_game_finished(data):
        """Handle game completion"""
        room_code = data.get('room_code', '').upper()

        if room_code not in trivia_rooms:
            return

        room = trivia_rooms[room_code]
        room['status'] = 'finished'

        # Send final scores
        final_scores = {name: player['score']
                        for name, player in room['players'].items()}
        emit('game_ended', {'final_scores': final_scores}, room=room_code)

        print(f"🏁 Game finished in room {room_code}")

    @socketio.on('get_trivia_rooms')
    def handle_get_rooms():
        """Get list of active trivia rooms"""
        rooms_list = [
            {
                'code': code,
                'player_count': len(room['players']),
                'status': room['status'],
                'topic': room['settings']['topic']
            }
            for code, room in trivia_rooms.items()
            if room['status'] == 'waiting'
        ]

        emit('rooms_list', {'rooms': rooms_list})

    @socketio.on('disconnect')
    def handle_disconnect():
        """Handle player disconnect"""
        # Find and remove player from any room they're in
        for room_code, room in list(trivia_rooms.items()):
            for player_name, player_data in list(room['players'].items()):
                if player_data.get('sid') == request.sid:
                    was_host = player_data['is_host']
                    del room['players'][player_name]

                    if was_host and room['players']:
                        new_host = list(room['players'].keys())[0]
                        room['players'][new_host]['is_host'] = True
                        room['host'] = new_host
                        room['host_sid'] = room['players'][new_host].get('sid')

                    if not room['players']:
                        del trivia_rooms[room_code]
                    else:
                        emit('player_left', {
                            'players': list(room['players'].values())
                        }, room=room_code)

                    break
