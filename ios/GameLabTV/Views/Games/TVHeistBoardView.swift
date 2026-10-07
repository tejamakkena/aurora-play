import SwiftUI
import SceneKit

// MARK: - Heist — TV Board
//
// GAME RULES:
//   • 3–6 players. One is secretly the Guard, rest are Thieves.
//   • TV shows the full vault floor plan (5×7 grid).
//   • Guard's phone shows camera positions + coverage arcs (private).
//   • Thieves' phones show only their own position (private).
//   • Each round: Guard sets cameras (phone), Thieves move 1 tile (phone).
//   • If a Thief lands on a camera-covered tile → caught, eliminated.
//   • Thieves must reach the Vault tile (center) and escape to EXIT tile.
//   • Guard wins if all Thieves caught. Thieves win if any escapes.
//
// PRESENTATION: the vault floor is a real top-down 3D SceneKit scene
// (`HeistCinematicBoardSceneView` below) with a small animated character per
// thief that walks tile-to-tile instead of teleporting. Every piece of game
// state a player actually needs to read -- round, phase, timer, the player
// list, caught/escaped status -- stays ordinary legible SwiftUI text drawn
// on top of it in `headerBar`/`playerSidebar`; the 3D scene is atmosphere,
// never the source of truth for any number on screen.

struct TVHeistBoardView: View {
    let room: Room
    @StateObject private var vm = HeistBoardViewModel()

    var body: some View {
        HStack(spacing: 0) {
            // Main board — 5/7 width
            ZStack {
                TVTheme.bg.ignoresSafeArea()

                HeistCinematicBoardSceneView(state: vm.state)
                    .ignoresSafeArea()

                // Subtle top gradient so the header text stays readable over
                // whatever is directly behind it in the live 3D scene.
                VStack {
                    LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 180)
                    Spacer()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 24) {
                    headerBar
                    Spacer()
                }
                .padding(48)
            }
            .frame(maxWidth: .infinity)

            // Right sidebar — player status
            playerSidebar
                .frame(width: 320)
                .background(Color.white.opacity(0.04))
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heist")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                Text("Round \(vm.state.round) of \(HeistConstants.maxRounds)")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Phase indicator
            PhaseTag(phase: vm.state.phase)

            Spacer()

            // Countdown timer ring
            TimerRing(
                secondsLeft: vm.state.secondsLeft,
                total: HeistConstants.secondsPerPhase
            )
        }
    }

    // MARK: - Sidebar

    private var playerSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Players")
                .font(.headline)
                .foregroundColor(.white.opacity(0.5))
                .padding(24)

            Divider().background(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(vm.state.playerStatuses) { status in
                        HeistPlayerRow(status: status)
                        Divider().background(Color.white.opacity(0.06))
                    }
                }
            }

            Spacer()

            if let winner = vm.state.winner {
                WinnerBanner(winner: winner)
                    .padding(24)
            }
        }
    }
}

// MARK: - Supporting views

private struct PhaseTag: View {
    let phase: HeistPhase

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(phase.color).frame(width: 10, height: 10)
            Text(phase.label)
                .font(.headline)
                .foregroundColor(phase.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(phase.color.opacity(0.15)))
    }
}

// TimerRing defined in TVClassicGameBoards.swift

