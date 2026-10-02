import SwiftUI
import SceneKit
import UIKit

// ---------------------------------------------------------------------------
// Snake & Ladder finally gets a real board. `TVGameBoardView` used to route
// `.snakeLadder` straight to `TVWebGameBoardView` -- a `WKWebView` pointing
// at the old, dead `games/snake_ladder` browser game (its `game_logic.py`/
// `models.py` are empty) -- so the TV showed a "coming soon" placeholder no
// matter how far along `SnakeLadderEngine` (the real, working native
// backend) was. This file is the board that was never built: a full 3D
// scene in the style of `PokerCinematicBoardSceneView` (same
// `CinematicCameraRig`/`CinematicLighting` primitives, built directly
// rather than through the generic `CinematicBoardSceneView` wrapper, since
// this needs live per-square token/snake/ladder content, not just a
// `TablePhase` label), reusing the "primitives + procedural `SCNAction`
// joints" technique `PokerDealerNode` proved out -- no imported 3D models
// anywhere in this project, and no toolchain here to make one.
//
// `SnakeLadderEngine.public_state()` now exposes its `snakes`/`ladders`
// maps directly (see `games/native_hub/engines/legacy_boards.py`), so this
// file treats them as the single authoritative board layout instead of
// hardcoding its own copy that could silently drift from the engine's.
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
            snakes = Dictionary(uniqueKeysWithValues: raw.compactMap { entry -> (Int, Int)? in
                guard let head = Int(entry.key), let tail = entry.value as? Int else { return nil }
                return (head, tail)
            })
        }
        if let raw = data["ladders"]?.value as? [String: Any] {
            ladders = Dictionary(uniqueKeysWithValues: raw.compactMap { entry -> (Int, Int)? in
                guard let bottom = Int(entry.key), let top = entry.value as? Int else { return nil }
                return (bottom, top)
            })
        }
        if let raw = data["lastSlide"]?.value as? [String: Any] {
            lastSlide = Dictionary(uniqueKeysWithValues: raw.compactMap { entry -> (String, SnakeLadderSlide)? in
                guard let d = entry.value as? [String: Any],
                      let kind = d["kind"] as? String,
                      let from = d["from"] as? Int,
                      let to = d["to"] as? Int,
                      let seq = d["seq"] as? Int else { return nil }
                return (entry.key, SnakeLadderSlide(playerID: entry.key, kind: kind, from: from, to: to, seq: seq))
            })
        }
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

// MARK: - TV board

struct TVSnakeLadderBoardView: View {
    let room: Room
    @StateObject private var vm = SnakeLadderBoardViewModel()

    private var currentName: String {
        vm.state.players.first { $0.id == vm.state.currentPlayerID }?.name ?? "\u{2014}"
    }
    private var winnerName: String? {
        guard let id = vm.state.winner else { return nil }
        return vm.state.players.first { $0.id == id }?.name
    }

    var body: some View {
        ZStack {
            // The real 3D board: 100 numbered squares, 3 resting/animated
            // snakes, 10 ladders, and a token per player, shot with the
            // cinematic camera rig. Every number below is rendered again as
            // legible SwiftUI text over the top -- the 3D scene is
            // atmosphere, never the only place a state fact lives.
            SnakeLadderCinematicBoardSceneView(state: vm.state)
                .ignoresSafeArea()

            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                TVRoundHeader(symbol: "arrow.up.right", title: "Snake & Ladder", round: 0, totalRounds: 0,
                              secondsLeft: vm.state.secondsLeft,
                              phaseLabel: vm.state.winner != nil ? "game over" : "\(currentName)'s turn")

                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.state.positions.sorted { $0.position > $1.position }) { p in
                            SnakeLadderPositionRow(entry: p, isCurrent: p.playerID == vm.state.currentPlayerID)
                        }
                    }
                    .padding(.leading, 48).padding(.top, 24)

                    Spacer()

