# AuroraPlay Travel Mode

A talking road-trip quizmaster on one phone. It asks riddles and fun quiz
questions out loud, and everyone in the car shouts the answers. No TV, no
roster, no room code, no setup.

## How to play

1. Open **Travel Mode** (car icon) on the Aurora Play join screen.
2. Tap **Riddles**, **Quiz** or **Mix it up**. That is the only choice.
3. Listen and shout. The quizmaster runs the rest by itself:

```
ASK (spoken) -> LISTEN (mic, ~9 s) -> react
  right answer      -> cheer + fun fact -> next question
  wrong / silence   -> a joke + a hint  -> listen again
  still wrong       -> "one more guess" -> listen again
  out of guesses    -> reveal + fun fact -> next question
```

Every ten questions it reads out the car's score.

**Say it instead of tapping:** "hint", "repeat", "skip" or "I give up".
The buttons on screen (Hint, Answer, Next, We got it!, Pause) are optional
shortcuts for a passenger. Nothing needs the driver's hands.

**No mic permission?** The same loop runs on a thinking-time countdown:
question, ten seconds, hint, eight seconds, answer.

## Content

- `ios/GameLabController/Views/Travel/TravelDeck.swift`: bundled,
  family-friendly riddles and fun-fact questions, so play works with no
  signal at all. Each item has the answer, other accepted ways of saying it,
  a hint, and an optional fun fact or punchline.
- **Fresh items:** `POST /api/travel/items` (`games/travel_items.py`). The
  server writes new riddles and quiz questions in the same shape with
  **OpenAI** (`OPENAI_API_KEY`, the key the voice already uses;
  `TRAVEL_TEXT_MODEL` picks the model, default `gpt-4o-mini`), falling back
  to Gemini (`GEMINI_API_KEY`). Results go into a shared pool, so most
  requests need no model call. With no model at all, Quiz falls back to Open
  Trivia DB questions (`/api/travel/questions`), and Riddles stays on the
  bundled deck.
- The phone mixes fresh items with bundled ones it hasn't heard. Once every
  bundled item has been heard, only fresh items are used. A bundled item
  repeats only when there's nothing new at all (offline). Two failed fetches
  in a row stop further requests for that game.

### How "already asked" is tracked

Repeats are matched on the **answer**, not the question text. A riddle
comes back reworded, but "a piano" is still "a piano".

1. **The phone** keeps its last 400 prompts and answers (`UserDefaults`)
   and sends the answers with every request. This is the durable copy,
   because the hosted server's disk resets on every redeploy.
2. **The server** keeps its own per-device answer history
   (`data/travel_items_served.json`) and never serves an answer that device
   has heard.
3. **The model** is told every heard answer, plus every answer already in
   the pool, is off limits. Its output is filtered against that list anyway.
   Because answers are one to four words, about 200 fit in one prompt.

Answer checking is local and instant (`TravelAnswerMatcher`): articles,
fillers and plurals are ignored ("it's a piano!" matches "a piano"), and a
right answer heard mid-sentence counts right away.

## Audio: one voice per session

- `TravelSpeech.prepare` decides once, at the start of a game, between the
  cloud AI voice (`GET /api/voice/tts`, OpenAI behind it, key kept
  server-side) and the phone's own voice. The cloud voice is used only if a
  line arrives within 10 s. A late-waking server gets the AI voice at the
  next **Change game**, never mid-game.
- Cloud lines are fetched as data through a disk cache and played with
  `AVAudioPlayer`, so every line the quizmaster might say next is
  pre-fetched with no dead air.
- If the cloud fails mid-game, the session switches to the phone voice for
  good. It switches at most once and never alternates.
- The phone voice skips Apple's novelty voices (Whisper, Bad News, Trinoids
  and the like) and prefers an Enhanced/Premium English voice.
- Every speech and mic callback carries a token, so a stale line can never
  talk over the current one or move the game on.
- The audio session is set once per game: `.playAndRecord` with
  `.defaultToSpeaker` when the mic is on (the loudspeaker, not the
  earpiece), or `.playback` without it. `.duckOthers` lowers car music
  rather than stopping it.

## The CarPlay reality

Apple does not allow games on the CarPlay display (there is no games
entitlement). Travel Mode has no CarPlay UI. Its audio simply plays through
the car speakers over CarPlay or Bluetooth, like any other audio.

## Safety

- The driver plays by voice only. The footer on every Travel Mode screen
  says so.
- If you're the only adult in the car, don't start it while driving.
