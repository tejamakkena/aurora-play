import Foundation
import SwiftUI

/// Boards for the games playable with the Siri Remote alone.
///
/// These differ from every other board in the app: they both render the game
/// *and* collect input, sending it through `TVRootViewModel.sendAction` because
/// there is no phone in the room to send it for them.

// MARK: - Shared chrome

private struct SoloHUD: View {
    let title: String
    let score: Int
    let subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("SCORE").font(.caption.bold()).tracking(3)
                    .foregroundColor(.white.opacity(0.4))
                Text("\(score)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.cyan)
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 50)
    }
}

private struct RemoteHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundColor(.white.opacity(0.35))
            .padding(.bottom, 40)
    }
}

private struct GameOverBanner: View {
    let score: Int
    var body: some View {
        VStack(spacing: 10) {
            Text("GAME OVER").font(.system(size: 44, weight: .heavy)).tracking(4)
                .foregroundColor(.red)
            Text("Final score \(score)").font(.title2).foregroundColor(.white.opacity(0.7))
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.75)))
    }
}

// MARK: - Neon Snake

/// Distinct neon hues per snake so multiple players (or multiple synthetic
/// snakes) read as separate creatures rather than one shared color.
enum SnakePalette {
    static let heads: [Color] = [
        Color(hex: "5eead4"), Color(hex: "f472b6"),
        Color(hex: "a3e635"), Color(hex: "fbbf24"),
    ]
    static let bodies: [Color] = [
        Color(hex: "22d3ee"), Color(hex: "ec4899"),
        Color(hex: "65a30d"), Color(hex: "f59e0b"),
    ]
    static func head(_ i: Int) -> Color { heads[i % heads.count] }
    static func body(_ i: Int) -> Color { bodies[i % bodies.count] }
}

struct SnakeState {
    // Mirrors NeonSnakeEngine's own W/H default so the first frame drawn
    // before any server state arrives is already the right shape.
    var width = 32, height = 18
    var food = (x: 10, y: 10)
    var bodies: [[(x: Int, y: Int)]] = []
    var colors: [Bool] = []          // alive flags, parallel to bodies
    var score = 0
    var finished = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["width"]?.value as? Int  { width = v }
        if let v = data["height"]?.value as? Int { height = v }
        if let f = data["food"]?.value as? [String: Any],
           let fx = f["x"] as? Int, let fy = f["y"] as? Int { food = (fx, fy) }
        if let v = data["finished"]?.value as? Bool { finished = v }
        if let snakes = data["snakes"]?.value as? [Any] {
            bodies = []; colors = []; score = 0
            for raw in snakes {
                guard let s = raw as? [String: Any] else { continue }
                let cells = (s["body"] as? [Any] ?? []).compactMap { item -> (x: Int, y: Int)? in
                    guard let c = item as? [String: Any],
                          let x = c["x"] as? Int, let y = c["y"] as? Int else { return nil }
                    return (x, y)
                }
                bodies.append(cells)
                colors.append(s["alive"] as? Bool ?? false)
                score = max(score, s["score"] as? Int ?? 0)
            }
        }
    }
}

@MainActor final class SnakeBoardViewModel: ObservableObject {
    @Published private(set) var state = SnakeState()
    private let socket = GameSocketManager.shared

    // Motion interpolation, the same idea as BrickViewModel's ball: the
    // server only steps the snake at NeonSnakeEngine.tick_hz (8 Hz), and
    // rendering each new grid position the instant it arrives is exactly
    // what read as "just a simple block" snapping from cell to cell instead
    // of a snake in motion. Every body array here is indexed the same way
    // the engine builds it: a new head is always inserted at index 0, so
    // (barring growth) index i's cell after a tick is exactly where index
    // i-1's cell was before it -- meaning "previous[i] -> target[i]" is
    // precisely each segment sliding forward into the slot ahead of it,
    // which is what a real snake's body actually looks like in motion.
    private var previousBodies: [[CGPoint]] = []
    private var targetBodies: [[CGPoint]] = []
    private var segmentStart = Date()
    private var segmentDuration: TimeInterval = 1.0 / 8.0
    private var lastUpdate = Date()

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard let self, r.roomCode == roomCode else { return }
            self.apply(r.boardState)
        }
    }

    /// Where segment `seg` of snake `i` should be drawn right now, in grid
    /// units (fractional once a slide is in progress).
    func segment(_ i: Int, _ seg: Int, at now: Date) -> CGPoint {
        guard i < targetBodies.count, seg < targetBodies[i].count else { return .zero }
        let target = targetBodies[i][seg]
        guard i < previousBodies.count, seg < previousBodies[i].count else { return target }
        let previous = previousBodies[i][seg]
        let f = min(1, max(0, now.timeIntervalSince(segmentStart) / max(segmentDuration, 1e-4)))
        return CGPoint(x: previous.x + (target.x - previous.x) * CGFloat(f),
                       y: previous.y + (target.y - previous.y) * CGFloat(f))
    }

    /// The heading a snake is currently facing, derived from its two
    /// frontmost segments (there is no explicit "direction" field on the
    /// wire). Falls back to facing right for a brand new single-cell snake.
    func heading(_ i: Int, at now: Date) -> CGVector {
        guard i < targetBodies.count, targetBodies[i].count >= 2 else { return CGVector(dx: 1, dy: 0) }
        let head = segment(i, 0, at: now)
        let neck = segment(i, 1, at: now)
        let dx = head.x - neck.x, dy = head.y - neck.y
        let len = max(hypot(dx, dy), 1e-4)
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private func apply(_ data: [String: AnyCodable]) {
        let now = Date()
        let hadBodies = !state.bodies.isEmpty
        var next = state
        next.update(from: data)

        segmentDuration = min(0.5, max(1.0 / 60.0, now.timeIntervalSince(lastUpdate)))
        lastUpdate = now
        segmentStart = now

        let newTargets = next.bodies.map { body in
            body.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        }
        if hadBodies {
            previousBodies = next.bodies.indices.map { i -> [CGPoint] in
                let oldBody = i < state.bodies.count ? state.bodies[i] : []
                return next.bodies[i].indices.map { seg -> CGPoint in
                    guard seg < oldBody.count else { return newTargets[i][seg] }
                    return CGPoint(x: CGFloat(oldBody[seg].x), y: CGFloat(oldBody[seg].y))
                }
            }
        } else {
            // First frame (or a fresh game after one finished) -- nothing to
            // slide from, so snap instead of animating in from the origin.
            previousBodies = newTargets
        }
        targetBodies = newTargets

        state = next
    }
}