private struct HeistPlayerRow: View {
    let status: HeistPlayerStatus

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(status.role == .guard ? TVTheme.red.opacity(0.3) : status.color.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(status.role == .guard ? "GUARD" : "THIEF").font(.caption.bold())
                        .font(.system(size: 18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(status.name)
                    .font(.body)
                    .foregroundColor(status.isCaught ? .white.opacity(0.3) : .white)
                Text(status.role == .guard ? "Guard" : status.isCaught ? "Caught" : "Thief")
                    .font(.caption)
                    .foregroundColor(status.role == .guard ? TVTheme.red.opacity(0.7) : .white.opacity(0.4))
            }

            Spacer()

            if status.hasEscaped {
                Text("ESCAPED").font(.caption2.bold()).foregroundColor(TVTheme.green)
            } else if status.isCaught {
                Image(systemName: "xmark.circle.fill").foregroundColor(TVTheme.red.opacity(0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .opacity(status.isCaught ? 0.5 : 1)
    }
}

private struct WinnerBanner: View {
    let winner: HeistWinner

    var body: some View {
        VStack(spacing: 8) {
            Text(winner == .guard ? "Guard Wins!" : "Thieves Win!")
                .font(.title3.bold())
                .foregroundColor(winner == .guard ? TVTheme.red : TVTheme.green)
            Text(winner == .guard ? "All thieves caught." : "A thief escaped!")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: ShellTheme.buttonRadius)
                .fill(winner == .guard ? TVTheme.red.opacity(0.15) : TVTheme.green.opacity(0.15))
        )
    }
}

// MARK: - ViewModel

@MainActor
final class HeistBoardViewModel: ObservableObject {
    @Published var state = HeistBoardState()
    private let socket = GameSocketManager.shared

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (response: GameStateResponse) in
            guard response.roomCode == roomCode else { return }
            self?.state.update(from: response.boardState)
        }
    }
}

// MARK: - State

struct HeistBoardState {
    var round = 1
    var phase: HeistPhase = .guardSets
    var secondsLeft = HeistConstants.secondsPerPhase
    var grid: [[HeistTileType]] = HeistBoardState.defaultGrid()
    var cameraPositions: [GridPos] = []           // Guard-controlled this round
    var cameraArcTiles: Set<GridPos> = []          // Computed from camera angles
    var thiefPositions: [String: GridPos] = [:]    // playerID → pos (revealed on TV)
    var playerStatuses: [HeistPlayerStatus] = []
    var winner: HeistWinner? = nil

    // Build the grid only once (layout is static)
    static func defaultGrid() -> [[HeistTileType]] {
        let cols = HeistConstants.cols
        let rows = HeistConstants.rows
        var g = Array(repeating: Array(repeating: HeistTileType.empty, count: cols), count: rows)

        // Walls along border
        for c in 0..<cols { g[0][c] = .wall; g[rows-1][c] = .wall }
        for r in 0..<rows { g[r][0] = .wall; g[r][cols-1] = .wall }

        // Inner wall obstacles
        let walls: [GridPos] = [
            .init(col:2,row:1), .init(col:2,row:2), .init(col:2,row:3),
            .init(col:4,row:3), .init(col:4,row:4), .init(col:4,row:5),
            .init(col:2,row:5), .init(col:2,row:6)
        ]
        for w in walls { g[w.row][w.col] = .wall }

        // Camera stands (Guard can use these)
        let cameras: [GridPos] = [
            .init(col:1,row:1), .init(col:5,row:1),
            .init(col:1,row:5), .init(col:5,row:5)
        ]
        for c in cameras { g[c.row][c.col] = .camera }

        // Vault in centre
        g[HeistConstants.rows/2][HeistConstants.cols/2] = .vault

        // Exits
        g[3][0] = .exit
        g[3][cols-1] = .exit

        return g
    }

    func tileType(at pos: GridPos) -> HeistTileType {
        guard pos.row >= 0, pos.row < grid.count,
              pos.col >= 0, pos.col < grid[0].count else { return .wall }
        return grid[pos.row][pos.col]
    }

    func cameraArcCovers(_ pos: GridPos) -> Bool { cameraArcTiles.contains(pos) }

    func thieves(at pos: GridPos) -> [HeistThiefStatus] {
        playerStatuses.filter {
            $0.role == .thief && !$0.isCaught && thiefPositions[$0.id] == pos
        }.map { HeistThiefStatus(id: $0.id, color: $0.color) }
    }

    func isGuardRevealedAt(_ pos: GridPos) -> Bool { cameraPositions.contains(pos) }

