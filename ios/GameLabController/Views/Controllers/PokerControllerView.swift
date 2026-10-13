import SwiftUI
import UIKit

// MARK: - Poker Controller (private hand on phone)
//
// The phone is the player's private seat: two big hole cards that stay face
// down until held (hold to peek, let go to hide them again), the numbers
// that matter for the decision (stack, pot, to call), and Fold / Check-Call /
// Raise with a raise slider and quick sizes.
//
// Action payloads are unchanged: "fold" and "check"/"call" with no data, and
// "bet" with {"amount": Int} where the amount is the player's total for the
// street (the engine treats it as "raise to").
//
// Styled with the Phone Play look (PhonePlayDesign): its tokens, rounded
// heavy type, surface cards, press style and haptics. The cards themselves
// keep the TV deck's faces and navy-and-gold backs.

struct PokerControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var raiseTo: Double = 0
    @State private var peeking = false
    @State private var showRankings = false

    // MARK: Private state

    private var hand: [String] { privateData["hand"] as? [String] ?? [] }
    private var chips: Int { int("chips") ?? 0 }
    private var canAct: Bool { (privateData["isMyTurn"] as? Bool) ?? false }
    private var minBet: Int { int("minBet") ?? 0 }
    private var toCall: Int { int("toCall") ?? 0 }
    private var myBet: Int { int("myBet") ?? 0 }
    private var tableBet: Int { int("currentBet") ?? (myBet + toCall) }
    private var pot: Int? { int("pot") }
    private var folded: Bool { privateData["folded"] as? Bool ?? false }
    private var allIn: Bool { privateData["allIn"] as? Bool ?? false }
    private var handNumber: Int { int("handNumber") ?? 0 }
    private var maxHands: Int { int("maxHands") ?? 0 }
    private var unlimited: Bool { privateData["unlimited"] as? Bool ?? false }
    private var canRebuy: Bool { privateData["canRebuy"] as? Bool ?? false }
    private var isBroke: Bool { privateData["isBroke"] as? Bool ?? false }
    private var rebuysOn: Bool { privateData["rebuys"] as? Bool ?? false }
    private var stack: Int { int("stack") ?? 1000 }
    private var buyIns: Int { int("buyIns") ?? 1 }
    private var net: Int { int("net") ?? 0 }
    private var votedEnd: Bool { privateData["votedEnd"] as? Bool ?? false }
    private var endVotes: Int { int("endVotes") ?? 0 }
    private var endVotesNeeded: Int { int("endVotesNeeded") ?? 0 }

    private func int(_ key: String) -> Int? {
        if let v = privateData[key] as? Int { return v }
        if let v = privateData[key] as? Double { return Int(v) }
        return nil
    }

    private var lastHandText: String? {
        guard (privateData["phase"] as? String) == "showdown",
              let last = privateData["lastHand"] as? [String: Any],
              let names = last["winnerNames"] as? [Any] else { return nil }
        let who = names.compactMap { $0 as? String }.joined(separator: " & ")
        guard !who.isEmpty else { return nil }
        let amount: Int = last["amount"] as? Int ?? 0
        if let name = last["handName"] as? String, !name.isEmpty {
            return "\(who) won \(PKCFormat.chips(amount)) with \(name)"
        }
        return "\(who) won \(PKCFormat.chips(amount))"
    }

    // MARK: Raise range

    /// Everything this player could put in this street (an all-in total).
    private var maxTotal: Int { chips + myBet }
    /// Smallest legal raise-to total.
    private var minRaise: Int { max(min(minBet, maxTotal), tableBet + 1) }
    /// The table caps raises per street (see PokerEngine.MAX_RAISES); once the
    /// cap is hit the server sends `canRaise: false` and only call/fold remain.
    private var raiseAllowed: Bool { privateData["canRaise"] as? Bool ?? true }
    private var canRaise: Bool { raiseAllowed && maxTotal > tableBet && minRaise <= maxTotal }

    private var raiseAmount: Int {
        let lo: Int = minRaise
        let hi: Int = maxTotal
        let raw: Int = Int(raiseTo.rounded())
        if raw >= hi { return hi }
        let snapped: Int = (raw / 10) * 10
        return min(hi, max(lo, snapped))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)

            Spacer(minLength: 8)

            holeCards

            Text(peekHint)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .padding(.top, 14)

            Spacer(minLength: 8)

            if canAct {
                actionPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 12) {
                    tableControls
                    statusLine
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showRankings) {
            PKCRankingsSheet()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PKCBackground().ignoresSafeArea())
        .animation(PhonePlayDesign.smooth, value: canAct)
        .onAppear { raiseTo = Double(minRaise) }
        .onChange(of: canAct) { _, nowActing in
            if nowActing { raiseTo = Double(minRaise) }
        }
        .onChange(of: minRaise) { _, newValue in
            raiseTo = Double(newValue)
        }
        .onChange(of: handNumber) { _, _ in peeking = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                PhonePlayHaptics.tap()
                showRankings = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Poker hand rankings")
            PKCStat(label: "STACK", value: PKCFormat.chips(chips), tint: PKCColors.gold)
            if let pot {
                PKCStat(label: "POT", value: PKCFormat.chips(pot), tint: .white)
            }
            Spacer(minLength: 4)
            if handNumber > 0 && (maxHands > 0 || unlimited) {
                Text(unlimited ? "HAND \(handNumber)" : "HAND \(handNumber)/\(maxHands)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(PhonePlayDesign.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(PhonePlayDesign.surface))
            }
        }
    }

    // MARK: Hole cards

    private var peekHint: String {
        if hand.isEmpty { return "Waiting for the deal" }
        // A folded player may still look at what they threw away.
        if folded { return peeking ? "Let go to hide" : "You folded. Hold to peek at your cards" }
        return peeking ? "Let go to hide" : "Hold to peek at your cards"
    }

    private var holeCards: some View {
        HStack(spacing: 18) {
            if hand.isEmpty {
                PKCCardBack().frame(width: 140, height: 196).opacity(0.25)
                PKCCardBack().frame(width: 140, height: 196).opacity(0.25)
            } else {
                ForEach(Array(hand.prefix(2).enumerated()), id: \.offset) { i, card in
                    PKCPeekCard(card: card, isFaceUp: peeking)
                        .frame(width: 140, height: 196)
                        .rotationEffect(.degrees(i == 0 ? -4 : 4))
                        .offset(y: peeking ? -8 : 0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75).delay(Double(i) * 0.05),
                                   value: peeking)
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .opacity(folded ? (peeking ? 0.85 : 0.5) : 1)
        .saturation(folded && !peeking ? 0.2 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !peeking, !hand.isEmpty else { return }
                    peeking = true
                    PhonePlayHaptics.rigid()
                }
                .onEnded { _ in peeking = false }
        )
        .id("hand-\(handNumber)")
    }

    // MARK: Waiting / result line

    private var statusLine: some View {
        let text: String
        let tint: Color
        if let result = lastHandText {
            text = result
            tint = PKCColors.gold
        } else if folded {
            text = "Folded -- sit tight for the next hand"
            tint = PhonePlayDesign.text2
        } else if allIn {
            text = "You're all in!"
            tint = PKCColors.red
        } else {
            text = "Waiting for your turn"
            tint = PhonePlayDesign.text2
        }
        return Text(text)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
            )
    }

    // MARK: Your turn

    private var actionPanel: some View {
        VStack(spacing: 14) {
            HStack {
                Text("YOUR TURN")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundColor(PKCColors.gold)
                Spacer()
                Text(toCall > 0 ? "To call: \(PKCFormat.chips(toCall))" : "Nothing to call")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }

            if canRaise {
                raiseControls
            } else if !raiseAllowed && tableBet > 0 {
                Text("Raise limit reached this street")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                PKCActionButton(title: "Fold", subtitle: nil, fill: PKCColors.red, ink: .white) {
                    onAction("fold", [:])
                }
                PKCActionButton(title: callTitle, subtitle: callSubtitle,
                                fill: PhonePlayDesign.surface2, ink: .white) {
                    onAction(toCall > 0 ? "call" : "check", [:])
                }
                if canRaise {
                    PKCActionButton(title: raiseTitle, subtitle: PKCFormat.chips(raiseAmount),
                                    fill: PKCColors.gold, ink: PhonePlayDesign.bg) {
                        onAction("bet", ["amount": raiseAmount])
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(PKCColors.gold.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var callTitle: String {
        if toCall <= 0 { return "Check" }
        return toCall >= chips ? "Call all in" : "Call"
    }

    private var callSubtitle: String? {
        toCall > 0 ? PKCFormat.chips(toCall) : nil
    }

    private var raiseTitle: String {
        if raiseAmount >= maxTotal { return "All in" }
        return tableBet > 0 ? "Raise to" : "Bet"
    }

    private var raiseControls: some View {
        let lo: Double = Double(minRaise)
        let hi: Double = Double(maxTotal)
        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(raiseAmount >= maxTotal ? "ALL IN" : (tableBet > 0 ? "RAISE TO" : "BET"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.text3)
                Spacer()
                Text(PKCFormat.chips(raiseAmount))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(raiseAmount >= maxTotal ? PKCColors.red : PKCColors.gold)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: raiseAmount)
            }
            if hi > lo {
                Slider(value: $raiseTo, in: lo...hi)
                    .tint(PKCColors.gold)
            }
            HStack(spacing: 8) {
                PKCQuickSize(title: "Min") { raiseTo = lo }
                PKCQuickSize(title: "1/2 Pot") { raiseTo = clamp(potSized(0.5), lo, hi) }
                PKCQuickSize(title: "Pot") { raiseTo = clamp(potSized(1.0), lo, hi) }
                PKCQuickSize(title: "All in") { raiseTo = hi }
            }
        }
    }

    /// A raise-to total of `fraction` of the pot after calling.
    private func potSized(_ fraction: Double) -> Double {
        let potAfterCall: Double = Double((pot ?? 0) + toCall)
        return Double(tableBet) + potAfterCall * fraction
    }

    private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, value))
    }
}

