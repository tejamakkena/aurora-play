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
    """The full game-win fanfare for the TV: a bright ascending major
    arpeggio (C5 E5 G5 C6 E6) that lands on a triumphant held C-major
    chord with a sparkle shimmer over the top, ~2.2 s. Bigger and longer
    than ``ladder_climb`` so only this reads as the game being over.
    Played via ``SoundPlayer.Effect.winFanfare`` wherever a TV game
    announces a winner (Snakes & Ladders, Roulette, Classic games)."""
    rng = random.Random(21)  # private instance: never disturbs the global
                             # sequence other generators rely on
    duration = 2.2
    n = int(SAMPLE_RATE * duration)
    out = [0.0] * n

    def bell(start: float, freq: float, length: float, level: float) -> None:
        offset = int(SAMPLE_RATE * start)
        count = int(SAMPLE_RATE * length)
        for i in range(offset, min(n, offset + count)):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 2.6) * (1 - math.exp(-t * 260))
            # Bright bell: fundamental plus quicker-decaying upper partials.
            v = math.sin(2 * math.pi * freq * t) * 0.50
            v += math.sin(2 * math.pi * freq * 2 * t) * 0.20 * math.exp(-t * 4.5)
            v += math.sin(2 * math.pi * freq * 2.76 * t) * 0.10 * math.exp(-t * 7)
            v += math.sin(2 * math.pi * freq * 5.40 * t) * 0.05 * math.exp(-t * 10)
            out[i] += v * env * level

    # Ascending major arpeggio: C5 E5 G5 C6 E6, bells ringing over.
    arpeggio = [523.25, 659.25, 783.99, 1046.50, 1318.51]
    for idx, freq in enumerate(arpeggio):
        bell(idx * 0.11, freq, 1.6, 0.40)

    # The landing: a full C-major chord struck as the arpeggio tops out,
    # held longer so the win feels resolved rather than trailing off.
    chord = [261.63, 329.63, 392.00, 523.25, 659.25, 783.99]
    for freq in chord:
        bell(0.55, freq, 1.65, 0.34)

    # Celebratory burst at the chord hit: a short filtered noise pop.
    pop_start = int(SAMPLE_RATE * 0.55)
    for i in range(pop_start, min(n, pop_start + int(SAMPLE_RATE * 0.25))):
        t = (i - pop_start) / SAMPLE_RATE
        env = math.exp(-t * 26)
        out[i] += (rng.random() * 2 - 1) * env * 0.10

    # Sparkle shimmer over the held chord: high sine glints, staggered.
    for idx, (start, freq) in enumerate([(0.62, 2_093.0), (0.78, 2_639.0), (0.94, 3_136.0)]):
        offset = int(SAMPLE_RATE * start)
        for i in range(offset, n):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 4.0)
            out[i] += math.sin(2 * math.pi * freq * t) * 0.07 * env
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
    write_wav("snake_doom_sting.wav", snake_doom_sting())
    write_wav("ladder_climb.wav", ladder_climb())
    # Poker table (each uses a private RNG, so the clips above stay
    # byte-identical when this script is re-run).
    write_wav("poker_chips.wav", poker_chips())
    write_wav("poker_card.wav", poker_card())
    write_wav("poker_check.wav", poker_check())
    write_wav("poker_fold.wav", poker_fold())
    write_wav("poker_allin.wav", poker_allin())
    write_wav("poker_lounge.wav", poker_lounge())


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


