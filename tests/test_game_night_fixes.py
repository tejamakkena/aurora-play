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


class TestLudoDestinations:
    def _rolled(self, engine, pid, die, tokens):
        engine.tokens[pid] = list(tokens)
        engine.die = die
        engine.rolled = True

    def test_public_legal_lists_destinations_with_abs_cells(self):
        engine, roster = make("ludo", players=2)
        pid = engine.current_player_id()
        self._rolled(engine, pid, 3, [10, -1, -1, -1])
        legal = engine.public_state()["legal"]
        assert legal == [{"token": 0, "dest": 13, "destAbs": 13}]

    def test_track_wrap_lands_in_home_run_with_no_abs_cell(self):
        engine, roster = make("ludo", players=2)
        pid = engine.current_player_id()
        self._rolled(engine, pid, 4, [50, -1, -1, -1])
        legal = engine.public_state()["legal"]
        assert legal == [{"token": 0, "dest": 102, "destAbs": None}]

    def test_yard_entry_needs_a_six(self):
        engine, roster = make("ludo", players=2)
        pid = engine.current_player_id()
        self._rolled(engine, pid, 6, [-1, 20, -1, -1])
        by_token = {m["token"]: m for m in engine.public_state()["legal"]}
        assert by_token[0] == {"token": 0, "dest": 0, "destAbs": 0}
        assert by_token[1]["dest"] == 26 and by_token[1]["destAbs"] == 26
        self._rolled(engine, pid, 5, [-1, 20, -1, -1])
        assert [m["token"] for m in engine.public_state()["legal"]] == [1]

    def test_private_legal_dests_only_for_current_player(self):
        engine, roster = make("ludo", players=2)
        pid = engine.current_player_id()
        other = roster[1].id if roster[0].id == pid else roster[0].id
        self._rolled(engine, pid, 3, [10, -1, -1, -1])
        mine = engine.private_state(pid)
        assert mine["legalDests"] == [{"token": 0, "dest": 13, "destAbs": 13}]
        assert mine["currentPlayerName"] == engine.player_name(pid)
        assert engine.private_state(other)["legalDests"] == []

    def test_no_legal_before_roll_or_after_finish(self):
        engine, roster = make("ludo", players=2)
        pid = engine.current_player_id()
        assert engine.public_state()["legal"] == []
        engine.tokens[pid] = [105, 105, 105, 105]
        engine.die = 6
        engine.rolled = True
        assert engine._has_won(pid)
        engine.finish(winner=pid)
        assert engine.public_state()["legal"] == []


class TestTambola:
    def _call_all(self, engine, pid, numbers):
        for n in numbers:
            if n not in engine.called:
                engine.called.append(n)
            engine.handle_action(pid, "mark", {"number": n})

    def test_line_and_early_five_prizes(self):
        engine, roster = make("tambola", players=2)
        pid = roster[0].id
        top = sorted(engine._row_numbers(pid, 0))
        self._call_all(engine, pid, top)
        engine.handle_action(pid, "claim", {"type": "top_line"})
        engine.handle_action(pid, "claim", {"type": "early_five"})
        engine.handle_action(pid, "claim", {"type": "middle_line"})   # not complete
        winners = {p["type"]: p["winnerID"] for p in engine.public_state()["prizes"]}
        assert winners["top_line"] == pid and winners["early_five"] == pid
        assert winners["middle_line"] is None
        assert engine.scores[pid] == 250 and not engine.is_over()

    def test_prize_goes_to_first_claim_only(self):
        engine, roster = make("tambola", players=2)
        for p in roster:
            self._call_all(engine, p.id, sorted(engine._ticket_numbers(p.id))[:5])
        engine.handle_action(roster[1].id, "claim", {"type": "early_five"})
        engine.handle_action(roster[0].id, "claim", {"type": "early_five"})
        assert engine.prize_winners["early_five"] == roster[1].id

    def test_full_house_ends_the_game(self):
        engine, roster = make("tambola", players=2)
        pid = roster[0].id
        self._call_all(engine, pid, sorted(engine._ticket_numbers(pid)))
        engine.handle_action(pid, "claim", {"type": "full_house"})
        assert engine.is_over() and engine.results()[0]["playerID"] == pid

    def test_cannot_mark_uncalled_number(self):
        engine, roster = make("tambola", players=2)
        pid = roster[0].id
        n = sorted(engine._ticket_numbers(pid))[0]
        engine.handle_action(pid, "mark", {"number": n})
        assert engine.private_state(pid)["marked"] == []


