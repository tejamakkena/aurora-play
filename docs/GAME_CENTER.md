# Game Center

Game Center is Aurora Play's only sign-in. There is no account system and no
password. A player who is not signed in plays exactly as before.

## What is built

| Piece | Where |
| --- | --- |
| Sign-in on the phone (Apple's own prompt) | `ios/GameLabController/App/GameCenterManager.swift` |
| The Game Center name fills the player name until they choose one | same file, `adoptNameIfEmpty` |
| `gcID` (a salted hash of Apple's team player id) sent when joining a room | `JoinRoomPayload.gcID`, validated by `utils/validators.py gc_id` |
| The TV's house leaderboard: games, wins, night wins, points | `ios/Shared/Models/HouseBoard.swift`, `ios/GameLabTV/Views/TVHouseBoardView.swift` |

The server never sees Apple's id, only the 16 character hash, and it only passes
it on in the room's player list. The house leaderboard is stored on the Apple
TV (`UserDefaults`), so it needs no server, costs nothing and survives a server
restart. It counts what happens on that TV, so two homes have two boards.

Points on the house board: 10 for a win, 6 for second, 4 for third, 2 for
playing. They live in `HouseBoardData.points(forRank:)`.

## One-time setup (App Store Connect and developer portal)

1. Developer portal, Identifiers, `com.gamelab.controller`: tick Game Center.
2. Regenerate the App Store provisioning profile for that identifier, and
   replace the `IOS_PROVISION_PROFILE_BASE64` secret (and
   `IOS_PROVISION_PROFILE_NAME` if the name changed). Without this the signed
   archive fails with a missing `com.apple.developer.game-center` entitlement.
3. App Store Connect, the app, Services, Game Center: turn it on.

The Apple TV app does not sign in to Game Center, so it needs none of this.

## Leaderboards and achievements for the next step

Not wired yet. Create these in App Store Connect when you are ready, with
exactly these IDs, and the next release can submit to them.

Leaderboards:

| ID | Type | Score |
| --- | --- | --- |
| `daily.quick5` | Recurring, resets daily | Points in the Daily Quick 5 |
| `arcade.lights` | Classic, high to low | Best Lights score |
| `arcade.numberrush` | Classic, high to low | Best Number Rush score |
| `arcade.2048` | Classic, high to low | Best 2048 score |
| `night.wins` | Classic, high to low | Game Night wins |

Achievements:

| ID | Name | How |
| --- | --- | --- |
| `streak.7` | One week strong | 7 day Daily streak |
| `night.first` | Party starter | Finish a first Game Night |
| `night.win10` | Night owl | Win 10 Game Nights |
| `host.hundred` | Crowd pleaser | 100 games played on the TV |
| `pointat.all` | Popular pick | Everyone points at you in Point at Them |
