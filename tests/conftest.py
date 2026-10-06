"""Shared test setup."""

import pytest


@pytest.fixture(autouse=True)
def isolated_content_service(tmp_path, monkeypatch):
    """Keep games/content_service.py's histories and pool out of the repo's
    data/ directory and fresh for every test (it is module-level state)."""
    from games import content_service
    monkeypatch.setenv("CONTENT_HEARD_PATH", str(tmp_path / "content_heard.json"))
    monkeypatch.setenv("CONTENT_POOL_PATH", str(tmp_path / "content_pool.json"))
    monkeypatch.setenv("CONTENT_AUTO_REFILL", "0")
    # Brain Battle personal bests (games/native_hub/engines/brain_battle.py).
    monkeypatch.setenv("BRAIN_SCORES_PATH", str(tmp_path / "brain_scores.json"))
    for var, name in (("PROFILES_PATH", "profiles.json"),
                      ("DAILY_SCORES_PATH", "daily_scores.json"),
                      ("DECKS_CACHE_PATH", "decks_cache.json")):
        monkeypatch.setenv(var, str(tmp_path / name))
    content_service.reset_for_tests()
    yield
    content_service.reset_for_tests()
