import SwiftUI

// MARK: - Shared helpers

struct PlaceholderBoardView: View {
    let game: GameID
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: game.sfSymbol).font(.system(size: 80)).foregroundColor(.white.opacity(0.7))
            Text(game.displayName).font(.largeTitle.bold()).foregroundColor(.white)
            Text("Coming soon").foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }
}

// Shared score header used by multiple board views
private struct TVScoreHeader: View {
    let players: [Player]
    let currentPlayerID: String?

    var body: some View {
        HStack(spacing: 16) {
            ForEach(players) { p in
                HStack(spacing: 8) {
                    Circle()
                        .fill(p.id == currentPlayerID ? Color.cyan : Color.white.opacity(0.15))
                        .frame(width: 12, height: 12)
                    Text(p.name).foregroundColor(p.id == currentPlayerID ? .white : .white.opacity(0.5))
                    Text("\(p.score)").font(.headline.bold()).foregroundColor(.cyan)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(p.id == currentPlayerID ? Color.cyan.opacity(0.15) : Color.white.opacity(0.05)))
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Pong Board

struct TVPongBoardView: View {
    let room: Room
    @StateObject private var vm = PongBoardViewModel()

    var body: some View {
        ZStack {
            // The arena is a real lit SceneKit scene (PongArenaSceneView):
            // glossy table, emissive paddles and ball, spark bursts on hits,
            // a goal flash and camera shake on points. Paddle and ball
            // positions come straight from the same PongState as before.
            PongArenaSceneView(state: vm.state)
                .ignoresSafeArea()

            VStack {
                LinearGradient(colors: [Color.black.opacity(0.55), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top) {
                    PongScorePanel(name: vm.state.leftPlayerName, score: vm.state.scoreLeft,
                                   color: Color(hex: "22d3ee"), alignTrailing: false)
                    Spacer()
                    TVGlowText(text: "PONG", size: 46, color: Color(hex: "a78bfa"))
                        .padding(.top, 14)
                    Spacer()
                    PongScorePanel(name: vm.state.rightPlayerName, score: vm.state.scoreRight,
                                   color: Color(hex: "f472b6"), alignTrailing: true)
                }
                .padding(.horizontal, 70)
                .padding(.top, 40)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

private struct PongScorePanel: View {
    let name: String
    let score: Int
    let color: Color
    let alignTrailing: Bool

    var body: some View {
        TVGlassCard(cornerRadius: 26, tint: color, glow: color, padding: 0) {
            HStack(spacing: 22) {
                if alignTrailing { scoreView }
                VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 4) {
                    Text("PLAYER").font(.caption.bold()).tracking(3)
                        .foregroundColor(color.opacity(0.9))
                    Text(name)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !alignTrailing { scoreView }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: 520, alignment: alignTrailing ? .trailing : .leading)
    }

    private var scoreView: some View {
        TVPopNumber(value: score, size: 64, color: color)
            .frame(minWidth: 70)
    }
}

struct PongState {
    var ballX: Double = 0.5
    var ballY: Double = 0.5
    var leftPaddlePos: Double = 0.5
    var rightPaddlePos: Double = 0.5
    var scoreLeft = 0
    var scoreRight = 0
    var leftPlayerName = "Player 1"
    var rightPlayerName = "Player 2"

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["ballX"]?.value as? Double          { ballX = v }
        if let v = data["ballY"]?.value as? Double          { ballY = v }
        if let v = data["leftPaddle"]?.value as? Double     { leftPaddlePos = v }
        if let v = data["rightPaddle"]?.value as? Double    { rightPaddlePos = v }
        if let v = data["scoreLeft"]?.value as? Int         { scoreLeft = v }
        if let v = data["scoreRight"]?.value as? Int        { scoreRight = v }
        if let v = data["leftName"]?.value as? String       { leftPlayerName = v }
        if let v = data["rightName"]?.value as? String      { rightPlayerName = v }
    }
}

@MainActor final class PongBoardViewModel: ObservableObject {
    @Published var state = PongState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Poker Board

struct TVPokerBoardView: View {
    let room: Room
    @StateObject private var vm = PokerBoardViewModel()

    var body: some View {
        ZStack {
            // The real 3D table: felt, seat markers, community-card slots,
            // and a procedurally-animated dealer, shot with the cinematic
            // camera rig. All of the actual game *state* below is rendered
            // as legible SwiftUI text over the top of it -- the 3D scene is
            // atmosphere, not the source of truth for any number on screen.
            PokerCinematicBoardSceneView(state: vm.state)
                .ignoresSafeArea()

            // Subtle top/bottom gradients so HUD text stays readable over
            // whatever is directly behind it in the live 3D scene.
            VStack {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Phase + pot
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.state.phase.uppercased()).font(.caption.bold()).tracking(3)
                            .foregroundColor(.yellow.opacity(0.85))
                        Text("Poker").font(.title2.bold()).foregroundColor(.white)
                        if vm.state.maxHands > 0 {
                            Text("Hand \(vm.state.handNumber) of \(vm.state.maxHands)")
                                .font(.headline).foregroundColor(.white.opacity(0.6))
                        }
                    }
                    Spacer()
                    if vm.state.phase == "showdown", let result = vm.state.handResult {
                        Label(result, systemImage: "crown.fill")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 28).padding(.vertical, 14)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("POT").font(.caption.bold()).tracking(2).foregroundColor(.white.opacity(0.6))
                        Text("$\(vm.state.pot)").font(.system(size: 36, weight: .bold)).foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 60).padding(.top, 40)

                // Community cards, positioned to roughly sit over the
                // physical card slots on the 3D table beneath.
                //
                // Reported directly as "too tiny for the TV screen" --
                // these were sized for a phone (70x100) despite being read
                // from a couch several feet away. Scaled up ~1.9x, with the
                // row spacing widened to match so the five wider cards
                // don't crowd together.
                VStack(spacing: 14) {
                    Text("Community Cards").font(.title3).foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 28) {
                        ForEach(0..<5, id: \.self) { idx in
                            if idx < vm.state.communityCards.count {
                                TVCardView(card: vm.state.communityCards[idx])
                            } else {
                                TVCardBack()
                            }
                        }
                    }
                }
                .padding(.top, 36)

                Spacer()

                // Every seat's chips/bet/status/turn, in a ring echoing the
                // table below -- see PokerSeatRingOverlay for why this is a
                // deliberately independent HUD layout rather than a live
                // 3D-to-screen projection of the SceneKit seat markers.
                // Height and inset scaled up alongside the bigger card/badge
                // sizing below so the ring still clears the screen edges.
                PokerSeatRingOverlay(seats: vm.state.playerSeats)
                    .frame(height: 340)
                    .padding(.bottom, 28)
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

private struct TVCardView: View {
    let card: String
    private var isRed: Bool { card.contains("♥") || card.contains("♦") }
    var body: some View {
        Text(card)
            .font(.system(size: 60, weight: .bold))
            .foregroundColor(isRed ? .red : .black)
            .frame(width: 132, height: 188)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
            .shadow(radius: 8)
    }
}

private struct TVCardBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(hex: "1a0a2e"))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.purple.opacity(0.4), lineWidth: 2))
            .frame(width: 132, height: 188)
            .overlay(Text("🂠").font(.system(size: 76)))
    }
}

struct PokerSeat: Identifiable {
    let id: String
    let name: String
    let chips: Int
    let currentBet: Int
    let status: String  // "active", "folded", "all-in", "waiting"
    let isCurrentTurn: Bool
}

struct PokerBoardState {
    var communityCards: [String] = []
    var pot = 0
    var phase = "pre-flop"
    var playerSeats: [PokerSeat] = []
    /// `PokerEngine.base_public()`'s "winner" field -- the player ID who
    /// took the pot, set the moment a hand ends (fold-out or showdown).
    /// Drives the dealer's showdown reaction gesture; nil while a hand is
    /// still in progress.
    var winnerID: String?
    var handNumber = 0
    var maxHands = 0
    /// "Asha wins $340" while the between-hands showdown pause is up.
    var handResult: String? = nil

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["handNumber"]?.value as? Int      { handNumber = v }
        if let v = data["maxHands"]?.value as? Int        { maxHands = v }
        if let last = data["lastHand"]?.value as? [String: Any],
           let names = last["winnerNames"] as? [Any] {
            let who = names.compactMap { $0 as? String }.joined(separator: " & ")
            let amount = last["amount"] as? Int ?? 0
            handResult = who.isEmpty ? nil : "\(who) wins $\(amount)"
        } else {
            handResult = nil
        }
        if let v = data["pot"]?.value as? Int             { pot = v }
        if let v = data["phase"]?.value as? String        { phase = v }
        if let v = data["communityCards"]?.value as? [String] { communityCards = v }
        if let winnerField = data["winner"]                { winnerID = winnerField.value as? String }
        if let seats = data["players"]?.value as? [[String: Any]] {
            playerSeats = seats.compactMap { d -> PokerSeat? in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return PokerSeat(id: id, name: name,
                                 chips: d["chips"] as? Int ?? 0,
                                 currentBet: d["currentBet"] as? Int ?? 0,
                                 status: d["status"] as? String ?? "waiting",
                                 isCurrentTurn: d["isCurrentTurn"] as? Bool ?? false)
            }
        }
    }
}

@MainActor final class PokerBoardViewModel: ObservableObject {
    @Published var state = PokerBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

/// Every seat's name/chips/bet/status/turn indicator, fanned along a shallow
/// bottom arc so the HUD echoes the seat ring standing on the 3D table
/// beneath it -- deliberately as an independent, fixed 2D layout rather than
/// a true 3D-to-screen projection of the SceneKit seat markers, so it stays
/// perfectly legible through every cinematic camera move instead of sliding
/// around (or off-screen) as the rig's shots change.
private struct PokerSeatRingOverlay: View {
    let seats: [PokerSeat]

    var body: some View {
        GeometryReader { geo in
            let count = max(seats.count, 1)
            ForEach(Array(seats.enumerated()), id: \.element.id) { i, seat in
                let t = count == 1 ? 0.5 : CGFloat(i) / CGFloat(count - 1)
                let angle = Double.pi * (0.12 + 0.76 * Double(t))
                // Inset widened from 90 to 150 to keep the now-larger
                // badges (below) clear of the screen edges at the same
                // arc radius.
                let x = geo.size.width / 2 - CGFloat(cos(angle)) * (geo.size.width / 2 - 150)
                let y = geo.size.height * 0.1 + CGFloat(sin(angle)) * (geo.size.height * 0.82)
                PokerSeatBadge(seat: seat)
                    .position(x: x, y: y)
            }
        }
    }
}

private struct PokerSeatBadge: View {
    let seat: PokerSeat
    var body: some View {
        VStack(spacing: 8) {
            Text(seat.name).font(.title3.bold())
                .foregroundColor(seat.isCurrentTurn ? .yellow : .white)
            Text("$\(seat.chips)").font(.headline).foregroundColor(.green)
            if seat.currentBet > 0 {
                Text("Bet: $\(seat.currentBet)").font(.subheadline).foregroundColor(.cyan)
            }
            Text(seat.status).font(.caption.bold())
                .foregroundColor(statusColor(seat.status))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18)
            .fill(seat.isCurrentTurn ? Color.yellow.opacity(0.18) : Color.black.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(seat.isCurrentTurn ? Color.yellow.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 2)))
    }
    private func statusColor(_ s: String) -> Color {
        switch s { case "active": return .white; case "folded": return .red.opacity(0.7);
                   case "all-in": return .orange; default: return .white.opacity(0.4) }
    }
}

// MARK: - Connect 4 Board

private let connect4CellSize: CGFloat = 104
private let connect4CellSpacing: CGFloat = 14

/// How long a disc takes to fall into row `row` (0 = top row, deepest rows
/// fall the furthest and therefore take the longest) -- used both to drive
/// the fall animation itself and to time the landing sound so the "clack"
/// lands exactly when the disc visually reaches the bottom of its drop.
private func connect4DropDuration(forRow row: Int) -> Double {
    0.22 + Double(row + 1) * 0.075
}

struct TVConnect4BoardView: View {
    let room: Room
    @StateObject private var vm = Connect4BoardViewModel()

    private let rows = 6, cols = 7

    var body: some View {
        VStack(spacing: 22) {
            TVScoreHeader(players: room.players, currentPlayerID: vm.state.currentPlayerID)
                .padding(.top, 40)

            Text("Connect 4").font(.largeTitle.bold()).foregroundColor(.white)

            if let winner = vm.state.winner {
                // `winner` is a player ID; show the name.
                let name = room.players.first(where: { $0.id == winner })?.name ?? "Winner"
                Text("\(name) wins!").font(.title2.bold()).foregroundColor(.yellow)
            } else {
                Text(vm.state.currentPlayerName.isEmpty ? "" : "\(vm.state.currentPlayerName)'s turn")
                    .font(.title3).foregroundColor(.white.opacity(0.6))
            }

            // Reported directly as wanting "realistic coin drop with sound
            // effects. And also the 3d stand." The grid now sits inside a
            // physical-looking cabinet/stand (Connect4StandFrame below),
            // and each newly-filled cell actually falls into place instead
            // of popping straight to its final colour -- see
            // Connect4BoardViewModel.bind for how the single new cell is
            // detected between two consecutive state pushes.
            Connect4StandFrame {
                VStack(spacing: connect4CellSpacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: connect4CellSpacing) {
                            ForEach(0..<cols, id: \.self) { col in
                                let cell = vm.state.grid[row][col]
                                let isWin = vm.state.winCells.contains("\(row),\(col)")
                                let dropToken: Int =
                                    (vm.justDropped?.row == row && vm.justDropped?.col == col)
                                    ? (vm.justDropped?.counter ?? 0) : 0
                                Connect4Slot(cell: cell, isWin: isWin, dropToken: dropToken,
                                             row: row, cellSize: connect4CellSize)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .background(Color(hex: "000814").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
        // Timed to land when the disc itself visually reaches the bottom
        // of its fall, not the instant the server tells us about it.
        .onChange(of: vm.justDropped?.counter) { _ in
            guard let drop = vm.justDropped else { return }
            let delay = connect4DropDuration(forRow: drop.row)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                SoundPlayer.shared.play(.connect4Drop)
            }
        }
        .onChange(of: vm.state.winner) { newWinner in
            guard newWinner != nil else { return }
            SoundPlayer.shared.play(.winFanfare)
        }
    }
}

/// A physical-looking cabinet and stand wrapped around the playfield --
/// layered SwiftUI gradients/shapes/shadows rather than SceneKit, so the
/// result is something this sandbox can actually be confident compiles.
///
/// Each decoration is added as a `.background()` of the (already fully
/// sized, via the grid's own fixed-size circles) content rather than as a
/// sibling shape in a `ZStack` -- a `.background()` view is always resized
/// to exactly match the view it's attached to, so the cabinet and recessed
/// panel take on the grid's real size with no ambiguous-layout guesswork.
private struct Connect4StandFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(hex: "07142c"))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.black.opacity(0.6), lineWidth: 5))
                    .shadow(color: .black.opacity(0.7), radius: 14)
            )
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 34)
                    .fill(
                        LinearGradient(colors: [Color(hex: "6b4222"), Color(hex: "4a2c15"), Color(hex: "301c0c")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(Color(hex: "20130a"), lineWidth: 6))
                    .overlay(RoundedRectangle(cornerRadius: 34).strokeBorder(Color.white.opacity(0.08), lineWidth: 1).padding(4))
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 20)
            )
            // Two stubby legs beneath the cabinet so it reads as a standing
            // object, not a flat poster. Attached as a background of the
            // finished cabinet (so it's sized to match) and then offset
            // further down so the feet actually poke out below it.
            .background(
                HStack {
                    Connect4StandLeg()
                    Spacer()
                    Connect4StandLeg()
                }
                .padding(.horizontal, 30)
                .offset(y: 40),
                alignment: .bottom
            )
    }
}

private struct Connect4StandLeg: View {
    var body: some View {
        Connect4Trapezoid()
            .fill(LinearGradient(colors: [Color(hex: "4a2c15"), Color(hex: "301c0c")],
                                  startPoint: .top, endPoint: .bottom))
            .frame(width: 74, height: 60)
            .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
    }
}

private struct Connect4Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset = rect.width * 0.22
        p.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// One slot in the grid. Owns its own fall-animation state, keyed off
/// `dropToken` (0 unless this exact cell is the one the view model just
/// reported as newly filled) so only the single new disc animates -- every
/// other cell simply displays its colour at rest.
private struct Connect4Slot: View {
    let cell: String
    let isWin: Bool
    let dropToken: Int
    let row: Int
    let cellSize: CGFloat

