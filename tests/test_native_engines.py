"""Every game engine, driven through real play.

The privacy tests are the important ones. `public_state()` goes to the whole
room and the TV renders it on a screen everyone can see, so a secret leaking
into it breaks the game regardless of what the phone UI chooses to draw.
"""

import json
import random

import pytest

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines._placeholder import PlaceholderEngine
from games.native_hub.registry import ENGINES, engine_for
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(game_id, players=4, seed=7):
    """Start a game with a plausible number of players."""
    random.seed(seed)
    cls = ENGINES[game_id]
    registry = RoomRegistry()
    room = registry.create(game_id)
    count = min(max(cls.min_players, players), cls.max_players)
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(count)]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


# Plausible actions per game, so the play loop exercises real code paths.
ACTIONS = {
    "bluff_it": [("submit_lie", {"text": "banana"}), ("pick", {"index": 0})],
    "last_tap": [("tap", {})],
    "herd": [("answer", {"text": "idli"})],
    "emoji_movie": [("submit_emoji", {"emoji": "\U0001F981\U0001F451"}),
                    ("guess", {"index": 0, "text": "Frozen"})],
    "npat": [("submit", {"name": "Amit", "place": "Agra",
                         "animal": "Ant", "thing": "Axe"})],
    "antakshari": [("submit_song", {"song": "Anything"})],
    "most_likely_to": [("vote", {"targetID": "p1"})],
    "brain_battle": [("answer", {"choice": "A"})],
    "cipher_grid": [("give_clue", {"word": "animal", "count": 2}),
                    ("guess", {"index": 0}), ("end_turn", {})],
    "odd_one_out": [("call_vote", {}), ("vote", {"targetID": "p1"})],
    "sealed_auction": [("bid", {"amount": 20})],
    "wavelength": [("give_clue", {"clue": "tea"}), ("set_dial", {"value": 60})],
    "kbc": [("lifeline_fifty", {}), ("poll_vote", {"index": 0}), ("answer", {"index": 0})],
    "bollywood_charades": [("guess", {"text": "Sholay"})],
    "defuse": [("cut", {"index": 0}), ("button", {"press": "tap"}),
               ("symbol", {"index": 0})],
    "battleship": [("fire", {"cell": 5}), ("fire", {"cell": 12})],
    "air_hockey": [("paddle", {"x": 40})],
    "heist_escape": [("move", {"direction": "right"}), ("move", {"direction": "down"})],
    "ludo": [("roll", {}), ("move", {"token": 0})],
    "carrom": [("position", {"x": 50}), ("flick", {"angle": 0.1, "power": 0.8})],
    "teen_patti": [("see", {}), ("call", {}), ("bet", {}), ("fold", {})],
    "neon_snake": [("turn", {"direction": "down"}), ("turn", {"direction": "left"})],
    "twenty48": [("swipe", {"direction": "left"}), ("swipe", {"direction": "up"})],
    "brick_breaker": [("paddle", {"x": 55})],
    "simon_says": [("pad", {"pad": "up"}), ("pad", {"pad": "down"})],
    "atlas": [("answer", {"place": "Agra"}), ("answer", {"place": "Nepal"})],
    "connect4": [("drop", {"column": 0}), ("drop", {"column": 1})],
    "memory": [("flip", {"index": 0}), ("flip", {"index": 1})],
    "chess": [("select", {"row": 6, "col": 0}), ("move", {"from": [6, 0], "to": [4, 0]})],
    "snake_ladder": [("roll", {"value": 4})],
    "pong": [("paddle", {"position": 0.2})],
    "poker": [("check", {}), ("bet", {"amount": 40}), ("fold", {})],
    "tambola": [("mark", {"number": 1}), ("claim", {"type": "full_house"})],
    "roulette": [("place_bet", {"target": "red", "amount": 10}), ("spin", {})],
    "digit_guess": [("guess", {"code": "1234"})],
    "mafia": [("vote", {"targetID": "p1"}), ("eliminate", {"targetID": "p1"}),
              ("save", {"targetID": "p1"}), ("investigate", {"targetID": "p1"})],
    "raja_mantri": [("accuse", {"targetID": "p1"})],
    "trivia": [("answer", {"choiceIndex": 0, "questionID": "q1"})],
    "heist": [("set_cameras", {"cameras": ["cam_tl"]}), ("move", {"direction": "right"})],
    "stock_panic": [("trade", {"stock": "AAPL", "action": "buy"})],
    "mind_meld": [("word", {"word": "red"})],
    "hot_grid": [("pick_tile", {"index": 0})],
    "speed_sculptor": [("drawing", {"lines": [[{"x": 0.1, "y": 0.1}]]})],
}

