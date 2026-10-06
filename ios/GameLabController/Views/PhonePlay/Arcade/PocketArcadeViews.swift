import SwiftUI
import UIKit

// MARK: - Pocket Arcade screens

struct PocketArcadeRootView: View {
    @ObservedObject var game: PocketArcadeViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .menu:
                PocketArcadeMenuView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .countdown:
                PocketArcadeCountdownView(game: game)
                    .transition(.opacity)
            case .playing:
                PocketArcadePlayView(game: game)
                    .transition(.opacity)
            case .finished:
                PocketArcadeResultView(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Menu

private struct PocketArcadeMenuView: View {
    @ObservedObject var game: PocketArcadeViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Pocket Arcade", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.cyan, PhonePlayDesign.indigo]))
                            .phonePlayIdle(degrees: 5, scale: 0.04, duration: 1.1)
                        Text("Pocket Arcade")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Quick reflex games for one. Beat your best.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    ForEach(Array(PocketArcadeGame.allCases.enumerated()), id: \.element.id) { pair in
                        PocketArcadeGameCard(choice: pair.element, best: bestText(pair.element),
                                             index: pair.offset) {
                            game.play(pair.element)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }

    private func bestText(_ choice: PocketArcadeGame) -> String {
        switch choice {
        case .lights:
            return game.bestLights > 0 ? "Best: \(game.bestLights) lights" : "No best yet"
        case .rush:
            return game.bestRush > 0 ? "Best: \(PocketArcadeStore.rushText(game.bestRush))" : "No best yet"
        }
    }
}

private struct PocketArcadeGameCard: View {
    let choice: PocketArcadeGame
    let best: String
    let index: Int
    let action: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Color.black.opacity(0.18)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(choice.title)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(choice.blurb)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(best)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(choice.colors))
            )
            .shadow(color: (choice.colors.first ?? .clear).opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(PhonePlayPressStyle())
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(PhonePlayDesign.pop.delay(Double(index) * 0.08)) {
                appeared = true
            }
        }
    }
}

// MARK: - Countdown

private struct PocketArcadeCountdownView: View {
    @ObservedObject var game: PocketArcadeViewModel

    var body: some View {
        ZStack {
            PhonePlayDesign.gradient(game.game.colors).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(game.game.title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                Text("\(game.countdown)")
                    .font(.system(size: 160, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .id(game.countdown)
                    .transition(.asymmetric(insertion: .scale(scale: 1.8).combined(with: .opacity),
                                            removal: .scale(scale: 0.4).combined(with: .opacity)))
                    .frame(height: 200)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: game.countdown)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}

// MARK: - Play

private struct PocketArcadePlayView: View {
    @ObservedObject var game: PocketArcadeViewModel

    var body: some View {
        VStack(spacing: 18) {
            header
            Spacer(minLength: 0)
            switch game.game {
            case .lights:
                PocketArcadeLightsGrid(game: game)
            case .rush:
                PocketArcadeRushGrid(game: game)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var header: some View {
        HStack {
            Button {
                PhonePlayHaptics.tap()
                game.backToMenu()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            Spacer()
            switch game.game {
            case .lights:
                PocketArcadeStat(label: "TIME", value: "\(game.secondsLeft)",
                                 tint: game.secondsLeft <= 5 ? PhonePlayDesign.red : .white)
                Spacer()
                PocketArcadeStat(label: "LIGHTS", value: "\(game.hits)", tint: PhonePlayDesign.yellow)
            case .rush:
                TimelineView(.periodic(from: game.startedAt, by: 0.05)) { context in
                    let elapsed: Double = max(0, context.date.timeIntervalSince(game.startedAt)) + game.penalty
                    PocketArcadeStat(label: "TIME", value: String(format: "%.1f", elapsed), tint: .white)
                }
                Spacer()
                PocketArcadeStat(label: "NEXT", value: "\(min(game.nextNumber, game.rushCount))",
                                 tint: PhonePlayDesign.cyan)
            }
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 10)
    }
}

private struct PocketArcadeStat: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
            Text(value)
                .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(tint)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 80)
    }
}

/// Fires on touch-down rather than on release, which matters when every
/// hundredth of a second counts.
private struct PocketArcadeTouchDown: ViewModifier {
    let action: () -> Void

    @State private var down: Bool = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down {
                            down = true
                            action()
                        }
                    }
                    .onEnded { _ in
                        down = false
                    }
            )
    }
}

private struct PocketArcadeLightsGrid: View {
    @ObservedObject var game: PocketArcadeViewModel

    var body: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: game.lightsColumns)
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<game.lightsCells, id: \.self) { cell in
                PocketArcadeLightCell(lit: game.litCell == cell,
                                      hit: game.hitCell == cell,
                                      wrong: game.wrongCell == cell)
                    .modifier(PocketArcadeTouchDown { game.tapLight(cell) })
            }
        }
    }
}