    @State private var displayedCell = ""
    @State private var offsetY: CGFloat = 0
    @State private var squashY: CGFloat = 1.0
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "06101f"))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: 3))
                .frame(width: cellSize, height: cellSize)

            if !displayedCell.isEmpty {
                Circle()
                    .fill(coinColor(displayedCell))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 2).padding(cellSize * 0.12))
                    .frame(width: cellSize, height: cellSize)
                    .shadow(color: isWin ? .yellow : .black.opacity(0.5), radius: isWin ? 16 : 4)
                    .scaleEffect(x: 1, y: squashY, anchor: .bottom)
                    .scaleEffect(isWin ? 1.08 : 1.0)
                    .offset(y: offsetY)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .animation(.spring(), value: isWin)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            // Whatever this slot already holds when the view first mounts
            // (e.g. joining a game in progress) is shown at rest -- only a
            // disc landing *while this view is watching* should animate.
            displayedCell = cell
        }
        .onChange(of: cell) { newValue in
            guard dropToken == 0 else { return }
            displayedCell = newValue
        }
        .onChange(of: dropToken) { newToken in
            guard newToken > 0, !cell.isEmpty else { return }
            animateDrop()
        }
    }

    private func animateDrop() {
        displayedCell = cell
        let travel = CGFloat(row + 1) * (cellSize + connect4CellSpacing) + 70
        offsetY = -travel
        squashY = 1.0
        let duration = connect4DropDuration(forRow: row)
        withAnimation(.easeIn(duration: duration)) {
            offsetY = 0
        }
        // A quick squash-and-recover "thud" once it lands, instead of an
        // overshoot on the position itself (which would read as the disc
        // sinking through the board floor).
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeOut(duration: 0.07)) { squashY = 0.7 }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.45).delay(0.07)) { squashY = 1.0 }
        }
    }

    private func coinColor(_ cell: String) -> Color {
        switch cell { case "red": return .red; case "yellow": return .yellow;
                      default: return Color(hex: "0a1a2e") }
    }
}

