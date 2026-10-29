#!/usr/bin/env python3
"""Render the offline voice pack: one small audio clip per spoken sentence.

The TV and phone apps speak a lot of fixed text. Instead of paying a cloud
voice for it on every game, render it ONCE here and ship the clips inside the
app (ios/Shared/Voice/Pack/<key>.m4a). The apps look a sentence up by key; a
sentence with no clip (a player's name) is spoken live by the device voice.

    python3 tools/render_voice_pack.py --dry-run               # count + size
    python3 tools/render_voice_pack.py --engine tone --limit 20  # plumbing test
    python3 tools/render_voice_pack.py --engine piper --piper-model path/to/voice.onnx
    OPENAI_API_KEY=... python3 tools/render_voice_pack.py --engine openai

Engines
    openai  the same cloud voice the app uses today (games/voice.py), once per
            sentence; costs credits one time.
    elevenlabs  the ElevenLabs voice (Eleven v3 acts from audio tags such as
            [laughs]); needs ELEVENLABS_API_KEY and ELEVENLABS_VOICE_ID.
    piper   free, fully offline (https://github.com/rhasspy/piper, MIT; pin
            piper-tts==1.2.0). Check the licence of the voice model you pick.
    tone    a quiet beep, for testing the pipeline without any voice.

Needs ffmpeg on PATH. Re-running skips clips that already exist.

The splitting and hashing rules below MUST match
ios/Shared/Voice/VoicePack.swift (tests/test_voice_pack.py pins golden values).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

PACK_DIR = ROOT / "ios" / "Shared" / "Voice" / "Pack"


# ---------------------------------------------------------------------------
# the shared rules (mirror VoicePack.swift)
# ---------------------------------------------------------------------------

def pieces(text: str) -> list[str]:
    """Sentences: split after . ? ! when whitespace or the end follows."""
    out: list[str] = []
    current = ""
    chars = list(text)
    for i, ch in enumerate(chars):
        current += ch
        if ch in ".?!":
            at_end = i + 1 >= len(chars)
            if at_end or chars[i + 1].isspace():
                piece = current.strip()
                if piece:
                    out.append(piece)
                current = ""
    rest = current.strip()
    if rest:
        out.append(rest)
    return out


def normalized(piece: str) -> str:
    return " ".join(piece.lower().split())


def key(piece: str) -> str:
    return hashlib.sha256(normalized(piece).encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------------------
# what gets spoken
# ---------------------------------------------------------------------------

def _wyr() -> list[str]:
    from games import content_service as cs
    return [f"Would you rather {a}, or {b}?" for a, b in cs.all_items("would_rather")]


def _trivia() -> list[str]:
    """Trivia as the TV reads it: 'Question. A: one. B: two. C: three. D: four.'"""
    from games import content_service as cs
    from games.native_hub.engines.content_packs import questions_for
    out = []
    for _cat, question, options, _ans in questions_for("en", "trivia"):
        out.append(_read_question(question, options))
    for item in cs.all_items("mc"):
        out.append(_read_question(item["question"], item["options"]))
    return out


def _read_question(question: str, options: list[str]) -> str:
    letters = "ABCD"
    opts = ". ".join(f"{letters[i]}: {o}" for i, o in enumerate(options[:4]))
    return f"{question}. {opts}."


def _hot_takes() -> list[str]:
    from games import content_service as cs
    out = [f"The hot take: {p}" for p in cs.all_items("hot_take")]
    out += [f"Round {n}." for n in range(1, 13)]
    out += ["Time to vote. Who argued better?"]
    return out


def _truth_dare() -> list[str]:
    from games import content_service as cs
    out = []
    for kind in cs.KINDS:
        if kind.startswith("td_"):
            out.extend(cs.all_items(kind))
    return out


def _host_lies() -> list[str]:
    from games.native_hub.engines import _hostlies as H
    out = list(H.OPENERS) + list(H.DEFENCES) + list(H.REPEATS) + list(H.STALLS)
    for fact in H.FACTS:
        out.append(fact[0])   # the true line; the false twin is spoken with tells layered on
        out.append(fact[1])
    return out


def _bluff_and_prompts() -> list[str]:
    """Short prompts the TV reads out in party games."""
    from games import content_service as cs
    out = []
    for kind in ("herd", "most_likely", "meld_category", "draw_prompt"):
        out.extend(cs.all_items(kind))
    return out


def _nhie_and_songs() -> list[str]:
    """Never Have I Ever statements and Guess the Song humor, as the TV reads them."""
    from games import content_service as cs
    from games.native_hub.engines import _humor as H
    out = []
    for kind in cs.KINDS:
        if kind.startswith("nhie_"):
            out.extend(f"Never have I ever {t}." for t in cs.all_items(kind))
    for pack in H.PACKS.values():
        for key in ("guessed", "missed", "filler"):
            out.extend(pack[key])
    return out


SOURCES = {
    "nhie_songs": _nhie_and_songs,
    "wyr": _wyr,
    "trivia": _trivia,
    "hot_takes": _hot_takes,
    "truth_dare": _truth_dare,
    "host_lies": _host_lies,
    "prompts": _bluff_and_prompts,
}

#: Swift files whose plain string literals are sentences the apps speak.
SWIFT_FILES = [
    "ios/GameLabController/Views/PhonePlay/Mafia/MafiaViewModel.swift",
    "ios/GameLabController/Views/PhonePlay/MindGym/NeuroPulseFallback.swift",
    "ios/GameLabController/Views/PhonePlay/MindGym/NeuroPulseViewModel.swift",
    "ios/GameLabController/Views/Travel/TravelModeViewModel.swift",
    "ios/GameLabTV/Views/Games/TVPokerBoardView.swift",
    "ios/GameLabTV/Views/Games/TVTriviaBoardView.swift",
    "ios/GameLabTV/Views/Games/TVHotTakesBoardView.swift",
]

_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def scan_swift(files: list[str] | None = None) -> list[str]:
    """Plain (no interpolation) string literals that read like spoken lines."""
    out = []
    for rel in files or SWIFT_FILES:
        path = ROOT / rel
        if not path.is_file():
            continue
        for raw in _LITERAL.findall(path.read_text(encoding="utf-8")):
            if "\\(" in raw or "\\n" in raw:
                continue
            text = raw.replace('\\"', '"').strip()
            if (12 <= len(text) <= 240 and " " in text and text[0].isupper()
                    and text[-1] in ".?!" and text.count(" ") >= 2):
                out.append(text)
    return out


def show_host_lines() -> list[str]:
    """The Game Night show host's script (games/show_host.py): heard every night."""
    from games import show_host
    return show_host.all_lines()


