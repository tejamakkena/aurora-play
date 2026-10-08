"""The browser controller (static/play): its page, its assets, and that it
covers every TV game the iOS controller does."""

import re
from pathlib import Path

import pytest

from app import create_app
from games.native_hub.registry import ENGINES

PLAY = Path(__file__).resolve().parent.parent / "static" / "play"

# GameIDs the iOS app retired (ios/Shared/Models/Game.swift `retired`): their
# engines stay on the server so older rooms still decode, but no controller
# exists for them in either client.
RETIRED = {
    "chess", "pong", "air_hockey", "carrom", "blast_runners", "neon_snake",
    "twenty48", "brick_breaker", "simon_says", "memory", "digit_guess",
    "hot_grid", "stock_panic", "kbc", "story_chain",
}


@pytest.fixture
def client():
    app, _ = create_app()
    return app.test_client()


class TestPlayPage:
    def test_play_page_serves_the_controller_shell(self, client):
        resp = client.get("/play")
        assert resp.status_code == 200
        body = resp.get_data(as_text=True)
        assert 'id="screen-root"' in body
        assert "play/vendor/socket.io.min.js" in body
        assert "play/js/main.js" in body
        assert "play/play.css" in body

    def test_code_in_the_path_prefills_the_join_form(self, client):
        body = client.get("/play/abc234").get_data(as_text=True)
        assert 'data-code="ABC234"' in body

    def test_bad_code_404s(self, client):
        assert client.get("/play/not-a-code").status_code == 404

    def test_every_script_the_page_loads_exists(self, client):
        body = client.get("/play").get_data(as_text=True)
        srcs = re.findall(r'<script src="([^"?]+)', body)
        assert len(srcs) > 20
        for src in srcs:
            assert client.get(src).status_code == 200, src

    def test_game_scripts_load_before_main(self, client):
        body = client.get("/play").get_data(as_text=True)
        assert body.index("play/js/games/trivia.js") < body.index("play/js/main.js")

    def test_play_is_not_rate_limited_per_ip(self, client):
        # A whole party shares one Wi-Fi IP; the 50-per-hour default would
        # lock guests out of joining.
        for _ in range(80):
            assert client.get("/play").status_code == 200

    def test_join_landing_offers_the_browser(self, client):
        body = client.get("/join/abc234").get_data(as_text=True)
        assert 'href="/play/ABC234"' in body


class TestControllerCoverage:
    def _registered(self):
        found = set()
        for path in (PLAY / "js" / "games").glob("*.js"):
            found |= set(re.findall(r"AP\.controllers\.(\w+)\s*=", path.read_text()))
        return found

    def test_every_live_game_has_a_web_controller(self):
        live = set(ENGINES) - RETIRED
        missing = live - self._registered()
        assert not missing, f"no web controller for: {sorted(missing)}"

    def test_no_controller_for_a_game_the_server_does_not_know(self):
        unknown = self._registered() - set(ENGINES)
        assert not unknown, f"controllers without an engine: {sorted(unknown)}"

    def test_game_metadata_lists_the_same_games(self):
        text = (PLAY / "js" / "games.js").read_text()
        block = text[text.index("var G = {"):text.index("var RETIRED")]
        listed = set(re.findall(r"^\s{4}(\w+):\s*\[", block, flags=re.M))
        assert listed == set(ENGINES) - RETIRED


class TestNoEmojiInSource:
    """The repo's no-emoji check scans static/**/*.js; card suits and arrows
    are exempt there, anything above U+2500 is not."""

    def test_sources_are_clean(self):
        exempt = set("♠♥♦♣⭕❌✓✕▶\U0001F0A0")
        for path in PLAY.rglob("*.js"):
            for n, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
                bad = [c for c in line if ord(c) > 0x2500 and c not in exempt]
                assert not bad, f"{path.name}:{n}: {bad}"