    mutating func update(from data: [String: AnyCodable]) {
        if let r = data["round"]?.value as? Int       { round = r }
        if let s = data["secondsLeft"]?.value as? Int { secondsLeft = s }
        if let p = data["phase"]?.value as? String    { phase = HeistPhase(rawValue: p) ?? .guardSets }

        // Camera positions the Guard activated this round
        if let cams = data["cameraPositions"]?.value as? [[String: Any]] {
            cameraPositions = cams.compactMap { dict -> GridPos? in
                guard let c = dict["col"] as? Int, let r = dict["row"] as? Int else { return nil }
                return GridPos(col: c, row: r)
            }
        }

        // Tiles covered by camera arcs (computed server-side)
        if let arcs = data["cameraArcTiles"]?.value as? [[String: Any]] {
            cameraArcTiles = Set(arcs.compactMap { dict -> GridPos? in
                guard let c = dict["col"] as? Int, let r = dict["row"] as? Int else { return nil }
                return GridPos(col: c, row: r)
            })
        }

        // Each thief's position (playerID → {col, row})
        if let positions = data["thiefPositions"]?.value as? [String: [String: Any]] {
            thiefPositions = positions.compactMapValues { dict -> GridPos? in
                guard let c = dict["col"] as? Int, let r = dict["row"] as? Int else { return nil }
                return GridPos(col: c, row: r)
            }
        }

        // Player status array
        if let statuses = data["playerStatuses"]?.value as? [[String: Any]] {
            let palette: [Color] = [TVTheme.cyan, TVTheme.yellow, TVTheme.green, TVTheme.orange, TVTheme.purple, TVTheme.pink]
            playerStatuses = statuses.enumerated().compactMap { idx, dict -> HeistPlayerStatus? in
                guard let id   = dict["id"]   as? String,
                      let name = dict["name"] as? String,
                      let rs   = dict["role"] as? String else { return nil }
                return HeistPlayerStatus(
                    id: id, name: name,
                    role: rs == "guard" ? .guard : .thief,
                    color: palette[idx % palette.count],
                    isCaught: dict["isCaught"] as? Bool ?? false,
                    hasEscaped: dict["hasEscaped"] as? Bool ?? false
                )
            }
        }

        // Game over
        if let w = data["winner"]?.value as? String {
            winner = w == "guard" ? .guard_ : .thieves
        }
    }
}

// MARK: - Supporting types
//
// GridPos, HeistPhase, and HeistRole moved to Shared/Models/HeistTypes.swift —
// HeistControllerView (a different Xcode target) needs them too.

enum HeistTileType { case empty, wall, vault, exit, camera }

enum HeistWinner { case guard_, thieves }
// disambiguate keyword
extension HeistWinner {
    static let `guard` = HeistWinner.guard_
}

struct HeistPlayerStatus: Identifiable {
    let id: String
    let name: String
    let role: HeistRole
    let color: Color
    var isCaught: Bool
    var hasEscaped: Bool
}

struct HeistThiefStatus: Identifiable {
    let id: String
    let color: Color
}

enum HeistConstants {
    static let cols = 7
    static let rows = 7
    static let maxRounds = 8
    static let secondsPerPhase = 20
}

// MARK: - 3D Board Scene
//
// A real top-down SceneKit presentation of the vault floor plan, standing in
// for what used to be a flat grid of `HeistTile` SwiftUI squares. Built
// self-contained in this file (rather than routed through the generic
// `CinematicBoardSceneView` wrapper) since a static top-down shot doesn't
// need that wrapper's `TablePhase` shot vocabulary -- it reuses
// `CinematicCameraRig` and `CinematicLighting` verbatim, the same way
// `PokerCinematicBoardSceneView` does.
//
// Layout convention: `GridPos(col, row)` maps to world space with the board
// centered on the origin -- `worldX(col)`/`worldZ(row)` below -- and every
// tile/character sits in the XZ plane so the top-down camera reads the whole
// floor plan at a glance.

/// Shared primitive-geometry material helper -- both the room dressing
/// (`HeistCinematicBoardSceneView.Coordinator`) and the thief character
/// (`ThiefCharacterNode`) need the same physically-based material recipe
/// `PokerDealerNode` uses, so it's a single free function rather than a
/// method duplicated on two types.
private func heistMaterial(color: UIColor, roughness: CGFloat, metalness: CGFloat = 0, emission: UIColor? = nil) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = color
    m.roughness.contents = roughness
    m.metalness.contents = metalness
    if let emission {
        m.emission.contents = emission
    }
    return m
}

