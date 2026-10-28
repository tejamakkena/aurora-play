# Game Night

An evening of games in one room, hosted from an iPad. Pick **Game Night** on the
TV (the pink button at the top of the sidebar), join with the iPad, and the iPad
sets up the party while the TV shows a welcome screen.

## The flow

1. **TV**: select *Game Night*. It shows a room code. There is no lobby: the night
   starts itself when the first phone joins.
2. **iPad**: open Aurora Play, enter the code. The first phone in is the **host**
   and gets the setup screen (anyone else can tap *I'm running the night* to take
   over, until the show starts).
   - Occasion: Birthday, Anniversary, Housewarming, Festival, New Year's Eve,
     Get-Together.
   - Name of the guest of honour (birthday person, festival name, ...).
   - Host voice, with a *Hear it on the TV* preview.
   - Tonight's games, in the order tapped. Never Have I Ever also gets a pack and
     a round count here.
   - Every change is sent live, so the TV already reads
     **"Welcome to Venkat's Birthday Party"** while the host is still typing.
3. The TV holds that welcome screen (with the room code and guests as they arrive)
   **until the host taps *Start the Night*** on the iPad. The TV also has a
   *Start the Night* button as a fallback.
4. **Show**: a voice says "Welcome to ...!" and the birthday cheer, announces every
   game in tonight's lineup, then each game gets a short intro and is played in
   turn. Between games there is a recap and a running tally; the voice names the
   winner and the leader.
5. **Finale**: the champion is announced, then the usual results screen.
   *Play Again* comes back to the setup screen with the same details filled in.

Guests can join at any point; a guest who arrives mid-game watches that game and
is dealt into the next one.

The host's bottom bar has **Next** (skip the current screen), **Skip this game**
and, in the menu, **End the night**.

## Scoring

Each hosted game awards night points by finishing position: 1st 10, 2nd 7, 3rd 5,
everyone else 2. A game nobody scored in (or where everyone tied) gives 2 to each
player and no winner, so a bad game never knocks anyone out.

## Voice

The host voice is the system speech synthesiser on the TV, so names and game
titles can be dropped into the script. A **voice pack** is a voice (language, rate,
pitch) plus a way of talking. There are four: Party Host, Game Show, Desi Dost
(Indian English) and Chill. Scripts live in
`games/native_hub/engines/_night_content.py` (`VOICE_PACKS`); every pack must define
every line key (a test enforces it).

Never Have I Ever also reads each statement aloud, in whatever voice the night
chose.

The system voices available depend on the Apple TV: if a pack's language has no
installed voice the TV falls back to US English.

## Never Have I Ever

Everyone answers privately and at the same time, *I have* or *Never*; the TV then
reveals who has, picks someone to tell the story, and each confession scores a
point (the ranking is "wildest in the room").

Packs (`games/native_hub/engines/_nhie_packs.py`): Surprise Mix (default, built from
every non-adult pack), Classic, Funny & Awkward, Desi Edition, Work & School, Food &
Travel, and two **18+** packs, Party Night and After Dark. The 18+ packs are never
in the default mix and are badged in the picker. Standalone, the host picks a pack
on their phone before the first statement (25 s, then it uses the mix); inside a
night the pack is chosen during setup.

To add statements, append to a list in `_nhie_packs.py`. Each completes the sentence
"Never have I ever ..." and must not end in a full stop.

## How it is built

`GameNightEngine` (`games/native_hub/engines/game_night.py`) is an ordinary hub
engine that **hosts other engines**. While a hosted game is running its
`public_state` / `private_state` are the hosted engine's own, so every existing TV
board and phone controller works unchanged. Phases:

    setup -> welcome -> lineup -> [ intro -> playing -> interlude ]* -> finale -> done

- The night's own screens travel on a separate TV-only `night_state` event (phones
  get the same data under `night` inside `private_state`), because each TV board
  owns the single `game_state` handler.
- The TV performs the speech and reports `night_announce_done`; a deadline estimated
  from the text is the fallback, and a minimum hold keeps each screen readable.
- Night verbs are all prefixed `night_` so they can never collide with a hosted
  game's own verbs. Only the host phone, or the TV (a non-player id, which the hub
  only accepts from a TV socket), may drive.
- Hub changes: engines can opt in to `late_join`; the pump follows the live
  engine's `tick_hz`; night rooms live 6 hours instead of 1 (`ROOM_TTL_BY_GAME`);
  `RoundBasedEngine.active_players` ignores guests who were not dealt in.

### Adding a game to the lineup

1. Make sure it has a hub engine and a TV board / phone controller as usual.
2. Add an entry to `CATALOG` in `_night_content.py` (id, name, emoji, one-line blurb).
   Player limits come from the engine itself. A game whose player range does not
   fit the room when its turn comes is skipped, with a spoken note.
3. If the game has options the host should choose up front, add a field to the config
   (`clean_config`) and read it in the engine's `apply_night_config`.

## Tests

`tests/test_game_night.py`, `tests/test_game_night_socket.py`,
`tests/test_never_have_i_ever.py`, plus both engines in the generic
`tests/test_native_engines.py` loops. The Swift side (setup form, TV stages, speech)
needs a build and a run on real devices.
