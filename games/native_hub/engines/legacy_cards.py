"""Card and gambling engines ported from the browser games catalog.

Poker's deck/blind/betting shape is ported from games/poker/socket_events.py
(whose own showdown was a TODO stub -- "first active player wins" -- so the
hand evaluator here is original, built the way TeenPattiEngine in duel.py
builds its own). Tambola ports ticket generation and win verification
directly from games/tambola/game_logic.py. Roulette ports the payout table
from games/roulette/socket_events.py. Digit Guess ports the bulls/cows
feedback formula from games/digit_guess/game_logic.py.
"""

import itertools
import random
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines._bases import TurnBasedEngine

# ---------------------------------------------------------------------------
# Poker -- verified against PokerBoardState/PokerControllerView in
# TVClassicGameBoards.swift and OtherControllerViews.swift. Plays a single
# hand to showdown (no multi-hand tournament loop) -- matching the pattern
# TeenPattiEngine already uses in duel.py for the other card game.
# ---------------------------------------------------------------------------

RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']
RANK_VALUE = {r: i + 2 for i, r in enumerate(RANKS)}
SUITS = ['♠', '♥', '♦', '♣']


def _make_deck():
    deck = [f"{r}{s}" for s in SUITS for r in RANKS]
    random.shuffle(deck)
    return deck


def _card_value(card):
    return RANK_VALUE[card[:-1]]


def _card_suit(card):
    return card[-1]


def _score_5(cards):
    """Standard hand ranking as a comparable tuple, high card counted last."""
    values = sorted((_card_value(c) for c in cards), reverse=True)
    suits = [_card_suit(c) for c in cards]
    counts: dict[int, int] = {}
    for v in values:
        counts[v] = counts.get(v, 0) + 1
    groups = sorted(counts.items(), key=lambda kv: (kv[1], kv[0]), reverse=True)
    group_sizes = [g[1] for g in groups]
    ordered_by_group = [g[0] for g in groups]

    flush = len(set(suits)) == 1
    distinct = sorted(set(values), reverse=True)
    straight_high = None
    if len(distinct) == 5:
        if distinct[0] - distinct[4] == 4:
            straight_high = distinct[0]
        elif distinct == [14, 5, 4, 3, 2]:
            straight_high = 5

    if straight_high and flush:
        return (8, straight_high)
    if group_sizes == [4, 1]:
        return (7, *ordered_by_group)
    if group_sizes == [3, 2]:
        return (6, *ordered_by_group)
    if flush:
        return (5, *values)
    if straight_high:
        return (4, straight_high)
    if group_sizes == [3, 1, 1]:
        return (3, *ordered_by_group)
    if group_sizes == [2, 2, 1]:
        return (2, *ordered_by_group)
    if group_sizes == [2, 1, 1, 1]:
        return (1, *ordered_by_group)
    return (0, *values)


def _best_hand(cards):
    if len(cards) <= 5:
        return _score_5(cards)
    return max(_score_5(list(combo)) for combo in itertools.combinations(cards, 5))


