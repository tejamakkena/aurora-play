"""The offline voice pack: the sentence/hash rules and the renderer's line list."""

import importlib.util
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("render_voice_pack", ROOT / "tools" / "render_voice_pack.py")
rvp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rvp)


def test_sentences_split_after_terminators_followed_by_space_or_end():
    assert rvp.pieces("Hi there.  Second one? Yes!") == ["Hi there.", "Second one?", "Yes!"]
    assert rvp.pieces("Teja chose truth. What is the silliest thing?") == [
        "Teja chose truth.", "What is the silliest thing?"]
    assert rvp.pieces("No terminator here") == ["No terminator here"]
    assert rvp.pieces("It costs 3.5 rupees. Fine.") == ["It costs 3.5 rupees.", "Fine."]
    assert rvp.pieces("   ") == []


def test_key_ignores_case_and_spacing_only():
    assert rvp.key("Hello,   World!  ") == rvp.key("hello, world!")
    assert rvp.key("Hello, World!") != rvp.key("Hello World!")
    assert len(rvp.key("x")) == 16


def test_swift_and_python_agree_on_the_golden_values():
    """VoicePack.selfCheck() asserts these in debug builds; keep both in step."""
    swift = (ROOT / "ios" / "Shared" / "Voice" / "VoicePack.swift").read_text()
    golden = re.search(r'key\(for: "Hello,   World!  "\) == "([0-9a-f]{16})"', swift)
    assert golden and rvp.key("Hello,   World!  ") == golden.group(1)
    assert 'pieces(of: "Hi there.  Second one? Yes!") == ["Hi there.", "Second one?", "Yes!"]' in swift


def test_trivia_is_read_the_way_the_tv_reads_it():
    assert rvp._read_question("What is 2+2?", ["3", "4", "5", "6"]) == "What is 2+2?. A: 3. B: 4. C: 5. D: 6."
    # The TV builds "<question>. A: ...", so the first sentence ends in "?." and the rest follow.
    assert rvp.pieces(rvp._read_question("What is 2+2?", ["3", "4", "5", "6"])) == [
        "What is 2+2?.", "A: 3.", "B: 4.", "C: 5.", "D: 6."]


def test_every_source_yields_clean_sentences():
    clips = rvp.collect(list(rvp.SOURCES), swift=True)
    assert len(clips) > 3000
    for k, text in list(clips.items())[:5000]:
        assert len(k) == 16 and text.strip() == text and len(text) >= 3


def test_wyr_lines_match_what_the_tv_speaks():
    from games import content_service as cs
    a, b = cs.all_items("would_rather")[0]
    clips = rvp.collect(["wyr"], swift=False)
    assert rvp.key(f"Would you rather {a}, or {b}?") in clips


def test_swift_scan_keeps_plain_spoken_lines_only():
    lines = rvp.scan_swift()
    assert all("\\(" not in line for line in lines)
    assert all(line[-1] in ".?!" for line in lines)


@pytest.mark.skipif(not shutil.which("ffmpeg"), reason="ffmpeg not installed")
def test_tone_engine_writes_playable_clips_and_an_index(tmp_path):
    out = subprocess.run(
        ["python3", str(ROOT / "tools" / "render_voice_pack.py"), "--engine", "tone",
         "--sources", "wyr", "--no-swift", "--limit", "3", "--out", str(tmp_path)],
        capture_output=True, text=True, cwd=ROOT)
    assert out.returncode == 0, out.stderr
    clips = sorted(tmp_path.glob("*.m4a"))
    assert len(clips) == 3 and all(c.stat().st_size > 1000 for c in clips)
    import json
    index = json.loads((tmp_path / "voicepack.json").read_text())
    assert set(index["clips"]) == {c.stem for c in clips}
    # Re-running renders nothing already there.
    again = subprocess.run(
        ["python3", str(ROOT / "tools" / "render_voice_pack.py"), "--engine", "tone",
         "--sources", "wyr", "--no-swift", "--limit", "3", "--out", str(tmp_path)],
        capture_output=True, text=True, cwd=ROOT)
    assert len(list(tmp_path.glob("*.m4a"))) == 6


def test_the_shipped_pack_never_contains_test_tones():
    index = ROOT / "ios" / "Shared" / "Voice" / "Pack" / "voicepack.json"
    import json
    assert json.loads(index.read_text())["engine"] != "tone"