struct TVNeonSnakeBoardView: View {
    let room: Room
    @EnvironmentObject private var root: TVRootViewModel
    @StateObject private var vm = SnakeBoardViewModel()

    var body: some View {
        // Reported directly as "not full screen", still true after the grid
        // was widened to a landscape 32x18: stacking SoloHUD and RemoteHint
        // above/below the GeometryReader in a VStack ate into the *vertical*
        // space the board's own scale calc measures, so the leftover area
        // was no longer actually 16:9 -- e.g. losing ~150-200pt of height on
        // a 1080p screen skews the remainder to something like a 2.1:1
        // rectangle, and `scale = min(widthScale, heightScale)` then binds
        // on height, rendering the board narrower than the full width with
        // black bars on both sides. Overlaying the HUD/hint on top of a
        // full-bleed board instead, rather than sharing layout flow with it,
        // means the GeometryReader measures the true full-screen area.
        ZStack {
            GeometryReader { geo in
                let margin: CGFloat = 28
                let unitW = CGFloat(max(vm.state.width, 1))
                let unitH = CGFloat(max(vm.state.height, 1))
                let scale = max(1, min((geo.size.width - margin * 2) / unitW,
                                       (geo.size.height - margin * 2) / unitH))

                board(scale: scale)
                    .frame(width: unitW * scale, height: unitH * scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            VStack {
                SoloHUD(title: "Neon Snake", score: vm.state.score, subtitle: nil)
                Spacer()
                RemoteHint(text: "Swipe or click the remote's edges to steer")
            }
            .allowsHitTesting(false)
        }
        .remoteDPad { event in
            // Now that "Invite Friends" can put phones in this same room
            // (see TVGameSelectionView.soloChoiceGame), the TV itself is no
            // longer necessarily a registered player -- only true in solo
            // mode is the deviceID this would send actually a player the
            // server recognizes.
            guard root.isSolo, let dir = event.directionName else { return }
            root.sendAction("turn", ["direction": dir])
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    // MARK: Board

    private func board(scale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: vm.state.finished)) { timeline in
            Canvas { context, _ in
                paint(&context, scale: scale, now: timeline.date)
            }
        }
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: "051014"), Color(hex: "0a1f22")],
                               startPoint: .top, endPoint: .bottom)
                // A faint grid so the empty board still reads as a play
                // field, not just a black rectangle -- legibility matters
                // more than the neon spectacle here.
                Canvas { ctx, size in
                    let cols = max(vm.state.width, 1), rows = max(vm.state.height, 1)
                    var grid = Path()
                    for c in 0...cols {
                        let x = CGFloat(c) / CGFloat(cols) * size.width
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for r in 0...rows {
                        let y = CGFloat(r) / CGFloat(rows) * size.height
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    ctx.stroke(grid, with: .color(.cyan.opacity(0.05)), lineWidth: 1)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 3)
        )
        .shadow(color: .cyan.opacity(0.18), radius: 30)
        .overlay { if vm.state.finished { GameOverBanner(score: vm.state.score) } }
    }

