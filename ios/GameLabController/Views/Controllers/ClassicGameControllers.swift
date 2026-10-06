import SwiftUI
import UIKit

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
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            statusLine
                .padding(.bottom, 18)
            columnPicker
                .padding(.horizontal, 14)
            turnOrderStrip
                .padding(.top, 18)
            Spacer(minLength: 12)
        }
        .background(Color(hex: "00040d").ignoresSafeArea())
        .onChange(of: isMyTurn) { mine in
            if !mine { aimedCol = nil }
            if mine { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        }
    }

    // MARK: Header / status

    private var header: some View {
        HStack(spacing: 12) {
            Text("Connect 4").font(.headline).foregroundColor(.white)
            Spacer()
            Connect4PhoneDisc(colorID: myColor, size: 28)
            Text("You are \(myColor.capitalized)")
                .font(.subheadline.bold())
                .foregroundColor(Connect4PhonePalette.of(myColor).light)
        }
        .padding(20)
        .background(Color.white.opacity(0.04))
    }

    @ViewBuilder
    private var statusLine: some View {
        if isMyTurn {
            VStack(spacing: 4) {
                Text("Your move!")
                    .font(.title2.bold())
                    .foregroundColor(Connect4PhonePalette.of(myColor).light)
                Text("Drag to aim, let go to drop")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
            }
        } else if !currentName.isEmpty {
            HStack(spacing: 8) {
                if !currentColor.isEmpty {
                    Connect4PhoneDisc(colorID: currentColor, size: 18)
                }
                waitingLabel("Waiting for \(currentName)")
            }
        } else {
            waitingLabel("Waiting...")
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
        return VStack(spacing: 6) {
            ZStack {
                if aimed {
                    Connect4PhoneDisc(colorID: myColor, size: discSize)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Image(systemName: "chevron.down")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(full ? 0.1 : 0.35))
                }
            }
            .frame(height: 36)
            RoundedRectangle(cornerRadius: min(10, width * 0.3))
                .fill(columnFill(full: full, aimed: aimed, palette: palette))
                .overlay(
                    RoundedRectangle(cornerRadius: min(10, width * 0.3))
                        .strokeBorder(aimed ? palette.light.opacity(0.9) : Color.white.opacity(0.08),
                                      lineWidth: aimed ? 2 : 1)
                )
                .overlay(
                    full ? Image(systemName: "xmark").font(.caption2).foregroundColor(.white.opacity(0.25)) : nil
                )
            Text("\(col + 1)")
                .font(.caption2)
                .foregroundColor(aimed ? .white : .white.opacity(0.45))
        }
        .frame(width: width)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: aimed)
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
        return LinearGradient(colors: [Color(hex: "2f6bff").opacity(0.30), Color(hex: "0f2a86").opacity(0.30)],
                              startPoint: .top, endPoint: .bottom)
    }

    // MARK: Turn order

    private var turnOrderStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(turnOrder.enumerated()), id: \.offset) { item in
                turnDot(playerID: item.element)
            }
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
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        onAction("drop", ["column": col])
    }
}

