import SwiftUI
import SceneKit
import UIKit

// ---------------------------------------------------------------------------
// Snake & Ladder's native TV board: a full 3D scene in the style of
// `PokerCinematicBoardSceneView` (same `CinematicCameraRig`/`CinematicLighting`
// primitives, built directly rather than through the generic
// `CinematicBoardSceneView` wrapper, since this needs live per-square
// token/snake/ladder content, not just a `TablePhase` label). No imported 3D
// models anywhere in this project, so everything is primitives plus a few
// procedurally built meshes and textures.
//
// `SnakeLadderEngine.public_state()` exposes its `snakes`/`ladders` maps
// directly (see `games/native_hub/engines/legacy_boards.py`), so this file
// treats them as the single authoritative board layout instead of hardcoding
// its own copy that could silently drift from the engine's.
//
// The engine is back to a classic-style board (10 snakes, 9 ladders) after a
// 3-snake version was reported as "same and easy". To keep that many set
// pieces cheap:
//   * each snake body is ONE continuous, tapering, slightly flattened tube
//     mesh swept along an S-curve (one draw call) instead of a chain of
//     capsule "balloons", wearing a runtime-drawn scale skin (dorsal
//     pattern, pale belly) plus a shared scale normal map; materials and
//     head geometry are shared per style, and nothing is rebuilt per frame;
//   * each ladder is built from shared wood material/rung geometry and then
//     flattened into a single node;
//   * every idle animation is an `SCNAction` loop on a small head/tongue
//     node -- no per-frame work, no particle systems;
//   * the numbered grid is one texture drawn once, not 100 text nodes.
// The board is printed card with a little thickness, lying on a wooden
// table in a warm, lamp-lit room (fogged into a dim background, with a
// SwiftUI vignette on top) rather than floating in a black void.
// Tokens walk square by square along the boustrophedon path; moves queue per
// token, so a quick roll-again on a 6 waits for the previous walk/slide to
// finish instead of fighting it.
// ---------------------------------------------------------------------------

// MARK: - Board state (mirrors SnakeLadderEngine.public_state())

private struct SnakeLadderPlayerPosition: Identifiable {
    var id: String { playerID }
    let playerID: String
    let name: String
    let position: Int   // 0 = not yet on the board, 1...100 = a real square
}

/// One snake bite or ladder climb, straight from
/// `SnakeLadderEngine.handle_action`'s `lastSlide` event. The TV drives its
/// bite/climb cinematics off this instead of re-inferring the slide from
/// positions + the last roll, which breaks when state updates coalesce.
private struct SnakeLadderSlide {
    let playerID: String
    let kind: String      // "snake" | "ladder"
    let from: Int         // head square (snake) or bottom square (ladder)
    let to: Int           // tail square (snake) or top square (ladder)
    let seq: Int          // monotonic per game; dedupes re-broadcasts
}

private struct SnakeLadderBoardState {
    var currentPlayerID: String?
    var secondsLeft = 0
    var winner: String?
    var players: [BoardPlayer] = []
    var positions: [SnakeLadderPlayerPosition] = []
    var lastRoll: [String: Int] = [:]
    /// head square -> tail square, straight from `SNAKES` in
    /// `legacy_boards.py` -- this Swift file never hardcodes its own copy.
    var snakes: [Int: Int] = [:]
    /// bottom square -> top square, straight from `LADDERS`.
    var ladders: [Int: Int] = [:]
    /// playerID -> the latest slide event for that player, straight from
    /// the engine's `lastSlide`. Empty for a player whose last move was a
    /// plain hop (or who hasn't moved yet).
    var lastSlide: [String: SnakeLadderSlide] = [:]
    /// Whoever rolled most recently (`lastRollerID`).
    var lastRollerID: String?
    /// True while the current player is owed another roll for a 6.
    var lastRollBonus = false
    /// Monotonic count of accepted rolls; a change means a fresh roll.
    var rollSeq = 0

    mutating func update(from data: [String: AnyCodable]) {
        currentPlayerID = data["currentPlayerID"]?.value as? String
        if let v = data["secondsLeft"]?.value as? Int { secondsLeft = v }
        winner = data["winner"]?.value as? String
        players = BoardPlayer.list(from: data["players"]?.value)

        if let raw = data["positions"]?.value as? [Any] {
            positions = raw.compactMap { item in
                guard let d = item as? [String: Any], let pid = d["playerID"] as? String else { return nil }
                return SnakeLadderPlayerPosition(playerID: pid,
                                                  name: d["name"] as? String ?? "Player",
                                                  position: d["position"] as? Int ?? 0)
            }
        }
        if let raw = data["lastRoll"]?.value as? [String: Any] {
            lastRoll = raw.compactMapValues { $0 as? Int }
        }
        if let raw = data["snakes"]?.value as? [String: Any] {
            snakes = Dictionary(raw.compactMap { entry -> (Int, Int)? in
                guard let head = Int(entry.key), let tail = entry.value as? Int else { return nil }
                return (head, tail)
            }, uniquingKeysWith: { first, _ in first })
        }
        if let raw = data["ladders"]?.value as? [String: Any] {
            ladders = Dictionary(raw.compactMap { entry -> (Int, Int)? in
                guard let bottom = Int(entry.key), let top = entry.value as? Int else { return nil }
                return (bottom, top)
            }, uniquingKeysWith: { first, _ in first })
        }
        if let raw = data["lastSlide"]?.value as? [String: Any] {
            lastSlide = Dictionary(raw.compactMap { entry -> (String, SnakeLadderSlide)? in
                guard let d = entry.value as? [String: Any],
                      let kind = d["kind"] as? String,
                      let from = d["from"] as? Int,
                      let to = d["to"] as? Int,
                      let seq = d["seq"] as? Int else { return nil }
                return (entry.key, SnakeLadderSlide(playerID: entry.key, kind: kind, from: from, to: to, seq: seq))
            }, uniquingKeysWith: { first, _ in first })
        }
        lastRollerID = data["lastRollerID"]?.value as? String
        lastRollBonus = (data["lastRollBonus"]?.value as? Bool) ?? false
        if let v = data["rollSeq"]?.value as? Int { rollSeq = v }
    }

    /// Stable per-player color slot: the player's index in the engine's
    /// `positions` list (the turn order), shared by the 3D tokens and the
    /// SwiftUI HUD so a player's color matches everywhere.
    func colorIndex(of playerID: String?) -> Int? {
        guard let playerID else { return nil }
        return positions.firstIndex { $0.playerID == playerID }
    }

    func name(of playerID: String?) -> String? {
        guard let playerID else { return nil }
        return players.first { $0.id == playerID }?.name
            ?? positions.first { $0.playerID == playerID }?.name
    }
}

@MainActor
private final class SnakeLadderBoardViewModel: ObservableObject {
    @Published var state = SnakeLadderBoardState()
    private let socket = GameSocketManager.shared

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

/// Token colors, shared by the 3D pawns and the SwiftUI HUD.
private enum SnakeLadderPalette {
    static let tokenColors: [UIColor] = [
        UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1),
        UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1),
        UIColor(red: 0.30, green: 0.85, blue: 0.40, alpha: 1),
        UIColor(red: 0.95, green: 0.80, blue: 0.20, alpha: 1),
        UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1),
        UIColor(red: 0.20, green: 0.85, blue: 0.85, alpha: 1),
    ]

    static func tokenColor(_ index: Int?) -> UIColor {
        guard let index, index >= 0 else { return UIColor(white: 0.8, alpha: 1) }
        return tokenColors[index % tokenColors.count]
    }
}

/// Standard die pip layout, as fractions of the face on each axis. Shared by
/// the HUD die and the 3D dice texture.
private enum SnakeLadderDice {
    static func pips(for value: Int) -> [CGPoint] {
        let raw: [(CGFloat, CGFloat)]
        switch value {
        case 1: raw = [(0.5, 0.5)]
        case 2: raw = [(0.28, 0.28), (0.72, 0.72)]
        case 3: raw = [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)]
        case 4: raw = [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)]
        case 5: raw = [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)]
        case 6: raw = [(0.28, 0.22), (0.72, 0.22), (0.28, 0.5), (0.72, 0.5), (0.28, 0.78), (0.72, 0.78)]
        default: raw = []
        }
        return raw.map { CGPoint(x: $0.0, y: $0.1) }
    }
}

// MARK: - TV board

struct TVSnakeLadderBoardView: View {
    let room: Room
    @StateObject private var vm = SnakeLadderBoardViewModel()

    private var currentName: String {
        vm.state.name(of: vm.state.currentPlayerID) ?? "\u{2014}"
    }
    private var winnerName: String? {
        vm.state.name(of: vm.state.winner)
    }
    /// The player whose roll the HUD shows: the engine's `lastRollerID`
    /// (the current player's own last roll would show the wrong number
    /// right after the turn passes).
    private var rollerID: String? {
        vm.state.lastRollerID ?? vm.state.currentPlayerID
    }

    var body: some View {
        ZStack {
            // The real 3D board: 100 numbered squares, the classic set of
            // snakes and ladders, and a pawn per player, shot with the
            // cinematic camera rig. Every fact below is rendered again as
            // legible SwiftUI text over the top -- the 3D scene is
            // atmosphere, never the only place a state fact lives.
            SnakeLadderCinematicBoardSceneView(state: vm.state)
                .ignoresSafeArea()

            // A soft vignette, like a lamp-lit table in a dim room: the
            // board stays bright, the corners of the room fall off.
            RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center,
                           startRadius: 420, endRadius: 1200)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if winnerName != nil {
                // The win banner (trophy + name) had no celebration
                // motion of its own -- confetti falls over it once per win.
                WinConfettiOverlay()
            }

            VStack(spacing: 0) {
                TVRoundHeader(symbol: "arrow.up.right", title: "Snake & Ladder", round: 0, totalRounds: 0,
                              secondsLeft: vm.state.secondsLeft,
                              phaseLabel: vm.state.winner != nil ? "game over" : "\(currentName)'s turn")

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.state.positions.sorted { $0.position > $1.position }) { p in
                            SnakeLadderPositionRow(
                                entry: p,
                                isCurrent: p.playerID == vm.state.currentPlayerID,
                                color: Color(uiColor: SnakeLadderPalette.tokenColor(vm.state.colorIndex(of: p.playerID)))
                            )
                        }
                    }
                    .padding(.leading, 48).padding(.top, 24)

                    Spacer()