ALL_GAMES = sorted(ENGINES)


class TestRegistry:
    def test_every_engine_declares_its_own_id(self):
        for gid, cls in ENGINES.items():
            assert cls.game_id == gid

    def test_unknown_ids_fall_back_to_the_placeholder(self):
        # Lets an id the Swift app knows about still be startable end to end.
        assert engine_for("not_a_game") is PlaceholderEngine
        assert engine_for("some_future_game") is PlaceholderEngine

    def test_every_legacy_game_id_now_has_a_real_engine(self):
        # The 17 "legacy" GameID cases used to all fall back to the
        # placeholder; this is the regression guard for that rollout.
        legacy_ids = {
            "trivia", "poker", "tambola", "mafia", "heist", "stock_panic",
            "mind_meld", "hot_grid", "speed_sculptor", "pong", "connect4",
            "chess", "snake_ladder", "roulette", "raja_mantri", "memory",
            "digit_guess",
        }
        for gid in legacy_ids:
            assert engine_for(gid) is not PlaceholderEngine, gid

    def test_player_bounds_are_sane(self):
        for gid, cls in ENGINES.items():
            assert 1 <= cls.min_players <= cls.max_players, gid

    def test_all_engines_implement_the_contract(self):
        for cls in ENGINES.values():
            assert issubclass(cls, NativeGameEngine)


@pytest.mark.parametrize("game_id", ALL_GAMES)
class TestPlayLoop:
    def test_drives_to_completion_without_raising(self, game_id):
        engine, roster = make(game_id)
        for _ in range(60):
            for i, player in enumerate(roster):
                for verb, data in ACTIONS.get(game_id, []):
                    payload = dict(data)
                    if "targetID" in payload:
                        payload["targetID"] = roster[(i + 1) % len(roster)].id
                    engine.handle_action(player.id, verb, payload)
            engine.tick(0.2)
            if engine.is_over():
                break
        assert isinstance(engine.results(), list)

    def test_state_is_json_serialisable(self, game_id):
        # Anything that cannot be serialised never reaches a client.
        engine, roster = make(game_id)
        json.dumps(engine.public_state())
        for player in roster:
            json.dumps(engine.private_state(player.id))

    def test_every_player_gets_a_non_empty_private_state(self, game_id):
        # The phone leaves its waiting screen on the first private_state it
        # receives, not on game_started -- an empty dict would strand it there.
        engine, roster = make(game_id)
        for player in roster:
            state = engine.private_state(player.id)
            assert isinstance(state, dict) and state, game_id

    def test_results_rows_have_the_expected_shape(self, game_id):
        engine, _ = make(game_id)
        for row in engine.results():
            assert {"playerID", "name", "score", "rank"} <= set(row)

    def test_ignores_junk_actions(self, game_id):
        engine, roster = make(game_id)
        for verb in ("not_a_verb", "tap", "move"):
            engine.handle_action(roster[0].id, verb, {"garbage": object()})
            engine.handle_action("ghost-player", verb, {})

    def test_survives_a_player_leaving(self, game_id):
        engine, roster = make(game_id)
        engine.on_player_leave(roster[-1].id)
        engine.tick(0.2)
        json.dumps(engine.public_state())


