# Design audit: one look across both apps

Phone Play is the reference. Everything else in `ios/GameLabController` and
`ios/GameLabTV` was audited against it, screen by screen, and the drift was
fixed. This document is the record: what each file group used before, the
verdict, and what changed.

Branch: `wt/design-audit` (off `feat/lineup`).

---

## 1. The reference

`ios/GameLabController/Views/PhonePlay/PhonePlayCore.swift` defines
`PhonePlayDesign`, which aliases `TravelDesign` in
`ios/GameLabController/Views/Travel/TravelModeViews.swift` and adds the party
colours. `PhonePlayComponents.swift` holds the parts built out of it.

| Role | Hex |
| --- | --- |
| `bg` | `0B0B12` |
| `surface` | `15151F` |
| `surface2` | `1E1E2B` |
| `green` | `2FE07A` |
| `cyan` | `38D6F5` |
| `yellow` | `FFC531` |
| `purple` | `B07CFF` |
| `orange` | `FF8A3D` |
| `red` | `FF4D6D` |
| `pink` | `FF5FC8` |
| `blue` | `4D7CFF` |
| `indigo` | `6C5CFF` |
| `text2` | `A7A7B8` |
| `text3` | `6B6B7E` |

Radii: cards **24**, buttons **18**, and -- newly named in this pass -- chips
**14**. Type: SF Rounded, heavy/black for titles, semibold/medium for body.
Buttons squash (`PhonePlayPressStyle`) and answer (`PhonePlayHaptics`).

---

## 2. Headline findings

1. **The TV's palette was a near-miss of the phone's in every shared role.**
   Not a different scheme -- the same intent, one or two hue steps off, which
   is the worst case: nothing looks wrong on its own screen and nothing
   matches across screens. Table in section 3.
2. **Three near-black backdrops.** The flat TV boards used `0a0a14`, `0a0814`
   and `0d0a14` for the one "board background" role, none of them the phone's
   `0B0B12`.
3. **Twenty-six places still held the pre-alignment value of a token the kit
   already named** (`22D3EE` for cyan, `34D399` for green, `EC4899`/`F472B6`
   for pink, `FACC15`/`FBBF24` for gold, `F43F5E` for red, `A855F7` for
   purple). This is how the drift happened in the first place.
4. **219 raw SwiftUI colours** (`.red`, `.cyan`, `.yellow`, `.mint`, ...)
   across thirteen TV boards and five phone files -- Apple's hues, not the
   product's.
5. **Per-game identity colours disagreed between the two screens in four
   games.** Trivia Showdown's answer tiles, team colours in every spoken
   game, Hot Takes' FOR/AGAINST pair, Codenames' cards. A player tapping
   tile B was tapping a different colour from the one the TV was showing.
6. **Physical game pieces had two values each.** A playing card's black ink
   was `121826` in Poker and `16161E` in Teen Patti; a chess piece was
   `fdf8ec`/`1b1b1f` on the TV and pure white/`16161E` on the phone.
7. **Twenty-two distinct corner radii on the TV, thirteen on the phone**, for
   three roles. `ShellGlassCard` was asked for 40 on one lobby panel and 44
   on the next.
8. **584 fonts were not rounded** -- 238 bare text styles (`.headline`,
   `.title2.bold()`) and 346 bare `.system(size:)` -- so whole screens drew
   in the default face next to rounded headings.
9. **Fifteen phone buttons fired with no haptic**, and `OneStopPressStyle`
   was a second copy of `PhonePlayPressStyle`'s body.
10. **`ProfilePalette` was Apple's ten named colours**, so a player's chosen
    profile colour matched nothing else on screen.

---

## 3. Palette alignment (phone hex wins)

