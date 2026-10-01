"""Every browser game page renders for a logged-in player.

A template syntax error (e.g. stray backslash-escaped quotes inside a Jinja
expression) only surfaces when the page is requested, as a 500.
"""

import pytest

from app import create_app

PAGES = [
    "/hangman/", "/mafia/mafia", "/pictionary/", "/raja-mantri/", "/poker/",
    "/tambola/", "/trivia/", "/connect4/", "/memory/", "/roulette/", "/snake/",
    "/digit-guess/", "/canvas-battle/", "/pong/", "/stickfight/", "/roadfighter/",
    "/tictactoe/", "/", "/about", "/join/ABC234",
]


@pytest.fixture(scope="module")
def client():
    app, _ = create_app()
    c = app.test_client()
    c.post("/login/manual", json={"player_name": "Tester"})
    return c


@pytest.mark.parametrize("path", PAGES)
def test_page_renders(client, path):
    assert client.get(path).status_code == 200
