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
    private var canRaise: Bool { maxTotal > tableBet && minRaise <= maxTotal }

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
                statusLine
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
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
            PKCStat(label: "STACK", value: PKCFormat.chips(chips), tint: PKCColors.gold)
            if let pot {
                PKCStat(label: "POT", value: PKCFormat.chips(pot), tint: .white)
            }
            Spacer(minLength: 4)
            if maxHands > 0 && handNumber > 0 {
                Text("HAND \(handNumber)/\(maxHands)")
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
        if folded { return "You folded this hand" }
        return peeking ? "Let go to hide" : "Hold to peek at your cards"
    }

    private var holeCards: some View {
        HStack(spacing: 18) {
            if hand.isEmpty {
                PKCCardBack().frame(width: 140, height: 196).opacity(0.25)
                PKCCardBack().frame(width: 140, height: 196).opacity(0.25)
            } else {
                ForEach(Array(hand.prefix(2).enumerated()), id: \.offset) { i, card in
                    PKCPeekCard(card: card, isFaceUp: peeking && !folded)
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
        .opacity(folded ? 0.35 : 1)
        .saturation(folded ? 0 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !peeking, !hand.isEmpty, !folded else { return }
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(PhonePlayDesign.surface))
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
                        .font(.system(size: w * 0.2, weight: .bold))
                }
                .foregroundColor(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, w * 0.09)
                .padding(.top, w * 0.06)
                Image(systemName: PKCSuit.symbol(parts.suit))
                    .font(.system(size: w * 0.5, weight: .bold))
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
                    .font(.system(size: w * 0.3, weight: .bold))
                    .foregroundColor(PKCColors.gold)
            }
        }
    }
}