| Role | Phone Play | TV before | TV now |
| --- | --- | --- | --- |
| background | `0B0B12` | `ShellTheme.ink` `07051A` | `0B0B12` |
| surface | `15151F` | `ShellTheme.panel` `120C2C` | `15151F` |
| surface2 | `1E1E2B` | not named | `ShellTheme.panel2` `1E1E2B` |
| green | `2FE07A` | `mint 34D399`, `TVTheme.success 4ade80`, `PKTColors.mint 34d399` | `2FE07A` |
| cyan | `38D6F5` | `22D3EE` | `38D6F5` |
| yellow | `FFC531` | not named (gold stood in) | `FFC531` |
| purple | `B07CFF` | not named (`A855F7` stood in) | `B07CFF` |
| orange | `FF8A3D` | `FB923C` | `FF8A3D` |
| red | `FF4D6D` | `TVTheme.danger f43f5e`, `F43F5E` | `FF4D6D` |
| pink | `FF5FC8` | `EC4899`, `F472B6` | `FF5FC8` |
| blue | `4D7CFF` | `2563EB`, `3B82F6`, `4D6BFF` | `4D7CFF` |
| indigo | `6C5CFF` | not named | `6C5CFF` |
| secondary text | `A7A7B8` | white 0.7 (shell) vs 0.62 (boards) | white 0.7 both, plus opaque `A7A7B8` |
| tertiary text | `6B6B7E` | white 0.45 (shell) vs 0.38 (boards) | white 0.45 both, plus opaque `6B6B7E` |
| card radius | 24 | 36 (shell) / 28 (boards) / 20-60 ad hoc | 24 |
| button radius | 18 | 24 | 18 |
| chip radius | 14 | not named | 14 |

Kept as the TV's own, because Phone Play has no equivalent:
`violet 7C3AED`, `gold FACC15`, and the ambient backdrop stops
`night 140A33` / `deepBlue 0A1238`.

`TVTheme` now forwards every shared role to `ShellTheme`, so the two TV kits
and the phone speak one vocabulary. The seven `TVPalette` moods (aurora,
neon, ice, ember, ocean, jungle, festival) stay the TV's own: a lit room's
backdrop has no counterpart on a phone at arm's length. Everything drawn
*on top* of a mood now comes from the shared tokens.

### Identity colours, matched both ways

These must agree across screens. Where they disagreed, the phone followed the
TV (per the brief), except where the TV was simply using an ad-hoc hex for a
role the kit names -- then the TV took the token, which is the phone's value.

| Thing | Before | Now |
| --- | --- | --- |
| Trivia answer tiles A-D | TV `FF3D7F/3D8BFF/FFB020/22C77A`, phone Phone Play red/blue/yellow/green | phone follows TV |
| Trivia doors | TV `FF4D8D/3DA5FF/FFB020`, phone pink/blue/yellow | phone follows TV |
| Trivia show gold | TV `FACC15`, phone `FFC531` | phone follows TV |
| Trivia power colours | TV `38BDF8/F472B6/8B8FD8/FACC15/22D3EE`, phone tokens | TV follows the tokens (= the phone) |
| Brain Battle answers A-D | both `FF3D7F/3D8BFF/FFB020/22C77A` | already agreed, left alone |
| Player avatar wheel (10) | both `F43F5E ... EC4899` | already agreed, left alone |
| Connect 4 discs | both `e8283b/ffc61a/1fc96b/35b4ff/8a94a6` | already agreed, left alone |
| Chess squares | both `f0d9b5` / `b58863` | already agreed, left alone |
| Chess pieces | TV `fdf8ec`/`1b1b1f`, phone white/`16161E` | phone follows TV |
| Playing card ink and face | Poker `d61f2c`/`121826`/`eef0f4`, Teen Patti Phone Play red/`16161E`/flat white | one table, Poker's (= the TV's) |
| Roulette pockets | both `0b7a3b/c0202a/15161a` | already agreed, left alone |
| Team colours (red/blue/green/yellow) | TV `red` token, `3B82F6`, `mint`, `gold`; phone all tokens | TV follows the tokens |
| Hot Takes FOR / AGAINST | TV `FF7A2F`/`FF3D7F` and cyan/`4D6BFF`; phone orange/red and cyan/blue | TV follows the tokens |
| 20 Questions verdicts and categories | TV `34D399/FB923C/60A5FA/F472B6/FACC15` | TV follows the tokens |
| Codenames cards | TV `c0392b`/`2471a3`, phone tokens | TV follows the tokens; tan `8d7f6d` bystander kept both sides |
| Defuse wire table | TV had no `black` case and fell through to grey | TV gains `black 121218` and the `text3` fallback, matching the phone's manual |

---

## 4. Screen-by-screen

Verdicts: **reference** (defines the look), **consistent** (already on the
tokens), **drifted** (tokens, but with off-vocabulary radii/type/hues),
**ad-hoc** (hand-picked colours or styles for roles the kit names).

### Phone -- Phone Play (the reference)

