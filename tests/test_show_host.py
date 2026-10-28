"""The Game Night show host (games/show_host.py): talk-show banter between and
inside the games, all of it fixed text the offline voice pack can carry."""

import random
import re

import pytest

from app import create_app
from games import game_night, show_host
from tests.test_native_engines import make
from utils.room_manager import RoomRegistry, rooms

NS = "/native"


def night_room(playlist=("trivia", "herd", "connect4"), players=3, kids=False, party=None):
    room = RoomRegistry().create(playlist[0])
    for i in range(players):
        room.add_player(f"p{i}", f"P{i}", f"sid{i}")
    game_night.start(room, list(playlist), kids=kids, party=party)
    return room


def moments(room):
    return [line["moment"] for line in room.host_queue]


def results(*order):
    return [{"playerID": pid, "name": pid.upper(), "score": 0, "rank": i + 1}
            for i, pid in enumerate(order)]


# ---- the script --------------------------------------------------------------

def test_every_line_can_be_prerendered():
    """Spoken lines are fixed: no names, no placeholders, no emoji, so the voice
    pack can hold every one of them."""
    for moment, lines in show_host.LINES.items():
        assert lines, moment
        for line in lines:
            assert "{" not in line and "}" not in line, line
            assert line == line.strip() and line[-1] in ".!?", line
            assert len(line) <= 140, line
            assert all(ord(ch) < 0x2000 for ch in line), line


def test_kids_mode_never_roasts():
    kids = " ".join(line for key, lines in show_host.LINES.items() if key.endswith("_kids")
                    for line in lines).lower()
    for word in ("disappointed", "embarrassing", "third grader", "rude", "apology", "wrong"):
        assert word not in kids, word
    # Moments with a roast and no gentle version simply stay quiet for kids.
    assert "last_place_kids" not in show_host.LINES and "runaway_kids" not in show_host.LINES


def test_every_moment_the_code_uses_has_lines():
    used = {m for _tag, m in show_host.INTRO_FOR_TAG} | {
        "night_open", "intro_any", "intro_kids", "last_game", "answers_none", "answers_all",
        "answers_one", "answers_most_wrong", "answers_silence", "game_won", "game_tied",
        "lead_change", "lead_kept", "close_race", "runaway", "last_place", "night_close"}
    assert used <= set(show_host.LINES)


def test_every_catalog_game_gets_a_teaser():
    for game_id in game_night.CATALOG:
        assert show_host.intro_moment(game_id) in show_host.LINES


# ---- when it speaks -------------------------------------------------------------

def test_quiet_outside_a_game_night():
    room = RoomRegistry().create("trivia")
    assert show_host.say(room, "night_open") is None
    assert show_host.answers_revealed(room, ["a"], [], 3) is None
    assert room.host_queue == []


def test_the_night_opens_with_an_opener_and_a_teaser():
    room = night_room()
    assert moments(room) == ["night_open", "intro_quiz"]
    assert room.host_queue[1]["headline"] == "Up next: Trivia"


def test_a_party_lets_its_own_welcome_open_the_night():
    room = night_room(party={"occasion": "birthday", "honoree": "Asha"})
    assert room.host_queue == []


def test_nobody_right_gets_the_third_grader_treatment():
    room = night_room()
    rng = random.Random(0)
    said = set()
    for _ in range(40):
        said.add(show_host.answers_revealed(room, ["p0", "p1", "p2"], [], 3, rng=rng))
    assert "Nobody got that? I expected a third grader to know this one." in said
    assert room.host_queue[-1]["headline"] == "Nobody got it!"


def test_kids_get_encouragement_instead():
    room = night_room(kids=True)
    line = show_host.answers_revealed(room, ["p0", "p1", "p2"], [], 3, rng=random.Random(1))
    assert line in show_host.LINES["answers_none_kids"]


def test_a_lone_right_answer_names_the_genius_on_screen_only():
    room = night_room()
    rng = random.Random(2)
    line = None
    while line is None:
        line = show_host.answers_revealed(room, ["p0", "p1", "p2"], ["p1"], 3, rng=rng)
    assert "P1" not in line
    assert room.host_queue[-1]["headline"] == "Only P1 got it!"


def test_an_ordinary_split_usually_stays_quiet():
    room = night_room(players=4)
    said = [show_host.answers_revealed(room, ["p0", "p1", "p2", "p3"], ["p0", "p1", "p2"], 4,
                                       rng=random.Random(seed)) for seed in range(20)]
    assert said == [None] * 20


