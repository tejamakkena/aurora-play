# Web controller

The phone controller for TV rooms, in the browser: `/play` (or `/play/<ROOM CODE>`).
No install and no TestFlight build; it is plain static files served by Flask.

It is a port of the iOS controller, not a second design. It speaks the same
`/native` Socket.IO protocol (so the server cannot tell it from the app) and wears
the same Phone Play look (`static/play/play.css` carries the `PhonePlayDesign`
tokens).

## What it covers

- Join by code or the `/join/<code>` link, loading and error states, "Rejoin" for a
  room left in the last three hours, reconnect re-seating.
- Lobby: room code and invite share, players with ready state, teams (tap to
  switch), and for the host: Game Night planner, make-your-own quiz, team setup,
  question language, bots.
- Rules gate (host taps Begin), every live TV game's controller, results with
  Play Again, Game Night standings between games.
- Voice quizmaster mic (browser speech recognition; hidden where unsupported).

Not included on purpose: Mind Gym, Phone Play games, Travel/Road Trip, profiles.

## Layout

| Path | What |
| --- | --- |
| `templates/play.html` | Page shell; scripts are listed by `games/native_hub/qr.py` |
| `static/play/play.css` | Design tokens and components |
| `static/play/js/dom.js` | `h()` element builder and `patch()` DOM morphing |
| `static/play/js/session.js` | Screen state machine (port of `ControllerRootViewModel`) |
| `static/play/js/screens.js`, `lobby.js`, `onestop.js`, `voice.js` | Join, rules, results, lobby, Game Night, quiz maker, mic |
| `static/play/js/games/*.js` | One controller factory per game: `AP.controllers.<gameID>` |

A controller is `function (ctx) { ...; return function render(privateData) { return node; }; }`.
It re-renders on every `private_state`; `patch()` keeps focus, scroll and CSS
transitions, the way SwiftUI keeps view state. `ctx.send(action, data)` emits
`game_action`.

## Keeping it in step with the app

`tests/test_web_controller.py` fails when a live game has no web controller, when a
controller has no engine, or when `games.js` drifts from the server registry. When a
Swift controller changes, change the matching file in `static/play/js/games/`.

`static/play/vendor/socket.io.min.js` is Socket.IO client 4.5.4 (MIT), vendored so the
controller works on a LAN party with no internet.
