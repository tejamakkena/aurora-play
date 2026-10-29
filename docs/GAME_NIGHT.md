# Game Night Guide

How to run an Aurora (TV) / Aurora Play (phone) party, and what to expect
from each game.

## Before people arrive

1. **Wake the server.** The hosted server (`gamelab2.onrender.com`) sleeps
   after ~15 minutes idle and takes 30-60 s to wake. Open the Aurora app on
   the TV (or visit the URL in a browser) a minute before you start.
2. **Install Aurora Play** on every phone that will play (TestFlight).
3. Pick a game on the TV. The lobby shows a room code, a QR code and the
   join link (`<server>/join/<CODE>`).

## Joining

- **Scan the QR** with the phone camera. The join page opens Aurora Play
  with the code filled in (`auroraplay://join/<CODE>`); if the app is not
  installed the page shows the code to type.
- **Or type the code** in Aurora Play. The app remembers each player's name.
- **Phones can lock.** If a phone sleeps or drops Wi-Fi, it re-joins its
  seat automatically when it comes back -- no need to rejoin by hand. The
  TV does the same after a network blip.

## Lobby options

- **Bots** (Trivia, KBC, Bluff It, Antakshari, Most Likely To): the TV
  remote or the host's phone can add/remove bot players to fill seats.
  Other games refuse bots, because a bot that can't play would stall turns.
- **Question language** (Trivia, KBC): English, Telugu or Hindi, from the
  TV ("Questions: ...") or the host's phone.

## Game notes

| Game | Players | Notes |
| --- | --- | --- |
| Poker | 2-8 | Up to 10 hands, rotating button, 45 s turn clock (idle checks/folds). |
| Teen Patti | 2-8 | Idle turns pack after 40 s. |
| Tambola | 2-20 | Early Five, Top/Middle/Bottom Line, Full House. Tap called numbers (ringed in yellow), then claim. |
| Roulette | 1-8 | Tap "Done betting"; the wheel spins when everyone is done or after 25 s. |
| KBC Hot Seat | 1-20 | Everyone (up to 6) gets a turn in the hot seat; the rest vote in the audience poll. |
| Trivia | 2-10 | Answer before the reveal; Telugu/Hindi packs available. |
| Mafia | 5-15 | Night ends when every role has acted; a tied day vote eliminates nobody. |
| Odd One Out | 4-10 | Three rounds, a new spy each round. |
| Dumb Charades | 3-16 | Guesses are forgiving: "DDLJ" or a small typo counts. |
| Most Likely To | 3-20 | Secret ballot, reveal on the TV. |
| Herd | 3-20 | Only answers someone else matched score. |
| Antakshari | 2-20 | First valid song takes the round; no repeats. |
| Last Tap | 2-20 | Reaction times are measured from when GO actually appears. |
| Carrom | 2-4 | Pull back from the striker and release; 10 shots each, first to 6. |
| Ludo | 2-4 | Single-choice moves play themselves. |
| Chess | 2 | Board on the TV, moves on the phone; pawns auto-queen; capture the king to win. |
| Speed Sculptor | 3-8 | Draw on the phone, then vote for the best drawing on the phone. |
| Never Have I Ever | 2-20 | Everyone taps I have or Never in secret; the TV reveals who has and picks someone to tell the story. Packs: Surprise Mix, Classic, Funny, Desi, Work, Food and Travel, and two 18+ packs. |
| Guess the Song | 2-20 | A word shows on every screen; the team names a song with that word, its Hindi meaning, or in the scene. A judge from the other team taps Guessed or Not guessed. Humor packs add the jokes. |

## What the score means

Results show what each game's score actually is, not "pts" everywhere
(`games/native_hub/scoring.py`):

- **Points** (trivia, most games): "30 pts".
- **Counts**: "450 chips" (Poker, Teen Patti), "square 87" (Snakes and Ladders),
  "6 pairs" (Memory), "52 steps" (Ludo), "9 hits" (Battleship).
- **One winner** (Chess, Connect 4): the winner shows "Winner"; the rest show no score.
- **Sides and teams** (Mafia, Heist, Defuse, Heist Escape): "Won" or "Lost".
- **No winner** (Truth or Dare, Would You Rather, Most Likely To, Never Have I
  Ever): no score is shown, and on a Game Night everyone gets the same 1 point
  for playing instead of 10, 7, 5, 3 by placing. The host does not announce a winner.

A lost co-op game (Defuse, Heist Escape) also gives everyone 1 point.
To change a game, edit `SCORING` in that file.

## Party mode (Game Night as an occasion)

On the host's phone, open **Game Night**, turn on **Make it a party** and pick the
occasion (birthday, anniversary, housewarming, festival, New Year's Eve or
get-together), the guest of honour's name, a host style (Party Host, Game Show,
Desi Dost, Chill) and, if they are in the lineup, the humor style and the Never Have
I Ever pack. Then start the night.

- The TV holds a welcome screen ("Welcome to Venkat's Birthday Party", the room
  code, who has joined) until the host taps **Begin the party** on the phone. The
  remote has a Begin button too.
- The TV's voice then speaks the welcome and announces the lineup, and the normal
  first-game lobby follows. At the end it announces the champion.
- Styles change the wording, not the voice: the TV keeps one consistent voice.
  Lines without a name are part of the offline voice pack
  (`tools/render_voice_pack.py`, source `nhie_songs` for the games' jokes).
- Code: `games/night_party.py`, `begin_party` in `socket_events.py`, `Room.night.party`.

## The show host

Every Game Night has a talk-show host. It opens the night, teases each game
("Quiz time! This is where we find out who actually paid attention in school."),
reacts when a quiz question is revealed ("Nobody got that? I expected a third
grader to know this one."), cheers each winner, reads the standings (new leader,
close race, runaway lead, last place) and closes the night for the champion.

- The TV shows each line as a lower third with a headline ("Asha takes the
  lead!") and speaks it between the game's own lines; the game always speaks
  first.
- Kids mode uses gentle, encouraging lines only.
- Spoken lines never contain names, so the whole script is in the offline voice
  pack (`tools/render_voice_pack.py` renders it with the game narration, first).
- Code: `games/show_host.py` (script and moments), `host_line` socket event
  (`broadcast.flush_host_lines`), `TVShowHostOverlay.swift`.

## No internet? Host on a laptop (LAN)

1. On a laptop on the party Wi-Fi:

   ```bash
   pip install -r requirements.txt
   python app.py            # serves on 0.0.0.0:5000
   ```

   Find the laptop's LAN address (e.g. `192.168.1.20`).
2. Point the QR at the laptop so phones' cameras land there:

   ```bash
   NATIVE_JOIN_URL_BASE=http://192.168.1.20:5000/join python app.py
   ```

3. **Phones:** on the Aurora Play join screen tap **Server** and enter
   `192.168.1.20:5000`, then **Connect**. "Use default" switches back.
4. **TV:** build the TV app with an `AuroraServerURL` Info.plist value of
   `http://192.168.1.20:5000` (there is no on-TV server field yet). Both apps
   allow plain HTTP to local-network hosts (`NSAllowsLocalNetworking`).
