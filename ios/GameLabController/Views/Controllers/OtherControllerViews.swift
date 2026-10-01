import SwiftUI
import CoreMotion

// MARK: - Poker Controller (private hand on phone)

struct PokerControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var hand: [String] { privateData["hand"] as? [String] ?? [] }
    private var chips: Int { privateData["chips"] as? Int ?? 0 }
    private var canBet: Bool { (privateData["isMyTurn"] as? Bool) ?? false }
    @State private var betAmount: Double = 0
    private var minBet: Int { privateData["minBet"] as? Int ?? 0 }
    private var maxBet: Int { chips }

    var body: some View {
        VStack(spacing: 16) {
            // Private hand — only you see this. Reported directly as "too
            // tiny... I want those in full screen with real card flipped
            // back": the hand is now the dominant element on the whole
            // screen (big cards, generous breathing room above/below)
            // instead of a small row floating over empty black space, and
            // each card starts face-down until swiped to reveal it.
            HStack(spacing: 6) {
                Image(systemName: "eye.slash.fill").foregroundColor(.cyan)
                Text("Your Hand (private) — swipe a card to reveal it")
                    .font(.caption).foregroundColor(.cyan)
            }
            .padding(.top, 20)

            Spacer(minLength: 4)

            HStack(spacing: 22) {
                ForEach(Array(hand.enumerated()), id: \.offset) { _, card in
                    FlippableHoleCard(card: card)
                }
            }

            Spacer(minLength: 4)

            Text("Chips: \(chips)").font(.headline).foregroundColor(.white)

            if canBet {
                VStack(spacing: 16) {
                    Text("Your Turn").font(.title3.bold()).foregroundColor(.yellow)

                    // Bet slider
                    VStack(spacing: 8) {
                        Text("Bet: \(Int(betAmount))").foregroundColor(.white)
                        Slider(value: $betAmount, in: Double(minBet)...Double(max(maxBet, minBet)))
                            .tint(.yellow)
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        ActionBtn("Fold",  color: .red)    { onAction("fold",  [:]) }
                        ActionBtn("Check", color: .gray)   { onAction("check", [:]) }
                        ActionBtn("Bet",   color: .yellow)  { onAction("bet",   ["amount": Int(betAmount)]) }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
            } else {
                Text("Waiting for your turn…")
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "001400").ignoresSafeArea())
        .onAppear { betAmount = Double(minBet) }
    }
}

// MARK: - Flippable hole card

private let pokerCardWidth: CGFloat = 150
private let pokerCardHeight: CGFloat = 210

/// One private hole card: starts face-down and flips, page-turn style, the
/// first time it's swiped. Each instance owns its own flip state so the two
/// hole cards are revealed independently of one another.
private struct FlippableHoleCard: View {
    let card: String

    @State private var isFlipped = false
    @State private var showFace = false
    private let flipDuration: Double = 0.55

    var body: some View {
        ZStack {
            if showFace {
                PokerCardFace(card: card)
            } else {
                PokerCardBack()
            }
        }
        .frame(width: pokerCardWidth, height: pokerCardHeight)
        // The standard SwiftUI card-flip technique: rotate the whole card
        // 0°→180° around the vertical axis, and swap which face is drawn
        // at the midpoint (via the delayed `showFace` flip below) rather
        // than cross-fading -- at 90° the card is edge-on to the camera,
        // so the swap is invisible and the reveal reads as a real flip.
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 14)
                .onEnded { value in
                    guard abs(value.translation.width) > 18 || abs(value.translation.height) > 18 else { return }
                    flip()
                }
        )
        .onTapGesture { flip() }
    }

    private func flip() {
        guard !isFlipped else { return }
        withAnimation(.easeInOut(duration: flipDuration)) {
            isFlipped = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flipDuration / 2) {
            showFace = true
        }
    }
}

