"""Regression tests for engine bugs found in the pre-game-night audit."""

import time

from tests.test_native_engines import make


class TestMemory:
    def _pair(self, engine):
        first = engine.cards[0]
        twin = next(i for i in range(1, len(engine.cards)) if engine.cards[i] == first)
        miss = next(i for i in range(1, len(engine.cards)) if engine.cards[i] != first)
        return twin, miss

    def test_match_scores_and_keeps_turn(self):
        engine, roster = make("memory", players=2)
        pid = engine.current_player_id()
        twin, _ = self._pair(engine)
        engine.handle_action(pid, "flip", {"index": 0})
        engine.handle_action(pid, "flip", {"index": twin})
        assert engine.scores[pid] == 1
        assert engine.room.player(pid).score == 1
        assert engine.current_player_id() == pid

    def test_mismatch_stays_visible_then_passes_turn(self, monkeypatch):
        engine, roster = make("memory", players=2)
        pid = engine.current_player_id()
        _, miss = self._pair(engine)
        engine.handle_action(pid, "flip", {"index": 0})
        engine.handle_action(pid, "flip", {"index": miss})
        cards = engine.public_state()["cards"]
        assert cards[0]["state"] == "flipped" and cards[miss]["state"] == "flipped"
        engine.handle_action(pid, "flip", {"index": 5})      # locked while showing
        assert len(engine.flipped) == 2

        later = time.time() + 5
        monkeypatch.setattr(time, "time", lambda: later)
        engine.tick(1.0)
        assert engine.flipped == []
        assert engine.current_player_id() != pid


class TestChess:
    def test_board_is_public_for_the_tv(self):
        engine, _ = make("chess", players=2)
        state = engine.public_state()
        assert len(state["board"]) == 8
        assert state["turnColor"] == "white"
        assert set(state["pieceColors"].values()) == {"white", "black"}

    def test_pawn_promotes_to_queen(self):
        engine, roster = make("chess", players=2)
        white = next(p for p, c in engine.piece_color.items() if c == "white")
        engine.board = [["" for _ in range(8)] for _ in range(8)]
        engine.board[1][0] = "♙"                      # white pawn
        engine.board[7][7] = "♔"                      # white king
        engine.board[0][7] = "♚"                      # black king
        engine.handle_action(white, "move", {"from": [1, 0], "to": [0, 0]})
        assert engine.board[0][0] == "♕"              # white queen

    def test_king_capture_wins_and_ranks_first(self):
        engine, roster = make("chess", players=2)
        white = next(p for p, c in engine.piece_color.items() if c == "white")
        engine.board = [["" for _ in range(8)] for _ in range(8)]
        engine.board[7][0] = "♖"                      # white rook
        engine.board[0][0] = "♚"                      # black king
        engine.board[7][7] = "♔"
        assert engine.public_state()["inCheck"] is False   # white to move
        engine.handle_action(white, "move", {"from": [7, 0], "to": [0, 0]})
        assert engine.is_over()
        assert engine.results()[0]["playerID"] == white


class TestTurnBasedRanking:
    def test_snake_ladder_winner_ranked_first(self):
        engine, roster = make("snake_ladder", players=3)
        last = roster[-1].id
        engine.finish(winner=last)
        assert engine.results()[0]["playerID"] == last
        assert [r["rank"] for r in engine.results()] == [1, 2, 3]


class _Clock:
    def __init__(self, monkeypatch):
        self.now = time.time()
        monkeypatch.setattr(time, "time", lambda: self.now)

    def advance(self, seconds):
        self.now += seconds


