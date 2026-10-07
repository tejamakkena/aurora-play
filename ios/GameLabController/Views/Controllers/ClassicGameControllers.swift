import SwiftUI
import UIKit

// MARK: - Shared chrome (Phone Play look)
//
// The classic controllers predate ControllerShell and several of them need
// a trailing item in the header (a disc, a score, a chip count), which
// ControllerShell has no slot for. ClassicShell is the same header card,
// backdrop and type as ControllerShell, plus that trailing slot.

private struct ClassicShell<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    /// A soft wash of colour from the top of the screen (Mafia's day/night).
    var glow: Color = .clear
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
                    .padding(.horizontal, 10)
            )
            .padding(.top, 6)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            ZStack {
                PhonePlayDesign.bg
                LinearGradient(colors: [glow.opacity(0.16), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        )
    }
}

/// A rounded status capsule: "Your move", "Waiting for Priya", hints.
private struct ClassicPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = PhonePlayDesign.text2

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
            }
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// Small number-over-label badge for the header's trailing slot.
private struct ClassicStatBadge: View {
    let value: String
    let label: String
    var tint: Color = PhonePlayDesign.cyan

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundColor(PhonePlayDesign.text3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                .fill(tint.opacity(0.12))
        )
        .animation(PhonePlayDesign.pop, value: value)
    }
}

/// The big gently-bobbing icon used for "sleeping", "eliminated", "won".
private struct ClassicHero: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 110

    var body: some View {
        ZStack {
            Circle()
                .fill(PhonePlayDesign.gradient([tint.opacity(0.6), tint.opacity(0.25)]))
                .frame(width: size, height: size)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundColor(.white)
        }
        .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
        .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
    }
}

/// A full-width pick-one row (vote, target, accuse) with a tint per role.
private struct ClassicPickRow: View {
    let text: String
    let tint: Color
    var selected: Bool = false
    /// Shown next to the check mark when selected ("Your vote").
    var badge: String? = nil
    /// Trailing icon when not selected.
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 12) {
                Text(text)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if selected {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        if let badge {
                            Text(badge)
                        }
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(tint)
                    .transition(.scale.combined(with: .opacity))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(tint.opacity(0.85))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(selected ? tint.opacity(0.2) : PhonePlayDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(selected ? tint : Color.white.opacity(0.06),
                                  lineWidth: selected ? 2 : 1)
            )
            .animation(PhonePlayDesign.pop, value: selected)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

/// Scrolls when the content is taller than the screen (a long player list,
/// a long guess history) and centres it vertically when it is not.
private struct ClassicCenteredScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private extension View {
    /// The standard Phone Play surface card behind a panel.
    func classicCard(_ fill: Color = PhonePlayDesign.surface) -> some View {
        background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(fill)
        )
    }
}

// MARK: - Connect 4 Controller

/// Phone palette for the server's disc colour ids (matches the TV board).
private struct Connect4PhonePalette {
    let base: Color
    let light: Color
    let dark: Color

    static func of(_ id: String) -> Connect4PhonePalette {
        switch id {
        case "red":
            return Connect4PhonePalette(base: Color(hex: "e8283b"), light: Color(hex: "ff8a8f"), dark: Color(hex: "7a0b16"))
        case "yellow":
            return Connect4PhonePalette(base: Color(hex: "ffc61a"), light: Color(hex: "fff1a8"), dark: Color(hex: "9a6a00"))
        case "green":
            return Connect4PhonePalette(base: Color(hex: "1fc96b"), light: Color(hex: "9cf5c2"), dark: Color(hex: "0a6634"))
        case "blue":
            return Connect4PhonePalette(base: Color(hex: "35b4ff"), light: Color(hex: "c4ecff"), dark: Color(hex: "0b5c9e"))
        default:
            return Connect4PhonePalette(base: Color(hex: "8a94a6"), light: Color(hex: "d5dbe6"), dark: Color(hex: "3c4454"))
        }
    }
}

/// Small glossy disc, same look as the TV's.
private struct Connect4PhoneDisc: View {
    let colorID: String
    let size: CGFloat

    var body: some View {
        let palette = Connect4PhonePalette.of(colorID)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [palette.light, palette.base, palette.dark],
                                   center: UnitPoint(x: 0.36, y: 0.30),
                                   startRadius: 0, endRadius: size * 0.72)
                )
            Circle()
                .strokeBorder(palette.dark.opacity(0.75), lineWidth: max(1, size * 0.05))
            Ellipse()
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.0)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: size * 0.52, height: size * 0.30)
                .offset(x: -size * 0.09, y: -size * 0.23)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.4), radius: size * 0.06, x: 0, y: size * 0.05)
    }
}

