import SwiftUI

// MARK: - Shared helpers

struct PlaceholderBoardView: View {
    let game: GameID
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: game.sfSymbol).font(.system(size: 80, weight: .regular, design: .rounded)).foregroundColor(.white.opacity(0.7))
            Text(game.displayName).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundColor(.white)
            Text("No longer available. Pick another game.").foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TVTheme.bg.ignoresSafeArea())
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
                        .fill(p.id == currentPlayerID ? TVTheme.cyan : Color.white.opacity(0.15))
                        .frame(width: 12, height: 12)
                    Text(p.name).foregroundColor(p.id == currentPlayerID ? .white : .white.opacity(0.5))
                    Text("\(p.score)").font(.system(.headline, design: .rounded, weight: .bold)).foregroundColor(TVTheme.cyan)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(p.id == currentPlayerID ? TVTheme.cyan.opacity(0.15) : Color.white.opacity(0.05)))
            }
            Spacer()
        }
        .padding(.horizontal, 48)
    }
}

// MARK: - Poker Board
//
// Moved to TVPokerBoardView.swift.

// MARK: - Four in a Row Board
//
// 2-4 players on a board that grows with the table (6x7, 7x9, 8x10). The
// playfield is built like the real toy: a glassy blue front panel with holes
// punched through it (an even-odd filled shape), with the discs living on a
// layer *behind* it. A dropped disc therefore falls behind the panel and
// flashes past each hole on its way down, then bounces as it lands.

/// Largest cell the board ever uses (a classic 6x7 game on a big screen).
private let connect4MaxCellSize: CGFloat = 104
/// Gap between holes and the panel margin, as fractions of a cell.
private let connect4GapRatio: CGFloat = 0.16
private let connect4MarginRatio: CGFloat = 0.32

/// How long a disc takes to fall into row `row` (0 = top row; deeper rows
/// fall further and take longer) -- drives the fall animation and times the
/// landing sound so the "clack" plays when the disc visually lands.
private func connect4DropDuration(forRow row: Int) -> Double {
    0.22 + Double(row + 1) * 0.075
}

/// Display palette for a disc colour id from the server.
private struct Connect4Palette {
    let base: Color
    let light: Color
    let dark: Color
    let glow: Color

    static func of(_ id: String) -> Connect4Palette {
        switch id {
        case "red":
            return Connect4Palette(base: Color(hex: "e8283b"), light: Color(hex: "ff8a8f"),
                                   dark: Color(hex: "7a0b16"), glow: Color(hex: "ff4d5e"))
        case "yellow":
            return Connect4Palette(base: Color(hex: "ffc61a"), light: Color(hex: "fff1a8"),
                                   dark: Color(hex: "9a6a00"), glow: Color(hex: "ffd84d"))
        case "green":
            return Connect4Palette(base: Color(hex: "1fc96b"), light: Color(hex: "9cf5c2"),
                                   dark: Color(hex: "0a6634"), glow: Color(hex: "3dff8f"))
        case "blue":
            // Brighter than the cabinet so blue discs still pop on a blue board.
            return Connect4Palette(base: Color(hex: "35b4ff"), light: Color(hex: "c4ecff"),
                                   dark: Color(hex: "0b5c9e"), glow: Color(hex: "6fd0ff"))
        default:
            return Connect4Palette(base: Color(hex: "8a94a6"), light: Color(hex: "d5dbe6"),
                                   dark: Color(hex: "3c4454"), glow: Color(hex: "b8c2d4"))
        }
    }

    static let fallbackOrder: [String] = ["red", "yellow", "green", "blue"]
}

/// Board geometry shared by the panel shape, the disc layer and the win
/// overlay so every layer lines up exactly.
private struct Connect4Layout {
    let rows: Int
    let cols: Int
    let cell: CGFloat

    var gap: CGFloat { cell * connect4GapRatio }
    var margin: CGFloat { cell * connect4MarginRatio }
    var width: CGFloat {
        margin * 2 + CGFloat(cols) * cell + CGFloat(max(cols - 1, 0)) * gap
    }
    var height: CGFloat {
        margin * 2 + CGFloat(rows) * cell + CGFloat(max(rows - 1, 0)) * gap
    }

    func center(row: Int, col: Int) -> CGPoint {
        let x: CGFloat = margin + CGFloat(col) * (cell + gap) + cell / 2
        let y: CGFloat = margin + CGFloat(row) * (cell + gap) + cell / 2
        return CGPoint(x: x, y: y)
    }

    /// Biggest cell that fits `rows` x `cols` (plus margins) in `size`.
    static func fitting(rows: Int, cols: Int, in size: CGSize) -> Connect4Layout {
        let r = CGFloat(max(rows, 1))
        let c = CGFloat(max(cols, 1))
        let unitsWide: CGFloat = c + (c - 1) * connect4GapRatio + 2 * connect4MarginRatio
        let unitsHigh: CGFloat = r + (r - 1) * connect4GapRatio + 2 * connect4MarginRatio
        let byWidth: CGFloat = max(size.width, 1) / unitsWide
        let byHeight: CGFloat = max(size.height, 1) / unitsHigh
        let cell: CGFloat = max(32, min(connect4MaxCellSize, min(byWidth, byHeight)))
        return Connect4Layout(rows: max(rows, 1), cols: max(cols, 1), cell: cell.rounded(.down))
    }
}