class TestPrivacy:
    """A secret must never appear in public_state."""

    def test_cipher_grid_key_is_spymaster_only(self):
        engine, roster = make("cipher_grid", players=4)
        assert "key" not in engine.public_state()
        spymasters = [p.id for p in roster
                      if engine.spymasters.get(engine.teams.get(p.id)) == p.id]
        others = [p.id for p in roster if p.id not in spymasters]
        assert len(engine.private_state(spymasters[0])["key"]) == 25
        assert engine.private_state(others[0])["key"] == []

    def test_spy_is_never_told_the_location(self):
        engine, roster = make("odd_one_out", players=5)
        assert engine.public_state()["location"] is None
        assert engine.private_state(engine.spy)["location"] is None
        innocent = next(p.id for p in roster if p.id != engine.spy)
        assert engine.private_state(innocent)["location"] == engine.location

    def test_bluff_it_truth_hidden_while_lies_are_written(self):
        engine, roster = make("bluff_it")
        assert engine.public_state()["truth"] is None
        for player in roster:
            blob = json.dumps(engine.private_state(player.id)).lower()
            assert engine.truth.lower() not in blob

    def test_wavelength_target_is_psychic_only(self):
        engine, roster = make("wavelength")
        assert engine.public_state()["target"] is None
        assert engine.private_state(engine.psychic)["target"] == engine.target
        guesser = next(p.id for p in roster if p.id != engine.psychic)
        assert engine.private_state(guesser)["target"] is None

    def test_kbc_answer_withheld_until_reveal(self):
        # The TV highlights correctIndex the moment the key is present.
        engine, _ = make("kbc")
        assert engine.public_state()["correctIndex"] is None

    def test_teen_patti_blind_players_are_not_sent_their_cards(self):
        engine, roster = make("teen_patti")
        assert engine.public_state()["showdown"] == []
        assert engine.private_state(roster[0].id)["cards"] == []
        actor = engine.current_player_id()
        engine.handle_action(actor, "see", {})
        assert len(engine.private_state(actor)["cards"]) == 3

    def test_teen_patti_never_reveals_another_hand(self):
        engine, roster = make("teen_patti")
        actor = engine.current_player_id()
        engine.handle_action(actor, "see", {})
        mine = json.dumps(engine.private_state(actor))
        for player in roster:
            if player.id != actor:
                assert json.dumps(engine.hands[player.id]) not in mine

    def test_battleship_fleets_stay_private(self):
        engine, roster = make("battleship", players=2)
        assert "ships" not in json.dumps(engine.public_state()).lower()
        mine = engine.private_state(roster[0].id)
        assert mine["myShips"] == engine.fleets[roster[0].id]
        assert "myShips" in mine and engine.fleets[roster[1].id] != mine["myShips"]

    def test_defuse_splits_the_bomb_from_the_manual(self):
        engine, roster = make("defuse", players=3)
        public = engine.public_state()
        assert "answer" not in public["module"]
        assert "manual" not in public["module"]

        defuser = engine.private_state(engine.defuser)
        assert defuser["manual"] == []          # sees the bomb, not the book
        helper_id = next(p.id for p in roster if p.id != engine.defuser)
        helper = engine.private_state(helper_id)
        assert helper["manual"] and helper["module"] == {}

        for player in roster:
            assert "answer" not in json.dumps(engine.private_state(player.id))

    def test_defuse_module_variants_stay_answer_free(self):
        engine, _ = make("defuse", players=3)
        for index, _ in enumerate(engine.modules):
            engine.module_index = index
            assert "answer" not in engine.public_state()["module"]

    def test_emoji_movie_titles_are_per_player(self):
        engine, roster = make("emoji_movie")
        assert engine.public_state()["entries"] == []
        mine = engine.private_state(roster[0].id)
        assert mine["myTitle"] == engine.assignments[roster[0].id]
        blob = json.dumps(mine).lower()
        for player in roster[1:]:
            other = engine.assignments[player.id]
            if other != mine["myTitle"]:
                assert other.lower() not in blob

    def test_charades_title_is_actor_only(self):
        engine, roster = make("bollywood_charades")
        assert engine.public_state()["title"] is None
        assert engine.private_state(engine.actor)["title"] == engine.title
        guesser = next(p.id for p in roster if p.id != engine.actor)
        assert engine.private_state(guesser)["title"] is None

    def test_heist_escape_map_is_split_not_shared(self):
        engine, roster = make("heist_escape", players=3)
        assert "walls" not in json.dumps(engine.public_state()).lower()
        sizes = [len(engine.private_state(p.id)["myWalls"]) for p in roster]
        assert all(size < len(engine.walls) for size in sizes)
        assert sum(sizes) == len(engine.walls)

    def test_simon_sequence_hidden_while_being_tested(self):
        engine, _ = make("simon_says", players=2)
        engine.phase = "input"
        assert engine.public_state()["sequence"] == []
        engine.phase = "show"
        assert engine.public_state()["sequence"]