    private func paint(_ ctx: inout GraphicsContext, scale: CGFloat, now: Date) {
        // ---- Food -------------------------------------------------------
        let f = vm.state.food
        let foodCenter = CGPoint(x: (CGFloat(f.x) + 0.5) * scale, y: (CGFloat(f.y) + 0.5) * scale)
        let foodR = scale * 0.32
        let pulse = CGFloat(1.0 + 0.12 * sin(now.timeIntervalSinceReferenceDate * 4))
        ctx.fill(Path(ellipseIn: CGRect(x: foodCenter.x - foodR * 2.2, y: foodCenter.y - foodR * 2.2,
                                        width: foodR * 4.4, height: foodR * 4.4)),
                 with: .radialGradient(Gradient(colors: [.yellow.opacity(0.35), .clear]),
                                       center: foodCenter, startRadius: 0, endRadius: foodR * 2.2))
        ctx.fill(Path(ellipseIn: CGRect(x: foodCenter.x - foodR * pulse, y: foodCenter.y - foodR * pulse,
                                        width: foodR * 2 * pulse, height: foodR * 2 * pulse)),
                 with: .color(.yellow))

        // ---- Snakes -------------------------------------------------------
        for i in vm.state.bodies.indices {
            let alive = i < vm.state.colors.count ? vm.state.colors[i] : false
            let segCount = vm.state.bodies[i].count
            guard segCount > 0 else { continue }
            let points = (0..<segCount).map { seg in
                let p = vm.segment(i, seg, at: now)
                return CGPoint(x: (p.x + 0.5) * scale, y: (p.y + 0.5) * scale)
            }
            let bodyColor = alive ? SnakePalette.body(i) : Color.white.opacity(0.25)
            let headColor = alive ? SnakePalette.head(i) : Color.white.opacity(0.4)
            let lineWidth = max(4, scale * 0.74)

            // A continuous stroked path through every segment's center reads
            // as one smooth creature instead of a checkerboard of squares.
            // The engine is still a discrete grid stepper underneath --
            // every turn is a hard 90-degree step at the next tick, and
            // genuinely continuous curving motion would need a full
            // continuous-position/heading rewrite of NeonSnakeEngine, out
            // of scope here -- but the path drawn through those grid points
            // doesn't have to trace them as straight segments. Running it
            // through a midpoint quadratic spline (the standard "round a
            // polyline's corners" trick: curve toward the midpoint of each
            // pair of segments, using the shared grid point as the curve's
            // control) turns every corner into a soft arc instead of a
            // sharp angle. Reported directly as wanting "smooth curvy...
            // turn."
            if points.count >= 2 {
                var spine = Path()
                spine.move(to: points[0])
                if points.count == 2 {
                    spine.addLine(to: points[1])
                } else {
                    // Named idx, not i, to avoid shadowing the outer per-snake
                    // loop's own `i` (this snake's index in vm.state.bodies).
                    for idx in 1..<(points.count - 1) {
                        let current = points[idx]
                        let next = points[idx + 1]
                        let midToNext = CGPoint(x: (current.x + next.x) / 2,
                                                 y: (current.y + next.y) / 2)
                        spine.addQuadCurve(to: midToNext, control: current)
                    }
                    spine.addLine(to: points[points.count - 1])
                }

                if alive {
                    // Soft neon glow underneath the crisp body -- Neon
                    // Snake's whole aesthetic -- without drowning the grid.
                    ctx.stroke(spine, with: .color(bodyColor.opacity(0.35)),
                               style: StrokeStyle(lineWidth: lineWidth * 1.9, lineCap: .round, lineJoin: .round))
                }
                ctx.stroke(spine, with: .linearGradient(
                    Gradient(colors: [headColor.opacity(0.95), bodyColor.opacity(alive ? 0.85 : 0.4)]),
                    startPoint: points.first!, endPoint: points.last!),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }

            // A distinct, slightly larger head with eyes pointing the way
            // it's moving, so the snake reads as a creature rather than a
            // line with no front.
            let head = points[0]
            let headR = lineWidth * 0.62
            if alive {
                ctx.fill(Path(ellipseIn: CGRect(x: head.x - headR * 1.8, y: head.y - headR * 1.8,
                                                width: headR * 3.6, height: headR * 3.6)),
                         with: .radialGradient(Gradient(colors: [headColor.opacity(0.4), .clear]),
                                               center: head, startRadius: 0, endRadius: headR * 1.8))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - headR, y: head.y - headR,
                                            width: headR * 2, height: headR * 2)),
                     with: .color(headColor))

            let dir = vm.heading(i, at: now)
            let side = CGVector(dx: -dir.dy, dy: dir.dx)          // perpendicular to travel
            let eyeForward = headR * 0.4, eyeSide = headR * 0.42, eyeR = max(1.5, headR * 0.22)
            let eyeSigns: [CGFloat] = [-1, 1]
            for sign in eyeSigns {
                let ex = head.x + dir.dx * eyeForward + side.dx * eyeSide * sign
                let ey = head.y + dir.dy * eyeForward + side.dy * eyeSide * sign
                ctx.fill(Path(ellipseIn: CGRect(x: ex - eyeR, y: ey - eyeR, width: eyeR * 2, height: eyeR * 2)),
                         with: .color(alive ? .white : .black.opacity(0.5)))
                if alive {
                    let pupilR = eyeR * 0.5
                    let px = ex + dir.dx * pupilR * 0.6, py = ey + dir.dy * pupilR * 0.6
                    ctx.fill(Path(ellipseIn: CGRect(x: px - pupilR, y: py - pupilR, width: pupilR * 2, height: pupilR * 2)),
                             with: .color(.black))
                }
            }
        }
    }
}

// MARK: - 2048

/// One occupied cell. `id` is the stable identity `Twenty48Engine.tile_ids`
/// hands out on spawn and carries through a slide -- without it, a client
/// only ever sees "the value at index 0 became 0 and the value at index 3
/// changed", which is indistinguishable from a merge or a fresh spawn
/// landing on 3. With a stable id, the same tile view can be repositioned
/// (`.position`) across a swipe instead of a whole grid of numbers being
/// re-rendered in place -- which is what actually reads as sliding rather
/// than "blocky, instant" change.
struct Twenty48Tile: Identifiable, Equatable {
    let id: Int
    var value: Int
    var row: Int
    var col: Int
    var merged: Bool     // this tile is the survivor of a merge this move
    var spawned: Bool    // this tile is brand new this move
}

struct Twenty48State {
    var size = 4
    var tiles: [Twenty48Tile] = []
    var score = 0
    var best = 0
    var done = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["size"]?.value as? Int { size = v }
        if let boards = data["boards"]?.value as? [Any],
           let first = boards.first as? [String: Any] {
            let mergedIDs = Set((first["merged"] as? [Any] ?? []).compactMap { jsonInt($0) })
            let spawnedID = jsonInt(first["spawned"])
            if let raw = first["tiles"] as? [Any] {
                tiles = raw.compactMap { item -> Twenty48Tile? in
                    guard let t = item as? [String: Any],
                          let id = jsonInt(t["id"]), let value = jsonInt(t["value"]),
                          let row = jsonInt(t["row"]), let col = jsonInt(t["col"])
                    else { return nil }
                    return Twenty48Tile(id: id, value: value, row: row, col: col,
                                         merged: mergedIDs.contains(id), spawned: id == spawnedID)
                }
            }
            if let v = first["score"] as? Int { score = v }
            if let v = first["best"]  as? Int { best = v }
            if let v = first["done"]  as? Bool { done = v }
        }
    }
}

@MainActor final class Twenty48ViewModel: ObservableObject {
    @Published var state = Twenty48State()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

/// The familiar 2048 ramp — warmer as the value climbs.
private func twenty48Color(for value: Int) -> Color {
    switch value {
    case 0:     return .white.opacity(0.06)
    case 2:     return Color(hex: "eee4da")
    case 4:     return Color(hex: "ede0c8")
    case 8:     return Color(hex: "f2b179")
    case 16:    return Color(hex: "f59563")
    case 32:    return Color(hex: "f67c5f")
    case 64:    return Color(hex: "f65e3b")
    case 128:   return Color(hex: "edcf72")
    case 256:   return Color(hex: "edcc61")
    case 512:   return Color(hex: "edc850")
    case 1024:  return Color(hex: "edc53f")
    default:    return Color(hex: "edc22e")
    }
}

/// One tile. A stable `id` (see `Twenty48Tile`) means SwiftUI reuses the same
/// view instance for the same physical tile across a swipe, so its `.position`
/// change is a real, animatable move instead of a teardown-and-rebuild -- and
/// this view can react to *its own* tile flipping to `merged` with a pop, and
/// to first appearing already flagged `spawned` with a fade-and-grow-in.
private struct Twenty48TileView: View {
    let tile: Twenty48Tile
    let cellSize: CGFloat
    @State private var popScale: CGFloat = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(twenty48Color(for: tile.value))
            .frame(width: cellSize, height: cellSize)
            .overlay(
                Text(tile.value > 0 ? "\(tile.value)" : "")
                    .font(.system(size: tile.value > 999 ? 40 : 52, weight: .heavy, design: .rounded))
                    .foregroundColor(tile.value <= 4 ? Color(hex: "776e65") : .white)
            )
            .scaleEffect(popScale)
            .transition(.scale(scale: 0.35).combined(with: .opacity))
            .onChange(of: tile.merged) { merged in
                guard merged else { return }
                pop()
            }
    }

