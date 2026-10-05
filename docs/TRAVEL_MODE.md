# AuroraPlay Travel Mode

Car-optimized, voice-first party games. One phone hosts; the **passenger**
operates it; the **driver plays by voice only and never touches the phone**.
No TV required.

## The concept

Travel Mode is a mode of the Aurora Play phone app (GameLabController) for
car rides. The passenger opens Travel Mode, picks a game, and runs it for
everyone in the car. Prompts are shown big on the phone and can be read aloud
through the car's speakers. Scoring is a tap. The games are conversational on
purpose: trivia debates, collaborative stories, yes/no guessing, hot-take
arguments — the fun is in the talking, not in staring at a screen.

## The CarPlay reality (read this first)

Apple does **not** allow games on the CarPlay display. CarPlay app categories
are limited (audio, navigation, messaging, food ordering, EV charging, and a
few others) and there is **no games entitlement** — a game cannot render UI on
the car's head unit, and attempting CarPlay screen templates for a game would
be rejected.

So Travel Mode deliberately has **no CarPlay screen UI**. "CarPlay support"
means exactly one thing: the game's **audio** (text-to-speech prompts, sound
effects) routes through the car's speakers automatically when the iPhone is
connected via CarPlay or Bluetooth. This works with a normal
`AVAudioSession` playback session (`AVAudioSession.Category.playback`,
`.spokenAudio` mode) — no CarPlay entitlement, no head-unit code, no review
risk. The phone screen stays the passenger's job.

## How to play

**Roles**

- **Passenger = host/operator.** Holds the phone, picks the game and topic,
  taps Read Aloud, advances rounds, taps +1 to score.
- **Driver = voice only.** Answers, argues, guesses — out loud. The driver
  never handles the phone. This rule is shown as a persistent footer on every
  Travel Mode screen: "Driver: voice only — never touch the phone."

**Session flow**

1. Passenger opens Travel Mode (car icon) from the app's join screen.
2. Pick a game. For trivia, pick or type a topic.
3. Add players (roster starts with Driver and Passenger).
4. Play: prompts appear large; Read Aloud speaks them through the car
   speakers; the host scores with +1 buttons.
5. Results show a ranked scoreboard and a "Next Up" button that walks the
   travel playlist: trivia → most likely to → story chain →
   twenty questions → hot takes → wavelength.

## The games

All six are playable with one phone and zero screen time for the driver.

| Game | How it plays in the car |
|---|---|
| **Trivia** | Host reads (or plays aloud) questions on the picked topic; players shout answers; host scores. Questions come from Topic Mode (below). |
| **Most Likely To** | Prompts like "most likely to fall asleep at the wheel (as a passenger)". Everyone points / shouts a name; host scores. |
| **Wavelength** | One player is the psychic with a secret target on a spectrum (e.g. "hot — cold"); the team debates a number. Driver can be psychic — the secret stays masked on screen with tap-to-peek. |
| **Story Chain** | Players add one sentence each to a growing story, in turn order. At the end, everyone votes for the funniest contributor. |
| **Twenty Questions** | The engine picks a secret thing (places, foods, movies, animals). Players ask yes/no questions — 20 max. The answerer taps yes/no; a correct guess scores. Secret is masked on screen. |
| **Hot Takes** | Debate prompts ("Is a hot dog a sandwich?"). Timed discussion; the host awards points to the most convincing arguer. |

## Topic Mode (live questions)

Fixed question packs are the **fallback**, not the primary source. In Travel
Mode the passenger types or picks a free-text topic ("Tollywood movies",
"cricket", "world capitals") and the server generates fresh questions for it.

**Source priority** for `GET /api/travel/questions?topic=<text>&count=10`:

1. **Free trivia APIs (no key).** The topic is mapped to the closest Open
   Trivia DB category via a keyword map (with General Knowledge as the
   default). Questions are fetched in one batched request, HTML entities are
   decoded, text is cleaned for speech, and every question is validated
   (exactly 4 choices, exactly one correct, no emojis, TTS-clean). Free and
   no-key beats paid on principle.
2. **LLM generation** (the existing `google.generativeai` integration) — only
   for free-text topics that don't map to an API category. A topic that maps
   to a category never spends LLM budget.
3. **Bundled packs** (`content_packs.py`) — the final offline fallback.

**Efficiency rules:** questions are generated/fetched in batches (default 10,
never one per round-trip); per-topic results are cached aggressively
(in-memory plus a persisted `data/topic_cache.json`, gitignored) so replays
and follow-up rounds don't re-hit any API; every question is deduped against
the session's asked history (the rolling no-repeat history trivia already
uses). When the bundled fallback serves a request the response carries
`"fallback": true` and the phone shows a small "Using offline questions"
note — play never dead-ends.

The same chain (minus the multiple-choice API tier) feeds twenty-questions
secrets (`GET /api/travel/secrets`) and hot-takes prompts
(`GET /api/travel/hot_takes`). The phone can also fetch questions itself and
pass them in `create_room` as `seedQuestions`; the trivia engine prefers
`seedQuestions → topic → content pack`, with the no-repeat history applied at
every level.

## Audio

- Prompts are read with `AVSpeechSynthesizer` (`.playback` category,
  `.spokenAudio` mode, `.duckOthers` so car audio dips politely).
- This is what carries the game over CarPlay/Bluetooth car speakers. Nothing
  renders on the head unit — by design (see "The CarPlay reality" above).
- All game text is written TTS-clean: no emojis (repo-wide rule), no stage
  directions, no abbreviations that read badly aloud.

## Connectivity

The backend server is still required in V1 — Travel Mode runs over cellular
data or a phone hotspot. True offline play (engines on-device) is not
supported yet. If the server is unreachable, the phone falls back to its
bundled offline question deck and keeps playing.

## Safety

- The driver never handles the phone. Ever. The safety line is a persistent
  footer on every Travel Mode screen.
- Big high-contrast type and large touch targets so the passenger can operate
  one-handed without looking long.
- If you're the only adult in the car, don't run Travel Mode while driving —
  wait for a passenger or a rest stop.

## Voice quizmaster (v2)

Trivia no longer needs the passenger to tap. A turn-based voice loop runs
each question:

```
ASK (cloud TTS speaks) -> LISTEN (mic armed, 8 s) -> LOCK (first answer wins)
    -> GRADE (fuzzy match, then one tiny LLM call) -> next question
```

- The mic is armed **only** inside LISTEN -- deaf by design everywhere else,
  which is what keeps side conversations from derailing the game.
- The voice is cloud TTS (`GET /api/voice/tts`, OpenAI behind it, key kept
  server-side), streamed and disk-cached; the on-device voice is the offline
  fallback. Push-to-talk (hold the mic button) is the default in the car.
- Question repeats are killed three ways: OpenTDB session tokens, a
  persistent per-device served history on the server, and high-temperature
  LLM generation with an exclusion list.
- The same loop runs cross-device on the TV: the TV speaks through the TV
  speakers, one phone holds the mic (`claim_mic`), and `voice_state` /
  `voice_transcript` / `voice_verdict` socket events keep them in sync.
  tvOS gives third-party apps no mic access, so this split is mandatory.
- Cost: roughly $0.07 per 10-question game (Oct 2026 pricing), ~95% of it
  TTS. See `games/voice.py` and the PR description for the API-key setup.
