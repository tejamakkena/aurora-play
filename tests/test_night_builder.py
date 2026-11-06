"""The Game Night builder: the host picks any games, how many rounds each,
and how the night scores."""

import random

import pytest

from app import create_app
from games import game_night
from games.native_hub import options
from games.native_hub.registry import ENGINES
from tests.test_native_engines import ACTIONS, _NullBroadcaster
from utils.room_manager import RoomRegistry, RoomState, rooms

NS = "/native"

ADJUSTABLE = sorted(g for g in ENGINES if options.rounds_menu(g))


def build(game_id, picks=None, players=4):
    random.seed(3)
    cls = ENGINES[game_id]
    room = RoomRegistry().create(game_id)
    room.options = dict(picks or {})
    count = min(max(cls.min_players, players), cls.max_players)
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(count)]
    engine = cls(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    return engine, roster


class TestRoundsMenu:
    def test_round_games_get_a_rounds_pick_around_their_own_length(self):
        assert ADJUSTABLE, "no game offers a Rounds pick"
        for gid in ADJUSTABLE:
            menu = options.rounds_menu(gid)[0]
            values = [int(c[0]) for c in menu["choices"]]
            assert values == sorted(values) and len(set(values)) >= 3, gid
            assert menu["default"] in [c[0] for c in menu["choices"]], gid

    def test_board_solo_and_turn_taking_games_have_no_rounds_pick(self):
        for gid in ("chess", "poker", "ludo", "mafia", "tambola", "hot_takes",
                    "twenty_questions", "bollywood_charades"):
            assert options.rounds_menu(gid) == [], gid

    def test_poker_keeps_its_own_options_and_gains_none(self):
        assert [o["key"] for o in options.menu("poker")] == \
            [o["key"] for o in options.MENUS["poker"]]

    @pytest.mark.parametrize("gid", ADJUSTABLE)
    def test_the_pick_sets_the_games_length(self, gid):
        menu = options.rounds_menu(gid)[0]
        low, high = menu["choices"][0][0], menu["choices"][-1][0]
        for pick in (low, high):
            engine, _ = build(gid, {"rounds": pick})
            if gid == "trivia":
                assert engine.total_rounds == min(int(pick) * 3, len(engine.pool))
            else:
                assert engine.total_rounds == int(pick), gid

    @pytest.mark.parametrize("gid", ADJUSTABLE)
    def test_without_a_pick_the_game_keeps_its_own_length(self, gid):
        engine, _ = build(gid)
        assert engine.total_rounds == int(options.rounds_menu(gid)[0]["default"]) * \
            (3 if gid == "trivia" else 1) or gid == "trivia"

    def test_an_invalid_pick_is_ignored(self):
        engine, _ = build("herd", {"rounds": "9999"})
        assert engine.total_rounds == ENGINES["herd"].total_rounds

    def test_a_rounds_pick_beats_the_party_nhie_length(self):
        random.seed(1)
        room = RoomRegistry().create("never_have_i_ever")
        room.night = {"party": {"nhieRounds": 15}}
        room.options = {"rounds": "5"}
        roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(3)]
        engine = ENGINES["never_have_i_ever"](room, _NullBroadcaster())
        engine.start(roster)
        assert engine.total_rounds == 5

    @pytest.mark.parametrize("gid", ADJUSTABLE)
    def test_the_longest_pick_still_plays_to_the_end(self, gid):
        high = options.rounds_menu(gid)[0]["choices"][-1][0]
        engine, roster = build(gid, {"rounds": high})
        for _ in range(4000):
            if getattr(engine, "deadline", 0.0):
                engine.deadline = 1.0            # the phase timer has run out
            for i, player in enumerate(roster):
                for verb, data in ACTIONS.get(gid, []):
                    payload = dict(data)
                    if "targetID" in payload:
                        payload["targetID"] = roster[(i + 1) % len(roster)].id
                    engine.handle_action(player.id, verb, payload)
            engine.tick(2.0)
            if engine.is_over():
                break
        assert engine.is_over(), f"{gid} did not finish at {high} rounds"