struct TVConnect4BoardView: View {
    let room: Room
    @StateObject private var vm = Connect4BoardViewModel()

    /// Space reserved around the panel for the cabinet bezel, the drop rail
    /// above it and the feet below it.
    private let bezel: CGFloat = 18
    private let railHeight: CGFloat = 30
    private let feetHeight: CGFloat = 34

    var body: some View {
        ZStack {
            Connect4AmbientBackground(accent: Connect4Palette.of(currentColorID).glow)
            VStack(spacing: 16) {
                topBar
                HStack(alignment: .center, spacing: 44) {
                    sidebar
                    boardArea
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 20)
        }
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

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONNECT 4")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(
                        LinearGradient(colors: [Color.white, Color(hex: "9fc4ff")],
                                       startPoint: .top, endPoint: .bottom)
                    )
                Text(subtitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer(minLength: 20)
            Connect4TurnBanner(
                bannerKey: bannerKey,
                text: bannerText,
                colorID: bannerColorID,
                isFinal: vm.state.winner != nil || vm.state.isDraw
            )
        }
        .frame(height: 84)
    }

    private var subtitle: String {
        // The real seat count, not a floor of two: it used to read "2
        // players" whatever the server had actually seated, which hid the
        // bug where two phones sharing a device id shared one seat.
        let count = seats.count
        let who = count == 1 ? "1 player" : "\(count) players"
        return "\(who)  |  \(vm.state.rows) x \(vm.state.cols)  |  four in a row wins"
    }

    private var winnerName: String {
        guard let winner = vm.state.winner else { return "" }
        // `winner` is the winning player's name (older servers) -- prefer
        // the explicit `winnerID` when the server sends it.
        if let id = vm.state.winnerID,
           let seat = seats.first(where: { $0.id == id }) {
            return seat.name
        }
        if let seat = seats.first(where: { $0.id == winner }) {
            return seat.name
        }
        return winner
    }

    private var bannerKey: String {
        if vm.state.winner != nil { return "win" }
        if vm.state.isDraw { return "draw" }
        return "turn-" + vm.state.currentPlayerID
    }

    private var bannerText: String {
        if vm.state.winner != nil { return "\(winnerName) wins!" }
        if vm.state.isDraw { return "Board full -- it's a draw" }
        if vm.state.currentPlayerName.isEmpty { return "Get ready" }
        return "\(vm.state.currentPlayerName)'s turn"
    }

    private var bannerColorID: String {
        if vm.state.winner != nil {
            if !vm.state.winnerColorID.isEmpty { return vm.state.winnerColorID }
            return seats.first(where: { isWinner($0) })?.colorID ?? ""
        }
        if vm.state.isDraw { return "" }
        return currentColorID
    }

    /// The mover's colour; older servers omit `currentColor`/`colors`, so
    /// fall back to the seat-order colour.
    private var currentColorID: String {
        if !vm.state.currentColorID.isEmpty { return vm.state.currentColorID }
        let current = vm.state.currentPlayerID
        guard !current.isEmpty else { return "" }
        return seats.first(where: { $0.id == current })?.colorID ?? ""
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PLAYERS")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .tracking(4)
                .foregroundColor(.white.opacity(0.45))
            ForEach(seats) { seat in
                Connect4PlayerChip(
                    seat: seat,
                    isCurrent: seat.id == vm.state.currentPlayerID
                        && vm.state.winner == nil && !vm.state.isDraw,
                    isWinner: isWinner(seat),
                    discCount: vm.state.discCount(of: seat.colorID)
                )
            }
            Spacer(minLength: 0)
            moveCounter
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var moveCounter: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "7fa8ff"))
            Text("\(vm.state.filledCount) / \(vm.state.rows * vm.state.cols) discs played")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func isWinner(_ seat: Connect4Seat) -> Bool {
        guard vm.state.winner != nil else { return false }
        if let id = vm.state.winnerID { return id == seat.id }
        return vm.state.winner == seat.name || vm.state.winner == seat.id
    }

    // MARK: Board

    private var boardArea: some View {
        GeometryReader { geo in
            let available = CGSize(
                width: geo.size.width - bezel * 2,
                height: geo.size.height - bezel * 2 - railHeight - feetHeight
            )
            let layout = Connect4Layout.fitting(rows: vm.state.rows, cols: vm.state.cols, in: available)
            boardStack(layout: layout)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func boardStack(layout: Connect4Layout) -> some View {
        VStack(spacing: 0) {
            Connect4DropRail(layout: layout, lastMove: vm.state.lastMove)
                .frame(width: layout.width, height: railHeight)
            Connect4Cabinet(layout: layout, bezel: bezel, feetHeight: feetHeight) {
                playfield(layout: layout)
            }
        }
    }

    private func playfield(layout: Connect4Layout) -> some View {
        ZStack(alignment: .topLeading) {
            Connect4BackWell(cornerRadius: layout.cell * 0.28)
            Connect4DiscLayer(layout: layout, state: vm.state, justDropped: vm.justDropped)
            Connect4FrontPanel(layout: layout)
            Connect4WinOverlay(layout: layout, cells: vm.state.winCellPoints,
                               colorID: bannerColorID)
        }
        .frame(width: layout.width, height: layout.height)
    }

    // MARK: Seats

    /// Players in turn order, each with their colour.
    private var seats: [Connect4Seat] {
        let known: [Connect4Seat] = vm.state.players.isEmpty
            ? room.players.map { Connect4Seat(id: $0.id, name: $0.name, score: $0.score, colorID: "") }
            : vm.state.players
        var ordered: [Connect4Seat] = []
        for id in vm.state.turnOrder {
            if let seat = known.first(where: { $0.id == id }) {
                ordered.append(seat)
            }
        }
        for seat in known where !ordered.contains(where: { $0.id == seat.id }) {
            ordered.append(seat)
        }
        var result: [Connect4Seat] = []
        for (index, seat) in ordered.enumerated() {
            var copy = seat
            copy.colorID = colorID(for: seat.id, fallbackIndex: index)
            result.append(copy)
        }
        return result
    }

    private func colorID(for playerID: String, fallbackIndex: Int = 0) -> String {
        if let id = vm.state.colors[playerID] { return id }
        if let index = vm.state.turnOrder.firstIndex(of: playerID) {
            return Connect4Palette.fallbackOrder[index % Connect4Palette.fallbackOrder.count]
        }
        return Connect4Palette.fallbackOrder[fallbackIndex % Connect4Palette.fallbackOrder.count]
    }
}

struct Connect4Seat: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    var colorID: String
}