/// Aim by dragging (or tapping) across the column strip; the disc drops
/// when you let go. The strip sizes itself to however many columns the
/// board has (7, 9 or 10) and is disabled while it isn't your turn.
struct Connect4ControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var aimedCol: Int? = nil

    private var isMyTurn: Bool { privateData["isMyTurn"] as? Bool ?? false }
    private var myColor: String { privateData["color"] as? String ?? "red" }
    private var columnCount: Int {
        let cols: Int = privateData["cols"] as? Int ?? 7
        return min(max(cols, 1), 16)
    }
    private var columnsFull: Set<Int> {
        Set((privateData["fullColumns"] as? [Int]) ?? [])
    }
    private var currentName: String { privateData["currentPlayerName"] as? String ?? "" }
    private var currentColor: String { privateData["currentColor"] as? String ?? "" }
    private var turnOrder: [String] { privateData["turnOrder"] as? [String] ?? [] }
    private var colors: [String: String] { privateData["colors"] as? [String: String] ?? [:] }
    private var currentID: String { privateData["currentPlayerID"] as? String ?? "" }

    var body: some View {
        ClassicShell(title: "Connect 4",
                     subtitle: "You are \(myColor.capitalized)",
                     trailing: {
                         Connect4PhoneDisc(colorID: myColor, size: 32)
                             .phonePlayIdle(dy: 2, duration: 1.4)
                     }) {
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                statusLine
                    .padding(.bottom, 18)
                columnPicker
                    .padding(12)
                    .classicCard()
                    .padding(.horizontal, 14)
                turnOrderStrip
                    .padding(.top, 18)
                Spacer(minLength: 12)
            }
            .animation(PhonePlayDesign.pop, value: isMyTurn)
        }
        .onChange(of: isMyTurn) { _, mine in
            if !mine { aimedCol = nil }
            if mine { PhonePlayHaptics.thump() }
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        if isMyTurn {
            VStack(spacing: 4) {
                Text("Your move!")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(Connect4PhonePalette.of(myColor).light)
                Text("Drag to aim, let go to drop")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else if !currentName.isEmpty {
            HStack(spacing: 10) {
                if !currentColor.isEmpty {
                    Connect4PhoneDisc(colorID: currentColor, size: 20)
                }
                Text("Waiting for \(currentName)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(PhonePlayDesign.surface))
            .transition(.opacity)
        } else {
            ClassicPill(text: "Waiting...", systemImage: "hourglass")
                .transition(.opacity)
        }
    }

    // MARK: Column picker

    private var columnPicker: some View {
        GeometryReader { geo in
            pickerStrip(width: geo.size.width)
        }
        .frame(height: 260)
        .opacity(isMyTurn ? 1.0 : 0.35)
        .allowsHitTesting(isMyTurn)
        .animation(.easeInOut(duration: 0.2), value: isMyTurn)
    }

    private func pickerStrip(width: CGFloat) -> some View {
        let count: Int = columnCount
        let spacing: CGFloat = count > 8 ? 4 : 6
        let totalSpacing: CGFloat = spacing * CGFloat(max(count - 1, 0))
        let colWidth: CGFloat = max(10, (width - totalSpacing) / CGFloat(max(count, 1)))
        return HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { col in
                columnView(col: col, width: colWidth)
            }
        }
        .frame(width: width, height: 260, alignment: .center)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    aim(at: value.location.x, colWidth: colWidth, spacing: spacing)
                }
                .onEnded { value in
                    aim(at: value.location.x, colWidth: colWidth, spacing: spacing)
                    releaseDrop()
                }
        )
    }

    private func columnView(col: Int, width: CGFloat) -> some View {
        let full: Bool = columnsFull.contains(col)
        let aimed: Bool = aimedCol == col && !full
        let palette = Connect4PhonePalette.of(myColor)
        let discSize: CGFloat = min(width * 0.9, 34)
        let radius: CGFloat = min(12, width * 0.32)
        return VStack(spacing: 6) {
            ZStack {
                if aimed {
                    Connect4PhoneDisc(colorID: myColor, size: discSize)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.white.opacity(full ? 0.1 : 0.35))
                }
            }
            .frame(height: 36)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(columnFill(full: full, aimed: aimed, palette: palette))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(aimed ? palette.light.opacity(0.9) : Color.white.opacity(0.08),
                                      lineWidth: aimed ? 2 : 1)
                )
                .overlay(
                    full ? Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white.opacity(0.25)) : nil
                )
                .shadow(color: aimed ? palette.base.opacity(0.45) : .clear, radius: 10, y: 4)
            Text("\(col + 1)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(aimed ? .white : PhonePlayDesign.text3)
        }
        .frame(width: width)
        .animation(PhonePlayDesign.pop, value: aimed)
    }

    private func columnFill(full: Bool, aimed: Bool, palette: Connect4PhonePalette) -> LinearGradient {
        if full {
            return LinearGradient(colors: [Color.white.opacity(0.03), Color.white.opacity(0.03)],
                                  startPoint: .top, endPoint: .bottom)
        }
        if aimed {
            return LinearGradient(colors: [palette.base.opacity(0.75), palette.dark.opacity(0.55)],
                                  startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [PhonePlayDesign.blue.opacity(0.32), PhonePlayDesign.indigo.opacity(0.18)],
                              startPoint: .top, endPoint: .bottom)
    }

    // MARK: Turn order

    @ViewBuilder
    private var turnOrderStrip: some View {
        if !turnOrder.isEmpty {
            HStack(spacing: 12) {
                ForEach(Array(turnOrder.enumerated()), id: \.offset) { item in
                    turnDot(playerID: item.element)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(PhonePlayDesign.surface))
            .animation(PhonePlayDesign.pop, value: currentID)
        }
    }

    private func turnDot(playerID: String) -> some View {
        let isCurrent: Bool = playerID == currentID
        let colorID: String = colors[playerID] ?? ""
        return Connect4PhoneDisc(colorID: colorID, size: isCurrent ? 26 : 18)
            .opacity(isCurrent ? 1.0 : 0.5)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(isCurrent ? 0.9 : 0.0), lineWidth: 2)
                    .padding(-4)
            )
    }

    // MARK: Actions

    private func aim(at x: CGFloat, colWidth: CGFloat, spacing: CGFloat) {
        let pitch: CGFloat = colWidth + spacing
        guard pitch > 0 else { return }
        let raw: Int = Int((x / pitch).rounded(.down))
        let col: Int = min(max(raw, 0), columnCount - 1)
        if col != aimedCol {
            aimedCol = col
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func releaseDrop() {
        guard isMyTurn, let col = aimedCol, !columnsFull.contains(col) else {
            aimedCol = nil
            return
        }
        aimedCol = nil
        PhonePlayHaptics.rigid()
        onAction("drop", ["column": col])
    }
}

// MARK: - Chess Controller

/// Draws a chess piece from the server's Unicode glyph. Both sides are drawn
/// with the solid glyph, coloured white or ink, so a white piece stays
/// readable on a light square (the outline glyph used to render white on
/// tan) and the black pawn never falls back to its emoji form.
private struct ChessPieceGlyph: View {
    let piece: String

    private static let whiteRange: ClosedRange<UInt32> = 0x2654...0x2659
    private static let chessRange: ClosedRange<UInt32> = 0x2654...0x265F

    private var scalar: UInt32 { piece.unicodeScalars.first?.value ?? 0 }
    private var isWhite: Bool { ChessPieceGlyph.whiteRange.contains(scalar) }
    private var isChess: Bool { ChessPieceGlyph.chessRange.contains(scalar) }

    /// The solid glyph for this piece, plus a text-presentation selector.
    private var solid: String {
        var base: String = piece
        if isWhite, let s = Unicode.Scalar(scalar + 6) {
            base = String(Character(s))
        }
        return base + "\u{FE0E}"
    }

    var body: some View {
        if isChess {
            Text(solid)
                .font(.system(size: 30))
                .minimumScaleFactor(0.5)
                .foregroundColor(isWhite ? GamePieceColors.chessWhite : GamePieceColors.chessBlack)
                .shadow(color: isWhite ? Color.black.opacity(0.75) : Color.white.opacity(0.35),
                        radius: 1, x: 0, y: 0.5)
        } else {
            Text(piece)
                .font(.system(size: 28))
                .minimumScaleFactor(0.5)
                .foregroundColor(.black)
        }
    }
}

struct ChessControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isMyTurn: Bool { privateData["isMyTurn"] as? Bool ?? false }
    private var myColor: String { privateData["pieceColor"] as? String ?? "white" }
    private var board: [[String]] {
        privateData["board"] as? [[String]] ?? Array(repeating: Array(repeating: "", count: 8), count: 8)
    }
    private var validMoves: [[Int]] {
        privateData["validMoves"] as? [[Int]] ?? []
    }

    @State private var selectedSquare: [Int]? = nil

    private var validMoveSet: Set<String> {
        // Defensive: the server should always send [row, col] pairs, but a
        // malformed entry used to crash on $0[0]/$0[1].
        Set(validMoves.compactMap { $0.count >= 2 ? "\($0[0]),\($0[1])" : nil })
    }

    private func pieceAt(row: Int, col: Int) -> String {
        guard row < board.count, col < board[row].count else { return "" }
        return board[row][col]
    }

    var body: some View {
        ClassicShell(title: "Chess",
                     subtitle: isMyTurn ? "Your move" : "Opponent's move",
                     trailing: { colorBadge }) {
            VStack(spacing: 14) {
                Group {
                    if isMyTurn {
                        ClassicPill(text: selectedSquare == nil ? "Tap your piece" : "Tap destination",
                                    systemImage: "hand.tap.fill", tint: PhonePlayDesign.cyan)
                    } else {
                        ClassicPill(text: "Opponent thinking…", systemImage: "hourglass")
                    }
                }
                .padding(.top, 14)

                boardView

                if let sel = selectedSquare {
                    Button(action: {
                        PhonePlayHaptics.tap()
                        selectedSquare = nil
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Deselect \(chessCellLabel(sel[0], sel[1]))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color.white.opacity(0.07))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        )
                    }
                    .buttonStyle(PhonePlayPressStyle())
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }

                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: isMyTurn)
            .animation(PhonePlayDesign.pop, value: selectedSquare)
        }
    }

    /// Fixed: the black badge used to draw black text on a black capsule.
    private var colorBadge: some View {
        let white: Bool = myColor == "white"
        return HStack(spacing: 6) {
            Circle()
                .fill(white ? GamePieceColors.chessWhite : GamePieceColors.chessBlack)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                .frame(width: 14, height: 14)
            Text(myColor.capitalized)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(white ? .black : .white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(white ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                .overlay(Capsule().strokeBorder(Color.white.opacity(white ? 0 : 0.3), lineWidth: 1))
        )
    }

    private var boardView: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        square(row: row, col: col)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(8)
        .classicCard()
        .padding(.horizontal, 12)
    }

    private func square(row: Int, col: Int) -> some View {
        let piece: String = pieceAt(row: row, col: col)
        let isSelected: Bool = selectedSquare == [row, col]
        let isValidTarget: Bool = validMoveSet.contains("\(row),\(col)")
        let isLight: Bool = (row + col) % 2 == 0
        return Button(action: {
            PhonePlayHaptics.tap()
            tapSquare(row: row, col: col)
        }) {
            ZStack {
                Rectangle().fill(
                    isSelected ? PhonePlayDesign.yellow.opacity(0.75) :
                    isValidTarget ? PhonePlayDesign.green.opacity(0.45) :
                    isLight ? GamePieceColors.chessLightSquare : GamePieceColors.chessDarkSquare
                )
                if !piece.isEmpty {
                    ChessPieceGlyph(piece: piece)
                }
                if isValidTarget && piece.isEmpty {
                    Circle().fill(PhonePlayDesign.green.opacity(0.75)).frame(width: 13, height: 13)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!isMyTurn)
    }

    private func tapSquare(row: Int, col: Int) {
        guard isMyTurn else { return }
        let piece = pieceAt(row: row, col: col)
        if let sel = selectedSquare {
            if validMoveSet.contains("\(row),\(col)") {
                onAction("move", ["from": sel, "to": [row, col]])
                selectedSquare = nil
            } else if !piece.isEmpty {
                // Re-select different own piece
                onAction("select", ["row": row, "col": col])
                selectedSquare = [row, col]
            } else {
                selectedSquare = nil
            }
        } else if !piece.isEmpty {
            onAction("select", ["row": row, "col": col])
            selectedSquare = [row, col]
        }
    }

    private func chessCellLabel(_ row: Int, _ col: Int) -> String {
        let files = ["a","b","c","d","e","f","g","h"]
        return "\(files[col])\(8 - row)"
    }
}

// MARK: - Memory Controller

struct MemoryControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isMyTurn: Bool { privateData["isMyTurn"] as? Bool ?? false }
    private var myScore: Int { privateData["myScore"] as? Int ?? 0 }
    private var flippedIndices: Set<Int> {
        Set((privateData["flipped"] as? [Int]) ?? [])
    }
    private var matchedIndices: Set<Int> {
        Set((privateData["matched"] as? [Int]) ?? [])
    }
    private var cardCount: Int { privateData["cardCount"] as? Int ?? 16 }
    private var cardValues: [String] {
        privateData["cardValues"] as? [String] ?? Array(repeating: "?", count: cardCount)
    }

    private let cols = 4

    var body: some View {
        ClassicShell(title: "Memory",
                     subtitle: isMyTurn ? "Your turn" : "Opponent's turn",
                     trailing: { ClassicStatBadge(value: "\(myScore)", label: "PAIRS") }) {
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                Group {
                    if isMyTurn {
                        ClassicPill(text: "Flip two cards!", systemImage: "hand.tap.fill",
                                    tint: PhonePlayDesign.green)
                    } else {
                        ClassicPill(text: "Opponent's turn…", systemImage: "hourglass")
                    }
                }
                .transition(.opacity)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
                    ForEach(0..<cardCount, id: \.self) { idx in
                        let revealed = flippedIndices.contains(idx) || matchedIndices.contains(idx)
                        let matched = matchedIndices.contains(idx)

                        Button(action: {
                            PhonePlayHaptics.tap()
                            tapCard(idx)
                        }) {
                            MemoryTile(value: idx < cardValues.count ? cardValues[idx] : "?",
                                       revealed: revealed, matched: matched)
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .disabled(!isMyTurn || revealed)
                    }
                }
                .padding(12)
                .classicCard()
                .padding(.horizontal, 14)

                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: isMyTurn)
        }
    }

    private func tapCard(_ index: Int) {
        guard isMyTurn, !flippedIndices.contains(index), !matchedIndices.contains(index) else { return }
        onAction("flip", ["index": index])
    }
}

