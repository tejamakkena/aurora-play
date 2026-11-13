"""Small fixes and features: the picker respects group size again, a topic quiz
fetches enough for its rounds and finale, every brain puzzle has four answers,
and a name can be said differently from how it is spelled."""

import importlib.util
import random
from pathlib import Path

import pytest

from games import brain_puzzles as bp, game_night, night_party as NP, show_host
from games.native_hub.engine import ROOM_CAP
from games.native_hub.registry import ENGINES
from tests.test_native_engines import _NullBroadcaster
from utils.room_manager import RoomRegistry

ROOT = Path(__file__).resolve().parents[1]


class TestPicker:
    def test_two_players_get_games_made_for_two_first(self):
        top = [g["id"] for g in game_night.pick_games(2, rng=random.Random(1))[:3]]
        assert all(ENGINES[g].max_players < ROOM_CAP for g in top), top

    def test_a_big_group_gets_room_wide_games_first(self):
        top = [g["id"] for g in game_night.pick_games(12, rng=random.Random(1))[:4]]
        assert all(ENGINES[g].max_players == ROOM_CAP for g in top), top


class TestTopicQuizLength:
    @pytest.mark.parametrize("rounds, expected", [(None, 17), ("2", 14), ("6", 26)])
    def test_it_asks_for_the_rounds_and_the_whole_finale(self, monkeypatch, rounds, expected):
        from games import topic_gen
        asked = []

        def fake_fetch(kind, topic, count, session_history=None):
            asked.append(count)
            return ([{"question": f"Q{i}?", "options": ["a", "b", "c", "d"], "correct_answer": 0}
                     for i in range(count)], "openai")

        monkeypatch.setattr(topic_gen, "_fetch", fake_fetch)
        room = RoomRegistry().create("trivia")
        room.topic = "Space"
        if rounds:
            room.options = {"rounds": rounds}
        players = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(3)]
        engine = ENGINES["trivia"](room, _NullBroadcaster())
        engine.start(players)
        assert asked == [expected]
        assert len(engine.finale_pool) == engine.FINALE_QUESTIONS


def test_every_ordering_puzzle_has_four_answers():
    for seed in range(100):
        for level in range(1, 11):
            p = bp.make("logic", level, random.Random(seed))
            assert len(set(p["options"])) == 4 and p["answer"] in p["options"]


class TestSayItAs:
    def party(self, **kw):
        return NP.clean_party({"occasion": "birthday", "honoree": "Venkat", **kw})

    def test_the_spelling_for_the_voice_is_kept_apart(self):
        p = self.party(honoreeSaid="Ven-kut")
        assert NP.say_as(p) == {"Venkat": "Ven-kut"}
        assert NP.spoken("Happy birthday, Venkat! Venkat's party.", p) == \
            "Happy birthday, Ven-kut! Ven-kut's party."
        assert NP.spoken("Venkatesh is here.", p) == "Venkatesh is here."   # whole words only

    def test_blank_or_same_means_nothing_to_swap(self):
        assert NP.say_as(self.party()) == {}
        assert NP.say_as(self.party(honoreeSaid="Venkat")) == {}
        assert NP.say_as(NP.clean_party({"honoreeSaid": "x"})) == {}

    def test_the_screen_keeps_the_real_name_and_the_tv_gets_the_mapping(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"],
                         party={"occasion": "birthday", "honoree": "Venkat", "honoreeSaid": "Ven-kut"})
        party = room.to_json()["night"]["party"]
        assert party["sayAs"] == {"Venkat": "Ven-kut"}
        assert "Happy birthday, Venkat!" in party["welcomeLines"]

    def test_prewarm_renders_what_the_tv_will_ask_for(self, monkeypatch):
        from games import voice
        seen = []
        monkeypatch.setattr(voice, "prewarm", lambda lines: seen.extend(lines) or len(lines))
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"],
                         party={"occasion": "birthday", "honoree": "Venkat", "honoreeSaid": "Ven-kut"})
        texts = " ".join(t for t, _ in seen)
        assert "Ven-kut" in texts and "Venkat" not in texts
        seen.clear()
        game_night.begin_party(room)
        show_host.shout(room)
        assert seen and "Ven-kut" in seen[-1][0]

    def test_the_name_is_cleaned(self):
        assert NP.clean_party({"honoreeSaid": "  Ven\x00 kut \n"})["honoreeSaid"] == "Ven kut"


class TestVoicePackNames:
    @pytest.fixture
    def rvp(self):
        spec = importlib.util.spec_from_file_location("rvp_polish", ROOT / "tools" / "render_voice_pack.py")
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod

    def test_a_name_can_carry_how_to_say_it(self, rvp):
        assert rvp.parse_name("Venkat = Ven-kut") == ("Venkat", "Ven-kut")
        assert rvp.parse_name("Teja") == ("Teja", None)
        rvp.SAY_AS["Venkat"] = "Ven-kut"
        assert rvp.spoken("Happy birthday, Venkat!") == "Happy birthday, Ven-kut!"

    def test_the_countdown_calls_are_in_the_pack(self, rvp):
        lines = rvp.scan_swift(["ios/GameLabTV/Views/TVTimeLimitBadge.swift"])
        assert lines == ["One minute to go!", "Ten seconds left!", "Time is up, everybody!"]
        assert "ios/GameLabTV/Views/TVTimeLimitBadge.swift" in rvp.SWIFT_FILES