def snake_doom_sting() -> list[float]:
    """A dramatic doom sting for a snake bite on the Snakes & Ladders TV
    board: low percussive hits under a descending minor motif, dark and
    cinematic. Layered with (not replacing) ``snake_bite``'s snap and hiss
    when the bite cinematic fires -- the bite is the strike, this is the
    dread that follows the token down the body."""
    random.seed(7)           # local seed: deterministic whatever main() does
    duration = 2.6
    n = int(SAMPLE_RATE * duration)
    out = [0.0] * n

    def add_note(start: float, freq: float, length: float, level: float) -> None:
        offset = int(SAMPLE_RATE * start)
        count = int(SAMPLE_RATE * length)
        for i in range(offset, min(n, offset + count)):
            t = (i - offset) / SAMPLE_RATE
            attack = 1 - math.exp(-t * 18)
            env = attack * math.exp(-t * 1.6)
            # Slightly detuned pair for a dark chorus width.
            v = math.sin(2 * math.pi * freq * t) * 0.55
            v += math.sin(2 * math.pi * freq * 1.005 * t) * 0.30
            v += math.sin(2 * math.pi * freq * 2 * t) * 0.14 * math.exp(-t * 3)
            out[i] += v * env * level

    def add_hit(start: float, level: float) -> None:
        offset = int(SAMPLE_RATE * start)
        count = int(SAMPLE_RATE * 0.5)
        for i in range(offset, min(n, offset + count)):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 22)
            thud = math.sin(2 * math.pi * 55 * t) * 0.8
            thud += math.sin(2 * math.pi * 82.5 * t) * 0.3
            noise = (random.random() * 2 - 1) * 0.25
            out[i] += (thud + noise) * env * level

    # Descending minor tetrachord -- A2, G2, F2, E2 -- the "doom" motif.
    motif = [(0.00, 110.00), (0.55, 98.00), (1.10, 87.31), (1.65, 82.41)]
    for start, freq in motif:
        add_note(start, freq, 1.1, 0.5)
    # Percussive hits under beats 1 and 3, plus a final punctuation hit.
    add_hit(0.0, 0.9)
    add_hit(1.1, 0.7)
    add_hit(2.2, 1.0)
    # Low 55 Hz drone swelling under the whole sting.
    for i in range(n):
        t = i / SAMPLE_RATE
        swell = min(1.0, t * 2.5) * math.exp(-max(0.0, t - 1.8) * 2.5)
        out[i] += math.sin(2 * math.pi * 55 * t) * swell * 0.18
    return [v * 0.55 for v in out]


def _noise_burst(rng: random.Random, n: int, decay: float, tone_hz: float = 0.0,
                 tone_level: float = 0.0, hp: float = 0.0) -> list[float]:
    """Decaying noise with an optional tone; ``hp`` (0..1) is a one-pole
    high-pass amount that makes it sound crisper / more papery."""
    out = []
    prev_in = 0.0
    prev_out = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        x = rng.random() * 2 - 1
        if hp:
            y = hp * (prev_out + x - prev_in)
            prev_in, prev_out = x, y
            x = y
        env = math.exp(-t * decay)
        v = x * env
        if tone_hz:
            v += math.sin(2 * math.pi * tone_hz * t) * tone_level * env
        out.append(v)
    return out


def _mix(out: list[float], clip: list[float], start: float, level: float) -> None:
    offset = int(SAMPLE_RATE * start)
    for i, v in enumerate(clip):
        if offset + i >= len(out):
            break
        out[offset + i] += v * level


def poker_chips() -> list[float]:
    """A little stack of clay chips being dropped: three quick clacks."""
    rng = random.Random(31)
    out = [0.0] * int(SAMPLE_RATE * 0.32)
    for start, hz, level in ((0.0, 2_400, 0.7), (0.045, 3_100, 0.55), (0.095, 2_700, 0.45),
                             (0.15, 3_400, 0.3)):
        _mix(out, _noise_burst(rng, int(SAMPLE_RATE * 0.05), 120, hz, 0.8, hp=0.6),
             start, level)
    return out


def poker_card() -> list[float]:
    """A card flicked across felt: a short papery swish."""
    rng = random.Random(32)
    n = int(SAMPLE_RATE * 0.16)
    clip = _noise_burst(rng, n, 26, hp=0.85)
    for i in range(n):
        t = i / n
        clip[i] *= math.sin(math.pi * min(1.0, t * 1.4)) * 0.8
    return clip


def poker_check() -> list[float]:
    """Knuckles tapping the table twice."""
    rng = random.Random(33)
    out = [0.0] * int(SAMPLE_RATE * 0.34)
    for start in (0.0, 0.13):
        n = int(SAMPLE_RATE * 0.12)
        thump = [math.sin(2 * math.pi * 170 * (i / SAMPLE_RATE)) * math.exp(-(i / SAMPLE_RATE) * 38)
                 for i in range(n)]
        click = _noise_burst(rng, n, 160, hp=0.5)
        _mix(out, [a * 0.9 + b * 0.35 for a, b in zip(thump, click)], start, 0.9)
    return out


def poker_fold() -> list[float]:
    """Cards tossed in: a falling swish."""
    rng = random.Random(34)
    n = int(SAMPLE_RATE * 0.38)
    out = []
    low = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        x = rng.random() * 2 - 1
        # A low-pass whose cutoff falls, so the swish sinks away.
        a = max(0.04, 0.5 - t * 1.1)
        low += a * (x - low)
        out.append(low * math.exp(-t * 6) * (1 - math.exp(-t * 90)) * 1.6)
    return out


