"""The rules payload behind the how-to-play interstitial.

The server attaches ``rules_for(game_id)`` to the ``game_started``
broadcast; the TV and the phones both render that same payload, so the
registry is the single source of truth for every game's rules text.
"""

import json
import re

from games.native_hub.registry import ENGINES
from games.native_hub.rules import RULES, rules_for


# Mirrors .github/workflows/no-emoji-check.yml (comments and dev logs are
# excluded there; this registry is pure UI strings, so no exclusions apply).
EMOJI_RE = re.compile(
    "["
    "\U0001F000-\U0001FAFF"
    "\u2600-\u27BF"
    "\u2B00-\u2BFF"
    "\uFE0F"
    "\u200D"
    "\u20E3"
    "\u2190-\u21FF"
    "\u2300-\u23FF"
    "]"
)
EXEMPT = set("\u2660\u2665\u2666\u2663\u2B55\u274C\u2713\u2715\u25B6\U0001F0A0")


def _all_text(game_id):
    entry = RULES[game_id]
    return [entry["title"], entry["objective"], entry["controls"]] + entry["rules"]


class TestEveryEngineHasRules:
    def test_every_registered_engine_id_has_an_entry(self):
        missing = [gid for gid in ENGINES if gid not in RULES]
        assert not missing, f"no rules entry for: {missing}"

    def test_no_orphan_entries(self):
        orphans = [gid for gid in RULES if gid not in ENGINES]
        assert not orphans, f"rules for unregistered ids: {orphans}"


class TestPayloadShape:
    def test_payload_keys(self):
        payload = rules_for("trivia")
        assert set(payload) == {"gameID", "title", "objective", "rules", "controls"}
        assert payload["gameID"] == "trivia"

    def test_title_objective_and_controls_are_non_empty(self):
        for gid in RULES:
            entry = RULES[gid]
            assert entry["title"].strip(), gid
            assert entry["objective"].strip(), gid
            assert entry["controls"].strip(), gid

    def test_three_to_six_non_empty_rule_bullets(self):
        for gid in RULES:
            bullets = RULES[gid]["rules"]
            assert 3 <= len(bullets) <= 6, f"{gid}: {len(bullets)} bullets"
            assert all(isinstance(b, str) and b.strip() for b in bullets), gid

    def test_payload_is_json_round_trippable(self):
        for gid in RULES:
            payload = rules_for(gid)
            assert json.loads(json.dumps(payload)) == payload

    def test_returns_a_copy_not_the_registry_entry(self):
        payload = rules_for("trivia")
        payload["rules"].append("mutated")
        assert "mutated" not in RULES["trivia"]["rules"]


class TestFallback:
    def test_unknown_id_gets_the_generic_entry(self):
        payload = rules_for("not_a_real_game")
        assert payload["gameID"] == "not_a_real_game"
        assert payload["title"]
        assert 3 <= len(payload["rules"]) <= 6


class TestNoEmoji:
    def test_no_emoji_in_any_rules_text(self):
        failures = []
        for gid in RULES:
            for text in _all_text(gid):
                bad = [c for c in text if EMOJI_RE.match(c) and c not in EXEMPT]
                if bad:
                    failures.append(f"{gid}: {''.join(sorted(set(bad)))}")
        assert not failures, f"emoji found in rules text:\n" + "\n".join(failures)
