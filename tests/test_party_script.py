"""The party host performs rather than reads: short sentences, a cue for how
each is said, the guest of honour's name in a few sentences only, a shout on
demand, and a joke about each game."""

import re

import pytest

from games import game_night, night_party as NP, party_script as PS, show_host, voice_styles
from games.native_hub.rules import rules_for
from utils.room_manager import RoomRegistry

EMOJI_RE = re.compile("[\U0001F000-\U0001FAFF☀-➿⬀-⯿️‍⃣←-⇿⌀-⏿]")


def party(**kw):
    return NP.clean_party({"occasion": "birthday", "honoree": "Venkat", **kw})


def room_with(playlist, **kw):
    room = RoomRegistry().create(playlist[0])
    for i in range(3):
        room.add_player(f"p{i}", f"P{i}", f"s{i}")
    game_night.start(room, playlist, party={"occasion": "birthday", "honoree": "Venkat", **kw})
    return room


class TestWords:
    def test_every_catalog_game_has_its_own_joke(self):
        missing = [g for g in game_night.CATALOG if g not in PS.TEASERS]
        assert not missing

    def test_no_emoji_anywhere_in_the_script(self):
        blobs = [str(PS.SCRIPTS), str(PS.TEASERS), str(NP.STYLES)]
        assert not any(EMOJI_RE.search(b) for b in blobs)

    def test_every_cue_is_a_known_voice_style(self):
        for occasion in PS.SCRIPTS:
            for name in ("Venkat", ""):
                p = NP.clean_party({"occasion": occasion, "honoree": name})
                for line, cue in (NP.welcome_script(p) + NP.lineup_script(p, ["herd", "trivia", "ludo"])
                                  + NP.finale_script(p, "Asha", 9) + NP.shout_script(p)):
                    assert line.strip() and voice_styles.canonical(cue), (occasion, line, cue)

    @pytest.mark.parametrize("occasion", sorted(PS.SCRIPTS))
    def test_a_name_never_hides_in_a_joke(self, occasion):
        """Only a few short sentences carry the name, so the pack can render them
        per name ahead of the party; every other sentence is the same for everyone."""
        p = NP.clean_party({"occasion": occasion, "honoree": "Zxqvname"})
        for line, _ in NP.welcome_script(p) + NP.finale_script(p, "Wnnrx", 3):
            if "Zxqvname" in line or "Wnnrx" in line:
                assert len(line) < 90, line
        for sentence in PS.script_for(occasion)["rules"] + list(PS.TEASERS.values()):
            assert "{" not in sentence

    def test_sentences_are_short_enough_to_perform(self):
        for text in list(PS.TEASERS.values()):
            assert len(text) <= 125, text