def poker_allin() -> list[float]:
    """The big shove: a low swell, a rush of chips and a bright bell."""
    rng = random.Random(35)
    n = int(SAMPLE_RATE * 1.5)
    out = [0.0] * n
    for i in range(n):
        t = i / SAMPLE_RATE
        swell = min(1.0, t * 1.6) * math.exp(-max(0.0, t - 0.7) * 3.2)
        out[i] += (math.sin(2 * math.pi * 82.4 * t) * 0.5 + math.sin(2 * math.pi * 123.5 * t) * 0.25) * swell * 0.55
    for k in range(9):
        _mix(out, _noise_burst(rng, int(SAMPLE_RATE * 0.05), 120, 2_300 + 150 * (k % 4), 0.8, hp=0.6),
             0.25 + k * 0.06, 0.5)
    for freq, level in ((659.25, 0.34), (987.77, 0.26), (1318.5, 0.16)):
        offset = int(SAMPLE_RATE * 0.8)
        for i in range(offset, min(n, offset + int(SAMPLE_RATE * 0.7))):
            t = (i - offset) / SAMPLE_RATE
            out[i] += math.sin(2 * math.pi * freq * t) * math.exp(-t * 5.5) * level
    return out


def poker_lounge() -> list[float]:
    """A soft, looping lounge-jazz bed for the poker table: electric-piano
    chords (Dm7, G7, Cmaj7, A7) over a walking bass and brushed hats, 84 bpm,
    ~11.4 s, meant to sit quietly under the game."""
    rng = random.Random(36)
    bpm = 84
    beat = 60.0 / bpm
    bars = 4
    total = bars * 4 * beat
    n = int(SAMPLE_RATE * total)
    out = [0.0] * n

    def midi(m: float) -> float:
        return 440.0 * 2 ** ((m - 69) / 12)

    def epiano(start: float, length: float, freq: float, level: float) -> None:
        offset = int(SAMPLE_RATE * start)
        count = int(SAMPLE_RATE * length)
        for i in range(offset, min(n, offset + count)):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 2.4) * (1 - math.exp(-t * 90))
            v = math.sin(2 * math.pi * freq * t)
            v += 0.35 * math.sin(2 * math.pi * freq * 2 * t) * math.exp(-t * 4)
            v += 0.12 * math.sin(2 * math.pi * freq * 4.02 * t) * math.exp(-t * 9)
            out[i] += v * env * level

    def bass(start: float, length: float, freq: float, level: float) -> None:
        offset = int(SAMPLE_RATE * start)
        count = int(SAMPLE_RATE * length)
        for i in range(offset, min(n, offset + count)):
            t = (i - offset) / SAMPLE_RATE
            env = math.exp(-t * 3.2) * (1 - math.exp(-t * 120))
            out[i] += (math.sin(2 * math.pi * freq * t)
                       + 0.3 * math.sin(2 * math.pi * freq * 2 * t)) * env * level

    # (chord tones as midi, bass walk as midi) per bar
    bars_def = [
        ([62, 65, 69, 72], [38, 41, 45, 43]),   # Dm7
        ([55, 59, 62, 65], [43, 47, 50, 47]),   # G7
        ([60, 64, 67, 71], [36, 40, 43, 40]),   # Cmaj7
        ([61, 64, 67, 71], [45, 49, 52, 49]),   # A7
    ]
    for bar, (chord, walk) in enumerate(bars_def):
        t0 = bar * 4 * beat
        # Comp on beat 1 and the "and" of 2, the classic lounge feel.
        for tone in chord:
            epiano(t0, beat * 1.8, midi(tone), 0.10)
            epiano(t0 + beat * 2.5, beat * 1.2, midi(tone), 0.07)
        for step, note in enumerate(walk):
            bass(t0 + step * beat, beat * 0.95, midi(note), 0.30)
        # Brushed hat on 2 and 4 (and a ghost on the offbeats).
        for step in range(4):
            level = 0.07 if step in (1, 3) else 0.03
            _mix(out, _noise_burst(rng, int(SAMPLE_RATE * 0.07), 55, hp=0.9),
                 t0 + step * beat, level)
            _mix(out, _noise_burst(rng, int(SAMPLE_RATE * 0.05), 70, hp=0.9),
                 t0 + step * beat + beat * 0.66, 0.025)
    return crossfade_loop([v * 0.7 for v in out], 0.25)


if __name__ == "__main__":
    main()
