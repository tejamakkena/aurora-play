"""Brain Battle engine: phases, scoring, memory twist, privacy, titles and
personal bests (written to a tmp path by tests/conftest.py)."""

import json
import os
import random
import time

import pytest

from games import brain_puzzles as bp
from games.native_hub import bots
from games.native_hub.engines import brain_battle as bb
from games.native_hub.engines.brain_battle import BrainBattleEngine
from games.native_hub.registry import ENGINES
from games.native_hub.rules import rules_for
from utils import validators as v
from utils.room_manager import RoomRegistry, RoomState


class _NullBroadcaster:
    def state(self): pass
    def room_update(self): pass
    def error(self, *args, **kwargs): pass


def make(players=4, seed=7, kinds=None):
    random.seed(seed)
    registry = RoomRegistry()
    room = registry.create("brain_battle")
    roster = [room.add_player(f"p{i}", f"P{i}", f"s{i}") for i in range(players)]
    engine = BrainBattleEngine(room, _NullBroadcaster())
    room.engine = engine
    room.state = RoomState.PLAYING
    engine.start(roster)
    if kinds is not None:
        force_kind(engine, kinds)
    return engine, roster


def force_kind(engine, kinds):
    """Replay the current round with a chosen puzzle kind."""
    engine.kind_order = list(kinds) if isinstance(kinds, (list, tuple)) else [kinds]
    engine.start_round()


def force_advance(engine):
    engine.deadline = time.time() - 1
    engine.tick(0)


def wrong_choice(engine):
    return next(o for o in engine.puzzle["options"] if o != engine.puzzle["answer"])


def keys_deep(value):
    if isinstance(value, dict):
        for k, inner in value.items():
            yield k
            yield from keys_deep(inner)
    elif isinstance(value, list):
        for inner in value:
            yield from keys_deep(inner)


def play_round(engine, roster, correct_ids=()):
    if engine.phase == "memorize":
        force_advance(engine)
    for p in roster:
        choice = engine.puzzle["answer"] if p.id in correct_ids else wrong_choice(engine)
        engine.handle_action(p.id, "answer", {"choice": choice})
    engine.tick(0)                 # everyone locked -> reveal
    assert engine.phase == "reveal"
    force_advance(engine)          # reveal -> next round (or summary)