// MARK: Four in a Row -- pieces

/// A glossy, 3D-looking disc: radial body, darker rim, an embossed inner
/// ring like the real toy, and a soft specular highlight up and to the left.
private struct Connect4Disc: View {
    let colorID: String
    let size: CGFloat

    var body: some View {
        let palette = Connect4Palette.of(colorID)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [palette.light, palette.base, palette.dark],
                                   center: UnitPoint(x: 0.36, y: 0.30),
                                   startRadius: 0, endRadius: size * 0.72)
                )
            Circle()
                .strokeBorder(palette.dark.opacity(0.75), lineWidth: max(1, size * 0.05))
            Circle()
                .strokeBorder(
                    LinearGradient(colors: [palette.dark.opacity(0.55), palette.light.opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: max(1, size * 0.035)
                )
                .padding(size * 0.17)
            Ellipse()
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: size * 0.52, height: size * 0.30)
                .offset(x: -size * 0.09, y: -size * 0.23)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.45), radius: size * 0.06, x: 0, y: size * 0.05)
    }
}

/// One disc slot on the layer behind the panel. Owns its own drop animation,
/// keyed off `dropToken` (0 unless this exact cell just filled) so only the
/// single new disc animates; every other disc simply sits at rest.
private struct Connect4DiscSlot: View {
    let cell: String
    let dropToken: Int
    let row: Int
    let layout: Connect4Layout

    @State private var displayedCell = ""
    @State private var offsetY: CGFloat = 0
    @State private var hasAppeared = false
    @State private var animatedToken = 0

    var body: some View {
        ZStack {
            if !displayedCell.isEmpty {
                Connect4Disc(colorID: displayedCell, size: layout.cell * 0.98)
                    .offset(y: offsetY)
            }
        }
        .frame(width: layout.cell, height: layout.cell)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            // Whatever the slot holds when it first mounts (joining a game
            // in progress) is shown at rest -- only a disc landing while
            // this view is watching animates.
            displayedCell = cell
            animatedToken = dropToken
        }
        .onChange(of: cell) { _ in sync() }
        .onChange(of: dropToken) { _ in sync() }
    }

    /// Reconciles the shown disc with `cell`/`dropToken`. Safe whichever of
    /// the two changes SwiftUI delivers first (or if they arrive in
    /// separate updates): the drop animates exactly once per token, and
    /// everything else (rematch clears, catch-up pushes) just snaps.
    private func sync() {
        if dropToken > 0, !cell.isEmpty, dropToken != animatedToken {
            animatedToken = dropToken
            animateDrop()
        } else if dropToken == 0 || cell.isEmpty {
            displayedCell = cell
            offsetY = 0
        }
    }

    private func animateDrop() {
        displayedCell = cell
        // Start just above the panel so the disc visibly enters from the top.
        let travel: CGFloat = CGFloat(row + 1) * (layout.cell + layout.gap) + layout.margin
        offsetY = -travel
        let duration = connect4DropDuration(forRow: row)
        withAnimation(.easeIn(duration: duration)) {
            offsetY = 0
        }
        // Two diminishing bounces after the landing.
        let first: CGFloat = -layout.cell * 0.20
        let second: CGFloat = -layout.cell * 0.07
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeOut(duration: 0.11)) { offsetY = first }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.11) {
            withAnimation(.easeIn(duration: 0.11)) { offsetY = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.22) {
            withAnimation(.easeOut(duration: 0.07)) { offsetY = second }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.29) {
            withAnimation(.easeIn(duration: 0.07)) { offsetY = 0 }
        }
    }
}