                    if let id = rollerID, let roll = vm.state.lastRoll[id] {
                        SnakeLadderLastRollCard(
                            rollerName: vm.state.name(of: id) ?? "",
                            value: roll,
                            color: Color(uiColor: SnakeLadderPalette.tokenColor(vm.state.colorIndex(of: id)))
                        )
                        .padding(.trailing, 60).padding(.top, 24)
                    }
                }

                Spacer()

                if let winnerName {
                    // SF symbol, never an emoji (no-emoji gate). The name
                    // truncates with an ellipsis rather than wrapping
                    // mid-word on a long name.
                    Label {
                        Text("\(winnerName) wins!")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "trophy.fill")
                    }
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(TVTheme.yellow)
                    .padding(.bottom, 24)
                } else if vm.state.currentPlayerID != nil {
                    SnakeLadderTurnBanner(
                        name: currentName,
                        color: Color(uiColor: SnakeLadderPalette.tokenColor(vm.state.colorIndex(of: vm.state.currentPlayerID))),
                        rollAgain: vm.state.lastRollBonus
                    )
                    .padding(.bottom, 36)
                }
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

/// The big "whose turn" pill along the bottom, in the current player's
/// token color, plus the "Rolled a 6, roll again!" call-out while the
/// engine says the current player is owed a bonus roll.
private struct SnakeLadderTurnBanner: View {
    let name: String
    let color: Color
    let rollAgain: Bool

    var body: some View {
        VStack(spacing: 12) {
            if rollAgain {
                Label {
                    Text("Rolled a 6, roll again!")
                } icon: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                }
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 28).padding(.vertical, 10)
                .background(Capsule().fill(TVTheme.yellow))
                .transition(.scale.combined(with: .opacity))
            }
            HStack(spacing: 16) {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 3))
                Text("\(name)'s turn")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 36).padding(.vertical, 14)
            .frame(maxWidth: 760)
            .background(Capsule().fill(Color.black.opacity(0.62)))
            .overlay(Capsule().stroke(color, lineWidth: 4))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: rollAgain)
    }
}

/// Top-right card: who rolled last and a real pip die face of the value.
private struct SnakeLadderLastRollCard: View {
    let rollerName: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text("LAST ROLL").font(.system(.caption, design: .rounded, weight: .bold)).tracking(2)
                .foregroundColor(.white.opacity(0.6))
            SnakeLadderDieFace(value: value, size: 84)
            Text(rollerName)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius).fill(Color.black.opacity(0.45)))
    }
}

private struct SnakeLadderDieFace: View {
    let value: Int
    var size: CGFloat = 84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color.white)
            ForEach(Array(SnakeLadderDice.pips(for: value).enumerated()), id: \.offset) { entry in
                Circle()
                    .fill(Color.black)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .position(x: entry.element.x * size, y: entry.element.y * size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Rolled \(value)")
    }
}

/// Falling confetti shown over the win banner. Pure SwiftUI, no textures:
/// a fixed set of colored shapes that drift down once when the win state
/// appears and settle below the fold. The no-emoji gate means celebration
/// is drawn shapes, never emoji glyphs.
private struct WinConfettiOverlay: View {
    struct Piece: Identifiable {
        let id = UUID()
        let x: CGFloat        // fraction of the screen width
        let delay: Double     // seconds before this piece starts falling
        let duration: Double  // fall time in seconds
        let color: Color
        let size: CGFloat
        let spin: Double      // total rotation in degrees
    }

    private let pieces: [Piece]
    @State private var falling = false

    init(count: Int = 44) {
        let colors: [Color] = [TVTheme.red, TVTheme.yellow, TVTheme.green, TVTheme.cyan, TVTheme.pink, TVTheme.orange, .white]
        pieces = (0..<count).map { _ in
            Piece(x: CGFloat.random(in: 0...1),
                  delay: Double.random(in: 0...0.9),
                  duration: Double.random(in: 1.6...2.6),
                  color: colors.randomElement() ?? TVTheme.yellow,
                  size: CGFloat.random(in: 8...16),
                  spin: Double.random(in: -540...540))
        }
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 3)
                    .fill(piece.color)
                    .frame(width: piece.size, height: piece.size * 0.6)
                    .rotationEffect(.degrees(falling ? piece.spin : 0))
                    .position(x: piece.x * geo.size.width,
                              y: falling ? geo.size.height + 40 : -40)
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay),
                               value: falling)
            }
        }
        .allowsHitTesting(false)
        .onAppear { falling = true }
    }
}

private struct SnakeLadderPositionRow: View {
    let entry: SnakeLadderPlayerPosition
    let isCurrent: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white.opacity(isCurrent ? 0.9 : 0), lineWidth: 2))
            // A long name must truncate with an ellipsis, never wrap
            // mid-word ("Gand"/"hi" on two lines). The fixed-width parent
            // below gives the truncation a bound to work against.
            Text(entry.name).font(.system(.headline, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isCurrent ? .white : .white.opacity(0.6))
            Spacer()
            Text(entry.position == 0 ? "start" : "\(entry.position)")
                .font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundColor(TVTheme.cyan)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(isCurrent ? Color.white.opacity(0.14) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isCurrent ? color : Color.clear, lineWidth: 2))
    }
}

// MARK: - The 3D scene

/// Built directly on `CinematicCameraRig`/`CinematicLighting` rather than
/// through the generic `CinematicBoardSceneView` wrapper -- same reasoning
/// `PokerCinematicBoardSceneView`'s header comment gives: this needs real
/// per-square board content driven by `SnakeLadderBoardState`, not just a
/// named phase.
private struct SnakeLadderCinematicBoardSceneView: UIViewRepresentable {
    var state: SnakeLadderBoardState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraRig.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = Coordinator.roomColor
        view.isPlaying = true
        view.rendersContinuously = true
        context.coordinator.apply(state, animated: false)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.apply(state, animated: true)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let cameraRig: CinematicCameraRig
        let lighting: CinematicLighting
        private let dice = DiceNode()

        // Board geometry constants. 10x10 grid, centred on the origin.
        private let cellSize: Float = 0.9
        private let boardExtent: Float = 9.0      // 10 * cellSize
        private let boardTopY: Float = 0.06       // top surface of the board slab
        private let tableTopY: Float = -0.02      // the tabletop the board lies on
        private let tokenHoverHeight: Float = 0.22
        /// One square-to-square hop while a token walks its roll.
        private let hopSeconds: TimeInterval = 0.2

        private var tokenNodes: [String: SCNNode] = [:]
        /// One glowing ring per player, marking the tile their token
        /// stands on in that player's color.
        private var playerRings: [String: SCNNode] = [:]
        /// The square each token was last told to go to.
        private var lastPositions: [String: Int] = [:]
        /// Where each token will rest once its queued movement finishes --
        /// the starting point for the next queued move.
        private var lastAnchors: [String: SCNVector3] = [:]
        /// `CACurrentMediaTime()` at which each token's queued movement
        /// ends. A new move (e.g. the bonus roll after a 6) waits for it.
        private var busyUntil: [String: CFTimeInterval] = [:]
        private var boardBuilt = false
        /// Becomes true once a real state (with positions) has been adopted
        /// as-is; until then every update is treated as a first paint, so
        /// a TV that joins mid-game never replays old moves.
        private var adoptedState = false
        private var snakeNodes: [Int: RealisticSnakeNode] = [:]
        private var ladderNodes: [Int: LadderNode] = [:]
        private var lastAnnouncedWinner: String?
        /// Slide-event seqs already played, per player -- `lastSlide`
        /// survives in the engine state until that player's next move, so
        /// without this every re-broadcast would replay the cinematic.
        private var seenSlideSeq: [String: Int] = [:]
        /// The engine's `rollSeq` last acted on (die tumble, bump).
        private var seenRollSeq = 0

        init() {
            // A wide, angled 3/4 overhead shot -- the whole board, the dice
            // podium, and the staging area all read at once, the way a
            // board game is normally seen. `boardRadius` here is purely a
            // framing distance for the camera math below, not a stored
            // property, so referencing it doesn't touch `self` before
            // `cameraRig`/`lighting` (the two properties with no default
            // value) are actually assigned.
            let boardRadius: Float = 5.6
            let initialShot = CameraShot(
                position: SCNVector3(1.4, boardRadius * 1.6, boardRadius * 1.55),
                lookAt: SCNVector3(0, 0.1, -0.3),
                fieldOfView: 48,
                focusDistance: CGFloat(boardRadius * 1.8)
            )
            cameraRig = CinematicCameraRig(initialShot: initialShot)
            lighting = CinematicLighting(tableRadius: boardRadius)

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)

            // A real room, not a void: the board lies on a big wooden
            // table, the far edges of which fade into a warm, dim room
            // through fog the color of the background.
            let room = Coordinator.roomColor
            scene.background.contents = room
            scene.fogColor = room
            scene.fogStartDistance = 15
            scene.fogEndDistance = 32
            scene.fogDensityExponent = 1.4

            let table = SCNBox(width: 24, height: 0.4, length: 18, chamferRadius: 0.06)
            table.materials = [SnakeLadderSharedParts.tableMaterial()]
            let tableNode = SCNNode(geometry: table)
            tableNode.position = SCNVector3(0, tableTopY - 0.2, -1.0)
            scene.rootNode.addChildNode(tableNode)

            // Warm, lamp-lit key: the shared rig's spotlight shifted toward
            // tungsten, plus a soft warm side lamp (no shadows, so it costs
            // no extra shadow pass) that lifts the board's near edge.
            lighting.apply(PhaseLightingMood(keyTemperature: 3500, fillTemperature: 4300,
                                             keyIntensity: 1350, fillIntensity: 300),
                           duration: 0)
            let lamp = SCNLight()
            lamp.type = .omni
            lamp.color = UIColor(red: 1.0, green: 0.80, blue: 0.58, alpha: 1)
            lamp.intensity = 380
            lamp.castsShadow = false
            let lampNode = SCNNode()
            lampNode.light = lamp
            lampNode.position = SCNVector3(-7, 6, 6)
            scene.rootNode.addChildNode(lampNode)

