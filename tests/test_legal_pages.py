"""The pages the App Store needs, and the headers every response carries."""

import pytest

from app import create_app


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("SUPPORT_EMAIL", raising=False)
    app, _ = create_app("default")
    return app.test_client()


def test_privacy_page_is_public_and_states_the_essentials(client):
    r = client.get("/privacy")
    assert r.status_code == 200
    text = r.get_data(as_text=True)
    for phrase in ("Privacy Policy", "Game Center", "device ID", "no ads", "Microphone"):
        assert phrase.lower() in text.lower()
    assert "<script" not in text


def test_support_page_is_public(client):
    r = client.get("/support")
    assert r.status_code == 200
    assert "Support" in r.get_data(as_text=True)


def test_contact_comes_from_the_environment_not_the_repo(monkeypatch):
    monkeypatch.setenv("SUPPORT_EMAIL", "help@example.test")
    app, _ = create_app("default")
    text = app.test_client().get("/privacy").get_data(as_text=True)
    assert "help@example.test" in text


def test_no_personal_address_is_baked_into_the_pages():
    import pathlib
    for name in ("privacy.html", "support.html"):
        body = pathlib.Path("templates", name).read_text(encoding="utf-8")
        assert "@gmail" not in body and "@icloud" not in body


def test_security_headers_on_every_response(client):
    r = client.get("/privacy")
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["X-Frame-Options"] == "SAMEORIGIN"
    assert r.headers["Referrer-Policy"] == "strict-origin-when-cross-origin"
    assert "microphone=()" in r.headers["Permissions-Policy"]
    assert "Strict-Transport-Security" not in r.headers      # plain http


def test_hsts_only_behind_https(client):
    r = client.get("/privacy", headers={"X-Forwarded-Proto": "https"})
    assert "max-age" in r.headers["Strict-Transport-Security"]


def test_production_never_signs_sessions_with_the_known_dev_key(monkeypatch):
    import importlib
    import config
    monkeypatch.delenv("SECRET_KEY", raising=False)
    importlib.reload(config)
    try:
        key = config.ProductionConfig.SECRET_KEY
        assert key != config._DEV_SECRET and len(key) >= 32
        monkeypatch.setenv("SECRET_KEY", "chosen-by-the-operator")
        importlib.reload(config)
        assert config.ProductionConfig.SECRET_KEY == "chosen-by-the-operator"
    finally:
        monkeypatch.delenv("SECRET_KEY", raising=False)
        importlib.reload(config)