| File group | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `PhonePlay/PhonePlayCore.swift` | `PhonePlayDesign`, `PhonePlayHaptics` | reference | Named the third radius: `chipRadius = 14`, with a comment stating the three-radius rule |
| `PhonePlay/PhonePlayComponents.swift` | tokens throughout | reference | Chip/row radius `14` -> `chipRadius`; icon fonts given `design: .rounded` |
| `PhonePlay/PhonePlayHomeView.swift`, `PhoneHomeParts.swift` | tokens | consistent | Radii and fonts to tokens |
| `PhonePlay/HeadsUp/` | tokens + eight per-deck gradient pairs (`colorHex`) | consistent | Card radius `20` -> 24, row `16`/`18` -> 18; fonts rounded; `endEarly` button gains a haptic. Deck gradients kept -- they are deck identity inside the reference |
| `PhonePlay/Spy/`, `Mafia/`, `TruthDare/`, `WouldRather/`, `HotPotato/`, `StoryChain/` | tokens | drifted | Radii `16/20/22/28/30` -> card 24 / button 18 / chip 14; fonts rounded. Mafia's night (`120B2E/2A1250`) and morning (`FF9A5A/FF5E7E`) scene gradients kept as scene identity |
| `PhonePlay/Daily/`, `WordDay/`, `Arcade/` | tokens | drifted | Same radius and type pass. WordDay's `design: .serif` dictionary word kept -- a deliberate editorial face |
| `Travel/TravelModeViews.swift` | `TravelDesign` (the source of the tokens) + Phone Play parts | consistent | Icon tile `26` -> 24, fonts rounded |

### Phone -- controllers

| File group | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `Controllers/ControllerKit.swift` | `PhonePlayDesign` (restyled earlier) | consistent | Added `GamePieceColors` (card face/ink/back, chess pieces and squares) so both screens draw a piece from one table; icon fonts rounded |
| `Controllers/ClassicGameControllers.swift` | tokens + Connect 4 + roulette + chess hexes | drifted | Chess pieces now follow the TV (`fdf8ec`/`1b1b1f`); board squares and Connect 4 discs via `GamePieceColors` / unchanged palette; radii and fonts to tokens |
| `Controllers/DuelControllers.swift` | tokens + card and carrom hexes | ad-hoc (cards) | Teen Patti's card ink and face -> `GamePieceColors`; carrom's wood ring (`d9b382`/`a57a4a`) kept as a material; radii and fonts |
| `Controllers/PokerControllerView.swift` | `PKCColors` on tokens + card hexes | consistent | Card face/ink/back -> `GamePieceColors` (same numbers, one home) |
| `Controllers/TriviaControllerView.swift` | `QuizPadStyle`, part tokens part hexes | ad-hoc (tiles) | Tiles, doors and show gold now the TV's values; avatar wheel already matched; ice panel (`E0F7FF/93D8F7/5BB8E8`) kept -- it is ice |
| `Controllers/BrainBattleControllerView.swift` | answer hexes | consistent | Fonts and radii only; answers already matched the TV |
| `Controllers/MidGroupControllers.swift` | tokens + `8d7f6d` | consistent | Fonts and radii; tan card stock kept |
| `Controllers/TalkGameControllers.swift` | tokens + two dark gradient tails | consistent | Fonts and radii; `0FA968`/`C81E4A` kept as gradient tails of the green and red tokens |
| `Controllers/SpokenGameControllers.swift` | tokens | consistent | Fonts and radii; the TV was brought to match this file |
| `Controllers/HeistControllerView.swift`, `OtherControllerViews.swift`, `PartyControllers.swift` | tokens | drifted | Radii and fonts; the dice face's `E8E8F0` -> `GamePieceColors.faceWhiteEdge` |
| `Controllers/ControllerGameView.swift` | nothing -- it routes a game id to a controller | consistent | Untouched: no styling in the file |

### Phone -- shell and one-stop

| File group | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `App/RootControllerView.swift` | tokens | drifted | Fonts rounded |
| `Views/JoinRoomView.swift` | tokens | drifted | Icon tile `26` -> 24, `16` -> 18, `12` -> 14; fonts; haptic on the server toggle |
| `Views/WaitingView.swift` | tokens | drifted | Icon tile `28` -> 24, row `16` -> 18; fonts |
| `Views/Voice/TVMicController.swift` | `Color.green`, semantic fonts, no haptic | ad-hoc | `PhonePlayDesign.green`; `.gray` -> `text3`; fonts rounded; haptic on "Take the mic" |
| `OneStop/OneStopKit.swift` | tokens | consistent | `OneStopPressStyle` was a duplicated body -> `typealias` for `PhonePlayPressStyle` |
| `OneStop/ProfileViews.swift` | `ProfilePalette` = Apple's `.red/.orange/...`; stat tiles `.cyan/.yellow/...` | ad-hoc | Ten swatches are the Phone Play palette (plus `teal 2BD9C0` and `brown C98A5E`, the two names the server has that Phone Play does not); stat tiles tokenized; haptics on colour and avatar picks |
| `OneStop/GameNightViews.swift` | literal `.cyan/.yellow/.orange`, semantic fonts | ad-hoc | Tokens; fonts; `16`/`12` radii -> 18/14; haptics on header, shuffle, remove, end-night |
| `OneStop/QuizMakerViews.swift` | literal `.green/.teal/.cyan/.orange`, semantic fonts | ad-hoc | Tokens; fonts; haptics on clear, start-over, correct-answer, expand, delete |
| `OneStop/TeamsViews.swift` | tokens | drifted | Fonts; haptic on shuffle |

