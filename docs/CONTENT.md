# Content variety

Every party game draws its prompts, questions and words from
`games/content_service.py`. Two things matter: where content comes from,
and what stops a table from seeing it twice.

## Where content comes from

All sources are merged and de-duplicated per kind:

1. **Built-in lists** in the engines (`games/native_hub/engines/_content.py`,
   `legacy_new.py`, `travel.py`).
2. **The content library**, `games/content_library/<kind>.json`, committed to
   the repo. Grow it with:

   ```bash
   OPENAI_API_KEY=sk-... python scripts/grow_content.py              # every kind, up to 300 each
   OPENAI_API_KEY=sk-... python scripts/grow_content.py herd --target 500
   ```

   Review the diff and commit it. Committed content survives server restarts.
3. **A runtime pool the server grows while it runs.** When a kind's fresh
   supply for the current table drops below 40, a background thread asks
   OpenAI (then Gemini; `games/llm_json.py`) for 30 new items. English
   trivia and KBC grow from Open Trivia DB instead, which is free and needs no
   key. Games never wait on this.

| Kind | Game | Before | Now (committed) |
| --- | --- | --- | --- |
| `herd` | Herd | 33 | 128 |
| `most_likely` | Most Likely To | 43 | 134 |
| `bluff` | Bluff It | 23 | 64 |
| `spy_location` | Odd One Out | 20 | 87 |
| `wavelength` | Spectrum | 15 | 86 |
| `auction` | Sealed Auction | 12 | 62 |
| `charades` | Bollywood Charades | 50 | 110 |
| `emoji_movie` | Emoji Charades | 40 | 132 |
| `meld_category` | Mind Meld | 7 | 101 |
| `draw_prompt` | Speed Sculptor | 10 | 150 |
| `hot_take` | Hot Takes | 20 | 96 |
| `cipher_word` | Cipher Grid | 50 | 192 |
| `mc` | Trivia / KBC (English) | 206 / 321 | + AI (OpenAI/Gemini) and Open Trivia DB, growing |
| `analogy` | Brain puzzles | 0 | 60 |
| `odd_word` | Brain puzzles | 0 | 60 |

## What stops repeats

`pick(room, kind)` skips the following, in this order. Each step relaxes only
when nothing fresh is left:

1. **This room**, across Play Again (`room.content_history`).
2. **Every player's phone at the table**, across rooms and game nights.
   Players' ids are stable device ids. The history is kept in memory and in
   `data/content_heard.json`. If a friend saw a prompt at another party, it's
   skipped for everyone.
3. **The current game's own picks.** Spectrum, Mind Meld and Speed
   Sculptor used to repeat within a single game. They don't anymore.

Trivia and KBC use the same device history on top of their existing
per-room history (`content_packs.fresh_questions`).

## Hosting note

On a free host, `data/` is wiped on every restart or spin-down. That loses
the runtime pool and the device history, but not the committed library.
To keep both, point `CONTENT_POOL_PATH` and `CONTENT_HEARD_PATH` at a
persistent disk. Otherwise, grow the library with the script and commit
it.

## Settings

| Variable | Purpose |
| --- | --- |
| `OPENAI_API_KEY` | Generation. The voice already uses this key. |
| `CONTENT_TEXT_MODEL` | OpenAI model for content (default `gpt-4o-mini`). |
| `GEMINI_API_KEY` | Fallback generator. |
| `CONTENT_AUTO_REFILL=0` | Turns off background generation. |
| `CONTENT_POOL_PATH`, `CONTENT_HEARD_PATH` | Where the pool and histories are saved. |

## AI everywhere questions are asked

- **Trivia and KBC (English):** the live pool grows from the LLM (60% of
  refills when a key is set: newer, India-flavoured, current events) and from
  Open Trivia DB (free) otherwise or on failure.
- **Topic trivia, 20 Questions secrets, Hot Takes topics**
  (`games/topic_gen.py`): now OpenAI first, then Gemini, via
  `games/llm_json.py`. Before, these were Gemini only.
- **Travel Mode riddles/quiz:** `games/travel_items.py` (OpenAI, then Gemini).
- **Every prompt game** (Herd, Most Likely To, Bluff It, ...): background LLM
  refill, as described above.

## Brain puzzles

`games/brain_puzzles.py` generates sequences, mental maths, memory chains,
ordering logic, calendar logic and shape rotation. Because they're computed,
every answer is right and the supply is endless, with difficulty set by
`level` 1-10. Analogies and odd-one-out words come from the library above.
`GET /api/brain/puzzles?level=&count=&kinds=&device=` serves Travel Mode.