                    if let id = vm.state.currentPlayerID, let roll = vm.state.lastRoll[id] {
                        VStack(spacing: 4) {
                            Text("LAST ROLL").font(.caption.bold()).tracking(2)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(roll)").font(.system(size: 44, weight: .heavy)).foregroundColor(.yellow)
                        }
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
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.yellow)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

private struct SnakeLadderPositionRow: View {
    let entry: SnakeLadderPlayerPosition
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isCurrent ? Color.yellow : Color.white.opacity(0.2))
                .frame(width: 10, height: 10)
            // A long name must truncate with an ellipsis, never wrap
            // mid-word ("Gand"/"hi" on two lines). The fixed-width parent
            // below gives the truncation a bound to work against.
            Text(entry.name).font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(isCurrent ? .white : .white.opacity(0.6))
            Spacer()
            Text(entry.position == 0 ? "start" : "\(entry.position)")
                .font(.subheadline.bold()).foregroundColor(.cyan)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(width: 260)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(isCurrent ? Color.white.opacity(0.14) : Color.white.opacity(0.05)))
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
        view.backgroundColor = .black
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
        private let tokenHoverHeight: Float = 0.22

        private var tokenNodes: [String: SCNNode] = [:]
        private var lastPositions: [String: Int] = [:]
        private var boardBuilt = false
        private var snakeNodes: [Int: SnakeNode] = [:]
        private var ladderNodes: [Int: LadderNode] = [:]
        private var lastAnnouncedWinner: String?
        /// Slide-event seqs already played, per player -- `lastSlide`
        /// survives in the engine state until that player's next move, so
        /// without this every re-broadcast would replay the cinematic.
        private var seenSlideSeq: [String: Int] = [:]

        init() {
            // A wide, angled 3/4 overhead shot -- the whole board, the dice
            // podium, and the staging area all read at once, the way a
            // board game is normally seen. `boardRadius` here is purely a
            // framing distance for the camera math below, not a stored
            // property, so referencing it doesn't touch `self` before
            // `cameraRig`/`lighting` (the two properties with no default
            // value) are actually assigned -- the same "local constant
            // instead of self" rule `PokerCinematicBoardSceneView.Coordinator.init()`
            // documents for its own `radius` local.
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

            let floor = SCNNode(geometry: SCNCylinder(radius: CGFloat(boardRadius) * 2.6, height: 0.02))
            let floorMaterial = SCNMaterial()
            floorMaterial.lightingModel = .physicallyBased
            floorMaterial.diffuse.contents = UIColor(white: 0.03, alpha: 1)
            floorMaterial.roughness.contents = 0.9
            floor.geometry?.materials = [floorMaterial]
            floor.position = SCNVector3(0, -0.2, 0)
            scene.rootNode.addChildNode(floor)

            let dicePosition = SCNVector3(-(boardExtent / 2 + 1.4), 0.35, -(boardExtent / 2 + 0.5))
            dice.rootNode.position = dicePosition
            scene.rootNode.addChildNode(dice.rootNode)

            let pedestalMaterial = SCNMaterial()
            pedestalMaterial.lightingModel = .physicallyBased
            pedestalMaterial.diffuse.contents = UIColor(red: 0.14, green: 0.12, blue: 0.20, alpha: 1)
            pedestalMaterial.roughness.contents = 0.6
            let pedestal = SCNNode(geometry: SCNCylinder(radius: 0.5, height: 0.5))
            pedestal.geometry?.materials = [pedestalMaterial]
            pedestal.position = SCNVector3(dicePosition.x, 0.1, dicePosition.z)
            scene.rootNode.addChildNode(pedestal)
        }

        // MARK: - Board dressing (built once, the first time snakes/ladders arrive)

        private func ensureBoardDressing(state: SnakeLadderBoardState) {
            guard !boardBuilt, !state.snakes.isEmpty else { return }
            boardBuilt = true

            let boardImage = Coordinator.boardTexture(snakes: state.snakes, ladders: state.ladders)
            let sideMaterial = SCNMaterial()
            sideMaterial.lightingModel = .physicallyBased
            sideMaterial.diffuse.contents = UIColor(red: 0.32, green: 0.20, blue: 0.11, alpha: 1)
            sideMaterial.roughness.contents = 0.7
            let topMaterial = SCNMaterial()
            topMaterial.lightingModel = .physicallyBased
            topMaterial.diffuse.contents = boardImage
            topMaterial.roughness.contents = 0.5

            // SCNBox material order is documented as front/right/back/left/
            // top/bottom -- index 4 is the +y face, the only one that needs
            // the numbered grid texture.
            let slab = SCNBox(width: CGFloat(boardExtent), height: 0.12, length: CGFloat(boardExtent), chamferRadius: 0.02)
            slab.materials = [sideMaterial, sideMaterial, sideMaterial, sideMaterial, topMaterial, sideMaterial]
            scene.rootNode.addChildNode(SCNNode(geometry: slab))

            for (head, tail) in state.snakes {
                let (color, band) = Coordinator.snakeColors[snakeNodes.count % Coordinator.snakeColors.count]
                let snake = SnakeNode(headSquare: head, tailSquare: tail, squareToPoint: squareToPoint,
                                      color: color, bandColor: band)
                scene.rootNode.addChildNode(snake.rootNode)
                snakeNodes[head] = snake
            }
            for (bottom, top) in state.ladders {
                let ladder = LadderNode(bottomSquare: bottom, topSquare: top, squareToPoint: squareToPoint)
                scene.rootNode.addChildNode(ladder.rootNode)
                ladderNodes[bottom] = ladder
            }
        }

        /// (body color, band color). Saturated and banded so each snake is
        /// unmistakable at TV distance -- and unmistakably not a ladder,
        /// which is bright gold and straight-edged.
        private static let snakeColors: [(UIColor, UIColor)] = [
            (UIColor(red: 0.82, green: 0.16, blue: 0.12, alpha: 1),
             UIColor(red: 1.00, green: 0.55, blue: 0.30, alpha: 1)),
            (UIColor(red: 0.14, green: 0.60, blue: 0.26, alpha: 1),
             UIColor(red: 0.62, green: 1.00, blue: 0.52, alpha: 1)),
            (UIColor(red: 0.42, green: 0.18, blue: 0.78, alpha: 1),
             UIColor(red: 0.74, green: 0.54, blue: 1.00, alpha: 1)),
        ]

        private static let tokenPalette: [UIColor] = [
            UIColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1),
            UIColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1),
            UIColor(red: 0.30, green: 0.85, blue: 0.40, alpha: 1),
            UIColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1),
            UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1),
            UIColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1),
        ]

        private func rebuildTokensIfNeeded(players: [SnakeLadderPlayerPosition]) {
            for entry in players where tokenNodes[entry.playerID] == nil {
                let color = Coordinator.tokenPalette[tokenNodes.count % Coordinator.tokenPalette.count]
                let token = Coordinator.makeTokenNode(color: color)
                scene.rootNode.addChildNode(token)
                tokenNodes[entry.playerID] = token
            }
        }

        private static func makeTokenNode(color: UIColor) -> SCNNode {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.metalness.contents = 0.15
            material.roughness.contents = 0.4

            let body = SCNNode(geometry: SCNCone(topRadius: 0.02, bottomRadius: 0.13, height: 0.28))
            body.geometry?.materials = [material]
            let head = SCNNode(geometry: SCNSphere(radius: 0.09))
            head.geometry?.materials = [material]
            head.position = SCNVector3(0, 0.19, 0)

            let root = SCNNode()
            root.addChildNode(body)
            root.addChildNode(head)

            let bobUp = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 0.9)
            bobUp.timingMode = .easeInEaseOut
            root.runAction(.repeatForever(.sequence([bobUp, bobUp.reversed()])), forKey: "idleBob")
            return root
        }

        // MARK: - Live state -> scene

        func apply(_ state: SnakeLadderBoardState, animated: Bool) {
            ensureBoardDressing(state: state)
            rebuildTokensIfNeeded(players: state.positions)

            if !animated {
                // First paint (or a full rebind): adopt the board as-is.
                // Any slide event the engine is still holding -- e.g. after
                // a rejoin mid-game -- is history, not a cue: record its
                // seq so it is never replayed as a cinematic.
                for (pid, slide) in state.lastSlide { seenSlideSeq[pid] = slide.seq }
            }

            var bySquare: [Int: [String]] = [:]
            for entry in state.positions { bySquare[entry.position, default: []].append(entry.playerID) }

            for entry in state.positions {
                guard let token = tokenNodes[entry.playerID] else { continue }
                let group = bySquare[entry.position] ?? [entry.playerID]
                let offsetIndex = group.firstIndex(of: entry.playerID) ?? 0
                let anchor = tokenAnchor(square: entry.position, offsetIndex: offsetIndex, offsetCount: group.count)
                let previous = lastPositions[entry.playerID] ?? 0

                if !animated || previous == entry.position {
                    token.position = anchor
                } else if let slide = state.lastSlide[entry.playerID],
                          slide.seq != seenSlideSeq[entry.playerID],
                          slide.to == entry.position {
                    // Authoritative slide event from the engine: play the
                    // full bite/climb cinematic (with its sound) instead of
                    // a plain hop. The seq check dedupes re-broadcasts.
                    seenSlideSeq[entry.playerID] = slide.seq
                    playSlideEvent(kind: slide.kind, from: slide.from, token: token,
                                   previous: previous, finalAnchor: anchor,
                                   diceValue: state.lastRoll[entry.playerID])
                } else {
                    let diceValue = state.lastRoll[entry.playerID] ?? max(entry.position - previous, 1)
                    animateMove(token: token, from: previous, to: entry.position, diceValue: diceValue, finalAnchor: anchor)
                }
                lastPositions[entry.playerID] = entry.position
            }

            if let winnerID = state.winner, winnerID != lastAnnouncedWinner {
                lastAnnouncedWinner = winnerID
                cameraRig.transition(to: Coordinator.winnerShot(), duration: 1.6)
            } else if state.winner == nil {
                lastAnnouncedWinner = nil
            }
        }

        /// Plain hop-to-hop token movement. Snake bites and ladder climbs
        /// never come through here -- the engine broadcasts an explicit
        /// `lastSlide` event for those and `apply` routes it to
        /// `playSlideEvent`, which is the only place the bite/climb
        /// cinematics (and their sounds) live.
        private func animateMove(token: SCNNode, from oldPos: Int, to newPos: Int, diceValue: Int, finalAnchor: SCNVector3) {
            dice.roll(to: max(1, min(6, diceValue)))

            guard oldPos > 0 else {
                // Entering the board for the first time -- there's no prior
                // square to hop from, so this is a single pop onto square 1.
                token.runAction(Coordinator.hopAction(from: token.position, to: finalAnchor, duration: 0.35, arcHeight: 0.5))
                return
            }

            runHopSequence(token: token, from: oldPos, to: newPos, finalAnchor: finalAnchor)
        }

        /// The authoritative slide cinematic, driven by the engine's
        /// `lastSlide` event. The token hops to the head/bottom square if
        /// it isn't there yet, then -- for a snake -- the head lunges
        /// (`playEat`), the bite sound fires, and the token rides the
        /// snake's body down; for a ladder the chime fires and the token
        /// climbs rung by rung.
        private func playSlideEvent(kind: String, from slideFrom: Int, token: SCNNode,
                                    previous: Int, finalAnchor: SCNVector3, diceValue: Int?) {
            dice.roll(to: max(1, min(6, diceValue ?? 1)))
            let headAnchor = tokenAnchor(square: slideFrom)
            let hopSeconds: TimeInterval
            if previous > 0, abs(slideFrom - previous) <= 8 {
                hopSeconds = runHopSequence(token: token, from: previous, to: slideFrom, finalAnchor: headAnchor)
            } else {
                // The TV missed the hops that led here (backgrounded, or a
                // rejoin landing on a live event): snap to the head/bottom
                // square so the cinematic still starts from the right place.
                token.position = headAnchor
                hopSeconds = 0.25
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + hopSeconds) { [weak self] in
                guard let self else { return }
                if kind == "snake", let snake = self.snakeNodes[slideFrom] {
                    snake.playEat()
                    SoundPlayer.shared.play(.snakeBite)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.runSlide(token: token, along: snake.pathPoints, finalAnchor: finalAnchor)
                    }
                } else if kind == "ladder", let ladder = self.ladderNodes[slideFrom] {
                    SoundPlayer.shared.play(.ladderClimb)
                    self.runClimb(token: token, ladder: ladder, finalAnchor: finalAnchor)
                } else {
                    // The event names a square this client has no model for
                    // (both come from the same engine maps, so this
                    // shouldn't happen): fall back to a plain hop.
                    token.runAction(Coordinator.hopAction(from: token.position, to: finalAnchor,
                                                         duration: 0.3, arcHeight: 0.3))
                }
            }
        }

        @discardableResult
        private func runHopSequence(token: SCNNode, from startSquare: Int, to endSquare: Int,
                                     finalAnchor: SCNVector3, perHop: TimeInterval = 0.16, arcHeight: Float = 0.3) -> TimeInterval {
            guard endSquare > startSquare else { return 0 }
            var actions: [SCNAction] = []
            var previous = token.position
            for square in (startSquare + 1)...endSquare {
                let point = square == endSquare ? finalAnchor : tokenAnchor(square: square)
                actions.append(Coordinator.hopAction(from: previous, to: point, duration: perHop, arcHeight: arcHeight))
                previous = point
            }
            token.runAction(.sequence(actions))
            return perHop * TimeInterval(endSquare - startSquare)
        }

        /// The distinct "eaten and spat out" motion: the token shrinks,
        /// rides the snake's own body centerline down to the tail, then
        /// grows back -- visually unmistakable from a normal hop.
        private func runSlide(token: SCNNode, along bodyPoints: [SCNVector3], finalAnchor: SCNVector3) {
            guard bodyPoints.count > 1 else {
                token.runAction(Coordinator.hopAction(from: token.position, to: finalAnchor, duration: 0.3, arcHeight: 0.15))
                return
            }
            let hoverAboveBody: Float = 0.12
            var waypoints = bodyPoints.map { SCNVector3($0.x, $0.y + hoverAboveBody, $0.z) }
            waypoints[waypoints.count - 1] = finalAnchor

            var actions: [SCNAction] = [SCNAction.scale(to: 0.45, duration: 0.18)]
            var previous = token.position
            for point in waypoints {
                actions.append(Coordinator.slideAction(from: previous, to: point, duration: 0.12))
                previous = point
            }
            actions.append(SCNAction.scale(to: 1.0, duration: 0.25))
            token.runAction(.sequence(actions))
        }

        /// A handful of taller, slower hops straight up the ladder's own
        /// line -- distinct from a normal hop's flatter, faster arc.
        private func runClimb(token: SCNNode, ladder: LadderNode, finalAnchor: SCNVector3) {
            let steps = 5
            var actions: [SCNAction] = []
            var previous = token.position
            for i in 1...steps {
                let t = Float(i) / Float(steps)
                let point: SCNVector3
                if i == steps {
                    point = finalAnchor
                } else {
                    point = SCNVector3(
                        ladder.bottomWorldPosition.x + (ladder.topWorldPosition.x - ladder.bottomWorldPosition.x) * t,
                        boardTopY + tokenHoverHeight,
                        ladder.bottomWorldPosition.z + (ladder.topWorldPosition.z - ladder.bottomWorldPosition.z) * t
                    )
                }
                actions.append(Coordinator.hopAction(from: previous, to: point, duration: 0.2, arcHeight: 0.2))
                previous = point
            }
            token.runAction(.sequence(actions))
        }

        // MARK: - Geometry helpers

        private func squareToPoint(_ n: Int) -> SCNVector3 {
            let (row, col) = Coordinator.squareRowCol(n)
            let x = (Float(col) - 4.5) * cellSize
            let z = (4.5 - Float(row)) * cellSize
            return SCNVector3(x, boardTopY, z)
        }

        private func stagingPoint(index: Int) -> SCNVector3 {
            SCNVector3(-(boardExtent / 2 + 1.1), boardTopY, 3.6 - Float(index) * 0.75)
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

        private static func winnerShot() -> CameraShot {
            CameraShot(position: SCNVector3(0, 10.5, 11.0), lookAt: SCNVector3(0, 0.2, 0),
                       fieldOfView: 55, focusDistance: 12)
        }

        /// The numbered 10x10 grid, drawn once into a texture (rather than
        /// as 100 individual `SCNText` nodes) and applied to the board
        /// slab's top face -- cheap, and guarantees every number is
        /// legible at TV distance regardless of camera angle.
        ///
        /// Numbers are big, centered, and full-contrast -- black on the
        /// light checker tiles, white on the dark snake-head/ladder-bottom
        /// tiles -- because the number is the tile's identity at TV
        /// distance.
        private static func boardTexture(snakes: [Int: Int], ladders: [Int: Int]) -> UIImage {
            let cells = 10
            let cellPx: CGFloat = 96
            let size = CGSize(width: cellPx * CGFloat(cells), height: cellPx * CGFloat(cells))
            let snakeHeads = Set(snakes.keys)
            let ladderBottoms = Set(ladders.keys)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                for n in 1...100 {
                    let (row, col) = Coordinator.squareRowCol(n)
                    let rect = CGRect(x: CGFloat(col) * cellPx, y: CGFloat(cells - 1 - row) * cellPx,
                                       width: cellPx, height: cellPx)
                    let isSpecial = snakeHeads.contains(n) || ladderBottoms.contains(n)
                    let base: UIColor
                    if snakeHeads.contains(n) {
                        base = UIColor(red: 0.55, green: 0.10, blue: 0.10, alpha: 1)
                    } else if ladderBottoms.contains(n) {
                        base = UIColor(red: 0.10, green: 0.42, blue: 0.20, alpha: 1)
                    } else {
                        base = (row + col).isMultiple(of: 2) ? UIColor(white: 0.90, alpha: 1) : UIColor(white: 0.80, alpha: 1)
                    }
                    base.setFill()
                    UIBezierPath(rect: rect).fill()
                    UIColor(white: 0, alpha: 0.18).setStroke()
                    UIBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).stroke()

                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = .center
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 44),
                        .foregroundColor: isSpecial ? UIColor.white : UIColor.black,
                        .paragraphStyle: paragraph,
                    ]
                    // Vertically centered: 44pt bold runs ~52pt tall.
                    let textRect = rect.insetBy(dx: 4, dy: (cellPx - 52) / 2)
                    ("\(n)" as NSString).draw(in: textRect, withAttributes: attrs)
                }
            }
        }
    }
}