// MARK: - Table controls (re-buy, end the game)

extension PokerControllerView {
    /// Between hands: buy back in when short, and (in an unlimited game)
    /// vote to end. Hidden when there is nothing to offer.
    @ViewBuilder
    fileprivate var tableControls: some View {
        VStack(spacing: 10) {
            if rebuysOn && (buyIns > 1 || net != 0) {
                Text(netLine)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(net >= 0 ? PKCColors.gold : PhonePlayDesign.text2)
            }
            if canRebuy {
                PKCActionButton(title: "Buy back in",
                                subtitle: "+" + PKCFormat.chips(stack),
                                fill: PKCColors.gold, ink: PhonePlayDesign.bg) {
                    PhonePlayHaptics.thump()
                    onAction("rebuy", [:])
                }
                if isBroke {
                    Button {
                        PhonePlayHaptics.tap()
                        onAction("sit_out", [:])
                    } label: {
                        Text("Sit this hand out")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .padding(.vertical, 8)
                    }
                }
            }
            if unlimited {
                Button {
                    PhonePlayHaptics.tap()
                    onAction("vote_end", [:])
                } label: {
                    Text(votedEnd
                         ? "You want to end (\(endVotes)/\(endVotesNeeded)). Tap to undo"
                         : "End the game (\(endVotes)/\(endVotesNeeded) agree)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(votedEnd ? PKCColors.red : PhonePlayDesign.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .fill(PhonePlayDesign.surface)
                        )
                }
            }
        }
    }