struct Connect4DropEvent {
    let row: Int
    let col: Int
    /// Monotonically increasing so SwiftUI's `onChange` fires even if a
    /// later drop happens to land in a cell with the same (row, col) as a
    /// previous one (a new game reusing the same grid, say).
    let counter: Int
}

struct Connect4BoardState {
    var grid: [[String]] = Array(repeating: Array(repeating: "", count: 7), count: 6)
    var currentPlayerID = ""
    var currentPlayerName = ""
    var winner: String? = nil
    var winCells: Set<String> = []

    mutating func update(from data: [String: AnyCodable]) {
        if let g = data["grid"]?.value as? [[String]]  { grid = g }
        if let v = data["currentPlayerID"]?.value as? String  { currentPlayerID = v }
        if let v = data["currentPlayerName"]?.value as? String { currentPlayerName = v }
        if let v = data["winner"]?.value as? String    { winner = v }
        if let v = data["winCells"]?.value as? [String] { winCells = Set(v) }
    }
}

@MainActor final class Connect4BoardViewModel: ObservableObject {
    @Published var state = Connect4BoardState()
    /// The single cell (if any) that just went from empty to filled on the
    /// most recent state push -- nil means either nothing changed or this
    /// is the very first push since `bind()` was called (no prior grid to
    /// diff against).
    @Published var justDropped: Connect4DropEvent?

