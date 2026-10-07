import SwiftUI

// MARK: - Truth or Dare screens

private enum TruthDareStyle {
    static let colors: [Color] = [PhonePlayDesign.pink, PhonePlayDesign.purple]
    static let truth: [Color] = [PhonePlayDesign.cyan, PhonePlayDesign.blue]
    static let dare: [Color] = [PhonePlayDesign.orange, PhonePlayDesign.red]

    static func colors(for kind: TruthDareKind) -> [Color] {
        switch kind {
        case .truth: return truth
        case .dare:  return dare
        }
    }

    static func symbol(for kind: TruthDareKind) -> String {
        switch kind {
        case .truth: return "bubble.left.and.bubble.right.fill"
        case .dare:  return "bolt.fill"
        }
    }
}

struct TruthDareRootView: View {
    @ObservedObject var game: TruthDareViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                TruthDareSetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .play:
                TruthDarePlayView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct TruthDareSetupView: View {
    @ObservedObject var game: TruthDareViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Truth or Dare", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow,
                                                                      PhonePlayDesign.pink]))
                            .phonePlayIdle(dy: 3, scale: 0.05, duration: 0.9)
                        Text("Truth or Dare")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Spin the arrow to pick a player. They choose a truth to answer or a dare to do. Skips are allowed, but everyone will see.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    PhonePlayNamesEditor(names: $game.names, range: game.playerRange,
                                         accent: PhonePlayDesign.pink)

                    VStack(spacing: 10) {
                        PhonePlaySectionLabel(text: "Level")
                        HStack(spacing: 10) {
                            ForEach(TruthDareLevel.allCases) { level in
                                PhonePlayChip(title: level.title, subtitle: level.subtitle,
                                              selected: game.level == level,
                                              colors: TruthDareStyle.colors) {
                                    game.setLevel(level)
                                }
                            }
                        }
                        Text("\(game.truthCount) truths and \(game.dareCount) dares ready")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentTransition(.numericText())
                            .animation(PhonePlayDesign.smooth, value: game.truthCount + game.dareCount)
                    }

                    PhonePlayAIButton(state: game.aiState, accent: PhonePlayDesign.pink) {
                        game.fetchFreshCards()
                    }

                    PhonePlayBigButton(title: "Let's play", symbol: "play.fill",
                                       colors: TruthDareStyle.colors, enabled: game.canStart) {
                        game.start()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Play

private struct TruthDarePlayView: View {
    @ObservedObject var game: TruthDareViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Truth or Dare", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    if let prompt = game.prompt {
                        TruthDarePromptCard(prompt: prompt)
                            .id(prompt.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.8).combined(with: .opacity),
                                                    removal: .opacity))
                    } else {
                        TruthDareWheel(names: game.names, angle: game.spinAngle,
                                       chosen: game.chosen, spinning: game.phase == .spinning)
                            .frame(height: 320)
                            .transition(.opacity)
                    }

                    controls
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.phase)
        .animation(PhonePlayDesign.pop, value: game.prompt)
    }

    @ViewBuilder
    private var controls: some View {
        switch game.phase {
        case .ready:
            VStack(spacing: 12) {
                PhonePlayBigButton(title: game.turns == 0 ? "Spin" : "Spin again",
                                   symbol: "arrow.triangle.2.circlepath",
                                   colors: TruthDareStyle.colors) {
                    game.spin()
                }
                if game.turns > 0 {
                    Text(game.turns == 1 ? "1 turn played" : "\(game.turns) turns played")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
            }
        case .spinning:
            Text("Spinning...")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .frame(height: 60)
        case .choosing:
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(game.chosenName)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Truth or dare?")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }
                HStack(spacing: 12) {
                    TruthDareKindButton(kind: .truth) { game.choose(.truth) }
                    TruthDareKindButton(kind: .dare) { game.choose(.dare) }
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .card:
            VStack(spacing: 12) {
                PhonePlayBigButton(title: "Done", symbol: "checkmark",
                                   colors: [PhonePlayDesign.green, PhonePlayDesign.cyan]) {
                    game.done()
                }
                HStack(spacing: 12) {
                    PhonePlayGhostButton(title: "Skip", symbol: "forward.fill") {
                        game.skip()
                    }
                    if let prompt = game.prompt {
                        let other: TruthDareKind = prompt.kind == .truth ? .dare : .truth
                        PhonePlayGhostButton(title: "Switch to \(other.title.lowercased())",
                                             symbol: TruthDareStyle.symbol(for: other)) {
                            game.choose(other)
                        }
                    }
                }
                PhonePlayAIButton(state: game.aiState, accent: PhonePlayDesign.pink) {
                    game.fetchFreshCards()
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - The spinning arrow

private struct TruthDareWheel: View {
    let names: [String]
    let angle: Double
    let chosen: Int?
    let spinning: Bool

    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = max(80, min(geo.size.width, geo.size.height))
            let radius: CGFloat = max(40, size / 2 - 30)
            let count: Int = max(1, names.count)
            let seatWidth: CGFloat = min(96, max(44, 2 * .pi * radius / CGFloat(count) - 6))
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.surface)
                    .frame(width: size - 4, height: size - 4)
                Circle()
                    .strokeBorder(PhonePlayDesign.gradient(TruthDareStyle.colors), lineWidth: 3)
                    .frame(width: size - 4, height: size - 4)
                    .opacity(0.6)
                Circle()
                    .fill(PhonePlayDesign.surface2)
                    .frame(width: size * 0.36, height: size * 0.36)

                ForEach(Array(names.enumerated()), id: \.offset) { pair in
                    let theta: Double = Double(pair.offset) / Double(count) * 2 * Double.pi
                    TruthDareSeat(name: pair.element,
                                  highlighted: chosen == pair.offset && !spinning,
                                  width: seatWidth)
                        .offset(x: CGFloat(sin(theta)) * radius, y: -CGFloat(cos(theta)) * radius)
                }

                Image(systemName: "location.north.fill")
                    .font(.system(size: size * 0.2, weight: .bold, design: .rounded))
                    .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow, PhonePlayDesign.pink]))
                    .shadow(color: PhonePlayDesign.pink.opacity(0.5), radius: 10)
                    .rotationEffect(.degrees(angle))
                    .animation(.timingCurve(0.12, 0.75, 0.2, 1, duration: TruthDareViewModel.spinDuration),
                               value: angle)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct TruthDareSeat: View {
    let name: String
    let highlighted: Bool
    let width: CGFloat

    var body: some View {
        Text(name)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundColor(highlighted ? .black : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 6)
            .frame(width: width, height: 32)
            .background(Capsule().fill(highlighted ? PhonePlayDesign.yellow : PhonePlayDesign.surface2))
            .overlay(Capsule().strokeBorder(Color.white.opacity(highlighted ? 0 : 0.1), lineWidth: 1))
            .scaleEffect(highlighted ? 1.18 : 1)
            .shadow(color: highlighted ? PhonePlayDesign.yellow.opacity(0.6) : .clear, radius: 10)
            .animation(PhonePlayDesign.pop, value: highlighted)
    }
}

// MARK: - Truth / Dare buttons and card

private struct TruthDareKindButton: View {
    let kind: TruthDareKind
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: TruthDareStyle.symbol(for: kind))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(kind.title.uppercased())
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(TruthDareStyle.colors(for: kind)))
            )
            .shadow(color: (TruthDareStyle.colors(for: kind).first ?? .clear).opacity(0.4), radius: 14, y: 6)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

private struct TruthDarePromptCard: View {
    let prompt: TruthDareViewModel.Prompt

    @State private var angle: Double = 70

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: TruthDareStyle.symbol(for: prompt.kind))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(prompt.kind.title.uppercased())
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(3)
                Spacer()
                Text(prompt.player)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundColor(.white.opacity(0.9))

            Spacer(minLength: 0)
            Text(prompt.text)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient(TruthDareStyle.colors(for: prompt.kind)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: (TruthDareStyle.colors(for: prompt.kind).first ?? .clear).opacity(0.4), radius: 20, y: 10)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                angle = 0
            }
        }
    }
}
