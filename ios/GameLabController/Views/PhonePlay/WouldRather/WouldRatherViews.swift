import SwiftUI

// MARK: - Would You Rather screens

private enum WouldRatherStyle {
    static let colors: [Color] = [PhonePlayDesign.blue, PhonePlayDesign.orange]
    static let sideA: [Color] = [PhonePlayDesign.blue, PhonePlayDesign.cyan]
    static let sideB: [Color] = [PhonePlayDesign.orange, PhonePlayDesign.red]

    static func colors(for side: WouldRatherViewModel.Side) -> [Color] {
        switch side {
        case .a: return sideA
        case .b: return sideB
        }
    }
}

struct WouldRatherRootView: View {
    @ObservedObject var game: WouldRatherViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                WouldRatherSetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .play:
                WouldRatherPlayView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct WouldRatherSetupView: View {
    @ObservedObject var game: WouldRatherViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Would You Rather", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 50, weight: .bold))
                            .foregroundStyle(PhonePlayDesign.gradient(WouldRatherStyle.colors))
                            .phonePlayIdle(dx: 6, duration: 0.8)
                        Text("Would You Rather")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Two choices, no fence-sitting. Pick a side and argue for it, or pass the phone round for a secret vote.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 10) {
                        PhonePlaySectionLabel(text: "How to play")
                        HStack(spacing: 10) {
                            ForEach(WouldRatherViewModel.Mode.allCases) { mode in
                                PhonePlayChip(title: mode.title, subtitle: mode.subtitle,
                                              selected: game.mode == mode,
                                              colors: WouldRatherStyle.colors) {
                                    game.setMode(mode)
                                }
                            }
                        }
                        Text(game.mode == .pick
                             ? "Everyone shouts their answer, then one person taps the winning side."
                             : "Each player taps their side in secret and passes the phone on. Reveal when everyone has voted.")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("\(game.poolCount) dilemmas ready")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PhonePlayAIButton(state: game.aiState, accent: PhonePlayDesign.blue) {
                        game.fetchFreshCards()
                    }

                    PhonePlayBigButton(title: "Start", symbol: "play.fill",
                                       colors: WouldRatherStyle.colors) {
                        game.start()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Play

private struct WouldRatherPlayView: View {
    @ObservedObject var game: WouldRatherViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Would You Rather", backTitle: "Setup", onBack: game.backToSetup)

            Text("WOULD YOU RATHER")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(PhonePlayDesign.text3)
                .padding(.top, 4)
                .padding(.bottom, 10)

            WouldRatherSplitCard(game: game)
                .id(game.cardNumber)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .padding(.horizontal, 16)

            footer
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .animation(PhonePlayDesign.smooth, value: game.cardNumber)
        .animation(PhonePlayDesign.pop, value: game.revealed)
    }

    @ViewBuilder
    private var footer: some View {
        switch game.mode {
        case .pick:
            PhonePlayBigButton(title: "Next dilemma", symbol: "arrow.right",
                               colors: WouldRatherStyle.colors) {
                game.next()
            }
        case .count:
            if game.revealed {
                PhonePlayBigButton(title: "Next dilemma", symbol: "arrow.right",
                                   colors: WouldRatherStyle.colors) {
                    game.next()
                }
            } else {
                VStack(spacing: 10) {
                    Text(game.totalVotes == 1 ? "1 vote in" : "\(game.totalVotes) votes in")
                        .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.text2)
                        .contentTransition(.numericText())
                        .animation(PhonePlayDesign.pop, value: game.totalVotes)
                    HStack(spacing: 12) {
                        PhonePlayGhostButton(title: "Clear", symbol: "arrow.counterclockwise") {
                            game.clearVotes()
                        }
                        .frame(maxWidth: 130)
                        PhonePlayBigButton(title: "Reveal", symbol: "eye.fill",
                                           colors: WouldRatherStyle.colors,
                                           enabled: game.totalVotes > 0) {
                            game.reveal()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - The split card

private struct WouldRatherSplitCard: View {
    @ObservedObject var game: WouldRatherViewModel

    var body: some View {
        VStack(spacing: 6) {
            WouldRatherHalf(game: game, side: .a, text: game.current.a)
            WouldRatherHalf(game: game, side: .b, text: game.current.b)
        }
        .overlay(
            Text("OR")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 62, height: 62)
                .background(Circle().fill(Color.white))
                .overlay(Circle().strokeBorder(PhonePlayDesign.bg, lineWidth: 5))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .allowsHitTesting(false)
        )
    }
}

private struct WouldRatherHalf: View {
    @ObservedObject var game: WouldRatherViewModel
    let side: WouldRatherViewModel.Side
    let text: String

    @State private var bump: Int = 0

    private var displayText: String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    private var isPicked: Bool { game.mode == .pick && game.picked == side }
    private var isDimmed: Bool {
        if game.mode == .pick, let picked = game.picked { return picked != side }
        if game.mode == .count && game.revealed { return game.share(side) < 0.5 }
        return false
    }

    var body: some View {
        Button {
            game.tap(side)
            bump += 1
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(WouldRatherStyle.colors(for: side)))
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(isPicked ? 0.9 : 0.15), lineWidth: isPicked ? 4 : 1)
                    )

                if game.mode == .count && game.revealed {
                    revealFill
                }

                VStack(spacing: 10) {
                    Text(displayText)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.45)
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    badge
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isDimmed ? 0.45 : 1)
            .scaleEffect(isPicked ? 1.02 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(game.mode == .count && game.revealed)
        .animation(PhonePlayDesign.pop, value: isPicked)
        .animation(PhonePlayDesign.smooth, value: isDimmed)
    }

    @ViewBuilder
    private var badge: some View {
        if isPicked {
            Label("Defend it!", systemImage: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white))
                .transition(.scale.combined(with: .opacity))
        } else if game.mode == .count && game.revealed {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int((game.share(side) * 100).rounded()))%")
                    .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                Text(game.votes(side) == 1 ? "1 vote" : "\(game.votes(side)) votes")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .opacity(0.85)
            }
            .foregroundColor(.white)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if game.mode == .count {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .symbolEffect(.bounce, value: bump)
        }
    }

    /// A darker band whose width shows the side's share of the votes.
    private var revealFill: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: geo.size.width * CGFloat(game.share(side)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous))
        .transition(.opacity)
    }
}
