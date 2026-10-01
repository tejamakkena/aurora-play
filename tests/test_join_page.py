"""QR join: the PNG endpoint and the /join/<code> landing page it encodes."""

import pytest

from app import create_app


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("NATIVE_JOIN_URL_BASE", raising=False)
    app, _ = create_app()
    return app.test_client()


class TestJoinPage:
    def test_join_page_shows_code_and_app_link(self, client):
        resp = client.get("/join/abc234")
        assert resp.status_code == 200
        body = resp.get_data(as_text=True)
        assert "ABC234" in body
        assert "auroraplay://join/ABC234" in body

    def test_bad_code_404s(self, client):
        assert client.get("/join/not-a-code").status_code == 404


class TestJoinBase:
    def test_base_defaults_to_this_server(self, client):
        from games.native_hub.qr import join_url_base
        with client.application.test_request_context(
                "/native/qr/ABC234", base_url="http://game.example",
                headers={"X-Forwarded-Proto": "https"}):
            assert join_url_base() == "https://game.example/join"

    def test_env_override_wins(self, client, monkeypatch):
        from games.native_hub.qr import join_url_base
        monkeypatch.setenv("NATIVE_JOIN_URL_BASE", "http://192.168.1.20:5000/join/")
        with client.application.test_request_context("/native/qr/ABC234"):
            assert join_url_base() == "http://192.168.1.20:5000/join"

    def test_qr_png_served(self, client):
        resp = client.get("/native/qr/ABC234")
        assert resp.status_code == 200
        assert resp.mimetype == "image/png"