class TestGameRules:
    def test_heist_escape_maze_is_always_solvable(self):
        # Walls are added only where they cannot block the carved solution.
        for seed in range(20):
            engine, _ = make("heist_escape", players=2, seed=seed)
            path = engine.path
            assert path[0] == 0 and path[-1] == engine.exit_cell
            for a, b in zip(path, path[1:]):
                assert (min(a, b), max(a, b)) not in engine.walls

    def test_last_tap_never_eliminates_everyone(self):
        engine, roster = make("last_tap", players=5)
        engine.phase = "go"
        for player in roster:
            engine.handle_action(player.id, "tap", {})
        engine._resolve()
        assert len(engine.alive) >= 1

    def test_teen_patti_ranks_a_trail_above_a_pair(self):
        engine, _ = make("teen_patti", players=2)
        trail = [{"rank": 9, "suit": s} for s in ("♠", "♥", "♦")]
        pair = [{"rank": 9, "suit": "♠"}, {"rank": 9, "suit": "♥"},
                {"rank": 4, "suit": "♦"}]
        assert engine._hand_rank(trail) > engine._hand_rank(pair)

    def test_teen_patti_pure_sequence_beats_a_plain_sequence(self):
        engine, _ = make("teen_patti", players=2)
        pure = [{"rank": r, "suit": "♠"} for r in (5, 6, 7)]
        plain = [{"rank": 5, "suit": "♠"}, {"rank": 6, "suit": "♥"},
                 {"rank": 7, "suit": "♦"}]
        assert engine._hand_rank(pure) > engine._hand_rank(plain)

    def test_cipher_grid_assassin_hands_the_win_to_the_other_team(self):
        engine, _ = make("cipher_grid", players=4)
        assassin = engine.key.index("assassin")
        engine.turn = "red"
        engine._reveal(assassin, "red")
        assert engine.is_over() and engine.winner == "blue"

    def test_npat_scores_unique_answers_higher(self):
        engine, roster = make("npat", players=3)
        letter = engine.letter.lower()
        shared = {f: letter + "same" for f in ["name", "place", "animal", "thing"]}
        engine.submissions[roster[0].id] = dict(shared)
        engine.submissions[roster[1].id] = dict(shared)
        engine.submissions[roster[2].id] = {f: letter + "uniq"
                                            for f in ["name", "place", "animal", "thing"]}
        engine._score()
        assert engine.scores[roster[2].id] > engine.scores[roster[0].id]

    def test_antakshari_chains_to_the_last_letter(self):
        engine, roster = make("antakshari", players=2)
        song = engine.letter + "melody"
        engine.handle_action(roster[0].id, "submit_song", {"song": song})
        engine._score()
        assert engine.letter == song[-1].upper()

    def test_antakshari_rejects_a_wrong_starting_letter(self):
        engine, roster = make("antakshari", players=2)
        wrong = "Z" if engine.letter != "Z" else "A"
        engine.handle_action(roster[0].id, "submit_song", {"song": wrong + "song"})
        assert roster[0].id not in engine.submissions

    def test_sealed_auction_cannot_bid_beyond_budget(self):
        engine, roster = make("sealed_auction", players=3)
        engine.handle_action(roster[0].id, "bid", {"amount": 10_000})
        assert roster[0].id not in engine.submissions

    def test_atlas_rejects_reused_and_mismatched_places(self):
        engine, roster = make("atlas", players=2)
        actor = engine.current_player()
        engine.letter = "N"
        engine.handle_action(actor, "answer", {"place": "Agra"})   # wrong letter
        assert len(engine.chain) == 1
        engine.handle_action(actor, "answer", {"place": "Nepal"})
        assert len(engine.chain) == 2
        engine.letter = "N"
        engine.handle_action(engine.current_player(), "answer", {"place": "Nepal"})
        assert len(engine.chain) == 2                              # already used

    def test_twenty48_merges_equal_tiles(self):
        engine, roster = make("twenty48", players=1)
        board = engine.boards[roster[0].id]
        board[:] = [0] * 16
        board[0] = board[1] = 2
        engine.handle_action(roster[0].id, "swipe", {"direction": "left"})
        assert 4 in engine.boards[roster[0].id]
        assert engine.scores[roster[0].id] >= 4

    def test_twenty48_tile_identity_survives_a_slide(self):
        # Reported as "blocky, not smooth": the client can only animate a
        # slide if it can tell a tile that moved from one that merely changed
        # value in place, which means the id at a tile's new cell has to be
        # the same id it had before the swipe.
        engine, roster = make("twenty48", players=1)
        pid = roster[0].id
        board = engine.boards[pid]
        board[:] = [0] * 16
        board[3] = 2                                  # one tile, far column
        ids = engine.tile_ids[pid]
        ids[:] = [0] * 16
        ids[3] = 7

        engine.handle_action(pid, "swipe", {"direction": "left"})

        assert engine.boards[pid][0] == 2
        assert engine.tile_ids[pid][0] == 7            # same id, new cell
        entities = engine.public_state()["boards"][0]["tiles"]
        slid = next(t for t in entities if t["id"] == 7)
        assert slid == {"id": 7, "value": 2, "row": 0, "col": 0}
        # The swipe also spawns a tile (the board wasn't full); that's a
        # second entity with a brand new id, not a mutation of tile 7.
        assert len(entities) == 2

    def test_twenty48_merge_reports_the_surviving_id_and_spawn(self):
        engine, roster = make("twenty48", players=1)
        pid = roster[0].id
        board = engine.boards[pid]
        board[:] = [0] * 16
        board[0], board[1] = 2, 2
        ids = engine.tile_ids[pid]
        ids[:] = [0] * 16
        ids[0], ids[1] = 5, 9

        engine.handle_action(pid, "swipe", {"direction": "left"})

        state = engine.public_state()["boards"][0]
        merged_tile = next(t for t in state["tiles"] if t["col"] == 0)
        assert merged_tile == {"id": 5, "value": 4, "row": 0, "col": 0}
        assert state["merged"] == [5]
        # The swipe also spawns a fresh tile; it must carry its own new id,
        # distinct from every id already on the board.
        spawned = next(t for t in state["tiles"] if t["id"] != 5)
        assert state["spawned"] == spawned["id"]
        assert spawned["id"] not in (5, 9)

    def test_twenty48_ids_stay_unique_and_stable_across_several_swipes(self):
        engine, roster = make("twenty48", players=1)
        pid = roster[0].id
        for direction in ("left", "up", "right", "down") * 3:
            engine.handle_action(pid, "swipe", {"direction": direction})
            tiles = engine.public_state()["boards"][0]["tiles"]
            ids = [t["id"] for t in tiles]
            assert len(ids) == len(set(ids))            # every id is unique
            assert all(isinstance(i, int) and i > 0 for i in ids)

    def test_brick_breaker_launches_itself_with_no_serve_action(self):
        # Reported as "no dropping blocks or something moving": worth pinning
        # down that nothing has to be *sent* for the ball to start moving --
        # the only gate is the ready-set-go pause, which the pump waits out.
        engine, _ = make("brick_breaker", players=1)
        assert engine.public_state()["serving"] is True

        engine.serve_at = 0.0                       # skip the pre-launch pause
        before = engine.public_state()["ball"]
        engine.tick(1 / 30)
        after = engine.public_state()["ball"]

        assert engine.public_state()["serving"] is False
        assert (after["x"], after["y"]) != (before["x"], before["y"])
        assert after["y"] < before["y"]             # launched upward

    def test_brick_breaker_arena_is_landscape_and_fully_described(self):
        # The TV draws the arena purely from these; a portrait arena is what
        # left an Apple TV screen mostly black.
        engine, _ = make("brick_breaker", players=1)
        state = engine.public_state()
        assert state["width"] > state["height"]
        for key in ("ballR", "paddleY", "paddleHeight", "paddleWidth", "rows"):
            assert key in state, key
        assert len(state["bricks"]) == engine.COLS * engine.ROWS
        assert {b["row"] for b in state["bricks"]} == set(range(engine.ROWS))

    def test_brick_breaker_ball_stays_inside_the_walls(self):
        engine, _ = make("brick_breaker", players=1)
        engine.serve_at = 0.0
        for _ in range(400):
            engine.tick(1 / 30)
            engine.serve_at = 0.0                   # never wait out a re-serve
            ball = engine.public_state()["ball"]
            assert -0.01 <= ball["x"] <= engine.W + 0.01
            assert ball["y"] >= -0.01               # only the floor is an exit

    def test_brick_breaker_paddle_action_clamps_to_the_arena(self):
        engine, roster = make("brick_breaker", players=1)
        engine.handle_action(roster[0].id, "paddle", {"x": 9999})
        assert engine.paddle == engine.W - engine.PADDLE_W / 2
        engine.handle_action(roster[0].id, "paddle", {"x": -9999})
        assert engine.paddle == engine.PADDLE_W / 2
        engine.handle_action(roster[0].id, "paddle", {"x": "left"})
        assert engine.paddle == engine.PADDLE_W / 2      # junk ignored, not raised

    def test_brick_breaker_clearing_the_wall_wins(self):
        engine, _ = make("brick_breaker", players=1)
        for brick in engine.bricks[:-1]:
            brick["alive"] = False
        last = engine.bricks[-1]
        engine.serving = False
        engine.serve_at = 0.0
        engine.bx = last["x"] + last["w"] / 2
        engine.by = last["y"] + last["h"] / 2
        engine.vx, engine.vy = 0.0, -1.0
        engine.tick(1 / 30)
        assert engine.is_over() and engine.public_state()["won"] is True

    def test_roulette_accepts_straight_up_number_bets(self):
        # Reported directly: "players betting on the board doesn't show up
        # as the placed chips on the numbers" -- there was no way to bet on
        # a single number at all, only the 9 outside bets (red/black/etc),
        # so a number could never carry a bet to display in the first place.
        engine, roster = make("roulette", players=1)
        pid = roster[0].id
        engine.handle_action(pid, "place_bet", {"target": "17", "amount": 10})
        assert engine.bets[pid].get("17") == 10
        assert engine.chips[pid] == engine.STARTING_CHIPS - 10

        # Junk targets are still rejected, same as before.
        engine.handle_action(pid, "place_bet", {"target": "37", "amount": 10})
        engine.handle_action(pid, "place_bet", {"target": "-1", "amount": 10})
        engine.handle_action(pid, "place_bet", {"target": "red7", "amount": 10})
        assert set(engine.bets[pid]) == {"17"}

    def test_roulette_straight_up_bet_pays_36x_on_a_hit(self):
        engine, roster = make("roulette", players=1)
        pid = roster[0].id
        engine.handle_action(pid, "place_bet", {"target": "17", "amount": 10})
        before = engine.chips[pid]
        engine.handle_action(pid, "spin", {})
        engine.pending_result = 17          # force the winning number
        engine.spin_deadline = 0.0
        engine.tick(1 / 30)
        assert engine.last_result == 17
        assert engine.chips[pid] == before + 10 * 36

    def test_roulette_bool_amount_is_not_a_valid_bet(self):
        # isinstance(True, int) is True in Python -- a bare isinstance(amount,
        # int) check would have silently accepted a bool as a bet amount.
        engine, roster = make("roulette", players=1)
        pid = roster[0].id
        engine.handle_action(pid, "place_bet", {"target": "red", "amount": True})
        assert engine.bets[pid] == {}
        assert engine.chips[pid] == engine.STARTING_CHIPS

    def test_roulette_publishes_bets_aggregated_by_target(self):
        # The TV draws chip stacks per cell from this; it must be a total
        # across every player's bet on that cell, not per-player.
        engine, roster = make("roulette", players=2)
        engine.handle_action(roster[0].id, "place_bet", {"target": "red", "amount": 10})
        engine.handle_action(roster[1].id, "place_bet", {"target": "red", "amount": 15})
        engine.handle_action(roster[1].id, "place_bet", {"target": "17", "amount": 5})
        by_target = engine.public_state()["betsByTarget"]
        assert by_target["red"] == 25
        assert by_target["17"] == 5

    def test_battleship_hit_keeps_the_turn(self):
        engine, roster = make("battleship", players=2)
        shooter = engine.current_player_id()
        target = next(p for p in engine.order if p != shooter)
        cell = engine.fleets[target][0][0]
        engine.handle_action(shooter, "fire", {"cell": cell})
        assert engine.current_player_id() == shooter

    def test_battleship_cannot_fire_out_of_turn(self):
        engine, _ = make("battleship", players=2)
        waiting = next(p for p in engine.order if p != engine.current_player_id())
        engine.handle_action(waiting, "fire", {"cell": 0})
        assert engine.shots[waiting] == {}