    /// A quick overshoot-and-settle, distinct from the slide/fade every other
    /// tile is doing, so a merge reads as an event rather than a value that
    /// silently doubled.
    private func pop() {
        popScale = 1.0
        withAnimation(.easeOut(duration: 0.08)) { popScale = 1.16 }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5).delay(0.08)) { popScale = 1.0 }
    }
}

struct TVTwenty48BoardView: View {
    let room: Room
    @EnvironmentObject private var root: TVRootViewModel
    @StateObject private var vm = Twenty48ViewModel()

    private let cell: CGFloat = 130
    private let gap: CGFloat = 12

    private var boardExtent: CGFloat {
        let n = CGFloat(max(vm.state.size, 1))
        return n * cell + max(n - 1, 0) * gap
    }

    private func center(row: Int, col: Int) -> CGPoint {
        CGPoint(x: CGFloat(col) * (cell + gap) + cell / 2,
                y: CGFloat(row) * (cell + gap) + cell / 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            SoloHUD(title: "2048", score: vm.state.score,
                    subtitle: "best tile \(vm.state.best)")
            Spacer()
            ZStack {
                // Empty-slot backdrop. Static, so only the tiles layered on
                // top of it ever move -- the grid itself is the one thing
                // that should look perfectly steady while everything slides.
                VStack(spacing: gap) {
                    ForEach(0..<vm.state.size, id: \.self) { _ in
                        HStack(spacing: gap) {
                            ForEach(0..<vm.state.size, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }

                ZStack {
                    ForEach(vm.state.tiles) { tile in
                        Twenty48TileView(tile: tile, cellSize: cell)
                            .position(center(row: tile.row, col: tile.col))
                    }
                }
                .frame(width: boardExtent, height: boardExtent)
                .animation(.easeInOut(duration: 0.15), value: vm.state.tiles)

                if vm.state.done { GameOverBanner(score: vm.state.score) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.05)))
            Spacer()
            RemoteHint(text: "Swipe the remote's touch surface to slide the tiles")
        }
        .remoteSwipe { event in
            // See TVNeonSnakeBoardView's identical guard: only in solo mode
            // is the TV's own deviceID a player the server recognizes.
            guard root.isSolo, let dir = event.directionName else { return }
            root.sendAction("swipe", ["direction": dir])
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Brick Breaker

/// Read a JSON number that may legitimately arrive as either an integer or a
/// double.
///
/// This is the fix for a whole class of silent-decode bug this project keeps
/// hitting. `BrickState` used to read every coordinate with a bare
/// `as? Double`, and *every one of those casts failed*:
///
///  * `AnyCodable.init(from:)` (ios/Shared/Networking/GameMessage.swift) tries
///    `Int` before `Double`, so any whole number decodes as `Int` and
///    `as? Double` on the resulting `Any` returns nil — Swift does no implicit
///    numeric bridging across an `Any` box.
///  * `GameSocketManager.on(_:)` re-serialises the socket payload through
///    `JSONSerialization`, which writes an integral double (`5.0`) back out as
///    `5` — so even a value Python emitted as a float arrives as an `Int`.
///  * And the engine emitted honest ints anyway: brick rows were laid out with
///    `12 + r * 7`, pure integer arithmetic that `round(_, 1)` leaves as `int`.
///
/// Net effect: `bricks` was `compactMap`ped down to an empty array on every
/// single frame. The wall was never drawn at all — which is exactly what "no
/// dropping blocks" described. Nothing logged, nothing threw; the value simply
/// stayed at its default.
private func jsonDouble(_ any: Any?) -> Double? {
    if any is Bool { return nil }        // Bool bridges to NSNumber; never read it as 1/0
    if let v = any as? Double { return v }
    if let v = any as? Int { return Double(v) }
    if let v = any as? NSNumber { return v.doubleValue }
    return nil
}

/// The same tolerance in the other direction, for counters the server may
/// round-trip as a double.
private func jsonInt(_ any: Any?) -> Int? {
    if any is Bool { return nil }
    if let v = any as? Int { return v }
    if let v = any as? Double { return Int(v.rounded()) }
    if let v = any as? NSNumber { return v.intValue }
    return nil
}

struct BrickTile: Equatable {
    let id: Int
    let row: Int
    let x, y, w, h: Double
}

struct BrickState {
    // Defaults mirror BrickBreakerEngine's own constants so the first frame
    // drawn before any server state arrives is already the right shape.
    var width: Double = 100
    var height: Double = 62
    var ball = (x: 50.0, y: 54.9)
    var ballRadius: Double = 1.1
    var paddle: Double = 50
    var paddleWidth: Double = 16
    var paddleY: Double = 56
    var paddleHeight: Double = 1.8
    var bricks: [BrickTile] = []
    var lives = 3
    var score = 0
    var serving = true
    var won = false
    var finished = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = jsonDouble(data["width"]?.value)        { width = v }
        if let v = jsonDouble(data["height"]?.value)       { height = v }
        if let b = data["ball"]?.value as? [String: Any],
           let x = jsonDouble(b["x"]), let y = jsonDouble(b["y"]) { ball = (x, y) }
        if let v = jsonDouble(data["ballR"]?.value)        { ballRadius = v }
        if let v = jsonDouble(data["paddle"]?.value)       { paddle = v }
        if let v = jsonDouble(data["paddleWidth"]?.value)  { paddleWidth = v }
        if let v = jsonDouble(data["paddleY"]?.value)      { paddleY = v }
        if let v = jsonDouble(data["paddleHeight"]?.value) { paddleHeight = v }
        if let v = jsonInt(data["lives"]?.value)           { lives = v }
        if let v = jsonInt(data["score"]?.value)           { score = v }
        if let v = data["serving"]?.value  as? Bool        { serving = v }
        if let v = data["won"]?.value      as? Bool        { won = v }
        if let v = data["finished"]?.value as? Bool        { finished = v }
        if let raw = data["bricks"]?.value as? [Any] {
            bricks = raw.compactMap { item in
                guard let b = item as? [String: Any],
                      let id = jsonInt(b["id"]),
                      let x = jsonDouble(b["x"]), let y = jsonDouble(b["y"]),
                      let w = jsonDouble(b["w"]), let h = jsonDouble(b["h"])
                else { return nil }
                return BrickTile(id: id, row: jsonInt(b["row"]) ?? 0, x: x, y: y, w: w, h: h)
            }
        }
    }
}

/// One shard thrown off a brick as it shatters. Positions are in arena units,
/// so a particle scales with the board like everything else.
struct BrickParticle: Identifiable {
    let id = UUID()
    let origin: CGPoint
    let velocity: CGVector
    let born: Date
    let life: Double
    let tint: Color
    let size: Double
}

/// Per-row colour bands, each a three-stop ramp so a brick reads as a moulded
/// solid rather than a flat rectangle.
enum BrickPalette {
    static let bands: [(light: Color, mid: Color, dark: Color)] = [
        (Color(hex: "ffd0d6"), Color(hex: "ff5f6d"), Color(hex: "9f1239")),
        (Color(hex: "ffe2c2"), Color(hex: "ff9f43"), Color(hex: "b45309")),
        (Color(hex: "fff6c2"), Color(hex: "ffd93d"), Color(hex: "a16207")),
        (Color(hex: "d3f9d0"), Color(hex: "6bd968"), Color(hex: "15803d")),
        (Color(hex: "ccf4f9"), Color(hex: "4dd0e1"), Color(hex: "0e7490")),
        (Color(hex: "ded8ff"), Color(hex: "9b8cff"), Color(hex: "5b21b6")),
    ]

    static func band(row: Int) -> (light: Color, mid: Color, dark: Color) {
        bands[((row % bands.count) + bands.count) % bands.count]
    }
}

@MainActor final class BrickViewModel: ObservableObject {
    @Published private(set) var state = BrickState()
    @Published private(set) var trail: [CGPoint] = []
    @Published private(set) var particles: [BrickParticle] = []

    /// The paddle position this TV is steering, in arena units. Remote input
    /// lands here instantly so the paddle tracks the thumb at full frame rate,
    /// independently of how often it is safe to tell the server about it.
    @Published private(set) var localPaddle: Double?

    private let socket = GameSocketManager.shared

    // Ball interpolation. The server pushes ~30 Hz; the TV draws at 60, so
    // snapping to each new authoritative position is visibly steppy. Drawing
    // between the last two positions costs one frame of latency and nothing
    // else -- the authoritative value is still the only thing being drawn,
    // just on the way to it rather than jumping.
    private var previousBall = CGPoint(x: 50, y: 54.9)
    private var targetBall = CGPoint(x: 50, y: 54.9)
    private var segmentStart = Date()
    private var segmentDuration: TimeInterval = 1.0 / 30.0
    private var lastUpdate = Date()

    // The server silently drops game_action bursts above 30 events per 2 s per
    // socket (ACTION_BURST / ACTION_WINDOW_SECONDS in
    // games/native_hub/socket_events.py), so a 60 Hz stream of paddle
    // positions would spend most of its frames in the bin -- and take every
    // other action from this socket down with it. Cap the wire rate at
    // 12.5 Hz, comfortably inside that budget, and always send a trailing
    // update so the final resting position is never the one that got dropped.
    private let sendInterval: TimeInterval = 0.08
    private var lastSend = Date.distantPast
    private var flush: Task<Void, Never>?

    private let trailLength = 14
    private let particleCap = 260

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.apply(r.boardState)
        }
    }

    /// What the paddle should be drawn at: the locally steered value while this
    /// TV is driving, the server's otherwise (a phone in the room, or before
    /// the first input).
    var displayPaddle: Double { localPaddle ?? state.paddle }

    func ball(at now: Date) -> CGPoint {
        let f = min(1, max(0, now.timeIntervalSince(segmentStart) / max(segmentDuration, 1e-4)))
        return CGPoint(x: previousBall.x + (targetBall.x - previousBall.x) * CGFloat(f),
                       y: previousBall.y + (targetBall.y - previousBall.y) * CGFloat(f))
    }

    /// Point the paddle at `t` (0 = left edge, 1 = right edge of the arena).
    func steer(toFraction t: Double, send: @escaping (Double) -> Void) {
        // Clamped the same way BrickBreakerEngine.handle_action clamps it, so
        // the predicted paddle and the authoritative one agree exactly.
        let half = state.paddleWidth / 2
        let lowest = half
        let highest = max(half, state.width - half)
        let x = min(highest, max(lowest, t * state.width))
        localPaddle = x

        let now = Date()
        let since = now.timeIntervalSince(lastSend)
        if since >= sendInterval {
            lastSend = now
            flush?.cancel()
            flush = nil
            send(x)
        } else if flush == nil {
            let wait = max(0, sendInterval - since)
            flush = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled, let self, let latest = self.localPaddle else { return }
                self.lastSend = Date()
                self.flush = nil
                send(latest)
            }
        }
    }

    // MARK: Private

    private func apply(_ data: [String: AnyCodable]) {
        let now = Date()
        let previous = state
        var next = state
        next.update(from: data)

        // Where the ball is being drawn *right now* becomes the start of the
        // next segment, so a late or early push never makes it jump backwards.
        let drawn = ball(at: now)
        segmentDuration = min(0.2, max(1.0 / 60.0, now.timeIntervalSince(lastUpdate)))
        lastUpdate = now
        segmentStart = now
        previousBall = drawn
        targetBall = CGPoint(x: next.ball.x, y: next.ball.y)

        // A serve, a lost life, or a dropped frame teleports the ball; smearing
        // a trail across that would draw a line through the whole arena.
        let jumped = (next.serving && !previous.serving)
            || hypot(targetBall.x - drawn.x, targetBall.y - drawn.y) > CGFloat(next.width) / 4
        if jumped {
            previousBall = targetBall
            trail = [targetBall]
        } else {
            trail.append(drawn)
            if trail.count > trailLength { trail.removeFirst(trail.count - trailLength) }
        }

        // The server never says "this brick was destroyed" -- the difference
        // between two consecutive brick sets is the only place that event
        // exists, so the burst is spawned from it.
        if !previous.bricks.isEmpty {
            let surviving = Set(next.bricks.map(\.id))
            for brick in previous.bricks where !surviving.contains(brick.id) {
                spawnBurst(for: brick, at: now)
            }
        }
        particles.removeAll { now.timeIntervalSince($0.born) > $0.life }

        state = next
    }

    private func spawnBurst(for brick: BrickTile, at now: Date) {
        let centre = CGPoint(x: CGFloat(brick.x + brick.w / 2),
                             y: CGFloat(brick.y + brick.h / 2))
        let tone = BrickPalette.band(row: brick.row)
        for i in 0..<12 {
            let angle = Double(i) / 12 * 2 * Double.pi + Double.random(in: -0.25...0.25)
            let speed = Double.random(in: 6...22)
            particles.append(BrickParticle(
                origin: centre,
                velocity: CGVector(dx: CGFloat(cos(angle) * speed),
                                   dy: CGFloat(sin(angle) * speed - 5)),
                born: now,
                life: Double.random(in: 0.35...0.75),
                tint: i.isMultiple(of: 2) ? tone.light : tone.mid,
                size: Double.random(in: 0.35...0.9)))
        }
        if particles.count > particleCap {
            particles.removeFirst(particles.count - particleCap)
        }
    }
}

struct TVBrickBreakerBoardView: View {
    let room: Room
    @EnvironmentObject private var root: TVRootViewModel
    @StateObject private var vm = BrickViewModel()
    @State private var showHint = true