// MARK: - Snakes

/// A single serpentine snake, built from chained capsule segments along a
/// gently wiggling path from its head square to its tail square -- the
/// "safest bet" construction the task called for: primitive geometry
/// chained with small per-segment offsets, the same technique
/// `PokerDealerNode` uses for every limb, rather than `SCNShape`/a custom
/// bezier-path geometry.
@MainActor
private final class SnakeNode {
    let rootNode = SCNNode()
    /// The body centerline from head (index 0) to tail (last index), at
    /// board-surface height -- exposed so the token can be animated
    /// sliding down it after being "eaten".
    let pathPoints: [SCNVector3]

    private let headNode: SCNNode

    init(headSquare: Int, tailSquare: Int, squareToPoint: (Int) -> SCNVector3, color: UIColor, bandColor: UIColor) {
        let head3D = squareToPoint(headSquare)
        let tail3D = squareToPoint(tailSquare)

        let segments = 10
        let dx = tail3D.x - head3D.x
        let dz = tail3D.z - head3D.z
        let length = sqrt(dx * dx + dz * dz)
        let perp: SCNVector3 = length > 0.0001
            ? SCNVector3(-dz / length, 0, dx / length)
            : SCNVector3(1, 0, 0)

        var points: [SCNVector3] = []
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let wiggle = sin(t * Float.pi * 2.4) * 0.38
            points.append(SCNVector3(
                head3D.x + dx * t + perp.x * wiggle,
                head3D.y + 0.10,
                head3D.z + dz * t + perp.z * wiggle
            ))
        }
        pathPoints = points