def extra_lines() -> list[str]:
    path = Path(__file__).with_name("voice_lines.txt")
    if not path.is_file():
        return []
    return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()
            if ln.strip() and not ln.startswith("#")]


#: How each question source is read (games/voice_styles.py).
SOURCE_STYLES = {
    "nhie_songs": "playful",
    "wyr": "quiz",
    "trivia": "quiz",
    "hot_takes": "host",
    "truth_dare": "host",
    "host_lies": "roast",
    "prompts": "host",
}


def show_host_groups() -> list[tuple[str, list[str]]]:
    """The Game Night host's lines, each moment in its own style."""
    from games import show_host, voice_styles
    return [(voice_styles.for_moment(moment), list(lines))
            for moment, lines in show_host.LINES.items()]


def collect_styled(sources: list[str], swift: bool) -> tuple[dict[str, str], dict[str, str]]:
    """(key -> sentence, key -> style name), every sentence of every line once."""
    # Game narration first (Mafia, poker, Travel Mode...): a few hundred short
    # lines heard in every game. The question banks after it run to thousands,
    # so a run with --limit or --max-mb covers the narration before them.
    groups: list[tuple[str, list[str]]] = []
    if swift:
        groups.append(("narrator", scan_swift()))
        groups.extend(show_host_groups())
    groups.append(("host", extra_lines()))
    for name in sources:
        groups.append((SOURCE_STYLES.get(name, "host"), SOURCES[name]()))
    clips: dict[str, str] = {}
    styles: dict[str, str] = {}
    for style, lines in groups:
        for line in lines:
            for piece in pieces(str(line)):
                if len(piece) < 3 or not any(c.isalpha() for c in piece):
                    continue
                k = key(piece)
                if k not in clips:
                    clips[k] = piece
                    styles[k] = style
    return clips, styles


def collect(sources: list[str], swift: bool) -> dict[str, str]:
    """key -> sentence, for every sentence of every line (deduplicated)."""
    return collect_styled(sources, swift)[0]