class TestSnakeLadder:
    """Board layout + movement rules for the native Snake & Ladder engine.

    Regression coverage for two changes: SNAKES was trimmed from 10 entries
    to exactly 3 (the TV board renders each as a full 3D serpentine model,
    so fewer/more-prominent snakes reads better cinematically), and
    public_state() now exposes the static snakes/ladders maps so the Swift
    client has one authoritative source for the board layout.
    """

    def test_exactly_three_snakes(self):
        from games.native_hub.engines.legacy_boards import SNAKES
        assert len(SNAKES) == 3
        for head, tail in SNAKES.items():
            assert 1 <= tail < head <= 100

    def test_ladders_unchanged_at_ten(self):
        from games.native_hub.engines.legacy_boards import LADDERS
        assert len(LADDERS) == 10
        for bottom, top in LADDERS.items():
            assert 1 <= bottom < top <= 100

    def test_public_state_exposes_snakes_and_ladders_maps(self):
        from games.native_hub.engines.legacy_boards import LADDERS, SNAKES
        engine, _ = make("snake_ladder", players=2)
        state = engine.public_state()
        assert state["snakes"] == {str(h): t for h, t in SNAKES.items()}
        assert state["ladders"] == {str(b): t for b, t in LADDERS.items()}
        # JSON object keys must be strings -- guard against a regression
        # back to int keys, which `json.dumps` would silently stringify
        # anyway but which would not round-trip equal to the raw dict.
        assert all(isinstance(k, str) for k in state["snakes"])
        assert all(isinstance(k, str) for k in state["ladders"])

    def test_landing_on_a_snake_head_slides_down_to_its_tail(self):
        from games.native_hub.engines.legacy_boards import SNAKES
        head = next(iter(SNAKES))
        tail = SNAKES[head]
        engine, roster = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = head - 4
        engine.handle_action(pid, "roll", {"value": 4})
        assert engine.positions[pid] == tail

    def test_landing_on_a_ladder_bottom_climbs_to_its_top(self):
        from games.native_hub.engines.legacy_boards import LADDERS
        bottom = next(iter(LADDERS))
        top = LADDERS[bottom]
        engine, roster = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = bottom - 3
        engine.handle_action(pid, "roll", {"value": 3})
        assert engine.positions[pid] == top

    def test_overshooting_100_stays_put(self):
        engine, roster = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = 98
        engine.handle_action(pid, "roll", {"value": 5})
        assert engine.positions[pid] == 98

    def test_landing_exactly_on_100_wins(self):
        engine, roster = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = 94
        engine.handle_action(pid, "roll", {"value": 6})
        assert engine.positions[pid] == 100
        assert engine.is_over()
        assert engine.winner == pid

    def test_snake_bite_records_last_slide_event(self):
        # The TV drives its bite cinematic (and the controller its haptic)
        # off this event rather than re-inferring the slide.
        from games.native_hub.engines.legacy_boards import SNAKES
        head = next(iter(SNAKES))
        tail = SNAKES[head]
        engine, _ = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = head - 4
        engine.handle_action(pid, "roll", {"value": 4})
        slide = engine.public_state()["lastSlide"][pid]
        assert slide["kind"] == "snake"
        assert slide["from"] == head
        assert slide["to"] == tail
        assert isinstance(slide["seq"], int) and slide["seq"] >= 1
        # The rolling player's private state carries their own event; other
        # players get it in public state only, never in private state.
        assert engine.private_state(pid)["lastSlide"] == slide
        other = next(p for p in engine.order if p != pid)
        assert engine.private_state(other)["lastSlide"] is None
        assert other not in engine.public_state()["lastSlide"]

    def test_ladder_climb_records_last_slide_event(self):
        from games.native_hub.engines.legacy_boards import LADDERS
        assert LADDERS[28] == 84
        engine, _ = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = 25
        engine.handle_action(pid, "roll", {"value": 3})
        slide = engine.public_state()["lastSlide"][pid]
        assert slide["kind"] == "ladder"
        assert slide["from"] == 28
        assert slide["to"] == 84
        assert isinstance(slide["seq"], int) and slide["seq"] >= 1

    def test_slide_seq_increases_across_slides(self):
        from games.native_hub.engines.legacy_boards import LADDERS, SNAKES
        assert SNAKES[89] == 53 and LADDERS[28] == 84
        engine, _ = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = 85
        engine.handle_action(pid, "roll", {"value": 4})
        first = engine.public_state()["lastSlide"][pid]["seq"]
        engine.turn_index = engine.order.index(pid)   # force the turn back
        engine.positions[pid] = 25
        engine.handle_action(pid, "roll", {"value": 3})
        second = engine.public_state()["lastSlide"][pid]["seq"]
        assert second > first

    def test_plain_move_clears_stale_slide_event(self):
        # A late joiner must never replay an old slide cinematic.
        from games.native_hub.engines.legacy_boards import SNAKES
        head = next(iter(SNAKES))
        engine, _ = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = head - 4
        engine.handle_action(pid, "roll", {"value": 4})
        assert engine.public_state()["lastSlide"][pid]["kind"] == "snake"
        engine.turn_index = engine.order.index(pid)   # force the turn back
        engine.positions[pid] = 40                    # 41..46: no snake/ladder
        engine.handle_action(pid, "roll", {"value": 1})
        assert pid not in engine.public_state()["lastSlide"]
        assert engine.private_state(pid)["lastSlide"] is None

    def test_overshoot_records_no_slide_event(self):
        engine, _ = make("snake_ladder", players=2)
        pid = engine.current_player_id()
        engine.positions[pid] = 98
        engine.handle_action(pid, "roll", {"value": 5})
        assert engine.positions[pid] == 98
        assert pid not in engine.public_state()["lastSlide"]