class TestMafia:
    def _by_role(self, engine, role):
        return [pid for pid, r in engine.roles.items() if r == role]

    def test_tied_day_vote_spares_everyone(self):
        engine, roster = make("mafia", players=6)
        engine.phase = "day"
        alive = engine._alive_ids()
        a, b = alive[0], alive[1]
        engine.day_votes = {alive[2]: a, alive[3]: b}
        engine._resolve_day()
        assert engine.alive[a] and engine.alive[b] and engine.last_day_tie

    def test_sheriff_gets_one_investigation_per_night(self):
        engine, roster = make("mafia", players=6)
        sheriff = self._by_role(engine, "sheriff")[0]
        others = [pid for pid in engine._alive_ids() if pid != sheriff]
        engine.handle_action(sheriff, "investigate", {"targetID": others[0]})
        first = engine.investigate_results[sheriff]
        engine.handle_action(sheriff, "investigate", {"targetID": others[1]})
        assert engine.investigate_results[sheriff] == first

    def test_night_ends_once_every_role_has_acted(self):
        engine, roster = make("mafia", players=6)
        town = [pid for pid in engine._alive_ids() if engine.roles[pid] == "villager"]
        for m in self._by_role(engine, "mafia"):
            engine.handle_action(m, "eliminate", {"targetID": town[0]})
        engine.handle_action(self._by_role(engine, "doctor")[0], "save", {"targetID": town[1]})
        engine.handle_action(self._by_role(engine, "sheriff")[0], "investigate",
                             {"targetID": town[1]})
        assert engine.phase == "day"
        assert not engine.alive[town[0]]

    def test_mafia_know_their_team_and_flag_is_exact(self):
        engine, roster = make("mafia", players=8)       # two mafia
        m1, m2 = self._by_role(engine, "mafia")[:2]
        assert engine.private_state(m1)["mafiaTeam"] == [engine.player_name(m2)]
        sheriff = self._by_role(engine, "sheriff")[0]
        villager = self._by_role(engine, "villager")[0]
        engine.handle_action(sheriff, "investigate", {"targetID": villager})
        assert engine.private_state(sheriff)["investigateIsMafia"] is False
        assert engine.private_state(villager)["mafiaTeam"] == []


def _trivia_to(engine, phase, limit=200):
    """Fast-forward the trivia game show to ``phase`` by expiring deadlines."""
    for _ in range(limit):
        if engine.phase == phase:
            return
        engine.deadline = 0.0
        engine.tick(0.0)
    raise AssertionError(f"never reached {phase}, stuck in {engine.phase}")


class TestTrivia:
    def test_no_scoring_after_the_reveal(self):
        engine, roster = make("trivia", players=2)
        _trivia_to(engine, "question")
        engine.phase = "reveal"
        correct = engine.question[3]
        engine.handle_action(roster[0].id, "answer",
                             {"choiceIndex": correct, "questionID": engine.question_id})
        assert engine.scores[roster[0].id] == 0

    def test_small_pack_does_not_repeat(self):
        engine, roster = make("trivia", players=2)
        engine.room.content_pack = "te"
        engine.start(roster)
        assert engine.total_rounds == min(engine.MAIN_QUESTIONS, len(engine.pool))
        assert len({q[1] for q in engine.pool}) == len(engine.pool)


class TestBotPolicies:
    def test_trivia_bot_sends_a_valid_answer(self):
        from games.native_hub import bots
        engine, roster = make("trivia", players=2)
        _trivia_to(engine, "question")
        verb, data = bots._policy_trivia(engine, "bot-x")
        assert verb == "answer"
        assert data["questionID"] == engine.question_id
        assert 0 <= data["choiceIndex"] < len(engine.question[2])

    def test_trivia_bot_answer_is_accepted(self):
        from games.native_hub import bots
        engine, roster = make("trivia", players=2)
        bot = engine.room.add_bot()
        engine.scores[bot.id] = 0
        _trivia_to(engine, "question")
        engine.choices_at = time.time()     # the question has been read out
        verb, data = bots._policy_trivia(engine, bot.id)
        engine.handle_action(bot.id, verb, data)
        assert bot.id in engine.answered


