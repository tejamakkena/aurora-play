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

## Using ElevenLabs instead

ElevenLabs' Eleven v3 voice acts from **audio tags** in the text, such as
`[excited]`, `[giggles]` and `[sarcastic]`, so it can give real laughs and a
real roast tone where OpenAI only changes the delivery. It costs more (about
$10 to $20 for the whole pack) and needs a paid plan for commercial use; the
free credits are for auditioning only.

Voices tried in an audition (Eleven v4): **Odom - Upbeat, Energetic, Playful**
(`7zoixx2reelPHqsL6WsW`, a game-show host) for the host voice, and **Neeraj - Warm
& Friendly Hindi** (`H9oourY5nVeVuzarh4D5`) for Hindi and Telugu words. Pick your
own from the Voice Library if you prefer. The tool code has not been run against the live
ElevenLabs REST API yet (only mocked), so the audition run is also its first test.

Set up:

1. In ElevenLabs, create an API key (Developers, API keys) and choose voices
   from the Voice Library. Copy each voice's id. Pick one warm host voice, and
   if you want Hindi and Telugu words said properly, a second voice with an
   Indian accent.
2. In GitHub, **Settings, Secrets and variables, Actions**: add the secret
   `ELEVENLABS_API_KEY`, and `ELEVENLABS_VOICE_ID` and, optionally,
   `ELEVENLABS_VOICE_ID_INDIAN`. The voice ids may be saved as secrets or as
   variables; the workflow reads either.
3. Run "Render voice pack" with engine `elevenlabs` and **audition** ticked, and
   listen. Then run it for real: engine `elevenlabs`, limit `0`, **redo** ticked.
   The host lines and game narration render first, so a plan's monthly
   credits spent on that part are the ones that matter most.

The tag each style uses is in `ELEVEN_TAGS` in `games/voice_styles.py`; the
tags are only sent in the request, never stored in the pack or shown on screen.

To use ElevenLabs for the live voice too (names, fresh AI questions), set
`TTS_PROVIDER=elevenlabs` plus the same three values on the Render server, so
the live voice matches the pack. Leave it off to keep the live voice on OpenAI.
`ELEVENLABS_MODEL` (default `eleven_v4`) picks another model; tags are only
added for `eleven_v4` and `eleven_v3`.

## Delay and slow voice

What makes the host feel slow, and what is done about each:

| Cause | Fix |
| --- | --- |
| The cloud voice renders each line the moment the TV asks for it (1 to 3 s). | The server renders the lines it already knows (party welcome and lineup, the host's quips) in the background as soon as they are written (`games/voice.py` `prewarm`). The TV also fetches the next two lines of a spoken run while the current one plays, so there is no gap between lines. `TTS_PREWARM=0` turns the server side off. |
| Two requests for one line (prewarm and the TV) each paid for it. | One lock per line: the second waits for the first and reads the cache. |
| A free-tier server sleeps after 15 idle minutes and takes up to a minute to wake. | The TV pings `/api/voice/warm` when a room opens. For a party, also open the site or use a free uptime monitor (UptimeRobot, 5-minute checks) on `/api/voice/warm` an hour before. |
| The server's cache is lost when it restarts (free disks are ephemeral). | Fixed lines come from the bundled pack, which needs no server. Only names and questions go to the cloud voice. |
| A high-quality model is slower. | Keep `eleven_v4` for the bundled pack, but run the live server on `ELEVENLABS_MODEL=eleven_flash_v2_5` (about 0.3 s, half the credits, no audio tags). |
| The offline clips and device voice read slowly. | **Host pace** in the TV's Settings (game list, Settings): Relaxed, Normal, Brisk (default), Quick. The style prompts also ask for a brisk read. |

A host moment (`answers_none`) now acts like its style (`roast`) on ElevenLabs too, not only on OpenAI.

## Installing the voice once (names and the party show)

The party host's lines are written to be pre-recorded, so the TV needs no internet and
there is no wait:

- Every fixed sentence (the jokes, the game teasers, the lineup frames, the cheers)
  is rendered once into the pack.
- The sentences with a **guest of honour's name** are rendered per name, ahead of the
  party. List the names in `tools/party_names.txt` (`Venkat = Ven-kut` to fix how one
  is said), or type them into the **names**
  box of the "Render voice pack" workflow (for example `Venkat, Asha, Teja`, with
  **occasions** `birthday`). Each name adds about 40 short clips. Names on the Indian-name
  list (`games/party_script.py`) are rendered with `ELEVENLABS_VOICE_ID_INDIAN`.
- A name that is not in the pack is still spoken at the party, live, in the cloud voice.
  With the cloud voice off it falls back to the device voice, which is why it is worth
  listing the names you will use.

The steps, once:

1. Add the ElevenLabs key and voice ids (above), or an OpenAI key.
2. Actions, **Render voice pack**: engine `elevenlabs`, **audition** ticked. Listen.
3. Run it again: engine `elevenlabs`, limit `0`, **redo** ticked, names filled in.
4. Open the pull request from the `voice-pack/...` branch it pushes and merge it. The
   next TestFlight build carries the pack; nothing is downloaded at the party.

Adding a birthday person later means running step 3 again with only the new name and
**redo** unticked: only the missing clips are rendered.

## Settings on the TV

The game list's **Settings** button holds the voice (Offline or Studio), the host's
pace, how many voice-pack lines this build carries, the server connection, and the
welcome guide that opens on first launch.