/// The revealed face of a hole card: white stock, corner rank/suit indices
/// top-left and bottom-right (the bottom one rotated, as on a real card so
/// it reads correctly from either side), and a large centre suit glyph.
private struct PokerCardFace: View {
    let card: String   // e.g. "A♠", "K♥"
    private var isRed: Bool { card.contains("♥") || card.contains("♦") }
    private var rank: String { card.isEmpty ? "?" : String(card.dropLast()) }
    private var suit: String { card.isEmpty ? "" : String(card.suffix(1)) }

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.white)
            .overlay(
                VStack {
                    HStack {
                        cornerIndex
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        cornerIndex.rotationEffect(.degrees(180))
                    }
                }
                .padding(14)
            )
            .overlay(
                Text(suit)
                    .font(.system(size: 76))
                    .foregroundColor(isRed ? .red : .black)
            )
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
    }

    private var cornerIndex: some View {
        VStack(spacing: -4) {
            Text(rank).font(.system(size: 26, weight: .bold))
            Text(suit).font(.system(size: 20))
        }
        .foregroundColor(isRed ? .red : .black)
    }
}

/// The hidden face of a hole card: a diagonal-hatch pattern over a deep
/// purple ground with a centre emblem, matching `TVCardBack`'s palette
/// (same `1a0a2e` ground / purple border) so the phone and TV card backs
/// read as the same deck rather than two unrelated designs.
private struct PokerCardBack: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(hex: "1a0a2e"))
            .overlay(
                Canvas { ctx, size in
                    let step: CGFloat = 16
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        ctx.stroke(path, with: .color(Color.purple.opacity(0.22)), lineWidth: 2)
                        x += step
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .inset(by: 14)
                    .strokeBorder(Color.purple.opacity(0.55), lineWidth: 2)
            )
            .overlay(
                Circle()
                    .fill(Color.purple.opacity(0.35))
                    .frame(width: 54, height: 54)
                    .overlay(Text("🂠").font(.system(size: 30)))
            )
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.purple.opacity(0.45), lineWidth: 1))
    }
}

private struct ActionBtn: View {
    let label: String
    let color: Color
    let action: () -> Void
    init(_ label: String, color: Color, action: @escaping () -> Void) {
        self.label = label; self.color = color; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(label).font(.headline).foregroundColor(color == .yellow ? .black : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.85)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Snake & Ladder — Shake to Roll

struct ShakeToRollControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var lastRoll: Int? = nil
    @State private var diceScale: CGFloat = 1.0
    @State private var diceRotation: Double = 0
    private var isMyTurn: Bool { (privateData["isMyTurn"] as? Bool) ?? false }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // A big, tactile pip-faced die (not just a printed number) --
            // the user specifically asked for "a little bigger dice" here,
            // so this is sized to dominate the screen the way a physical
            // die would in your hand, with its own roll flourish on both a
            // shake and a direct tap (the shake gesture alone is easy to
            // trigger by accident or to miss entirely; a tap always works).
            Button(action: roll) {
                DiceFaceView(value: lastRoll ?? 0, size: 220)
                    .scaleEffect(diceScale)
                    .rotation3DEffect(.degrees(diceRotation), axis: (x: 0.5, y: 1, z: 0.15))
                    .shadow(color: .cyan.opacity(isMyTurn ? 0.35 : 0), radius: 24)
            }
            .buttonStyle(.plain)
            .disabled(!isMyTurn)
            .onShake { roll() }
            .accessibilityLabel("Roll the dice")

            if let roll = lastRoll {
                Text("You rolled \(roll)!")
                    .font(.largeTitle.bold()).foregroundColor(.white)
            }

            Text(isMyTurn ? "Shake or tap the die to roll!" : "Not your turn…")
                .font(.title3)
                .foregroundColor(isMyTurn ? .cyan : .white.opacity(0.4))

            if let pos = privateData["position"] as? Int {
                Text("Your position: \(pos)")
                    .font(.subheadline).foregroundColor(.white.opacity(0.5))
            }

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }

    private func roll() {
        guard isMyTurn else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) { diceScale = 1.28 }
        withAnimation(.easeOut(duration: 0.55)) { diceRotation += 360 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.spring()) { diceScale = 1.0 }
            let value = Int.random(in: 1...6)
            lastRoll = value
            onAction("roll", ["value": value])
        }
    }
}

/// A real six-sided die face drawn as pips on a rounded square, rather than
/// a printed digit -- `value` of 0 renders a blank/idle face (before the
/// first roll of the game).
private struct DiceFaceView: View {
    let value: Int
    var size: CGFloat = 200