struct HeistCinematicBoardSceneView: UIViewRepresentable {
    var state: HeistBoardState

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
        private let boardRadius: Float

        private let tileSize: Float = 1.0
        private let cols = HeistConstants.cols
        private let rows = HeistConstants.rows

        /// Coverage-glow floor overlays, keyed by tile -- built once for
        /// every non-wall tile, hidden (`opacity == 0`) until `apply` turns
        /// on whichever ones are in this round's `cameraArcTiles`.
        private var arcGlowNodes: [GridPos: SCNNode] = [:]
        /// Each camera stand's lens light -- dim while dormant, driven up
        /// when the Guard has actually activated that stand this round.
        private var cameraLights: [GridPos: SCNLight] = [:]
        private var characters: [String: ThiefCharacterNode] = [:]
        private var lastPositions: [String: GridPos] = [:]
        private var lastPhase: HeistPhase?

        init() {
            // `radius` is a local copy specifically so the two static-method
            // calls right below (`Coordinator.shot`/building the rig) never
            // need to read a stored property before `self` is fully formed
            // -- the same reason `PokerCinematicBoardSceneView.Coordinator`
            // copies `tableRadius` to a local `radius` before its own
            // closure-based setup.
            let radius = Float(max(HeistConstants.cols, HeistConstants.rows))
            boardRadius = radius

            let initialShot = Coordinator.shot(forPhase: .guardSets, boardRadius: radius)
            cameraRig = CinematicCameraRig(initialShot: initialShot)
            lighting = CinematicLighting(tableRadius: radius * 0.6)

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)