    private let socket = GameSocketManager.shared
    private var hasReceivedState = false
    private var dropCounter = 0

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard let self, r.roomCode == roomCode else { return }
            if self.hasReceivedState, let newGrid = r.boardState["grid"]?.value as? [[String]] {
                if let changed = Self.firstNewlyFilledCell(old: self.state.grid, new: newGrid) {
                    self.dropCounter += 1
                    self.justDropped = Connect4DropEvent(row: changed.row, col: changed.col, counter: self.dropCounter)
                }
            }
            self.state.update(from: r.boardState)
            self.hasReceivedState = true
        }
    }

    /// Diffs two grids -- the same "what just changed between two
    /// consecutive state pushes" pattern used by the other TV board view
    /// models in this file -- and returns the first cell that went from
    /// empty to non-empty. Connect 4 only ever drops one disc per turn, so
    /// there is at most one such cell in practice.
    private static func firstNewlyFilledCell(old: [[String]], new: [[String]]) -> (row: Int, col: Int)? {
        guard old.count == new.count else { return nil }
        for r in 0..<new.count {
            guard r < old.count, old[r].count == new[r].count else { continue }
            for c in 0..<new[r].count where old[r][c].isEmpty && !new[r][c].isEmpty {
                return (r, c)
            }
        }
        return nil
    }
}

// MARK: - Memory Board

struct TVMemoryBoardView: View {
    let room: Room
    @StateObject private var vm = MemoryBoardViewModel()

    private let cols = 4

    var body: some View {
        VStack(spacing: 24) {
            TVScoreHeader(players: room.players, currentPlayerID: vm.state.currentPlayerID)
                .padding(.top, 40)

            Text("Memory").font(.largeTitle.bold()).foregroundColor(.white)

            Text(vm.state.currentPlayerName.isEmpty ? "" : "\(vm.state.currentPlayerName)'s turn")
                .font(.title3).foregroundColor(.white.opacity(0.5))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 16), count: cols), spacing: 16) {
                ForEach(Array(vm.state.cards.enumerated()), id: \.offset) { idx, card in
                    TVMemoryCard(card: card)
                }
            }
            .padding(32)

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct MemoryCard: Identifiable {
    let id: Int
    var value: String
    var state: MemoryCardState  // hidden, flipped, matched
}

enum MemoryCardState: String { case hidden, flipped, matched }

private struct TVMemoryCard: View {
    let card: MemoryCard
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(card.state == .matched ? Color.green.opacity(0.25)
                      : card.state == .flipped ? Color.white.opacity(0.15)
                      : Color(hex: "1e1e3a"))
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(card.state == .matched ? Color.green.opacity(0.5) : Color.white.opacity(0.06),
                                  lineWidth: 2))
                .frame(width: 112, height: 112)

            if card.state != .hidden {
                // Counter-rotation for the flip below: the tile container
                // rests at 180 degrees around Y once revealed, which shows
                // the card plane's back side to the viewer and mirrors every
                // glyph (e.g. words or asymmetric emoji read backwards).
                // Counter-rotating the revealed face by the same 180
                // degrees nets to zero, so revealed tiles read correctly.
                Text(card.value).font(.system(size: 48))
                    .rotation3DEffect(
                        .degrees(180),
                        axis: (x: 0, y: 1, z: 0)
                    )
            } else {
                Image(systemName: "questionmark").font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
        .rotation3DEffect(
            .degrees(card.state == .hidden ? 0 : 180),
            axis: (x: 0, y: 1, z: 0)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: card.state)
    }
}

struct MemoryBoardState {
    var cards: [MemoryCard] = []
    var currentPlayerID = ""
    var currentPlayerName = ""

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["currentPlayerID"]?.value as? String   { currentPlayerID = v }
        if let v = data["currentPlayerName"]?.value as? String { currentPlayerName = v }
        if let rawCards = data["cards"]?.value as? [[String: Any]] {
            cards = rawCards.enumerated().compactMap { idx, d -> MemoryCard? in
                let stateStr = d["state"] as? String ?? "hidden"
                return MemoryCard(
                    id: idx,
                    value: d["value"] as? String ?? "?",
                    state: MemoryCardState(rawValue: stateStr) ?? .hidden
                )
            }
        }
    }
}

@MainActor final class MemoryBoardViewModel: ObservableObject {
    @Published var state = MemoryBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Mafia Board

struct TVMafiaBoardView: View {
    let room: Room
    @StateObject private var vm = MafiaBoardViewModel()

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mafia").font(.system(size: 48, weight: .bold)).foregroundColor(.white)
                    Text(vm.state.phase == "day" ? "Day \(vm.state.round) — Vote to eliminate"
                         : "Night — Mafia is choosing")
                        .font(.title3).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                TimerRing(secondsLeft: vm.state.secondsLeft, total: vm.state.phase == "day" ? 60 : 30)
            }
            .padding(.horizontal, 60).padding(.top, 40)