    /// Standard die pip layout, positions as fractions of `size` on each
    /// axis so the same layout scales to any `size`.
    private var pipPositions: [(CGFloat, CGFloat)] {
        switch value {
        case 1: return [(0.5, 0.5)]
        case 2: return [(0.26, 0.26), (0.74, 0.74)]
        case 3: return [(0.26, 0.26), (0.5, 0.5), (0.74, 0.74)]
        case 4: return [(0.26, 0.26), (0.74, 0.26), (0.26, 0.74), (0.74, 0.74)]
        case 5: return [(0.26, 0.26), (0.74, 0.26), (0.5, 0.5), (0.26, 0.74), (0.74, 0.74)]
        case 6: return [(0.26, 0.22), (0.74, 0.22), (0.26, 0.5), (0.74, 0.5), (0.26, 0.78), (0.74, 0.78)]
        default: return []
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: size * 0.18)
                .stroke(Color.black.opacity(0.08), lineWidth: 2)
            ForEach(Array(pipPositions.enumerated()), id: \.offset) { _, pip in
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: size * 0.15, height: size * 0.15)
                    .position(x: pip.0 * size, y: pip.1 * size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
    }
}

// MARK: - Pong — Tilt controller

struct PongControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @StateObject private var motion = MotionManager()
    @State private var lastSent: Date = .distantPast

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Pong")
                .font(.largeTitle.bold()).foregroundColor(.white)

            Text("Tilt your phone to move your paddle")
                .foregroundColor(.white.opacity(0.5))

            // Visual tilt indicator
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 120, height: 300)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cyan)
                    .frame(width: 20, height: 60)
                    .offset(y: CGFloat(motion.roll) * 100)
            }

            Text("Side: \(privateData["side"] as? String ?? "?")")
                .font(.caption).foregroundColor(.white.opacity(0.4))

            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onChange(of: motion.roll) { roll in
            let now = Date()
            // Reported directly as "so glitchy": this was capped at 20/sec,
            // but game_action's shared rate limiter (socket_events.py's
            // ACTION_BURST/ACTION_WINDOW_SECONDS) only sustains 15/sec
            // averaged over its window. A continuously-tilting phone at
            // 20/sec burned through the burst budget in under two seconds,
            // then had updates silently dropped until older ones aged out
            // -- smooth for a beat, then a stall, on repeat. 12/sec sends
            // comfortably under the sustained limit instead of racing it.
            guard now.timeIntervalSince(lastSent) > 0.083 else { return } // ~12 fps max
            lastSent = now
            onAction("paddle", ["position": roll])
        }
    }
}

@MainActor
final class MotionManager: ObservableObject {
    @Published var roll: Double = 0
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let sample = max(-1, min(1, motion.attitude.roll / (.pi / 2)))
            // A raw instantaneous gyro reading has no smoothing at all, so
            // any hand tremor or sensor noise went straight into the
            // paddle's position. A simple exponential low-pass filter
            // (each sample nudges toward the new value rather than jumping
            // to it) removes that noise while still tracking a deliberate
            // tilt within a frame or two.
            self.roll = self.roll * 0.75 + sample * 0.25
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

// MARK: - Mind Meld

struct MindMeldControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var wordInput = ""
    @State private var hasSubmitted = false
    private var category: String { privateData["category"] as? String ?? "" }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Mind Meld").font(.largeTitle.bold()).foregroundColor(.white)
            Text("Category: \(category)").font(.title3).foregroundColor(.cyan)
            Text("Type ONE word that fits the category.\nTry to match what others think!").font(.subheadline)
                .foregroundColor(.white.opacity(0.5)).multilineTextAlignment(.center)