class TestRajaMantri:
    def test_idle_sipahi_times_out_and_cannot_accuse_self(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("raja_mantri", players=4)
        engine.handle_action(engine.sipahi_id, "accuse", {"targetID": engine.sipahi_id})
        assert engine.phase == "guess"
        clock.advance(engine.GUESS_SECONDS + 1)
        engine.tick(1.0)
        assert engine.phase == "reveal" and "ran out of time" in engine.round_result


class TestRoulette:
    def test_betting_clock_spins_without_everyone_ready(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("roulette", players=3)
        engine.handle_action(roster[0].id, "place_bet", {"target": "red", "amount": 10})
        engine.handle_action(roster[0].id, "spin", {})
        assert not engine.is_spinning
        clock.advance(engine.BET_SECONDS + 1)
        engine.tick(0.25)
        assert engine.is_spinning


class TestOddOneOut:
    def test_three_rounds_with_scoring(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("odd_one_out", players=4)
        spies = set()
        for round_no in range(1, engine.TOTAL_ROUNDS + 1):
            assert engine.round == round_no and engine.phase == "question"
            spies.add(engine.spy)
            engine.handle_action(roster[0].id, "call_vote", {})
            for p in roster:
                target = engine.spy if p.id != engine.spy else \
                    next(r.id for r in roster if r.id != p.id)
                engine.handle_action(p.id, "vote", {"targetID": target})
            assert engine.phase == "reveal" and engine.winner == "players"
            assert engine.public_state()["location"]
            clock.advance(engine.REVEAL_SECONDS + 1)
            engine.tick(1.0)
        assert engine.is_over()
        assert len(spies) == engine.TOTAL_ROUNDS            # a new spy each round

    def test_tied_vote_lets_the_spy_escape(self):
        engine, roster = make("odd_one_out", players=4)
        engine.handle_action(roster[0].id, "call_vote", {})
        others = [p.id for p in roster if p.id != engine.spy]
        engine.votes = {others[0]: others[1], others[1]: engine.spy}
        engine._resolve_vote()
        assert engine.winner == "spy" and engine.scores[engine.spy] == 2


class TestGuessMatching:
    def test_charades_accepts_initials_and_typos(self):
        engine, roster = make("bollywood_charades", players=3)
        engine.title = "Dilwale Dulhania Le Jayenge"
        guesser = next(p.id for p in roster if p.id != engine.actor)
        engine.handle_action(guesser, "guess", {"text": "DDLJ"})
        assert guesser in engine.correct_ids


class TestKBC:
    def test_hot_seat_rotates_after_a_wrong_answer(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("kbc", players=3)
        first = engine.hot_seat
        wrong = next(i for i in range(len(engine.choices)) if i != engine.correct)
        engine.handle_action(first, "answer", {"index": wrong})
        assert engine.phase == "reveal" and not engine.is_over()   # reveal is shown
        clock.advance(engine.REVEAL_SECONDS + 1)
        engine.tick(1.0)
        assert engine.hot_seat != first and engine.rung == 0
        assert engine.lifelines == {"fifty": True, "poll": True, "skip": True}

    def test_skip_flips_the_question_without_climbing(self):
        engine, roster = make("kbc", players=2)
        before = engine.question
        engine.handle_action(engine.hot_seat, "lifeline_skip", {})
        assert engine.rung == 0 and engine.question != before

    def test_game_ends_after_every_seat_and_ranks_banked(self, monkeypatch):
        clock = _Clock(monkeypatch)
        engine, roster = make("kbc", players=2)
        engine.handle_action(engine.hot_seat, "answer", {"index": engine.correct})
        clock.advance(engine.REVEAL_SECONDS + 1)
        engine.tick(1.0)
        first = roster[0].id if engine.banked_by[roster[0].id] else roster[1].id
        for _ in range(2):
            engine.handle_action(engine.hot_seat, "walk_away", {})
            clock.advance(engine.REVEAL_SECONDS + 1)
            engine.tick(1.0)
        assert engine.is_over()
        assert engine.results()[0]["playerID"] == first


class TestHerd:
    def test_spelling_variants_herd_together_and_loners_score_nothing(self):
        engine, roster = make("herd", players=4)
        a, b, c, d = (p.id for p in roster)
        engine.submissions = {a: "Idli", b: "idly", c: "Idlis", d: "Dosa"}
        engine._cluster_and_score()
        assert engine.clusters[0]["size"] == 3
        assert engine.scores[a] == engine.scores[b] == engine.scores[c] > 0
        assert engine.scores[d] == 0


class TestLudoSafeSquares:
    """Start squares and star squares must block captures (classic rules)."""

    def _ids(self, engine, roster):
        pid = engine.current_player_id()
        other = roster[1].id if roster[0].id == pid else roster[0].id
        return pid, other

    def test_capture_on_normal_square_works(self):
        engine, roster = make("ludo", players=2)
        pid, other = self._ids(engine, roster)
        engine.tokens[pid] = [10, -1, -1, -1]      # abs 10
        engine.tokens[other] = [49, -1, -1, -1]    # abs (13+49)%52 = 10
        engine.die = 0
        assert engine._apply_move(pid, 0) is True
        assert engine.tokens[other][0] == -1       # sent back to the yard

    def test_no_capture_on_start_square(self):
        engine, roster = make("ludo", players=2)
        pid, other = self._ids(engine, roster)
        engine.tokens[pid] = [0, -1, -1, -1]       # abs 0, a start square
        engine.tokens[other] = [39, -1, -1, -1]    # abs (13+39)%52 = 0
        engine.die = 0
        assert engine._apply_move(pid, 0) is False
        assert engine.tokens[other][0] == 39        # coexists, not captured
        assert engine.tokens[pid][0] == 0

    def test_no_capture_on_star_square(self):
        engine, roster = make("ludo", players=2)
        pid, other = self._ids(engine, roster)
        engine.tokens[pid] = [8, -1, -1, -1]       # abs 8, a star square
        engine.tokens[other] = [47, -1, -1, -1]    # abs (13+47)%52 = 8
        engine.die = 0
        assert engine._apply_move(pid, 0) is False
        assert engine.tokens[other][0] == 47
        assert engine.tokens[pid][0] == 8

    def test_yard_exit_onto_occupied_start_is_safe(self):
        engine, roster = make("ludo", players=2)
        pid, other = self._ids(engine, roster)
        engine.tokens[pid] = [-1, -1, -1, -1]
        engine.tokens[other] = [39, -1, -1, -1]    # sitting on abs 0
        engine.die = 6
        assert engine._apply_move(pid, 0) is False
        assert engine.tokens[pid][0] == 0          # entered the track
        assert engine.tokens[other][0] == 39       # not captured

    def test_home_run_tokens_cannot_be_captured(self):
        engine, roster = make("ludo", players=2)
        pid, other = self._ids(engine, roster)
        engine.tokens[pid] = [102, -1, -1, -1]     # deep in the home stretch
        engine.tokens[other] = [100, -1, -1, -1]   # opponent also home
        engine.die = 0
        assert engine._apply_move(pid, 0) is False
        assert engine.tokens[pid][0] == 102
        assert engine.tokens[other][0] == 100

    def test_public_state_exposes_safe_squares(self):
        engine, _ = make("ludo", players=2)
        assert engine.public_state()["safe"] == [0, 8, 13, 21, 26, 34, 39, 47]


class TestRouletteResultMatchesSpin:
    def test_settled_number_is_the_one_the_wheel_was_sent(self, monkeypatch):
        clock = _Clock(monkeypatch)
        for _ in range(20):
            engine, roster = make("roulette", players=1)
            engine.handle_action(roster[0].id, "place_bet", {"target": "red", "amount": 10})
            engine.handle_action(roster[0].id, "spin", {})
            announced = engine.public_state()["pendingResult"]
            assert announced is not None and 0 <= announced <= 36
            clock.advance(engine.SPIN_SECONDS + 0.1)
            engine.tick(0.25)
            assert engine.public_state()["lastResult"] == announced