/// One Memory card, turned over with the Phone Play flip.
private struct MemoryTile: View {
    let value: String
    let revealed: Bool
    let matched: Bool

    var body: some View {
        PhonePlayFlip(flipped: revealed, front: cardBack, back: cardFace, duration: 0.4)
            .frame(height: 70)
            .animation(PhonePlayDesign.pop, value: matched)
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
            .fill(PhonePlayDesign.gradient([PhonePlayDesign.indigo.opacity(0.6),
                                            PhonePlayDesign.purple.opacity(0.35)]))
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .overlay(
                Image(systemName: "questionmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white.opacity(0.45))
            )
    }

    private var cardFace: some View {
        RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
            .fill(matched ? PhonePlayDesign.green.opacity(0.22) : PhonePlayDesign.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .strokeBorder(matched ? PhonePlayDesign.green : Color.white.opacity(0.12),
                                  lineWidth: matched ? 2 : 1)
            )
            .overlay(
                Text(value)
                    .font(.system(size: 30))
                    .minimumScaleFactor(0.5)
            )
    }
}

// MARK: - Roulette Controller

/// Reported directly from on-device testing: "controls on the adding the bets
/// is little cropped where delete options is not highlighted."
///
/// The cause was a fixed-width row that could not fit on a narrow phone. The
/// chip selector laid out four `.frame(width: 64)` buttons plus 3×10pt of
/// spacing (286pt), a `Spacer()`, and the Clear button — all inside a
/// `.padding(.horizontal, 20)`, with the Clear button carrying a *further*
/// `.padding(.trailing, 20)` of its own. On a 375pt-wide phone only 335pt is
/// available, so the Spacer collapsed to zero and Clear was pushed off the
/// right edge: cropped, and (as a 12pt red-at-70% caption with no background)
/// unreadable and effectively untappable even where it wasn't.
///
/// The layout is now built so nothing can overflow at any width:
///   * Chips share the row equally (`maxWidth: .infinity`) instead of each
///     claiming a fixed 64pt, so four of them fit any iPhone down to an SE.
///   * Clear gets its own full-width row — a real destructive button with a
///     44pt-plus tap target, an icon, a label and the amount it will refund —
///     so it can never be squeezed out by a neighbour again.
///   * Exactly one horizontal padding is applied, on the scroll content, so
///     no child can double up and push itself past the edge.
///   * Spin lives in a fixed bottom bar outside the ScrollView, so it stays
///     reachable without scrolling past nine bet tiles, and sits above the
///     home indicator rather than under it.
struct RouletteControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var chips: Int { privateData["chips"] as? Int ?? 100 }