    fileprivate var netLine: String {
        let sign: String = net >= 0 ? "+" : "-"
        return "Bought in \(buyIns)x  |  Net \(sign)\(PKCFormat.chips(abs(net)))"
    }
}

// MARK: - Hand rankings ("i" button)

private struct PKCRankingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Rank: Identifiable {
        let id: Int
        let name: String
        let example: String
        let note: String
    }

    private let ranks: [Rank] = [
        Rank(id: 1, name: "Royal Flush", example: "A\u{2660} K\u{2660} Q\u{2660} J\u{2660} 10\u{2660}", note: "Ace to ten, one suit"),
        Rank(id: 2, name: "Straight Flush", example: "9\u{2665} 8\u{2665} 7\u{2665} 6\u{2665} 5\u{2665}", note: "Five in a row, one suit"),
        Rank(id: 3, name: "Four of a Kind", example: "Q\u{2660} Q\u{2665} Q\u{2666} Q\u{2663} 4\u{2660}", note: "Four cards of one rank"),
        Rank(id: 4, name: "Full House", example: "K\u{2660} K\u{2665} K\u{2666} 8\u{2663} 8\u{2660}", note: "Three of a kind plus a pair"),
        Rank(id: 5, name: "Flush", example: "A\u{2666} J\u{2666} 8\u{2666} 6\u{2666} 2\u{2666}", note: "Five cards of one suit"),
        Rank(id: 6, name: "Straight", example: "10\u{2660} 9\u{2665} 8\u{2666} 7\u{2663} 6\u{2660}", note: "Five in a row, any suits"),
        Rank(id: 7, name: "Three of a Kind", example: "7\u{2660} 7\u{2665} 7\u{2666} K\u{2663} 2\u{2660}", note: "Three cards of one rank"),
        Rank(id: 8, name: "Two Pair", example: "J\u{2660} J\u{2665} 4\u{2666} 4\u{2663} A\u{2660}", note: "Two different pairs"),
        Rank(id: 9, name: "One Pair", example: "10\u{2660} 10\u{2665} A\u{2666} 7\u{2663} 3\u{2660}", note: "Two cards of one rank"),
        Rank(id: 10, name: "High Card", example: "A\u{2660} J\u{2665} 8\u{2666} 5\u{2663} 2\u{2660}", note: "None of the above: highest card plays"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Best hand wins. Strongest at the top.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .padding(.bottom, 4)
                    ForEach(ranks) { rank in
                        HStack(spacing: 12) {
                            Text("\(rank.id)")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(PKCColors.gold)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rank.name)
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                Text(rank.example)
                                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                                    .foregroundColor(PKCColors.gold)
                                Text(rank.note)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(PhonePlayDesign.text3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface))
                    }
                    Text("Each player makes the best five cards from their two cards plus the five on the table.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                }
                .padding(16)
            }
            .background(PhonePlayDesign.bg.ignoresSafeArea())
            .navigationTitle("Hand rankings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Pieces

private enum PKCColors {
    static let gold: Color = PhonePlayDesign.yellow
    static let red: Color = PhonePlayDesign.red
}

private enum PKCFormat {
    static func chips(_ value: Int) -> String {
        value.formatted(.number)
    }
}

/// The Phone Play backdrop with a faint green glow behind the cards, a
/// nod to the table's felt.
private struct PKCBackground: View {
    var body: some View {
        ZStack {
            PhonePlayDesign.bg
            RadialGradient(colors: [PhonePlayDesign.green.opacity(0.16), Color.clear],
                           center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: 420)
        }
    }
}

private struct PKCStat: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(tint)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous).fill(PhonePlayDesign.surface))
    }
}