            if !hasSubmitted {
                TextField("Your word…", text: $wordInput)
                    .font(.title2).foregroundColor(.white).multilineTextAlignment(.center)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                    .padding(.horizontal, 32)

                Button(action: submit) {
                    Text("Submit").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.purple))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain).disabled(wordInput.isEmpty).padding(.horizontal, 32)
            } else {
                Image(systemName: "brain.filled.head.profile").font(.system(size: 60)).foregroundColor(.purple)
                Text("Word submitted!\nWatch the TV for the meld…").font(.title3).foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .background(Color(hex: "0d0a14").ignoresSafeArea())
    }

    private func submit() {
        guard !wordInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        hasSubmitted = true
        onAction("word", ["word": wordInput.trimmingCharacters(in: .whitespaces).lowercased()])
    }
}

// MARK: - Hot Grid

struct HotGridControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var hasPicked = false
    private var isMyTurn: Bool { (privateData["isMyTurn"] as? Bool) ?? false }
    private let gridSize = 5

    var body: some View {
        VStack(spacing: 24) {
            Text("Hot Grid").font(.largeTitle.bold()).foregroundColor(.white)
            Text(isMyTurn ? "Pick a tile!" : "Waiting for your turn…")
                .font(.title3).foregroundColor(isMyTurn ? .yellow : .white.opacity(0.4))

            if isMyTurn && !hasPicked {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: gridSize), spacing: 12) {
                    ForEach(0..<gridSize*gridSize, id: \.self) { idx in
                        Button(action: { pick(idx) }) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 52)
                                .overlay(Text("?").font(.title2).foregroundColor(.white.opacity(0.5)))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            Spacer()
        }
        .padding(.top, 40)
        .background(Color(hex: "0a0a0a").ignoresSafeArea())
    }

    private func pick(_ index: Int) {
        hasPicked = true
        onAction("pick_tile", ["index": index])
    }
}

// MARK: - Stock Panic

struct StockPanicControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var portfolio: [String: Int] { privateData["portfolio"] as? [String: Int] ?? [:] }
    private var cash: Int { privateData["cash"] as? Int ?? 0 }
    private var stocks: [String] { portfolio.keys.sorted() }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Stock Panic").font(.title.bold()).foregroundColor(.white)
                Text("Cash: $\(cash)").font(.headline).foregroundColor(.green)

                ForEach(stocks, id: \.self) { stock in
                    HStack(spacing: 16) {
                        Text(stock).font(.headline).foregroundColor(.white).frame(width: 80)
                        Text("×\(portfolio[stock] ?? 0)").foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Button("Buy") { onAction("trade", ["stock": stock, "action": "buy"]) }
                            .foregroundColor(.green).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.2)))
                            .buttonStyle(.plain)
                        Button("Sell") { onAction("trade", ["stock": stock, "action": "sell"]) }
                            .foregroundColor(.red).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.2)))
                            .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
            }
            .padding(24)
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }
}

// MARK: - Speed Sculptor (drawing canvas)

struct SpeedSculptorControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var lines: [DrawLine] = []
    @State private var currentLine: DrawLine? = nil
    @State private var submitted = false
    private var prompt: String { privateData["prompt"] as? String ?? "?" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Draw: \(prompt)").font(.headline).foregroundColor(.white)
                Spacer()
                Button("Clear") { lines = []; currentLine = nil }
                    .foregroundColor(.cyan).buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.white.opacity(0.06))

            // Drawing canvas
            Canvas { ctx, size in
                for line in lines {
                    var path = Path()
                    guard let first = line.points.first else { continue }
                    path.move(to: first)
                    for pt in line.points.dropFirst() { path.addLine(to: pt) }
                    ctx.stroke(path, with: .color(line.color), style: .init(lineWidth: line.width, lineCap: .round, lineJoin: .round))
                }
                if let current = currentLine {
                    var path = Path()
                    guard let first = current.points.first else { return }
                    path.move(to: first)
                    for pt in current.points.dropFirst() { path.addLine(to: pt) }
                    ctx.stroke(path, with: .color(current.color), style: .init(lineWidth: current.width, lineCap: .round, lineJoin: .round))
                }
            }
            .background(Color.white)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if currentLine == nil {
                            currentLine = DrawLine(points: [value.location], color: .black, width: 4)
                        } else {
                            currentLine?.points.append(value.location)
                        }
                    }
                    .onEnded { _ in
                        if let line = currentLine { lines.append(line) }
                        currentLine = nil
                    }
            )

            if !submitted {
                Button(action: submitDrawing) {
                    Text("Submit Drawing").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.purple))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain).padding(16)
            } else {
                Text("✓ Submitted! Watch the TV.").foregroundColor(.green).padding(16)
            }
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }

    private func submitDrawing() {
        submitted = true
        // Encode lines as simplified point arrays for server
        let encoded = lines.map { line in
            line.points.map { ["x": $0.x, "y": $0.y] }
        }
        onAction("drawing", ["lines": encoded, "prompt": prompt])
    }
}