# ---------------------------------------------------------------------------
# engines
# ---------------------------------------------------------------------------

#: Cut the silence a voice leaves before and after a sentence, then add back a
#: short, even tail. Clips play one after another, so untrimmed silence stacked
#: into odd pauses between sentences; this leaves one natural beat.
TRIM = ("silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,"
        "areverse,"
        "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,"
        "areverse,"
        "apad=pad_dur=0.14")


def _ffmpeg(src: Path, dest: Path, extra: list[str] | None = None) -> None:
    cmd = ["ffmpeg", "-y", "-loglevel", "error", *(extra or []), "-i", str(src),
           "-af", TRIM, "-ac", "1", "-ar", "24000", "-c:a", "aac", "-b:a", "32k", str(dest)]
    subprocess.run(cmd, check=True)


def render_tone(text: str, dest: Path, style: str | None = None) -> None:
    # Length roughly follows the text so timing in the app feels real.
    seconds = max(0.4, min(8.0, len(text) / 15.0))
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
           f"sine=frequency=330:duration={seconds:.2f}", "-af", "volume=0.05",
           "-ac", "1", "-ar", "24000", "-c:a", "aac", "-b:a", "32k", str(dest)]
    subprocess.run(cmd, check=True)


def render_openai(text: str, dest: Path, style: str | None = None) -> None:
    os.environ.setdefault("TTS_DAILY_CHAR_CAP", "50000000")
    os.environ.setdefault("TTS_CACHE_PATH", str(Path(tempfile.gettempdir()) / "voice_pack_tts_cache"))
    from games.voice import synthesize_speech
    audio, _source = synthesize_speech(text, style=style)
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
        tmp.write(audio)
    try:
        _ffmpeg(Path(tmp.name), dest)
    finally:
        os.unlink(tmp.name)


def render_elevenlabs(text: str, dest: Path, style: str | None = None) -> None:
    """The ElevenLabs voice (games/voice.py), once per sentence."""
    os.environ["TTS_PROVIDER"] = "elevenlabs"
    os.environ.setdefault("TTS_DAILY_CHAR_CAP", "50000000")
    os.environ.setdefault("TTS_CACHE_PATH", str(Path(tempfile.gettempdir()) / "voice_pack_tts_cache"))
    from games.voice import synthesize_speech
    audio, _source = synthesize_speech(text, style=style)
    with tempfile.NamedTemporaryFile(suffix=".mp3", delete=False) as tmp:
        tmp.write(audio)
    try:
        _ffmpeg(Path(tmp.name), dest)
    finally:
        os.unlink(tmp.name)