        let bodyMaterial = SCNMaterial()
        bodyMaterial.lightingModel = .physicallyBased
        bodyMaterial.diffuse.contents = color
        bodyMaterial.roughness.contents = 0.45
        let bandMaterial = SCNMaterial()
        bandMaterial.lightingModel = .physicallyBased
        bandMaterial.diffuse.contents = bandColor
        bandMaterial.roughness.contents = 0.45

        // Thick, banded body -- the old 0.09-radius tube read as a thin
        // line next to the ladders; alternating bands make it read as a
        // snake from across the room.
        for i in 0..<(points.count - 1) {
            let material = i.isMultiple(of: 2) ? bodyMaterial : bandMaterial
            let segment = SnakeNode.capsuleSegment(from: points[i], to: points[i + 1], radius: 0.17, material: material)
            rootNode.addChildNode(segment)
        }

        let head = SCNNode(geometry: SCNSphere(radius: 0.27))
        head.geometry?.materials = [bodyMaterial]
        head.position = points[0]
        rootNode.addChildNode(head)
        headNode = head

        let jawMaterial = SCNMaterial()
        jawMaterial.lightingModel = .physicallyBased
        jawMaterial.diffuse.contents = UIColor(red: 0.55, green: 0.08, blue: 0.10, alpha: 1)
        let jaw = SCNNode(geometry: SCNCone(topRadius: 0.03, bottomRadius: 0.16, height: 0.22))
        jaw.geometry?.materials = [jawMaterial]
        jaw.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        jaw.position = SCNVector3(0, -0.05, 0.16)
        head.addChildNode(jaw)

