"""GameID -> engine class mapping.

Anything not listed falls back to ``PlaceholderEngine``, so an id the Swift app
knows about is always startable even before its engine exists.
"""

from games.native_hub.engine import NativeGameEngine
from games.native_hub.engines._placeholder import PlaceholderEngine

ENGINES: dict[str, type[NativeGameEngine]] = {}


def register(game_id: str, engine_cls: type[NativeGameEngine]) -> None:
    ENGINES[game_id] = engine_cls


def engine_for(game_id: str) -> type[NativeGameEngine]:
    return ENGINES.get(game_id, PlaceholderEngine)


def _load_engines() -> None:
    """Import engine modules and register them.

    Imported lazily inside a function so a syntax error in one engine cannot
    take down the whole hub at import time.
    """
    from games.native_hub.engines import (
        party, midgroup, duel, solo,
        legacy_boards, legacy_cards, legacy_social, legacy_new,
        blast_runners, travel, talk, brain_battle, spoken,
    )

    for module in (party, midgroup, duel, solo,
                   legacy_boards, legacy_cards, legacy_social, legacy_new,
                   blast_runners, travel, talk, brain_battle, spoken):
        for gid, cls in module.ENGINES.items():
            register(gid, cls)


try:
    _load_engines()
except Exception as exc:  # pragma: no cover - defensive
    import logging
    logging.getLogger(__name__).exception("engine load failed: %s", exc)