/// Every disc slot, positioned on the shared layout.
private struct Connect4DiscLayer: View {
    let layout: Connect4Layout
    let state: Connect4BoardState
    let justDropped: Connect4DropEvent?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<(layout.rows * layout.cols), id: \.self) { index in
                slot(index: index)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    private func slot(index: Int) -> some View {
        let row: Int = index / layout.cols
        let col: Int = index % layout.cols
        let point: CGPoint = layout.center(row: row, col: col)
        var token: Int = 0
        if let drop = justDropped, drop.row == row, drop.col == col {
            token = drop.counter
        }
        return Connect4DiscSlot(cell: state.cell(row: row, col: col), dropToken: token,
                                row: row, layout: layout)
            .position(x: point.x, y: point.y)
    }
}

// MARK: Four in a Row -- cabinet

/// The panel outline with every hole punched out (filled even-odd).
private struct Connect4PanelShape: Shape {
    let layout: Connect4Layout
    let includeOutline: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        if includeOutline {
            p.addRoundedRect(in: rect, cornerSize: CGSize(width: layout.cell * 0.28,
                                                          height: layout.cell * 0.28))
        }
        for row in 0..<layout.rows {
            for col in 0..<layout.cols {
                let c = layout.center(row: row, col: col)
                let r = layout.cell / 2
                p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
        }
        return p
    }
}

/// Dark recess behind the discs, seen through empty holes.
private struct Connect4BackWell: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(colors: [Color(hex: "020817"), Color(hex: "06123a")],
                               startPoint: .top, endPoint: .bottom)
            )
    }
}

/// The glassy blue front panel: gradient body, a glass sheen across the
/// top, an inner shadow around every hole and a bright lip on each hole's
/// lower edge where light catches it.
private struct Connect4FrontPanel: View {
    let layout: Connect4Layout

    private var panel: Connect4PanelShape { Connect4PanelShape(layout: layout, includeOutline: true) }
    private var holes: Connect4PanelShape { Connect4PanelShape(layout: layout, includeOutline: false) }

    var body: some View {
        ZStack {
            panel
                .fill(
                    LinearGradient(colors: [Color(hex: "2f6bff"), Color(hex: "1a44c9"), Color(hex: "0f2a86")],
                                   startPoint: .top, endPoint: .bottom),
                    style: FillStyle(eoFill: true)
                )
            sheen
            holeShading
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }

    private var sheen: some View {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.28), location: 0.0),
                .init(color: Color.white.opacity(0.06), location: 0.42),
                .init(color: Color.clear, location: 0.55),
                .init(color: Color.black.opacity(0.18), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .mask { panel.fill(style: FillStyle(eoFill: true)) }
    }

    private var holeShading: some View {
        ZStack {
            // Inner shadow: a dark stroke blurred and clipped inside each hole.
            holes
                .stroke(Color.black.opacity(0.75), lineWidth: max(4, layout.cell * 0.10))
                .blur(radius: max(2, layout.cell * 0.05))
                .clipShape(holes)
            // Light catching the lower lip of each hole: the ring shifted up
            // and clipped to the holes leaves a crescent on each lower edge.
            holes
                .stroke(Color(hex: "a9c8ff").opacity(0.55), lineWidth: lipWidth)
                .offset(y: -lipWidth)
                .blur(radius: 1)
                .clipShape(holes)
            // A crisp dark rim so every hole reads cleanly at any size.
            holes
                .stroke(Color.black.opacity(0.4), lineWidth: 1.5)
        }
    }

    private var lipWidth: CGFloat { max(2, layout.cell * 0.045) }
}

/// Outer cabinet: a deep glassy frame around the panel, with an inner
/// shadow, a highlighted rim, a long soft drop shadow and two feet.
private struct Connect4Cabinet<Content: View>: View {
    let layout: Connect4Layout
    let bezel: CGFloat
    let feetHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(bezel)
                .background(cabinetBody)
            feet
        }
    }

    private var cabinetBody: some View {
        let shape = RoundedRectangle(cornerRadius: bezel + layout.cell * 0.28)
        return shape
            .fill(
                LinearGradient(colors: [Color(hex: "1b3fae"), Color(hex: "0c2170"), Color(hex: "06143f")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                shape
                    .stroke(Color.black.opacity(0.6), lineWidth: 10)
                    .blur(radius: 8)
                    .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color(hex: "8fb4ff").opacity(0.75), Color(hex: "0a1a55").opacity(0.4)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 2.5
                )
            )
            .shadow(color: Color(hex: "1d4ed8").opacity(0.35), radius: 40, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.6), radius: 26, x: 0, y: 22)
    }

    private var feet: some View {
        HStack {
            Connect4Foot()
            Spacer()
            Connect4Foot()
        }
        .padding(.horizontal, bezel + layout.cell * 0.4)
        .frame(width: layout.width + bezel * 2, height: feetHeight, alignment: .top)
    }
}