            // The die rests on the table beside the board.
            let dicePosition = SCNVector3(-(boardExtent / 2 + 1.4), tableTopY + 0.25, -(boardExtent / 2 + 0.5))
            dice.rootNode.position = dicePosition
            scene.rootNode.addChildNode(dice.rootNode)
        }

        /// The dim, warm room around the table (background and fog).
        static let roomColor = UIColor(red: 0.10, green: 0.06, blue: 0.035, alpha: 1)

        // MARK: - Board dressing (built once, the first time snakes/ladders arrive)

        private func ensureBoardDressing(state: SnakeLadderBoardState) {
            guard !boardBuilt, !state.snakes.isEmpty || !state.ladders.isEmpty else { return }
            boardBuilt = true

            let parts = SnakeLadderSharedParts.shared

            let topMaterial = SCNMaterial()
            topMaterial.lightingModel = .physicallyBased
            topMaterial.diffuse.contents = Coordinator.boardTexture()
            topMaterial.diffuse.mipFilter = .linear
            topMaterial.roughness.contents = 0.55

            // The board itself: printed cardboard with a little thickness,
            // lying flat on the table. SCNBox material order is documented
            // as front/right/back/left/top/bottom -- index 4 is the +y face,
            // the only one that needs the numbered grid texture; the edges
            // show the layered board stock.
            let thickness = boardTopY - tableTopY
            let slab = SCNBox(width: CGFloat(boardExtent), height: CGFloat(thickness),
                              length: CGFloat(boardExtent), chamferRadius: 0.012)
            let edge = Coordinator.boardEdgeMaterial()
            slab.materials = [edge, edge, edge, edge, topMaterial, edge]
            let slabNode = SCNNode(geometry: slab)
            slabNode.position = SCNVector3(0, tableTopY + thickness / 2, 0)
            scene.rootNode.addChildNode(slabNode)

            // Sorted so each snake keeps the same style on every launch.
            for (index, head) in state.snakes.keys.sorted().enumerated() {
                guard let tail = state.snakes[head] else { continue }
                // Keep this call to the original snake initializer shape:
                // a drop-in snake class with the same API can replace
                // `SnakeNode` here by name alone.
                let style = SnakeStyle.style(index)
                let snake = RealisticSnakeNode(headSquare: head, tailSquare: tail, squareToPoint: squareToPoint,
                                      color: style.base, bandColor: style.accent)
                scene.rootNode.addChildNode(snake.rootNode)
                snakeNodes[head] = snake
            }
            for bottom in state.ladders.keys.sorted() {
                guard let top = state.ladders[bottom] else { continue }
                let ladder = LadderNode(bottomSquare: bottom, topSquare: top, squareToPoint: squareToPoint, parts: parts)
                scene.rootNode.addChildNode(ladder.rootNode)
                ladderNodes[bottom] = ladder
            }
        }

        private func rebuildTokensIfNeeded(players: [SnakeLadderPlayerPosition]) {
            for (index, entry) in players.enumerated() where tokenNodes[entry.playerID] == nil {
                let color = SnakeLadderPalette.tokenColor(index)
                let token = Coordinator.makeTokenNode(color: color)
                // Floating name plate, billboarded so it always faces the
                // camera; it rides the token, so it follows automatically.
                let plate = Coordinator.makeNamePlate(name: entry.name, color: color)
                plate.position = SCNVector3(0, 0.66, 0)
                token.addChildNode(plate)
                token.position = tokenAnchor(square: 0, offsetIndex: index, offsetCount: players.count)
                scene.rootNode.addChildNode(token)
                tokenNodes[entry.playerID] = token

                let ring = Coordinator.makePlayerRing(color: color)
                scene.rootNode.addChildNode(ring)
                playerRings[entry.playerID] = ring
            }
        }

        /// A classic pawn: base disc, conical body and a round head. The
        /// idle bob runs on an inner node, so the outer node's position is
        /// owned entirely by the walk/slide actions and never drifts.
        private static func makeTokenNode(color: UIColor) -> SCNNode {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.metalness.contents = 0.15
            material.roughness.contents = 0.35

            let base = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 0.05))
            base.geometry?.materials = [material]
            base.position = SCNVector3(0, -0.12, 0)
            let body = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.12, height: 0.26))
            body.geometry?.materials = [material]
            let head = SCNNode(geometry: SCNSphere(radius: 0.09))
            head.geometry?.materials = [material]
            head.position = SCNVector3(0, 0.18, 0)

            let bob = SCNNode()
            bob.addChildNode(base)
            bob.addChildNode(body)
            bob.addChildNode(head)

            let root = SCNNode()
            root.addChildNode(bob)

            let bobUp = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 0.9)
            bobUp.timingMode = .easeInEaseOut
            bob.runAction(.repeatForever(.sequence([bobUp, bobUp.reversed()])), forKey: "idleBob")
            return root
        }

        /// A flat glowing ring marking the tile the token stands on, in
        /// the player's color, with a gentle pulse.
        private static func makePlayerRing(color: UIColor) -> SCNNode {
            let ring = SCNTorus(ringRadius: 0.34, pipeRadius: 0.035)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.emission.contents = color
            ring.materials = [material]
            let node = SCNNode(geometry: ring)
            node.castsShadow = false
            let pulse = SCNAction.scale(by: 1.08, duration: 0.8)
            pulse.timingMode = .easeInEaseOut
            node.runAction(.repeatForever(.sequence([pulse, pulse.reversed()])), forKey: "ringPulse")
            return node
        }

        /// A billboarded name plate floating above the token: a dark pill
        /// with the player's name, edged in the player's color. `.constant`
        /// lighting keeps it legible instead of shaded by the scene lights.
        private static func makeNamePlate(name: String, color: UIColor) -> SCNNode {
            let label = name.count > 12 ? String(name.prefix(11)) + "\u{2026}" : name
            let size = CGSize(width: 256, height: 64)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                let pill = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 32)
                UIColor(white: 0.05, alpha: 0.78).setFill()
                pill.fill()
                color.withAlphaComponent(0.9).setStroke()
                pill.lineWidth = 4
                pill.stroke()
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 30),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph,
                ]
                (label as NSString).draw(in: CGRect(x: 8, y: 12, width: size.width - 16, height: 44),
                                        withAttributes: attrs)
            }
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.isDoubleSided = true
            let plane = SCNPlane(width: 1.1, height: 0.28)
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.castsShadow = false
            node.constraints = [SCNBillboardConstraint()]
            return node
        }

        // MARK: - Live state -> scene

        func apply(_ state: SnakeLadderBoardState, animated requestedAnimation: Bool) {
            ensureBoardDressing(state: state)
            rebuildTokensIfNeeded(players: state.positions)

            let animated = requestedAnimation && adoptedState
            if !state.positions.isEmpty { adoptedState = true }

            // The roller whose roll left them where they were (an overshoot
            // near 100 needs the exact number): they get a little bump.
            var bumpPlayer: String?
            if !animated {
                // First paint (or a mid-game join): adopt the board as-is.
                // Any slide event the engine is still holding is history,
                // not a cue: record its seq so it is never replayed.
                for (pid, slide) in state.lastSlide { seenSlideSeq[pid] = slide.seq }
                seenRollSeq = state.rollSeq
            } else if state.rollSeq != seenRollSeq {
                seenRollSeq = state.rollSeq
                if let roller = state.lastRollerID, let value = state.lastRoll[roller] {
                    dice.roll(to: max(1, min(6, value)))
                    bumpPlayer = roller
                }
            }

            var bySquare: [Int: [String]] = [:]
            for entry in state.positions { bySquare[entry.position, default: []].append(entry.playerID) }

            for (index, entry) in state.positions.enumerated() {
                let pid = entry.playerID
                guard let token = tokenNodes[pid] else { continue }
                let group = bySquare[entry.position] ?? [pid]
                let anchor: SCNVector3
                if entry.position > 0 {
                    anchor = tokenAnchor(square: entry.position,
                                         offsetIndex: group.firstIndex(of: pid) ?? 0,
                                         offsetCount: group.count)
                } else {
                    // Off-board tokens keep a fixed staging slot each.
                    anchor = tokenAnchor(square: 0, offsetIndex: index, offsetCount: state.positions.count)
                }
                let previous = lastPositions[pid] ?? 0

                if !animated {
                    token.removeAllActions()
                    token.position = anchor
                    token.scale = SCNVector3(1, 1, 1)
                    busyUntil[pid] = 0
                    placeRing(for: pid, at: anchor, after: 0)
                } else if previous != entry.position {
                    var slide: SnakeLadderSlide?
                    if let event = state.lastSlide[pid], event.seq != seenSlideSeq[pid], event.to == entry.position {
                        slide = event
                        seenSlideSeq[pid] = event.seq
                    }
                    if state.rollSeq == 0, let value = state.lastRoll[pid] {
                        // An engine without `rollSeq`: tumble on the move.
                        dice.roll(to: max(1, min(6, value)))
                    }
                    let done = queueMove(pid: pid, token: token, from: previous, to: entry.position,
                                         slide: slide, finalAnchor: anchor)
                    placeRing(for: pid, at: anchor, after: done)
                } else if pid == bumpPlayer, entry.position > 0 {
                    // Rolled, but the exact-roll rule kept them in place.
                    let start = lastAnchors[pid] ?? anchor
                    let done = queue(pid: pid, token: token, actions: [
                        Coordinator.hopAction(from: start, to: anchor, duration: 0.22, arcHeight: 0.22),
                        Coordinator.hopAction(from: anchor, to: anchor, duration: 0.18, arcHeight: 0.12),
                    ], duration: 0.4)
                    placeRing(for: pid, at: anchor, after: done)
                } else if let last = lastAnchors[pid], !SnakeLadderGeometry.nearlyEqual(last, anchor) {
                    // Same square, but another token arrived or left, so the
                    // tokens sharing it re-spread around the tile.
                    let done = queue(pid: pid, token: token,
                                     actions: [Coordinator.slideAction(from: last, to: anchor, duration: 0.25)],
                                     duration: 0.25)
                    placeRing(for: pid, at: anchor, after: done)
                }
                lastPositions[pid] = entry.position
                lastAnchors[pid] = anchor
            }

            if let winnerID = state.winner, winnerID != lastAnnouncedWinner {
                lastAnnouncedWinner = winnerID
                cameraRig.transition(to: Coordinator.winnerShot(), duration: 1.6)
                // Game over: the big fanfare. The ladder climb deliberately
                // uses its own lighter chime so only this reads as a win.
                SoundPlayer.shared.play(.winFanfare)
            } else if state.winner == nil {
                lastAnnouncedWinner = nil
            }
        }

        /// Runs `actions` on the token once its current queued movement is
        /// done. Returns the seconds from now until this one finishes.
        @discardableResult
        private func queue(pid: String, token: SCNNode, actions: [SCNAction], duration: TimeInterval) -> TimeInterval {
            let now = CACurrentMediaTime()
            let startDelay = max(0, (busyUntil[pid] ?? 0) - now)
            var sequence: [SCNAction] = []
            if startDelay > 0 { sequence.append(.wait(duration: startDelay)) }
            sequence.append(contentsOf: actions)
            if !sequence.isEmpty { token.runAction(.sequence(sequence)) }
            let total = startDelay + duration
            busyUntil[pid] = now + total
            return total
        }

        /// The whole move for one roll as a single queued action sequence:
        /// walk square by square along the boustrophedon path (to the
        /// snake head / ladder bottom when the engine says this roll hit
        /// one), then the bite-and-slide or the climb. Sounds and the
        /// snake's strike are scheduled to line up with the queued motion.
        /// Returns the seconds from now until the token comes to rest.
        private func queueMove(pid: String, token: SCNNode, from previous: Int, to target: Int,
                               slide: SnakeLadderSlide?, finalAnchor: SCNVector3) -> TimeInterval {
            let now = CACurrentMediaTime()
            let startDelay = max(0, (busyUntil[pid] ?? 0) - now)
            var actions: [SCNAction] = []
            var elapsed: TimeInterval = 0
            var cursor = lastAnchors[pid] ?? token.position
            var hopTimes: [TimeInterval] = []

            let walkEnd = slide?.from ?? target
            let walkStart = max(previous, 0)
            if walkEnd > walkStart, walkEnd - walkStart <= 12 {
                for square in (walkStart + 1)...walkEnd {
                    let point = (square == walkEnd && slide == nil) ? finalAnchor : tokenAnchor(square: square)
                    let entering = walkStart == 0 && square == 1
                    let duration = entering ? 0.35 : hopSeconds
                    actions.append(Coordinator.hopAction(from: cursor, to: point, duration: duration,
                                                         arcHeight: entering ? 0.5 : 0.3))
                    cursor = point
                    elapsed += duration
                    hopTimes.append(startDelay + elapsed)
                }
            } else if walkEnd != walkStart {
                // The TV missed updates (backgrounded, or a reconnect): one
                // long arc beats a 40-square march.
                let point = slide == nil ? finalAnchor : tokenAnchor(square: walkEnd)
                actions.append(Coordinator.hopAction(from: cursor, to: point, duration: 0.6, arcHeight: 0.9))
                cursor = point
                elapsed += 0.6
                hopTimes.append(startDelay + elapsed)
            }

            // A soft tick as the pawn lands on each square, like a pawn
            // being tapped along a real board.
            for time in hopTimes {
                DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                    SoundPlayer.shared.playClick(volume: 0.25)
                }
            }

            if let slide {
                let strikeAt = startDelay + elapsed
                if slide.kind == "snake", let snake = snakeNodes[slide.from] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + strikeAt) { [weak self] in
                        snake.playEat()
                        SoundPlayer.shared.play(.snakeBite)
                        // A short, subtle camera rumble sells the strike.
                        self?.cameraRig.shake(intensity: 0.12, duration: 0.4)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + strikeAt + 0.3) {
                        SoundPlayer.shared.play(.snakeDoomSting, volume: 0.9)
                    }
                    actions.append(.wait(duration: 0.4))
                    elapsed += 0.4
                    // Swallowed: shrink, ride the snake's own body down to
                    // the tail, then pop back out at full size.
                    actions.append(.scale(to: 0.45, duration: 0.18))
                    elapsed += 0.18
                    let body = snake.pathPoints
                    if body.count > 1 {
                        let rideSeconds = min(2.2, max(1.0, Double(body.count) * 0.05))
                        let perPoint = rideSeconds / Double(body.count - 1)
                        for (i, p) in body.enumerated().dropFirst() {
                            let point = i == body.count - 1 ? finalAnchor : SCNVector3(p.x, p.y + 0.16, p.z)
                            actions.append(Coordinator.slideAction(from: cursor, to: point, duration: perPoint))
                            cursor = point
                            elapsed += perPoint
                        }
                    } else {
                        actions.append(Coordinator.slideAction(from: cursor, to: finalAnchor, duration: 0.6))
                        elapsed += 0.6
                    }
                    actions.append(.scale(to: 1.0, duration: 0.25))
                    elapsed += 0.25
                } else if slide.kind == "ladder", let ladder = ladderNodes[slide.from] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + strikeAt) {
                        SoundPlayer.shared.play(.ladderClimb)
                    }
                    // Taller, slower hops rung by rung up the ladder's own
                    // line -- distinct from a normal hop's flatter arc.
                    let steps = max(4, min(10, ladder.rungCount / 2))
                    for i in 1...steps {
                        let t = Float(i) / Float(steps)
                        let point: SCNVector3
                        if i == steps {
                            point = finalAnchor
                        } else {
                            point = SCNVector3(
                                ladder.bottomWorldPosition.x + (ladder.topWorldPosition.x - ladder.bottomWorldPosition.x) * t,
                                boardTopY + tokenHoverHeight + 0.08,
                                ladder.bottomWorldPosition.z + (ladder.topWorldPosition.z - ladder.bottomWorldPosition.z) * t
                            )
                        }
                        actions.append(Coordinator.hopAction(from: cursor, to: point, duration: 0.2, arcHeight: 0.2))
                        cursor = point
                        elapsed += 0.2
                    }
                } else {
                    // The event names a square this client has no model for
                    // (both come from the same engine maps, so this
                    // shouldn't happen): fall back to a plain hop.
                    actions.append(Coordinator.hopAction(from: cursor, to: finalAnchor, duration: 0.4, arcHeight: 0.4))
                    elapsed += 0.4
                }
            }

            var sequence: [SCNAction] = []
            if startDelay > 0 { sequence.append(.wait(duration: startDelay)) }
            sequence.append(contentsOf: actions)
            if !sequence.isEmpty { token.runAction(.sequence(sequence)) }
            let total = startDelay + elapsed
            busyUntil[pid] = now + total
            return total
        }

        /// Moves the player's color ring to the token's resting tile once
        /// the token gets there.
        private func placeRing(for pid: String, at anchor: SCNVector3, after delay: TimeInterval) {
            guard let ring = playerRings[pid] else { return }
            // Just above whatever surface the token stands on (the board,
            // or the table for an off-board token).
            let target = SCNVector3(anchor.x, anchor.y - tokenHoverHeight + 0.02, anchor.z)
            ring.removeAction(forKey: "ringMove")
            if delay <= 0 {
                ring.position = target
            } else {
                ring.runAction(.sequence([.wait(duration: delay), .move(to: target, duration: 0.2)]), forKey: "ringMove")
            }
        }

        // MARK: - Geometry helpers

        private func squareToPoint(_ n: Int) -> SCNVector3 {
            let (row, col) = Coordinator.squareRowCol(n)
            let x = (Float(col) - 4.5) * cellSize
            let z = (4.5 - Float(row)) * cellSize
            return SCNVector3(x, boardTopY, z)
        }

        /// Off-board tokens wait on the table beside square 1.
        private func stagingPoint(index: Int) -> SCNVector3 {
            SCNVector3(-(boardExtent / 2 + 1.1), tableTopY, 3.6 - Float(index) * 0.75)
        }

        private func tokenAnchor(square: Int) -> SCNVector3 {
            let p = squareToPoint(square)
            return SCNVector3(p.x, p.y + tokenHoverHeight, p.z)
        }

        private func tokenAnchor(square: Int, offsetIndex: Int, offsetCount: Int) -> SCNVector3 {
            guard square > 0 else {
                let p = stagingPoint(index: offsetIndex)
                return SCNVector3(p.x, p.y + tokenHoverHeight, p.z)
            }
            guard offsetCount > 1 else { return tokenAnchor(square: square) }
            let base = squareToPoint(square)
            let angle = Float(offsetIndex) / Float(offsetCount) * 2 * .pi
            let r: Float = 0.22
            return SCNVector3(base.x + cos(angle) * r, base.y + tokenHoverHeight, base.z + sin(angle) * r)
        }

        /// Standard boustrophedon (zigzag) numbering: square 1 is
        /// bottom-left, row 0 runs left-to-right (1...10), row 1 runs
        /// right-to-left (11...20, so 11 sits directly above 10 and 20
        /// directly above 1), and so on up to row 9 (91...100).
        private static func squareRowCol(_ n: Int) -> (row: Int, col: Int) {
            let clamped = max(1, min(100, n))
            let row = (clamped - 1) / 10
            let posInRow = (clamped - 1) % 10
            let col = row.isMultiple(of: 2) ? posInRow : 9 - posInRow
            return (row, col)
        }

        private static func hopAction(from a: SCNVector3, to b: SCNVector3, duration: TimeInterval, arcHeight: Float) -> SCNAction {
            SCNAction.customAction(duration: duration) { node, elapsed in
                let t: Float = duration > 0 ? Float(elapsed / CGFloat(duration)) : 1
                let ct = min(max(t, 0), 1)
                let x = a.x + (b.x - a.x) * ct
                let z = a.z + (b.z - a.z) * ct
                let y = a.y + (b.y - a.y) * ct + sin(Float.pi * ct) * arcHeight
                node.position = SCNVector3(x, y, z)
            }
        }

        private static func slideAction(from a: SCNVector3, to b: SCNVector3, duration: TimeInterval) -> SCNAction {
            SCNAction.customAction(duration: duration) { node, elapsed in
                let t: Float = duration > 0 ? Float(elapsed / CGFloat(duration)) : 1
                let ct = min(max(t, 0), 1)
                node.position = SCNVector3(a.x + (b.x - a.x) * ct, a.y + (b.y - a.y) * ct, a.z + (b.z - a.z) * ct)
            }
        }

        /// The board's cut edge: layered board stock -- a printed red
        /// border band over pale card with faint ply lines.
        private static func boardEdgeMaterial() -> SCNMaterial {
            let size = CGSize(width: 64, height: 32)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                UIColor(red: 0.88, green: 0.82, blue: 0.70, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
                UIColor(red: 0.62, green: 0.14, blue: 0.10, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: size.width, height: 9)).fill()
                UIColor(white: 0, alpha: 0.12).setFill()
                for y: CGFloat in [15, 21, 27] {
                    UIBezierPath(rect: CGRect(x: 0, y: y, width: size.width, height: 1)).fill()
                }
            }
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = image
            material.roughness.contents = 0.8
            return material
        }

        private static func winnerShot() -> CameraShot {
            CameraShot(position: SCNVector3(0, 10.5, 11.0), lookAt: SCNVector3(0, 0.2, 0),
                       fieldOfView: 55, focusDistance: 12)
        }

        /// The numbered 10x10 grid, drawn once into a texture (rather than
        /// as 100 individual `SCNText` nodes) and applied to the board
        /// slab's top face -- cheap, and every number stays legible at TV
        /// distance regardless of camera angle.
        ///
        /// The classic printed-board look: a checkerboard of alternating
        /// warm tones (cream / orange on one row, butter / brick red on the
        /// next), big outlined numbers in each square's top-left corner so
        /// a snake or ladder lying across the middle never hides them, and
        /// START / HOME on 1 and 100.
        private static func boardTexture() -> UIImage {
            let cells = 10
            let cellPx: CGFloat = 128
            let size = CGSize(width: cellPx * CGFloat(cells), height: cellPx * CGFloat(cells))
            let cream = UIColor(red: 0.99, green: 0.94, blue: 0.80, alpha: 1)
            let butter = UIColor(red: 0.99, green: 0.86, blue: 0.52, alpha: 1)
            let orange = UIColor(red: 0.95, green: 0.55, blue: 0.22, alpha: 1)
            let brick = UIColor(red: 0.80, green: 0.26, blue: 0.19, alpha: 1)
            let darkText = UIColor(red: 0.30, green: 0.15, blue: 0.07, alpha: 1)

            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                for n in 1...100 {
                    let (row, col) = Coordinator.squareRowCol(n)
                    let rect = CGRect(x: CGFloat(col) * cellPx, y: CGFloat(cells - 1 - row) * cellPx,
                                      width: cellPx, height: cellPx)
                    let warm = (row + col) % 2 == 1
                    let evenRow = row % 2 == 0
                    let tile: UIColor = warm ? (evenRow ? orange : brick) : (evenRow ? cream : butter)
                    tile.setFill()
                    UIBezierPath(rect: rect).fill()
                    UIColor(white: 0, alpha: 0.18).setStroke()
                    let border = UIBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
                    border.lineWidth = 2
                    border.stroke()

                    let textColor: UIColor = warm ? .white : darkText
                    let outline: UIColor = warm ? UIColor(white: 0, alpha: 0.55) : UIColor(white: 1, alpha: 0.8)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 46, weight: .heavy),
                        .foregroundColor: textColor,
                        .strokeColor: outline,
                        .strokeWidth: -3.0,
                    ]
                    ("\(n)" as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 4), withAttributes: attrs)

                    if n == 1 || n == 100 {
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.alignment = .center
                        let small: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 22, weight: .black),
                            .foregroundColor: textColor,
                            .paragraphStyle: paragraph,
                        ]
                        let caption = n == 1 ? "START" : "HOME"
                        (caption as NSString).draw(in: CGRect(x: rect.minX, y: rect.maxY - 34, width: cellPx, height: 30),
                                                   withAttributes: small)
                    }
                }
                // A dark outer border so the grid reads as a printed board.
                UIColor(red: 0.25, green: 0.12, blue: 0.05, alpha: 1).setStroke()
                let edge = UIBezierPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3))
                edge.lineWidth = 6
                edge.stroke()
            }
        }
    }
}

