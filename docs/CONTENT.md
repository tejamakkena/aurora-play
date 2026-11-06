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

4. **What the TV remembers.** The TV keeps its own list of what its family has
   seen (short hashes, not the text, in `SeenStore`), gives it to the server
   when a room opens (`restore_seen`), and takes the new ones back when a game
   ends (`seen_state`). The server counts those as seen for trivia and every
   prompt game, so a restarted server does not start from zero.

## Hosting note

On a free host, `data/` is wiped on every restart, redeploy and spin-down. That
used to lose the device history, so the same questions came round again. The
TV now carries that memory (step 4 above), so the server's own copy no longer
matters. The runtime pool still lives in `data/`, which is why the committed
library (below) is the part that matters.

## New questions every day

Three layers, cheapest first:

1. **A daily job grows the committed library** (`.github/workflows/grow-content.yml`).
   Every day it adds about 30 new items to each kind and keeps one pull request
   (`content/daily`) open. Trivia grows from Open Trivia DB with no key; the
   other kinds use `OPENAI_API_KEY` or `GEMINI_API_KEY` if either is a repository
   secret (Gemini's free tier is enough). Merge the pull request when you like;
   merging redeploys Render and the new items are served from then on. Run it
   once from the Actions tab to try it.
2. **The server grows a runtime pool while it runs** (above): extra items between
   deploys, lost when the server sleeps.
3. **The TV remembers what it has shown**, so the next game always prefers
   something new, and only recycles the longest-ago items when the bank is used up.

Bigger banks matter more than clever shuffling: with 600 questions and three
games a night, a family sees a repeat within a few weeks; with thousands, never.

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

Brain Battle is not a quiz with different names: every round is a generated
puzzle that trains a skill, and the end screen gives each player a title for
the skill they were best at. `games/brain_puzzles.py` has 13 kinds:

| Skill | Kinds |
| --- | --- |
| Number Speed | quick maths, mental chain ("start with 7, double it, take away 4"), missing number ("? times 6, plus 9, makes 81") |
| Memory | digit chains forwards and backwards (shown, then hidden) |
| Patterns | number sequences, letter patterns |
| Logic | who is tallest, calendar sums, clock sums |
| Word Smarts | analogies, odd one out, anagrams |
| Spatial | shape rotation |

Because they're computed, every answer is right and the supply is endless, with
difficulty set by `level` 1-10 (it rises every two rounds). A 12-round game
mixes at least ten kinds in a fresh order. Analogies and odd-one-out words come
from the library above.
`GET /api/brain/puzzles?level=&count=&kinds=&device=` serves Travel Mode.