class TestPokerMultiHand:
    def _fold_to_one(self, engine):
        while len(engine._live()) > 1 and not engine.next_hand_at:
            engine.handle_action(engine.current_player_id(), "fold", {})

    def test_hand_ends_then_next_deal_after_pause(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("poker", players=3)
        assert engine.hand_number == 1
        self._fold_to_one(engine)
        assert engine.phase == "showdown" and engine.next_hand_at
        assert not engine.is_over()
        assert sum(engine.chips.values()) == 3 * engine.STARTING_CHIPS
        # Nobody can act during the pause.
        engine.handle_action(engine.current_player_id(), "check", {})
        clock.advance(engine.HAND_PAUSE_SECONDS + 1)
        engine.tick(1.0)
        assert engine.hand_number == 2 and engine.phase == "preflop"
        assert engine.pot == engine.SMALL_BLIND + engine.BIG_BLIND

    def test_game_finishes_after_max_hands_ranked_by_chips(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("poker", players=2)
        for _ in range(engine.MAX_HANDS):
            self._fold_to_one(engine)
            clock.advance(engine.HAND_PAUSE_SECONDS + 1)
            engine.tick(1.0)
        assert engine.is_over()
        results = engine.results()
        assert results[0]["score"] >= results[1]["score"]

    def test_idle_player_times_out(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("poker", players=3)
        idle = engine.current_player_id()
        clock.advance(engine.turn_seconds + 1)
        engine.tick(1.0)
        assert idle in engine.folded or engine.current_player_id() != idle

    def test_all_in_call_runs_out_the_board(self):
        engine, roster = make("poker", players=2)
        first = engine.current_player_id()
        engine.handle_action(first, "bet", {"amount": 5000})       # shove
        second = engine.current_player_id()
        assert second != first
        engine.handle_action(second, "call", {})
        assert engine.phase == "showdown"
        assert len(engine.community) == 5
        assert sum(engine.chips.values()) == 2 * engine.STARTING_CHIPS


class TestTeenPatti:
    def test_folded_player_never_gets_the_turn(self):
        engine, roster = make("teen_patti", players=3)
        folder = engine.current_player_id()
        engine.handle_action(folder, "fold", {})
        for _ in range(6):
            pid = engine.current_player_id()
            assert pid != folder
            engine.handle_action(pid, "call", {})
            if engine.is_over():
                break


class TestDigitGuess:
    def test_tv_and_phone_both_get_the_guess(self):
        engine, roster = make("digit_guess", players=2)
        engine.handle_action(roster[0].id, "guess", {"code": "1234"})
        entry = engine.public_state()["players"][0]["guesses"][0]
        assert entry["code"] == "1234" and entry["guess"] == "1234"


class TestSpeedSculptor:
    def test_point_dicts_are_normalised_for_the_tv(self):
        engine, roster = make("speed_sculptor", players=3)
        engine.handle_action(roster[0].id, "drawing", {
            "lines": [[{"x": 0, "y": 0}, {"x": 200, "y": 100}]],
            "width": 400, "height": 200})
        lines = engine.drawings[roster[0].id]["lines"]
        assert lines == [[[0.0, 0.0], [0.5, 0.5]]]

    def test_normalised_pairs_pass_through(self):
        engine, roster = make("speed_sculptor", players=3)
        engine.handle_action(roster[0].id, "drawing", {"lines": [[[0.25, 0.75]]]})
        assert engine.drawings[roster[0].id]["lines"] == [[[0.25, 0.75]]]

    def test_phone_gets_vote_candidates_and_votes_score(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("speed_sculptor", players=3)
        for p in roster:
            engine.handle_action(p.id, "drawing", {"lines": [[[0.1, 0.1]]]})
        engine.tick(0.1)                               # everyone drew -> voting
        private = engine.private_state(roster[0].id)
        assert private["votingPhase"] is True
        ids = {c["id"] for c in private["candidates"]}
        assert ids == {roster[1].id, roster[2].id}
        for p in roster:
            target = roster[(roster.index(p) + 1) % 3].id
            engine.handle_action(p.id, "vote", {"targetID": target})
        engine.tick(0.1)                               # everyone voted -> scored
        assert sum(engine.scores.values()) == 150
        assert engine.private_state(roster[0].id)["round"] == 2


class TestMindMeld:
    def test_private_state_carries_round(self):
        engine, roster = make("mind_meld", players=3)
        state = engine.private_state(roster[0].id)
        assert state["round"] == 1 and state["hasSubmitted"] is False
        engine.handle_action(roster[0].id, "word", {"word": "Mango"})
        assert engine.private_state(roster[0].id)["myWord"] == "mango"


class TestHotGrid:
    def test_trap_costs_points_and_phone_sees_tiles(self):
        engine, roster = make("hot_grid", players=2)
        pid = engine.current_player_id()
        engine.scores[pid] = 10
        trap = next((i for i, c in enumerate(engine.cells) if c["type"] == "trap"), None)
        if trap is None:
            engine.cells[0] = {"type": "trap", "value": 0}
            trap = 0
        engine.handle_action(pid, "pick_tile", {"index": trap})
        assert engine.scores[pid] == 0
        tiles = engine.private_state(roster[0].id)["tiles"]
        assert tiles[trap] == "trap" and tiles.count("hidden") == 24


class TestCarrom:
    def test_every_game_ends_on_the_shot_cap(self):
        engine, roster = make("carrom", players=2)
        for _ in range(engine.max_shots() + 5):
            if engine.is_over():
                break
            engine.handle_action(engine.current_player_id(), "flick",
                                 {"angle": 3.0, "power": 0.1})   # a feeble miss
        assert engine.is_over()

    def test_straight_shot_moves_the_coin_it_hits(self):
        engine, roster = make("carrom", players=2)
        queen = engine.coins[0]
        engine.striker_x = queen["x"]
        engine.handle_action(engine.current_player_id(), "flick", {"angle": 0.0, "power": 0.6})
        assert queen["potted"] or (queen["x"], queen["y"]) != (50.0, 50.0)


class TestLudo:
    def test_single_choice_moves_automatically(self, monkeypatch):
        import random
        engine, roster = make("ludo", players=2)
        pid = engine.current_player_id()
        monkeypatch.setattr(random, "randint", lambda a, b: 6)
        engine.handle_action(pid, "roll", {})
        # All four tokens were in the yard -- identical choices -- so one came out.
        assert engine.tokens[pid].count(0) == 1
        assert engine.die == 6 and engine.rolled is False
        assert engine.current_player_id() == pid          # a six rolls again