// MARK: - Shared snake/ladder parts

/// One natural snake look: body color, dorsal pattern color, the pale
/// outline some patterns carry, belly tint and the dorsal pattern itself.
/// Cycled by snake index (snakes sorted by head square), so with the
/// classic ten snakes almost every snake has its own identity at TV
/// distance.
private struct SnakeStyle {
    enum Pattern {
        case blotches   // python: big irregular dorsal saddles
        case diamonds   // rattlesnake: a chain of outlined diamonds
        case bands      // krait: full rings
        case coral      // coral snake: wide rings edged in a thin pale ring
        case zigzag     // viper: a dark zigzag down the spine
        case spots      // a double row of small dorsal spots
    }

    let base: UIColor
    let accent: UIColor
    let outline: UIColor
    let belly: UIColor
    let pattern: Pattern

    static let all: [SnakeStyle] = [
        // Green python.
        SnakeStyle(base: UIColor(red: 0.27, green: 0.50, blue: 0.16, alpha: 1),
                   accent: UIColor(red: 0.09, green: 0.20, blue: 0.06, alpha: 1),
                   outline: UIColor(red: 0.78, green: 0.82, blue: 0.40, alpha: 1),
                   belly: UIColor(red: 0.86, green: 0.86, blue: 0.56, alpha: 1), pattern: .blotches),
        // Brown/tan rattlesnake.
        SnakeStyle(base: UIColor(red: 0.70, green: 0.56, blue: 0.36, alpha: 1),
                   accent: UIColor(red: 0.33, green: 0.20, blue: 0.10, alpha: 1),
                   outline: UIColor(red: 0.95, green: 0.89, blue: 0.72, alpha: 1),
                   belly: UIColor(red: 0.93, green: 0.87, blue: 0.71, alpha: 1), pattern: .diamonds),
        // Black-and-yellow banded krait.
        SnakeStyle(base: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1),
                   accent: UIColor(red: 0.95, green: 0.80, blue: 0.16, alpha: 1),
                   outline: UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1),
                   belly: UIColor(red: 0.85, green: 0.78, blue: 0.50, alpha: 1), pattern: .bands),
        // Red coral-style: red with black rings edged in yellow.
        SnakeStyle(base: UIColor(red: 0.78, green: 0.13, blue: 0.08, alpha: 1),
                   accent: UIColor(red: 0.06, green: 0.05, blue: 0.05, alpha: 1),
                   outline: UIColor(red: 0.98, green: 0.84, blue: 0.22, alpha: 1),
                   belly: UIColor(red: 0.90, green: 0.55, blue: 0.40, alpha: 1), pattern: .coral),
        // Olive viper.
        SnakeStyle(base: UIColor(red: 0.45, green: 0.46, blue: 0.21, alpha: 1),
                   accent: UIColor(red: 0.17, green: 0.17, blue: 0.07, alpha: 1),
                   outline: UIColor(red: 0.70, green: 0.70, blue: 0.42, alpha: 1),
                   belly: UIColor(red: 0.82, green: 0.80, blue: 0.58, alpha: 1), pattern: .zigzag),
        // Brown python.
        SnakeStyle(base: UIColor(red: 0.56, green: 0.40, blue: 0.22, alpha: 1),
                   accent: UIColor(red: 0.22, green: 0.13, blue: 0.07, alpha: 1),
                   outline: UIColor(red: 0.85, green: 0.72, blue: 0.48, alpha: 1),
                   belly: UIColor(red: 0.90, green: 0.82, blue: 0.62, alpha: 1), pattern: .blotches),
        // Emerald tree snake with pale dorsal spots.
        SnakeStyle(base: UIColor(red: 0.08, green: 0.48, blue: 0.26, alpha: 1),
                   accent: UIColor(red: 0.90, green: 0.95, blue: 0.85, alpha: 1),
                   outline: UIColor(red: 0.04, green: 0.25, blue: 0.12, alpha: 1),
                   belly: UIColor(red: 0.80, green: 0.90, blue: 0.55, alpha: 1), pattern: .spots),
        // Grey-brown rattlesnake.
        SnakeStyle(base: UIColor(red: 0.56, green: 0.52, blue: 0.45, alpha: 1),
                   accent: UIColor(red: 0.24, green: 0.21, blue: 0.18, alpha: 1),
                   outline: UIColor(red: 0.90, green: 0.87, blue: 0.80, alpha: 1),
                   belly: UIColor(red: 0.88, green: 0.85, blue: 0.76, alpha: 1), pattern: .diamonds),
    ]

    static func style(_ index: Int) -> SnakeStyle {
        all[((index % all.count) + all.count) % all.count]
    }

    /// Side length of the square skin/normal textures, and of one scale.
    static let texturePixels = 128
    static let scalePixels = 16

    /// One repeat of the skin. `u` (x) runs around the body, with the top
    /// of the back (the dorsal line) at x = 0.25 and the belly at x = 0.75;
    /// `v` (y) runs along the body and repeats. Drawn once per style with
    /// Core Graphics and shared by every snake wearing that style.
    func skinTexture() -> UIImage {
        let w = CGFloat(SnakeStyle.texturePixels)
        let h = w
        let size = CGSize(width: w, height: h)
        return UIGraphicsImageRenderer(size: size).image { _ in
            base.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            // Lighter belly, feathered into the flanks.
            belly.withAlphaComponent(0.45).setFill()
            UIBezierPath(rect: CGRect(x: w * 0.52, y: 0, width: w * 0.46, height: h)).fill()
            belly.setFill()
            UIBezierPath(rect: CGRect(x: w * 0.60, y: 0, width: w * 0.30, height: h)).fill()

            switch pattern {
            case .blotches:
                // Irregular dorsal saddles with pale borders, python style,
                // plus small lateral blotches low on each flank.
                let saddles: [CGRect] = [
                    CGRect(x: w * 0.08, y: h * 0.04, width: w * 0.34, height: h * 0.36),
                    CGRect(x: w * 0.12, y: h * 0.54, width: w * 0.26, height: h * 0.34),
                ]
                for rect in saddles {
                    let saddle = UIBezierPath(roundedRect: rect, cornerRadius: w * 0.09)
                    outline.withAlphaComponent(0.9).setStroke()
                    saddle.lineWidth = 5
                    saddle.stroke()
                    accent.setFill()
                    saddle.fill()
                }
                accent.withAlphaComponent(0.8).setFill()
                UIBezierPath(ovalIn: CGRect(x: w * 0.44, y: h * 0.40, width: w * 0.10, height: h * 0.14)).fill()
                UIBezierPath(ovalIn: CGRect(x: w * 0.94, y: h * 0.40, width: w * 0.10, height: h * 0.14)).fill()
                UIBezierPath(ovalIn: CGRect(x: w * -0.06, y: h * 0.40, width: w * 0.10, height: h * 0.14)).fill()
            case .diamonds:
                // A chain of dark diamonds with pale borders down the spine.
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: w * 0.25, y: 0))
                diamond.addLine(to: CGPoint(x: w * 0.47, y: h * 0.5))
                diamond.addLine(to: CGPoint(x: w * 0.25, y: h))
                diamond.addLine(to: CGPoint(x: w * 0.03, y: h * 0.5))
                diamond.close()
                outline.setStroke()
                diamond.lineWidth = 8
                diamond.stroke()
                accent.setFill()
                diamond.fill()
                // Lighter diamond centres.
                let inner = UIBezierPath()
                inner.move(to: CGPoint(x: w * 0.25, y: h * 0.28))
                inner.addLine(to: CGPoint(x: w * 0.34, y: h * 0.5))
                inner.addLine(to: CGPoint(x: w * 0.25, y: h * 0.72))
                inner.addLine(to: CGPoint(x: w * 0.16, y: h * 0.5))
                inner.close()
                base.withAlphaComponent(0.6).setFill()
                inner.fill()
            case .bands:
                accent.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: w, height: h * 0.32)).fill()
            case .coral:
                outline.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: h * 0.0, width: w, height: h * 0.44)).fill()
                accent.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: h * 0.06, width: w, height: h * 0.32)).fill()
            case .zigzag:
                let zig = UIBezierPath()
                zig.move(to: CGPoint(x: w * 0.13, y: 0))
                zig.addLine(to: CGPoint(x: w * 0.37, y: h * 0.25))
                zig.addLine(to: CGPoint(x: w * 0.13, y: h * 0.5))
                zig.addLine(to: CGPoint(x: w * 0.37, y: h * 0.75))
                zig.addLine(to: CGPoint(x: w * 0.13, y: h))
                zig.lineJoinStyle = .miter
                outline.withAlphaComponent(0.7).setStroke()
                zig.lineWidth = w * 0.14
                zig.stroke()
                accent.setStroke()
                zig.lineWidth = w * 0.09
                zig.stroke()
            case .spots:
                accent.setFill()
                outline.setStroke()
                let spots: [(CGFloat, CGFloat)] = [(0.17, 0.2), (0.33, 0.45), (0.17, 0.7), (0.33, 0.95), (0.33, -0.05)]
                for (x, y) in spots {
                    let spot = UIBezierPath(ovalIn: CGRect(x: x * w - w * 0.06, y: y * h - w * 0.06,
                                                           width: w * 0.12, height: w * 0.12))
                    spot.fill()
                    spot.lineWidth = 2
                    spot.stroke()
                }
            }

            // Overlapping scale rows over everything: each scale is a
            // small arc, offset half a scale on alternate rows, with a
            // faint highlight on its upper edge. Same tiling as the
            // shared normal map, so the shading lines up with the lines.
            let cell = CGFloat(SnakeStyle.scalePixels)
            let cells = SnakeStyle.texturePixels / SnakeStyle.scalePixels
            for row in 0..<cells {
                let shift: CGFloat = row % 2 == 0 ? 0 : cell / 2
                for col in -1...cells {
                    let cx = CGFloat(col) * cell + cell / 2 - shift
                    let cy = CGFloat(row) * cell + cell / 2
                    let scale = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: cell * 0.55,
                                             startAngle: 0, endAngle: .pi, clockwise: true)
                    UIColor(white: 0, alpha: 0.22).setStroke()
                    scale.lineWidth = 1.5
                    scale.stroke()
                    let shine = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy - cell * 0.1), radius: cell * 0.3,
                                             startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: true)
                    UIColor(white: 1, alpha: 0.12).setStroke()
                    shine.lineWidth = 1.5
                    shine.stroke()
                }
            }
        }
    }

    /// A tangent-space normal map of domed, overlapping scales on the same
    /// tiling as `skinTexture`'s scale lines. Computed once (128x128) from a
    /// height field and shared by every snake.
    static func scaleNormalMap() -> UIImage? {
        let size = texturePixels
        let cell = scalePixels
        var height = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let row = y / cell
            let shift = row % 2 == 0 ? 0 : cell / 2
            for x in 0..<size {
                let lx = Float((x + shift) % cell) - Float(cell) / 2 + 0.5
                let ly = Float(y % cell) - Float(cell) / 2 + 0.5
                let d = sqrt(lx * lx + ly * ly) / (Float(cell) * 0.62)
                height[y * size + x] = max(0, 1 - d * d)
            }
        }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        let strength: Float = 2.2
        for y in 0..<size {
            for x in 0..<size {
                let left = height[y * size + (x + size - 1) % size]
                let right = height[y * size + (x + 1) % size]
                let up = height[((y + size - 1) % size) * size + x]
                let down = height[((y + 1) % size) * size + x]
                var nx = (left - right) * strength
                var ny = (up - down) * strength
                var nz: Float = 1
                let len = sqrt(nx * nx + ny * ny + nz * nz)
                nx /= len
                ny /= len
                nz /= len
                let i = (y * size + x) * 4
                pixels[i] = UInt8(max(0, min(255, (nx * 0.5 + 0.5) * 255)))
                pixels[i + 1] = UInt8(max(0, min(255, (ny * 0.5 + 0.5) * 255)))
                pixels[i + 2] = UInt8(max(0, min(255, (nz * 0.5 + 0.5) * 255)))
                pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Geometry and materials built once per board and shared by every snake
/// and ladder, so ten snakes and nine ladders cost a handful of materials
/// and textures rather than one of each per node.
@MainActor
private final class SnakeLadderSharedParts {
    /// One set for the app's lifetime: a handful of small textures and
    /// materials, reused by every board this TV ever shows.
    static let shared = SnakeLadderSharedParts()

    let woodMaterial: SCNMaterial
    let rungGeometry: SCNGeometry
    let eyeGeometry: SCNGeometry
    let pupilGeometry: SCNGeometry
    let glintGeometry: SCNGeometry
    let tongueGeometry: SCNGeometry
    let tongueForkGeometry: SCNGeometry
    /// The domed-scale normal map, shared by every snake's skin and head.
    private let scaleNormals: UIImage?
    private var bodyMaterials: [Int: SCNMaterial] = [:]
    private var headGeometries: [Int: SCNGeometry] = [:]

    init() {
        let wood = SCNMaterial()
        wood.lightingModel = .physicallyBased
        wood.diffuse.contents = SnakeLadderSharedParts.woodTexture(
            base: UIColor(red: 0.62, green: 0.38, blue: 0.16, alpha: 1))
        wood.roughness.contents = 0.65
        wood.metalness.contents = 0.0
        woodMaterial = wood

        let rung = SCNCylinder(radius: 0.035, height: 0.56)
        rung.radialSegmentCount = 10
        rung.materials = [wood]
        rungGeometry = rung

        let eyeMaterial = SCNMaterial()
        eyeMaterial.lightingModel = .physicallyBased
        eyeMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.72, blue: 0.15, alpha: 1)
        eyeMaterial.roughness.contents = 0.1
        let eye = SCNSphere(radius: 0.05)
        eye.segmentCount = 12
        eye.materials = [eyeMaterial]
        eyeGeometry = eye

        let pupilMaterial = SCNMaterial()
        pupilMaterial.lightingModel = .physicallyBased
        pupilMaterial.diffuse.contents = UIColor.black
        pupilMaterial.roughness.contents = 0.05
        let pupil = SCNSphere(radius: 0.03)
        pupil.segmentCount = 10
        pupil.materials = [pupilMaterial]
        pupilGeometry = pupil

        // The glossy highlight: a tiny unlit white dot on each eye, so the
        // eyes read as wet and alive under any light.
        let glintMaterial = SCNMaterial()
        glintMaterial.lightingModel = .constant
        glintMaterial.diffuse.contents = UIColor.white
        let glint = SCNSphere(radius: 0.012)
        glint.segmentCount = 6
        glint.materials = [glintMaterial]
        glintGeometry = glint

        let tongueMaterial = SCNMaterial()
        tongueMaterial.lightingModel = .physicallyBased
        tongueMaterial.diffuse.contents = UIColor(red: 0.85, green: 0.08, blue: 0.15, alpha: 1)
        tongueMaterial.roughness.contents = 0.3
        let tongue = SCNBox(width: 0.032, height: 0.012, length: 0.2, chamferRadius: 0)
        tongue.materials = [tongueMaterial]
        tongueGeometry = tongue
        let fork = SCNBox(width: 0.018, height: 0.01, length: 0.08, chamferRadius: 0)
        fork.materials = [tongueMaterial]
        tongueForkGeometry = fork

        scaleNormals = SnakeStyle.scaleNormalMap()
    }

    /// The patterned, scaled, repeating skin for a snake style.
    func bodyMaterial(style index: Int) -> SCNMaterial {
        let key = ((index % SnakeStyle.all.count) + SnakeStyle.all.count) % SnakeStyle.all.count
        if let cached = bodyMaterials[key] { return cached }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = SnakeStyle.style(key).skinTexture()
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.mipFilter = .linear
        if let scaleNormals {
            material.normal.contents = scaleNormals
            material.normal.wrapS = .repeat
            material.normal.wrapT = .repeat
            material.normal.mipFilter = .linear
            material.normal.intensity = 0.8
        }
        // Snakeskin has a soft satin sheen rather than a plastic shine.
        material.roughness.contents = 0.42
        material.metalness.contents = 0.0
        material.isDoubleSided = true
        bodyMaterials[key] = material
        return material
    }

    /// The head shape for a snake style: a sphere the snake scales into a
    /// flattened wedge, in the style's body color with the same scales.
    func headGeometry(style index: Int) -> SCNGeometry {
        let key = ((index % SnakeStyle.all.count) + SnakeStyle.all.count) % SnakeStyle.all.count
        if let cached = headGeometries[key] { return cached }
        let style = SnakeStyle.style(key)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = style.pattern == .coral ? style.accent : style.base
        if let scaleNormals {
            material.normal.contents = scaleNormals
            material.normal.wrapS = .repeat
            material.normal.wrapT = .repeat
            material.normal.contentsTransform = SCNMatrix4MakeScale(3, 2, 1)
            material.normal.intensity = 0.6
        }
        material.roughness.contents = 0.4
        let sphere = SCNSphere(radius: 0.24)
        sphere.segmentCount = 24
        sphere.materials = [material]
        headGeometries[key] = sphere
        return sphere
    }

    /// Varnished wood: a base tone with darker grain streaks running along
    /// the image's height (the long axis of a rail/rung box face).
    private static func woodTexture(base: UIColor) -> UIImage {
        let size = CGSize(width: 64, height: 256)
        return UIGraphicsImageRenderer(size: size).image { _ in
            base.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            // Fixed grain positions, so every launch looks the same.
            let grain: [(CGFloat, CGFloat, CGFloat)] = [
                (6, 2, 0.22), (13, 1, 0.12), (21, 3, 0.18), (30, 1, 0.10),
                (37, 2, 0.20), (45, 1, 0.14), (52, 3, 0.16), (59, 1, 0.12),
            ]
            for (x, width, alpha) in grain {
                UIColor(red: 0.18, green: 0.09, blue: 0.03, alpha: alpha).setFill()
                UIBezierPath(rect: CGRect(x: x, y: 0, width: width, height: size.height)).fill()
            }
        }
    }

    /// The tabletop the board rests on: warm, honey-toned planks with
    /// flowing grain and dark seams, tiled across a large slab.
    static func tableMaterial() -> SCNMaterial {
        let size = CGSize(width: 512, height: 512)
        let plankHeight: CGFloat = 128
        let tones: [UIColor] = [
            UIColor(red: 0.50, green: 0.30, blue: 0.15, alpha: 1),
            UIColor(red: 0.56, green: 0.34, blue: 0.17, alpha: 1),
            UIColor(red: 0.46, green: 0.27, blue: 0.13, alpha: 1),
            UIColor(red: 0.53, green: 0.32, blue: 0.16, alpha: 1),
        ]
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            for plank in 0..<4 {
                let top = CGFloat(plank) * plankHeight
                tones[plank % tones.count].setFill()
                UIBezierPath(rect: CGRect(x: 0, y: top, width: size.width, height: plankHeight)).fill()
                // Gently waving grain lines along each plank.
                for line in 0..<9 {
                    let baseY = top + 8 + CGFloat(line) * 13
                    let grain = UIBezierPath()
                    grain.move(to: CGPoint(x: 0, y: baseY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let wave = sin((x / size.width) * 2 * .pi * CGFloat(1 + (line + plank) % 3)
                                       + CGFloat(line)) * 3
                        grain.addLine(to: CGPoint(x: x, y: baseY + wave))
                        x += 16
                    }
                    UIColor(red: 0.20, green: 0.10, blue: 0.04, alpha: line % 3 == 0 ? 0.22 : 0.10).setStroke()
                    grain.lineWidth = line % 3 == 0 ? 2 : 1
                    grain.stroke()
                }
                // Dark seam between planks.
                UIColor(red: 0.12, green: 0.06, blue: 0.02, alpha: 0.85).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: top, width: size.width, height: 3)).fill()
            }
        }
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.mipFilter = .linear
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        material.roughness.contents = 0.45
        return material
    }
}

