import SwiftUI
import CoreMotion
import UIKit

// Styled with the Phone Play look (PhonePlayDesign): surface cards, rounded
// heavy type, gradient buttons that squash under the finger, and haptics.
// The results screen further down keeps its own styling.

// MARK: - Shared pieces

private extension View {
    /// A Phone Play surface card, optionally edged in an accent colour.
    func otherPadCard(_ accent: Color? = nil,
                      radius: CGFloat = PhonePlayDesign.cardRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.4) ?? Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

/// A short status line in a tinted capsule.
private struct OtherPadPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = PhonePlayDesign.cyan
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(filled ? .black : tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(filled ? tint : tint.opacity(0.14)))
    }
}

// MARK: - Poker Controller
//
// Moved to PokerControllerView.swift.

// MARK: - Snake & Ladder — Shake to Roll

struct ShakeToRollControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var lastRoll: Int? = nil
    @State private var diceScale: CGFloat = 1.0
    @State private var diceRotation: Double = 0
    /// Seq of the last slide event this phone already buzzed for -- the
    /// engine keeps `lastSlide` in private state until the player's next
    /// move, so without this every re-broadcast would buzz again.
    @State private var lastBuzzedSlideSeq: Int? = nil
    /// True between a tap and the roll being sent, so a double tap can
    /// never send two rolls (a 6 keeps `isMyTurn` true for the bonus roll).
    @State private var isRolling = false
    private var isMyTurn: Bool { (privateData["isMyTurn"] as? Bool) ?? false }
    /// The engine says this player just rolled a 6 and goes again
    /// (`SnakeLadderEngine.private_state`'s `rollAgain`).
    private var rollAgain: Bool { (privateData["rollAgain"] as? Bool) ?? false }

    /// This player's own latest slide event, if their last roll landed on
    /// a snake head or ladder bottom (`SnakeLadderEngine.private_state`).
    private var slideEvent: (kind: String, seq: Int)? {
        guard let slide = privateData["lastSlide"] as? [String: Any],
              let kind = slide["kind"] as? String,
              let seq = slide["seq"] as? Int else { return nil }
        return (kind, seq)
    }

    var body: some View {
        ControllerShell(title: "Snakes & Ladders",
                        subtitle: isMyTurn ? "Your turn" : "Waiting for your turn") {
            VStack(spacing: 26) {
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
                        .shadow(color: PhonePlayDesign.cyan.opacity(isMyTurn ? 0.45 : 0), radius: 26)
                        .phonePlayIdle(dy: 4, duration: 1.3)
                }
                .buttonStyle(PhonePlayPressStyle())
                .disabled(!isMyTurn)
                .onShake { roll() }
                .accessibilityLabel("Roll the dice")

                if let roll = lastRoll {
                    Text("You rolled \(roll)!")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText(value: Double(roll)))
                }

                if rollAgain && isMyTurn {
                    OtherPadPill(text: "Rolled a 6, roll again!",
                                 systemImage: "arrow.counterclockwise.circle.fill",
                                 tint: PhonePlayDesign.yellow, filled: true)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                OtherPadPill(text: isMyTurn ? "Shake or tap the die to roll!" : "Not your turn…",
                             systemImage: isMyTurn ? "hand.tap.fill" : "hourglass",
                             tint: isMyTurn ? PhonePlayDesign.cyan : PhonePlayDesign.text3)

                if let pos = privateData["position"] as? Int {
                    Text("Your position: \(pos)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }

                Spacer()
            }
            .animation(PhonePlayDesign.pop, value: lastRoll)
            .animation(PhonePlayDesign.pop, value: isMyTurn)
            .animation(PhonePlayDesign.pop, value: rollAgain)
        }
        .onChange(of: slideEvent?.seq ?? -1) { _, seq in
            // A fresh slide event for this player: buzz once. A snake bite
            // is an error-style jolt, a ladder climb a success-style tap.
            guard seq >= 0, seq != lastBuzzedSlideSeq else { return }
            lastBuzzedSlideSeq = seq
            playSlideHaptic(kind: slideEvent?.kind)
        }
    }

    /// Optional, safe haptic: the feedback generators no-op on devices
    /// without a haptic engine, so this is purely additive.
    private func playSlideHaptic(kind: String?) {
        switch kind {
        case "snake": PhonePlayHaptics.error()
        case "ladder": PhonePlayHaptics.success()
        default: break
        }
    }

    private func roll() {
        guard isMyTurn, !isRolling else { return }
        isRolling = true
        PhonePlayHaptics.thump()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.35)) { diceScale = 1.28 }
        withAnimation(.easeOut(duration: 0.55)) { diceRotation += 360 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(PhonePlayDesign.pop) { diceScale = 1.0 }
            let value = Int.random(in: 1...6)
            lastRoll = value
            onAction("roll", ["value": value])
            // Leave a beat for the server's reply before the die can be
            // rolled again (only possible after a 6).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isRolling = false }
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
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(LinearGradient(colors: [GamePieceColors.faceWhite, GamePieceColors.faceWhiteEdge],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 2)
            ForEach(Array(pipPositions.enumerated()), id: \.offset) { _, pip in
                Circle()
                    .fill(PhonePlayDesign.bg)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .position(x: pip.0 * size, y: pip.1 * size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
    }
}

// MARK: - Mind Meld

struct MindMeldControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var wordInput = ""
    /// The round this phone submitted in. Compared against the server's round
    /// so a new round re-opens the input (it used to stay locked after round 1).
    @State private var submittedRound: Int? = nil
    private var category: String { privateData["category"] as? String ?? "" }
    private var round: Int { privateData["round"] as? Int ?? 0 }
    private var totalRounds: Int { privateData["totalRounds"] as? Int ?? 0 }
    private var showReveal: Bool { privateData["showReveal"] as? Bool ?? false }
    private var myWord: String? { privateData["myWord"] as? String }
    private var hasSubmitted: Bool {
        (privateData["hasSubmitted"] as? Bool ?? false) || submittedRound == round
    }

    var body: some View {
        ControllerShell(title: "Mind Meld",
                        subtitle: totalRounds > 0 ? "Round \(round) of \(totalRounds)" : nil) {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Text("CATEGORY")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(PhonePlayDesign.purple)
                    Text(category)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Type ONE word that fits the category.\nTry to match what others think!")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .otherPadCard(PhonePlayDesign.purple)
                .padding(.horizontal, 20)
                .padding(.top, 14)

                if showReveal {
                    WaitingState(systemIcon: "tv", text: "Look at the TV for the melds!")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else if !hasSubmitted {
                    VStack(spacing: 14) {
                        Spacer()
                        AnswerField(placeholder: "Your word…", text: $wordInput, autocapitalize: false)
                            .submitLabel(.send)
                            .onSubmit(submit)
                        BigButton(title: "Submit", systemImage: "paperplane.fill",
                                  tint: PhonePlayDesign.purple,
                                  enabled: !wordInput.trimmingCharacters(in: .whitespaces).isEmpty) {
                            submit()
                        }
                        Spacer()
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    WaitingState(systemIcon: "brain.filled.head.profile",
                                 text: "You said \"\(myWord ?? wordInput)\"",
                                 detail: "Waiting for the others…")
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: showReveal)
            .animation(PhonePlayDesign.pop, value: hasSubmitted)
        }
        .onChange(of: round) { _, _ in
            wordInput = ""
            submittedRound = nil
        }
    }

    private func submit() {
        let word = wordInput.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !hasSubmitted else { return }
        submittedRound = round
        onAction("word", ["word": word.lowercased()])
    }
}

// MARK: - Speed Sculptor (drawing canvas)

struct SpeedSculptorControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var lines: [DrawLine] = []
    @State private var currentLine: DrawLine? = nil
    @State private var submittedRound: Int? = nil
    @State private var canvasSize: CGSize = .zero
    private var prompt: String { privateData["prompt"] as? String ?? "?" }
    private var round: Int { privateData["round"] as? Int ?? 0 }
    private var votingPhase: Bool { privateData["votingPhase"] as? Bool ?? false }
    private var secondsLeft: Int { privateData["secondsLeft"] as? Int ?? 0 }
    private var myVote: String? { privateData["myVote"] as? String }
    private var submitted: Bool {
        (privateData["hasSubmitted"] as? Bool ?? false) || submittedRound == round
    }
    private var candidates: [(id: String, name: String)] {
        (privateData["candidates"] as? [Any] ?? []).compactMap {
            guard let d = $0 as? [String: Any], let id = d["id"] as? String else { return nil }
            return (id, d["playerName"] as? String ?? "Player")
        }
    }

    var body: some View {
        ControllerShell(title: "Speed Sculptor",
                        subtitle: votingPhase ? "Vote: best \(prompt)" : "Draw: \(prompt)",
                        secondsLeft: secondsLeft) {
            VStack(spacing: 0) {
                if votingPhase {
                    votingList
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    VStack(spacing: 10) {
                        HStack {
                            Text("YOUR CANVAS")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .tracking(2)
                                .foregroundColor(PhonePlayDesign.purple)
                                .lineLimit(1)
                            Spacer()
                            if !submitted {
                                Button(action: {
                                    PhonePlayHaptics.tap()
                                    lines = []
                                    currentLine = nil
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text("Clear")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                    }
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(PhonePlayPressStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        drawingCanvas
                            .padding(.horizontal, 16)

                        if !submitted {
                            BigButton(title: "Submit Drawing", systemImage: "paperplane.fill",
                                      tint: PhonePlayDesign.purple) {
                                submitDrawing()
                            }
                            .padding(.vertical, 12)
                        } else {
                            OtherPadPill(text: "Submitted! Watch the TV.",
                                         systemImage: "checkmark.circle.fill",
                                         tint: PhonePlayDesign.green)
                                .padding(.vertical, 18)
                        }
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .animation(PhonePlayDesign.pop, value: votingPhase)
            .animation(PhonePlayDesign.pop, value: submitted)
        }
        .onChange(of: round) { _, _ in
            lines = []
            currentLine = nil
            submittedRound = nil
        }
    }

    private var drawingCanvas: some View {
        Canvas { ctx, size in
            for line in lines + (currentLine.map { [$0] } ?? []) {
                var path = Path()
                guard let first = line.points.first else { continue }
                path.move(to: first)
                for pt in line.points.dropFirst() { path.addLine(to: pt) }
                ctx.stroke(path, with: .color(line.color), style: .init(lineWidth: line.width, lineCap: .round, lineJoin: .round))
            }
        }
        .background(Color.white)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
        })
        .clipShape(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(PhonePlayDesign.purple.opacity(0.5), lineWidth: 2)
        )
        .allowsHitTesting(!submitted)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if currentLine == nil {
                        currentLine = DrawLine(points: [value.location], color: .black, width: 4)
                    } else if let last = currentLine?.points.last,
                              hypot(value.location.x - last.x, value.location.y - last.y) >= 3 {
                        // Skip near-duplicate points: keeps the payload small.
                        currentLine?.points.append(value.location)
                    }
                }
                .onEnded { _ in
                    if let line = currentLine { lines.append(line) }
                    currentLine = nil
                }
        )
    }

    private var votingList: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Look at the drawings on the TV and vote for your favourite")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                if candidates.isEmpty {
                    Text("No other drawings this round")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
                ForEach(candidates, id: \.id) { c in
                    ChoiceRow(text: c.name, selected: myVote == c.id) {
                        onAction("vote", ["targetID": c.id])
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func submitDrawing() {
        guard !submitted else { return }
        submittedRound = round
        let w = max(Double(canvasSize.width), 1)
        let h = max(Double(canvasSize.height), 1)
        // Normalised [x, y] pairs (0...1), 3 decimals -- what the TV draws.
        let encoded: [[[Double]]] = lines.map { line in
            line.points.map { p in
                [(Double(p.x) / w * 1000).rounded() / 1000,
                 (Double(p.y) / h * 1000).rounded() / 1000]
            }
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

    /// Parsed element by element: the ticket's blanks arrive as JSON null
    /// (NSNull), which a blanket `as? [[Int?]]` cast cannot be relied on to
    /// accept -- it would leave the whole ticket empty.
    private var ticket: [[Int?]] {
        (privateData["ticket"] as? [Any] ?? []).map { row in
            (row as? [Any] ?? []).map { $0 as? Int }
        }
    }
    private var markedNumbers: Set<Int> {
        Set((privateData["marked"] as? [Any] ?? []).compactMap { $0 as? Int })
    }
    private var calledOnTicket: Set<Int> {
        Set((privateData["calledOnTicket"] as? [Any] ?? []).compactMap { $0 as? Int })
    }
    private var lastCalled: Int? { privateData["lastCalled"] as? Int }
    private var score: Int { privateData["score"] as? Int ?? 0 }
    private var prizes: [(type: String, label: String, winner: String?)] {
        (privateData["prizes"] as? [Any] ?? []).compactMap {
            guard let d = $0 as? [String: Any], let type = d["type"] as? String else { return nil }
            return (type, d["label"] as? String ?? type, d["winnerName"] as? String)
        }
    }

    var body: some View {
        ControllerShell(title: "Tambola", subtitle: "Score \(score)") {
            ScrollView {
                VStack(spacing: 14) {
                    if let lastCalled {
                        VStack(spacing: 2) {
                            Text("LAST CALLED")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .tracking(2)
                                .foregroundColor(PhonePlayDesign.text3)
                            Text("\(lastCalled)")
                                .font(.system(size: 58, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow,
                                                                           PhonePlayDesign.orange]))
                                .contentTransition(.numericText(value: Double(lastCalled)))
                                .animation(PhonePlayDesign.pop, value: lastCalled)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .otherPadCard(PhonePlayDesign.yellow)
                    }

                    Text("Tap called numbers on your ticket")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)

                    // Cells share the width rather than a fixed 36pt each, so
                    // a nine-column row never runs off a small phone.
                    VStack(spacing: 5) {
                        ForEach(Array(ticket.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 4) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, num in
                                    if let n = num {
                                        let marked = markedNumbers.contains(n)
                                        let called = calledOnTicket.contains(n)
                                        Button(action: {
                                            PhonePlayHaptics.tap()
                                            onAction(marked ? "unmark" : "mark", ["number": n])
                                        }) {
                                            Text("\(n)")
                                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                                .monospacedDigit()
                                                .minimumScaleFactor(0.7)
                                                .lineLimit(1)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 42)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                        .fill(marked
                                                              ? PhonePlayDesign.gradient([PhonePlayDesign.green,
                                                                                          PhonePlayDesign.green.opacity(0.7)])
                                                              : PhonePlayDesign.gradient([PhonePlayDesign.surface2,
                                                                                          PhonePlayDesign.surface2]))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                        .strokeBorder(called && !marked ? PhonePlayDesign.yellow : Color.clear,
                                                                      lineWidth: 2)
                                                )
                                                .foregroundColor(marked ? .black : .white)
                                        }
                                        .buttonStyle(PhonePlayPressStyle())
                                    } else {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(Color.white.opacity(0.03))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 42)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .otherPadCard()

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(prizes, id: \.type) { prize in
                            Button(action: {
                                PhonePlayHaptics.thump()
                                onAction("claim", ["type": prize.type])
                            }) {
                                VStack(spacing: 2) {
                                    Text(prize.label)
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    if let winner = prize.winner {
                                        Text("won by \(winner)")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                        .fill(prize.winner == nil
                                              ? PhonePlayDesign.gradient([PhonePlayDesign.yellow, PhonePlayDesign.orange])
                                              : PhonePlayDesign.gradient([PhonePlayDesign.surface, PhonePlayDesign.surface]))
                                )
                                .foregroundColor(prize.winner == nil ? .black : PhonePlayDesign.text3)
                            }
                            .buttonStyle(PhonePlayPressStyle())
                            .disabled(prize.winner != nil)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Generic tap controller (fallback)

struct GenericTapControllerView: View {
    let room: Room
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([PhonePlayDesign.indigo.opacity(0.55),
                                                    PhonePlayDesign.cyan.opacity(0.35)]))
                    .frame(width: 120, height: 120)
                Image(systemName: room.gameID.sfSymbol)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
            Text(room.gameID.displayName)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Game in progress")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhonePlayDesign.bg.ignoresSafeArea())
    }
}

// TV board views are defined in TVClassicGameBoards.swift and TVHeistBoardView.swift
// TVResultsView moved to Shared/Views/ResultsView.swift — GameLabTV's
// RootTVView needs it, and this file only compiles into GameLabController.

// MARK: - Results views

struct ResultsControllerView: View {
    let room: Room
    let onLeave: () -> Void
    let onPlayAgain: () -> Void

    @EnvironmentObject private var vm: ControllerRootViewModel
    @State private var appeared = false

    private var myID: String { vm.playerID }
    private var sorted: [Player] { room.players.sorted { $0.score > $1.score } }
    private var myRank: Int {
        (sorted.firstIndex(where: { $0.id == myID }) ?? 0) + 1
    }

    // Phone Play look (PhonePlayDesign / PhonePlayBigButton): this screen
    // is the phone's, not a game controller's.
    private var rankColors: [Color] {
        switch myRank {
        case 1:  return [PhonePlayDesign.yellow, PhonePlayDesign.orange]
        case 2:  return [PhonePlayDesign.cyan, PhonePlayDesign.indigo]
        case 3:  return [PhonePlayDesign.orange, PhonePlayDesign.pink]
        default: return [PhonePlayDesign.purple, PhonePlayDesign.blue]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Game Over")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [PhonePlayDesign.orange, PhonePlayDesign.pink, PhonePlayDesign.purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Text(room.gameID.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            .padding(.top, 36).padding(.bottom, 20)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)

            // My rank callout
            HStack(spacing: 14) {
                Image(systemName: myRank == 1 ? "trophy.fill" : (myRank <= 3 ? "medal.fill" : "star.fill"))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .phonePlayIdle(dy: 3, degrees: 5, duration: 1.2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You finished \(ordinal(myRank))")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    if let me = sorted.first(where: { $0.id == myID }) {
                        Text("\(me.score) points")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(rankColors))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: (rankColors.first ?? .clear).opacity(0.35), radius: 14, y: 8)
            .padding(.horizontal, 20)
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .animation(PhonePlayDesign.pop.delay(0.08), value: appeared)

            // Full leaderboard
            ScrollView {
                VStack(spacing: 8) {
                    PhonePlaySectionLabel(text: "Leaderboard")
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { rank, player in
                        HStack(spacing: 12) {
                            Text("\(rank + 1)")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundColor(rank < 3 ? .black : .white.opacity(0.75))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(rank < 3 ? NightStandingsList.rankColor(rank + 1)
                                                                   : PhonePlayDesign.surface2))
                            Text(player.name)
                                .font(.system(size: 17, weight: player.id == myID ? .heavy : .semibold,
                                              design: .rounded))
                                .foregroundColor(player.id == myID ? PhonePlayDesign.cyan : .white)
                                .lineLimit(1)
                            if player.id == myID {
                                Text("YOU")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(PhonePlayDesign.cyan))
                            }
                            Spacer()
                            Text("\(player.score)")
                                .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .fill(player.id == myID ? PhonePlayDesign.cyan.opacity(0.12) : PhonePlayDesign.surface)
                        )
                        .offset(y: appeared ? 0 : 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(PhonePlayDesign.pop.delay(0.15 + Double(min(rank, 8)) * 0.05), value: appeared)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 18)
            }

            Spacer(minLength: 8)

            // Rematch. start_game is host-or-TV-only server-side, so this
            // mirrors the lobby's host gating (see WaitingView/HostLobbyControls):
            // only the host's phone gets the button; everyone else sees a
            // waiting note. The emitted action is identical to the TV's
            // Play Again (TVRootViewModel.playAgain) -- start_game with the
            // same room code -- and the existing privateState handler moves
            // this phone results -> playing when the restart pumps.
            // During a Game Night the night panel replaces Play Again: the
            // host moves the room to the next game (or ends the night)
            // instead of replaying this one (Views/OneStop/GameNightViews).
            if let night = room.night {
                GameNightResultsPanel(room: room, night: night, isHost: vm.isHost,
                                      myID: vm.playerID)
                    .padding(.horizontal, 20).padding(.bottom, 12)
            } else if vm.isHost {
                PhonePlayBigButton(title: "Play Again", symbol: "arrow.clockwise",
                                   colors: [PhonePlayDesign.purple, PhonePlayDesign.pink],
                                   action: onPlayAgain)
                    .padding(.horizontal, 20).padding(.bottom, 12)
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.9).tint(PhonePlayDesign.text2)
                    Text("Waiting for the host to start a rematch")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }

            PhonePlayGhostButton(title: "Leave Room", symbol: "arrow.left.circle", action: onLeave)
                .padding(.horizontal, 20).padding(.bottom, 28)
        }
        .background(PhonePlayDesign.bg.ignoresSafeArea())
        .onAppear {
            if myRank == 1 { PhonePlayHaptics.success() } else { PhonePlayHaptics.tap() }
            withAnimation(PhonePlayDesign.pop) { appeared = true }
        }
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

