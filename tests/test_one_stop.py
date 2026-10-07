"""One-stop features: Game Night, smart picker, profiles, Daily Brain
Challenge scores and AI-made decks."""

import datetime as dt

import pytest

from app import create_app
from games import ai_decks, daily, game_night, llm_json, profiles
from utils.room_manager import RoomRegistry, RoomState, rooms

NS = "/native"


# --------------------------------------------------------------------------
# smart picker / playlist
# --------------------------------------------------------------------------

def test_picker_only_offers_games_that_fit_the_group():
    for g in game_night.pick_games(4):
        assert g["minPlayers"] <= 4 <= g["maxPlayers"]
    ids = {g["id"] for g in game_night.pick_games(12)}
    assert "chess" not in ids and "most_likely_to" in ids


def test_picker_kids_mode_drops_casino_and_mafia():
    ids = {g["id"] for g in game_night.pick_games(6, kids=True)}
    assert not ids & {"poker", "teen_patti", "roulette", "mafia"}


def test_picker_respects_minutes():
    assert all(g["minutes"] <= 8 for g in game_night.pick_games(4, minutes=8))


def test_playlist_is_varied_and_fits():
    import random
    playlist = game_night.build_playlist(5, kids=True, total_minutes=45,
                                         rng=random.Random(1))
    assert 2 <= len(playlist) <= 8
    assert len(set(playlist)) == len(playlist)
    picked = {g["id"] for g in game_night.pick_games(5, kids=True)}
    assert set(playlist) <= picked


# --------------------------------------------------------------------------
# night scoring
# --------------------------------------------------------------------------

def make_room(game_id="trivia", ids=("a", "b", "c")):
    room = RoomRegistry().create(game_id)
    for pid in ids:
        room.add_player(pid, pid.upper(), f"s-{pid}")
    return room


def results(*order):
    return [{"playerID": pid, "name": pid.upper(), "score": 10 - i, "rank": i + 1}
            for i, pid in enumerate(order)]


def test_night_points_and_champion():
    room = make_room()
    game_night.start(room, ["trivia", "herd"])
    game_night.record_game(room, results("a", "b", "c"))
    assert game_night.advance(room) == "herd" and room.game_id == "herd"
    game_night.record_game(room, results("c", "a", "b"))
    assert game_night.advance(room) is None
    table = game_night.standings(room)
    assert [r["playerID"] for r in table] == ["a", "c", "b"]
    assert table[0]["points"] == 10 + 7
    assert room.to_json()["night"]["finished"] is True


def test_room_json_has_no_night_outside_game_night():
    assert make_room().to_json()["night"] is None


# --------------------------------------------------------------------------
# socket flow
# --------------------------------------------------------------------------

@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


def test_game_night_over_sockets(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
            namespace=NS)
    code = latest(tv, "room_updated")["code"]
    for i in range(3):
        phone = socketio.test_client(app, namespace=NS)
        phone.emit("join_room", {"roomCode": code, "playerName": f"P{i}",
                                 "playerID": f"dev-{i}", "isTV": False}, namespace=NS)
    tv.get_received(NS)

    tv.emit("start_night", {"roomCode": code, "playlist": ["trivia", "herd", "nope"]},
            namespace=NS)
    night = latest(tv, "room_updated")["night"]
    assert night["playlist"] == ["trivia", "herd"] and night["current"] == "trivia"

    room = rooms.get(code)
    with room.lock:
        room.state = RoomState.RESULTS
        game_night.record_game(room, results("dev-0", "dev-1", "dev-2"))
    tv.emit("next_game", {"roomCode": code}, namespace=NS)
    upd = latest(tv, "room_updated")
    assert upd["gameID"] == "herd" and upd["state"] == "lobby"
    assert upd["night"]["standings"][0]["playerID"] == "dev-0"

    with room.lock:
        room.state = RoomState.RESULTS
    tv.emit("next_game", {"roomCode": code}, namespace=NS)
    assert latest(tv, "room_updated")["night"]["finished"] is True
    assert profiles.get("dev-0")["stats"]["nights"] == 1
    assert profiles.get("dev-0")["stats"]["nightWins"] == 1