    /// Defensive about the wire type: a JSON object arrives as `[String: Any]`
    /// holding bridged `NSNumber`s, and a straight `as? [String: Int]` is the
    /// kind of cast that fails silently and would leave Spin permanently
    /// disabled with no clue why.
    private var currentBets: [String: Int] {
        if let typed = privateData["bets"] as? [String: Int] { return typed }
        guard let raw = privateData["bets"] as? [String: Any] else { return [:] }
        return raw.compactMapValues { $0 as? Int }
    }

    private var isSpinning: Bool { privateData["isSpinning"] as? Bool ?? false }
    private var lastResult: Int? { privateData["lastResult"] as? Int }

    private var stakedTotal: Int { currentBets.values.reduce(0, +) }
    private var hasBets: Bool { stakedTotal > 0 }

    @State private var selectedChip = 5

    private let chipValues = [1, 5, 25, 100]
    // These ids are the server's contract: RouletteEngine only accepts a
    // `target` that is a key of ROULETTE_PAYOUTS, and an `amount` that is a
    // positive Int no larger than the player's chips.
    private let betTargets: [(String, String)] = [
        ("red", "Red"), ("black", "Black"),
        ("odd", "Odd"), ("even", "Even"),
        ("1-12", "1st 12"), ("13-24", "2nd 12"), ("25-36", "3rd 12"),
        ("low", "1–18"), ("high", "19–36"),
    ]