class TestRegistration:
    def test_registered_everywhere(self):
        assert ENGINES["brain_battle"] is BrainBattleEngine
        assert "brain_battle" in v.GAME_IDS
        assert rules_for("brain_battle")["title"] == "Brain Battle"
        assert "brain_battle" in bots.POLICIES

    def test_bounds(self):
        assert BrainBattleEngine.min_players == 2
        assert BrainBattleEngine.max_players == 12
        assert BrainBattleEngine.total_rounds == 12

    def test_swift_enum_knows_the_id(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        with open(os.path.join(root, "ios", "Shared", "Models", "Game.swift")) as fh:
            assert '"brain_battle"' in fh.read()


class TestRounds:
    def test_kinds_cycle_through_every_kind(self):
        engine, _ = make()
        first8 = [engine.kind_for_round(r) for r in range(1, 9)]
        assert sorted(first8) == sorted(bp.ALL_KINDS)
        assert engine.kind_for_round(9) == engine.kind_for_round(1)

    def test_level_rises_every_two_rounds(self):
        engine, _ = make()
        assert [engine.level_for_round(r) for r in (1, 2, 3, 4, 5, 12)] == [2, 2, 3, 3, 4, 7]
        assert engine.level_for_round(100) == 10

    def test_first_round_starts_in_answer_or_memorize(self):
        engine, _ = make()
        expected = "memorize" if engine.puzzle["kind"] == "memory" else "answer"
        assert engine.phase == expected
        assert engine.round == 1

    def test_answer_phase_ends_early_when_all_locked(self):
        engine, roster = make(kinds="math")
        assert engine.phase == "answer"
        for p in roster[:-1]:
            engine.handle_action(p.id, "answer", {"choice": engine.puzzle["answer"]})
        engine.tick(0)
        assert engine.phase == "answer"           # still waiting on one
        engine.handle_action(roster[-1].id, "answer", {"choice": engine.puzzle["answer"]})
        engine.tick(0)
        assert engine.phase == "reveal"
        assert engine.seconds_left() > 0          # reveal holds its beat
        engine.tick(0)
        assert engine.phase == "reveal"           # reveal never ends early

    def test_answer_times_out(self):
        engine, roster = make(kinds="logic")
        force_advance(engine)
        assert engine.phase == "reveal"
        force_advance(engine)
        assert engine.round == 2

    def test_disconnected_players_do_not_stall(self):
        engine, roster = make(kinds="sequence")
        roster[3].connected = False
        for p in roster[:3]:
            engine.handle_action(p.id, "answer", {"choice": engine.puzzle["answer"]})
        engine.tick(0)
        assert engine.phase == "reveal"
        assert roster[3].id not in engine.round_outcome["correctIDs"]

    def test_full_game_reaches_summary_then_final(self):
        engine, roster = make()
        for _ in range(12):
            play_round(engine, roster, correct_ids={roster[0].id})
        assert engine.phase == "summary"
        assert not engine.is_over()
        assert engine.public_state()["results"]
        force_advance(engine)
        assert engine.is_over()
        assert engine.phase == "final"
        assert engine.results()[0]["playerID"] == roster[0].id


class TestAnswers:
    def test_first_answer_locks(self):
        engine, roster = make(kinds="calendar")
        wrong = wrong_choice(engine)
        engine.handle_action("p0", "answer", {"choice": wrong})
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        assert engine.submissions["p0"]["choice"] == wrong
        priv = engine.private_state("p0")
        assert priv["locked"] is True and priv["myAnswer"] == wrong

    def test_rejects_bad_choices_and_players(self):
        engine, roster = make(kinds="math")
        engine.handle_action("p0", "answer", {"choice": "not an option"})
        engine.handle_action("p0", "answer", {"choice": 3})
        engine.handle_action("p0", "answer", {})
        engine.handle_action("ghost", "answer", {"choice": engine.puzzle["answer"]})
        engine.handle_action("p0", "vote", {"choice": engine.puzzle["answer"]})
        assert engine.submissions == {}

    def test_no_answers_outside_answer_phase(self):
        engine, roster = make(kinds="memory")
        assert engine.phase == "memorize"
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        assert engine.submissions == {}


class TestScoring:
    def test_correct_scores_base_plus_speed_bonus(self):
        engine, roster = make(kinds="sequence")
        engine.answer_started = time.time() - 5         # 15 of 20 seconds left
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        engine.answer_started = time.time() - 15        # 5 left
        engine.handle_action("p1", "answer", {"choice": engine.puzzle["answer"]})
        engine.handle_action("p2", "answer", {"choice": wrong_choice(engine)})
        # Nothing awarded before the reveal: the TV scoreboard stays honest.
        assert engine.scores["p0"] == 0
        force_advance(engine)
        assert 870 <= engine.scores["p0"] <= 875
        assert 620 <= engine.scores["p1"] <= 625
        assert engine.scores["p2"] == 0 and engine.scores["p3"] == 0
        out = engine.public_state()["reveal"]
        assert set(out["correctIDs"]) == {"p0", "p1"}
        assert out["fastestID"] == "p0"
        assert out["answer"] == engine.puzzle["answer"]
        assert out["explain"]

    def test_points_bounds(self):
        engine, _ = make()
        assert engine.points_for(0) == 1000
        assert engine.points_for(20) == 500
        assert engine.points_for(99) == 500

    def test_private_reveal_feedback(self):
        engine, roster = make(kinds="sequence")
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        engine.handle_action("p1", "answer", {"choice": wrong_choice(engine)})
        force_advance(engine)
        p0, p1, p2 = (engine.private_state(pid) for pid in ("p0", "p1", "p2"))
        assert p0["wasCorrect"] is True and p0["pointsEarned"] > 500 and p0["isFastest"]
        assert p0["myScore"] == p0["pointsEarned"]
        assert p1["wasCorrect"] is False and p1["pointsEarned"] == 0
        assert p2["wasCorrect"] is False and p2["locked"] is False
        assert p1["correctAnswer"] == engine.puzzle["answer"]

    def test_skill_stats_tracked(self):
        engine, roster = make(kinds="rotation")
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        force_advance(engine)
        assert engine.skill_stats["p0"]["Spatial"] == {"correct": 1, "total": 1}
        assert engine.skill_stats["p1"]["Spatial"] == {"correct": 0, "total": 1}


class TestMemory:
    def test_memorize_shows_digits_then_hides_them(self):
        engine, roster = make(kinds="memory")
        assert engine.phase == "memorize"
        pub = engine.public_state()
        assert pub["memoryDigits"] == engine.memory_digits
        assert len(engine.memory_digits) >= 3
        assert pub["puzzle"]["options"] == []
        assert engine.private_state("p0")["options"] == []
        force_advance(engine)
        assert engine.phase == "answer"
        pub = engine.public_state()
        assert pub["memoryDigits"] == []
        assert len(pub["puzzle"]["options"]) == 4
        # Digits must not survive in the prompt either.
        digits_text = ", ".join(str(d) for d in engine.memory_digits)
        assert digits_text not in pub["puzzle"]["prompt"]

    def test_memory_options_are_unique_near_misses(self):
        rng = random.Random(3)
        for backwards in (False, True):
            for length in range(3, 9):
                digits = [rng.randint(1, 9) for _ in range(length)]
                answer, opts = bb.memory_options(rng, digits, backwards)
                assert len(opts) == 4 and len(set(opts)) == 4
                assert answer in opts
                expect = list(reversed(digits)) if backwards else digits
                assert answer == " ".join(str(d) for d in expect)
                for o in opts:
                    assert len(o.split()) == length

    def test_memory_round_scores(self):
        engine, roster = make(kinds="memory")
        force_advance(engine)
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        force_advance(engine)
        assert engine.scores["p0"] >= 500
        assert engine.skill_stats["p0"]["Memory"]["correct"] == 1


class TestRotationAndPrivacy:
    def test_rotation_visual_reaches_tv_and_phone(self):
        engine, roster = make(kinds="rotation")
        pub = engine.public_state()["puzzle"]
        assert pub["options"] == ["A", "B", "C", "D"]
        assert len(pub["visual"]["choices"]) == 4
        assert pub["visual"]["target"]
        priv = engine.private_state("p0")
        assert priv["visual"] == pub["visual"]
        assert priv["options"] == ["A", "B", "C", "D"]

    @pytest.mark.parametrize("kind", list(bp.ALL_KINDS))
    def test_answer_never_public_before_reveal(self, kind):
        engine, roster = make(kinds=kind)
        for _ in range(2):   # memorize (if any) and answer
            pub = engine.public_state()
            assert pub["reveal"] is None
            keys = set(keys_deep(pub))
            assert not keys & {"answer", "explain", "correctIDs", "accepts", "hint", "spoken"}
            priv = engine.private_state("p1")
            assert priv["correctAnswer"] is None and priv["wasCorrect"] is None
            json.dumps(pub)
            json.dumps(priv)
            if engine.phase == "memorize":
                force_advance(engine)
            else:
                break
        assert engine.phase == "answer"
        engine.handle_action("p0", "answer", {"choice": engine.puzzle["answer"]})
        assert engine.public_state()["lockedCount"] == 1
        assert engine.public_state()["players"][0]["score"] == 0
        force_advance(engine)
        assert engine.public_state()["reveal"]["answer"] == engine.puzzle["answer"]


class TestResults:
    def test_titles_from_best_skill(self):
        engine, roster = make()
        engine.skill_stats = {
            "p0": {"Memory": {"correct": 2, "total": 2}, "Logic": {"correct": 1, "total": 3}},
            "p1": {"Spatial": {"correct": 1, "total": 1}},
            "p2": {"Word Smarts": {"correct": 2, "total": 3}, "Patterns": {"correct": 1, "total": 2}},
            "p3": {"Number Speed": {"correct": 0, "total": 2}},
        }
        assert engine.brain_title("p0") == "Memory Champ"
        assert engine.brain_title("p1") == "Shape Shifter"
        assert engine.brain_title("p2") == "Word Wizard"
        assert engine.brain_title("p3") == bb.FALLBACK_TITLE
        assert set(bb.BRAIN_TITLES) == set(bp.SKILLS.values())

    def test_brain_score_weighted_by_level(self):
        engine, _ = make()
        engine.level_points = {"p0": [6, 8], "p1": [0, 8]}
        assert engine.brain_score("p0") == 75
        assert engine.brain_score("p1") == 0
        assert engine.brain_score("p2") == 0

    def _finish(self, engine, roster, correct_ids):
        for _ in range(engine.total_rounds - engine.round + 1):
            play_round(engine, roster, correct_ids=correct_ids)
        assert engine.phase == "summary"
        return engine.results()

    def test_results_carry_titles_and_scores(self):
        engine, roster = make()
        rows = self._finish(engine, roster, {"p0", "p1"})
        assert [r["rank"] for r in rows] == [1, 2, 3, 4]
        top = {r["playerID"]: r for r in rows}
        assert top["p0"]["brainScore"] == 100
        assert top["p0"]["brainTitle"] in bb.BRAIN_TITLES.values()
        assert top["p3"]["brainScore"] == 0
        assert top["p3"]["brainTitle"] == bb.FALLBACK_TITLE
        assert top["p3"]["personalBest"] is False
        priv = engine.private_state("p0")
        assert priv["brainTitle"] == top["p0"]["brainTitle"] and priv["rank"] in (1, 2)

    def test_personal_best_persisted_to_tmp_path(self, tmp_path):
        path = tmp_path / "brain_scores.json"
        assert os.environ["BRAIN_SCORES_PATH"] == str(path)
        engine, roster = make()
        rows = self._finish(engine, roster, {"p0"})
        p0 = next(r for r in rows if r["playerID"] == "p0")
        assert p0["personalBest"] is True and p0["previousBest"] is None
        saved = json.loads(path.read_text())
        assert saved["p0"]["best"] == 100
        assert "p3" not in saved               # a zero is never a record

        # Second game: matching the best is not a new record.
        engine2, roster2 = make(seed=11)
        rows2 = self._finish(engine2, roster2, {"p0", "p1"})
        p0 = next(r for r in rows2 if r["playerID"] == "p0")
        p1 = next(r for r in rows2 if r["playerID"] == "p1")
        assert p0["personalBest"] is False and p0["previousBest"] == 100
        assert p1["personalBest"] is True
        assert json.loads(path.read_text())["p1"]["best"] == 100

    def test_beating_an_old_best(self, tmp_path):
        path = tmp_path / "brain_scores.json"
        path.write_text(json.dumps({"p0": {"best": 40, "name": "P0"}}))
        engine, roster = make()
        rows = self._finish(engine, roster, {"p0"})
        p0 = next(r for r in rows if r["playerID"] == "p0")
        assert p0["personalBest"] is True and p0["previousBest"] == 40
        assert json.loads(path.read_text())["p0"]["best"] == 100

    def test_unwritable_path_is_best_effort(self, monkeypatch, tmp_path):
        blocker = tmp_path / "file"
        blocker.write_text("x")
        monkeypatch.setenv("BRAIN_SCORES_PATH", str(blocker / "nested" / "scores.json"))
        engine, roster = make()
        rows = self._finish(engine, roster, {"p0"})
        assert rows[0]["playerID"] == "p0"

    def test_early_results_do_not_persist(self, tmp_path):
        engine, roster = make()
        assert isinstance(engine.results(), list)
        assert not (tmp_path / "brain_scores.json").exists()


class TestBots:
    def test_bot_answers_with_a_valid_option(self):
        engine, roster = make(kinds="calendar")
        action = bots._policy_brain_battle(engine, "p0")
        assert action[0] == "answer"
        assert action[1]["choice"] in engine.puzzle["options"]

    def test_bot_waits_outside_answer_phase(self):
        engine, roster = make(kinds="memory")
        assert bots._policy_brain_battle(engine, "p0") is None
