import SwiftUI

/// Chess on the TV: the shared board everyone watches while the two players
/// move from their phones. Reads `board`, `pieceColors`, `turnColor`,
/// `lastMove`, `captured` and `inCheck` from ChessEngine.public_state.

struct ChessBoardState {
    var board: [[String]] = Array(repeating: Array(repeating: "", count: 8), count: 8)
    var pieceColors: [String: String] = [:]
    var turnColor: String? = nil
    var lastMove: [[Int]] = []
    var capturedByWhite: [String] = []
    var capturedByBlack: [String] = []
    var inCheck = false
    var draw = false
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let rows = d["board"]?.value as? [Any] {
            let parsed = rows.map { row -> [String] in
                (row as? [Any] ?? []).map { $0 as? String ?? "" }
            }
            if parsed.count == 8 { board = parsed }
        }
        if let colors = d["pieceColors"]?.value as? [String: Any] {
            var out: [String: String] = [:]
            for (k, v) in colors { if let s = v as? String { out[k] = s } }
            pieceColors = out
        }
        turnColor = d["turnColor"]?.value as? String
        lastMove = (d["lastMove"]?.value as? [Any] ?? []).map { sq in
            (sq as? [Any] ?? []).compactMap { $0 as? Int }
        }
        if let cap = d["captured"]?.value as? [String: Any] {
            capturedByWhite = (cap["white"] as? [Any] ?? []).compactMap { $0 as? String }
            capturedByBlack = (cap["black"] as? [Any] ?? []).compactMap { $0 as? String }
        }
        inCheck = d["inCheck"]?.value as? Bool ?? false
        draw = d["draw"]?.value as? Bool ?? false
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
    }

    func name(for color: String) -> String {
        guard let pid = pieceColors.first(where: { $0.value == color })?.key else {
            return color.capitalized
        }
        return players.first(where: { $0.id == pid })?.name ?? color.capitalized
    }

    func isLastMove(_ row: Int, _ col: Int) -> Bool {
        lastMove.contains { $0.count == 2 && $0[0] == row && $0[1] == col }
    }
}

/// Server glyph -> (filled glyph, isWhite). Both sides are drawn with the
/// solid glyph shapes and tinted, which reads far better at TV distance than
/// the hollow "white" outlines.
private func chessGlyph(_ piece: String) -> (glyph: String, isWhite: Bool)? {
    let white: [String: String] = [
        "\u{2654}": "\u{265A}", "\u{2655}": "\u{265B}", "\u{2656}": "\u{265C}",
        "\u{2657}": "\u{265D}", "\u{2658}": "\u{265E}", "\u{2659}": "\u{265F}",
    ]
    let black: Set<String> = ["\u{265A}", "\u{265B}", "\u{265C}", "\u{265D}", "\u{265E}", "\u{265F}"]
    if let solid = white[piece] { return (solid + "\u{FE0E}", true) }
    if black.contains(piece) { return (piece + "\u{FE0E}", false) }
    return nil
}

private struct ChessPieceText: View {
    let piece: String
    let size: CGFloat

    var body: some View {
        if let g = chessGlyph(piece) {
            Text(g.glyph)
                .font(.system(size: size))
                .foregroundColor(g.isWhite ? Color(hex: "fdf8ec") : Color(hex: "1b1b1f"))
                .shadow(color: g.isWhite ? .black.opacity(0.85) : .white.opacity(0.35),
                        radius: 1.5)
        }
    }
}

struct TVChessBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: ChessBoardState()) { $0.update(from: $1) }

    private let cell: CGFloat = 104
    private let files = ["a", "b", "c", "d", "e", "f", "g", "h"]

    var body: some View {
        HStack(spacing: 60) {
            board
            sidePanel.frame(width: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: "14101f"), Color(hex: "07060c")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private var board: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    Text("\(8 - row)")
                        .font(.headline).foregroundColor(.white.opacity(0.4))
                        .frame(width: 34)
                    ForEach(0..<8, id: \.self) { col in
                        square(row: row, col: col)
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 34)
                ForEach(files, id: \.self) { f in
                    Text(f).font(.headline).foregroundColor(.white.opacity(0.4))
                        .frame(width: cell, height: 34)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "3b2a1a")))
        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
    }

    private func square(row: Int, col: Int) -> some View {
        let isLight = (row + col) % 2 == 0
        let piece = vm.state.board[row][col]
        let highlighted = vm.state.isLastMove(row, col)
        let base = isLight ? Color(hex: "f0d9b5") : Color(hex: "b58863")
        return ZStack {
            Rectangle().fill(base)
            if highlighted {
                Rectangle().fill(TVTheme.yellow.opacity(0.42))
            }
            ChessPieceText(piece: piece, size: 76)
        }
        .frame(width: cell, height: cell)
        .animation(.easeInOut(duration: 0.25), value: piece)
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 14) {
                Image(systemName: "checkerboard.rectangle").font(.system(size: 40))
                Text("Chess").font(.system(size: 52, weight: .heavy))
            }
            .foregroundColor(.white)

            playerRow(color: "black")
            playerRow(color: "white")

            statusBanner

            if !vm.state.capturedByWhite.isEmpty || !vm.state.capturedByBlack.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CAPTURED").font(.caption.bold()).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    capturedRow(vm.state.capturedByWhite)
                    capturedRow(vm.state.capturedByBlack)
                }
            }
            Spacer()
            Text("Move on your phone: tap a piece, then its destination. Pawns promote to queens. Capture the king to win.")
                .font(.callout).foregroundColor(.white.opacity(0.35))
        }
        .padding(.vertical, 60)
    }

    private func playerRow(color: String) -> some View {
        let active = vm.state.turnColor == color && vm.state.winner == nil
        return HStack(spacing: 16) {
            Circle()
                .fill(color == "white" ? Color(hex: "fdf8ec") : Color(hex: "1b1b1f"))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 2))
                .frame(width: 34, height: 34)
            Text(vm.state.name(for: color))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(active ? TVTheme.yellow : .white.opacity(0.8))
                .lineLimit(1)
            Spacer()
            if active {
                Text("TO MOVE").font(.caption.bold()).tracking(2)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(TVTheme.yellow))
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(active ? TVTheme.yellow.opacity(0.12) : Color.white.opacity(0.05)))
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let winner = vm.state.winner {
            let name = vm.state.players.first(where: { $0.id == winner })?.name ?? "Winner"
            Label("\(name) captured the king!", systemImage: "crown.fill")
                .font(.title2.bold()).foregroundColor(TVTheme.yellow)
        } else if vm.state.draw {
            Label("Stalemate: no legal moves", systemImage: "equal.circle.fill")
                .font(.title2.bold()).foregroundColor(TVTheme.cyan)
        } else if vm.state.inCheck {
            Label("Check! \(vm.state.name(for: vm.state.turnColor ?? "white")) must save the king",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold()).foregroundColor(TVTheme.red)
        }
    }

    private func capturedRow(_ pieces: [String]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, p in
                ChessPieceText(piece: p, size: 36)
            }
        }
    }
}