            // Every stored property above is assigned by this point, so
            // this ordinary method call (which freely touches `self`) is
            // safe -- unlike a closure captured *during* the assignments
            // above would have been.
            buildFloorPlan()
        }

        // MARK: - Grid <-> world space

        private func worldX(_ col: Int) -> Float { (Float(col) - Float(cols - 1) / 2) * tileSize }
        private func worldZ(_ row: Int) -> Float { (Float(row) - Float(rows - 1) / 2) * tileSize }
        private func worldPosition(_ pos: GridPos, y: Float = 0) -> SCNVector3 {
            SCNVector3(worldX(pos.col), y, worldZ(pos.row))
        }

        // MARK: - Room dressing (built once -- the layout never changes)

        private func buildFloorPlan() {
            let ground = SCNNode(geometry: SCNBox(
                width: CGFloat(Float(cols) * tileSize + 1),
                height: 0.05,
                length: CGFloat(Float(rows) * tileSize + 1),
                chamferRadius: 0.05
            ))
            ground.geometry?.materials = [heistMaterial(color: UIColor(white: 0.015, alpha: 1), roughness: 0.9)]
            ground.position = SCNVector3(0, -0.06, 0)
            scene.rootNode.addChildNode(ground)

            let grid = HeistBoardState.defaultGrid()
            for row in 0..<rows {
                for col in 0..<cols {
                    buildTile(pos: GridPos(col: col, row: row), type: grid[row][col])
                }
            }
        }

        private func buildTile(pos: GridPos, type: HeistTileType) {
            let world = worldPosition(pos)

            if type == .wall {
                let wall = SCNNode(geometry: SCNBox(
                    width: CGFloat(tileSize * 0.94), height: 0.6, length: CGFloat(tileSize * 0.94), chamferRadius: 0.03
                ))
                wall.geometry?.materials = [heistMaterial(color: UIColor(white: 0.06, alpha: 1), roughness: 0.8)]
                wall.position = SCNVector3(world.x, 0.3, world.z)
                scene.rootNode.addChildNode(wall)
                return
            }

            let floorColor: UIColor
            switch type {
            case .vault:  floorColor = UIColor(red: 0.20, green: 0.14, blue: 0.02, alpha: 1)
            case .exit:   floorColor = UIColor(red: 0.02, green: 0.16, blue: 0.05, alpha: 1)
            case .camera: floorColor = UIColor(red: 0.16, green: 0.02, blue: 0.04, alpha: 1)
            default:      floorColor = UIColor(red: 0.07, green: 0.08, blue: 0.13, alpha: 1)
            }
            let floor = SCNNode(geometry: SCNBox(
                width: CGFloat(tileSize * 0.94), height: 0.08, length: CGFloat(tileSize * 0.94), chamferRadius: 0.04
            ))
            floor.geometry?.materials = [heistMaterial(color: floorColor, roughness: 0.75)]
            floor.position = SCNVector3(world.x, 0.04, world.z)
            scene.rootNode.addChildNode(floor)

            // Coverage-glow overlay -- a thin emissive plane just above the
            // floor, hidden until `apply` reveals it for a round where this
            // tile is under camera coverage. Rotated flat (facing +Y) the
            // same way an `SCNPlane` always needs to be to lie on a floor:
            // its default normal is +Z, and rotating -90° about X carries
            // that normal to +Y.
            let glowMaterial = heistMaterial(color: UIColor.red, roughness: 1.0, emission: UIColor.red)
            let glow = SCNNode(geometry: SCNPlane(width: CGFloat(tileSize * 0.9), height: CGFloat(tileSize * 0.9)))
            glow.geometry?.materials = [glowMaterial]
            glow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            glow.position = SCNVector3(world.x, 0.09, world.z)
            glow.opacity = 0
            scene.rootNode.addChildNode(glow)
            arcGlowNodes[pos] = glow

            switch type {
            case .vault:
                let vault = SCNNode(geometry: SCNCylinder(radius: CGFloat(tileSize * 0.32), height: 0.3))
                vault.geometry?.materials = [heistMaterial(
                    color: UIColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1),
                    roughness: 0.3, metalness: 0.6,
                    emission: UIColor(red: 0.5, green: 0.38, blue: 0.04, alpha: 1)
                )]
                vault.position = SCNVector3(world.x, 0.2, world.z)
                scene.rootNode.addChildNode(vault)

                let pulseUp = SCNAction.scale(by: 1.06, duration: 1.5)
                pulseUp.timingMode = .easeInEaseOut
                vault.runAction(.repeatForever(.sequence([pulseUp, pulseUp.reversed()])), forKey: "vaultPulse")

            case .exit:
                let ring = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(tileSize * 0.32), pipeRadius: 0.04))
                ring.geometry?.materials = [heistMaterial(
                    color: UIColor(red: 0.1, green: 0.9, blue: 0.3, alpha: 1),
                    roughness: 0.4,
                    emission: UIColor(red: 0.05, green: 0.55, blue: 0.15, alpha: 1)
                )]
                ring.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                ring.position = SCNVector3(world.x, 0.1, world.z)
                scene.rootNode.addChildNode(ring)

            case .camera:
                let turret = Coordinator.buildCameraTurret()
                turret.node.position = SCNVector3(world.x, 0, world.z)
                scene.rootNode.addChildNode(turret.node)
                cameraLights[pos] = turret.light

            default:
                break
            }
        }

        /// A small security-camera turret -- base, dome, and a lens light
        /// that `apply` drives from a dim dormant glow up to a bright red
        /// alert when the Guard actually activates that stand for the
        /// round, so guard presence reads clearly on the board itself.
        private static func buildCameraTurret() -> (node: SCNNode, light: SCNLight) {
            let root = SCNNode()

            let base = SCNNode(geometry: SCNCylinder(radius: 0.16, height: 0.14))
            base.geometry?.materials = [heistMaterial(color: UIColor(white: 0.22, alpha: 1), roughness: 0.5, metalness: 0.4)]
            base.position = SCNVector3(0, 0.07, 0)
            root.addChildNode(base)

            let dome = SCNNode(geometry: SCNSphere(radius: 0.14))
            dome.geometry?.materials = [heistMaterial(
                color: UIColor(white: 0.55, alpha: 1), roughness: 0.15, metalness: 0.3,
                emission: UIColor(red: 0.35, green: 0.04, blue: 0.05, alpha: 1)
            )]
            dome.position = SCNVector3(0, 0.2, 0)
            root.addChildNode(dome)

            let lens = SCNNode(geometry: SCNSphere(radius: 0.045))
            lens.geometry?.materials = [heistMaterial(color: UIColor.black, roughness: 0.1, emission: UIColor.red)]
            lens.position = SCNVector3(0, 0.13, 0.1)
            root.addChildNode(lens)

            let light = SCNLight()
            light.type = .omni
            light.color = UIColor.red
            light.intensity = 30
            let lightNode = SCNNode()
            lightNode.light = light
            lightNode.position = SCNVector3(0, 0.4, 0)
            root.addChildNode(lightNode)

            return (root, light)
        }

        // MARK: - Live state -> scene

        func apply(_ state: HeistBoardState, animated: Bool) {
            if state.phase != lastPhase {
                lastPhase = state.phase
                let duration: TimeInterval = animated ? 1.2 : 0
                cameraRig.transition(to: Coordinator.shot(forPhase: state.phase, boardRadius: boardRadius), duration: duration)
                lighting.apply(Coordinator.mood(for: state.phase), duration: duration)
            }

            updateCameraGlow(state: state, animated: animated)
            updateCharacters(state: state, animated: animated)
        }

        private func updateCameraGlow(state: HeistBoardState, animated: Bool) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.6 : 0
            for (pos, light) in cameraLights {
                light.intensity = state.isGuardRevealedAt(pos) ? 850 : 30
            }
            for (pos, glow) in arcGlowNodes {
                glow.opacity = state.cameraArcCovers(pos) ? 0.55 : 0
            }
            SCNTransaction.commit()
        }

        /// Walks every currently-live thief's character to its latest
        /// tile, spawning a character the first time a thief appears and
        /// fading one out the moment it drops out of `thiefPositions`
        /// (caught, or escaped) rather than yanking it off the board.
        private func updateCharacters(state: HeistBoardState, animated: Bool) {
            let statusByID = Dictionary(uniqueKeysWithValues: state.playerStatuses.map { ($0.id, $0) })

            for (id, pos) in state.thiefPositions {
                let target = worldPosition(pos)
                if let character = characters[id] {
                    if lastPositions[id] != pos {
                        lastPositions[id] = pos
                        if animated {
                            character.walk(to: target, duration: 0.6)
                        } else {
                            character.rootNode.position = target
                        }
                    }
                    character.setHidden(false, animated: animated)
                } else {
                    let color = statusByID[id].map { UIColor($0.color) } ?? UIColor.cyan
                    let character = ThiefCharacterNode(color: color)
                    character.rootNode.position = target
                    scene.rootNode.addChildNode(character.rootNode)
                    characters[id] = character
                    lastPositions[id] = pos
                }
            }

            for (id, character) in characters where state.thiefPositions[id] == nil {
                character.setHidden(true, animated: animated)
            }
        }

        // MARK: - Phase -> cinematic vocabulary

        private static func shot(forPhase phase: HeistPhase, boardRadius: Float) -> CameraShot {
            switch phase {
            case .guardSets:
                // Wide establishing view -- the whole floor plan at once.
                return CameraShot(
                    position: SCNVector3(0, boardRadius * 1.35, boardRadius * 0.55),
                    lookAt: SCNVector3(0, 0, 0),
                    fieldOfView: 50,
                    focusDistance: CGFloat(boardRadius * 1.3)
                )
            case .thievesMove:
                // A touch closer -- the "action" shot while thieves move.
                return CameraShot(
                    position: SCNVector3(0, boardRadius * 1.12, boardRadius * 0.4),
                    lookAt: SCNVector3(0, 0, 0),
                    fieldOfView: 46,
                    focusDistance: CGFloat(boardRadius * 1.1)
                )
            case .reveal:
                // Push in tighter for the round's resolution.
                return CameraShot(
                    position: SCNVector3(0, boardRadius * 0.92, boardRadius * 0.28),
                    lookAt: SCNVector3(0, 0, 0),
                    fieldOfView: 40,
                    focusDistance: CGFloat(boardRadius * 0.95)
                )
            }
        }

        private static func mood(for phase: HeistPhase) -> PhaseLightingMood {
            switch phase {
            case .guardSets:   return .warm
            case .thievesMove: return .neutral
            case .reveal:      return .tense
            }
        }
    }
}

