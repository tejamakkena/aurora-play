"""Phone Play content that Swift can't check for us on Linux: the Guess the Song
deck matches the server's word list, Secret Story templates are well formed,
and the bigger Charades and Truth or Dare decks have no repeats."""

import importlib.util
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
PHONE = ROOT / "ios" / "GameLabController" / "Views" / "PhonePlay"


def swift_strings(block: str) -> list[str]:
    return [s.replace('\\"', '"') for s in re.findall(r'"((?:[^"\\]|\\.)*)"', block)]


# ---- Guess the Song --------------------------------------------------------------

def test_phone_song_deck_is_the_server_word_list():
    """The phone copy is generated; regenerate with tools/gen_song_deck_swift.py."""
    spec = importlib.util.spec_from_file_location("gen", ROOT / "tools" / "gen_song_deck_swift.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    assert gen.OUT.read_text(encoding="utf-8") == gen.render(), \
        "run: python3 tools/gen_song_deck_swift.py"


def test_song_decks_are_themed_like_charades():
    """Each theme has its own words, a menu title and an SF Symbol; the hint
    language is set per theme (none for English)."""
    from games.native_hub.engines._song_words import DECKS
    assert {"bollywood", "tollywood", "english"} <= set(DECKS)
    for deck_id, deck in DECKS.items():
        assert deck["title"] and deck["symbol"] and len(deck["words"]) >= 40, deck_id
        for entry in deck["words"]:
            for song in entry["songs"]:
                assert re.fullmatch(r".+ \(.+\)", song), song


# ---- Secret Story -----------------------------------------------------------------

def secret_story_templates():
    text = (PHONE / "StoryChain" / "StoryChainDeck.swift").read_text(encoding="utf-8")
    out = []
    for block in re.findall(r"SecretStoryTemplate\((.*?)story: (\".*?\")\)", text, re.S):
        body, story = block
        blanks = re.findall(r'\.init\(prompt: "((?:[^"\\]|\\.)*)", example: "((?:[^"\\]|\\.)*)"\)', body)
        title = re.search(r'title: "([^"]+)"', body).group(1)
        out.append((title, blanks, swift_strings(story)[0]))
    return out


def test_there_are_plenty_of_secret_stories():
    templates = secret_story_templates()
    assert len(templates) >= 8
    assert len({t for t, _b, _s in templates}) == len(templates)


@pytest.mark.parametrize("title,blanks,story", secret_story_templates())
def test_each_story_uses_every_blank_exactly(title, blanks, story):
    used = {int(n) for n in re.findall(r"\{(\d+)\}", story)}
    assert used == set(range(len(blanks))), title
    assert 5 <= len(blanks) <= 8, title
    for prompt, example in blanks:
        assert prompt and example, title


# ---- Truth or Dare topics -----------------------------------------------------------

def topic_cards(kind: str) -> dict[str, list[str]]:
    text = (PHONE / "TruthDare" / "TruthDareTopics.swift").read_text(encoding="utf-8")
    section = text[text.index(f"static let {kind}:"):]
    section = section[:section.index("\n    ]\n")]
    return {m.group(1): swift_strings(m.group(2))
            for m in re.finditer(r"\.(\w+): \[(.*?)\n        \]", section, re.S)}


@pytest.mark.parametrize("kind", ["truths", "dares"])
def test_every_topic_has_a_full_deck(kind):
    cards = topic_cards(kind)
    assert len(cards) >= 9
    seen = set()
    for topic, lines in cards.items():
        assert len(lines) >= 12, topic
        for line in lines:
            assert line[-1] in ".?!", line
            assert line.lower() not in seen, line
            seen.add(line.lower())


# ---- Charades --------------------------------------------------------------------------

def test_tv_charades_has_a_big_deck():
    from games import content_service as cs
    assert len(cs.all_items("charades")) >= 250


def test_phone_charades_movie_decks_have_no_repeats():
    text = (PHONE / "HeadsUp" / "HeadsUpDeckData.swift").read_text(encoding="utf-8")
    for name in ("bollywoodMovies", "tollywoodMovies", "hollywoodMovies", "southMovies"):
        block = re.search(r"static let %s: \[String\] = \[(.*?)\n    \]" % name, text, re.S).group(1)
        items = [s.lower() for s in swift_strings(block)]
        assert len(items) >= 80, name
        assert len(items) == len(set(items)), name
