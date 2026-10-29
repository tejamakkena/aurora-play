# The voice

The TV and phones speak in three ways. Knowing which one a line uses tells you
what to change when it sounds wrong.

| Line | Voice | Where it comes from |
|---|---|---|
| Fixed lines (game narration, the Game Night host, question banks) | Bundled clips, offline and free | `ios/Shared/Voice/Pack`, rendered once by `tools/render_voice_pack.py` |
| Lines with a name or a fresh AI question | The cloud voice (OpenAI) | `/api/voice/tts`, `games/voice.py` |
| Anything else, or no internet | The device voice | Apple's built-in voices |

## Sounding alive

The cloud voice (`gpt-4o-mini-tts`) acts a line when it is told how. Without
that it reads flat, which is why the birthday welcome sounded like text on a
page. `games/voice_styles.py` holds the directions: `welcome`, `hype`,
`playful`, `roast`, `finale`, `narrator`, `quiz`, `kids`, and `indian` for
Hindi and Telugu words. A Game Night host line asks for its style by moment
(`night_open` is `welcome`, `answers_none` is `roast`...), and every other
line is the warm `host`. Set `TTS_STYLES=0` on the server to turn it off.

The voice pack renders each line in its own style, then trims the silence a
voice leaves at the start and end of each clip and adds one short, even gap, so
sentences played one after another no longer pause oddly.

## Rendering the pack with OpenAI

You need an OpenAI account with a few dollars of credit.

1. Create an API key at <https://platform.openai.com/api-keys>.
2. In the GitHub repo: **Settings, Secrets and variables, Actions, New
   repository secret**. Name it `OPENAI_API_KEY` and paste the key. (The
   server on Render needs the same key as an environment variable; it
   probably has it already.)
3. **Listen first.** Actions, "Render voice pack", Run workflow: engine
   `openai`, tick **audition**. It renders ten sample lines in every style for
   about a cent and attaches them to the run as the `voice-audition` download.
4. **Render everything.** Run it again: engine `openai`, limit `0`, tick
   **redo** (so the whole pack is one voice instead of a mix with the old Piper
   clips), max MB `0`. The full pack is about 5,900 sentences, 190,000
   characters and 52 MB. At OpenAI's current rate that is roughly $3 to $6, once.
   Check the live price before you run it.
5. The run pushes a `voice-pack/<run id>` branch. Listen to a few clips, then
   open a pull request from it. Merging ships the clips in the next TestFlight build.

Lines the pack does not have (a player's name, a fresh AI question) use the
cloud voice, now in the host style.