        let eyeMaterial = SCNMaterial()
        eyeMaterial.diffuse.contents = UIColor.yellow
        for xSign: Float in [-1, 1] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.045))
            eye.geometry?.materials = [eyeMaterial]
            eye.position = SCNVector3(xSign * 0.13, 0.10, 0.14)
            head.addChildNode(eye)
        }

        startIdle()
    }

    private static func capsuleSegment(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = max(sqrt(dx * dx + dy * dy + dz * dz), 0.02)
        let capsule = SCNCapsule(capRadius: radius, height: CGFloat(length))
        capsule.materials = [material]
        let node = SCNNode(geometry: capsule)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        SnakeLadderGeometry.alignYAxis(of: node, to: SCNVector3(dx, dy, dz))
        return node
    }

    /// Always-running idle loop -- subtle breathing plus a slow head sway,
    /// the "3 snakes resting with some animation" the user asked for.
    /// Runs on nodes `playEat()` never touches, so neither fights the
    /// other, mirroring `PokerDealerNode`'s idle/gesture split.
    private func startIdle() {
        let breatheUp = SCNAction.scale(by: 1.05, duration: 1.6)
        breatheUp.timingMode = .easeInEaseOut
        rootNode.runAction(.repeatForever(.sequence([breatheUp, breatheUp.reversed()])), forKey: "idleBreathe")

        let swayOut = SCNAction.rotate(by: 0.12, around: SCNVector3(0, 1, 0), duration: 1.9)
        swayOut.timingMode = .easeInEaseOut
        headNode.runAction(.repeatForever(.sequence([swayOut, swayOut.reversed()])), forKey: "idleSway")
    }

    /// A one-shot lunge-and-gulp at the head when a token lands on it --
    /// the "effect of eating" the user asked for, distinct from both the
    /// idle loop above and the normal hop-to-hop token movement.
    func playEat() {
        let lunge = SCNAction.scale(by: 1.35, duration: 0.16)
        lunge.timingMode = .easeOut
        let tilt = SCNAction.rotate(by: -0.5, around: SCNVector3(1, 0, 0), duration: 0.16)
        tilt.timingMode = .easeOut
        let gulp = SCNAction.sequence([
            .group([lunge, tilt]),
            .wait(duration: 0.1),
            .group([lunge.reversed(), tilt.reversed()]),
        ])
        headNode.removeAction(forKey: "gesture")
        headNode.runAction(gulp, forKey: "gesture")
    }
}