private struct Connect4Foot: View {
    var body: some View {
        Connect4Trapezoid()
            .fill(
                LinearGradient(colors: [Color(hex: "0c2170"), Color(hex: "040b26")],
                               startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 92, height: 34)
            .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 8)
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

/// A little marker above the column the last disc went into.
private struct Connect4DropRail: View {
    let layout: Connect4Layout
    let lastMove: Connect4Move?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let move = lastMove, move.col >= 0, move.col < layout.cols {
                marker(colorID: move.colorID)
                    .position(x: layout.center(row: 0, col: move.col).x, y: 14)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: move.col)
            }
        }
    }

    private func marker(colorID: String) -> some View {
        let palette = Connect4Palette.of(colorID)
        return Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundColor(palette.base)
            .shadow(color: palette.glow.opacity(0.8), radius: 8)
    }
}

// MARK: Four in a Row -- win, banner, chips, background

/// Pulsing glow rings over the winning four, drawn above the panel.
private struct Connect4WinOverlay: View {
    let layout: Connect4Layout
    let cells: [Connect4CellPoint]
    let colorID: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(cells) { cell in
                Connect4WinRing(colorID: colorID, size: layout.cell)
                    .position(layout.center(row: cell.row, col: cell.col))
            }
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }
}

private struct Connect4WinRing: View {
    let colorID: String
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        let palette = Connect4Palette.of(colorID)
        return Circle()
            .strokeBorder(Color.white.opacity(0.95), lineWidth: max(3, size * 0.06))
            .background(Circle().fill(palette.glow.opacity(pulse ? 0.35 : 0.08)))
            .frame(width: size * 1.06, height: size * 1.06)
            .shadow(color: palette.glow, radius: pulse ? size * 0.32 : size * 0.10)
            .shadow(color: Color.white.opacity(pulse ? 0.6 : 0.2), radius: size * 0.06)
            .scaleEffect(pulse ? 1.10 : 0.96)
            .onAppear {
                // Next runloop, so the forever-animation never captures the
                // view's own initial layout.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
    }
}

/// "Name's turn" capsule in the mover's colour. Each new turn slides in.
private struct Connect4TurnBanner: View {
    let bannerKey: String
    let text: String
    let colorID: String
    let isFinal: Bool

    var body: some View {
        ZStack {
            Connect4TurnBannerCapsule(text: text, colorID: colorID, isFinal: isFinal)
                .id(bannerKey)
                .transition(
                    .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity)
                )
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: bannerKey)
    }
}

private struct Connect4TurnBannerCapsule: View {
    let text: String
    let colorID: String
    let isFinal: Bool
    @State private var glow = false

    var body: some View {
        let palette = Connect4Palette.of(colorID)
        let tint: Color = colorID.isEmpty ? Color.white.opacity(0.6) : palette.glow
        return HStack(spacing: 18) {
            if isFinal && !colorID.isEmpty {
                Image(systemName: "crown.fill")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(palette.light)
            }
            if colorID.isEmpty {
                Image(systemName: "equal.circle.fill")
                    .font(.system(size: 36, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                Connect4Disc(colorID: colorID, size: 46)
            }
            Text(text)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.leading, 18)
        .padding(.trailing, 32)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(
                    LinearGradient(colors: [palette.base.opacity(colorID.isEmpty ? 0.15 : 0.45),
                                            palette.dark.opacity(colorID.isEmpty ? 0.15 : 0.55)],
                                   startPoint: .top, endPoint: .bottom)
                )
        )
        .overlay(Capsule().strokeBorder(tint.opacity(glow ? 0.95 : 0.45), lineWidth: 3))
        .shadow(color: tint.opacity(glow ? 0.75 : 0.25), radius: glow ? 26 : 10)
        .onAppear {
            // Next runloop, so the forever-animation never captures the
            // view's own initial layout.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: isFinal ? 0.6 : 1.1).repeatForever(autoreverses: true)) {
                    glow = true
                }
            }
        }
    }
}

private struct Connect4PlayerChip: View {
    let seat: Connect4Seat
    let isCurrent: Bool
    let isWinner: Bool
    let discCount: Int

