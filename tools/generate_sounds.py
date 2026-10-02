#!/usr/bin/env python3
"""Generate GameLab TV's sound effects as 16-bit PCM WAV files.

Committed alongside its output so the assets are reproducible rather than
opaque binaries: re-run this to regenerate or tweak them.

    python3 tools/generate_sounds.py

Everything here is stdlib-only (``math``, ``random``, ``struct``, ``wave``)
so it runs anywhere without a numpy/audio dependency.
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44_100
OUT_DIR = os.path.join("ios", "GameLabTV", "Resources", "Sounds")


def write_wav(name: str, samples: list[float]) -> None:
    """Write mono 16-bit PCM, clipped to [-1, 1] with a little headroom."""
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    frames = bytearray()
    for s in samples:
        clipped = max(-1.0, min(1.0, s * 0.9))
        frames += struct.pack("<h", int(clipped * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(bytes(frames))
    print(f"{path}  ({len(samples) / SAMPLE_RATE:.2f}s, {len(frames) // 1024} KiB)")


def crossfade_loop(samples: list[float], fade_seconds: float = 0.12) -> list[float]:
    """Make a clip loop seamlessly by folding its tail back over its head."""
    fade = int(SAMPLE_RATE * fade_seconds)
    if fade * 2 >= len(samples):
        return samples
    out = samples[:-fade]
    for i in range(fade):
        t = i / fade
        out[i] = out[i] * t + samples[len(samples) - fade + i] * (1 - t)
    return out


def ball_click() -> list[float]:
    """The ball ticking over a fret: a very short, bright transient."""
    duration = 0.028
    n = int(SAMPLE_RATE * duration)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 190)
        tone = math.sin(2 * math.pi * 2_300 * t) * 0.55
        tone += math.sin(2 * math.pi * 3_700 * t) * 0.25
        noise = (random.random() * 2 - 1) * 0.35
        out.append((tone + noise) * env)
    return out


def spin_loop() -> list[float]:
    """The wheel itself: a low whirr that loops under the whole spin."""
    duration = 2.0                       # exact cycles at 80/120/200 Hz
    n = int(SAMPLE_RATE * duration)
    out = []
    # A slow-moving low-pass on the noise, done as a one-pole filter so the
    # rumble sits under the tone rather than hissing over it.
    filtered = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        body = (
            math.sin(2 * math.pi * 80 * t) * 0.30
            + math.sin(2 * math.pi * 120 * t) * 0.16
            + math.sin(2 * math.pi * 200 * t) * 0.08
        )
        noise = random.random() * 2 - 1
        filtered += (noise - filtered) * 0.035
        # Gentle tremolo so it reads as rotation, not a held organ note.
        tremolo = 0.85 + 0.15 * math.sin(2 * math.pi * 6 * t)
        out.append((body + filtered * 0.5) * tremolo * 0.5)
    return crossfade_loop(out)


def win_fanfare() -> list[float]:
    """Played when the winning number lands."""
    notes = [(523.25, 0.00), (659.25, 0.10), (783.99, 0.20), (1046.50, 0.32)]
    duration = 1.7
    n = int(SAMPLE_RATE * duration)
    out = [0.0] * n
    for freq, start in notes:
        offset = int(SAMPLE_RATE * start)
        for i in range(offset, n):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 3.1) * (1 - math.exp(-t * 260))
            # Bell-ish: fundamental plus a quieter, faster-decaying octave.
            v = math.sin(2 * math.pi * freq * t) * 0.5
            v += math.sin(2 * math.pi * freq * 2 * t) * 0.18 * math.exp(-t * 5.5)
            v += math.sin(2 * math.pi * freq * 3.01 * t) * 0.07 * math.exp(-t * 8)
            out[i] += v * env * 0.42
    # A little sparkle over the top of the final chord.
    for i in range(int(SAMPLE_RATE * 0.32), n):
        t = (i - SAMPLE_RATE * 0.32) / SAMPLE_RATE
        env = math.exp(-t * 4.5)
        out[i] += math.sin(2 * math.pi * 2_093 * t) * 0.07 * env
    return out


def coin_drop() -> list[float]:
    """A Connect 4 disc landing in its slot: a short low wooden thud with a
    brief higher-pitched plastic-on-plastic clack riding on top of it."""
    duration = 0.22
    n = int(SAMPLE_RATE * duration)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        thud_env = math.exp(-t * 34)
        thud = math.sin(2 * math.pi * 140 * t) * thud_env * 0.6
        thud += math.sin(2 * math.pi * 90 * t) * thud_env * 0.35
        clack_env = math.exp(-t * 95)
        clack = math.sin(2 * math.pi * 1_900 * t) * clack_env * 0.3
        clack += (random.random() * 2 - 1) * clack_env * 0.28
        out.append(thud + clack)
    return out


def main() -> None:
    random.seed(7)          # deterministic output across regenerations
    write_wav("roulette_click.wav", ball_click())
    write_wav("roulette_spin.wav", spin_loop())
    write_wav("win_fanfare.wav", win_fanfare())
    write_wav("connect4_drop.wav", coin_drop())
    write_wav("snake_bite.wav", snake_bite())
    write_wav("ladder_climb.wav", ladder_climb())


def snake_bite() -> list[float]:
    """A snake strike, for the Snakes & Ladders TV board: a sharp snapping
    transient at the lunge, then a descending warning hiss as the token is
    dragged down. The falling pitch reads as danger, not reward."""
    random.seed(11)          # local seed: deterministic whatever main() does
    duration = 0.75
    n = int(SAMPLE_RATE * duration)
    out = [0.0] * n
    hiss_lp = 0.0            # one-pole low-pass state for the hiss bed
    for i in range(n):
        t = i / SAMPLE_RATE
        # Snap: bright noise burst plus a low thud, both dying fast.
        snap_env = math.exp(-t * 60)
        v = (random.random() * 2 - 1) * snap_env * 0.55
        v += math.sin(2 * math.pi * 110 * t) * snap_env * 0.5
        # Hiss: noise through a low-pass whose cutoff falls with the pitch
        # sweep, so the whole texture darkens as the snake settles.
        k = t / duration
        cutoff = 0.55 - 0.38 * k
        noise = random.random() * 2 - 1
        hiss_lp += (noise - hiss_lp) * cutoff
        hiss_env = math.exp(-t * 4.5) * min(1.0, t * 40)
        v += hiss_lp * hiss_env * 1.1
        # Descending whistle 900 -> 300 Hz with a little vibrato.
        sweep = 900 - 600 * k
        vibrato = 1 + 0.06 * math.sin(2 * math.pi * 28 * t)
        v += math.sin(2 * math.pi * sweep * vibrato * t) * hiss_env * 0.28
        out[i] = v * 0.5
    return out


def ladder_climb() -> list[float]:
    """A pleasant ascending chime for the Snakes & Ladders TV board: five
    bell-like notes climbing a major arpeggio. Shorter and brighter than
    win_fanfare so a ladder never reads as the game being over."""
    notes = [523.25, 659.25, 783.99, 1046.50, 1318.51]
    duration = 1.3
    n = int(SAMPLE_RATE * duration)
    out = [0.0] * n
    for idx, freq in enumerate(notes):
        offset = int(SAMPLE_RATE * idx * 0.11)
        for i in range(offset, n):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 4.2) * (1 - math.exp(-t * 320))
            v = math.sin(2 * math.pi * freq * t) * 0.5
            v += math.sin(2 * math.pi * freq * 2 * t) * 0.16 * math.exp(-t * 7)
            v += math.sin(2 * math.pi * freq * 3.01 * t) * 0.06 * math.exp(-t * 10)
            out[i] += v * env * 0.34
    return out


if __name__ == "__main__":
    main()
