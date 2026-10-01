"""Engines with no browser backend to port from -- Heist, Stock Panic, Mind
Meld, Hot Grid and Speed Sculptor were Swift-only concepts from an earlier
PR (no games/heist, games/stock_panic, etc directories exist). Every engine
below is built directly from the Swift state contract:

* Heist        -- TVHeistBoardView.swift, HeistControllerView.swift,
                  Shared/Models/HeistTypes.swift (grid layout, phases,
                  camera-slot ids all copied verbatim from the Swift side).
* Stock Panic  -- TVClassicGameBoards.swift's StockPanicBoardState,
                  OtherControllerViews.swift's StockPanicControllerView.
* Mind Meld    -- TVClassicGameBoards.swift's MindMeldBoardState,
                  OtherControllerViews.swift's MindMeldControllerView.
* Hot Grid     -- TVClassicGameBoards.swift's HotGridBoardState (tile
                  content enum hidden/coin/trap/teleport),
                  OtherControllerViews.swift's HotGridControllerView.
* Speed Sculptor -- TVClassicGameBoards.swift's SpeedSculptorBoardState,
                  OtherControllerViews.swift's SpeedSculptorControllerView.
"""

import random
import time

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines._bases import TurnBasedEngine

# ---------------------------------------------------------------------------
# Heist
# ---------------------------------------------------------------------------

COLS, ROWS = 7, 7
MAX_ROUNDS = 8
SECONDS_PER_PHASE = 20

WALLS = {
    (2, 1), (2, 2), (2, 3), (4, 3), (4, 4), (4, 5), (2, 5), (2, 6),
}
CAMERA_STANDS = {(1, 1), (5, 1), (1, 5), (5, 5)}   # (col, row)
VAULT = (3, 3)
EXITS = {(0, 3), (6, 3)}

CAMERA_SLOTS = {
    "cam_tl": (1, 1), "cam_tr": (5, 1), "cam_bl": (1, 5), "cam_br": (5, 5),
}


def _tile_type(pos):
    col, row = pos
    if col in (0, COLS - 1) or row in (0, ROWS - 1):
        return "wall" if pos not in EXITS else "exit"
    if pos in WALLS:
        return "wall"
    if pos in CAMERA_STANDS:
        return "camera"
    if pos == VAULT:
        return "vault"
    return "empty"


def _in_bounds(pos):
    col, row = pos
    return 0 <= col < COLS and 0 <= row < ROWS