def test_lines_do_not_repeat_until_the_pool_runs_out():
    room = night_room()
    pool = show_host.LINES["answers_none"]
    said = [show_host.say(room, "answers_none", rng=random.Random(i)) for i in range(len(pool))]
    assert sorted(said) == sorted(pool)
    assert show_host.say(room, "answers_none") in pool          # then it starts over


def test_a_game_ending_cheers_the_winner_and_reads_the_table():
    room = night_room()
    room.host_queue.clear()
    before = game_night.standings(room)
    game_night.record_game(room, results("p0", "p1", "p2"))
    show_host.game_finished(room, results("p0", "p1", "p2"), before, rng=random.Random(0))
    assert moments(room) == ["game_won"]
    assert room.host_queue[0]["headline"] == "P0 wins Trivia!"

    game_night.advance(room)
    room.host_queue.clear()
    before = game_night.standings(room)
    game_night.record_game(room, results("p1", "p2", "p0"))
    show_host.game_finished(room, results("p1", "p2", "p0"), before, rng=random.Random(0))
    assert moments(room)[0] == "game_won"
    assert moments(room)[1] in ("lead_change", "close_race")


def test_the_last_game_and_the_champion():
    room = night_room(playlist=("trivia", "herd"))
    game_night.record_game(room, results("p0", "p1", "p2"))
    game_night.advance(room)
    assert moments(room)[-1] == "last_game"
    game_night.record_game(room, results("p0", "p1", "p2"))
    assert game_night.advance(room) is None
    assert moments(room)[-1] == "night_close"
    assert room.host_queue[-1]["headline"] == "P0 is tonight's champion!"


def test_each_line_is_sent_once():
    room = night_room()
    first = show_host.pending(room)
    assert [line["moment"] for line in first] == ["night_open", "intro_quiz"]
    assert show_host.pending(room) == []
    show_host.say(room, "game_won")
    assert [line["moment"] for line in show_host.pending(room)] == ["game_won"]


def test_the_queue_stays_short():
    room = night_room()
    for _ in range(10):
        show_host.say(room, "game_won")
    assert len(room.host_queue) == show_host.MAX_QUEUED


# ---- inside the quiz games ----------------------------------------------------------

def test_trivia_reveal_reacts_in_a_game_night():
    engine, roster = make("trivia", players=3)
    game_night.start(engine.room, ["trivia"])
    engine.room.host_queue.clear()
    engine.question = ("Q?", ["a", "b", "c", "d"], "x", 0)
    engine.answered = {p.id: 2 for p in roster}            # everyone wrong
    engine.pending_points = {}
    engine._reveal()
    assert moments(engine.room) == ["answers_none"]


def test_trivia_reveal_is_quiet_outside_a_game_night():
    engine, roster = make("trivia", players=3)
    engine.question = ("Q?", ["a", "b", "c", "d"], "x", 0)
    engine.answered = {p.id: 2 for p in roster}
    engine.pending_points = {}
    engine._reveal()
    assert engine.room.host_queue == []


# ---- the voice pack ---------------------------------------------------------------------

def test_the_whole_script_is_in_the_voice_pack_narration():
    import importlib.util
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location("rvp", root / "tools" / "render_voice_pack.py")
    rvp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rvp)
    narration = set(rvp.collect([], swift=True).values())
    for line in show_host.all_lines():
        for piece in rvp.pieces(line):
            assert piece in narration, piece


# ---- over the sockets -------------------------------------------------------------------

@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def received(client, name):
    return [e["args"][0] for e in client.get_received(NS) if e["name"] == name]


def test_the_tv_hears_the_host_over_sockets(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"}, namespace=NS)
    code = received(tv, "room_updated")[-1]["code"]
    host = socketio.test_client(app, namespace=NS)
    host.emit("join_room", {"roomCode": code, "playerName": "Asha", "playerID": "dev-h",
                            "isTV": False}, namespace=NS)
    guest = socketio.test_client(app, namespace=NS)
    guest.emit("join_room", {"roomCode": code, "playerName": "Ravi", "playerID": "dev-g",
                             "isTV": False}, namespace=NS)
    tv.get_received(NS)

    host.emit("start_night", {"roomCode": code, "playlist": ["trivia", "herd"]}, namespace=NS)
    lines = received(tv, "host_line")
    assert [line["moment"] for line in lines] == ["night_open", "intro_quiz"]
    assert all(line["roomCode"] == code and line["text"] for line in lines)
    assert re.match(r"Up next: ", lines[1]["headline"])

    host.emit("start_night", {"roomCode": code, "playlist": ["trivia", "herd"]}, namespace=NS)
    seqs = [line["seq"] for line in received(tv, "host_line")]
    assert seqs and min(seqs) > max(line["seq"] for line in lines)      # never re-sent