struct DrawLine {
    var points: [CGPoint]
    let color: Color
    let width: CGFloat
}

// MARK: - Tambola (Bingo ticket)

struct TambolaControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var ticket: [[Int?]] { (privateData["ticket"] as? [[Int?]]) ?? [] }
    private var markedNumbers: Set<Int> {
        Set((privateData["marked"] as? [Int]) ?? [])
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Tambola").font(.title.bold()).foregroundColor(.white)
            Text("Your Ticket").font(.subheadline).foregroundColor(.white.opacity(0.4))

            VStack(spacing: 6) {
                ForEach(Array(ticket.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, num in
                            if let n = num {
                                Button(action: { onAction("mark", ["number": n]) }) {
                                    Text("\(n)").font(.system(.body, design: .monospaced).bold())
                                        .frame(width: 40, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(markedNumbers.contains(n) ? Color.green.opacity(0.4) : Color.white.opacity(0.1)))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.03))
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                }
            }

            Button(action: { onAction("claim", ["type": "full_house"]) }) {
                Text("Claim Full House!").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.yellow.opacity(0.85)))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain).padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 40)
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }
}

// MARK: - Generic tap controller (fallback)

struct GenericTapControllerView: View {
    let room: Room
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: room.gameID.sfSymbol).font(.system(size: 64)).foregroundColor(.white.opacity(0.85))
            Text(room.gameID.displayName).font(.title.bold()).foregroundColor(.white)
            Text("Game in progress").foregroundColor(.white.opacity(0.4))
            Spacer()
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }
}

// TV board views are defined in TVClassicGameBoards.swift and TVHeistBoardView.swift
// TVResultsView moved to Shared/Views/ResultsView.swift — GameLabTV's
// RootTVView needs it, and this file only compiles into GameLabController.

// MARK: - Results views

struct ResultsControllerView: View {
    let room: Room
    let onLeave: () -> Void

    private var myID: String { AppConstants.deviceID }
    private var sorted: [Player] { room.players.sorted { $0.score > $1.score } }
    private var myRank: Int {
        (sorted.firstIndex(where: { $0.id == myID }) ?? 0) + 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Game Over").font(.largeTitle.bold()).foregroundColor(.white)
                Text(room.gameID.displayName).font(.subheadline).foregroundColor(.white.opacity(0.4))
            }
            .padding(.top, 48).padding(.bottom, 24)

            // My rank callout
            HStack(spacing: 12) {
                Text(rankEmoji(myRank)).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("You finished \(ordinal(myRank))").font(.headline).foregroundColor(.white)
                    if let me = sorted.first(where: { $0.id == myID }) {
                        Text("\(me.score) points").font(.subheadline).foregroundColor(.cyan)
                    }
                }
                Spacer()
            }
            .padding(16).padding(.horizontal, 24)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
            .padding(.horizontal, 24)

            // Full leaderboard
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { rank, player in
                        HStack(spacing: 12) {
                            Text(rankEmoji(rank + 1)).font(.title3).frame(width: 36)
                            Text(player.name)
                                .font(.body)
                                .foregroundColor(player.id == myID ? .cyan : .white)
                                .fontWeight(player.id == myID ? .bold : .regular)
                            if player.id == myID {
                                Text("YOU").font(.caption2.bold()).foregroundColor(.cyan)
                            }
                            Spacer()
                            Text("\(player.score)").font(.headline.bold()).foregroundColor(.white)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(player.id == myID ? Color.cyan.opacity(0.1) : Color.white.opacity(0.04)))
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16)
            }

            Spacer()

            Button(action: onLeave) {
                Label("Leave Room", systemImage: "arrow.left.circle")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1)))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain).padding(.horizontal, 24).padding(.bottom, 40)
        }
        .background(Color(hex: "0a0a14").ignoresSafeArea())
    }

    private func rankEmoji(_ rank: Int) -> String {
        ordinal(rank)
    }

    private func ordinal(_ n: Int) -> String {
        switch n { case 1: return "1st"; case 2: return "2nd"; case 3: return "3rd"; default: return "\(n)th" }
    }
}