// MARK: - Thief character

/// A small, stylized "cute" thief character built entirely from primitive
/// SceneKit geometry (capsule body, spheres for head/eyes/feet, a torus for
/// a cartoon hood) -- no imported 3D model/rig, same discipline
/// `PokerDealerNode` uses. `rootNode`'s position is the *only* thing
/// `walk(to:duration:)` ever touches (a one-shot move); the idle bob and
/// glance loops below run forever on separate child nodes, so nothing ever
/// needs to pause or cancel the idle loop to animate a step.
@MainActor
private final class ThiefCharacterNode {
    let rootNode = SCNNode()
    private let facingNode: SCNNode
    private let bobNode: SCNNode
    private let headPivot: SCNNode

    init(color: UIColor) {
        let bodyMaterial = heistMaterial(color: color, roughness: 0.55)
        let trimMaterial = heistMaterial(color: UIColor.white, roughness: 0.3, emission: color)
        let eyeMaterial = heistMaterial(color: UIColor.black, roughness: 0.2)

        let facing = SCNNode()
        rootNode.addChildNode(facing)
        facingNode = facing

        let bob = SCNNode()
        bob.position = SCNVector3(0, 0.14, 0)
        facing.addChildNode(bob)
        bobNode = bob

        let body = SCNNode(geometry: SCNCapsule(capRadius: 0.14, height: 0.26))
        body.geometry?.materials = [bodyMaterial]
        body.position = SCNVector3(0, 0.15, 0)
        bob.addChildNode(body)

        // Stubby feet -- purely decorative grounding, like PokerDealerNode's
        // static legs, so only `bobNode`'s hop ever moves them.
        for xSign: Float in [-1, 1] {
            let foot = SCNNode(geometry: SCNSphere(radius: 0.07))
            foot.geometry?.materials = [trimMaterial]
            foot.position = SCNVector3(xSign * 0.09, 0.02, 0.03)
            bob.addChildNode(foot)
        }

        let head = SCNNode()
        head.position = SCNVector3(0, 0.34, 0)
        bob.addChildNode(head)
        headPivot = head

        let skull = SCNNode(geometry: SCNSphere(radius: 0.15))
        skull.geometry?.materials = [bodyMaterial]
        head.addChildNode(skull)

        // Big cute eyes, facing the +Z "front" of the character.
        for xSign: Float in [-1, 1] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.035))
            eye.geometry?.materials = [eyeMaterial]
            eye.position = SCNVector3(xSign * 0.06, 0.02, 0.13)
            head.addChildNode(eye)
        }

        // A hood-trim ring -- reads as a cartoon "thief" silhouette from
        // directly above without needing a rigged cape.
        let hood = SCNNode(geometry: SCNTorus(ringRadius: 0.15, pipeRadius: 0.025))
        hood.geometry?.materials = [trimMaterial]
        hood.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        hood.position = SCNVector3(0, 0.05, 0)
        head.addChildNode(hood)

        startIdle()
    }

    // MARK: - Idle loop (always running, never interrupted)

    private func startIdle() {
        let bobUp = SCNAction.moveBy(x: 0, y: 0.03, z: 0, duration: 0.55)
        bobUp.timingMode = .easeInEaseOut
        let bobCycle = SCNAction.sequence([bobUp, bobUp.reversed()])
        bobNode.runAction(.repeatForever(bobCycle), forKey: "idleBob")

        let glanceOut = SCNAction.rotate(by: 0.35, around: SCNVector3(0, 1, 0), duration: 1.1)
        glanceOut.timingMode = .easeInEaseOut
        let glance = SCNAction.sequence([glanceOut, .wait(duration: 0.3), glanceOut.reversed(), .wait(duration: 0.5)])
        headPivot.runAction(.repeatForever(glance), forKey: "idleGlance")
    }

    // MARK: - One-shot movement (root + facing only -- never fights the idle loop)

    /// Glides from wherever `rootNode` currently sits to `worldPosition`,
    /// turning `facingNode` to face the direction of travel along the way.
    /// Speeding up the always-running idle bob for the duration of the walk
    /// is what reads as a "footstep" bounce, rather than layering a second,
    /// competing position animation onto the same node.
    func walk(to worldPosition: SCNVector3, duration: TimeInterval) {
        let from = rootNode.position
        let dx = worldPosition.x - from.x
        let dz = worldPosition.z - from.z

        if abs(dx) > 0.001 || abs(dz) > 0.001 {
            let heading = CGFloat(atan2(dx, dz))
            let current = CGFloat(facingNode.eulerAngles.y)
            // Shortest signed turn from `current` to `heading`, normalized
            // into (-pi, +pi) -- using `SCNAction.rotate(by:around:duration:)`
            // (the exact call `PokerDealerNode`'s idle sway already proves
            // compiles) instead of an absolute rotate-to, since the delta is
            // trivial to compute by hand and this sidesteps needing to know
            // that API's exact parameter labels.
            var delta = heading - current
            while delta > CGFloat.pi { delta -= 2 * CGFloat.pi }
            while delta < -CGFloat.pi { delta += 2 * CGFloat.pi }

            facingNode.removeAction(forKey: "turn")
            let turn = SCNAction.rotate(by: delta, around: SCNVector3(0, 1, 0), duration: duration * 0.4)
            turn.timingMode = .easeOut
            facingNode.runAction(turn, forKey: "turn")
        }

        rootNode.removeAction(forKey: "walk")
        let move = SCNAction.move(to: worldPosition, duration: duration)
        move.timingMode = .easeInEaseOut

        // `speed` belongs to SCNAction, not SCNNode -- there's no such
        // property on the node itself. The already-running "idleBob"
        // action (started in startIdle()) is what needs speeding up, via
        // the action instance SCNNode.action(forKey:) hands back.
        bobNode.action(forKey: "idleBob")?.speed = 1.8
        rootNode.runAction(move, forKey: "walk") { [weak self] in
            DispatchQueue.main.async { self?.bobNode.action(forKey: "idleBob")?.speed = 1.0 }
        }
    }

    /// Fades the whole character in/out -- used when a thief first appears
    /// on the board, and when one drops out of `thiefPositions` (caught or
    /// escaped) rather than vanishing instantly.
    func setHidden(_ hidden: Bool, animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.5 : 0
        rootNode.opacity = hidden ? 0 : 1
        SCNTransaction.commit()
    }
}