    var body: some View {
        let palette = Connect4Palette.of(seat.colorID)
        let highlighted: Bool = isCurrent || isWinner
        return HStack(spacing: 16) {
            Connect4Disc(colorID: seat.colorID, size: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(highlighted ? .white : .white.opacity(0.7))
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(highlighted ? palette.light : .white.opacity(0.4))
            }
            Spacer(minLength: 8)
            scoreBadge
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius)
                .fill(highlighted ? palette.base.opacity(0.22) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius)
                .strokeBorder(highlighted ? palette.glow.opacity(0.9) : Color.white.opacity(0.08),
                              lineWidth: highlighted ? 3 : 1)
        )
        .shadow(color: highlighted ? palette.glow.opacity(0.45) : Color.clear, radius: 16)
        .scaleEffect(isCurrent ? 1.04 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCurrent)
    }

    private var statusText: String {
        if isWinner { return "WINNER" }
        if isCurrent { return "Dropping now" }
        return discCount == 1 ? "1 disc" : "\(discCount) discs"
    }

    private var scoreBadge: some View {
        VStack(spacing: 0) {
            Text("\(seat.score)")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("WINS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(width: 66)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: ShellTheme.chipRadius).fill(Color.black.opacity(0.25)))
    }
}

/// Slow drifting light blobs behind everything, one tinted with the colour
/// of the player to move.
private struct Connect4AmbientBackground: View {
    let accent: Color
    @State private var drift = false

    var body: some View {
        // The oversized blobs live in an overlay so they never grow the
        // board's layout past the screen.
        Color(hex: "02040d")
            .overlay(blobs)
            .clipped()
            .ignoresSafeArea()
            .onAppear {
                // Next runloop, so the forever-animation never captures the
                // view's own initial layout.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                        drift = true
                    }
                }
            }
    }

    private var blobs: some View {
        ZStack {
            blob(color: Color(hex: "1d4ed8").opacity(0.45), size: 1100)
                .offset(x: drift ? -420 : -560, y: drift ? -260 : -140)
            blob(color: Color(hex: "7c3aed").opacity(0.25), size: 900)
                .offset(x: drift ? 620 : 480, y: drift ? 320 : 180)
            blob(color: accent.opacity(0.22), size: 1000)
                .animation(.easeInOut(duration: 0.8), value: accent)
                .offset(x: drift ? 160 : 300, y: drift ? -120 : 60)
        }
    }

    private func blob(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, Color.clear], center: .center,
                                 startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}

// MARK: Four in a Row -- state

struct Connect4DropEvent {
    let row: Int
    let col: Int
    /// Monotonically increasing so SwiftUI's `onChange` fires even if a
    /// later drop happens to land in a cell with the same (row, col) as a
    /// previous one (a new game reusing the same grid, say).
    let counter: Int
}

struct Connect4Move: Equatable {
    let row: Int
    let col: Int
    let colorID: String
}

struct Connect4CellPoint: Identifiable, Equatable {
    let row: Int
    let col: Int
    var id: String { "\(row),\(col)" }
}

struct Connect4BoardState {
    var rows: Int = 6
    var cols: Int = 7
    var grid: [[String]] = Array(repeating: Array(repeating: "", count: 7), count: 6)
    var currentPlayerID = ""
    var currentPlayerName = ""
    var currentColorID = ""
    /// Older servers send the winner's *name* here; newer ones also send
    /// `winnerID` and `winnerColor`.
    var winner: String? = nil
    var winnerID: String? = nil
    var winnerColorID = ""
    var winCells: Set<String> = []
    var isDraw = false
    var colors: [String: String] = [:]
    var turnOrder: [String] = []
    var players: [Connect4Seat] = []
    var lastMove: Connect4Move? = nil

    mutating func update(from data: [String: AnyCodable]) {
        if let g = data["grid"]?.value as? [[String]] { grid = g }
        updateDimensions(from: data)
        if let v = data["currentPlayerID"]?.value as? String { currentPlayerID = v }
        if let v = data["currentPlayerName"]?.value as? String { currentPlayerName = v }
        if let v = data["currentColor"]?.value as? String { currentColorID = v }
        if data["winner"] != nil { winner = data["winner"]?.value as? String }
        if data["winnerID"] != nil { winnerID = data["winnerID"]?.value as? String }
        if let v = data["winnerColor"]?.value as? String { winnerColorID = v }
        if let v = data["winCells"]?.value as? [String] { winCells = Set(v) }
        if let v = data["isDraw"]?.value as? Bool { isDraw = v }
        if let v = data["colors"]?.value as? [String: String] { colors = v }
        if let v = data["turnOrder"]?.value as? [String] { turnOrder = v }
        if let v = data["players"]?.value as? [[String: Any]] { players = Self.parsePlayers(v) }
        if data["lastMove"] != nil { lastMove = Self.parseMove(data["lastMove"]?.value) }
        if currentColorID.isEmpty, let c = colors[currentPlayerID] { currentColorID = c }
    }

    private mutating func updateDimensions(from data: [String: AnyCodable]) {
        let gridRows: Int = grid.count
        let gridCols: Int = grid.first?.count ?? 0
        if let r = data["rows"]?.value as? Int, r > 0 {
            rows = r
        } else if gridRows > 0 {
            rows = gridRows
        }
        if let c = data["cols"]?.value as? Int, c > 0 {
            cols = c
        } else if gridCols > 0 {
            cols = gridCols
        }
    }

    private static func parsePlayers(_ raw: [[String: Any]]) -> [Connect4Seat] {
        var seats: [Connect4Seat] = []
        for entry in raw {
            guard let id = entry["id"] as? String else { continue }
            let name: String = entry["name"] as? String ?? "Player"
            let score: Int = entry["score"] as? Int ?? 0
            seats.append(Connect4Seat(id: id, name: name, score: score, colorID: ""))
        }
        return seats
    }

    private static func parseMove(_ raw: Any?) -> Connect4Move? {
        guard let dict = raw as? [String: Any],
              let row = dict["row"] as? Int,
              let col = dict["col"] as? Int else { return nil }
        return Connect4Move(row: row, col: col, colorID: dict["color"] as? String ?? "")
    }