    var body: some View {
        ClassicShell(title: "Roulette",
                     subtitle: isSpinning ? "The wheel is spinning"
                                          : (hasBets ? "Staked $\(stakedTotal)" : "Place your bets"),
                     trailing: { headerTrailing }) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        chipSelector
                        clearButton
                        numberGrid
                        betGrid
                    }
                    // The one and only horizontal inset in this screen. Every row
                    // below is width-flexible, so nothing can extend past it.
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                // Never bounce past the top on a screen this short — the header is
                // pinned, so a rubber-band there just looks like a glitch.
                .scrollBounceBehavior(.basedOnSize)

                spinBar
            }
        }
    }

    // MARK: Sections

    private var headerTrailing: some View {
        HStack(spacing: 10) {
            if let result = lastResult {
                Text("Last \(result)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(PhonePlayDesign.yellow.opacity(0.15)))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.scale.combined(with: .opacity))
            }

            Text("$\(chips)")
                .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(PhonePlayDesign.green)
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
        }
        .animation(PhonePlayDesign.pop, value: chips)
        .animation(PhonePlayDesign.pop, value: lastResult)
    }

    private var chipSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhonePlaySectionLabel(text: "Chip value")

            HStack(spacing: 10) {
                ForEach(chipValues, id: \.self) { val in
                    let affordable = val <= chips && !isSpinning
                    let selected = selectedChip == val
                    Button(action: {
                        PhonePlayHaptics.tap()
                        selectedChip = val
                    }) {
                        Text("$\(val)")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            // Equal shares of whatever width the phone has —
                            // this is what stops the row overflowing at all.
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                    .fill(selected
                                          ? PhonePlayDesign.gradient([PhonePlayDesign.yellow, PhonePlayDesign.orange])
                                          : PhonePlayDesign.gradient([PhonePlayDesign.surface, PhonePlayDesign.surface]))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                    .strokeBorder(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1)
                            )
                            .shadow(color: PhonePlayDesign.yellow.opacity(selected ? 0.3 : 0), radius: 8, y: 3)
                            .foregroundColor(selected ? .black : .white)
                            .opacity(affordable ? 1 : 0.35)
                    }
                    .buttonStyle(PhonePlayPressStyle())
                    // Mirrors the server rule (`amount > chips` is ignored), so
                    // a denomination you can't cover reads as unavailable
                    // instead of as a dead tap.
                    .disabled(!affordable)
                }
            }
            .animation(PhonePlayDesign.pop, value: selectedChip)
        }
    }

    /// Deliberately its own full-width row rather than a trailing item on the
    /// chip row: that is exactly the arrangement that cropped it before.
    private var clearButton: some View {
        Button(action: {
            PhonePlayHaptics.warning()
            clearBets()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(hasBets ? "Clear bets · $\(stakedTotal)" : "Clear bets")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if hasBets {
                    Text("refunds your stake")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.red.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .foregroundColor(hasBets ? PhonePlayDesign.red : .white.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(hasBets ? PhonePlayDesign.red.opacity(0.14) : PhonePlayDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .strokeBorder(hasBets ? PhonePlayDesign.red.opacity(0.5) : Color.white.opacity(0.06),
                                          lineWidth: 1.5)
                    )
            )
            .animation(PhonePlayDesign.pop, value: hasBets)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!hasBets || isSpinning)
    }

    /// Straight-up bets on a single pocket, "0" through "36" -- the actual
    /// numbers a real roulette table lets you stake, and the reason a placed
    /// bet was never showing up as a chip on the TV's number grid: there was
    /// no way to bet on a number at all before RouletteEngine grew this.
    private var numberGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhonePlaySectionLabel(text: "Bet on a number")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                spacing: 6
            ) {
                ForEach(0...36, id: \.self) { number in
                    NumberBetTile(
                        number: number,
                        betAmount: currentBets["\(number)"] ?? 0,
                        isEnabled: !isSpinning && selectedChip <= chips,
                        onTap: { placeBet(on: "\(number)") }
                    )
                }
            }
            .padding(10)
            .classicCard()
        }
    }

    private var betGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhonePlaySectionLabel(text: "Or an outside bet")

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(betTargets, id: \.0) { id, label in
                    BetTile(
                        label: label,
                        betAmount: currentBets[id] ?? 0,
                        isEnabled: !isSpinning && selectedChip <= chips,
                        onTap: { placeBet(on: id) }
                    )
                }
            }
        }
    }

    /// Pinned outside the ScrollView so it is always visible and always above
    /// the home indicator, rather than being the ninth thing you have to
    /// scroll to on a small phone.
    private var isReady: Bool { privateData["isReady"] as? Bool ?? false }
    private var readyCount: Int { privateData["readyCount"] as? Int ?? 0 }
    private var readyNeeded: Int { privateData["readyNeeded"] as? Int ?? 0 }
    private var betSecondsLeft: Int { privateData["betSecondsLeft"] as? Int ?? 0 }

    /// "Spin" is now "I'm done betting": the wheel goes once everyone still
    /// in is done, or when the betting clock runs out.
    private var spinLabel: String {
        if isSpinning { return "Spinning…" }
        if isReady {
            let clock = betSecondsLeft > 0 ? " · \(betSecondsLeft)s" : ""
            return "Waiting for others (\(readyCount)/\(readyNeeded))\(clock)"
        }
        return betSecondsLeft > 0 ? "Done betting · \(betSecondsLeft)s" : "Done betting - spin!"
    }

    private var spinIcon: String {
        if isSpinning { return "arrow.triangle.2.circlepath" }
        return isReady ? "hourglass" : "checkmark.circle.fill"
    }

    private var spinBar: some View {
        let canSpin = !isSpinning && hasBets && !isReady
        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            BigButton(title: spinLabel, systemImage: spinIcon,
                      tint: PhonePlayDesign.green, enabled: canSpin) {
                spin()
            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            if !hasBets && !isSpinning {
                Text("Tap a bet above to stake your $\(selectedChip) chip")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .background(PhonePlayDesign.surface.opacity(0.7).ignoresSafeArea(edges: .bottom))
        .animation(PhonePlayDesign.pop, value: hasBets)
    }

    // MARK: Actions — these match RouletteEngine.handle_action exactly.

    private func placeBet(on target: String) {
        guard !isSpinning, selectedChip <= chips else { return }
        onAction("place_bet", ["target": target, "amount": selectedChip])
    }

    private func clearBets() {
        guard !isSpinning else { return }
        onAction("clear_bets", [:])
    }

    private func spin() {
        guard !isSpinning else { return }
        onAction("spin", [:])
    }
}

private struct BetTile: View {
    let label: String
    let betAmount: Int
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            onTap()
        }) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Always present (empty when unstaked) so a landing bet can't
                // change the tile's height and reflow the whole grid under
                // the thumb that just tapped it.
                Text(betAmount > 0 ? "$\(betAmount)" : " ")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.green)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .fill(betAmount > 0 ? PhonePlayDesign.green.opacity(0.18) : PhonePlayDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                            .strokeBorder(betAmount > 0 ? PhonePlayDesign.green.opacity(0.6) : Color.white.opacity(0.06),
                                          lineWidth: 1.5)
                    )
            )
            .opacity(isEnabled ? 1 : 0.4)
            .animation(PhonePlayDesign.pop, value: betAmount)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!isEnabled)
    }
}