// MARK: - Ladders

/// Two rails + evenly spaced rungs, laid diagonally between a ladder's
/// bottom and top squares -- straight boxes oriented with
/// `SnakeLadderGeometry`, since a ladder (unlike a snake) is a straight
/// climb rather than a curve.
@MainActor
private final class LadderNode {
    let rootNode = SCNNode()
    let bottomWorldPosition: SCNVector3
    let topWorldPosition: SCNVector3

    init(bottomSquare: Int, topSquare: Int, squareToPoint: (Int) -> SCNVector3) {
        let a = squareToPoint(bottomSquare)
        let b = squareToPoint(topSquare)
        bottomWorldPosition = SCNVector3(a.x, a.y + 0.10, a.z)
        topWorldPosition = SCNVector3(b.x, b.y + 0.10, b.z)

        let dx = topWorldPosition.x - bottomWorldPosition.x
        let dz = topWorldPosition.z - bottomWorldPosition.z
        let length = sqrt(dx * dx + dz * dz)
        let perpLength = length > 0.0001 ? length : 1
        let perp = SCNVector3(-dz / perpLength, 0, dx / perpLength)
        let railOffset: Float = 0.24

        // Bright gold and straight-edged -- the visual opposite of the
        // thick, winding, banded snakes, so the two never read as the same
        // kind of thing at a glance.
        let railMaterial = SCNMaterial()
        railMaterial.lightingModel = .physicallyBased
        railMaterial.diffuse.contents = UIColor(red: 0.98, green: 0.72, blue: 0.16, alpha: 1)
        railMaterial.metalness.contents = 0.35
        railMaterial.roughness.contents = 0.4

        for sign: Float in [-1, 1] {
            let railA = SCNVector3(bottomWorldPosition.x + perp.x * railOffset * sign, bottomWorldPosition.y,
                                    bottomWorldPosition.z + perp.z * railOffset * sign)
            let railB = SCNVector3(topWorldPosition.x + perp.x * railOffset * sign, topWorldPosition.y,
                                    topWorldPosition.z + perp.z * railOffset * sign)
            rootNode.addChildNode(LadderNode.beam(from: railA, to: railB, thickness: 0.10, material: railMaterial))
        }

        let rungCount = max(4, Int(length / 0.55))
        for i in 0...rungCount {
            let t = Float(i) / Float(rungCount)
            let cx = bottomWorldPosition.x + dx * t
            let cy = bottomWorldPosition.y + (topWorldPosition.y - bottomWorldPosition.y) * t
            let cz = bottomWorldPosition.z + dz * t
            let rungA = SCNVector3(cx - perp.x * railOffset, cy, cz - perp.z * railOffset)
            let rungB = SCNVector3(cx + perp.x * railOffset, cy, cz + perp.z * railOffset)
            rootNode.addChildNode(LadderNode.beam(from: rungA, to: rungB, thickness: 0.06, material: railMaterial))
        }
    }