// MARK: - Snakes

/// A single snake: one smooth, continuous, tapering tube mesh swept along
/// an S-curve from its head square to its tail square, with a slightly
/// flattened cross-section so it reads as lying on the board, a scaled
/// skin, a wedge-shaped head (glossy eyes, a forked tongue that flicks
/// now and then) on the head square and a thin pointed tail ending on the
/// tail square. The body is built once and is one draw call; the only
/// animation is a couple of `SCNAction` loops on the head and tongue --
/// no per-frame mesh rebuilds.
@MainActor
private final class SnakeNode {
    let rootNode = SCNNode()
    /// The body centerline from head (index 0) to tail (last index) --
    /// exposed so the token can be animated sliding down it after being
    /// "eaten".
    let pathPoints: [SCNVector3]

    /// Idle sway/lift lives here...
    private let swayNode: SCNNode
    /// ...and the one-shot strike lives here, so neither fights the other.
    private let gestureNode: SCNNode
    private let tongueNode: SCNNode

    /// Height of the body's cross-section relative to its width.
    private static let flatten: Float = 0.72

    /// Same initializer shape as the original capsule snake (and the
    /// drop-in `RealisticSnakeNode`), so the two are interchangeable at the
    /// one call site. `color`/`bandColor` pick the matching `SnakeStyle`
    /// (pattern, belly and outline included); colors that match no style
    /// fall back to the first style's pattern in the given colors.
    init(headSquare: Int, tailSquare: Int, squareToPoint: (Int) -> SCNVector3,
         color: UIColor, bandColor: UIColor) {
        let parts = SnakeLadderSharedParts.shared
        let styleIndex = SnakeStyle.all.firstIndex { $0.base == color && $0.accent == bandColor } ?? 0
        let head2D = squareToPoint(headSquare)
        // `squareToPoint` returns points on the board's top surface.
        let boardTopY = head2D.y
        let tail2D = squareToPoint(tailSquare)
        let dx = tail2D.x - head2D.x
        let dz = tail2D.z - head2D.z
        let length = sqrt(dx * dx + dz * dz)
        let perp: SCNVector3 = length > 0.0001
            ? SCNVector3(-dz / length, 0, dx / length)
            : SCNVector3(1, 0, 0)

        // A smooth S-curve whose wiggle fades to zero at both ends, so the
        // head sits exactly on the head square and the tail tip exactly on
        // the tail square. Alternate snakes bend the opposite way. The
        // curve is analytic (a sine wave under a sine envelope), so it is
        // smooth at any sample count -- no control-point kinks.
        let samples = max(28, min(72, Int(length / 0.13)))
        let waves = max(1, (length / 2.4).rounded())
        let amplitude = min(0.42, 0.2 + length * 0.025) * (styleIndex.isMultiple(of: 2) ? 1 : -1)
        var centers: [SCNVector3] = []
        var radii: [Float] = []
        centers.reserveCapacity(samples + 1)
        radii.reserveCapacity(samples + 1)
        for i in 0...samples {
            let t = Float(i) / Float(samples)
            let offset = amplitude * sin(2 * Float.pi * waves * t) * sin(Float.pi * t)
            let r = SnakeNode.radius(at: t)
            radii.append(r)
            centers.append(SCNVector3(head2D.x + dx * t + perp.x * offset,
                                      boardTopY + r * SnakeNode.flatten * 0.92,
                                      head2D.z + dz * t + perp.z * offset))
        }
        pathPoints = centers

        let skin = parts.bodyMaterial(style: styleIndex)
        let tube = SnakeNode.tubeGeometry(centers: centers, radii: radii, radialSegments: 12,
                                          flatten: SnakeNode.flatten, repeatLength: 0.85)
        tube.materials = [skin]
        rootNode.addChildNode(SCNNode(geometry: tube))

        // Close the thin tail tip.
        if let tipCenter = centers.last, let tipRadius = radii.last {
            let tip = SCNSphere(radius: CGFloat(tipRadius))
            tip.segmentCount = 8
            tip.materials = [skin]
            let tipNode = SCNNode(geometry: tip)
            tipNode.position = tipCenter
            tipNode.scale = SCNVector3(1, SnakeNode.flatten, 1)
            rootNode.addChildNode(tipNode)
        }

        // The head faces away from the body.
        let first = centers[0]
        let second = centers.count > 1 ? centers[1] : SCNVector3(first.x, first.y, first.z + 1)
        let forward = SnakeLadderGeometry.normalized(
            SCNVector3(first.x - second.x, 0, first.z - second.z), fallback: SCNVector3(0, 0, 1))
        let heading = atan2(forward.x, forward.z)

        let orient = SCNNode()
        orient.position = SCNVector3(first.x, boardTopY + 0.15, first.z)
        orient.eulerAngles = SCNVector3(0, heading, 0)
        let sway = SCNNode()
        orient.addChildNode(sway)
        let gesture = SCNNode()
        sway.addChildNode(gesture)

        // A wedge: a broad, flat skull blending into a narrower, flatter
        // snout -- two scaled copies of the same sphere.
        let headShape = parts.headGeometry(style: styleIndex)
        let skull = SCNNode(geometry: headShape)
        skull.scale = SCNVector3(1.0, 0.6, 1.05)
        skull.position = SCNVector3(0, 0, 0.02)
        gesture.addChildNode(skull)
        let snout = SCNNode(geometry: headShape)
        snout.scale = SCNVector3(0.72, 0.46, 0.95)
        snout.position = SCNVector3(0, -0.015, 0.2)
        gesture.addChildNode(snout)

        for side: Float in [-1, 1] {
            let eye = SCNNode(geometry: parts.eyeGeometry)
            eye.position = SCNVector3(side * 0.15, 0.08, 0.15)
            gesture.addChildNode(eye)
            let pupil = SCNNode(geometry: parts.pupilGeometry)
            pupil.position = SCNVector3(side * 0.175, 0.085, 0.16)
            pupil.scale = SCNVector3(0.5, 1.0, 0.45)   // a vertical slit
            gesture.addChildNode(pupil)
            let glint = SCNNode(geometry: parts.glintGeometry)
            glint.position = SCNVector3(side * 0.19, 0.11, 0.18)
            glint.castsShadow = false
            gesture.addChildNode(glint)
        }

        // Forked tongue: a thin red strip plus two angled tips, inside a
        // container scaled from the mouth so a flick shoots it out.
        let tongue = SCNNode()
        tongue.position = SCNVector3(0, -0.04, 0.4)
        tongue.scale = SCNVector3(0.05, 0.05, 0.05)
        let strip = SCNNode(geometry: parts.tongueGeometry)
        strip.position = SCNVector3(0, 0, 0.1)
        tongue.addChildNode(strip)
        for side: Float in [-1, 1] {
            let fork = SCNNode(geometry: parts.tongueForkGeometry)
            fork.position = SCNVector3(side * 0.016, 0, 0.23)
            fork.eulerAngles = SCNVector3(0, side * 0.45, 0)
            tongue.addChildNode(fork)
        }
        tongue.castsShadow = false
        gesture.addChildNode(tongue)

        rootNode.addChildNode(orient)
        swayNode = sway
        gestureNode = gesture
        tongueNode = tongue

        startIdle(phase: Double(styleIndex % 5) * 0.37, restSeconds: 2.4 + Double(styleIndex % 3) * 0.8)
    }