    /// Safe lookup: "" for anything outside the grid the server sent.
    func cell(row: Int, col: Int) -> String {
        guard row >= 0, row < grid.count else { return "" }
        let line = grid[row]
        guard col >= 0, col < line.count else { return "" }
        return line[col]
    }

    func discCount(of colorID: String) -> Int {
        guard !colorID.isEmpty else { return 0 }
        var count = 0
        for line in grid {
            for value in line where value == colorID { count += 1 }
        }
        return count
    }

    var filledCount: Int {
        var count = 0
        for line in grid {
            for value in line where !value.isEmpty { count += 1 }
        }
        return count
    }

    var winCellPoints: [Connect4CellPoint] {
        var points: [Connect4CellPoint] = []
        for key in winCells.sorted() {
            let parts = key.split(separator: ",")
            guard parts.count == 2, let r = Int(parts[0]), let c = Int(parts[1]) else { continue }
            points.append(Connect4CellPoint(row: r, col: c))
        }
        return points
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
    /// empty to non-empty. Four in a Row only ever drops one disc per turn, so
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

// MARK: - Mafia Board

struct TVMafiaBoardView: View {
    let room: Room
    @StateObject private var vm = MafiaBoardViewModel()

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mafia").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text(vm.state.phase == "day" ? "Day \(vm.state.round) — Vote to eliminate"
                         : "Night — Mafia is choosing")
                        .font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.5))
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
                    Text("Vote Tally").font(.system(.headline, design: .rounded)).foregroundColor(.white.opacity(0.5))
                    ForEach(vm.state.votes.sorted(by: { $0.value > $1.value }), id: \.key) { name, count in
                        HStack {
                            Text(name).foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(0..<count, id: \.self) { _ in
                                    Circle().fill(TVTheme.red).frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius).fill(Color.white.opacity(0.05)))
                .padding(.horizontal, 60)
            }

            if let eliminated = vm.state.lastEliminated {
                Text("\(eliminated) was eliminated!")
                    .font(.system(.title3, design: .rounded, weight: .bold)).foregroundColor(TVTheme.red)
            }

            Spacer()
        }
        .background((vm.state.phase == "day" ? TVTheme.bg : Color(hex: "00000a")).ignoresSafeArea())
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
                    .fill(player.isAlive ? Color.white.opacity(0.1) : TVTheme.red.opacity(0.15))
                    .frame(width: 64, height: 64)
                Text(player.isAlive ? String(player.name.prefix(1)) : "–")
                    .font(.system(.title, design: .rounded, weight: .bold)).foregroundColor(.white)
            }
            Text(player.name).font(.system(.subheadline, design: .rounded))
                .foregroundColor(player.isAlive ? .white : .white.opacity(0.3))
                .strikethrough(!player.isAlive)
            if let role = player.revealedRole {
                Text(role).font(.system(.caption2, design: .rounded, weight: .bold)).foregroundColor(TVTheme.red)
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

// MARK: - Raja Mantri Board

struct TVRajaMantriBoard: View {
    let room: Room
    @StateObject private var vm = RajaMantriViewModel()

    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Text("Raja Mantri").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundColor(.white)
                Spacer()
                Text("Round \(vm.state.round)").font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 60).padding(.top, 40)

            Text(vm.state.phaseLabel).font(.system(.title2, design: .rounded)).foregroundColor(TVTheme.cyan.opacity(0.8))

            // Player role cards (revealed after round ends)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(room.players.count, 4)),
                      spacing: 20) {
                ForEach(vm.state.playerRoles) { p in
                    RajaMantriPlayerCard(player: p)
                }
            }
            .padding(.horizontal, 60)

            if let result = vm.state.roundResult {
                Text(result).font(.system(.title3, design: .rounded, weight: .bold)).foregroundColor(TVTheme.yellow)
            }

            // Score table
            VStack(spacing: 10) {
                ForEach(room.players.sorted(by: { $0.score > $1.score })) { p in
                    HStack {
                        Text(p.name).foregroundColor(.white)
                        Spacer()
                        Text("\(p.score) pts").font(.system(.headline, design: .rounded, weight: .bold)).foregroundColor(TVTheme.cyan)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius).fill(Color.white.opacity(0.04)))
            .padding(.horizontal, 60)

            Spacer()
        }
        .background(TVTheme.bg.ignoresSafeArea())
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
            Text(player.revealedRole.map { roleEmoji($0) } ?? "?").font(.system(size: 48, weight: .regular, design: .rounded))
            Text(player.name).font(.system(.headline, design: .rounded)).foregroundColor(.white)
            if let role = player.revealedRole {
                Text(role).font(.system(.caption, design: .rounded, weight: .bold)).foregroundColor(roleColor(role))
            }
            if player.isAccused {
                Text("← ACCUSED").font(.system(.caption2, design: .rounded, weight: .bold)).foregroundColor(TVTheme.red)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius).fill(Color.white.opacity(0.06)))
    }

    private func roleEmoji(_ r: String) -> String {
        switch r { case "Raja": return "R"; case "Mantri": return "M"; case "Chor": return "C"; default: return "?" }
    }
    private func roleColor(_ r: String) -> Color {
        switch r { case "Raja": return TVTheme.yellow; case "Mantri": return TVTheme.purple; case "Chor": return TVTheme.red; default: return TVTheme.cyan }
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
                Text("Tambola").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(.white)

                if let last = vm.state.lastCalled {
                    VStack(spacing: 8) {
                        Text("\(last)").font(.system(size: 96, weight: .black, design: .rounded))
                            .foregroundColor(TVTheme.yellow)
                        Text("Last Called").font(.system(.subheadline, design: .rounded)).foregroundColor(.white.opacity(0.4))
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: ShellTheme.cardRadius).fill(TVTheme.yellow.opacity(0.1)))
                }

                Text("Called: \(vm.state.calledNumbers.count)").font(.system(.body, design: .rounded)).foregroundColor(.white.opacity(0.5))

                Spacer()

                // Prize board: every prize and who took it.
                if vm.state.prizes.isEmpty {
                    ForEach(vm.state.claims, id: \.self) { claim in
                        Text("\(claim)").font(.system(.headline, design: .rounded)).foregroundColor(TVTheme.green)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(vm.state.prizes, id: \.label) { prize in
                            HStack(spacing: 10) {
                                Image(systemName: prize.winner == nil ? "circle" : "checkmark.seal.fill")
                                    .foregroundColor(prize.winner == nil ? .white.opacity(0.3) : TVTheme.green)
                                Text(prize.label).font(.system(.headline, design: .rounded))
                                    .foregroundColor(prize.winner == nil ? .white : .white.opacity(0.5))
                                Spacer()
                                Text(prize.winner ?? "open").font(.system(.headline, design: .rounded))
                                    .foregroundColor(prize.winner == nil ? .white.opacity(0.3) : TVTheme.green)
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
                                  ? TVTheme.yellow : Color.white.opacity(0.06)))
                }
            }
            .padding(24)
        }
        .padding(60)
        .background(TVTheme.bg.ignoresSafeArea())
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