class TestTrivia:
    @staticmethod
    def _to(engine, phase, limit=200):
        for _ in range(limit):
            if engine.phase == phase:
                return
            engine.deadline = 0.0
            engine.tick(1 / 30)
        raise AssertionError(f"never reached {phase}")

    def test_trivia_plays_nine_questions_in_three_rounds(self):
        engine, _ = make("trivia", players=2)
        assert engine.total_rounds == engine.MAIN_QUESTIONS == 9
        assert engine.total_round_groups == 3

    def test_trivia_hides_the_correct_answer_until_reveal(self):
        # correctIndex used to be sent on every single push, including the
        # very first one for a brand new question -- the TV painted the
        # correct choice green before anyone had answered. Reported
        # directly as "answers are getting revealed way before the
        # questions."
        engine, _ = make("trivia", players=2)
        self._to(engine, "question")
        assert "correctIndex" not in engine.public_state()

        engine.deadline = 0.0             # force the round timer to expire
        engine.tick(1 / 30)
        assert engine.phase == "reveal"
        assert "correctIndex" in engine.public_state()

    def test_trivia_holds_the_reveal_before_advancing(self):
        engine, _ = make("trivia", players=2)
        self._to(engine, "question")
        first_question_id = engine.question_id
        engine.deadline = 0.0
        engine.tick(1 / 30)
        assert engine.phase == "reveal"

        # The reveal deadline is still in the future -- ticking again
        # shouldn't jump straight to the next question.
        engine.tick(1 / 30)
        assert engine.phase == "reveal"
        assert engine.question_id == first_question_id

        self._to(engine, "question")
        assert engine.question_id != first_question_id