### Shared (compiled into both targets)

These cannot reference either kit, so the palette exists in a third copy.
Each now says so and carries the same numbers.

| File | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `Shared/Views/RulesInterstitialView.swift` | scattered private statics: `tvAccent 22D3EE`, panel `120C2C`, radii 44/22/16 | ad-hoc | One documented `RulesDesign` token block; cyan `38D6F5`, panel `15151F`, radii 24/18/14; `TVRuleRow` reads the same block |
| `Shared/Models/HeistTypes.swift` | `.red` / `.cyan` / `.yellow` | ad-hoc | `FF4D6D` / `38D6F5` / `FFC531` with a keep-in-step note |
| `Shared/Views/BrainShapeView.swift` | `38BDF8` | ad-hoc | `38D6F5` |
| `Shared/Constants.swift` | the `Color(hex:)` helper | consistent | untouched |

### TV -- the kit

| File | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `Theme/TVShellTheme.swift` | `ShellTheme` with its own hexes and `cornerRadius: 36`/`24` defaults | drifted | Palette aligned (section 3); gained `panel2`, `green`, `red`, `yellow`, `purple`, `indigo`, opaque `text2`/`text3`, `cardRadius`/`buttonRadius`/`chipRadius`, `gradient()`; brand gradient, mesh field, ambient blobs and confetti read the tokens; glass and button radii read the tokens |
| `Theme/TVTheme.swift` | `TVTheme` with a third set of values (`gold fbbf24`, `danger f43f5e`, `success 4ade80`, text at 0.62/0.38) | drifted | Forwards every shared role to `ShellTheme`; `TVGlassCard` default 28 -> 24; winner banner 34 -> 24; the seven moods documented as TV-only |

### TV -- shell screens

| File | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `TVGameSelectionView.swift` | `ShellTheme` + raw `.cyan/.green/.gray` | drifted | Tokens; `40` glass surface -> 24; `16` -> 18; fonts. The violet depth-shadow stack (`3B1C7A/2A1358/1A0B3A`) and card inset `150F30` kept: they are shades of `ShellTheme.violet` |
| `TVLobbyView.swift` | `ShellTheme` + raw colours | drifted | Tokens; `40`/`44`/`36` panels -> 24; fonts; panel inset `1B1440` kept |
| `TVResultsView.swift` | `ShellTheme` + a medal palette | consistent | Fonts and radii. Medal gold/silver/bronze kept -- they are medals |
| `TVGameNightViews.swift` | `ShellTheme` + raw colours | drifted | Tokens; `26`/`36` -> 24; fonts |
| `TVTeamsViews.swift` | `ShellTheme` | consistent | Radii and fonts |
| `TVGameBoardView.swift` | nothing -- it routes a game id to a board | consistent | Untouched: no styling in the file |
| `Voice/TVVoiceOverlay.swift` | raw `.green`, `.gray`, semantic fonts | ad-hoc | `TVTheme.green`, `TVTheme.text3`, rounded fonts |
| `TVGameCardArt.swift` | nine per-category gradients | consistent (identity) | Untouched. The file documents why the nine categories have their own hues; folding them into the tokens would undo the thing it exists for |

### TV -- game boards