// MARK: - Mind Meld Board

struct TVMindMeldBoardView: View {
    let room: Room
    @StateObject private var vm = MindMeldBoardViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Text("Mind Meld").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(.white)
                .padding(.top, 40)

            if let category = vm.state.category {
                Text("Category: \(category)").font(.system(.title2, design: .rounded)).foregroundColor(TVTheme.cyan)
            }

            if vm.state.showReveal {
                // Reveal all words
                VStack(spacing: 16) {
                    Text("Words submitted:").font(.system(.headline, design: .rounded)).foregroundColor(.white.opacity(0.5))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(vm.state.submissions) { sub in
                            VStack(spacing: 4) {
                                Text(sub.word).font(.system(.title2, design: .rounded, weight: .bold)).foregroundColor(.white)
                                Text(sub.playerName).font(.system(.caption, design: .rounded)).foregroundColor(.white.opacity(0.5))
                                if sub.isMeld {
                                    Text("MELD +\(sub.meldCount)!").font(.system(.caption, design: .rounded, weight: .bold)).foregroundColor(TVTheme.green)
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(sub.isMeld ? TVTheme.green.opacity(0.2) : Color.white.opacity(0.06)))
                        }
                    }
                }
                .padding(.horizontal, 60)
            } else {
                // Waiting for submissions
                VStack(spacing: 16) {
                    let submitted = vm.state.submissions.count
                    let total = room.players.count
                    Text("\(submitted) / \(total) submitted").font(.system(.title2, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 12) {
                        ForEach(room.players) { p in
                            VStack(spacing: 6) {
                                Image(systemName: vm.state.submittedIDs.contains(p.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(.system(.title, design: .rounded)).foregroundColor(vm.state.submittedIDs.contains(p.id) ? TVTheme.green : .white.opacity(0.3))
                                Text(p.name).font(.system(.caption, design: .rounded)).foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                }
            }

            TVScoreHeader(players: room.players, currentPlayerID: nil)

            Spacer()
        }
        .background(TVTheme.bg.ignoresSafeArea())
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

// MARK: - Speed Sculptor Board

struct TVSpeedSculptorBoardView: View {
    let room: Room
    @StateObject private var vm = SpeedSculptorBoardViewModel()

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Speed Sculptor").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(.white)
                Spacer()
                if let prompt = vm.state.prompt {
                    Text("Drawing: \(prompt)").font(.system(.title2, design: .rounded, weight: .bold)).foregroundColor(TVTheme.yellow)
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
                    Text("Players are drawing…").font(.system(.title2, design: .rounded)).foregroundColor(.white.opacity(0.5))
                    let submitted = vm.state.submittedCount
                    Text("\(submitted) / \(room.players.count) submitted")
                        .font(.system(.subheadline, design: .rounded)).foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .background(TVTheme.bg.ignoresSafeArea())
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
                Text(drawing.playerName).font(.system(.headline, design: .rounded)).foregroundColor(.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "hand.thumbsup.fill").foregroundColor(TVTheme.cyan)
                    Text("\(drawing.voteCount)").font(.system(.headline, design: .rounded, weight: .bold)).foregroundColor(TVTheme.cyan)
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
                .stroke(progress > 0.4 ? TVTheme.cyan : TVTheme.red,
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