    /// Body radius along the snake: a slim neck behind the head, the
    /// thickest point a little way down, tapering to a thin tail.
    private static func radius(at t: Float) -> Float {
        if t < 0.15 {
            return 0.13 + 0.05 * (t / 0.15)
        }
        let rest = (t - 0.15) / 0.85
        return 0.165 * pow(max(0, 1 - rest), 1.1) + 0.015
    }

    /// A tube swept along `centers`: rings of `radialSegments + 1` vertices
    /// (the seam is duplicated so the texture wraps cleanly) on an
    /// elliptical cross-section `flatten` times as tall as it is wide,
    /// outward ellipse normals, and texture coordinates with `u` around the
    /// body (0.25 = top of the back) and `v` along it in repeats of
    /// `repeatLength`.
    private static func tubeGeometry(centers: [SCNVector3], radii: [Float], radialSegments: Int,
                                     flatten: Float, repeatLength: Float) -> SCNGeometry {
        let ringCount = centers.count
        let stride = radialSegments + 1
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []
        vertices.reserveCapacity(ringCount * stride)
        normals.reserveCapacity(ringCount * stride)
        uvs.reserveCapacity(ringCount * stride)
        indices.reserveCapacity(max(0, ringCount - 1) * radialSegments * 6)

        let up = SCNVector3(0, 1, 0)
        var arc: Float = 0
        for i in 0..<ringCount {
            let c = centers[i]
            if i > 0 { arc += SnakeLadderGeometry.distance(c, centers[i - 1]) }
            let prev = centers[max(i - 1, 0)]
            let next = centers[min(i + 1, ringCount - 1)]
            let tangent = SnakeLadderGeometry.normalized(SnakeLadderGeometry.subtract(next, prev),
                                                         fallback: SCNVector3(1, 0, 0))
            let side = SnakeLadderGeometry.normalized(SnakeLadderGeometry.cross(tangent, up),
                                                      fallback: SCNVector3(0, 0, 1))
            let lift = SnakeLadderGeometry.cross(side, tangent)
            let r = i < radii.count ? radii[i] : 0.05
            for j in 0...radialSegments {
                let a = Float(j) / Float(radialSegments) * 2 * Float.pi
                let ca = cos(a)
                let sa = sin(a)
                // Point on the ellipse (semi-axes r and r * flatten)...
                let offset = SCNVector3(side.x * ca * r + lift.x * sa * r * flatten,
                                        side.y * ca * r + lift.y * sa * r * flatten,
                                        side.z * ca * r + lift.z * sa * r * flatten)
                vertices.append(SCNVector3(c.x + offset.x, c.y + offset.y, c.z + offset.z))
                // ...and its outward normal, proportional to (flatten * cos, sin).
                let normal = SnakeLadderGeometry.normalized(
                    SCNVector3(side.x * ca * flatten + lift.x * sa,
                               side.y * ca * flatten + lift.y * sa,
                               side.z * ca * flatten + lift.z * sa),
                    fallback: up)
                normals.append(normal)
                uvs.append(CGPoint(x: CGFloat(j) / CGFloat(radialSegments),
                                   y: CGFloat(arc / repeatLength)))
            }
        }
        if ringCount > 1 {
            for i in 0..<(ringCount - 1) {
                for j in 0..<radialSegments {
                    let a = Int32(i * stride + j)
                    let b = Int32((i + 1) * stride + j)
                    indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
                }
            }
        }

        let sources = [
            SCNGeometrySource(vertices: vertices),
            SCNGeometrySource(normals: normals),
            SCNGeometrySource(textureCoordinates: uvs),
        ]
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: sources, elements: [element])
    }

    /// Always-running, cheap idle: the head sways and lifts a little (a
    /// gentle slither at the business end) and the forked tongue flicks
    /// every few seconds. Phase-shifted per snake so ten snakes never move
    /// in lockstep. Pure `SCNAction` loops -- no per-frame code.
    private func startIdle(phase: TimeInterval, restSeconds: TimeInterval) {
        let axis = SCNVector3(0, 1, 0)
        let swayOut = SCNAction.rotate(by: 0.24, around: axis, duration: 1.5)
        swayOut.timingMode = .easeInEaseOut
        let liftUp = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 1.5)
        liftUp.timingMode = .easeInEaseOut
        let out = SCNAction.group([swayOut, liftUp])
        let back = SCNAction.group([swayOut.reversed(), liftUp.reversed()])
        swayNode.runAction(.sequence([
            .wait(duration: phase),
            .rotate(by: -0.12, around: axis, duration: 0.75),
            .repeatForever(.sequence([out, back])),
        ]), forKey: "idleSway")

        tongueNode.runAction(.sequence([
            .wait(duration: phase + 0.6),
            .repeatForever(.sequence([
                SnakeNode.tongueFlick(),
                .wait(duration: restSeconds),
            ])),
        ]), forKey: "idleTongue")
    }

    /// Two quick in-out flicks of the tongue.
    private static func tongueFlick() -> SCNAction {
        .sequence([
            .scale(to: 1.0, duration: 0.07),
            .wait(duration: 0.14),
            .scale(to: 0.05, duration: 0.07),
            .wait(duration: 0.1),
            .scale(to: 1.0, duration: 0.07),
            .wait(duration: 0.14),
            .scale(to: 0.05, duration: 0.07),
        ])
    }

    /// A one-shot strike-and-gulp when a token lands on the head: the head
    /// rears, lunges forward and snaps back, tongue out. Distinct from both
    /// the idle loop above and the normal square-to-square walk.
    func playEat() {
        gestureNode.removeAction(forKey: "eat")
        gestureNode.scale = SCNVector3(1, 1, 1)
        gestureNode.eulerAngles = SCNVector3(0, 0, 0)
        gestureNode.position = SCNVector3(0, 0, 0)
        let strike = SCNAction.group([
            .scale(to: 1.4, duration: 0.15),
            .rotateTo(x: -0.45, y: 0, z: 0, duration: 0.15),
            .move(to: SCNVector3(0, 0.05, 0.25), duration: 0.15),
        ])
        strike.timingMode = .easeOut
        let settle = SCNAction.group([
            .scale(to: 1.0, duration: 0.22),
            .rotateTo(x: 0, y: 0, z: 0, duration: 0.22),
            .move(to: SCNVector3(0, 0, 0), duration: 0.22),
        ])
        settle.timingMode = .easeInEaseOut
        gestureNode.runAction(.sequence([strike, .wait(duration: 0.12), settle]), forKey: "eat")
        tongueNode.runAction(SnakeNode.tongueFlick(), forKey: "eatTongue")
    }
}

