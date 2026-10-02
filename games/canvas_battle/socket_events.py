from flask_socketio import emit, join_room, leave_room
from flask import request
import random
import string
import time

# Store active canvas battle rooms
canvas_rooms = {}


def generate_room_code():
    """Generate a unique 6-character room code"""
    while True:
        code = ''.join(
            random.choices(
                string.ascii_uppercase +
                string.digits,
                k=6))
        if code not in canvas_rooms:
            return code


def register_canvas_battle_events(socketio):
    """Register all Canvas Battle socket events"""

    @socketio.on('create_canvas_room')
    def handle_create_room(data):
        """Create a new canvas battle room"""
        room_code = generate_room_code()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid
        time_limit = data.get('time_limit', 60)  # seconds

        print(f"\n{'=' * 60}")
        print(f"🎨 CREATING CANVAS BATTLE ROOM")
        print(f"Room code: {room_code}")
        print(f"Host: {player_name}")
        print(f"Time limit: {time_limit}s")

        canvas_rooms[room_code] = {
            'code': room_code,
            'host': player_id,
            'players': [{
                'id': player_id,
                'name': player_name,
                'is_host': True,
                'ready': False,
                'canvas_data': None,
                'votes': 0,
                'score': 0
            }],
            'status': 'waiting',  # waiting, drawing, voting, finished
            'time_limit': time_limit,
            'round': 0,
            'max_rounds': 3,
            'theme': None,
            'round_start_time': None,
            'voters': set()  # player ids that already voted this round
        }

        join_room(room_code)

        print(f"✅ Canvas Battle room created")
        print(f"{'=' * 60}\n")

        emit('canvas_room_created', {
            'room_code': room_code,
            'player_id': player_id,
            'players': canvas_rooms[room_code]['players'],
            'time_limit': time_limit
        })

    @socketio.on('join_canvas_room')
    def handle_join_room(data):
        """Join an existing canvas battle room"""
        room_code = data.get('room_code', '').upper().strip()
        player_name = data.get('player_name', 'Player')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"🚪 JOINING CANVAS BATTLE ROOM")
        print(f"Room code: {room_code}")
        print(f"Player: {player_name}")

        if room_code not in canvas_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            emit('canvas_error', {'message': 'Room not found!'})
            return

        room = canvas_rooms[room_code]

        if room['status'] != 'waiting':
            print(f"❌ Game already in progress")
            print(f"{'=' * 60}\n")
            emit('canvas_error', {'message': 'Game already in progress!'})
            return

        if len(room['players']) >= 6:
            print(f"❌ Room is full")
            print(f"{'=' * 60}\n")
            emit('canvas_error', {'message': 'Room is full! (Max 6 players)'})
            return

        room['players'].append({
            'id': player_id,
            'name': player_name,
            'is_host': False,
            'ready': False,
            'canvas_data': None,
            'votes': 0,
            'score': 0
        })

        join_room(room_code)

        print(f"✅ Player joined")
        print(f"Total players: {len(room['players'])}")
        print(f"{'=' * 60}\n")

        emit('canvas_room_joined', {
            'room_code': room_code,
            'player_id': player_id,
            'players': room['players']
        }, to=request.sid)

        emit('canvas_player_joined', {
            'player_name': player_name,
            'players': room['players']
        }, room=room_code, include_self=False)

    @socketio.on('canvas_player_ready')
    def handle_player_ready(data):
        """Mark player as ready"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in canvas_rooms:
            return

        room = canvas_rooms[room_code]

        for player in room['players']:
            if player['id'] == player_id:
                player['ready'] = True
                break

        socketio.emit('canvas_player_ready_update', {
            'players': room['players']
        }, room=room_code)

        # Check if all players are ready
        if all(
                p['ready'] for p in room['players']) and len(
                room['players']) >= 2:
            start_drawing_round(room_code, socketio)

    @socketio.on('start_canvas_battle')
    def handle_start_game(data):
        """Start the canvas battle game"""
        room_code = data.get('room_code', '').upper()

        print(f"\n{'=' * 60}")
        print(f"🎮 STARTING CANVAS BATTLE - Room: {room_code}")

        if room_code not in canvas_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            return

        room = canvas_rooms[room_code]

        if request.sid != room['host']:
            print(f"❌ Only host can start")
            print(f"{'=' * 60}\n")
            emit('canvas_error', {'message': 'Only host can start the game!'})
            return

        if len(room['players']) < 2:
            print(f"❌ Need at least 2 players")
            print(f"{'=' * 60}\n")
            emit(
                'canvas_error', {
                    'message': 'Need at least 2 players to start!'})
            return

        print(f"✅ Game starting with {len(room['players'])} players")
        print(f"{'=' * 60}\n")

        start_drawing_round(room_code, socketio)

    def start_drawing_round(room_code, socketio):
        """Start a new drawing round"""
        room = canvas_rooms[room_code]
        room['round'] += 1
        room['status'] = 'drawing'
        room['round_start_time'] = time.time()
        room['voters'] = set()

        # Generate random theme
        themes = [
            'Sunset on Mars', 'Underwater City', 'Robot Dance Party',
            'Magic Forest', 'Space Station', 'Dragon Castle',
            'Neon Cityscape', 'Alien Garden', 'Time Machine',
            'Crystal Cave', 'Flying Car', 'Pirate Ship',
            'Zombie Apocalypse', 'Candy Land', 'Dinosaur Park',
            'Haunted House', 'Beach Paradise', 'Mountain Peak',
            'Desert Oasis', 'Arctic Adventure', 'Jungle Temple',
            'Medieval Battle', 'Steampunk City', 'Cyber Samurai'
        ]

        room['theme'] = random.choice(themes)

        # Reset player data for new round
        for player in room['players']:
            player['canvas_data'] = None
            player['votes'] = 0

        print(
            f"\n🎨 Round {room['round']}/{room['max_rounds']} - Theme: {room['theme']}")

        socketio.emit('drawing_round_start', {
            'round': room['round'],
            'max_rounds': room['max_rounds'],
            'theme': room['theme'],
            'time_limit': room['time_limit']
        }, room=room_code)

    @socketio.on('submit_canvas')
    def handle_submit_canvas(data):
        """Submit canvas drawing"""
        room_code = data.get('room_code', '').upper()
        canvas_data = data.get('canvas_data')
        player_id = request.sid

        print(f"\n{'=' * 60}")
        print(f"📤 CANVAS SUBMISSION")
        print(f"Room: {room_code}")
        print(f"Player ID: {player_id}")
        print(f"Data size: {len(canvas_data) if canvas_data else 0} bytes")

        if room_code not in canvas_rooms:
            print(f"❌ Room not found")
            print(f"{'=' * 60}\n")
            return

        if not canvas_data:
            print(f"❌ No canvas data provided")
            print(f"{'=' * 60}\n")
            emit('canvas_error', {'message': 'No drawing data received'})
            return

        room = canvas_rooms[room_code]

        player_found = False
        for player in room['players']:
            if player['id'] == player_id:
                player['canvas_data'] = canvas_data
                print(f"✅ {player['name']} submitted drawing")
                player_found = True
                break

        if not player_found:
            print(f"❌ Player not found in room")
            print(f"{'=' * 60}\n")
            return

        # Check if all players submitted
        submitted_count = sum(1 for p in room['players'] if p['canvas_data'])

        print(f"Submissions: {submitted_count}/{len(room['players'])}")
        print(f"{'=' * 60}\n")

        socketio.emit('canvas_submission_update', {
            'submitted': submitted_count,
            'total': len(room['players'])
        }, room=room_code)

        if submitted_count == len(room['players']):
            print(f"✅ All players submitted, starting voting...")
            start_voting_round(room_code, socketio)

    def start_voting_round(room_code, socketio):
        """Start voting round"""
        room = canvas_rooms[room_code]
        room['status'] = 'voting'

        # Prepare submissions for voting
        submissions = []
        for player in room['players']:
            if player['canvas_data']:
                submissions.append({
                    'player_id': player['id'],
                    'player_name': player['name'],
                    'canvas_data': player['canvas_data']
                })
            else:
                print(f"⚠️ {player['name']} has no canvas data!")

        print(f"\n{'=' * 60}")
        print(f"🗳️ VOTING ROUND STARTED")
        print(f"Room: {room_code}")
        print(f"Submissions: {len(submissions)}")
        for i, sub in enumerate(submissions):
            print(
                f"  {i + 1}. {sub['player_name']} - {len(sub['canvas_data'])} bytes")
        print(f"{'=' * 60}\n")

        if len(submissions) == 0:
            print(f"❌ No submissions to vote on!")
            socketio.emit('canvas_error', {
                'message': 'No drawings were submitted!'
            }, room=room_code)
            return

        socketio.emit('voting_round_start', {
            'submissions': submissions,
            'theme': room['theme']
        }, room=room_code)

    @socketio.on('submit_vote')
    def handle_submit_vote(data):
        """Submit vote for a drawing"""
        room_code = data.get('room_code', '').upper()
        voted_for_id = data.get('voted_for_id')
        voter_id = request.sid

        if room_code not in canvas_rooms:
            return

        room = canvas_rooms[room_code]

        if room['status'] != 'voting':
            emit('canvas_error', {'message': 'Voting is not open right now'})
            return

        # Can't vote for yourself
        if voted_for_id == voter_id:
            emit('canvas_error', {'message': 'Cannot vote for yourself!'})
            return

        # One vote per player per round
        if voter_id in room['voters']:
            emit('canvas_error', {'message': 'You already voted!'})
            return

        # Voter must be in the room
        if not any(p['id'] == voter_id for p in room['players']):
            emit('canvas_error', {'message': 'You are not in this game'})
            return

        # Add vote
        voted = False
        for player in room['players']:
            if player['id'] == voted_for_id:
                player['votes'] += 1
                voted = True
                print(f"✅ Vote recorded for {player['name']}")
                break

        if not voted:
            emit('canvas_error', {'message': 'Invalid vote target'})
            return

        room['voters'].add(voter_id)

        # Check if all players voted
        socketio.emit('vote_recorded', {
            'voter_id': voter_id,
            'votes_cast': len(room['voters']),
            'total_players': len(room['players'])
        }, room=room_code)

        # Auto-end voting once everyone has voted
        if len(room['voters']) >= len(room['players']):
            finish_voting_round(room_code, socketio)

    def finish_voting_round(room_code, socketio):
        """Tally votes, show results, and advance or finish the game."""
        room = canvas_rooms[room_code]

        # Calculate scores
        for player in room['players']:
            player['score'] += player['votes']

        # Sort by votes for this round
        round_results = sorted(
            room['players'],
            key=lambda p: p['votes'],
            reverse=True
        )

        print(f"\n🏆 Round {room['round']} Results:")
        for i, player in enumerate(round_results):
            print(f"{i + 1}. {player['name']}: {player['votes']} votes")

        socketio.emit('round_results', {
            'round': room['round'],
            'results': [{
                'name': p['name'],
                'votes': p['votes'],
                'total_score': p['score']
            } for p in round_results]
        }, room=room_code)

        # Check if game is over
        if room['round'] >= room['max_rounds']:
            end_game(room_code, socketio)
        else:
            room['status'] = 'waiting'

    @socketio.on('end_voting')
    def handle_end_voting(data):
        """End voting and show results (host only)"""
        room_code = data.get('room_code', '').upper()

        if room_code not in canvas_rooms:
            return

        room = canvas_rooms[room_code]

        if request.sid != room['host']:
            emit('canvas_error', {'message': 'Only the host can end voting'})
            return

        # Silently ignore a stale end-voting (e.g. the host client's
        # auto-timer firing after the server already ended voting on its
        # own): erroring here would pop a spurious alert on the host's
        # screen after results are already showing.
        if room['status'] != 'voting':
            return

        finish_voting_round(room_code, socketio)

    @socketio.on('next_round')
    def handle_next_round(data):
        """Start next round"""
        room_code = data.get('room_code', '').upper()

        if room_code not in canvas_rooms:
            return

        room = canvas_rooms[room_code]

        if request.sid != room['host']:
            return

        # Game is over; a finished game cannot start another round
        if room['status'] == 'finished':
            emit('canvas_error', {'message': 'Game is already finished'})
            return

        start_drawing_round(room_code, socketio)

    def end_game(room_code, socketio):
        """End the game and show final results"""
        room = canvas_rooms[room_code]
        room['status'] = 'finished'

        # Sort by total score
        final_results = sorted(
            room['players'],
            key=lambda p: p['score'],
            reverse=True
        )

        print(f"\n🎉 GAME OVER - Final Results:")
        for i, player in enumerate(final_results):
            print(f"{i + 1}. {player['name']}: {player['score']} total points")

        socketio.emit('game_over', {
            'final_results': [{
                'name': p['name'],
                'score': p['score'],
                'rank': i + 1
            } for i, p in enumerate(final_results)]
        }, room=room_code)

    @socketio.on('leave_canvas_room')
    def handle_leave_room(data):
        """Leave canvas battle room"""
        room_code = data.get('room_code', '').upper()
        player_id = request.sid

        if room_code not in canvas_rooms:
            return

        room = canvas_rooms[room_code]

        # Remove player
        room['players'] = [p for p in room['players'] if p['id'] != player_id]

        leave_room(room_code)

        if len(room['players']) == 0:
            # Delete empty room
            del canvas_rooms[room_code]
            print(f"🗑️ Room {room_code} deleted (empty)")
        else:
            # If host left, assign new host
            if room['host'] == player_id and len(room['players']) > 0:
                room['host'] = room['players'][0]['id']
                room['players'][0]['is_host'] = True

            socketio.emit('canvas_player_left', {
                'players': room['players']
            }, room=room_code)

    print("✅ Canvas Battle socket events registered")
