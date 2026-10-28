"""The party layer of a Game Night: occasion, guest of honour, host style."""

import re

import pytest

from app import create_app
from games import game_night, night_party as NP
from utils.room_manager import RoomRegistry, RoomState, rooms

NS = "/native"

EMOJI_RE = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍⃣←-⇿⌀-⏿]")


def results(*ids):
    return [{"playerID": pid, "name": pid.upper(), "score": 10 - i, "rank": i + 1}
            for i, pid in enumerate(ids)]


class TestParty:
    def test_invalid_fields_keep_their_previous_value(self):
        base = NP.clean_party({"occasion": "birthday", "honoree": "Asha"})
        party = NP.clean_party({"occasion": "x", "style": 4, "humor": "no",
                                "nhiePack": "no", "nhieRounds": 99}, base)
        assert party == base

    @pytest.mark.parametrize("junk", [None, "x", 7, []])
    def test_non_dict_is_ignored(self, junk):
        assert NP.clean_party(junk) == NP.default_party()

    def test_bool_is_not_a_round_count(self):
        assert NP.clean_party({"nhieRounds": True})["nhieRounds"] == 10

    def test_name_is_cleaned_and_capped(self):
        party = NP.clean_party({"honoree": "  Ve\x00nkat\n\n Teja " + "x" * 80})
        assert "\x00" not in party["honoree"] and "\n" not in party["honoree"]
        assert party["honoree"].startswith("Venkat Teja")
        assert len(party["honoree"]) <= NP.MAX_NAME_LEN

    def test_titles_and_cheers(self):
        p = NP.clean_party({"occasion": "birthday", "honoree": "Venkat"})
        assert NP.title_for(p) == "Venkat's Birthday Party"
        assert NP.cheer_for(p) == "Happy birthday, Venkat!"
        assert NP.title_for(NP.clean_party({"occasion": "birthday", "honoree": "James"})) \
            == "James' Birthday Party"
        assert NP.title_for(NP.clean_party({"occasion": "birthday"})) == "Birthday Party"
        fest = NP.clean_party({"occasion": "festival", "honoree": "Diwali"})
        assert NP.title_for(fest) == "Diwali Party" and NP.cheer_for(fest) == "Happy Diwali!"

    def test_every_style_defines_every_line_and_speaks_them(self):
        keys = set(NP.STYLES["party_host"])
        for sid, style in NP.STYLES.items():
            assert set(style) == keys, sid
            p = NP.clean_party({"style": sid, "occasion": "birthday", "honoree": "Asha"})
            assert "Asha's Birthday Party" in NP.welcome_lines(p)[0]
            text = " ".join(NP.lineup_lines(p, ["herd", "trivia", "never_have_i_ever"]))
            assert "Herd" in text and "Never Have I Ever" in text
            assert NP.lineup_lines(p, ["herd"]) and NP.lineup_lines(p, [])
            assert "Asha" in " ".join(NP.finale_lines(p, "Asha", 20))
            assert NP.finale_lines(p, None, 0)

    def test_lineup_names_games_in_order(self):
        text = " ".join(NP.lineup_lines(NP.default_party(), ["herd", "trivia", "bluff_it"]))
        assert text.index("Herd") < text.index("Trivia") < text.index("Bluff")

    def test_a_get_together_does_not_repeat_its_welcome(self):
        assert len(NP.welcome_lines(NP.clean_party({"occasion": "gathering"}))) == 1

    def test_nothing_the_tv_says_or_shows_has_emoji(self):
        blobs = [str(NP.OCCASIONS), str(NP.STYLES)]
        assert not any(EMOJI_RE.search(b) for b in blobs)


class TestNightWithAParty:
    def make(self, **party):
        room = RoomRegistry().create("trivia")
        for i in range(3):
            room.add_player(f"p{i}", f"P{i}", f"s{i}")
        game_night.start(room, ["trivia", "herd"], party=party or None)
        return room

    def test_no_party_means_no_party_json(self):
        room = RoomRegistry().create("trivia")
        game_night.start(room, ["trivia"])
        assert room.to_json()["night"]["party"] is None
        assert game_night.begin_party(room) is False

    def test_the_welcome_waits_for_the_host(self):
        room = self.make(occasion="birthday", honoree="Venkat")
        party = room.to_json()["night"]["party"]
        assert party["welcomed"] is False
        assert party["title"] == "Venkat's Birthday Party"
        assert "Venkat's Birthday Party" in party["welcomeLines"][0]
        assert "Happy birthday, Venkat!" in party["welcomeLines"]
        assert any("Trivia" in l for l in party["lineupLines"])
        assert game_night.begin_party(room) is True
        assert room.to_json()["night"]["party"]["welcomed"] is True
        assert game_night.begin_party(room) is False          # only once

    def test_the_lines_do_not_change_between_pushes(self):
        room = self.make(occasion="birthday", honoree="Venkat")
        assert room.to_json()["night"]["party"] == room.to_json()["night"]["party"]

    def test_the_night_settings_reach_the_games(self):
        room = self.make(nhiePack="desi", humor="dad")
        assert room.night["party"]["nhiePack"] == "desi"

    def test_the_finale_names_the_champion(self):
        room = self.make(occasion="birthday", honoree="Venkat")
        game_night.record_game(room, results("p0", "p1", "p2"))
        game_night.advance(room)
        game_night.record_game(room, results("p0", "p2", "p1"))
        assert game_night.advance(room) is None
        lines = room.to_json()["night"]["party"]["finaleLines"]
        assert "P0" in " ".join(lines) and "Venkat's Birthday Party" in " ".join(lines)


@pytest.fixture
def server():
    rooms.clear()
    return create_app("default")


def latest(client, name):
    events = [e for e in client.get_received(NS) if e["name"] == name]
    assert events, f"expected {name}"
    return events[-1]["args"][0]


def test_party_over_sockets(server):
    app, socketio = server
    tv = socketio.test_client(app, namespace=NS)
    tv.emit("create_room", {"gameID": "trivia", "hostName": "TV", "hostID": "tv-1"}, namespace=NS)
    code = latest(tv, "room_updated")["code"]
    host = socketio.test_client(app, namespace=NS)
    host.emit("join_room", {"roomCode": code, "playerName": "Ipad", "playerID": "dev-h",
                            "isTV": False}, namespace=NS)
    guest = socketio.test_client(app, namespace=NS)
    guest.emit("join_room", {"roomCode": code, "playerName": "G", "playerID": "dev-g",
                             "isTV": False}, namespace=NS)
    guest.get_received(NS)

    host.emit("start_night", {"roomCode": code, "playlist": ["trivia", "herd"],
                              "party": {"occasion": "birthday", "honoree": "Venkat"}},
              namespace=NS)
    party = latest(tv, "room_updated")["night"]["party"]
    assert party["title"] == "Venkat's Birthday Party" and party["welcomed"] is False

    guest.emit("begin_party", {"roomCode": code}, namespace=NS)         # a guest cannot
    assert latest(guest, "error")["code"] == "NOT_HOST"
    assert rooms.get(code).night["party"]["welcomed"] is False

    host.emit("begin_party", {"roomCode": code}, namespace=NS)
    assert latest(tv, "room_updated")["night"]["party"]["welcomed"] is True

