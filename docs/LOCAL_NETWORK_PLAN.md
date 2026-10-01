# Local-Network / Offline Play Plan

Goal: a party with no reliable internet can still play — one device hosts,
everyone else joins over the local network. This is phased because true
offline (no server at all) needs client-side engines that do not exist yet.

## Phase 1 — LAN host (small work, big payoff)

- Run the Flask server on the host device (laptop) with `--host=0.0.0.0`.
- Phones join via `http://<host-lan-ip>:5000`; the TV shows
  `/native/qr/<code>` encoding that LAN URL.
- Add a "Copy LAN join link" affordance next to the QR on the TV lobby so
  the host can share the exact URL (IP + port) without typing.
- No code changes to game logic; document the one command in the README.

## Phase 2 — Resilient reconnects

- Client-side rejoin with the same `playerID` after a drop (server already
  keys players by id; needs a `rejoin_room` event that re-attaches the sid).
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