/// One pocket in the number grid, coloured to match its real felt colour so
/// the 37-cell grid reads at a glance the same way the TV's wheel does.
private struct NumberBetTile: View {
    let number: Int
    let betAmount: Int
    let isEnabled: Bool
    let onTap: () -> Void

    // Same 18 numbers as RouletteWheel.redNumbers / RED_NUMBERS on the
    // engine -- kept local rather than shared across targets, matching how
    // this file already keeps its own small colour/rule duplicates.
    private static let redNumbers: Set<Int> = [
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
    ]

    private var fill: Color {
        if number == 0 { return Color(hex: "0b7a3b") }
        return Self.redNumbers.contains(number) ? Color(hex: "c0202a") : Color(hex: "15161a")
    }

    var body: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            onTap()
        }) {
            VStack(spacing: 1) {
                Text("\(number)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(betAmount > 0 ? "$\(betAmount)" : " ")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(betAmount > 0 ? PhonePlayDesign.yellow : Color.white.opacity(0.15),
                                          lineWidth: betAmount > 0 ? 2 : 1)
                    )
            )
            .opacity(isEnabled ? 1 : 0.4)
            .animation(PhonePlayDesign.pop, value: betAmount)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!isEnabled)
    }
}

// MARK: - Mafia Controller

struct MafiaControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var role: String { privateData["role"] as? String ?? "town" }
    private var phase: String { privateData["phase"] as? String ?? "day" }
    private var isAlive: Bool { privateData["isAlive"] as? Bool ?? true }
    private var players: [[String: Any]] { privateData["players"] as? [[String: Any]] ?? [] }
    private var myVote: String? { privateData["myVote"] as? String }
    private var investigateResult: String? { privateData["investigateResult"] as? String }
    private var investigateIsMafia: Bool {
        // Text matching misread "X is not Mafia." as a hit; prefer the flag.
        privateData["investigateIsMafia"] as? Bool
            ?? (investigateResult.map { $0.hasSuffix("is Mafia!") } ?? false)
    }
    private var myNightTarget: String? { privateData["myNightTarget"] as? String }
    private var mafiaTeam: [String] {
        (privateData["mafiaTeam"] as? [Any] ?? []).compactMap { $0 as? String }
    }

    private var isDay: Bool { phase == "day" }

    var body: some View {
        ClassicShell(title: "Mafia",
                     subtitle: isDay ? "Discuss, then vote" : "Eyes closed, phones low",
                     glow: isDay ? PhonePlayDesign.yellow : PhonePlayDesign.indigo,
                     trailing: { phaseChip }) {
            VStack(spacing: 0) {
                // Role card
                roleCard
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                ClassicCenteredScroll {
                    Group {
                        if !isAlive {
                            eliminatedView
                        } else if isDay {
                            dayPhaseView
                        } else {
                            nightPhaseView
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: isAlive)
        }
    }

    private var phaseChip: some View {
        HStack(spacing: 6) {
            Image(systemName: isDay ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 13, weight: .bold))
            Text(isDay ? "Day" : "Night")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
        }
        .foregroundColor(isDay ? PhonePlayDesign.yellow : PhonePlayDesign.cyan)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill((isDay ? PhonePlayDesign.yellow : PhonePlayDesign.cyan).opacity(0.15)))
    }

    private var roleInfo: (symbol: String, color: Color, desc: String) {
        switch role {
        case "mafia":   return ("moon.stars.fill", PhonePlayDesign.red, "Eliminate town at night")
        case "sheriff": return ("magnifyingglass", PhonePlayDesign.yellow, "Investigate one player per night")
        case "doctor":  return ("cross.fill", PhonePlayDesign.green, "Save one player per night")
        default:        return ("person.fill", PhonePlayDesign.blue, "Vote out Mafia during the day")
        }
    }

    private var roleCard: some View {
        let info = roleInfo
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([info.color.opacity(0.75), info.color.opacity(0.3)]))
                    .frame(width: 54, height: 54)
                Image(systemName: info.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            .phonePlayIdle(dy: 2, scale: 0.03, duration: 1.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(role.capitalized)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(info.color)
                Text(info.desc)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .classicCard()
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(info.color.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var dayPhaseView: some View {
        VStack(spacing: 12) {
            // The night can now end the moment everyone has acted, so the
            // Sheriff's finding has to stay visible into the day.
            if role == "sheriff", let result = investigateResult {
                ClassicPill(text: "Last night: \(result)", systemImage: "magnifyingglass",
                            tint: investigateIsMafia ? PhonePlayDesign.red : PhonePlayDesign.green)
                    .padding(.horizontal, 20)
            }
            if role == "mafia" && !mafiaTeam.isEmpty {
                ClassicPill(text: "Fellow Mafia: \(mafiaTeam.joined(separator: ", "))",
                            systemImage: "person.2.fill", tint: PhonePlayDesign.red)
                    .padding(.horizontal, 20)
            }
            PhonePlaySectionLabel(text: "Vote to eliminate")
                .padding(.horizontal, 24)
                .padding(.top, 4)
            ForEach(alivePlayers, id: \.0) { id, name in
                ClassicPickRow(text: name, tint: PhonePlayDesign.red,
                               selected: myVote == id, badge: "Your vote") {
                    vote(for: id)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var nightPhaseView: some View {
        VStack(spacing: 12) {
            switch role {
            case "mafia":
                nightTitle("Choose your target", tint: PhonePlayDesign.red)
                if !mafiaTeam.isEmpty {
                    ClassicPill(text: "Your fellow Mafia: \(mafiaTeam.joined(separator: ", "))",
                                systemImage: "person.2.fill", tint: PhonePlayDesign.red)
                        .padding(.horizontal, 20)
                }
                ForEach(alivePlayers.filter { $0.0 != (privateData["myID"] as? String ?? "") }, id: \.0) { id, name in
                    ClassicPickRow(text: name, tint: PhonePlayDesign.red,
                                   selected: myNightTarget == id, systemImage: "scope") {
                        nightAction(action: "eliminate", targetID: id)
                    }
                }
                .padding(.horizontal, 20)

            case "doctor":
                nightTitle("Save someone tonight", tint: PhonePlayDesign.green)
                ForEach(alivePlayers, id: \.0) { id, name in
                    ClassicPickRow(text: name, tint: PhonePlayDesign.green,
                                   selected: myNightTarget == id, systemImage: "cross.fill") {
                        nightAction(action: "save", targetID: id)
                    }
                }
                .padding(.horizontal, 20)

            case "sheriff":
                nightTitle("Investigate a player", tint: PhonePlayDesign.yellow)
                if let result = investigateResult {
                    ClassicPill(text: "Result: \(result)", systemImage: "magnifyingglass",
                                tint: investigateIsMafia ? PhonePlayDesign.red : PhonePlayDesign.green)
                        .padding(.horizontal, 20)
                }
                if myNightTarget == nil {
                    ForEach(alivePlayers.filter { $0.0 != (privateData["myID"] as? String ?? "") }, id: \.0) { id, name in
                        ClassicPickRow(text: name, tint: PhonePlayDesign.yellow,
                                       systemImage: "magnifyingglass") {
                            nightAction(action: "investigate", targetID: id)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    ClassicPill(text: "One investigation per night. Sleep now.",
                                systemImage: "moon.zzz.fill")
                }

            default:
                VStack(spacing: 18) {
                    ClassicHero(systemImage: "moon.fill", tint: PhonePlayDesign.indigo)
                    Text("Sleep tight…")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("Mafia is choosing their target.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
            }
        }
    }

    private func nightTitle(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
    }

    private var eliminatedView: some View {
        VStack(spacing: 16) {
            ClassicHero(systemImage: "person.fill.xmark", tint: PhonePlayDesign.red)
            Text("You were eliminated")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.red)
            Text("Watch the TV to see how the game ends.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var alivePlayers: [(String, String)] {
        players.compactMap { d -> (String, String)? in
            guard let id = d["id"] as? String,
                  let name = d["name"] as? String,
                  d["isAlive"] as? Bool ?? true else { return nil }
            return (id, name)
        }
    }

    private func vote(for targetID: String) {
        onAction("vote", ["targetID": targetID])
    }

    private func nightAction(action: String, targetID: String) {
        onAction(action, ["targetID": targetID])
    }
}

// MARK: - Digit Guess Controller (Mastermind / Bulls & Cows)

struct DigitGuessControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isMyTurn: Bool { privateData["isMyTurn"] as? Bool ?? true }
    private var myGuesses: [[String: Any]] { privateData["myGuesses"] as? [[String: Any]] ?? [] }
    private var won: Bool { privateData["won"] as? Bool ?? false }

    @State private var digits: [Int] = [0, 0, 0, 0]

    var body: some View {
        ClassicShell(title: "Digit Guess",
                     subtitle: won ? "Code cracked" : (isMyTurn ? "Your guess" : "Waiting for your turn"),
                     trailing: {
                         ClassicStatBadge(value: "\(myGuesses.count)", label: "GUESSES",
                                          tint: PhonePlayDesign.purple)
                     }) {
            ClassicCenteredScroll {
                Group {
                    if won {
                        VStack(spacing: 14) {
                            ClassicHero(systemImage: "party.popper.fill", tint: PhonePlayDesign.green)
                            Text("You cracked it!")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundColor(PhonePlayDesign.green)
                            Text("in \(myGuesses.count) guesses")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text2)
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else {
                        guessPanel
                    }
                }
                .padding(.vertical, 20)
            }
            .animation(PhonePlayDesign.pop, value: won)
        }
    }

    private var guessPanel: some View {
        VStack(spacing: 22) {
            Text("Guess the 4-digit code")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)

            // 4-digit selectors
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { pos in
                    digitWheel(pos)
                }
            }

            BigButton(title: "Submit Guess", systemImage: "paperplane.fill",
                      tint: PhonePlayDesign.purple, enabled: isMyTurn) {
                submitGuess()
            }

            // Guess history
            if !myGuesses.isEmpty {
                VStack(spacing: 8) {
                    PhonePlaySectionLabel(text: "Your guesses")
                    ForEach(Array(myGuesses.enumerated()), id: \.offset) { _, g in
                        HStack(spacing: 10) {
                            Text(g["guess"] as? String ?? "????")
                                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer(minLength: 8)
                            scoreChip("Bulls \(g["bulls"] as? Int ?? 0)", tint: PhonePlayDesign.green)
                            scoreChip("Cows \(g["cows"] as? Int ?? 0)", tint: PhonePlayDesign.yellow)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                .fill(PhonePlayDesign.surface)
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func digitWheel(_ pos: Int) -> some View {
        VStack(spacing: 6) {
            stepButton("chevron.up") { digits[pos] = (digits[pos] + 1) % 10 }

            Text("\(digits[pos])")
                .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .frame(width: 64, height: 70)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient([PhonePlayDesign.purple.opacity(0.5),
                                                        PhonePlayDesign.indigo.opacity(0.3)]))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            stepButton("chevron.down") { digits[pos] = (digits[pos] + 9) % 10 }
        }
        .animation(PhonePlayDesign.pop, value: digits[pos])
    }

    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: {
            PhonePlayHaptics.tap()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 64, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PhonePlayDesign.surface)
                )
        }
        .buttonStyle(PhonePlayPressStyle())
    }

    private func scoreChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.14)))
    }

    private func submitGuess() {
        guard isMyTurn else { return }
        onAction("guess", ["digits": digits, "code": digits.map(String.init).joined()])
    }
}

// MARK: - Raja Mantri Controller

struct RajaMantriControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var role: String { privateData["role"] as? String ?? "" }
    private var phase: String { privateData["phase"] as? String ?? "deal" }
    private var players: [(String, String)] {
        let raw = privateData["players"] as? [[String: Any]] ?? []
        return raw.compactMap { d -> (String, String)? in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return (id, name)
        }
    }
    private var myScore: Int { privateData["score"] as? Int ?? 0 }
    private var hasGuessed: Bool { privateData["hasGuessed"] as? Bool ?? false }

    var body: some View {
        ClassicShell(title: "Raja Mantri",
                     trailing: { ClassicStatBadge(value: "\(myScore)", label: "SCORE") }) {
            ClassicCenteredScroll {
                VStack(spacing: 24) {
                    // Role card
                    if !role.isEmpty {
                        roleCard
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }

                    // Sipahi guesses who is the Chor
                    if role == "Sipahi" && phase == "guess" && !hasGuessed {
                        VStack(spacing: 10) {
                            Text("Catch the Chor!")
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(PhonePlayDesign.yellow)
                            Text("Who is the thief?")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text2)
                                .padding(.bottom, 4)
                            ForEach(players, id: \.0) { id, name in
                                ClassicPickRow(text: name, tint: PhonePlayDesign.yellow,
                                               systemImage: "hand.point.right.fill") {
                                    onAction("accuse", ["targetID": id])
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } else if phase == "wait" || hasGuessed {
                        ClassicPill(text: "Wait for the round to end", systemImage: "hourglass")
                    }
                }
                .padding(.vertical, 20)
            }
            .animation(PhonePlayDesign.pop, value: role)
            .animation(PhonePlayDesign.pop, value: phase)
        }
    }

    private var roleCard: some View {
        let tint: Color = roleColor(role)
        return VStack(spacing: 10) {
            Text(roleInitial(role))
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 104, height: 104)
                .background(Circle().fill(PhonePlayDesign.gradient([tint, tint.opacity(0.55)])))
                .shadow(color: tint.opacity(0.4), radius: 16, y: 8)
                .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
            Text(role)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(tint)
            Text(roleDesc(role))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .classicCard()
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
        )
        .padding(.horizontal, 20)
    }

    private func roleInitial(_ r: String) -> String {
        switch r { case "Raja": return "R"; case "Mantri": return "M"; case "Chor": return "C"; default: return "?" }
    }
    private func roleColor(_ r: String) -> Color {
        switch r {
        case "Raja":   return PhonePlayDesign.yellow
        case "Mantri": return PhonePlayDesign.purple
        case "Chor":   return PhonePlayDesign.red
        default:       return PhonePlayDesign.cyan
        }
    }
    private func roleDesc(_ r: String) -> String {
        switch r {
        case "Raja":   return "You are the King. Stay safe."
        case "Mantri": return "You are the Minister. Protect the Raja."
        case "Chor":   return "You are the Thief. Hide your identity!"
        default:       return "You are the Guard. Find the Chor!"
        }
    }
}
