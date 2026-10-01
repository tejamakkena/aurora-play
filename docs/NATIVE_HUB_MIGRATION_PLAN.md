# Legacy-to-`native_hub` Migration Plan

The 17 legacy Flask/Socket.IO browser games and the `native_hub` engine
architecture currently coexist. `native_hub` is the target: unit-testable
engines, public/private state separation, a central room manager with
reaping, and one `/native` Socket.IO namespace. This doc phases the
consolidation so no single PR has to do it all.

## Phase 1 — Harden the seam (done)

- Legacy templates/JS moved behind `CleanupManager` (listener/timer teardown).
- Shared `utils/room_manager.py` room lifecycle; bot-aware reaping.
- `SOCKETIO_CORS_ORIGINS` default tightened to same-origin.
- No-emoji CI gate (`.github/workflows/no-emoji-check.yml`).

## Phase 2 — Engine ports (next)

Port legacy games one at a time as `native_hub` engines, keeping the
legacy route until the port is proven:

1. Trivia / KBC — content packs (`en`/`te`/`hi`) already live here.
2. Tambola, Poker, Mafia, Pictionary — the high-traffic party games.
3. The rest (snake, roulette, tictactoe, memory, pong, etc.).

Each port: engine + registry entry + `GameID` allowlist + Swift `Game.swift`
metadata + bot policy if it needs seat-fillers. Delete the legacy
`games/<name>/` module and template only after the port ships.

## Phase 3 — Retire legacy transports

- Remove per-game Socket.IO namespaces; everything goes through `/native`.
- Remove module-level room dicts in favor of `RoomRegistry`.
- Keep the legacy HTML pages as thin clients during transition, then
  replace with the TV/phone clients.

## Phase 4 — Single client story

- Web becomes a join/display client only (no per-game JS).
- iOS `GameLabTV` + `GameLabController` are the primary clients.
- QR join (`/native/qr/<code>`) is the default onboarding path.