    private static func beam(from a: SCNVector3, to b: SCNVector3, thickness: CGFloat, material: SCNMaterial) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = max(sqrt(dx * dx + dy * dy + dz * dz), 0.02)
        let box = SCNBox(width: thickness, height: CGFloat(length), length: thickness, chamferRadius: 0)
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
        SnakeLadderGeometry.alignYAxis(of: node, to: SCNVector3(dx, dy, dz))
        return node
    }
}

/// Shared vector math for orienting a primitive (capsule/box) so its local
/// +Y axis points along an arbitrary 3D direction -- the standard
/// "rotate one vector onto another" construction (axis = cross product,
/// angle = arccos of the dot product). Both `SnakeNode`'s body segments and
/// `LadderNode`'s rails/rungs use this so neither needs `SCNShape` or a
/// custom bezier-path geometry to lay a primitive between two arbitrary
/// points.
private enum SnakeLadderGeometry {
    static func alignYAxis(of node: SCNNode, to direction: SCNVector3) {
        let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        guard length > 0.0001 else { return }
        let to = SCNVector3(direction.x / length, direction.y / length, direction.z / length)
        let from = SCNVector3(0, 1, 0)
        let dot = max(-1, min(1, from.x * to.x + from.y * to.y + from.z * to.z))
        if dot > 0.9999 { return }
        if dot < -0.9999 {
            node.eulerAngles = SCNVector3(Float.pi, 0, 0)
            return
        }
        let axis = SCNVector3(
            from.y * to.z - from.z * to.y,
            from.z * to.x - from.x * to.z,
            from.x * to.y - from.y * to.x
        )
        let axisLength = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
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
        cubeNode.removeAction(forKey: "roll")
        let spinDuration: TimeInterval = 0.85
        let spin = SCNAction.rotateBy(x: CGFloat.pi * 5, y: CGFloat.pi * 3, z: CGFloat.pi * 2, duration: spinDuration)
        spin.timingMode = .easeOut
        cubeNode.runAction(spin, forKey: "roll")

        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) { [weak self] in
            guard let self else { return }
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
            for pip in DiceNode.pipPositions(for: value) {
                let center = CGPoint(x: pip.0 * size.width, y: pip.1 * size.height)
                UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2)).fill()
            }
        }
    }

    private static func pipPositions(for value: Int) -> [(CGFloat, CGFloat)] {
        switch value {
        case 1: return [(0.5, 0.5)]
        case 2: return [(0.28, 0.28), (0.72, 0.72)]
        case 3: return [(0.28, 0.28), (0.5, 0.5), (0.72, 0.72)]
        case 4: return [(0.28, 0.28), (0.72, 0.28), (0.28, 0.72), (0.72, 0.72)]
        case 5: return [(0.28, 0.28), (0.72, 0.28), (0.5, 0.5), (0.28, 0.72), (0.72, 0.72)]
        case 6: return [(0.28, 0.22), (0.72, 0.22), (0.28, 0.5), (0.72, 0.5), (0.28, 0.78), (0.72, 0.78)]
        default: return []
        }
    }
}
