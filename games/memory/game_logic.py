import random


class MemoryGame:
    """Memory Card Matching Game Logic"""

    # Card symbols/emojis for the game (8 pairs = 16 cards for 4x4 grid)
    CARD_SYMBOLS = ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
                    '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔']

    def __init__(self, room_code, grid_size=16):
        self.room_code = room_code
        self.grid_size = grid_size  # Default 4x4 grid (16 cards)
        self.players = {}  # {player_id: {'name': str, 'score': int}}
        self.current_player_idx = 0
        self.player_order = []  # List of player_ids in turn order
        self.cards = []
        self.flipped_cards = []  # Currently flipped cards (max 2)
        self.matched_cards = []  # List of matched card indices
        self.state = "WAITING"  # WAITING, PLAYING, FINISHED
        self.winner = None
        self.initialize_deck()

    def initialize_deck(self):
        """Create and shuffle card deck"""
        num_pairs = self.grid_size // 2
        selected_symbols = random.sample(self.CARD_SYMBOLS, num_pairs)
        
        # Create pairs
        deck = []
        for symbol in selected_symbols:
            deck.append({'symbol': symbol, 'matched': False})
            deck.append({'symbol': symbol, 'matched': False})
        
        # Shuffle
        random.shuffle(deck)
        self.cards = deck

    def add_player(self, player_id, player_name=None):
        """Add a player to the game"""
        if len(self.players) >= 4:
            return None
        
        if player_id not in self.players:
            self.players[player_id] = {
                'name': player_name or f'Player {len(self.players) + 1}',
                'score': 0
            }
            self.player_order.append(player_id)
            
            # Start game if we have at least 1 player
            if len(self.players) == 1:
                self.state = "PLAYING"
        
        return self.players[player_id]

    def get_current_player_id(self):
        """Get the current player's ID"""
        if not self.player_order:
            return None
        return self.player_order[self.current_player_idx]

    def flip_card(self, player_id, card_index):
        """Flip a card"""
        # Validate turn
        if self.get_current_player_id() != player_id:
            return {'success': False, 'error': 'Not your turn'}
        
        # Validate card index
        if (not isinstance(card_index, int) or isinstance(card_index, bool)
                or card_index < 0 or card_index >= len(self.cards)):
            return {'success': False, 'error': 'Invalid card index'}
        
        # Check if card already matched
        if card_index in self.matched_cards:
            return {'success': False, 'error': 'Card already matched'}
        
        # Check if card already flipped
        if card_index in self.flipped_cards:
            return {'success': False, 'error': 'Card already flipped'}
        
        # Check if we already have 2 cards flipped
        if len(self.flipped_cards) >= 2:
            return {'success': False, 'error': 'Two cards already flipped. Check for match first.'}
        
        # Flip the card
        self.flipped_cards.append(card_index)
        
        # Check for match if 2 cards are flipped
        if len(self.flipped_cards) == 2:
            match_result = self.check_match()
            return {
                'success': True,
                'card': self.cards[card_index],
                'flipped_cards': self.flipped_cards,
                'match_result': match_result,
                'game_state': self.get_game_state()
            }
        
        return {
            'success': True,
            'card': self.cards[card_index],
            'flipped_cards': self.flipped_cards,
            'game_state': self.get_game_state()
        }

    def check_match(self):
        """Check if the two flipped cards match"""
        if len(self.flipped_cards) != 2:
            return {'matched': False, 'error': 'Need 2 cards to check match'}
        
        idx1, idx2 = self.flipped_cards
        card1 = self.cards[idx1]
        card2 = self.cards[idx2]
        
        if card1['symbol'] == card2['symbol']:
            # Match found!
            current_player_id = self.get_current_player_id()
            if current_player_id is None or current_player_id not in self.players:
                self.flipped_cards = []
                return {'matched': False, 'error': 'Current player left the game'}
            self.players[current_player_id]['score'] += 1
            self.matched_cards.extend([idx1, idx2])
            
            # Check if game is finished
            if len(self.matched_cards) == len(self.cards):
                self.state = "FINISHED"
                self.determine_winner()
            
            # Clear flipped cards (player gets another turn)
            self.flipped_cards = []
            
            return {
                'matched': True,
                'indices': [idx1, idx2],
                'player': current_player_id,
                'score': self.players[current_player_id]['score']
            }
        else:
            # No match - next player's turn
            return {'matched': False, 'indices': [idx1, idx2]}

    def reset_flipped_cards(self):
        """Reset flipped cards and move to next player"""
        if len(self.flipped_cards) == 2:
            # Check if they were matched
            if self.flipped_cards[0] not in self.matched_cards:
                # Not matched, move to next player
                self.next_turn()
        
        self.flipped_cards = []
        return {'success': True}

    def remove_player(self, player_id):
        """Remove a player and keep the turn pointer valid."""
        if player_id not in self.players:
            return False

        removed_index = (self.player_order.index(player_id)
                         if player_id in self.player_order else None)
        was_current = (removed_index is not None
                       and removed_index == self.current_player_idx)

        del self.players[player_id]
        if player_id in self.player_order:
            self.player_order.remove(player_id)

        if not self.player_order:
            self.current_player_idx = 0
            self.flipped_cards = []
            return True

        if removed_index is not None:
            if removed_index < self.current_player_idx:
                self.current_player_idx -= 1
            # removed_index == current: the next player slides into this
            # slot, so the index stays as-is (modulo the new length).
            self.current_player_idx %= len(self.player_order)

        # A mid-turn leave drops the abandoned flipped cards
        if was_current:
            self.flipped_cards = []
        return True

    def next_turn(self):
        """Move to next player's turn"""
        if len(self.player_order) > 0:
            self.current_player_idx = (
                self.current_player_idx + 1) % len(self.player_order)

    def determine_winner(self):
        """Determine the winner based on scores"""
        if not self.players:
            return
        
        max_score = max(p['score'] for p in self.players.values())
        winners = [
            pid for pid,
            p in self.players.items() if p['score'] == max_score]
        
        if len(winners) == 1:
            self.winner = winners[0]
        else:
            self.winner = "TIE"

    def get_game_state(self):
        """Get current game state"""
        return {
            'cards': [
                {
                    'symbol': card['symbol'] if i in self.matched_cards or i in self.flipped_cards else '❓',
                    'matched': i in self.matched_cards,
                    'flipped': i in self.flipped_cards
                }
                for i, card in enumerate(self.cards)
            ],
            'players': self.players,
            'current_player': self.get_current_player_id(),
            'flipped_cards': self.flipped_cards,
            'matched_count': len(self.matched_cards),
            'total_pairs': self.grid_size // 2,
            'state': self.state,
            'winner': self.winner
        }
