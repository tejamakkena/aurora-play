# Releasing to the App Store

Everything the App Store asks for, what is already done in the repository, and
the text to paste. No payments are involved: the app is free with no in-app
purchases, so no Paid Applications agreement, tax or banking forms are needed.

Where this says "paste", the text is final and within Apple's length limits.
The working name is **Aurora Play**; see "Name" first.

## 0. Name (decide first, everything else repeats it)

Today three names exist: the App Store record (Cast Arena), the iPhone home
screen name (Aurora Play) and the Apple TV name (Aurora). Game Center shows the App
Store record name. Pick one brand and use it everywhere:

1. App Store Connect, App Information, **Name**: the public name (up to 30
   characters, must be unique across the App Store).
2. `CFBundleDisplayName` in `ios/project.yml`: the name under the icon (shorter is
   fine, e.g. "Aurora Play" on iPhone and "Aurora" on TV).
3. The privacy policy and support pages say "Aurora Play (iPhone) and Aurora (Apple
   TV)". Change `templates/privacy.html` and `templates/support.html` if the name
   changes.

A player's name on the TV leaderboard is separate from all of this: it is the
name they use in the room (see `docs/GAME_CENTER.md`).

## 1. What is done in the repository

| Item | Status |
| --- | --- |
| App icon 1024 (iPhone), layered icons and Top Shelf (tvOS) | In the asset catalogs |
| Privacy manifests (`PrivacyInfo.xcprivacy`) for both apps | Added |
| Export compliance (`ITSAppUsesNonExemptEncryption = false`) | In `project.yml` |
| Permission texts (motion, microphone, speech, local network) | In `project.yml` |
| Public privacy policy and support page | Served at `/privacy` and `/support` |
| Game Center sign-in and entitlement | Added |
| Security scans, tests, dependency updates | See `SECURITY.md` |

## 2. What only you can do

| Item | Where |
| --- | --- |
| Set `SUPPORT_EMAIL` on Render (a dedicated address, not a personal one) | Render, Environment |
| Redeploy Render so `/privacy` and `/support` exist | Render |
| Check both URLs open in a browser | `https://gamelab2.onrender.com/privacy` and `/support` |
| Fill in App Information, pricing, privacy answers, age rating | Sections 3 to 6 below |
| Take the screenshots | Section 7 |
| Add the reviewer notes | Section 8 |
| Pick the build, press Submit for Review | App Store Connect |

## 3. App Store Connect: iPhone app

| Field | Value |
| --- | --- |
| Name | Aurora Play |
| Subtitle (22/30) | Party games on your TV |
| Primary category | Games |
| Game subcategories | Trivia, Family (or Board if offered) |
| Secondary category | Entertainment |
| Price | Free (Tier 0). No in-app purchases. |
| Availability | All countries (or choose) |
| Privacy Policy URL | https://gamelab2.onrender.com/privacy |
| Support URL | https://gamelab2.onrender.com/support |
| Marketing URL | leave empty |
| Copyright | 2026 followed by your name |
| Content Rights | You own or have licensed all content (questions are written for the app or generated; nothing is copied) |
| Sign-in required | No |

**Promotional text** (137/170):

```
Turn your Apple TV into a game show. Phones are the controllers: trivia, brain battles, charades and more. Start a Game Night in seconds.
```

**Keywords** (100/100):

```
party,trivia,family,game night,charades,quiz,tv games,multiplayer,friends,brain,birthday,couch,board
```

**Description** (1618/4000):

```
Aurora Play turns your Apple TV into a party. The TV is the board, every phone is a controller, and nobody needs an account. Pick a game, scan the code, play.

GAME NIGHT
Line up as many games as you like with one running scoreboard. Choose the games, the number of rounds and a time limit, pick how points are scored, and let the host run the show. Going to a birthday or an anniversary? Add the guest of honour and the host will shout their name, tell jokes and lead a cheer.

A GAME FOR EVERY ROOM
Trivia with fresh questions every day. Brain Battle puzzles that test memory, speed and logic. Most Likely To, Would You Rather, Truth or Dare, Never Have I Ever, Point at Them, charades, Antakshari, Tambola, Ludo, Snake and Ladder, Connect 4, Battleship, bluffing and deduction games, and many more. Family, teen and adult levels so the whole room can join in.

BIG GROUPS WELCOME
Up to 50 phones in one room. Scoreboards are built to be read from the sofa.

NO TV? NO PROBLEM
Phone Play has games you can enjoy on your own or pass around: a daily Mind Gym, a Quick 5 quiz, Word of the Day, arcade games, Forehead Charades and more.

GAME CENTER
Sign in with Game Center and your name fills in automatically. The Apple TV keeps a house leaderboard with games played, wins and points for everyone who has played there.

A HOST WITH PERSONALITY
The TV host speaks every game with jokes and shout-outs. Use the built-in voices for free and offline, or switch to the studio voice for names and fresh questions.

Aurora Play is free, with no ads and no in-app purchases. Phones need an internet connection to join a room.
```

**What's New** (first version):

```
First release. Play party games on your Apple TV with every phone as a controller, run a Game Night, or play on the phone alone.
```

## 4. App Store Connect: Apple TV app

Same name, category, price, URLs, keywords and description. Use this short
description if you want the TV page to lead with the TV:

```
Aurora turns your Apple TV into a party. Pick a game or a whole Game Night, then everyone joins with the Aurora Play app on their iPhone: scan the code and play. Trivia, brain battles, Most Likely To, charades, Antakshari, Tambola, Ludo and many more, with a host who shouts, jokes and leads a cheer for the guest of honour.

Aurora needs the free Aurora Play app on at least one iPhone, and an internet connection. Free, no ads, no in-app purchases.
```

## 5. App Privacy ("nutrition label")

The app has no accounts and no tracking. Answer the questionnaire like this, for
both apps. The same facts are in the privacy manifests and the policy page.

- **Do you or your third-party partners collect data from this app?** Yes.
- **Data types collected, all "linked to the user's device", none used for tracking, purpose "App Functionality":**
  - Contact Info, Name (the display name; iPhone only)
  - Identifiers, User ID (the random device id and the Game Center hash)
  - User Content, Other User Content (a quiz topic or party name typed in)
  - Gameplay Content (scores and results; iPhone only)
- **Everything else:** No (no location, health, contacts, photos, browsing, purchases, diagnostics or advertising data).
- **Tracking:** No.

## 6. Age rating

Answer the questionnaire honestly for what the app contains. Guidance:

- Violence, gambling, sexual content, profanity, horror: None. (Poker, Teen Patti
  and Roulette are play-money games with no real-money gambling.)
- Alcohol, tobacco or drugs references: check the adult decks (Never Have I Ever,
  Truth or Dare, Would You Rather). If any prompt mentions drinking, answer
  "Infrequent/Mild", which makes the app 12+.
- Mature or suggestive themes: same check. If adult decks contain any, answer
  "Infrequent/Mild".
- User-generated content: players type names and topics, shared with the room. Say yes.
- Generative AI: topic questions and host jokes can be written by an AI model. Say yes.
- Unrestricted web access: No. Medical or wellness: No.

Expect 12+ if the adult decks touch alcohol, otherwise 4+. Do not choose the Kids category.

## 7. Screenshots

At least one set per platform is required. Use real captures: Apple rejects
mock-ups that do not show the app. Check the sizes App Store Connect asks for, as
Apple changes them.

| Platform | Size | How many |
| --- | --- | --- |
| iPhone 6.9 inch (iPhone 17 Pro Max simulator) | 1320 x 2868 | 3 to 10 |
| iPad 13 inch, only if the app runs on iPad | 2064 x 2752 | 3 to 10 |
| Apple TV | 1920 x 1080 | 3 to 10 |

The iPhone app is currently built for iPhone and iPad. To skip iPad
screenshots, set `TARGETED_DEVICE_FAMILY: "1"` for the controller in
`ios/project.yml` and ship iPhone only.

**How to capture:** Xcode, run the app in the simulator, press Cmd+S (saves to
the Desktop), or run `xcrun simctl io booted screenshot shot.png`. Put the Apple TV
simulator in a room with a few bot players so boards look alive.

Suggested shots, in order:

| iPhone | Apple TV |
| --- | --- |
| Home with the Today card | Game picker |
| Joining a room with the code | Lobby with the room code and QR |
| Game Night builder | A trivia question on the board |
| A game controller in play | Game Night scoreboard |
| Phone Play arcade | House leaderboard |
| Profile with Game Center | Party host welcome |

## 8. App Review information

| Field | Value |
| --- | --- |
| Sign-in required | No |
| Contact | Your name, phone number and the support email |
| Notes | the text below |

```
Aurora Play is a party-game controller for an Apple TV app called Aurora.
No account or login is needed.

To test on one iPhone with no TV: open the app, tap any game under "Phone Play" (for example Quick 5, Forehead Charades, Lights). These play on the phone alone.

To test the TV games: open Aurora on an Apple TV (or the Apple TV simulator), pick a game, and the TV shows a 6 character room code. In Aurora Play on the iPhone tap Join, type the code, then press Ready on the phone and Start on the TV. A single phone is enough; "Add bot" in the TV lobby fills the other seats.

The game server is hosted on a free plan and sleeps when idle. The first request after a long gap can take up to a minute to wake. If a join does not work at once, wait a moment and try again.

Game Center sign-in is optional. Signing in fills in the player name and lists the player on the TV's house leaderboard.
```

If you can, add a short screen recording link in the notes. Reviewers without a
TV find the app easier to approve when they can watch the multiplayer flow.

## 9. Before you press Submit

1. Move the hosted server off a sleeping free plan for the review window, or keep
   it awake (Render paid, or a free uptime monitor pinging `/about` every 5
   minutes). A reviewer who waits a minute and sees "could not reach the room"
   will reject the build for not working.
2. TestFlight: install both builds, play one game with two phones, run one Game
   Night, check Game Center sign-in and the Leaderboard button.
3. Version 1.0 on both apps, a build from the latest main, processing finished.
4. Choose "Manually release this version" so you decide the launch day.
5. Click Add for Review, then Submit. Review usually takes one to two days.

## 10. After release

- Watch the weekly Security scans and Dynamic scan runs; open `zap-report` and
  triage findings, then set `fail_action: true` in `dast.yml`.
- Merge Dependabot PRs when green.
- Reply to App Store reviews from App Store Connect.