// MARK: - Shake gesture

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(action: action))
    }
}

struct ShakeDetector: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShakeNotification)) { _ in
            action()
        }
    }
}

extension Notification.Name {
    static let deviceDidShakeNotification = Notification.Name("DeviceDidShake")
}

// MARK: - Blast Runners (D-pad + one big action button)
//
// The only controller in this file with a movement pad *and* a dedicated
// action button on the same screen -- Neon Snake/Simon Says's plain D-pad
// (DuelControllers.swift) has nothing to press besides the arrows, so
// rather than bolt an action button onto that shared type this builds its
// own compact cross layout scoped entirely to this struct, exactly as the
// task brief allows ("build fresh" is fine here).
//
// `private_state` carries no secrets for this game (`hasPrivateInfo` is
// false server-side too) -- this screen exists purely so a phone player has
// the same D-pad + action input a Siri Remote can't cleanly provide
// alongside real-time steering, not to show anything the TV doesn't.

struct BlastRunnersControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var level: Int { privateData.int("level", 1) }
    private var livesCurrent: Int { privateData.int("livesCurrent") }
    private var livesMax: Int { privateData.int("livesMax") }
    private var gemsRemaining: Int { privateData.int("gemsRemaining") }
    private var phase: String { privateData.str("phase", "playing") }
    private var isAlive: Bool { privateData.bool("alive", true) }

    private var canAct: Bool { phase == "playing" && isAlive }

    var body: some View {
        ControllerShell(
            title: "Blast Runners",
            subtitle: "Level \(level) of 25 · \(gemsRemaining) gems left"
        ) {
            VStack(spacing: 18) {
                statusBar

                if !canAct {
                    bannerText
                        .padding(.top, 8)
                }

                Spacer()

                HStack(alignment: .center, spacing: 28) {
                    dpad
                    blastButton
                }
                .padding(.horizontal, 24)

                Spacer()
                Text("Move with the pad, then BLAST to clear rock or knock out enemies")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(0..<max(livesMax, 1), id: \.self) { index in
                    Image(systemName: index < livesCurrent ? "heart.fill" : "heart")
                        .foregroundColor(index < livesCurrent ? .red : .white.opacity(0.25))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var bannerText: some View {
        switch phase {
        case "levelFailed":
            Text("Team down — resetting level \(level)…")
                .font(.headline).foregroundColor(.red)
        case "levelComplete":
            Text("Level \(level) clear!")
                .font(.headline).foregroundColor(.green)
        case "gameComplete":
            Text("All 25 levels cleared!")
                .font(.headline).foregroundColor(.yellow)
        default:
            if !isAlive {
                Text("Respawning…")
                    .font(.headline).foregroundColor(.orange)
            }
        }
    }

    private var dpad: some View {
        VStack(spacing: 10) {
            dpadArrow("up", "chevron.up")
            HStack(spacing: 10) {
                dpadArrow("left", "chevron.left")
                dpadArrow("down", "chevron.down")
                dpadArrow("right", "chevron.right")
            }
        }
    }

    private func dpadArrow(_ direction: String, _ icon: String) -> some View {
        Button(action: { if canAct { onAction("move", ["direction": direction]) } }) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(canAct ? .white : .white.opacity(0.3))
                .frame(width: 64, height: 58)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
        .disabled(!canAct)
    }

    private var blastButton: some View {
        Button(action: { if canAct { onAction("blast", [:]) } }) {
            VStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 30, weight: .bold))
                Text("BLAST")
                    .font(.headline.bold())
            }
            .foregroundColor(canAct ? .black : .white.opacity(0.35))
            .frame(width: 116, height: 116)
            .background(Circle().fill(canAct ? Color.orange : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!canAct)
    }
}