// MARK: - Chess Controller

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
        VStack(spacing: 0) {
            HStack {
                Text("Chess").font(.headline).foregroundColor(.white)
                Spacer()
                Text(myColor.capitalized).font(.subheadline)
                    .foregroundColor(myColor == "white" ? .white : .black.opacity(0.8))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(myColor == "white" ? Color.white.opacity(0.2) : Color.black.opacity(0.8)))
            }
            .padding(16).background(Color.white.opacity(0.04))

            if isMyTurn {
                Text(selectedSquare == nil ? "Tap your piece" : "Tap destination")
                    .font(.subheadline).foregroundColor(.cyan.opacity(0.8))
                    .padding(.vertical, 8)
            } else {
                Text("Opponent thinking…").font(.subheadline).foregroundColor(.white.opacity(0.4)).padding(.vertical, 8)
            }

            // 8×8 board
            VStack(spacing: 1) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<8, id: \.self) { col in
                            let piece = pieceAt(row: row, col: col)
                            let isSelected = selectedSquare == [row, col]
                            let isValidTarget = validMoveSet.contains("\(row),\(col)")
                            let isLight = (row + col) % 2 == 0

                            Button(action: { tapSquare(row: row, col: col) }) {
                                ZStack {
                                    Rectangle().fill(
                                        isSelected ? Color.yellow.opacity(0.6) :
                                        isValidTarget ? Color.green.opacity(0.4) :
                                        isLight ? Color(hex: "f0d9b5") : Color(hex: "b58863")
                                    )
                                    if !piece.isEmpty {
                                        Text(piece).font(.system(size: 28))
                                    }
                                    if isValidTarget && piece.isEmpty {
                                        Circle().fill(Color.green.opacity(0.5)).frame(width: 14, height: 14)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain).disabled(!isMyTurn)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(hex: "1a1a1a"))
            .cornerRadius(12)
            .padding(.horizontal, 12)

            if let sel = selectedSquare {
                Button(action: { selectedSquare = nil }) {
                    Label("Deselect (\(chessCellLabel(sel[0], sel[1])))", systemImage: "xmark.circle")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain).padding(.top, 8)
            }

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
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
        VStack(spacing: 0) {
            HStack {
                Text("Memory").font(.headline).foregroundColor(.white)
                Spacer()
                Text("Pairs: \(myScore)").font(.subheadline.bold()).foregroundColor(.cyan)
            }
            .padding(16).background(Color.white.opacity(0.04))

            Spacer()

            if isMyTurn {
                Text("Flip two cards!").font(.subheadline).foregroundColor(.green.opacity(0.8))
                    .padding(.vertical, 8)
            } else {
                waitingLabel("Opponent's turn…")
                    .padding(.vertical, 8)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
                ForEach(0..<cardCount, id: \.self) { idx in
                    let revealed = flippedIndices.contains(idx) || matchedIndices.contains(idx)
                    let matched = matchedIndices.contains(idx)

                    Button(action: { tapCard(idx) }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(matched ? Color.green.opacity(0.3) :
                                      revealed ? Color.white.opacity(0.15) :
                                      Color(hex: "1e1e3a"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(matched ? Color.green.opacity(0.6) : Color.white.opacity(0.08),
                                                      lineWidth: 1.5)
                                )

                            if revealed {
                                Text(idx < cardValues.count ? cardValues[idx] : "?")
                                    .font(.system(size: 28))
                            } else {
                                Image(systemName: "questionmark").font(.title2)
                                    .foregroundColor(.white.opacity(0.3))
                            }
                        }
                        .frame(height: 70)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isMyTurn || revealed)
                }
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }

    private func tapCard(_ index: Int) {
        guard isMyTurn, !flippedIndices.contains(index), !matchedIndices.contains(index) else { return }
        onAction("flip", ["index": index])
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
        VStack(spacing: 0) {
            header

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
        .background(Color(hex: "060d00").ignoresSafeArea())
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Roulette")
                .font(.title2.bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            if let result = lastResult {
                Text("Last spin \(result)")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.yellow.opacity(0.15)))
                    .lineLimit(1)
                    .fixedSize()
            }

            Text("$\(chips)")
                .font(.headline.bold())
                .foregroundColor(.green)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04))
    }

    private var chipSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chip value")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 10) {
                ForEach(chipValues, id: \.self) { val in
                    let affordable = val <= chips && !isSpinning
                    Button(action: { selectedChip = val }) {
                        Text("$\(val)")
                            .font(.headline)
                            // Equal shares of whatever width the phone has —
                            // this is what stops the row overflowing at all.
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedChip == val
                                          ? Color.yellow.opacity(0.85)
                                          : Color.white.opacity(0.1))
                            )
                            .foregroundColor(selectedChip == val ? .black : .white)
                            .opacity(affordable ? 1 : 0.35)
                    }
                    .buttonStyle(.plain)
                    // Mirrors the server rule (`amount > chips` is ignored), so
                    // a denomination you can't cover reads as unavailable
                    // instead of as a dead tap.
                    .disabled(!affordable)
                }
            }
        }
    }

    /// Deliberately its own full-width row rather than a trailing item on the
    /// chip row: that is exactly the arrangement that cropped it before.
    private var clearButton: some View {
        Button(action: clearBets) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                Text(hasBets ? "Clear bets · $\(stakedTotal)" : "Clear bets")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if hasBets {
                    Text("refunds your stake")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .foregroundColor(hasBets ? Color(hex: "FF6B6B") : .white.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hasBets ? Color.red.opacity(0.14) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(hasBets ? Color.red.opacity(0.45) : Color.white.opacity(0.08),
                                          lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasBets || isSpinning)
    }

    /// Straight-up bets on a single pocket, "0" through "36" -- the actual
    /// numbers a real roulette table lets you stake, and the reason a placed
    /// bet was never showing up as a chip on the TV's number grid: there was
    /// no way to bet on a number at all before RouletteEngine grew this.
    private var numberGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bet on a number")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.45))

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
        }
    }

    private var betGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or an outside bet")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.45))

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

    private var spinBar: some View {
        let canSpin = !isSpinning && hasBets && !isReady
        return VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            Button(action: spin) {
                Text(spinLabel)
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(canSpin ? Color.green.opacity(0.85) : Color.white.opacity(0.1))
                    )
                    .foregroundColor(canSpin ? .black : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSpin)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)

            if !hasBets && !isSpinning {
                Text("Tap a bet above to stake your $\(selectedChip) chip")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 10)
            }
        }
        .background(Color.white.opacity(0.03))
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
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Always present (empty when unstaked) so a landing bet can't
                // change the tile's height and reflow the whole grid under
                // the thumb that just tapped it.
                Text(betAmount > 0 ? "$\(betAmount)" : " ")
                    .font(.caption.bold())
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(betAmount > 0 ? Color.green.opacity(0.2) : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(betAmount > 0 ? Color.green.opacity(0.5) : Color.white.opacity(0.08),
                                          lineWidth: 1.5)
                    )
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
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
        Button(action: onTap) {
            VStack(spacing: 1) {
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(betAmount > 0 ? "$\(betAmount)" : " ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.yellow)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(betAmount > 0 ? Color.yellow : Color.white.opacity(0.15),
                                          lineWidth: betAmount > 0 ? 2 : 1)
                    )
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(spacing: 0) {
            // Role card
            roleCard

            Spacer()

            if !isAlive {
                eliminatedView
            } else if phase == "day" {
                dayPhaseView
            } else {
                nightPhaseView
            }

            Spacer()
        }
        .background(Color(hex: phase == "day" ? "0a0814" : "000814").ignoresSafeArea())
    }

    private var roleCard: some View {
        let (symbol, color, desc): (String, Color, String) = {
            switch role {
            case "mafia":   return ("moon.stars.fill", .red, "Eliminate town at night")
            case "sheriff": return ("magnifyingglass", .yellow, "Investigate one player per night")
            case "doctor":  return ("cross.fill", .green, "Save one player per night")
            default:        return ("person.fill", .white, "Vote out Mafia during the day")
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(role.capitalized).font(.headline).foregroundColor(color)
                Text(desc).font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Text(phase == "day" ? "Day" : "Night")
                .font(.caption.bold())
                .foregroundColor(phase == "day" ? .yellow : .cyan)
        }
        .padding(20)
        .background(color.opacity(0.1))
    }

    private var dayPhaseView: some View {
        VStack(spacing: 16) {
            // The night can now end the moment everyone has acted, so the
            // Sheriff's finding has to stay visible into the day.
            if role == "sheriff", let result = investigateResult {
                Text("Last night: \(result)").font(.subheadline.bold())
                    .foregroundColor(investigateIsMafia ? .red : .green)
            }
            if role == "mafia" && !mafiaTeam.isEmpty {
                Text("Fellow Mafia: \(mafiaTeam.joined(separator: ", "))")
                    .font(.caption).foregroundColor(.red.opacity(0.8))
            }
            Text("Vote to eliminate").font(.headline).foregroundColor(.white.opacity(0.7))
            ForEach(alivePlayers, id: \.0) { id, name in
                Button(action: { vote(for: id) }) {
                    HStack {
                        Text(name).foregroundColor(.white)
                        Spacer()
                        if myVote == id {
                            Label("Your vote", systemImage: "checkmark").font(.caption).foregroundColor(.red)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(myVote == id ? Color.red.opacity(0.2) : Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(myVote == id ? Color.red.opacity(0.5) : .clear, lineWidth: 1.5)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
        }
    }

    private var nightPhaseView: some View {
        VStack(spacing: 16) {
            switch role {
            case "mafia":
                Text("Choose your target").font(.headline).foregroundColor(.red)
                if !mafiaTeam.isEmpty {
                    Text("Your fellow Mafia: \(mafiaTeam.joined(separator: ", "))")
                        .font(.caption).foregroundColor(.red.opacity(0.8))
                }
                ForEach(alivePlayers.filter { $0.0 != (privateData["myID"] as? String ?? "") }, id: \.0) { id, name in
                    Button(action: { nightAction(action: "eliminate", targetID: id) }) {
                        Text(name).foregroundColor(.white).frame(maxWidth: .infinity).padding(14)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(myNightTarget == id ? 0.45 : 0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

            case "doctor":
                Text("Save someone tonight").font(.headline).foregroundColor(.green)
                ForEach(alivePlayers, id: \.0) { id, name in
                    Button(action: { nightAction(action: "save", targetID: id) }) {
                        Text(name).foregroundColor(.white).frame(maxWidth: .infinity).padding(14)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(myNightTarget == id ? 0.45 : 0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

            case "sheriff":
                Text("Investigate a player").font(.headline).foregroundColor(.yellow)
                if let result = investigateResult {
                    Text("Result: \(result)").font(.body.bold())
                        .foregroundColor(investigateIsMafia ? .red : .green)
                        .padding(.horizontal, 24)
                }
                if myNightTarget == nil {
                    ForEach(alivePlayers.filter { $0.0 != (privateData["myID"] as? String ?? "") }, id: \.0) { id, name in
                        Button(action: { nightAction(action: "investigate", targetID: id) }) {
                            Text(name).foregroundColor(.white).frame(maxWidth: .infinity).padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                } else {
                    Text("One investigation per night. Sleep now.")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }

            default:
                VStack(spacing: 12) {
                    Image(systemName: "moon.fill").font(.system(size: 52)).foregroundColor(.cyan.opacity(0.8))
                    Text("Sleep tight…\nMafia is choosing their target.").font(.body)
                        .foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center)
                }
            }
        }
    }

    private var eliminatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "skull").font(.system(size: 64)).foregroundColor(.white.opacity(0.7))
            Text("You were eliminated").font(.title2.bold()).foregroundColor(.red)
            Text("Watch the TV to see how the game ends.").font(.subheadline)
                .foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center)
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
        VStack(spacing: 0) {
            HStack {
                Text("Digit Guess").font(.headline).foregroundColor(.white)
                Spacer()
                Text("Guesses: \(myGuesses.count)").font(.subheadline).foregroundColor(.white.opacity(0.5))
            }
            .padding(16).background(Color.white.opacity(0.04))

            Spacer()

            if won {
                VStack(spacing: 12) {
                    Image(systemName: "party.popper.fill").font(.system(size: 56)).foregroundColor(.green)
                    Text("You cracked it!").font(.title2.bold()).foregroundColor(.green)
                    Text("in \(myGuesses.count) guesses").foregroundColor(.white.opacity(0.5))
                }
            } else {
                VStack(spacing: 24) {
                    Text("Guess the 4-digit code").font(.subheadline).foregroundColor(.white.opacity(0.5))

                    // 4-digit selectors
                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { pos in
                            VStack(spacing: 0) {
                                Button(action: { digits[pos] = (digits[pos] + 1) % 10 }) {
                                    Image(systemName: "chevron.up").foregroundColor(.white.opacity(0.5)).frame(height: 32)
                                }
                                .buttonStyle(.plain)

                                Text("\(digits[pos])")
                                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))

                                Button(action: { digits[pos] = (digits[pos] + 9) % 10 }) {
                                    Image(systemName: "chevron.down").foregroundColor(.white.opacity(0.5)).frame(height: 32)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(action: submitGuess) {
                        Text("Submit Guess").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(isMyTurn ? Color.purple : Color.white.opacity(0.08)))
                            .foregroundColor(isMyTurn ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain).disabled(!isMyTurn).padding(.horizontal, 24)

                    // Guess history
                    if !myGuesses.isEmpty {
                        VStack(spacing: 6) {
                            Text("Your guesses").font(.caption.bold()).foregroundColor(.white.opacity(0.4))
                            ForEach(Array(myGuesses.enumerated()), id: \.offset) { _, g in
                                HStack {
                                    Text(g["guess"] as? String ?? "????")
                                        .font(.system(.body, design: .monospaced).bold()).foregroundColor(.white)
                                    Spacer()
                                    Text("Bulls \(g["bulls"] as? Int ?? 0) · Cows \(g["cows"] as? Int ?? 0)")
                                        .font(.caption).foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
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
        VStack(spacing: 0) {
            HStack {
                Text("Raja Mantri").font(.headline).foregroundColor(.white)
                Spacer()
                Text("Score: \(myScore)").font(.subheadline.bold()).foregroundColor(.cyan)
            }
            .padding(16).background(Color.white.opacity(0.04))

            Spacer()

            VStack(spacing: 24) {
                // Role card
                if !role.isEmpty {
                    VStack(spacing: 8) {
                        Text(roleEmoji(role)).font(.system(size: 72))
                        Text(role).font(.system(size: 32, weight: .bold)).foregroundColor(roleColor(role))
                        Text(roleDesc(role)).font(.subheadline).foregroundColor(.white.opacity(0.5))
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 20).fill(roleColor(role).opacity(0.08)))
                    .padding(.horizontal, 24)
                }

                // Sipahi guesses who is the Chor
                if role == "Sipahi" && phase == "guess" && !hasGuessed {
                    VStack(spacing: 12) {
                        Text("Catch the Chor!").font(.headline.bold()).foregroundColor(.yellow)
                        Text("Who is the thief?").font(.subheadline).foregroundColor(.white.opacity(0.5))
                        ForEach(players, id: \.0) { id, name in
                            Button(action: { onAction("accuse", ["targetID": id]) }) {
                                HStack {
                                    Text(name).foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "hand.point.right.fill").foregroundColor(.yellow)
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.yellow.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                } else if phase == "wait" || hasGuessed {
                    Label("Wait for the round to end", systemImage: "hourglass")
                        .font(.subheadline).foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }

    private func roleEmoji(_ r: String) -> String {
        switch r { case "Raja": return "R"; case "Mantri": return "M"; case "Chor": return "C"; default: return "?" }
    }
    private func roleColor(_ r: String) -> Color {
        switch r { case "Raja": return .yellow; case "Mantri": return .purple; case "Chor": return .red; default: return .cyan }
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

// MARK: - Shared helpers

private func waitingLabel(_ text: String) -> some View {
    Label(text, systemImage: "hourglass")
        .font(.subheadline).foregroundColor(.white.opacity(0.4))
}