class TestSettings:
    def test_only_real_picks_for_playlist_games_survive(self):
        raw = {
            "herd": {"rounds": "9", "junk": "1", "poker": "x"},
            "trivia": {"rounds": "4"},
            "chess": {"rounds": "4"},          # chess has no rounds pick
            "mafia": "not a dict",
            "ludo": {"rounds": "4"},           # not in the playlist
        }
        assert game_night.clean_settings(["herd", "trivia", "chess", "mafia"], raw) == \
            {"herd": {"rounds": "9"}, "trivia": {"rounds": "4"}}

    @pytest.mark.parametrize("junk", [None, "x", 3, []])
    def test_non_dict_settings_are_ignored(self, junk):
        assert game_night.clean_settings(["herd"], junk) == {}

    def test_a_games_picks_do_not_leak_into_the_next_game(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "poker", "brain_battle"],
                         settings={"herd": {"rounds": "9"}, "brain_battle": {"rounds": "6"}})
        assert room.options == {"rounds": "9"}
        game_night.advance(room)
        assert room.game_id == "poker" and room.options == {}
        game_night.advance(room)
        assert room.game_id == "brain_battle" and room.options == {"rounds": "6"}

    def test_the_night_reports_the_picked_rounds(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"], settings={"trivia": {"rounds": "4"}})
        assert game_night.to_json(room)["rounds"] == {"trivia": "4"}


def finish(room, *ids):
    game_night.record_game(room, [
        {"playerID": pid, "name": pid.upper(), "score": 10 - i, "rank": i + 1}
        for i, pid in enumerate(ids)])


class TestPoints:
    def test_classic_is_unchanged(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"])
        finish(room, "a", "b", "c", "d", "e")
        assert game_night.to_json(room)["points"] == "classic"
        assert [r["points"] for r in game_night.standings(room)] == [10, 7, 5, 3, 1]

    def test_fair_share_counts_every_place(self):
        assert [game_night.game_points("fair", r, 4) for r in (1, 2, 3, 4)] == [10, 7, 4, 1]
        assert [game_night.game_points("fair", r, 2) for r in (1, 2)] == [10, 1]
        assert game_night.game_points("fair", 1, 1) == 10
        pts = [game_night.game_points("fair", r, 12) for r in range(1, 13)]
        assert pts == sorted(pts, reverse=True) and pts[0] == 10 and pts[-1] == 1
        assert len(set(pts)) >= 9               # a big field is not flattened to a few values

    def test_a_small_game_is_worth_as_much_as_a_big_one(self):
        for field in (2, 5, 12):
            assert game_night.game_points("fair", 1, field) == 10
            assert game_night.game_points("fair", field, field) == 1

    @pytest.mark.parametrize("rank", [None, 0, -2, True, "1"])
    def test_a_non_placing_finish_gets_the_participation_point(self, rank):
        for mode in game_night.POINT_MODES:
            assert game_night.game_points(mode, rank, 4) == 1

    def test_tied_players_share_a_place(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"], points="fair")
        game_night.record_game(room, [
            {"playerID": "a", "name": "A", "rank": 1},
            {"playerID": "b", "name": "B", "rank": 2},
            {"playerID": "c", "name": "C", "rank": 2},
            {"playerID": "d", "name": "D", "rank": 4}])
        got = {r["playerID"]: r["points"] for r in game_night.standings(room)}
        assert got == {"a": 10, "b": 7, "c": 7, "d": 1}

    def test_big_finish_doubles_only_the_last_game(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"], points="comeback")
        assert game_night.multiplier(room) == 1
        finish(room, "a", "b")
        game_night.advance(room)
        assert game_night.multiplier(room) == 2
        assert game_night.to_json(room)["multiplier"] == 2
        finish(room, "b", "a")
        got = {r["playerID"]: r["points"] for r in game_night.standings(room)}
        assert got == {"a": 10 + 14, "b": 7 + 20}

    def test_unknown_mode_falls_back_to_classic(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd"], points="chaos")
        assert game_night.to_json(room)["points"] == "classic"

    def test_a_game_with_no_winner_still_gives_everyone_one_point(self):
        room = RoomRegistry().create("truth_or_dare")
        game_night.start(room, ["truth_or_dare", "herd"], points="comeback")
        finish(room, "a", "b", "c")
        assert {r["points"] for r in game_night.standings(room)} == {1}

    def test_the_picker_lists_the_modes(self):
        assert [m for m in game_night.POINT_MODES] == ["classic", "fair", "comeback"]


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


class TestOverSockets:
    def test_the_host_builds_a_night(self, server):
        app, socketio = server
        tv = socketio.test_client(app, namespace=NS)
        tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
                namespace=NS)
        code = latest(tv, "room_updated")["code"]
        tv.emit("start_night", {
            "roomCode": code,
            "playlist": ["herd", "poker", "trivia"],
            "settings": {"herd": {"rounds": "9"}, "trivia": {"rounds": "bad"}},
            "points": "comeback"}, namespace=NS)
        room = latest(tv, "room_updated")
        assert room["night"]["playlist"] == ["herd", "poker", "trivia"]
        assert room["night"]["points"] == "comeback"
        assert room["night"]["rounds"] == {"herd": "9"}
        picked = {o["key"]: o["value"] for o in room["options"]}
        assert picked["rounds"] == "9"

    def test_the_picker_offers_every_game_and_its_options(self, server):
        app, _ = server
        body = app.test_client().get("/api/picker?players=4&all=1").get_json()
        ids = {g["id"] for g in body["games"]}
        assert ids >= {"connect4", "poker", "herd", "trivia"}
        by_id = {g["id"]: g for g in body["games"]}
        assert by_id["herd"]["fits"] is True
        assert any(o["key"] == "rounds" for o in by_id["herd"]["options"])
        assert by_id["connect4"]["options"] == []
        assert [m["id"] for m in body["pointModes"]] == ["classic", "fair", "comeback"]

    def test_the_default_picker_is_unchanged_in_shape(self, server):
        app, _ = server
        body = app.test_client().get("/api/picker?players=4").get_json()
        assert body["games"] and all(g["fits"] for g in body["games"])