    var body: some View {
        GeometryReader { geo in
            // The arena is landscape now (see BrickBreakerEngine's docstring),
            // so this genuinely fills a 16:9 screen instead of leaving two
            // thirds of it black. The HUD and hint float *over* the playfield's
            // own empty top and bottom bands rather than stealing layout height
            // from it, which is what kept the board small even after the
            // GeometryReader scale fix.
            let margin: CGFloat = 24
            let unitW = CGFloat(max(vm.state.width, 1))
            let unitH = CGFloat(max(vm.state.height, 1))
            let scale = max(1, min((geo.size.width - margin * 2) / unitW,
                                   (geo.size.height - margin * 2) / unitH))

            arena(scale: scale)
                .frame(width: unitW * scale, height: unitH * scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .remoteScrub { event in
            // Only in a solo room is this TV's own deviceID a player the
            // server recognises -- an "Invite Friends" room puts real phones
            // in the seats and leaves the TV a spectator board. Verified this
            // guard is *not* what was blocking solo play: createSoloRoom sets
            // isSolo before create_room is emitted and it stays true for the
            // whole .playing screen (ios/GameLabTV/App/RootTVView.swift).
            guard root.isSolo else { return }
            if case .scrub(let t) = event {
                vm.steer(toFraction: t) { x in root.sendAction("paddle", ["x": x]) }
            }
        }
        .onAppear {
            vm.bind(roomCode: room.code)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                withAnimation(.easeOut(duration: 0.6)) { showHint = false }
            }
        }
    }

    // MARK: Arena

    private func arena(scale: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: vm.state.finished)) { timeline in
            Canvas { context, size in
                paint(&context, size: size, scale: scale, now: timeline.date)
            }
        }
        .background(playfield)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color(hex: "67e8f9").opacity(0.65),
                                            Color(hex: "a78bfa").opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 3)
        )
        .shadow(color: Color(hex: "22d3ee").opacity(0.22), radius: 44)
        .overlay(alignment: .top) { hud }
        .overlay { readyBadge }
        .overlay { banner }
        .overlay(alignment: .bottom) { hint }
    }

    private var playfield: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "0b1026"), Color(hex: "160b2b"), Color(hex: "05070f")],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "1d4ed8").opacity(0.30), .clear],
                           center: .top, startRadius: 0, endRadius: 760)
        }
    }

    private func paint(_ ctx: inout GraphicsContext, size: CGSize, scale: CGFloat, now: Date) {
        let s = scale

        // ---- Bricks ---------------------------------------------------------
        // One drawLayer for the whole wall so the drop shadow is a single
        // filter rather than one per brick.
        if !vm.state.bricks.isEmpty {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.6),
                                        radius: s * 0.42, x: 0, y: s * 0.3))
                for brick in vm.state.bricks {
                    let rect = CGRect(x: CGFloat(brick.x) * s, y: CGFloat(brick.y) * s,
                                      width: CGFloat(brick.w) * s, height: CGFloat(brick.h) * s)
                    guard rect.width > 2, rect.height > 2 else { continue }
                    let tone = BrickPalette.band(row: brick.row)
                    let body = Path(roundedRect: rect,
                                    cornerRadius: min(rect.height * 0.3, 12))

                    layer.fill(body, with: .linearGradient(
                        Gradient(colors: [tone.light, tone.mid, tone.dark]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))

                    // A highlight along the top face reads as a bevel.
                    let shine = rect.insetBy(dx: rect.width * 0.07, dy: 0)
                        .divided(atDistance: rect.height * 0.34, from: .minYEdge).slice
                        .offsetBy(dx: 0, dy: rect.height * 0.10)
                    if shine.height > 1 {
                        layer.fill(Path(roundedRect: shine, cornerRadius: shine.height / 2),
                                   with: .linearGradient(
                                    Gradient(colors: [.white.opacity(0.55), .white.opacity(0.04)]),
                                    startPoint: CGPoint(x: shine.midX, y: shine.minY),
                                    endPoint: CGPoint(x: shine.midX, y: shine.maxY)))
                    }

                    layer.stroke(body, with: .color(.black.opacity(0.42)),
                                 lineWidth: max(1, s * 0.06))
                }
            }
        }

        // ---- Ball trail -----------------------------------------------------
        let head = vm.ball(at: now)
        let ballPx = max(CGFloat(vm.state.ballRadius) * s, 4)
        var samples = vm.trail
        samples.append(head)
        if samples.count >= 2 {
            for i in 1..<samples.count {
                let f = Double(i) / Double(samples.count - 1)
                var segment = Path()
                segment.move(to: CGPoint(x: samples[i - 1].x * s, y: samples[i - 1].y * s))
                segment.addLine(to: CGPoint(x: samples[i].x * s, y: samples[i].y * s))
                ctx.stroke(segment,
                           with: .color(Color(hex: "5eead4").opacity(0.04 + 0.38 * f)),
                           style: StrokeStyle(lineWidth: ballPx * CGFloat(0.4 + 1.5 * f),
                                              lineCap: .round))
            }
        }

        // ---- Ball -----------------------------------------------------------
        let centre = CGPoint(x: head.x * s, y: head.y * s)
        let glow = ballPx * 3.4
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - glow, y: centre.y - glow,
                                        width: glow * 2, height: glow * 2)),
                 with: .radialGradient(
                    Gradient(colors: [Color(hex: "67e8f9").opacity(0.50),
                                      Color(hex: "67e8f9").opacity(0)]),
                    center: centre, startRadius: 0, endRadius: glow))
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - ballPx, y: centre.y - ballPx,
                                        width: ballPx * 2, height: ballPx * 2)),
                 with: .radialGradient(
                    Gradient(colors: [.white, Color(hex: "a5f3fc")]),
                    center: CGPoint(x: centre.x - ballPx * 0.32, y: centre.y - ballPx * 0.32),
                    startRadius: 0, endRadius: ballPx * 1.5))

        // A dashed guide while the ball is parked on the paddle, so the
        // pre-launch pause reads as "aim", not "frozen".
        if vm.state.serving && !vm.state.finished {
            var guide = Path()
            guide.move(to: CGPoint(x: centre.x, y: centre.y - ballPx * 1.6))
            guide.addLine(to: CGPoint(x: centre.x, y: centre.y - ballPx * 1.6 - 9 * s))
            ctx.stroke(guide, with: .color(.white.opacity(0.3)),
                       style: StrokeStyle(lineWidth: max(2, s * 0.1), lineCap: .round,
                                          dash: [s * 0.8, s * 0.8]))
        }

        // ---- Paddle ---------------------------------------------------------
        let paddleH = max(CGFloat(vm.state.paddleHeight) * s, 7)
        let paddle = CGRect(x: CGFloat(vm.displayPaddle - vm.state.paddleWidth / 2) * s,
                            y: CGFloat(vm.state.paddleY) * s,
                            width: CGFloat(vm.state.paddleWidth) * s,
                            height: paddleH)
        ctx.fill(Path(roundedRect: paddle.insetBy(dx: -paddleH * 1.5, dy: -paddleH * 1.5),
                      cornerRadius: paddleH * 2),
                 with: .color(Color(hex: "22d3ee").opacity(0.13)))
        ctx.fill(Path(roundedRect: paddle.insetBy(dx: -paddleH * 0.55, dy: -paddleH * 0.55),
                      cornerRadius: paddleH * 1.3),
                 with: .color(Color(hex: "22d3ee").opacity(0.26)))
        ctx.fill(Path(roundedRect: paddle, cornerRadius: paddleH / 2),
                 with: .linearGradient(
                    Gradient(colors: [Color(hex: "f0fdff"), Color(hex: "22d3ee"), Color(hex: "0e7490")]),
                    startPoint: CGPoint(x: paddle.midX, y: paddle.minY),
                    endPoint: CGPoint(x: paddle.midX, y: paddle.maxY)))

        // ---- Shards ---------------------------------------------------------
        for particle in vm.particles {
            let age = now.timeIntervalSince(particle.born)
            guard age >= 0, age < particle.life else { continue }
            let t = CGFloat(age)
            let fade = age / particle.life
            let px = particle.origin.x + particle.velocity.dx * t
            let py = particle.origin.y + particle.velocity.dy * t + 26 * t * t   // gravity
            let radius = CGFloat(particle.size) * s * CGFloat(1 - fade * 0.75)
            guard radius > 0.5 else { continue }
            ctx.fill(Path(ellipseIn: CGRect(x: px * s - radius, y: py * s - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .color(particle.tint.opacity(1 - fade)))
        }
    }

    // MARK: Chrome

    private var hud: some View {
        HStack(alignment: .center, spacing: 28) {
            Text("BRICK BREAKER")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .tracking(6)
                .foregroundStyle(LinearGradient(colors: [.white, Color(hex: "67e8f9")],
                                                startPoint: .top, endPoint: .bottom))
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                ForEach(0..<max(3, vm.state.lives), id: \.self) { index in
                    Image(systemName: index < vm.state.lives ? "heart.fill" : "heart")
                        .font(.system(size: 26))
                        .foregroundColor(index < vm.state.lives
                                         ? Color(hex: "fb7185") : .white.opacity(0.16))
                }
            }
            .animation(.easeOut(duration: 0.2), value: vm.state.lives)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: -2) {
                Text("SCORE")
                    .font(.system(size: 15, weight: .bold)).tracking(5)
                    .foregroundColor(.white.opacity(0.45))
                Text("\(vm.state.score)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(hex: "67e8f9"))
                    .animation(.easeOut(duration: 0.18), value: vm.state.score)
            }
        }
        .padding(.horizontal, 42)
        .padding(.top, 22)
    }

    @ViewBuilder private var readyBadge: some View {
        if vm.state.serving && !vm.state.finished {
            Text("GET READY")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .tracking(8)
                .foregroundColor(.white.opacity(0.82))
                .shadow(color: Color(hex: "22d3ee").opacity(0.6), radius: 18)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var banner: some View {
        if vm.state.finished {
            VStack(spacing: 12) {
                Text(vm.state.won ? "WALL CLEARED" : "GAME OVER")
                    .font(.system(size: 58, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(LinearGradient(
                        colors: vm.state.won
                            ? [Color(hex: "fde68a"), Color(hex: "f59e0b")]
                            : [Color(hex: "fca5a5"), Color(hex: "dc2626")],
                        startPoint: .top, endPoint: .bottom))
                Text("Final score \(vm.state.score)")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 46)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 2))
        }
    }

    @ViewBuilder private var hint: some View {
        if showHint && !vm.state.finished {
            Text(root.isSolo
                 ? "Slide your thumb across the remote's touch surface to move the paddle"
                 : "Slide on your phone to move the paddle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(Capsule().fill(.black.opacity(0.45)))
                .padding(.bottom, 20)
                .transition(.opacity)
        }
    }
}

// MARK: - Simon Says

struct SimonState {
    var phase = "show"
    var round = 0
    var sequence: [String] = []
    var progress = 0
    var currentName = ""
    var finished = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["phase"]?.value as? String { phase = v }
        if let v = data["round"]?.value as? Int    { round = v }
        if let v = data["progress"]?.value as? Int { progress = v }
        if let v = data["currentName"]?.value as? String { currentName = v }
        if let v = data["finished"]?.value as? Bool { finished = v }
        // Empty during the input phase by design — the answer must not be on screen.
        sequence = (data["sequence"]?.value as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

@MainActor final class SimonViewModel: ObservableObject {
    @Published var state = SimonState()
    @Published var litPad: String? = nil
    private let socket = GameSocketManager.shared
    private var playbackTask: Task<Void, Never>?

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard let self, r.roomCode == roomCode else { return }
            let wasShowing = self.state.phase == "show"
            self.state.update(from: r.boardState)
            if self.state.phase == "show", !wasShowing || self.playbackTask == nil {
                self.playSequence()
            }
        }
    }

    /// Flash the sequence once when the show phase begins. The server's own
    /// show-phase timer is sized to match this playback.
    private func playSequence() {
        playbackTask?.cancel()
        let steps = state.sequence
        playbackTask = Task { @MainActor in
            for pad in steps {
                litPad = pad
                try? await Task.sleep(nanoseconds: 420_000_000)
                litPad = nil
                try? await Task.sleep(nanoseconds: 260_000_000)
                if Task.isCancelled { return }
            }
        }
    }

    func flash(_ pad: String) {
        litPad = pad
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            if litPad == pad { litPad = nil }
        }
    }
}

struct TVSimonSaysBoardView: View {
    let room: Room
    @EnvironmentObject private var root: TVRootViewModel
    @StateObject private var vm = SimonViewModel()

    private let pads = ["up", "right", "down", "left"]
    private let colors: [String: Color] = [
        "up": .green, "right": .red, "down": .yellow, "left": .blue,
    ]

    var body: some View {
        VStack(spacing: 0) {
            SoloHUD(title: "Simon Says", score: vm.state.round,
                    subtitle: vm.state.phase == "show" ? "watch…" : "your turn")
            Spacer()
            ZStack {
                VStack(spacing: 18) {
                    pad("up")
                    HStack(spacing: 18) { pad("left"); pad("right") }
                    pad("down")
                }
                if vm.state.finished { GameOverBanner(score: vm.state.round) }
            }
            Spacer()
            RemoteHint(text: vm.state.phase == "show"
                       ? "Watch the sequence"
                       : "Repeat it with the remote's D-pad")
        }
        .remoteDPad { event in
            // See TVNeonSnakeBoardView's identical guard: only in solo mode
            // is the TV's own deviceID a player the server recognizes.
            guard root.isSolo, vm.state.phase == "input", let dir = event.directionName else { return }
            vm.flash(dir)
            root.sendAction("pad", ["pad": dir])
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private func pad(_ name: String) -> some View {
        let lit = vm.litPad == name
        return RoundedRectangle(cornerRadius: 24)
            .fill((colors[name] ?? .gray).opacity(lit ? 1.0 : 0.28))
            .frame(width: 220, height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(lit ? 0.9 : 0.15), lineWidth: lit ? 5 : 2)
            )
            .scaleEffect(lit ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.12), value: lit)
    }
}

// MARK: - Atlas

struct AtlasState {
    var letter = ""
    var chain: [(place: String, name: String)] = []
    var chainLength = 0
    var secondsLeft = 0
    var currentName = ""
    var finished = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["letter"]?.value as? String { letter = v }
        if let v = data["chainLength"]?.value as? Int { chainLength = v }
        if let v = data["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = data["currentName"]?.value as? String { currentName = v }
        if let v = data["finished"]?.value as? Bool { finished = v }
        if let raw = data["chain"]?.value as? [Any] {
            chain = raw.compactMap { item in
                guard let c = item as? [String: Any],
                      let place = c["place"] as? String else { return nil }
                return (place, c["name"] as? String ?? "")
            }
        }
    }
}

@MainActor final class AtlasViewModel: ObservableObject {
    @Published var state = AtlasState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

struct TVAtlasBoardView: View {
    let room: Room
    @StateObject private var vm = AtlasViewModel()

    var body: some View {
        VStack(spacing: 0) {
            SoloHUD(title: "Atlas", score: vm.state.chainLength,
                    subtitle: vm.state.currentName.isEmpty ? nil : "\(vm.state.currentName)'s turn")
            Spacer()
            VStack(spacing: 34) {
                VStack(spacing: 8) {
                    Text("NEXT PLACE STARTS WITH")
                        .font(.caption.bold()).tracking(4)
                        .foregroundColor(.white.opacity(0.4))
                    Text(vm.state.letter)
                        .font(.system(size: 150, weight: .heavy, design: .rounded))
                        .foregroundColor(.cyan)
                }

                TimerRing(secondsLeft: vm.state.secondsLeft, total: 20)
                    .frame(width: 120, height: 120)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(vm.state.chain.enumerated()), id: \.offset) { _, entry in
                            VStack(spacing: 4) {
                                Text(entry.place).font(.title3.bold()).foregroundColor(.white)
                                Text(entry.name).font(.caption)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 22).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(.white.opacity(0.07)))
                        }
                    }
                    .padding(.horizontal, 80)
                }
            }
            Spacer()
            // "...or pass the remote around" used to sit here too, but the
            // remote has no text entry at all -- that half of the hint was
            // never actually possible. A phone is the only way to answer.
            RemoteHint(text: "Type the next place on your phone")
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}
