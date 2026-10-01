# Local-Network / Offline Play Plan

Goal: a party with no reliable internet can still play — one device hosts,
everyone else joins over the local network. This is phased because true
offline (no server at all) needs client-side engines that do not exist yet.

## Phase 1 — LAN host (done)

- `python app.py` already serves on `0.0.0.0:5000`.
- The QR (`/native/qr/<code>`) encodes this server's own `/join/<code>`
  page by default; `NATIVE_JOIN_URL_BASE` points it at a LAN address.
- The TV lobby prints the join link (host, port, code) under the QR -- the
  tvOS stand-in for "copy link", since a TV has no clipboard to share.
- Apps: the phone's join screen has a **Server** field (saved in
  `UserDefaults`); the TV reads an `AuroraServerURL` Info.plist value. Both
  allow plain HTTP to local-network hosts (`NSAllowsLocalNetworking`).
- The one-command setup is documented in [GAME_NIGHT.md](GAME_NIGHT.md).

## Phase 2 — Resilient reconnects (done)

- No new event was needed: `join_room` with an existing `playerID` already
  re-attaches the new sid to the seat. `GameSocketManager.onConnected`
  hooks re-send it after every reconnect -- phones as their player, the TV
  as a board (`isTV`).
- The phone stays on its controller across a rejoin (`room_joined` is
  routed by room state), and the server pushes `private_state` straight
  away.
- Room state survives transient disconnects; the reaper already spares
  rooms with humans connected.

## Phase 3 — True offline (future)

- Port the `native_hub` engine core to Swift so the TV can host a room
  with zero network (phones connect over MultipeerConnectivity or
  local WebSocket).
- This is a large port; do not start it until Phase 2 ships and the
  engine API is stable.

## Non-goals

- Internet matchmaking / random opponents. AuroraPlay is a party-room
  product: the room code is the lobby.
