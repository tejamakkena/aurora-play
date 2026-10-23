"""Instant tap feedback must predict exactly what the server says back.

The phones (OptimisticEcho.swift and static/play/js/optimistic.js) show a
vote or answer before the server confirms it. Each prediction has to equal
the private-state change the engine really makes, or the button would flick
between the guess and the truth. This plays every predicted action against
the real engine and compares.
"""

import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

from tests.test_native_engines import make

ROOT = Path(__file__).resolve().parents[1]
JS = ROOT / "static" / "play" / "js" / "optimistic.js"
SWIFT = ROOT / "ios" / "GameLabController" / "Views" / "Controllers" / "OptimisticEcho.swift"

IGNORED = {"secondsLeft"}


def _diff(before: dict, after: dict) -> dict:
    return {k: v for k, v in after.items() if k not in IGNORED and before.get(k) != v}


def _hot_takes_voter(engine, roster):
    return next(p.id for p in roster if engine.is_voter(p.id))


def _atlas_judge(engine, roster):
    engine.phase = "say"
    return engine.judges()[0]


def _odd_vote(engine, roster):
    engine.phase = "vote"
    return roster[1].id


# game, phase to enter, action, data, who acts (default: the second seat)
CASES = [
    ("would_rather", "vote", "vote", {"side": "a"}, None),
    ("host_lies", "vote", "vote", {"side": "liar"}, None),
    ("hot_takes", "vote", "vote", {"side": "for"}, _hot_takes_voter),
    ("most_likely_to", "vote", "vote", {"targetID": "p2"}, None),
    ("odd_one_out", None, "vote", {"targetID": "p2"}, _odd_vote),
    ("bluff_it", "write", "submit_lie", {"text": "banana"}, None),
    ("bluff_it", "pick", "pick", {"index": 0}, None),
    ("herd", "answer", "answer", {"text": "idli"}, None),
    ("emoji_movie", "compose", "submit_emoji", {"emoji": "\U0001F981\U0001F451"}, None),
    ("npat", "fill", "submit", {"name": "Asha", "place": "Agra", "animal": "Ant", "thing": "Axe"}, None),
    ("atlas", None, "judge", {"verdict": "valid"}, _atlas_judge),
]


def _server_echo(game, phase, action, data, who):
    engine, roster = make(game, players=4)
    if phase:
        engine.enter_phase(phase)
    pid = who(engine, roster) if who else roster[1].id
    before = engine.private_state(pid)
    engine.handle_action(pid, action, dict(data))
    return _diff(before, engine.private_state(pid))


def _js_patch(game, action, data):
    script = (
        "global.window = {AP: {}};"
        f"require({json.dumps(str(JS))});"
        f"process.stdout.write(JSON.stringify(window.AP.optimistic.patch("
        f"{json.dumps(game)}, {json.dumps(action)}, {json.dumps(data)})));"
    )
    out = subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


@pytest.mark.skipif(shutil.which("node") is None, reason="node not installed")
@pytest.mark.parametrize("game,phase,action,data,who", CASES)
def test_browser_prediction_matches_the_server(game, phase, action, data, who):
    assert _js_patch(game, action, data) == _server_echo(game, phase, action, data, who)


SWIFT_CASE = {
    "would_rather": "wouldRather", "host_lies": "hostLies", "hot_takes": "hotTakes",
    "most_likely_to": "mostLikelyTo", "odd_one_out": "oddOneOut", "bluff_it": "bluffIt",
    "herd": "herd", "emoji_movie": "emojiMovie", "npat": "npat", "atlas": "atlas",
}


@pytest.mark.parametrize("game,phase,action,data,who", CASES)
def test_ios_prediction_names_the_same_fields(game, phase, action, data, who):
    """Swift can't run here, so check its table names this game/action and
    returns exactly the keys the server changes."""
    source = SWIFT.read_text(encoding="utf-8")
    pair = f'(.{SWIFT_CASE[game]}, "{action}")'
    start = source.index(pair)
    returned = re.search(r"return \[(.*?)\]\n", source[start:], re.S).group(1)
    keys = set(re.findall(r'"(\w+)":', returned))
    assert keys == set(_server_echo(game, phase, action, data, who))


def test_both_tables_cover_the_same_actions():
    source = SWIFT.read_text(encoding="utf-8")
    swift_pairs = set(re.findall(r'\(\.(\w+), "(\w+)"\)', source))
    expected = {(SWIFT_CASE[g], a) for g, _p, a, _d, _w in CASES}
    assert swift_pairs == expected
    js = JS.read_text(encoding="utf-8")
    js_pairs = set(re.findall(r"case '(\w+):(\w+)'", js))
    assert js_pairs == {(g, a) for g, _p, a, _d, _w in CASES}
