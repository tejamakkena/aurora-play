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
| Guess the Song | 2-20 | A word shows on every screen; the team names a song with that word (Hindi, Telugu or English, by deck), its meaning, or in the scene; the English meaning is the hint. A judge from the other team taps Guessed or Not guessed. Humor packs add the jokes. |

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

## Build your own night

On the TV home screen (Game Night panel) or the host's phone (Game Night card) the
suggested lineup is only a starting point:

- **Any game.** Remove games, move them up or down, or add any other game, even one
  that suits a different number of players. Up to 10 games.
- **Any length.** Every round-based game (Trivia, Brain Battle, Herd, Never Have I
  Ever, Guess the Song, Would You Rather, Host Lies, ...) has a **Rounds** pick of about
  half, as it is, one and a half times or double its normal length. Games that
  give everybody a turn (Hot Takes, Twenty Questions, Bollywood Charades) or that are
  not played in rounds (chess, poker, Ludo) keep their own length. The same pick also
  shows in a game's lobby when you play it outside a Game Night.
- **A clock.** Snakes and Ladders, Ludo and Battleship have a **Time limit** (2, 3, 5 or
  10 minutes). A countdown shows on the TV; when it hits zero whoever is furthest
  ahead wins (a tie at the top is a tie) and the night scores the placings as usual.
  Poker keeps its own Hands pick. Every other option a game has (poker chips, song
  decks...) is also shown for that game in the builder.
- **Any scoring.** See below.

Each game gets only its own picks, so "12 rounds" for one game never carries into the next.

## How a night scores

Every game's placings turn into night points. The host picks the rule:

| Rule | 1st | 2nd | 3rd | 4th | Rest | Good for |
| --- | --- | --- | --- | --- | --- | --- |
| **Classic** | 10 | 7 | 5 | 3 | 1 | Small groups; the original scoring |
| **Fair share** | 10 | spread evenly down to 1 for last | | | | Big groups: every place counts and a 2-player duel is worth as much as a 12-player party game |
| **Big finish** | Classic, but the **last game pays double** | | | | | Keeps the night open until the end |

Ties share a place. Games with no winner (Truth or Dare, Would You Rather, ...) and lost
co-op games give everyone 1 point (2 on a double-point finale). The TV and the phones
say "double points" while the last game of a Big finish night is up.

## Party mode (Game Night as an occasion)

On the host's phone, open **Game Night**, turn on **Make it a party** and pick the
occasion (birthday, anniversary, housewarming, festival, New Year's Eve or
get-together), the guest of honour's name, a host style (Party Host, Game Show,
Desi Dost, Chill) and, if they are in the lineup, the humor style and the Never Have
I Ever pack. Then start the night.

- The TV holds a welcome screen ("Welcome to Venkat's Birthday Party", the room
  code, who has joined) until the host taps **Begin the party**. The remote has a
  Begin button too. The name can be typed on the TV (the field appears when you pick
  an occasion) or on the host's phone.
- Then the TV performs rather than reads: a welcome, a joke at the room's expense,
  a line for the guest of honour, and a **shout** ("Everybody, on three! One, two,
  three! Happy birthday, Venkat!") in a crowd-leading voice. The lineup counts the
  games and teases the first and last by name; every later game gets its own joke
  when its lobby comes up ("Ludo. The game that has ended more friendships than any
  other. Dice ready."). At the end it names the champion, roasts everyone else
  lovingly, and toasts the guest of honour.
- **Cheer on demand.** While the party runs, the host's phone has **Cheer for
  Venkat** and the TV lobby has a Cheer button; either makes the TV shout again.
- **Indian names.** Common Indian names (Venkat, Teja, Priya, ...) are said in the
  Indian voice automatically. On the phone, **Say the name** lets you force Indian or
  Standard. The Indian voice is the one set as `ELEVENLABS_VOICE_ID_INDIAN`; point both
  voice ids at one Indian-English voice if you want the whole party in it.
- Styles change the wording (Party Host, Game Show, Desi Dost, Chill), not the voice.
- Code: `games/party_script.py` (the words and the Indian-name list),
  `games/night_party.py` (the show), `shout` in `games/show_host.py`, `cheer` and
  `begin_party` in `socket_events.py`, `Room.night.party`.

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