class TestTheShow:
    def test_cues_run_alongside_the_lines(self):
        room = room_with(["herd", "trivia", "ludo"])
        night = room.to_json()["night"]["party"]
        assert len(night["welcomeLines"]) == len(night["welcomeCues"]) > 5
        assert len(night["lineupLines"]) == len(night["lineupCues"]) > 3

    def test_the_welcome_shouts_for_the_birthday_person(self):
        script = NP.welcome_script(party(accent="standard"))
        assert script[-1] == ("Happy birthday, Venkat!", "cheer")
        assert any(c == "roast" for _, c in script)           # a joke at the room's expense
        assert NP.welcome_script(party())[-1] == ("Happy birthday, Venkat!", "indian")

    def test_the_lineup_teases_the_first_and_last_game(self):
        lines = NP.lineup_lines(party(), ["herd", "trivia", "ludo"])
        text = " ".join(lines)
        assert PS.teaser("herd") in text and PS.teaser("ludo") in text
        assert text.index("Herd") < text.index("Trivia") < text.index("Ludo")

    def test_the_finale_names_the_winner_and_toasts_the_guest(self):
        lines = NP.finale_lines(party(), "Asha", 20)
        assert "Asha!" in lines
        assert "Venkat" in lines[-1]
        assert NP.finale_lines(party(), None, 0)

    def test_a_shout_is_one_breath_in_the_shouting_voice(self):
        room = room_with(["herd", "trivia"])
        text = show_host.shout(room)
        assert text and "Venkat" in text
        entry = room.host_queue[-1]
        assert entry["moment"] in ("cheer", "indian")
        assert entry["headline"] == "Happy birthday, Venkat!"
        assert show_host.pending(room)[-1]["text"] == text

    def test_no_party_no_shout(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia"])
        assert show_host.shout(room) is None

    def test_each_later_game_is_teased_by_name(self):
        room = room_with(["herd", "trivia", "ludo", "mafia"])
        show_host.pending(room)
        game_night.advance(room)
        assert show_host.pending(room)[-1]["text"] == PS.teaser("trivia")
        game_night.advance(room)
        assert show_host.pending(room)[-1]["text"] == PS.teaser("ludo")
        game_night.advance(room)                               # the last game keeps its own line
        assert show_host.pending(room)[-1]["text"] != PS.teaser("mafia")

    def test_a_plain_night_is_unchanged(self):
        room = RoomRegistry().create("herd")
        game_night.start(room, ["herd", "trivia", "ludo"])
        show_host.pending(room)
        game_night.advance(room)
        assert show_host.pending(room)[-1]["moment"].startswith("intro_")


class TestIndianNames:
    @pytest.mark.parametrize("name", ["Venkat", "teja", "Priya Sharma", "ASHA"])
    def test_common_indian_names_use_the_indian_voice(self, name):
        p = NP.clean_party({"honoree": name, "occasion": "birthday"})
        assert NP.indian_voice(p) is True
        lines = NP.welcome_script(p)
        assert any(cue == "indian" for text, cue in lines if name.split()[0] in text)

    def test_other_names_use_the_normal_voice_unless_asked(self):
        assert NP.indian_voice(NP.clean_party({"honoree": "James"})) is False
        assert NP.indian_voice(NP.clean_party({"honoree": "James", "accent": "indian"})) is True
        assert NP.indian_voice(NP.clean_party({"honoree": "Venkat", "accent": "standard"})) is False

    def test_the_fixed_jokes_keep_their_own_cue(self):
        lines = NP.welcome_script(party())
        assert any(cue == "roast" for _, cue in lines)

    def test_a_bad_accent_is_ignored(self):
        assert NP.clean_party({"accent": "pirate"})["accent"] == "auto"

    def test_the_night_says_which_voice(self):
        assert room_with(["herd", "trivia"]).to_json()["night"]["party"]["indianVoice"] is True
        assert room_with(["herd", "trivia"], honoree="James").to_json()["night"]["party"]["indianVoice"] is False


class TestVoicePackLines:
    def test_names_get_their_own_sentences_and_the_indian_voice(self):
        lines = NP.pack_lines(["Venkat", "James"])
        by_text = {t: c for t, c in lines}
        assert by_text["Happy birthday, Venkat!"] == "indian"
        assert by_text["Happy birthday, James!"] == "cheer"
        assert "Venkat!" in by_text and "James!" in by_text           # the champion's name
        assert by_text["Hip hip!"] == "cheer"

    def test_without_names_only_fixed_sentences(self):
        lines = NP.pack_lines([])
        assert not any("Venkat" in t for t, _ in lines)
        assert any(t == PS.teaser("herd") for t, _ in lines)
        assert len(lines) == len(set(lines))

    def test_every_sentence_a_party_can_say_is_in_the_pack(self):
        """Whatever the host says at a party that has no name in it is in the pack."""
        import re as _re
        split = lambda text: _re.split(r"(?<=[.!?])\s+", text)          # noqa: E731
        pack = {sentence for t, _ in NP.pack_lines([]) for sentence in split(t)}
        for occasion in ("birthday", "gathering", "festival"):
            p = NP.clean_party({"occasion": occasion, "style": "game_show"})
            lineup = NP.lineup_script(p, ["herd", "trivia", "ludo", "mafia"])
            for text, _ in NP.welcome_script(p) + lineup + NP.shout_script(p):
                for sentence in split(text):
                    assert sentence in pack, sentence

    def test_the_renderer_collects_them_with_their_cues(self):
        import importlib.util
        from pathlib import Path
        root = Path(__file__).resolve().parents[1]
        spec = importlib.util.spec_from_file_location("rvp2", root / "tools" / "render_voice_pack.py")
        rvp = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(rvp)
        clips, styles = rvp.collect_styled([], swift=True, names=["Teja"], occasions=["birthday"])
        key = rvp.key("Happy birthday, Teja!")
        assert clips[key] == "Happy birthday, Teja!" and styles[key] == "indian"
        assert styles[rvp.key("Hip hip!")] == "cheer"