// MARK: - Ladders

/// A wooden ladder: two rails plus evenly spaced rungs, laid between a
/// ladder's bottom and top squares. Built from the shared wood material and
/// a shared rung geometry, then flattened into a single node so each ladder
/// costs one draw call.
@MainActor
private final class LadderNode {
    let rootNode: SCNNode
    let bottomWorldPosition: SCNVector3
    let topWorldPosition: SCNVector3
    let rungCount: Int

    init(bottomSquare: Int, topSquare: Int, squareToPoint: (Int) -> SCNVector3, parts: SnakeLadderSharedParts) {
        let a = squareToPoint(bottomSquare)
        let b = squareToPoint(topSquare)
        let bottom = SCNVector3(a.x, a.y + 0.09, a.z)
        let top = SCNVector3(b.x, b.y + 0.09, b.z)
        bottomWorldPosition = bottom
        topWorldPosition = top

        let dx = top.x - bottom.x
        let dz = top.z - bottom.z
        let length = sqrt(dx * dx + dz * dz)
        let safeLength = length > 0.0001 ? length : 1
        let along = SCNVector3(dx / safeLength, 0, dz / safeLength)
        let perp = SCNVector3(-along.z, 0, along.x)
        let railOffset: Float = 0.26
        // The rails overhang the end squares a little, like a real ladder
        // resting on the board.
        let overhang: Float = 0.22

        let assembly = SCNNode()
        for sign: Float in [-1, 1] {
            let railA = SCNVector3(bottom.x - along.x * overhang + perp.x * railOffset * sign, bottom.y,
                                   bottom.z - along.z * overhang + perp.z * railOffset * sign)
            let railB = SCNVector3(top.x + along.x * overhang + perp.x * railOffset * sign, top.y,
                                   top.z + along.z * overhang + perp.z * railOffset * sign)
            assembly.addChildNode(LadderNode.rail(from: railA, to: railB, material: parts.woodMaterial))
        }

        let rungs = max(4, Int(length / 0.42))
        rungCount = rungs
        for i in 0...rungs {
            let t = Float(i) / Float(rungs)
            let rung = SCNNode(geometry: parts.rungGeometry)
            rung.position = SCNVector3(bottom.x + dx * t, bottom.y, bottom.z + dz * t)
            SnakeLadderGeometry.alignYAxis(of: rung, to: perp)
            assembly.addChildNode(rung)
        }
        rootNode = assembly.flattenedClone()
    }