def test_only_host_or_tv_can_run_the_night(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
            namespace=NS)
    code = latest(tv, "room_updated")["code"]
    host = socketio.test_client(app, namespace=NS)
    host.emit("join_room", {"roomCode": code, "playerName": "H", "playerID": "dev-h",
                            "isTV": False}, namespace=NS)
    guest = socketio.test_client(app, namespace=NS)
    guest.emit("join_room", {"roomCode": code, "playerName": "G", "playerID": "dev-g",
                             "isTV": False}, namespace=NS)
    guest.get_received(NS)
    guest.emit("start_night", {"roomCode": code}, namespace=NS)
    assert latest(guest, "error")["code"] == "NOT_HOST"
    assert rooms.get(code).night is None


def test_custom_questions_reach_the_room(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
            namespace=NS)
    code = latest(tv, "room_updated")["code"]
    good = {"question": "Who is our family's best cook?",
            "options": ["Amma", "Nanna", "Ravi", "Sita"], "correct_answer": 0}
    tv.emit("set_custom_questions", {"roomCode": code, "questions": [good, {"bad": 1}]},
            namespace=NS)
    assert rooms.get(code).seed_questions == [good]


# --------------------------------------------------------------------------
# profiles
# --------------------------------------------------------------------------

def test_profile_update_is_validated():
    p = profiles.update("device-1", {"name": "  Teja   M ", "color": "teal",
                                     "avatar": "star.fill"})
    assert (p["name"], p["color"], p["avatar"]) == ("Teja M", "teal", "star.fill")
    p = profiles.update("device-1", {"color": "neon-hotpink", "avatar": "../../etc"})
    assert (p["color"], p["avatar"]) == ("teal", "star.fill")


def test_finished_games_build_stats_and_friends():
    room = make_room(ids=("d-a", "d-b", "bot-1"))
    room.players[2].is_bot = True
    profiles.record_results("trivia", results("d-a", "d-b", "bot-1"), room.players)
    profiles.record_results("trivia", results("d-b", "d-a", "bot-1"), room.players)
    a = profiles.get("d-a")
    assert a["stats"]["played"] == 2 and a["stats"]["wins"] == 1
    assert a["stats"]["byGame"]["trivia"] == {"played": 2, "wins": 1, "best": 10}
    assert a["friends"] == ["d-b"]
    assert profiles.get("bot-1")["stats"]["played"] == 0


def test_profile_http(server):
    app, _ = server
    client = app.test_client()
    assert client.get("/api/profile/x").status_code == 400
    client.put("/api/profile/device-9", json={"name": "Asha"})
    assert client.get("/api/profile/device-9").get_json()["profile"]["name"] == "Asha"


# --------------------------------------------------------------------------
# daily challenge
# --------------------------------------------------------------------------

def test_daily_scores_rank_and_dedupe():
    today = dt.date.today().isoformat()
    assert daily.submit("device-1", "A", today, 4, 50)
    assert not daily.submit("device-1", "A", today, 5, 10)      # one try a day
    assert daily.submit("device-2", "B", today, 4, 40)
    assert daily.submit("device-3", "C", today, 5, 90)
    board = daily.leaderboard(today)["everyone"]
    assert [r["device"] for r in board] == ["device-3", "device-2", "device-1"]


def test_daily_rejects_bad_input():
    today = dt.date.today().isoformat()
    assert not daily.submit("device-1", "A", "2001-01-01", 3, 10)
    assert not daily.submit("device-1", "A", today, 9, 10)
    assert not daily.submit("x", "A", today, 3, 10)


def test_daily_friends_board():
    room = make_room(ids=("dev-x", "dev-y"))
    profiles.record_results("herd", results("dev-x", "dev-y"), room.players)
    today = dt.date.today().isoformat()
    daily.submit("dev-x", "X", today, 3, 30)
    daily.submit("dev-y", "Y", today, 4, 30)
    daily.submit("dev-stranger", "S", today, 5, 30)
    friends = daily.leaderboard(today, "dev-x")["friends"]
    assert [r["device"] for r in friends] == ["dev-y", "dev-x"]


# --------------------------------------------------------------------------
# AI decks
# --------------------------------------------------------------------------

def test_decks_validate_and_cache(monkeypatch):
    calls = []

    def fake(prompt, system=None):
        calls.append(prompt)
        return (["Shah Rukh Khan", "Biryani", "x" * 60, "Biryani", "Charminar"], "openai")
    monkeypatch.setattr(llm_json, "json_items", fake)
    items, source = ai_decks.generate("headsup", "Hyderabad", 3)
    assert source == "openai" and items == ["Shah Rukh Khan", "Biryani", "Charminar"]
    again, source = ai_decks.generate("headsup", "hyderabad", 3)
    assert source == "cache" and again == items and len(calls) == 1


