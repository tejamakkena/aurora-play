"""CORS defaults and Socket.IO event throttling."""

import time

from games.native_hub import socket_events as se


class TestActionThrottle:
    def test_burst_allowed_then_blocked(self):
        sid = "throttle-test-sid"
        se._action_buckets.pop(sid, None)
        for _ in range(se.ACTION_BURST):
            assert se._rate_limited(sid) is False
        assert se._rate_limited(sid) is True
        se._action_buckets.pop(sid, None)

    def test_window_expiry_resets(self):
        sid = "throttle-expiry-sid"
        old = time.time() - se.ACTION_WINDOW_SECONDS - 1
        se._action_buckets[sid] = [old] * se.ACTION_BURST
        assert se._rate_limited(sid) is False
        se._action_buckets.pop(sid, None)

    def test_sensitive_events_are_throttled(self):
        import inspect
        src = inspect.getsource(se.register_native_events)
        for event in ("create_room", "join_room", "add_bot", "remove_bot",
                      "game_action"):
            # Each handler body must call _rate_limited.
            handler = src.split(f'@socketio.on("{event}"')[1].split(
                '@socketio.on(')[0]
            assert "_rate_limited" in handler, event


class TestCorsConfig:
    def _make_origins(self, raw):
        if raw == "*":
            return "*"
        return [o.strip() for o in raw.split(",") if o.strip()]

    def test_default_is_same_origin_only(self):
        import os
        import config
        # Env is unset in the test runner, so the default must be the
        # restrictive empty string (parsed to no allowed origins).
        assert os.environ.get("SOCKETIO_CORS_ORIGINS") is None
        assert config.Config.SOCKETIO_CORS_ORIGINS == ""
        assert self._make_origins(config.Config.SOCKETIO_CORS_ORIGINS) == []

    def test_parses_allowlist(self):
        assert self._make_origins("https://a.example, https://b.example") == \
            ["https://a.example", "https://b.example"]

    def test_star_passthrough(self):
        assert self._make_origins("*") == "*"


class TestOriginChecker:
    """The real checker app.py hands to engine.io."""

    def _check(self, raw=""):
        from app import make_origin_checker
        return make_origin_checker(raw)

    def test_no_origin_header_is_allowed(self):
        assert self._check()(None, {"HTTP_HOST": "game.example"}) is True

    def test_same_host_allowed_even_behind_tls_proxy(self):
        env = {"HTTP_HOST": "game.example", "wsgi.url_scheme": "http",
               "HTTP_X_FORWARDED_PROTO": "https"}
        assert self._check()("https://game.example", env) is True
        assert self._check()("https://game.example:443", env) is True

    def test_lan_host_with_port_allowed(self):
        env = {"HTTP_HOST": "192.168.1.20:5000"}
        assert self._check()("http://192.168.1.20:5000", env) is True

    def test_foreign_origin_rejected(self):
        env = {"HTTP_HOST": "game.example"}
        assert self._check()("https://evil.example", env) is False

    def test_allowlisted_origin_accepted(self):
        env = {"HTTP_HOST": "game.example"}
        check = self._check("https://partner.example, https://b.example")
        assert check("https://partner.example", env) is True
        assert check("https://b.example/", env) is True

    def test_browser_socket_handshake_with_same_origin(self):
        from app import create_app
        app, _ = create_app()
        client = app.test_client()
        resp = client.get("/socket.io/?EIO=4&transport=polling",
                          headers={"Origin": "http://localhost", "Host": "localhost"})
        assert resp.status_code == 200
        bad = client.get("/socket.io/?EIO=4&transport=polling",
                         headers={"Origin": "https://evil.example", "Host": "localhost"})
        assert bad.status_code == 400