            // Players grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                ForEach(vm.state.players) { p in
                    MafiaPlayerTile(player: p)
                }
            }
            .padding(.horizontal, 60)

            // Vote tally (day only)
            if vm.state.phase == "day" && !vm.state.votes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vote Tally").font(.headline).foregroundColor(.white.opacity(0.5))
                    ForEach(vm.state.votes.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
                        HStack {
                            Text(name).foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(0..<count, id: \.self) { _ in
                                    Circle().fill(Color.red).frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                .padding(.horizontal, 60)
            }

            if let eliminated = vm.state.lastEliminated {
                Text("\(eliminated) was eliminated!")
                    .font(.title3.bold()).foregroundColor(.red)
            }

            Spacer()
        }
        .background(Color(hex: vm.state.phase == "day" ? "0a0814" : "00000a").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct MafiaPlayer: Identifiable {
    let id: String
    let name: String
    var isAlive: Bool
    var revealedRole: String?
}

private struct MafiaPlayerTile: View {
    let player: MafiaPlayer
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(player.isAlive ? Color.white.opacity(0.1) : Color.red.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(player.isAlive ? String(player.name.prefix(1)) : "–")
                    .font(.title.bold()).foregroundColor(.white)
            }
            Text(player.name).font(.subheadline)
                .foregroundColor(player.isAlive ? .white : .white.opacity(0.3))
                .strikethrough(!player.isAlive)
            if let role = player.revealedRole {
                Text(role).font(.caption2.bold()).foregroundColor(.red)
            }
        }
        .opacity(player.isAlive ? 1 : 0.5)
    }
}

struct MafiaBoardState {
    var players: [MafiaPlayer] = []
    var phase = "day"
    var round = 1
    var secondsLeft = 60
    var votes: [String: Int] = [:]
    var lastEliminated: String? = nil

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["phase"]?.value as? String        { phase = v }
        if let v = data["round"]?.value as? Int           { round = v }
        if let v = data["secondsLeft"]?.value as? Int     { secondsLeft = v }
        if let v = data["lastEliminated"]?.value as? String { lastEliminated = v }
        if let v = data["votes"]?.value as? [String: Int] { votes = v }
        if let ps = data["players"]?.value as? [[String: Any]] {
            players = ps.compactMap { d -> MafiaPlayer? in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return MafiaPlayer(id: id, name: name,
                                   isAlive: d["isAlive"] as? Bool ?? true,
                                   revealedRole: d["revealedRole"] as? String)
            }
        }
    }
}

@MainActor final class MafiaBoardViewModel: ObservableObject {
    @Published var state = MafiaBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Roulette Board

// The Roulette board lives in its own file (TVRouletteBoardView.swift):
// the animated wheel, ball physics and felt layout are far too much to
// keep wedged in among the other classic boards.

// MARK: - Digit Guess Board (Mastermind / shared guess history)

struct TVDigitGuessBoardView: View {
    let room: Room
    @StateObject private var vm = DigitGuessBoardViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("Digit Guess").font(.system(size: 48, weight: .bold)).foregroundColor(.white)
                .padding(.top, 40)

            Text(vm.state.solved ? "Code cracked!" : "Guess the secret 4-digit code")
                .font(.title3).foregroundColor(vm.state.solved ? .green : .white.opacity(0.5))