def make_piper_renderer(model: str):
    piper = shutil.which("piper")
    if not piper:
        sys.exit("piper not found on PATH (pip install piper-tts==1.2.0)")

    def render(text: str, dest: Path, style: str | None = None) -> None:
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            wav = Path(tmp.name)
        try:
            subprocess.run([piper, "--model", model, "--output_file", str(wav)],
                           input=text.encode("utf-8"), check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            _ffmpeg(wav, dest)
        finally:
            wav.unlink(missing_ok=True)
    return render


# ---------------------------------------------------------------------------

#: A few lines in every style, to hear before paying for the whole pack.
AUDITION = [
    ("welcome", "Welcome, everyone, to Aanya's birthday night! Tonight, you are all on the show."),
    ("hype", "Oh, it is neck and neck! One game left, and anyone can win it."),
    ("roast", "Nobody got that one. Not one of you. I am not angry, just disappointed."),
    ("playful", "And the crowd goes wild! That is a win for the red team."),
    ("finale", "And tonight's champion is... Kavya! Give her a round of applause."),
    ("narrator", "Everyone, close your eyes. The Mafia is waking up."),
    ("quiz", "Which planet is known as the Red Planet? A: Mars. B: Venus. C: Jupiter. D: Saturn."),
    ("indian", "Your word is Baarish. Sing a song with the word, or its meaning."),
    ("indian", "Your word is Vaana. Think of a Telugu song with rain in it."),
    ("kids", "Great job! You got three right. Ready for the next one?"),
]


def audition(out_dir: Path, engine: str = "openai") -> int:
    """Render AUDITION with the OpenAI or ElevenLabs voice into ``out_dir`` and stop."""
    render = render_elevenlabs if engine == "elevenlabs" else render_openai
    out_dir.mkdir(parents=True, exist_ok=True)
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg not found on PATH")
    for i, (style, text) in enumerate(AUDITION, 1):
        dest = out_dir / f"{i:02d}-{style}.m4a"
        render(text, dest, style)
        print(f"  {dest.name}: {text[:60]}")
    print(f"wrote {len(AUDITION)} clips to {out_dir}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", choices=["openai", "elevenlabs", "piper", "tone"], default="openai")
    ap.add_argument("--piper-model", help="path to a Piper .onnx voice (with its .json beside it)")
    ap.add_argument("--sources", default=",".join(SOURCES), help=f"comma list of: {', '.join(SOURCES)}")
    ap.add_argument("--no-swift", action="store_true", help="skip string literals scanned from the Swift files")
    ap.add_argument("--limit", type=int, default=0, help="render at most N new clips")
    ap.add_argument("--force", action="store_true", help="re-render clips that already exist")
    ap.add_argument("--max-mb", type=float, default=0, help="stop when the pack reaches this size")
    ap.add_argument("--out", help="write clips here instead of ios/Shared/Voice/Pack (for tests)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--audition", metavar="DIR",
                    help="render a few lines in every style with the OpenAI voice into DIR, then stop")
    args = ap.parse_args()
    if args.audition:
        return audition(Path(args.audition), args.engine)

    names = [s for s in args.sources.split(",") if s]
    unknown = [s for s in names if s not in SOURCES]
    if unknown:
        ap.error(f"unknown sources: {unknown}")
    global PACK_DIR
    if args.out:
        PACK_DIR = Path(args.out)
    clips, styles = collect_styled(names, swift=not args.no_swift)
    PACK_DIR.mkdir(parents=True, exist_ok=True)
    have = {p.stem for p in PACK_DIR.glob("*.m4a")}
    todo = [k for k in clips if args.force or k not in have]
    chars = sum(len(clips[k]) for k in todo)
    by_style: dict[str, int] = {}
    for k in todo:
        by_style[styles.get(k, "host")] = by_style.get(styles.get(k, "host"), 0) + 1
    print("by style: " + ", ".join(f"{s} {n}" for s, n in sorted(by_style.items())))
    print(f"{len(clips)} sentences, {len(have & set(clips))} already rendered, {len(todo)} to render "
          f"({chars:,} characters; about {len(todo) * 9 / 1024:.0f} MB at ~9 KB each)")
    if args.dry_run or not todo:
        return 0
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg not found on PATH")

    if args.engine == "openai":
        render = render_openai
    elif args.engine == "elevenlabs":
        render = render_elevenlabs
    elif args.engine == "piper":
        if not args.piper_model:
            sys.exit("--piper-model is required for the piper engine")
        render = make_piper_renderer(args.piper_model)
    else:
        render = render_tone

    done = 0
    for k in todo:
        if args.limit and done >= args.limit:
            break
        if args.max_mb and _pack_mb() >= args.max_mb:
            print(f"reached {args.max_mb} MB, stopping")
            break
        dest = PACK_DIR / f"{k}.m4a"
        try:
            render(clips[k], dest, styles.get(k))
        except Exception as exc:   # one bad line must not lose the rest
            print(f"  skipped {k} ({clips[k][:50]!r}): {exc}")
            dest.unlink(missing_ok=True)
            continue
        done += 1
        if done % 50 == 0:
            print(f"  {done}/{len(todo)}")
    write_index(clips, args.engine)
    print(f"rendered {done} clips; pack is now {_pack_mb():.1f} MB")
    return 0


def _pack_mb() -> float:
    return sum(p.stat().st_size for p in PACK_DIR.glob("*.m4a")) / (1024 * 1024)


def write_index(clips: dict[str, str], engine: str) -> None:
    """voicepack.json: which sentence each clip says (for review, and so the
    next run knows what exists). Shipped in the app; a few hundred KB."""
    have = {p.stem for p in PACK_DIR.glob("*.m4a")}
    (PACK_DIR / "voicepack.json").write_text(json.dumps({
        "version": 1,
        "engine": engine,
        "clips": {k: clips[k] for k in sorted(have) if k in clips},
    }, ensure_ascii=False, indent=0), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
