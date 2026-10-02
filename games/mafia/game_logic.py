"""
Mafia Game Logic
Social deduction game with roles, day/night phases, and voting
"""

import random
from enum import Enum


class Role(Enum):
    MAFIA = "mafia"
    DOCTOR = "doctor"
    DETECTIVE = "detective"
    VILLAGER = "villager"


class Phase(Enum):
    LOBBY = "lobby"
    NIGHT = "night"
    DAY = "day"
    VOTING = "voting"
    FINISHED = "finished"


class MafiaGame:
    """Mafia game logic with roles, phases, and win conditions"""

    def __init__(self, room_code):
        self.room_code = room_code
        self.players = {}  # {player_id: {name, role, alive, votes}}
        self.phase = Phase.LOBBY
        self.night_actions = {}  # {player_id: action_data}
        self.day_votes = {}  # {voter_id: target_id}
        self.game_log = []
        self.round_number = 0
        self.killed_tonight = None
        self.saved_tonight = None
        self.investigated_tonight = None

    def add_player(self, player_id, player_name):
        """Add a player to the lobby"""
        if self.phase != Phase.LOBBY:
            return {'success': False, 'error': 'Game already started'}
        
        if player_id in self.players:
            return {'success': False, 'error': 'Already joined'}
        
        self.players[player_id] = {
            'name': player_name,
            'role': None,
            'alive': True,
            'votes': 0
        }
        
        self.log_event(f"{player_name} joined the game")
        return {'success': True}

    def start_game(self):
        """Assign roles and start the game"""
        if len(self.players) < 4:
            return {'success': False, 'error': 'Need at least 4 players'}
        
        if self.phase != Phase.LOBBY:
            return {'success': False, 'error': 'Game already started'}
        
        # Assign roles based on player count
        player_ids = list(self.players.keys())
        random.shuffle(player_ids)
        
        num_players = len(player_ids)
        num_mafia = max(1, num_players // 4)  # 25% mafia
        
        # Assign roles
        role_assignments = (
            [Role.MAFIA] * num_mafia +
            [Role.DOCTOR] +
            [Role.DETECTIVE] +
            [Role.VILLAGER] * (num_players - num_mafia - 2)
        )
        
        for i, player_id in enumerate(player_ids):
            self.players[player_id]['role'] = role_assignments[i]
        
        self.phase = Phase.NIGHT
        self.round_number = 1
        self.log_event("Game started! Night phase begins...")
        
        return {'success': True}

    def submit_night_action(self, player_id, action_type, target_id=None):
        """Submit a night action (kill, save, investigate)"""
        if self.phase != Phase.NIGHT:
            return {'success': False, 'error': 'Not night phase'}

        if player_id not in self.players:
            return {'success': False, 'error': 'You are not in this game'}
        
        if not self.players[player_id]['alive']:
            return {'success': False, 'error': 'You are dead'}
        
        player_role = self.players[player_id]['role']
        
        # Validate action type matches role
        if player_role == Role.MAFIA and action_type != 'kill':
            return {'success': False, 'error': 'Mafia can only kill'}
        elif player_role == Role.DOCTOR and action_type != 'save':
            return {'success': False, 'error': 'Doctor can only save'}
        elif player_role == Role.DETECTIVE and action_type != 'investigate':
            return {'success': False, 'error': 'Detective can only investigate'}
        elif player_role == Role.VILLAGER:
            return {'success': False, 'error': 'Villagers have no night action'}
        
        # Validate target
        if target_id and (target_id not in self.players or not self.players[target_id]['alive']):
            return {'success': False, 'error': 'Invalid target'}
        
        self.night_actions[player_id] = {
            'action': action_type,
            'target': target_id
        }
        
        return {'success': True}

    def remove_player_actions(self, player_id):
        """Drop any pending night actions / votes from a departed player."""
        self.night_actions.pop(player_id, None)
        self.day_votes.pop(player_id, None)
        # Votes aimed at the departed player no longer count
        self.day_votes = {
            voter: target for voter, target in self.day_votes.items()
            if target != player_id
        }

    def night_actions_complete(self):
        """True when every living special role has submitted a night action."""
        if self.phase != Phase.NIGHT:
            return False
        alive_with_actions = sum(
            1 for p in self.players.values()
            if p['alive'] and p['role'] and p['role'].value in ['mafia', 'doctor', 'detective']
        )
        return len(self.night_actions) >= alive_with_actions

    def resolve_night(self):
        """Resolve all night actions"""
        if self.phase != Phase.NIGHT:
            return {'success': False, 'error': 'Not night phase'}
        
        # Reset night state
        self.killed_tonight = None
        self.saved_tonight = None
        self.investigated_tonight = None
        
        # Process mafia kills
        mafia_kills = {}
        for player_id, action in self.night_actions.items():
            if action['action'] == 'kill' and self.players[player_id]['role'] == Role.MAFIA:
                target = action['target']
                mafia_kills[target] = mafia_kills.get(target, 0) + 1
        
        if mafia_kills:
            # Most voted target dies
            self.killed_tonight = max(mafia_kills, key=mafia_kills.get)
        
        # Process doctor save
        for player_id, action in self.night_actions.items():
            if action['action'] == 'save' and self.players[player_id]['role'] == Role.DOCTOR:
                self.saved_tonight = action['target']
        
        # Process detective investigation
        for player_id, action in self.night_actions.items():
            if action['action'] == 'investigate' and self.players[player_id]['role'] == Role.DETECTIVE:
                self.investigated_tonight = action['target']
        
        # Apply kill if not saved
        if self.killed_tonight and self.killed_tonight != self.saved_tonight:
            self.players[self.killed_tonight]['alive'] = False
            victim_name = self.players[self.killed_tonight]['name']
            self.log_event(f"{victim_name} was killed by the Mafia!")
        elif self.killed_tonight == self.saved_tonight:
            self.log_event("The Doctor saved someone tonight!")
        else:
            self.log_event("Nobody died tonight.")
        
        # Clear night actions
        self.night_actions = {}
        
        # Move to day phase
        self.phase = Phase.DAY
        self.log_event("Day phase begins. Discuss and vote!")
        
        # Check win condition
        winner = self.check_winner()
        if winner:
            self.phase = Phase.FINISHED
            return {'success': True, 'winner': winner}
        
        return {'success': True}

    def submit_vote(self, voter_id, target_id):
        """Submit a vote to eliminate a player"""
        if self.phase != Phase.VOTING:
            return {'success': False, 'error': 'Not voting phase'}

        if voter_id not in self.players:
            return {'success': False, 'error': 'You are not in this game'}
        
        if not self.players[voter_id]['alive']:
            return {'success': False, 'error': 'You are dead'}
        
        if target_id not in self.players or not self.players[target_id]['alive']:
            return {'success': False, 'error': 'Invalid target'}
        
        self.day_votes[voter_id] = target_id
        return {'success': True}

    def resolve_voting(self):
        """Resolve day voting and eliminate someone"""
        if self.phase != Phase.VOTING:
            return {'success': False, 'error': 'Not voting phase'}
        
        if not self.day_votes:
            self.log_event("No votes cast. Nobody eliminated.")
        else:
            # Count votes
            vote_counts = {}
            for target_id in self.day_votes.values():
                vote_counts[target_id] = vote_counts.get(target_id, 0) + 1
            
            # Find player with most votes
            eliminated_id = max(vote_counts, key=vote_counts.get)
            self.players[eliminated_id]['alive'] = False
            
            eliminated_name = self.players[eliminated_id]['name']
            eliminated_role = self.players[eliminated_id]['role'].value
            self.log_event(f"{eliminated_name} was eliminated! They were a {eliminated_role}.")
        
        # Clear votes
        self.day_votes = {}
        
        # Check win condition
        winner = self.check_winner()
        if winner:
            self.phase = Phase.FINISHED
            return {'success': True, 'winner': winner}
        
        # Move to night phase
        self.phase = Phase.NIGHT
        self.round_number += 1
        self.log_event(f"Night {self.round_number} begins...")
        
        return {'success': True}

    def start_voting(self):
        """Transition from day to voting phase"""
        if self.phase != Phase.DAY:
            return {'success': False, 'error': 'Not day phase'}
        
        self.phase = Phase.VOTING
        self.log_event("Voting phase begins!")
        return {'success': True}

    def check_winner(self):
        """Check if game is over and return winner"""
        alive_players = [p for p in self.players.values() if p['alive']]
        alive_mafia = [p for p in alive_players if p['role'] == Role.MAFIA]
        alive_villagers = [p for p in alive_players if p['role'] != Role.MAFIA]
        
        if not alive_mafia:
            return 'villagers'
        
        if len(alive_mafia) >= len(alive_villagers):
            return 'mafia'
        
        return None

    def get_game_state(self, player_id=None):
        """Get current game state (filtered by player if provided)"""
        state = {
            'room_code': self.room_code,
            'phase': self.phase.value,
            'round': self.round_number,
            'players': [],
            'log': self.game_log[-10:],  # Last 10 events
        }
        
        # Build player list
        for pid, pdata in self.players.items():
            player_info = {
                'id': pid,
                'name': pdata['name'],
                'alive': pdata['alive'],
            }
            
            # Only show role to the player themselves
            if player_id == pid and pdata['role'] is not None:
                player_info['role'] = pdata['role'].value
            
            state['players'].append(player_info)
        
        # Add phase-specific info
        if player_id and player_id in self.players:
            player_role = self.players[player_id]['role']
            
            if self.phase == Phase.NIGHT:
                # Show who has submitted actions
                state['actions_submitted'] = len(self.night_actions)
                
                # Detective gets investigation result
                if player_role == Role.DETECTIVE and self.investigated_tonight:
                    target_role = self.players[self.investigated_tonight]['role']
                    target_name = self.players[self.investigated_tonight]['name']
                    is_mafia = target_role == Role.MAFIA
                    state['investigation_result'] = {
                        'target': target_name,
                        'is_mafia': is_mafia
                    }
            
            elif self.phase == Phase.VOTING:
                state['votes_cast'] = len(self.day_votes)
                state['alive_count'] = sum(1 for p in self.players.values() if p['alive'])
        
        return state

    def log_event(self, message):
        """Add event to game log"""
        self.game_log.append(message)

    def get_player_role(self, player_id):
        """Get a player's role"""
        if player_id not in self.players:
            return None
        return self.players[player_id]['role'].value