class PokerEngine(TurnBasedEngine):
    """Texas Hold'em over several hands.

    The table plays up to ``MAX_HANDS`` hands (dealer button rotating) or
    until one player holds every chip; final ranking is by chip count. Each
    hand ends on a short "showdown" pause so the TV can show who took the
    pot before the next deal.
    """

    game_id = "poker"
    min_players = 2
    max_players = 8
    turn_seconds = 45

    STARTING_CHIPS = 1000
    SMALL_BLIND = 10
    BIG_BLIND = 20
    STREETS = ["preflop", "flop", "turn", "river", "showdown"]
    MAX_HANDS = 10
    HAND_PAUSE_SECONDS = 6

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.deck: list[str] = []
        self.hands: dict[str, list[str]] = {}
        self.community: list[str] = []
        self.chips: dict[str, int] = {}
        self.contrib: dict[str, int] = {}
        self.current_bet = 0
        self.pot = 0
        self.folded: set[str] = set()
        self.all_in: set[str] = set()
        self.acted: set[str] = set()
        self.phase = "preflop"
        self.showdown: list[dict] = []
        self.hand_number = 0
        self.next_hand_at = 0.0
        self.game_over_pending = False
        self.last_hand: dict | None = None

    def setup(self):
        self.chips = {pid: self.STARTING_CHIPS for pid in self.order}
        self._start_hand()

    # ---- hand lifecycle ------------------------------------------------

    def _seated(self):
        return [pid for pid in self.order if self.chips.get(pid, 0) > 0]

    def _start_hand(self):
        seated = self._seated()
        if len(seated) < 2:
            self._finish_game()
            return
        self.hand_number += 1
        self.deck = _make_deck()
        self.hands = {pid: [self.deck.pop(), self.deck.pop()] for pid in seated}
        self.community = []
        self.contrib = {pid: 0 for pid in self.order}
        self.folded = {pid for pid in self.order if pid not in seated}
        self.all_in = set()
        self.acted = set()
        self.phase = "preflop"
        self.showdown = []
        self.winner = None
        self.next_hand_at = 0.0

        n = len(seated)
        dealer = (self.hand_number - 1) % n
        if n == 2:
            sb, bb = seated[dealer], seated[(dealer + 1) % n]   # heads-up: button posts SB
        else:
            sb, bb = seated[(dealer + 1) % n], seated[(dealer + 2) % n]
        self._post(sb, self.SMALL_BLIND)
        self._post(bb, self.BIG_BLIND)
        self.current_bet = max(self.contrib.values())

        self.turn_index = self.order.index(bb)
        if len(self._actionable()) <= 1 and self._bets_settled():
            self._run_out()
            return
        self.next_turn()

    def _end_hand(self, winners, share):
        self.pot = 0
        self.phase = "showdown"
        self.winner = winners[0] if len(winners) == 1 else None
        self.last_hand = {
            "handNumber": self.hand_number,
            "winnerIDs": list(winners),
            "winnerNames": [self.player_name(w) for w in winners],
            "amount": share,
        }
        self._sync_scores()
        self.deadline = 0.0
        if len(self._seated()) < 2 or self.hand_number >= self.MAX_HANDS:
            self.game_over_pending = True
        self.next_hand_at = time.time() + self.HAND_PAUSE_SECONDS

    def _finish_game(self):
        self._sync_scores()
        leader = max(self.order, key=lambda pid: self.chips.get(pid, 0)) if self.order else None
        self.finish(winner=leader)

    def tick(self, dt):
        if self._finished:
            return
        if self.next_hand_at:
            if time.time() >= self.next_hand_at:
                self.next_hand_at = 0.0
                if self.game_over_pending:
                    self._finish_game()
                else:
                    self._start_hand()
            return
        super().tick(dt)

    def on_turn_timeout(self):
        # An idle phone checks when it can and folds when it would have to pay.
        pid = self.current_player_id()
        if pid is None:
            return
        to_call = self.current_bet - self.contrib.get(pid, 0)
        self.handle_action(pid, "check" if to_call <= 0 else "fold", {})

    def on_player_leave(self, player_id):
        if (not self._finished and not self.next_hand_at
                and player_id in self.hands and player_id not in self.folded
                and self.is_my_turn(player_id)):
            self.handle_action(player_id, "fold", {})
            return
        super().on_player_leave(player_id)

    # ---- betting -------------------------------------------------------

    def _post(self, pid, amount):
        amount = min(amount, self.chips[pid])
        self.chips[pid] -= amount
        self.contrib[pid] += amount
        self.pot += amount
        if self.chips[pid] == 0:
            self.all_in.add(pid)

    def _live(self):
        return [pid for pid in self.order if pid not in self.folded]

    def _actionable(self):
        return [pid for pid in self.order if pid not in self.folded and pid not in self.all_in]

    def _bets_settled(self):
        return all(self.contrib[pid] >= self.current_bet for pid in self._actionable())

    def next_turn(self):
        live = self._actionable()
        if not live:
            return
        for _ in range(len(self.order)):
            self.turn_index = (self.turn_index + 1) % len(self.order)
            pid = self.order[self.turn_index]
            if pid in live:
                break
        self.reset_turn_clock()

    def _round_complete(self):
        live = self._actionable()
        if not live:
            return True
        if len(live) == 1 and self.contrib[live[0]] >= self.current_bet:
            return True       # everyone else is all-in or folded
        return all(pid in self.acted and self.contrib[pid] == self.current_bet for pid in live)

    def handle_action(self, player_id, action, data):
        if (self._finished or self.next_hand_at or player_id in self.folded
                or player_id in self.all_in or not self.is_my_turn(player_id)):
            return

        if action == "fold":
            self.folded.add(player_id)
            self.acted.add(player_id)
        elif action in ("check", "call"):
            call_amount = min(self.current_bet - self.contrib[player_id], self.chips[player_id])
            if call_amount > 0:
                self.chips[player_id] -= call_amount
                self.contrib[player_id] += call_amount
                self.pot += call_amount
                if self.chips[player_id] == 0:
                    self.all_in.add(player_id)
            self.acted.add(player_id)
        elif action == "bet":
            amount = data.get("amount")
            if not isinstance(amount, int):
                return
            amount = max(amount, self.current_bet)       # never less than a call
            if amount <= self.contrib[player_id]:
                return
            cost = min(amount - self.contrib[player_id], self.chips[player_id])
            self.chips[player_id] -= cost
            self.contrib[player_id] += cost
            self.pot += cost
            if self.contrib[player_id] > self.current_bet:
                self.current_bet = self.contrib[player_id]
                self.acted = {player_id}
            else:
                self.acted.add(player_id)
            if self.chips[player_id] == 0:
                self.all_in.add(player_id)
        else:
            return

        if len(self._live()) == 1:
            self._award(self._live()[0])
            return

        if self._round_complete():
            self._advance_street()
        else:
            self.next_turn()

    def _advance_street(self):
        self.acted = set()
        self.contrib = {pid: 0 for pid in self.order}
        self.current_bet = 0

        if self.phase == "river":
            self._showdown()
            return
        idx = self.STREETS.index(self.phase)
        if self.phase == "preflop":
            self.community += [self.deck.pop() for _ in range(3)]
        else:
            self.community.append(self.deck.pop())
        self.phase = self.STREETS[idx + 1]

        live = self._actionable()
        if len(live) <= 1:
            self._run_out()                 # nobody left to bet against
            return
        # First to act after the flop: the first live seat after the button.
        self.turn_index = self.order.index(live[0]) - 1
        self.next_turn()

    def _run_out(self):
        """Deal the rest of the board with no more betting, then show down."""
        while len(self.community) < 5:
            self.community.append(self.deck.pop())
        self.phase = "river"
        self._showdown()

    def _showdown(self):
        self.phase = "showdown"
        live = self._live()
        ranked = sorted(live, key=lambda pid: _best_hand(self.hands[pid] + self.community), reverse=True)
        best_score = _best_hand(self.hands[ranked[0]] + self.community)
        winners = [pid for pid in ranked
                   if _best_hand(self.hands[pid] + self.community) == best_score]
        self.showdown = [
            {"playerID": pid, "name": self.player_name(pid), "cards": self.hands[pid]}
            for pid in live
        ]
        share, remainder = divmod(self.pot, len(winners))
        for pid in winners:
            self.chips[pid] += share
        self.chips[winners[0]] += remainder
        self._end_hand(winners, share)

    def _award(self, winner):
        amount = self.pot
        self.chips[winner] += self.pot
        self._end_hand([winner], amount)

    def _sync_scores(self):
        for pid in self.order:
            self.scores[pid] = self.chips.get(pid, 0)
            player = self.room.player(pid)
            if player is not None:
                player.score = self.chips.get(pid, 0)

    def _status(self, pid):
        if pid in self.folded:
            return "folded"
        if pid in self.all_in:
            return "all-in"
        return "active"

    def public_state(self):
        state = self.base_public()
        current = self.current_player_id()
        state.update({
            "pot": self.pot,
            "phase": self.phase,
            "communityCards": list(self.community),
            "players": [
                {"id": pid, "name": self.player_name(pid), "chips": self.chips.get(pid, 0),
                 "currentBet": self.contrib.get(pid, 0), "status": self._status(pid),
                 "isCurrentTurn": pid == current}
                for pid in self.order
            ],
            "showdown": self.showdown,
            "handNumber": self.hand_number,
            "maxHands": self.MAX_HANDS,
            "lastHand": self.last_hand,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        min_bet = self.current_bet + self.BIG_BLIND if self.current_bet else self.BIG_BLIND
        to_call = max(0, min(self.current_bet - self.contrib.get(player_id, 0),
                             self.chips.get(player_id, 0)))
        state.update({
            "hand": self.hands.get(player_id, []),
            "chips": self.chips.get(player_id, 0),
            "minBet": min(min_bet, self.chips.get(player_id, 0) + self.contrib.get(player_id, 0)),
            "toCall": to_call,
            "folded": player_id in self.folded,
            "allIn": player_id in self.all_in,
            "isMyTurn": (self.is_my_turn(player_id) and not self.next_hand_at
                         and player_id not in self.folded and player_id not in self.all_in),
            "phase": self.phase,
            "handNumber": self.hand_number,
            "maxHands": self.MAX_HANDS,
            "lastHand": self.last_hand,
        })
        return state


# ---------------------------------------------------------------------------
# Tambola -- ports generate_ticket/verify_win from games/tambola/game_logic.py
# (WinType.FULL_HOUSE) and adds a periodic auto-caller since the browser
# game let the host call numbers manually with no server-driven cadence.
# Verified against TambolaBoardState/TambolaControllerView.
# ---------------------------------------------------------------------------


def _generate_ticket():
    grid = [[None] * 9 for _ in range(3)]
    for row in range(3):
        cols_with_numbers = random.sample(range(9), 5)
        for col in cols_with_numbers:
            if col == 0:
                num_range = range(1, 10)
            elif col == 8:
                num_range = range(80, 91)
            else:
                num_range = range(col * 10, col * 10 + 10)
            available = [n for n in num_range if all(grid[r][col] != n for r in range(3))]
            grid[row][col] = random.choice(available)
    for col in range(9):
        col_numbers = sorted(grid[row][col] for row in range(3) if grid[row][col] is not None)
        idx = 0
        for row in range(3):
            if grid[row][col] is not None:
                grid[row][col] = col_numbers[idx]
                idx += 1
    return grid


class TambolaEngine(NativeGameEngine):
    game_id = "tambola"
    min_players = 2
    max_players = 20

    CALL_INTERVAL_SECONDS = 3.0

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.tickets: dict[str, list] = {}
        self.marked: dict[str, set] = {}
        self.called: list[int] = []
        self.available: set = set()
        self.claims: list[str] = []
        self.next_call_at = 0.0
        self.winner: str | None = None
        self._finished = False

    def start(self, players):
        for p in players:
            self.tickets[p.id] = _generate_ticket()
            self.marked[p.id] = set()
        self.available = set(range(1, 91))
        self.next_call_at = time.time() + self.CALL_INTERVAL_SECONDS

    def _ticket_numbers(self, pid):
        return {n for row in self.tickets.get(pid, []) for n in row if n is not None}

    def tick(self, dt):
        if self._finished:
            return
        if time.time() >= self.next_call_at:
            if not self.available:
                self._finished = True
                return
            number = random.choice(list(self.available))
            self.available.discard(number)
            self.called.append(number)
            self.next_call_at = time.time() + self.CALL_INTERVAL_SECONDS

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        if action == "mark":
            number = data.get("number")
            if (isinstance(number, int) and number in self.called
                    and number in self._ticket_numbers(player_id)):
                self.marked.setdefault(player_id, set()).add(number)
        elif action == "claim":
            claim_type = data.get("type", "full_house")
            if claim_type != "full_house" or self.winner is not None:
                return
            all_numbers = self._ticket_numbers(player_id)
            marked = self.marked.get(player_id, set())
            if all_numbers and all_numbers.issubset(marked):
                self.winner = player_id
                self.claims.append(f"{self.player_name(player_id)} completed Full House!")
                player = self.room.player(player_id)
                if player is not None:
                    player.score = 1000
                self._finished = True

    def public_state(self):
        return {
            "called": list(self.called),
            "lastCalled": self.called[-1] if self.called else None,
            "claims": list(self.claims),
            "finished": self._finished,
            "winner": self.winner,
        }

    def private_state(self, player_id):
        return {
            "ticket": self.tickets.get(player_id, []),
            "marked": sorted(self.marked.get(player_id, set())),
            "finished": self._finished,
            "won": player_id == self.winner,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Roulette -- ports the payout table/bet_wins logic from
# games/roulette/socket_events.py, renamed to the target ids
# RouletteControllerView actually sends ("1-12" not "first12", etc).
# ---------------------------------------------------------------------------

RED_NUMBERS = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
ROULETTE_PAYOUTS = {
    "red": 2, "black": 2, "odd": 2, "even": 2,
    "1-12": 3, "13-24": 3, "25-36": 3, "low": 2, "high": 2,
}
# A straight-up bet on a single pocket ("0".."36") pays real-table 35-to-1 --
# 36x the stake back, same "total return" convention as ROULETTE_PAYOUTS
# above, not the "35 to 1" profit-only phrasing. These aren't in
# ROULETTE_PAYOUTS itself because there are 37 of them and they're
# data-derived (the target IS the number), not a fixed name.
STRAIGHT_UP_PAYOUT = 36
STRAIGHT_UP_TARGETS = {str(n) for n in range(37)}


def _number_color(n):
    if n == 0:
        return "green"
    return "red" if n in RED_NUMBERS else "black"


def _is_valid_bet_target(target):
    return target in ROULETTE_PAYOUTS or target in STRAIGHT_UP_TARGETS


def _payout_multiplier(bet_type):
    if bet_type in ROULETTE_PAYOUTS:
        return ROULETTE_PAYOUTS[bet_type]
    if bet_type in STRAIGHT_UP_TARGETS:
        return STRAIGHT_UP_PAYOUT
    return None


def _bet_wins(bet_type, number, color):
    if bet_type == "red":
        return color == "red"
    if bet_type == "black":
        return color == "black"
    if bet_type == "even":
        return number != 0 and number % 2 == 0
    if bet_type == "odd":
        return number != 0 and number % 2 == 1
    if bet_type == "low":
        return 1 <= number <= 18
    if bet_type == "high":
        return 19 <= number <= 36
    if bet_type == "1-12":
        return 1 <= number <= 12
    if bet_type == "13-24":
        return 13 <= number <= 24
    if bet_type == "25-36":
        return 25 <= number <= 36
    if bet_type in STRAIGHT_UP_TARGETS:
        return number == int(bet_type)
    return False


class RouletteEngine(NativeGameEngine):
    game_id = "roulette"
    min_players = 1
    max_players = 8
    # Only needs to notice its own spin deadline, but the default 1 Hz pump
    # would settle the wheel up to a second after the board's ball animation
    # has already come to rest. A few ticks a second keeps the number
    # appearing when the ball actually lands.
    tick_hz = 4.0

    STARTING_CHIPS = 1000
    MAX_ROUNDS = 15
    # A real wheel takes several seconds to settle, and the TV board
    # animates the ball decelerating into its pocket over exactly this
    # window (see TVRouletteBoardView). Two seconds read as an instant
    # cut rather than a spin.
    SPIN_SECONDS = 6.0

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.chips: dict[str, int] = {}
        self.bets: dict[str, dict[str, int]] = {}
        self.is_spinning = False
        self.spin_deadline = 0.0
        self.last_result: int | None = None
        # Chosen when the spin starts rather than when it ends, so the
        # board can animate the ball into the pocket it will actually
        # land in. Only ever published on public_state (the TV), never
        # on private_state (the phones), so nobody sees it early.
        self.pending_result: int | None = None
        self.round = 0
        self._finished = False

    def start(self, players):
        self.chips = {p.id: self.STARTING_CHIPS for p in players}
        self.bets = {p.id: {} for p in players}

    def handle_action(self, player_id, action, data):
        if self._finished or self.is_spinning or player_id not in self.chips:
            return
        if action == "place_bet":
            target = data.get("target")
            amount = data.get("amount")
            if (not isinstance(target, str) or not _is_valid_bet_target(target)
                    or isinstance(amount, bool) or not isinstance(amount, int) or amount <= 0):
                return
            if amount > self.chips[player_id]:
                return
            self.chips[player_id] -= amount
            player_bets = self.bets.setdefault(player_id, {})
            player_bets[target] = player_bets.get(target, 0) + amount
        elif action == "clear_bets":
            refund = sum(self.bets.get(player_id, {}).values())
            self.chips[player_id] += refund
            self.bets[player_id] = {}
        elif action == "spin":
            if any(self.bets.get(pid) for pid in self.bets):
                self.is_spinning = True
                self.pending_result = random.randint(0, 36)
                self.spin_deadline = time.time() + self.SPIN_SECONDS

    def tick(self, dt):
        if self._finished or not self.is_spinning:
            return
        if time.time() < self.spin_deadline:
            return
        result = self.pending_result if self.pending_result is not None \
            else random.randint(0, 36)
        color = _number_color(result)
        for pid, player_bets in self.bets.items():
            won = sum(amount * _payout_multiplier(target)
                      for target, amount in player_bets.items()
                      if _bet_wins(target, result, color))
            self.chips[pid] = self.chips.get(pid, 0) + won
        self.bets = {pid: {} for pid in self.chips}
        self.last_result = result
        self.pending_result = None
        self.is_spinning = False
        self.round += 1
        for pid in self.chips:
            player = self.room.player(pid)
            if player is not None:
                player.score = self.chips[pid]
        if self.round >= self.MAX_ROUNDS:
            self._finished = True

    def public_state(self):
        # spinRemaining rather than an absolute deadline: the Apple TV's
        # clock does not have to agree with the server's for the ball to
        # land on time.
        remaining = max(0.0, self.spin_deadline - time.time()) if self.is_spinning else 0.0
        # Per-target totals across every player, not per-player -- once bets
        # are on the table in a real casino they're visible to the whole
        # room, and the TV needs "how much is on red" / "how much is on 17"
        # to draw chip stacks on the felt, not who put it there.
        by_target: dict[str, int] = {}
        for player_bets in self.bets.values():
            for target, amount in player_bets.items():
                by_target[target] = by_target.get(target, 0) + amount
        return {
            "isSpinning": self.is_spinning,
            "lastResult": self.last_result,
            "pendingResult": self.pending_result if self.is_spinning else None,
            "spinRemaining": round(remaining, 2),
            "spinSeconds": self.SPIN_SECONDS,
            "playerBets": {pid: sum(b.values()) for pid, b in self.bets.items()},
            "betsByTarget": by_target,
            "chips": dict(self.chips),
            "round": self.round,
            "maxRounds": self.MAX_ROUNDS,
            "finished": self._finished,
        }

    def private_state(self, player_id):
        return {
            "chips": self.chips.get(player_id, 0),
            "bets": dict(self.bets.get(player_id, {})),
            "isSpinning": self.is_spinning,
            "lastResult": self.last_result,
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.chips)


# ---------------------------------------------------------------------------
# Digit Guess -- ports calculate_feedback (bulls/cows) from
# games/digit_guess/game_logic.py. The browser version was strictly
# 2-player turn-based against each other's secret; the native version has
# everyone racing to crack one shared secret simultaneously, matching
# DigitGuessControllerView's isMyTurn defaulting to true (no turn gate) and
# the TV's single "Guess the secret 4-digit code" header for the whole room.
# ---------------------------------------------------------------------------


class DigitGuessEngine(NativeGameEngine):
    game_id = "digit_guess"
    min_players = 2
    max_players = 4

    MAX_GUESSES = 15

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.secret = ""
        self.guesses: dict[str, list[dict]] = {}
        self.winner: str | None = None
        self._finished = False

    def start(self, players):
        self.secret = "".join(str(random.randint(0, 9)) for _ in range(4))
        self.guesses = {p.id: [] for p in players}

    @staticmethod
    def _feedback(secret, guess):
        bulls = sum(1 for i in range(4) if secret[i] == guess[i])
        correct_digits = 0
        for digit in set(guess):
            correct_digits += min(secret.count(digit), guess.count(digit))
        return bulls, correct_digits - bulls

    def handle_action(self, player_id, action, data):
        if self._finished or action != "guess" or player_id not in self.guesses:
            return
        if len(self.guesses[player_id]) >= self.MAX_GUESSES:
            return
        code = data.get("code")
        if not isinstance(code, str):
            digits = data.get("digits")
            code = "".join(str(d) for d in digits) if isinstance(digits, list) else None
        if not code or len(code) != 4 or not code.isdigit():
            return

        bulls, cows = self._feedback(self.secret, code)
        # "guess" is what the phone reads, "code" what the TV board reads.
        self.guesses[player_id].append({"guess": code, "code": code,
                                        "bulls": bulls, "cows": cows})
        if bulls == 4:
            self.winner = player_id
            self._finished = True
            player = self.room.player(player_id)
            if player is not None:
                player.score = max(100, 1000 - 50 * len(self.guesses[player_id]))
        elif all(len(g) >= self.MAX_GUESSES for g in self.guesses.values()):
            self._finished = True

    def public_state(self):
        return {
            "solved": self.winner is not None,
            "players": [
                {"id": p.id, "name": p.name, "guesses": self.guesses.get(p.id, [])}
                for p in self.room.players
            ],
        }

    def private_state(self, player_id):
        return {
            "isMyTurn": True,
            "myGuesses": self.guesses.get(player_id, []),
            "won": player_id == self.winner,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


ENGINES = {
    "poker": PokerEngine,
    "tambola": TambolaEngine,
    "roulette": RouletteEngine,
    "digit_guess": DigitGuessEngine,
}