            // Player columns
            HStack(alignment: .top, spacing: 24) {
                ForEach(vm.state.playerColumns) { col in
                    VStack(spacing: 8) {
                        Text(col.playerName).font(.headline).foregroundColor(.white)
                            .padding(.bottom, 4)
                        ForEach(Array(col.guesses.enumerated()), id: \.offset) { _, guess in
                            HStack {
                                Text(guess.code)
                                    .font(.system(.body, design: .monospaced).bold())
                                    .foregroundColor(.white)
                                Spacer()
                                Text("Bulls \(guess.bulls) · Cows \(guess.cows)")
                                    .font(.caption).foregroundColor(.white.opacity(0.6))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(guess.bulls == 4 ? Color.green.opacity(0.3) : Color.white.opacity(0.05)))
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct DigitGuessEntry: Identifiable {
    let id = UUID()
    let code: String
    let bulls: Int
    let cows: Int
}

struct DigitGuessPlayerColumn: Identifiable {
    let id: String
    let playerName: String
    var guesses: [DigitGuessEntry]
}

struct DigitGuessBoardState {
    var playerColumns: [DigitGuessPlayerColumn] = []
    var solved = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["solved"]?.value as? Bool { solved = v }
        if let cols = data["players"]?.value as? [[String: Any]] {
            playerColumns = cols.compactMap { d -> DigitGuessPlayerColumn? in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                let guesses = (d["guesses"] as? [[String: Any]] ?? []).compactMap { g -> DigitGuessEntry? in
                    guard let code = g["code"] as? String else { return nil }
                    return DigitGuessEntry(code: code,
                                          bulls: g["bulls"] as? Int ?? 0,
                                          cows: g["cows"] as? Int ?? 0)
                }
                return DigitGuessPlayerColumn(id: id, playerName: name, guesses: guesses)
            }
        }
    }
}

@MainActor final class DigitGuessBoardViewModel: ObservableObject {
    @Published var state = DigitGuessBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Raja Mantri Board

struct TVRajaMantriBoard: View {
    let room: Room
    @StateObject private var vm = RajaMantriViewModel()

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Text("Raja Mantri").font(.system(size: 44, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text("Round \(vm.state.round)").font(.title3).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 60).padding(.top, 40)

            Text(vm.state.phaseLabel).font(.title2).foregroundColor(.cyan.opacity(0.8))

            // Player role cards (revealed after round ends)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(room.players.count, 4)),
                      spacing: 20) {
                ForEach(vm.state.playerRoles) { p in
                    RajaMantriPlayerCard(player: p)
                }
            }
            .padding(.horizontal, 60)

            if let result = vm.state.roundResult {
                Text(result).font(.title3.bold()).foregroundColor(.yellow)
            }

            // Score table
            VStack(spacing: 10) {
                ForEach(room.players.sorted(by: { $0.score > $1.score })) { p in
                    HStack {
                        Text(p.name).foregroundColor(.white)
                        Spacer()
                        Text("\(p.score) pts").font(.headline.bold()).foregroundColor(.cyan)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
            .padding(.horizontal, 60)

            Spacer()
        }
        .background(Color(hex: "0a0814").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct RajaPlayer: Identifiable {
    let id: String
    let name: String
    var revealedRole: String?
    var isAccused: Bool
}

private struct RajaMantriPlayerCard: View {
    let player: RajaPlayer
    var body: some View {
        VStack(spacing: 10) {
            Text(player.revealedRole.map { roleEmoji($0) } ?? "?").font(.system(size: 48))
            Text(player.name).font(.headline).foregroundColor(.white)
            if let role = player.revealedRole {
                Text(role).font(.caption.bold()).foregroundColor(roleColor(role))
            }
            if player.isAccused {
                Text("← ACCUSED").font(.caption2.bold()).foregroundColor(.red)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
    }

    private func roleEmoji(_ r: String) -> String {
        switch r { case "Raja": return "R"; case "Mantri": return "M"; case "Chor": return "C"; default: return "?" }
    }
    private func roleColor(_ r: String) -> Color {
        switch r { case "Raja": return .yellow; case "Mantri": return .purple; case "Chor": return .red; default: return .cyan }
    }
}

struct RajaMantriState {
    var round = 1
    var phase = "deal"
    var playerRoles: [RajaPlayer] = []
    var roundResult: String? = nil

    var phaseLabel: String {
        switch phase {
        case "deal":    return "Roles are being dealt…"
        case "guess":   return "Sipahi is guessing the Chor!"
        case "reveal":  return "Roles revealed!"
        default:        return phase
        }
    }

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["round"]?.value as? Int           { round = v }
        if let v = data["phase"]?.value as? String        { phase = v }
        if let v = data["roundResult"]?.value as? String  { roundResult = v }
        if let ps = data["players"]?.value as? [[String: Any]] {
            playerRoles = ps.compactMap { d -> RajaPlayer? in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return RajaPlayer(id: id, name: name,
                                  revealedRole: d["role"] as? String,
                                  isAccused: d["isAccused"] as? Bool ?? false)
            }
        }
    }
}

@MainActor final class RajaMantriViewModel: ObservableObject {
    @Published var state = RajaMantriState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Tambola Board

struct TVTambolaBoardView: View {
    let room: Room
    @StateObject private var vm = TambolaBoardViewModel()

    var body: some View {
        HStack(spacing: 60) {
            // Left — caller column
            VStack(spacing: 20) {
                Text("Tambola").font(.system(size: 40, weight: .bold)).foregroundColor(.white)

                if let last = vm.state.lastCalled {
                    VStack(spacing: 8) {
                        Text("\(last)").font(.system(size: 96, weight: .black))
                            .foregroundColor(.yellow)
                        Text("Last Called").font(.subheadline).foregroundColor(.white.opacity(0.4))
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.yellow.opacity(0.1)))
                }

                Text("Called: \(vm.state.calledNumbers.count)").font(.body).foregroundColor(.white.opacity(0.5))

                Spacer()

                // Prize board: every prize and who took it.
                if vm.state.prizes.isEmpty {
                    ForEach(vm.state.claims, id: \.self) { claim in
                        Text("\(claim)").font(.headline).foregroundColor(.green)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.state.prizes, id: \.label) { prize in
                            HStack(spacing: 10) {
                                Image(systemName: prize.winner == nil ? "circle" : "checkmark.seal.fill")
                                    .foregroundColor(prize.winner == nil ? .white.opacity(0.3) : .green)
                                Text(prize.label).font(.headline)
                                    .foregroundColor(prize.winner == nil ? .white : .white.opacity(0.5))
                                Spacer()
                                Text(prize.winner ?? "open").font(.headline)
                                    .foregroundColor(prize.winner == nil ? .white.opacity(0.3) : .green)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(width: 320)

            // Right — number board (1–90 grid)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(56)), count: 10), spacing: 8) {
                ForEach(1...90, id: \.self) { num in
                    Text("\(num)")
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundColor(vm.state.calledNumbers.contains(num) ? .black : .white)
                        .frame(width: 50, height: 40)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(vm.state.calledNumbers.contains(num)
                                  ? Color.yellow : Color.white.opacity(0.06)))
                }
            }
            .padding(24)
        }
        .padding(60)
        .background(Color(hex: "0a0814").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct TambolaBoardState {
    var calledNumbers: Set<Int> = []
    var lastCalled: Int? = nil
    var claims: [String] = []
    var prizes: [(label: String, winner: String?)] = []

    mutating func update(from data: [String: AnyCodable]) {
        prizes = (data["prizes"]?.value as? [Any] ?? []).compactMap {
            guard let d = $0 as? [String: Any], let label = d["label"] as? String else { return nil }
            return (label, d["winnerName"] as? String)
        }
        if let v = data["called"]?.value as? [Int]       { calledNumbers = Set(v) }
        if let v = data["lastCalled"]?.value as? Int      { lastCalled = v }
        if let v = data["claims"]?.value as? [String]     { claims = v }
    }
}

@MainActor final class TambolaBoardViewModel: ObservableObject {
    @Published var state = TambolaBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Stock Panic Board

struct TVStockPanicBoardView: View {
    let room: Room
    @StateObject private var vm = StockPanicBoardViewModel()

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Stock Panic").font(.system(size: 44, weight: .bold)).foregroundColor(.white)
                Spacer()
                if let news = vm.state.latestNews {
                    HStack(spacing: 8) {
                        Image(systemName: "newspaper.fill").foregroundColor(.yellow)
                        Text(news).font(.subheadline).foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Color.yellow.opacity(0.15)))
                }
            }
            .padding(.horizontal, 60).padding(.top, 40)

            // Stock ticker
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(vm.state.stocks) { stock in
                    StockTile(stock: stock)
                }
            }
            .padding(.horizontal, 60)

            // Leaderboard
            HStack(alignment: .top, spacing: 0) {
                ForEach(room.players.sorted(by: { $0.score > $1.score })) { p in
                    VStack(spacing: 4) {
                        Text(p.name).font(.subheadline).foregroundColor(.white)
                        Text("$\(p.score)").font(.headline.bold()).foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
            .padding(.horizontal, 60)

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct StockEntry: Identifiable {
    let id: String
    let name: String
    var price: Int
    var change: Int
}

private struct StockTile: View {
    let stock: StockEntry
    var body: some View {
        VStack(spacing: 6) {
            Text(stock.name).font(.headline).foregroundColor(.white)
            Text("$\(stock.price)").font(.system(size: 32, weight: .bold))
                .foregroundColor(stock.change >= 0 ? .green : .red)
            HStack(spacing: 4) {
                Image(systemName: stock.change >= 0 ? "arrow.up" : "arrow.down")
                Text("\(abs(stock.change))").font(.caption)
            }
            .foregroundColor(stock.change >= 0 ? .green : .red)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }
}

struct StockPanicBoardState {
    var stocks: [StockEntry] = []
    var latestNews: String? = nil

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["latestNews"]?.value as? String { latestNews = v }
        if let s = data["stocks"]?.value as? [[String: Any]] {
            stocks = s.compactMap { d -> StockEntry? in
                guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
                return StockEntry(id: id, name: name,
                                  price: d["price"] as? Int ?? 0,
                                  change: d["change"] as? Int ?? 0)
            }
        }
    }
}

@MainActor final class StockPanicBoardViewModel: ObservableObject {
    @Published var state = StockPanicBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Mind Meld Board

struct TVMindMeldBoardView: View {
    let room: Room
    @StateObject private var vm = MindMeldBoardViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Text("Mind Meld").font(.system(size: 48, weight: .bold)).foregroundColor(.white)
                .padding(.top, 40)

            if let category = vm.state.category {
                Text("Category: \(category)").font(.title2).foregroundColor(.cyan)
            }

            if vm.state.showReveal {
                // Reveal all words
                VStack(spacing: 16) {
                    Text("Words submitted:").font(.headline).foregroundColor(.white.opacity(0.5))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(vm.state.submissions) { sub in
                            VStack(spacing: 4) {
                                Text(sub.word).font(.title2.bold()).foregroundColor(.white)
                                Text(sub.playerName).font(.caption).foregroundColor(.white.opacity(0.5))
                                if sub.isMeld {
                                    Text("MELD +\(sub.meldCount)!").font(.caption.bold()).foregroundColor(.green)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(sub.isMeld ? Color.green.opacity(0.2) : Color.white.opacity(0.06)))
                        }
                    }
                }
                .padding(.horizontal, 60)
            } else {
                // Waiting for submissions
                VStack(spacing: 16) {
                    let submitted = vm.state.submissions.count
                    let total = room.players.count
                    Text("\(submitted) / \(total) submitted").font(.title2).foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 12) {
                        ForEach(room.players) { p in
                            VStack(spacing: 6) {
                                Image(systemName: vm.state.submittedIDs.contains(p.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.title).foregroundColor(vm.state.submittedIDs.contains(p.id) ? .green : .white.opacity(0.3))
                                Text(p.name).font(.caption).foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
            }

            TVScoreHeader(players: room.players, currentPlayerID: nil)

            Spacer()
        }
        .background(Color(hex: "0d0a14").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct MeldSubmission: Identifiable {
    let id: String
    let playerName: String
    let word: String
    var isMeld: Bool
    var meldCount: Int
}

struct MindMeldBoardState {
    var category: String? = nil
    var submittedIDs: Set<String> = []
    var submissions: [MeldSubmission] = []
    var showReveal = false

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["category"]?.value as? String        { category = v }
        if let v = data["showReveal"]?.value as? Bool        { showReveal = v }
        if let v = data["submittedIDs"]?.value as? [String]  { submittedIDs = Set(v) }
        if let subs = data["submissions"]?.value as? [[String: Any]] {
            submissions = subs.compactMap { d -> MeldSubmission? in
                guard let id = d["id"] as? String,
                      let name = d["playerName"] as? String,
                      let word = d["word"] as? String else { return nil }
                return MeldSubmission(id: id, playerName: name, word: word,
                                      isMeld: d["isMeld"] as? Bool ?? false,
                                      meldCount: d["meldCount"] as? Int ?? 0)
            }
        }
    }
}

@MainActor final class MindMeldBoardViewModel: ObservableObject {
    @Published var state = MindMeldBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Hot Grid Board

struct TVHotGridBoardView: View {
    let room: Room
    @StateObject private var vm = HotGridBoardViewModel()

    private let gridSize = 5
    private let tileSize: CGFloat = 110
    private let gap: CGFloat = 12

    var body: some View {
        ZStack {
            TVAnimatedBackground(palette: TVTheme.ember)

            VStack(spacing: 28) {
                header
                TVScoreHeader(players: room.players, currentPlayerID: vm.state.currentPlayerID)
                Spacer(minLength: 0)
                grid
                Spacer(minLength: 0)
            }
            .padding(.bottom, 40)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private var header: some View {
        HStack(alignment: .center) {
            TVGlowText(text: "Hot Grid", size: 54, color: TVTheme.ember.accent)
            Spacer()
            if !vm.state.currentPlayerName.isEmpty {
                TVGlassCard(cornerRadius: 22, tint: TVTheme.gold, glow: TVTheme.gold, padding: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.point.up.left.fill").foregroundColor(TVTheme.gold)
                        Text("\(vm.state.currentPlayerName)'s turn")
                            .font(.title3.bold()).foregroundColor(.white)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                }
                .id(vm.state.currentPlayerName)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: vm.state.currentPlayerName)
        .padding(.horizontal, 60).padding(.top, 40)
    }

    // 5x5 grid of flip tiles on a tilted, glowing tray.
    private var grid: some View {
        VStack(spacing: gap) {
            ForEach(0..<gridSize, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<gridSize, id: \.self) { col in
                        HotGridTileView(tile: vm.state.tiles[safe: row * gridSize + col], size: tileSize)
                    }
                }
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "2a1206"), Color(hex: "120703")],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [TVTheme.gold.opacity(0.6), Color(hex: "b45309").opacity(0.2)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 2))
        )
        .shadow(color: Color(hex: "f97316").opacity(0.25), radius: 40)
        .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 26)
        .rotation3DEffect(.degrees(16), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
    }
}

enum HotGridTileContent { case hidden, coin(Int), trap, teleport }

/// A tile that flips over in 3D the moment it is revealed.
private struct HotGridTileView: View {
    let tile: HotGridTileContent?
    let size: CGFloat

    private var revealed: Bool {
        switch tile {
        case .hidden, .none: return false
        default: return true
        }
    }

    var body: some View {
        TVFlipCard(isFaceUp: revealed) {
            face
        } back: {
            back
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.65, dampingFraction: 0.7), value: revealed)
    }

    private var back: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "3f2a1e"), Color(hex: "1c120c")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 1.5)
            Text("?")
                .font(TVTheme.display(size * 0.38))
                .foregroundColor(Color.white.opacity(0.28))
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 8)
    }

    private var face: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [faceColors.0, faceColors.1],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
            faceContent
        }
        .frame(width: size, height: size)
        .shadow(color: faceColors.0.opacity(0.7), radius: 18)
    }

    @ViewBuilder private var faceContent: some View {
        switch tile {
        case .coin(let v):
            VStack(spacing: 2) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(LinearGradient(colors: [Color.white, Color(hex: "fde047")],
                                                    startPoint: .top, endPoint: .bottom))
                Text("+\(v)").font(TVTheme.display(size * 0.18)).foregroundColor(.white)
            }
        case .trap:
            Image(systemName: "burst.fill")
                .font(.system(size: size * 0.42))
                .foregroundColor(.white)
        case .teleport:
            Image(systemName: "tornado")
                .font(.system(size: size * 0.42))
                .foregroundColor(.white)
        case .hidden, .none:
            EmptyView()
        }
    }

    private var faceColors: (Color, Color) {
        switch tile {
        case .coin: return (Color(hex: "f59e0b"), Color(hex: "92400e"))
        case .trap: return (Color(hex: "ef4444"), Color(hex: "7f1d1d"))
        case .teleport: return (Color(hex: "a855f7"), Color(hex: "4c1d95"))
        case .hidden, .none: return (Color(hex: "3f2a1e"), Color(hex: "1c120c"))
        }
    }
}

struct HotGridBoardState {
    var tiles: [HotGridTileContent] = Array(repeating: .hidden, count: 25)
    var currentPlayerID = ""
    var currentPlayerName = ""

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["currentPlayerID"]?.value as? String   { currentPlayerID = v }
        if let v = data["currentPlayerName"]?.value as? String { currentPlayerName = v }
        if let rawTiles = data["tiles"]?.value as? [String] {
            tiles = rawTiles.map { t -> HotGridTileContent in
                if t == "hidden"    { return .hidden }
                if t == "trap"      { return .trap }
                if t == "teleport"  { return .teleport }
                if let v = Int(t)   { return .coin(v) }
                return .hidden
            }
        }
    }
}

@MainActor final class HotGridBoardViewModel: ObservableObject {
    @Published var state = HotGridBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Speed Sculptor Board

struct TVSpeedSculptorBoardView: View {
    let room: Room
    @StateObject private var vm = SpeedSculptorBoardViewModel()

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Speed Sculptor").font(.system(size: 40, weight: .bold)).foregroundColor(.white)
                Spacer()
                if let prompt = vm.state.prompt {
                    Text("Drawing: \(prompt)").font(.title2.bold()).foregroundColor(.yellow)
                }
            }
            .padding(.horizontal, 60).padding(.top, 40)

            if vm.state.votingPhase {
                // Show all drawings + vote tally
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(room.players.count, 3)),
                          spacing: 20) {
                    ForEach(vm.state.drawings) { drawing in
                        DrawingCard(drawing: drawing)
                    }
                }
                .padding(.horizontal, 60)
            } else {
                // Countdown while players draw
                VStack(spacing: 24) {
                    TimerRing(secondsLeft: vm.state.secondsLeft, total: 20)
                        .frame(width: 120, height: 120)
                    Text("Players are drawing…").font(.title2).foregroundColor(.white.opacity(0.5))
                    let submitted = vm.state.submittedCount
                    Text("\(submitted) / \(room.players.count) submitted")
                        .font(.subheadline).foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

struct PlayerDrawing: Identifiable {
    let id: String
    let playerName: String
    let lines: [[[Double]]]  // simplified line arrays from server
    var voteCount: Int
}

private struct DrawingCard: View {
    let drawing: PlayerDrawing
    var body: some View {
        VStack(spacing: 8) {
            Canvas { ctx, size in
                for line in drawing.lines {
                    var path = Path()
                    let pts = line.compactMap { p -> CGPoint? in
                        guard p.count >= 2 else { return nil }
                        return CGPoint(x: p[0] * size.width, y: p[1] * size.height)
                    }
                    guard let first = pts.first else { continue }
                    path.move(to: first)
                    for pt in pts.dropFirst() { path.addLine(to: pt) }
                    ctx.stroke(path, with: .color(.black), lineWidth: 3)
                }
            }
            .background(Color.white)
            .frame(height: 220)
            .cornerRadius(12)

            HStack {
                Text(drawing.playerName).font(.headline).foregroundColor(.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsup.fill").foregroundColor(.cyan)
                    Text("\(drawing.voteCount)").font(.headline.bold()).foregroundColor(.cyan)
                }
            }
        }
    }
}

struct SpeedSculptorBoardState {
    var prompt: String? = nil
    var secondsLeft = 20
    var votingPhase = false
    var submittedCount = 0
    var drawings: [PlayerDrawing] = []

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["prompt"]?.value as? String       { prompt = v }
        if let v = data["secondsLeft"]?.value as? Int     { secondsLeft = v }
        if let v = data["votingPhase"]?.value as? Bool    { votingPhase = v }
        if let v = data["submittedCount"]?.value as? Int  { submittedCount = v }
        if let ds = data["drawings"]?.value as? [[String: Any]] {
            drawings = ds.compactMap { d -> PlayerDrawing? in
                guard let id = d["id"] as? String, let name = d["playerName"] as? String else { return nil }
                return PlayerDrawing(id: id, playerName: name,
                                     lines: d["lines"] as? [[[Double]]] ?? [],
                                     voteCount: d["voteCount"] as? Int ?? 0)
            }
        }
    }
}

@MainActor final class SpeedSculptorBoardViewModel: ObservableObject {
    @Published var state = SpeedSculptorBoardState()
    private let socket = GameSocketManager.shared
    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}

// MARK: - Array safe subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// MARK: - TimerRing (shared across board views)

struct TimerRing: View {
    let secondsLeft: Int
    let total: Int

    private var progress: Double { total > 0 ? Double(secondsLeft) / Double(total) : 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progress > 0.4 ? Color.cyan : Color.red,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsLeft)
            Text("\(secondsLeft)")
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 70, height: 70)
    }
}