private struct PocketArcadeLightCell: View {
    let lit: Bool
    let hit: Bool
    let wrong: Bool

    private var fill: Color {
        if wrong { return PhonePlayDesign.red }
        if hit { return PhonePlayDesign.green }
        if lit { return PhonePlayDesign.yellow }
        return PhonePlayDesign.surface
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(lit ? 0.6 : 0.08), lineWidth: lit ? 3 : 1)
            )
            .overlay(
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black.opacity(0.55))
                    .opacity(lit ? 1 : 0)
            )
            .shadow(color: lit ? PhonePlayDesign.yellow.opacity(0.8) : .clear, radius: 18)
            .scaleEffect(lit ? 1.06 : (hit ? 0.92 : 1))
            .aspectRatio(1, contentMode: .fit)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: lit)
            .animation(.easeOut(duration: 0.15), value: hit)
            .animation(.easeOut(duration: 0.15), value: wrong)
    }
}

private struct PocketArcadeRushGrid: View {
    @ObservedObject var game: PocketArcadeViewModel

    var body: some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 10), count: game.rushColumns)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(game.numbers.enumerated()), id: \.offset) { pair in
                PocketArcadeNumberCell(value: pair.element,
                                       cleared: pair.element < game.nextNumber,
                                       wrong: game.wrongCell == pair.offset)
                    .modifier(PocketArcadeTouchDown { game.tapNumber(at: pair.offset) })
            }
        }
    }
}

private struct PocketArcadeNumberCell: View {
    let value: Int
    let cleared: Bool
    let wrong: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(wrong ? PhonePlayDesign.red
                        : (cleared ? PhonePlayDesign.surface.opacity(0.4) : PhonePlayDesign.surface2))
            .overlay(
                Text("\(value)")
                    .font(.system(size: 26, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundColor(cleared ? PhonePlayDesign.text3.opacity(0.4) : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(PhonePlayDesign.cyan.opacity(cleared ? 0 : 0.25), lineWidth: 1)
            )
            .scaleEffect(cleared ? 0.86 : 1)
            .aspectRatio(1, contentMode: .fit)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: cleared)
            .animation(.easeOut(duration: 0.12), value: wrong)
    }
}

// MARK: - Result

private struct PocketArcadeResultView: View {
    @ObservedObject var game: PocketArcadeViewModel

    @State private var appeared: Bool = false

    private var scoreText: String {
        switch game.game {
        case .lights: return "\(game.hits)"
        case .rush:   return PocketArcadeStore.rushText(game.resultSeconds)
        }
    }

    private var scoreLabel: String {
        switch game.game {
        case .lights: return game.hits == 1 ? "light tapped" : "lights tapped"
        case .rush:   return game.penalty > 0 ? "including \(Int(game.penalty))s of penalties" : "no wrong taps"
        }
    }

    private var bestText: String {
        switch game.game {
        case .lights: return "Best: \(game.bestLights) lights"
        case .rush:   return "Best: \(PocketArcadeStore.rushText(game.bestRush))"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: game.game.title, backTitle: "Arcade", onBack: game.backToMenu)
            ScrollView {
                VStack(spacing: 18) {
                    if game.newBest {
                        Label("New best!", systemImage: "trophy.fill")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(PhonePlayDesign.yellow))
                            .scaleEffect(appeared ? 1 : 0.3)
                            .rotationEffect(.degrees(appeared ? 0 : -12))
                    }

                    VStack(spacing: 4) {
                        Text(scoreText)
                            .font(.system(size: 90, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(PhonePlayDesign.gradient(game.game.colors))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .scaleEffect(appeared ? 1 : 0.5)
                            .opacity(appeared ? 1 : 0)
                        Text(scoreLabel)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                        if game.game == .lights && game.averageReactionMs > 0 {
                            Text("Average reaction \(game.averageReactionMs) ms, \(game.misses) missed")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                        }
                        Text(bestText)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                            .padding(.top, 6)
                    }
                    .padding(.top, 10)

                    PhonePlayBigButton(title: "Play again", symbol: "arrow.clockwise",
                                       colors: game.game.colors) {
                        game.playAgain()
                    }
                    PhonePlayGhostButton(title: "Other games", symbol: "square.grid.2x2.fill") {
                        game.backToMenu()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.1)) {
                appeared = true
            }
        }
    }
}