| File | Used before | Verdict | Changed |
| --- | --- | --- | --- |
| `TVClassicGameBoards.swift` | 42 raw SwiftUI colours, 44 hexes, three backdrops, 20 radii | ad-hoc | All raw colours -> `TVTheme`; backdrops -> `TVTheme.bg` (Mafia's night `00000a` kept); stale `22d3ee`/`f472b6`/`a855f7` -> tokens; radii and fonts. Connect 4 discs, the pong arena blues and the treasure-hunt wood kept as identity |
| `TVMidGroupBoards.swift` | 33 raw colours, Codenames hexes | ad-hoc | Tokens throughout; Codenames red/blue -> tokens; radii and fonts |
| `TVDuelGameBoards.swift` | 27 raw colours, 22 hexes | ad-hoc | Tokens; the Defuse wire table bridges the tokens through `UIColor(_:)` and gains the missing `black` case; radii and fonts |
| `TVTriviaBoardView.swift` | 43 loose hexes | ad-hoc | `TShowPalette` gains named stage tokens (`stageInk`, `stageDeep`, `spotlight`, `goldWarm`, `hotPink`, `magenta`, ...); role colours -> `TVTheme`; power colours now the phone's; radii and fonts |
| `TVBrainBattleBoardView.swift` | 34 hexes | drifted | Skill colours and the timer ring -> tokens; answers A-D and the night sky kept; radii and fonts |
| `TVSoloGameBoards.swift` | 12 raw colours, 42 hexes | drifted | Raw colours and stale `22d3ee` -> tokens; radii and fonts. The 2048 tile ramp, `SnakePalette` and the brick-breaker ice kept as identity |
| `TVPokerBoardView.swift` | `PKTColors` casino palette, 38 hexes | consistent (identity) | `PKTColors.mint` -> `TVTheme.green`; radii and fonts. Felt, leather, brass and card hexes kept; the phone's Poker controller already matches them |
| `TVRouletteBoardView.swift` | 31 hexes | consistent (identity) | One raw colour and the radii and fonts. Wood, brass, felt and pocket colours kept; the phone's pockets already match |
| `TVChessBoardView.swift` | 7 raw colours, 5 hexes | drifted | Tokens; radii and fonts. Squares and pieces kept -- the phone was brought to them |
| `TVSnakeLadderBoardView.swift` | 10 raw colours | ad-hoc | Tokens; radii and fonts. The drawn pill sprite in `UIBezierPath` keeps its own radius |
| `TVHeistBoardView.swift`, `TVRevealBoardView.swift`, `TVPartyGameBoards.swift`, `TVBlastRunnersBoardView.swift` | raw colours | ad-hoc | Tokens; SceneKit palettes bridge the tokens through `UIColor(_:)` instead of re-picking them; radii and fonts. The Blast Runners stage (`05070a`) stays near-black so the 3D scene reads |
| `TVSpokenGameBoards.swift` | `SpokenTVStyle` part tokens part hexes | drifted | Team colours now the phone's; the verdict banner's `60` radius -> 24; radii and fonts |
| `TVTalkGameKit.swift`, `TVHotTakesBoardView.swift`, `TVTwentyQuestionsBoardView.swift` | `TalkPalette` / category hexes | ad-hoc | FOR/AGAINST pair, verdicts and categories -> tokens, which is what the phone already used; radii and fonts |

---

## 5. What was deliberately left alone

- **The seven `TVPalette` moods** -- a board's backdrop story. The TV's own.
- **`ShellTheme.violet` and `.gold`**, and the `night`/`deepBlue` ambient
  stops. Phone Play has no equivalent.
- **Per-game identity palettes that already agreed across screens**: the
  ten-step avatar wheel, Brain Battle's answers, Connect 4's discs, the
  chess board, the roulette pockets, Trivia's tiles (after the phone
  followed the TV).
- **Material colours**: Poker's felt and brass, roulette's wood, carrom's
  wood ring, Codenames' tan card stock, the 2048 tile ramp, `SnakePalette`,
  Trivia's ice sheet, the medal gold/silver/bronze, the violet depth-shadow
  stack. A card is off-white because cards are off-white.
- **`TVGameCardArt`'s nine category gradients** and **Heads Up's eight deck
  gradients** -- both exist so a grid can be scanned by colour.
- **`Color.white.opacity(...)`** for hairlines, ghost fills and chip washes.
  This is Phone Play's own idiom (`PhonePlayGhostButton` is `0.07`,
  `PhonePlayTopBar` is `0.08`), not an ad-hoc style.
- **The two monospaced faces**: `ShellTheme.mono`, and the server-address
  field, which wants fixed-width digits. Every `.monospacedDigit()` chain
  survives on top of the rounded face.
- **WordDay's `design: .serif`** dictionary word -- an editorial choice
  inside the reference itself.
- **Radii below 14** (12, 10, 9, 8, 7, 6, 5, 3, 2). Each belongs to a game
  piece or a drawn sprite and is sized from the piece.

---

## 6. Scope

This was a styling pass. No behaviour, action payload, state key, layout or
socket event changed.