class HeistEngine(NativeGameEngine):
    game_id = "heist"
    min_players = 3
    max_players = 6

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.guard_id: str | None = None
        self.thieves: list[str] = []
        self.round = 1
        self.phase = "guard_sets"
        self.deadline = 0.0
        self.camera_positions: list[tuple] = []
        self.camera_arc_tiles: set[tuple] = set()
        self.positions: dict[str, tuple] = {}
        self.caught: dict[str, bool] = {}
        self.reached_vault: dict[str, bool] = {}
        self.escaped: dict[str, bool] = {}
        self.moved_this_round: set[str] = set()
        self.guard_submitted = False
        self.winner: str | None = None
        self._finished = False

    def start(self, players):
        ids = [p.id for p in players]
        self.guard_id = random.choice(ids)
        self.thieves = [pid for pid in ids if pid != self.guard_id]
        exits = list(EXITS)
        for i, pid in enumerate(self.thieves):
            self.positions[pid] = exits[i % len(exits)]
            self.caught[pid] = False
            self.reached_vault[pid] = False
            self.escaped[pid] = False
        self._enter_phase("guard_sets")

    def _enter_phase(self, phase):
        self.phase = phase
        self.deadline = time.time() + SECONDS_PER_PHASE
        if phase == "guard_sets":
            self.guard_submitted = False
            self.camera_positions = []
            self.camera_arc_tiles = set()
        elif phase == "thieves_move":
            self.moved_this_round = set()

    def seconds_left(self):
        return max(0, int(round(self.deadline - time.time()))) if self.deadline else 0

    def _live_thieves(self):
        return [pid for pid in self.thieves if not self.caught[pid] and not self.escaped[pid]]

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        if action == "set_cameras" and player_id == self.guard_id and self.phase == "guard_sets":
            ids = data.get("cameras")
            if not isinstance(ids, list):
                return
            chosen = [CAMERA_SLOTS[i] for i in ids[:2] if i in CAMERA_SLOTS]
            self.camera_positions = chosen
            self.camera_arc_tiles = set()
            for pos in chosen:
                col, row = pos
                self.camera_arc_tiles.add(pos)
                for dc, dr in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nxt = (col + dc, row + dr)
                    if _in_bounds(nxt) and _tile_type(nxt) != "wall":
                        self.camera_arc_tiles.add(nxt)
            self.guard_submitted = True
            self._enter_phase("thieves_move")

        elif action == "move" and player_id in self.thieves and self.phase == "thieves_move":
            if self.caught[player_id] or self.escaped[player_id] or player_id in self.moved_this_round:
                return
            direction = data.get("direction")
            col, row = self.positions[player_id]
            target = {"up": (col, row - 1), "down": (col, row + 1),
                      "left": (col - 1, row), "right": (col + 1, row)}.get(direction)
            if target is None or not _in_bounds(target) or _tile_type(target) == "wall":
                return
            self.positions[player_id] = target
            self.moved_this_round.add(player_id)
            if target == VAULT:
                self.reached_vault[player_id] = True
            elif target in EXITS and self.reached_vault[player_id]:
                self.escaped[player_id] = True

            live = self._live_thieves()
            if live and all(pid in self.moved_this_round for pid in live):
                self._resolve_round()

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        deadline_hit = now >= self.deadline
        if self.phase == "guard_sets" and (deadline_hit or self.guard_submitted):
            self._enter_phase("thieves_move")
            return
        if self.phase == "thieves_move":
            live = self._live_thieves()
            all_moved = bool(live) and all(pid in self.moved_this_round for pid in live)
            if deadline_hit or all_moved:
                self._resolve_round()
            return
        if self.phase == "reveal" and deadline_hit:
            self._start_next_round_or_finish()

    def _resolve_round(self):
        for pid in self._live_thieves():
            if self.positions[pid] in self.camera_arc_tiles:
                self.caught[pid] = True
        if any(self.escaped.values()):
            self.winner = "thieves"
            self._finish()
            return
        if all(self.caught[pid] for pid in self.thieves):
            self.winner = "guard"
            self._finish()
            return
        self.phase = "reveal"
        self.deadline = time.time() + 5

    def _start_next_round_or_finish(self):
        if self.round >= MAX_ROUNDS:
            self.winner = "guard"
            self._finish()
            return
        self.round += 1
        self._enter_phase("guard_sets")

    def _finish(self):
        self._finished = True
        for pid in self.thieves:
            player = self.room.player(pid)
            if player is not None:
                player.score = 1000 if self.winner == "thieves" else 0
        guard_player = self.room.player(self.guard_id) if self.guard_id else None
        if guard_player is not None:
            guard_player.score = 1000 if self.winner == "guard" else 0

    def public_state(self):
        return {
            "round": self.round,
            "phase": self.phase,
            "secondsLeft": self.seconds_left(),
            "cameraPositions": [{"col": c, "row": r} for c, r in self.camera_positions],
            "cameraArcTiles": [{"col": c, "row": r} for c, r in self.camera_arc_tiles],
            "thiefPositions": {pid: {"col": pos[0], "row": pos[1]}
                                for pid, pos in self.positions.items() if not self.caught[pid]},
            "playerStatuses": [
                {"id": self.guard_id, "name": self.player_name(self.guard_id), "role": "guard",
                 "isCaught": False, "hasEscaped": False},
            ] + [
                {"id": pid, "name": self.player_name(pid), "role": "thief",
                 "isCaught": self.caught[pid], "hasEscaped": self.escaped[pid]}
                for pid in self.thieves
            ] if self.guard_id else [],
            "winner": self.winner,
        }

    def private_state(self, player_id):
        is_guard = player_id == self.guard_id
        pos = self.positions.get(player_id, (1, 1))
        return {
            "role": "guard" if is_guard else "thief",
            "phase": self.phase,
            "round": self.round,
            "col": pos[0],
            "row": pos[1],
            "hasReachedVault": self.reached_vault.get(player_id, False),
            "isCaught": self.caught.get(player_id, False),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Stock Panic
# ---------------------------------------------------------------------------

STOCK_NAMES = ["AAPL", "TSLA", "GOOG", "AMZN", "MSFT", "NFLX"]
NEWS_TEMPLATES = ["{s} surges on earnings!", "{s} crashes after scandal!",
                   "{s} announces stock split!", "Investors flee {s}!"]


class StockPanicEngine(NativeGameEngine):
    game_id = "stock_panic"
    min_players = 2
    max_players = 6

    ROUND_SECONDS = 90
    TICK_INTERVAL = 4.0
    STARTING_CASH = 1000
    STARTING_PRICE = 100

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.prices: dict[str, int] = {}
        self.changes: dict[str, int] = {}
        self.cash: dict[str, int] = {}
        self.portfolio: dict[str, dict[str, int]] = {}
        self.latest_news: str | None = None
        self.deadline = 0.0
        self.next_tick_at = 0.0
        self._finished = False

    def start(self, players):
        self.prices = {s: self.STARTING_PRICE for s in STOCK_NAMES}
        self.changes = {s: 0 for s in STOCK_NAMES}
        for p in players:
            self.cash[p.id] = self.STARTING_CASH
            self.portfolio[p.id] = {s: 0 for s in STOCK_NAMES}
        now = time.time()
        self.deadline = now + self.ROUND_SECONDS
        self.next_tick_at = now + self.TICK_INTERVAL

    def handle_action(self, player_id, action, data):
        if self._finished or action != "trade" or player_id not in self.cash:
            return
        stock = data.get("stock")
        trade = data.get("action")
        if stock not in self.prices:
            return
        price = self.prices[stock]
        book = self.portfolio[player_id]
        if trade == "buy" and self.cash[player_id] >= price:
            self.cash[player_id] -= price
            book[stock] = book.get(stock, 0) + 1
        elif trade == "sell" and book.get(stock, 0) > 0:
            self.cash[player_id] += price
            book[stock] -= 1
        self._update_net_worth(player_id)

    def _update_net_worth(self, pid):
        worth = self.cash.get(pid, 0) + sum(
            qty * self.prices[s] for s, qty in self.portfolio.get(pid, {}).items())
        player = self.room.player(pid)
        if player is not None:
            player.score = worth

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        if now >= self.deadline:
            self._finished = True
            return
        if now >= self.next_tick_at:
            stock = random.choice(STOCK_NAMES)
            pct = random.uniform(-0.15, 0.18)
            old = self.prices[stock]
            new = max(1, int(round(old * (1 + pct))))
            self.changes[stock] = new - old
            self.prices[stock] = new
            if abs(pct) > 0.1:
                self.latest_news = random.choice(NEWS_TEMPLATES).format(s=stock)
            self.next_tick_at = now + self.TICK_INTERVAL
            for pid in self.cash:
                self._update_net_worth(pid)

    def public_state(self):
        return {
            "stocks": [
                {"id": s, "name": s, "price": self.prices[s], "change": self.changes[s]}
                for s in STOCK_NAMES
            ],
            "latestNews": self.latest_news,
            "secondsLeft": max(0, int(round(self.deadline - time.time()))),
            "finished": self._finished,
        }

    def private_state(self, player_id):
        return {
            "portfolio": dict(self.portfolio.get(player_id, {})),
            "cash": self.cash.get(player_id, 0),
            "finished": self._finished,
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results({p.id: p.score for p in self.room.players})


# ---------------------------------------------------------------------------
# Mind Meld
# ---------------------------------------------------------------------------

MELD_CATEGORIES = ["Colors", "Animals", "Fruits", "Sports", "Movies", "Countries", "Foods"]


class MindMeldEngine(NativeGameEngine):
    game_id = "mind_meld"
    min_players = 3
    max_players = 8

    TOTAL_ROUNDS = 5
    SUBMIT_SECONDS = 20
    REVEAL_SECONDS = 6

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.round = 0
        self.category = ""
        self.submissions: dict[str, str] = {}
        self.show_reveal = False
        self.deadline = 0.0
        self.scores: dict[str, int] = {}
        self._finished = False

    def start(self, players):
        self.scores = {p.id: 0 for p in players}
        self.round = 0
        self._next_round()

    def _next_round(self):
        self.round += 1
        self.category = random.choice(MELD_CATEGORIES)
        self.submissions = {}
        self.show_reveal = False
        self.deadline = time.time() + self.SUBMIT_SECONDS

    def handle_action(self, player_id, action, data):
        if self._finished or action != "word" or self.show_reveal:
            return
        word = str(data.get("word", "")).strip().lower()
        if word:
            self.submissions[player_id] = word

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        active = self.room.connected_players()
        everyone_submitted = bool(active) and all(p.id in self.submissions for p in active)
        if not self.show_reveal and (now >= self.deadline or everyone_submitted):
            self._reveal()
        elif self.show_reveal and now >= self.deadline:
            if self.round >= self.TOTAL_ROUNDS:
                self._finished = True
            else:
                self._next_round()

    def _reveal(self):
        self.show_reveal = True
        self.deadline = time.time() + self.REVEAL_SECONDS
        counts: dict[str, int] = {}
        for word in self.submissions.values():
            counts[word] = counts.get(word, 0) + 1
        for pid, word in self.submissions.items():
            if counts[word] >= 2:
                self.scores[pid] = self.scores.get(pid, 0) + 100
                player = self.room.player(pid)
                if player is not None:
                    player.score = self.scores[pid]

    def public_state(self):
        counts: dict[str, int] = {}
        for word in self.submissions.values():
            counts[word] = counts.get(word, 0) + 1
        return {
            "category": self.category,
            "submittedIDs": list(self.submissions.keys()),
            "showReveal": self.show_reveal,
            "submissions": [
                {"id": pid, "playerName": self.player_name(pid), "word": word,
                 "isMeld": counts[word] >= 2, "meldCount": counts[word]}
                for pid, word in self.submissions.items()
            ] if self.show_reveal else [],
            "finished": self._finished,
        }

    def private_state(self, player_id):
        return {
            "category": self.category,
            "round": self.round,
            "totalRounds": self.TOTAL_ROUNDS,
            "showReveal": self.show_reveal,
            "secondsLeft": max(0, int(round(self.deadline - time.time()))),
            "hasSubmitted": player_id in self.submissions,
            "myWord": self.submissions.get(player_id),
            "score": self.scores.get(player_id, 0),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.scores)


# ---------------------------------------------------------------------------
# Hot Grid
# ---------------------------------------------------------------------------


class HotGridEngine(TurnBasedEngine):
    """Take turns flipping tiles: coins score, traps burn points, teleports
    give a small bonus. Highest score when the grid is cleared wins."""

    game_id = "hot_grid"
    min_players = 2
    max_players = 8
    turn_seconds = 30           # an idle phone loses its turn, not the table's time

    SIZE = 5
    TRAP_PENALTY = 25

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.cells: list[dict] = []
        self.revealed: set[int] = set()
        self.last_pick: dict | None = None

    def setup(self):
        n = self.SIZE * self.SIZE
        self.cells = []
        for _ in range(n):
            roll = random.random()
            if roll < 0.6:
                self.cells.append({"type": "coin", "value": random.choice([10, 20, 30, 40, 50])})
            elif roll < 0.85:
                self.cells.append({"type": "trap", "value": 0})
            else:
                self.cells.append({"type": "teleport", "value": 15})

    def handle_action(self, player_id, action, data):
        if self._finished or action != "pick_tile" or not self.is_my_turn(player_id):
            return
        idx = data.get("index")
        if not isinstance(idx, int) or not 0 <= idx < len(self.cells) or idx in self.revealed:
            return
        self.revealed.add(idx)
        cell = self.cells[idx]
        delta = cell["value"] if cell["type"] in ("coin", "teleport") else -self.TRAP_PENALTY
        self.scores[player_id] = max(0, self.scores.get(player_id, 0) + delta)
        player = self.room.player(player_id)
        if player is not None:
            player.score = self.scores[player_id]
        self.last_pick = {"playerID": player_id, "name": self.player_name(player_id),
                          "index": idx, "tile": self._tile_display(idx), "delta": delta}
        if len(self.revealed) >= len(self.cells):
            self.finish()
            return
        self.next_turn()

    def _tile_display(self, idx):
        if idx not in self.revealed:
            return "hidden"
        cell = self.cells[idx]
        if cell["type"] == "coin":
            return str(cell["value"])
        return cell["type"]

    def public_state(self):
        state = self.base_public()
        current = self.current_player_id()
        state.update({
            "currentPlayerID": current or "",
            "currentPlayerName": self.player_name(current) if current else "",
            "tiles": [self._tile_display(i) for i in range(len(self.cells))],
            "lastPick": self.last_pick,
        })
        return state

    def private_state(self, player_id):
        state = self.base_private(player_id)
        # The phone needs the board too, so it only offers tiles still hidden.
        state["tiles"] = [self._tile_display(i) for i in range(len(self.cells))]
        state["lastPick"] = self.last_pick
        return state


# ---------------------------------------------------------------------------
# Speed Sculptor
# ---------------------------------------------------------------------------

DRAW_PROMPTS = ["Cat", "House", "Tree", "Car", "Sun", "Fish", "Robot", "Flower", "Rocket", "Boat"]


class SpeedSculptorEngine(NativeGameEngine):
    game_id = "speed_sculptor"
    min_players = 3
    max_players = 8

    TOTAL_ROUNDS = 3
    DRAW_SECONDS = 20
    VOTE_SECONDS = 15

    def __init__(self, room, broadcaster):
        super().__init__(room, broadcaster)
        self.round = 0
        self.prompt = ""
        self.voting_phase = False
        self.drawings: dict[str, dict] = {}
        self.votes: dict[str, str] = {}
        self.deadline = 0.0
        self.scores: dict[str, int] = {}
        self._finished = False

    def start(self, players):
        self.scores = {p.id: 0 for p in players}
        self.round = 0
        self._next_round()

    def _next_round(self):
        self.round += 1
        self.prompt = random.choice(DRAW_PROMPTS)
        self.voting_phase = False
        self.drawings = {}
        self.votes = {}
        self.deadline = time.time() + self.DRAW_SECONDS

    def handle_action(self, player_id, action, data):
        if self._finished:
            return
        if action == "drawing" and not self.voting_phase:
            self.drawings[player_id] = {
                "playerName": self.player_name(player_id),
                "lines": self._normalise_lines(data.get("lines"),
                                               data.get("width"), data.get("height")),
            }
        elif action == "vote" and self.voting_phase:
            target = data.get("targetID")
            if target and target != player_id and target in self.drawings:
                self.votes[player_id] = target

    MAX_POINTS = 1500

    @staticmethod
    def _normalise_lines(lines, width, height):
        """Lines as ``[[[x, y], ...], ...]`` with x/y in 0..1 -- what the TV draws.

        Accepts ``[x, y]`` pairs or ``{"x", "y"}`` points; points in canvas
        units are scaled by the phone-reported canvas size.
        """
        if not isinstance(lines, list):
            return []
        w = float(width) if isinstance(width, (int, float)) and width > 0 else None
        h = float(height) if isinstance(height, (int, float)) and height > 0 else None
        out, budget = [], SpeedSculptorEngine.MAX_POINTS
        for line in lines:
            if not isinstance(line, list) or budget <= 0:
                continue
            pts = []
            for p in line[:budget]:
                if isinstance(p, dict):
                    x, y = p.get("x"), p.get("y")
                elif isinstance(p, list) and len(p) >= 2:
                    x, y = p[0], p[1]
                else:
                    continue
                if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
                    continue
                if w and h:
                    x, y = x / w, y / h
                pts.append([round(min(1.0, max(0.0, float(x))), 3),
                            round(min(1.0, max(0.0, float(y))), 3)])
            budget -= len(pts)
            if pts:
                out.append(pts)
        return out

    def tick(self, dt):
        if self._finished:
            return
        now = time.time()
        active = self.room.connected_players()
        if not self.voting_phase:
            everyone_drew = bool(active) and all(p.id in self.drawings for p in active)
            if now >= self.deadline or everyone_drew:
                self.voting_phase = True
                self.deadline = now + self.VOTE_SECONDS
            return

        voters = [p for p in active if any(pid != p.id for pid in self.drawings)]
        everyone_voted = bool(voters) and all(p.id in self.votes for p in voters)
        if now >= self.deadline or everyone_voted:
            counts: dict[str, int] = {}
            for target in self.votes.values():
                counts[target] = counts.get(target, 0) + 1
            for pid, count in counts.items():
                self.scores[pid] = self.scores.get(pid, 0) + count * 50
                player = self.room.player(pid)
                if player is not None:
                    player.score = self.scores[pid]
            if self.round >= self.TOTAL_ROUNDS:
                self._finished = True
            else:
                self._next_round()

    def public_state(self):
        counts: dict[str, int] = {}
        for target in self.votes.values():
            counts[target] = counts.get(target, 0) + 1
        return {
            "prompt": self.prompt,
            "secondsLeft": max(0, int(round(self.deadline - time.time()))),
            "votingPhase": self.voting_phase,
            "submittedCount": len(self.drawings),
            "drawings": [
                {"id": pid, "playerName": d["playerName"], "lines": d["lines"],
                 "voteCount": counts.get(pid, 0)}
                for pid, d in self.drawings.items()
            ] if self.voting_phase else [],
            "finished": self._finished,
        }

    def private_state(self, player_id):
        return {
            "prompt": self.prompt,
            "round": self.round,
            "secondsLeft": max(0, int(round(self.deadline - time.time()))),
            "votingPhase": self.voting_phase,
            "hasSubmitted": player_id in self.drawings,
            "score": self.scores.get(player_id, 0),
            # Who you can vote for: everyone else who actually drew.
            "candidates": [
                {"id": pid, "playerName": d["playerName"]}
                for pid, d in self.drawings.items() if pid != player_id
            ] if self.voting_phase else [],
            "myVote": self.votes.get(player_id),
        }

    def is_over(self):
        return self._finished

    def results(self):
        return self.ranked_results(self.scores)


ENGINES = {
    "heist": HeistEngine,
    "stock_panic": StockPanicEngine,
    "mind_meld": MindMeldEngine,
    "hot_grid": HotGridEngine,
    "speed_sculptor": SpeedSculptorEngine,
}