def test_decks_quiz_items_use_the_trivia_shape(monkeypatch):
    good = {"question": "Which city is famous for Charminar?",
            "options": ["Hyderabad", "Delhi", "Pune", "Agra"], "correct_answer": 0}
    monkeypatch.setattr(llm_json, "json_items",
                        lambda p, system=None: ([good, {"question": "bad"}], "openai"))
    items, _ = ai_decks.generate("quiz", "India", 5)
    assert items == [good]


def test_decks_prompt_carries_safety_and_language():
    prompt = ai_decks.build_prompt("truth", "college days", 10, True, "te")
    assert "family-friendly" in prompt and "Telugu" in prompt


def test_wyr_must_be_a_would_you_rather():
    assert ai_decks.validate("wyr", "Pizza or pasta?") is None
    assert ai_decks.validate("wyr", "Would you rather fly or swim?")


def test_decks_without_a_model_return_empty(monkeypatch):
    def boom(p, system=None):
        raise llm_json.LLMError("no key")
    monkeypatch.setattr(llm_json, "json_items", boom)
    assert ai_decks.generate("dare", "beach", 5) == ([], "none")


def test_decks_http(server, monkeypatch):
    app, _ = server
    monkeypatch.setattr(llm_json, "json_items",
                        lambda p, system=None: (["Things in a fridge"], "openai"))
    client = app.test_client()
    assert client.post("/api/decks/generate", json={"kind": "poker"}).status_code == 400
    body = client.post("/api/decks/generate",
                       json={"kind": "hotpotato", "topic": "kitchen", "count": 5}).get_json()
    assert body["items"] == ["Things in a fridge"]


def test_picker_http(server):
    app, _ = server
    body = app.test_client().get("/api/picker?players=6&kids=1&minutes=10").get_json()
    assert body["games"] and all(g["kids"] for g in body["games"])


# --------------------------------------------------------------------------
# Kids mode = learning mode
# --------------------------------------------------------------------------

def test_kids_mode_is_learning_games_only():
    ids = {g["id"] for g in game_night.pick_games(4, kids=True)}
    assert ids, "kids mode must still offer games"
    assert ids <= {"trivia", "kbc", "brain_battle", "npat", "cipher_grid", "connect4",
                   "snake_ladder", "memory", "hot_grid", "digit_guess", "battleship",
                   "twenty_questions"}
    assert not ids & {"most_likely_to", "bluff_it", "pong", "emoji_movie", "poker"}


def test_chess_is_not_offered():
    assert "chess" not in game_night.CATALOG


def test_kids_night_rotates_learning_topics_and_clears_them():
    room = make_room()
    game_night.start(room, ["trivia", "brain_battle"], kids=True)
    first = room.topic
    assert first in game_night.KIDS_TOPICS
    game_night.record_game(room, results("a", "b", "c"))
    game_night.advance(room)
    assert room.topic in game_night.KIDS_TOPICS and room.topic != first


def test_kids_mode_keeps_a_host_topic():
    room = make_room()
    room.topic = "Cricket"
    game_night.start(room, ["trivia"], kids=True)
    assert room.topic == "Cricket"


def test_end_night_drops_the_kids_topic(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"},
            namespace=NS)
    code = latest(tv, "room_updated")["code"]
    tv.emit("start_night", {"roomCode": code, "playlist": ["trivia"], "kids": True},
            namespace=NS)
    assert latest(tv, "room_updated")["topic"] in game_night.KIDS_TOPICS
    tv.emit("end_night", {"roomCode": code}, namespace=NS)
    assert latest(tv, "room_updated")["topic"] == ""


def test_retired_games_are_not_picked_for_a_night():
    retired = {"kbc", "pong", "memory", "hot_grid", "digit_guess", "stock_panic",
               "roulette", "air_hockey", "carrom", "blast_runners", "neon_snake",
               "twenty48", "brick_breaker", "simon_says", "story_chain", "chess"}
    assert not retired & set(game_night.CATALOG)
    for players in (2, 4, 8):
        assert not retired & {g["id"] for g in game_night.pick_games(players)}