private struct PKCQuickSize: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            action()
        }) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Capsule().fill(PhonePlayDesign.surface2))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

private struct PKCActionButton: View {
    let title: String
    let subtitle: String?
    let fill: Color
    let ink: Color
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .opacity(0.85)
                        .lineLimit(1)
                }
            }
            .foregroundColor(ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient([fill, fill.opacity(0.75)]))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: fill.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

// MARK: - Cards

private enum PKCSuit {
    static func parse(_ card: String) -> (rank: String, suit: String) {
        guard let last = card.last else { return ("", "") }
        return (String(card.dropLast()), String(last))
    }

    static func isRed(_ suit: String) -> Bool {
        suit == "\u{2665}" || suit == "\u{2666}"
    }

    static func symbol(_ suit: String) -> String {
        switch suit {
        case "\u{2665}": return "suit.heart.fill"
        case "\u{2666}": return "suit.diamond.fill"
        case "\u{2663}": return "suit.club.fill"
        default: return "suit.spade.fill"
        }
    }
}

/// A hole card that flips face up while `isFaceUp` (the peek) and back down
/// when released. The face swap happens per animation frame at 90 degrees,
/// so neither side is ever seen mirrored.
private struct PKCPeekCard: View {
    let card: String
    let isFaceUp: Bool

    var body: some View {
        let angle: Double = isFaceUp ? 0 : 180
        return ZStack {
            PKCCardBack()
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .modifier(PKCFaceVisibility(angle: angle, isFront: false))
            PKCCardFace(card: card)
                .modifier(PKCFaceVisibility(angle: angle, isFront: true))
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isFaceUp)
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 8)
    }
}

private struct PKCFaceVisibility: ViewModifier, Animatable {
    var angle: Double
    let isFront: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let frontShowing: Bool = angle < 90
        return content.opacity(frontShowing == isFront ? 1 : 0)
    }
}

private struct PKCCardFace: View {
    let card: String

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let parts = PKCSuit.parse(card)
            let ink: Color = PKCSuit.isRed(parts.suit) ? GamePieceColors.cardRedInk
                                                       : GamePieceColors.cardBlackInk
            let shape = RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
            ZStack {
                shape.fill(LinearGradient(colors: [GamePieceColors.faceWhite, GamePieceColors.faceWhiteEdge],
                                          startPoint: .top, endPoint: .bottom))
                shape.strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
                VStack(spacing: 0) {
                    Text(parts.rank)
                        .font(.system(size: w * (parts.rank.count > 1 ? 0.34 : 0.4), weight: .heavy, design: .rounded))
                    Image(systemName: PKCSuit.symbol(parts.suit))
                        .font(.system(size: w * 0.2, weight: .bold, design: .rounded))
                }
                .foregroundColor(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, w * 0.09)
                .padding(.top, w * 0.06)
                Image(systemName: PKCSuit.symbol(parts.suit))
                    .font(.system(size: w * 0.5, weight: .bold, design: .rounded))
                    .foregroundColor(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(w * 0.1)
            }
        }
    }
}

/// Navy back with a gold frame, matching the TV table's deck.
private struct PKCCardBack: View {
    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let shape = RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
            let inner = RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
            ZStack {
                shape.fill(Color.white)
                inner
                    .fill(LinearGradient(colors: [GamePieceColors.cardBackTop, GamePieceColors.cardBackBottom],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(inner.strokeBorder(PKCColors.gold.opacity(0.75), lineWidth: 2))
                    .padding(w * 0.07)
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: w * 0.3, weight: .bold, design: .rounded))
                    .foregroundColor(PKCColors.gold)
            }
        }
    }
}
