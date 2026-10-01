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