    private static func rail(from a: SCNVector3, to b: SCNVector3, material: SCNMaterial) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = max(sqrt(dx * dx + dy * dy + dz * dz), 0.02)
        let box = SCNBox(width: 0.09, height: CGFloat(length), length: 0.06, chamferRadius: 0.015)
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        SnakeLadderGeometry.alignYAxis(of: node, to: SCNVector3(dx, dy, dz))
        return node
    }
}

/// Shared vector math. `alignYAxis` orients a primitive (capsule/box/
/// cylinder) so its local +Y axis points along an arbitrary 3D direction --
/// the standard "rotate one vector onto another" construction (axis = cross
/// product, angle = arccos of the dot product). Kept as static functions
/// rather than `SCNVector3` operator overloads, so nothing here can collide
/// with helpers declared elsewhere in the app.
private enum SnakeLadderGeometry {
    static func subtract(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ v: SCNVector3) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }

    static func distance(_ a: SCNVector3, _ b: SCNVector3) -> Float {
        length(subtract(a, b))
    }

    static func normalized(_ v: SCNVector3, fallback: SCNVector3) -> SCNVector3 {
        let l = length(v)
        guard l > 0.00001 else { return fallback }
        return SCNVector3(v.x / l, v.y / l, v.z / l)
    }

    static func nearlyEqual(_ a: SCNVector3, _ b: SCNVector3) -> Bool {
        distance(a, b) < 0.001
    }

    static func alignYAxis(of node: SCNNode, to direction: SCNVector3) {
        let len = length(direction)
        guard len > 0.0001 else { return }
        let to = SCNVector3(direction.x / len, direction.y / len, direction.z / len)
        let from = SCNVector3(0, 1, 0)
        let dot = max(-1, min(1, from.x * to.x + from.y * to.y + from.z * to.z))
        if dot > 0.9999 { return }
        if dot < -0.9999 {
            node.eulerAngles = SCNVector3(Float.pi, 0, 0)
            return
        }
        let axis = cross(from, to)
        let axisLength = length(axis)
        let angle = acos(dot)
        node.rotation = SCNVector4(axis.x / axisLength, axis.y / axisLength, axis.z / axisLength, angle)
    }
}

// MARK: - Dice

/// A cube whose top face's texture is swapped to the rolled value's pips
/// once its tumble finishes -- rather than computing the (much fussier)
/// rotation that would put a fixed face's pre-existing pips physically
/// upright, this gets the same "settles on the rolled value" result by
/// controlling which texture that face shows. The number is always also
/// shown as legible SwiftUI text in the HUD, so this cube is atmosphere,
/// never the only place the value lives.
@MainActor
private final class DiceNode {
    let rootNode = SCNNode()
    private let cubeNode: SCNNode
    private let topMaterial = SCNMaterial()
    /// Bumped on every roll, so a stale settle from an earlier, interrupted
    /// tumble never overwrites a newer roll's face.
    private var rollToken = 0

    init() {
        let sideMaterial = SCNMaterial()
        sideMaterial.lightingModel = .physicallyBased
        sideMaterial.diffuse.contents = UIColor.white
        sideMaterial.roughness.contents = 0.35

        topMaterial.lightingModel = .physicallyBased
        topMaterial.diffuse.contents = DiceNode.pipTexture(value: 1)
        topMaterial.roughness.contents = 0.3

        let box = SCNBox(width: 0.5, height: 0.5, length: 0.5, chamferRadius: 0.06)
        box.materials = [sideMaterial, sideMaterial, sideMaterial, sideMaterial, topMaterial, sideMaterial]

        let node = SCNNode(geometry: box)
        cubeNode = node
        rootNode.addChildNode(node)
    }

    /// Tumbles the cube, then -- once the spin finishes -- swaps its top
    /// face to `value`'s pips and resets orientation, reading as "the die
    /// settled on this number".
    func roll(to value: Int) {
        rollToken += 1
        let token = rollToken
        cubeNode.removeAction(forKey: "roll")
        let spinDuration: TimeInterval = 0.85
        let spin = SCNAction.rotateBy(x: CGFloat.pi * 5, y: CGFloat.pi * 3, z: CGFloat.pi * 2, duration: spinDuration)
        spin.timingMode = .easeOut
        cubeNode.runAction(spin, forKey: "roll")

        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) { [weak self] in
            guard let self, self.rollToken == token else { return }
            self.topMaterial.diffuse.contents = DiceNode.pipTexture(value: value)
            self.cubeNode.eulerAngles = SCNVector3(0, 0, 0)
        }
    }

    private static func pipTexture(value: Int) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            UIColor.black.setFill()
            let radius: CGFloat = 12
            for pip in SnakeLadderDice.pips(for: value) {
                let center = CGPoint(x: pip.x * size.width, y: pip.y * size.height)
                UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2)).fill()
            }
        }
    }
}
