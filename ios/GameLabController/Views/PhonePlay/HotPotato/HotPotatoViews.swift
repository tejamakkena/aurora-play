import SwiftUI
import UIKit

// MARK: - Hot Potato screens

private enum HotPotatoStyle {
    static let colors: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.red]
    static let flame: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.orange, PhonePlayDesign.red]
}

struct HotPotatoRootView: View {
    @ObservedObject var game: HotPotatoViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                HotPotatoSetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .ready:
                HotPotatoReadyView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .burning:
                HotPotatoBurningView(game: game)
                    .transition(.opacity)
            case .boom:
                HotPotatoBoomView(game: game)
                    .transition(.opacity)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct HotPotatoSetupView: View {
    @ObservedObject var game: HotPotatoViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Hot Potato", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 54, weight: .bold))
                            .foregroundStyle(PhonePlayDesign.gradient(HotPotatoStyle.flame))
                            .phonePlayIdle(degrees: 6, scale: 0.06, duration: 0.5)
                        Text("Hot Potato")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Name something in the category, then pass the phone. A hidden fuse ticks faster and faster. Holding it when it blows? That is a burn.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    PhonePlayNamesEditor(names: $game.names, range: game.playerRange,
                                         accent: PhonePlayDesign.orange)

                    Toggle(isOn: $game.soundOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ticking sound")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Haptic ticks always play; the click follows your ringer")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                        }
                    }
                    .tint(PhonePlayDesign.orange)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface))

                    VStack(spacing: 8) {
                        Text("\(game.categoryCount) categories ready")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PhonePlayAIButton(state: game.aiState, accent: PhonePlayDesign.orange,
                                          title: "Fresh AI categories") {
                            game.fetchFreshCards()
                        }
                    }

                    PhonePlayBigButton(title: "Start", symbol: "flame.fill",
                                       colors: HotPotatoStyle.colors, enabled: game.canStart) {
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

// MARK: - Ready

private struct HotPotatoReadyView: View {
    @ObservedObject var game: HotPotatoViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Hot Potato", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    HotPotatoCategoryCard(category: game.category, large: true)
                        .id(game.category)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))

                    VStack(spacing: 4) {
                        Text("Starting with")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                        Text(game.holderName)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    PhonePlayBigButton(title: "Light the fuse", symbol: "flame.fill",
                                       colors: HotPotatoStyle.colors) {
                        game.light()
                    }
                    PhonePlayGhostButton(title: "Different category", symbol: "shuffle") {
                        game.newCategory()
                    }

                    if game.round > 0 {
                        HotPotatoStandings(game: game)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
        }
        .animation(PhonePlayDesign.pop, value: game.category)
    }
}

private struct HotPotatoCategoryCard: View {
    let category: String
    var large: Bool = false

    var body: some View {
        VStack(spacing: large ? 12 : 4) {
            Text("CATEGORY")
                .font(.system(size: large ? 14 : 11, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.white.opacity(0.75))
            Text(category)
                .font(.system(size: large ? 34 : 22, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, large ? 34 : 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(large ? PhonePlayDesign.gradient(HotPotatoStyle.colors)
                            : PhonePlayDesign.gradient([Color.black.opacity(0.28), Color.black.opacity(0.18)]))
        )
        .shadow(color: large ? PhonePlayDesign.orange.opacity(0.35) : .clear, radius: 16, y: 8)
    }
}

private struct HotPotatoStandings: View {
    @ObservedObject var game: HotPotatoViewModel

    var body: some View {
        VStack(spacing: 8) {
            PhonePlaySectionLabel(text: "Burns (fewest wins)")
            ForEach(Array(game.standings.enumerated()), id: \.offset) { pair in
                HStack(spacing: 12) {
                    Text("\(pair.offset + 1)")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(pair.offset == 0 ? .black : .white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(pair.offset == 0 ? PhonePlayDesign.yellow : PhonePlayDesign.surface2))
                    Text(pair.element.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<min(pair.element.burns, 6), id: \.self) { _ in
                            Image(systemName: "flame.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(PhonePlayDesign.orange)
                        }
                    }
                    Text("\(pair.element.burns)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(pair.element.burns == 0 ? PhonePlayDesign.green : PhonePlayDesign.orange)
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface))
            }
        }
    }
}

// MARK: - Burning

private struct HotPotatoBurningView: View {
    @ObservedObject var game: HotPotatoViewModel

    private var glow: [Color] {
        [PhonePlayDesign.orange.opacity(0.15 + 0.5 * game.heat),
         PhonePlayDesign.red.opacity(0.1 + 0.6 * game.heat),
         PhonePlayDesign.bg]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: glow, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: game.heat)

            VStack(spacing: 18) {
                HStack {
                    Button {
                        PhonePlayHaptics.tap()
                        game.stopRound()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.black.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(game.passes == 1 ? "1 pass" : "\(game.passes) passes")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.25)))
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                HotPotatoCategoryCard(category: game.category)
                    .padding(.horizontal, 20)

                Spacer(minLength: 0)

                HotPotatoBomb(tick: game.tick, heat: game.heat)

                VStack(spacing: 2) {
                    Text(game.holderName)
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .id(game.holder)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                    Text("name one, then pass!")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.horizontal, 20)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: game.holder)

                Spacer(minLength: 0)

                Button {
                    game.pass()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.point.right.fill")
                            .font(.system(size: 28, weight: .bold))
                        Text("PASS")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(4)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .fill(PhonePlayDesign.gradient(HotPotatoStyle.colors))
                    )
                    .shadow(color: PhonePlayDesign.red.opacity(0.45), radius: 18, y: 8)
                }
                .buttonStyle(PhonePlayPressStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

/// The glowing, throbbing "potato": one throb per tick.
private struct HotPotatoBomb: View {
    let tick: Int
    let heat: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [PhonePlayDesign.yellow.opacity(0.55), .clear],
                                     center: .center, startRadius: 10, endRadius: 120))
                .frame(width: 240, height: 240)
                .scaleEffect(CGFloat(1 + 0.25 * heat))
            Circle()
                .fill(PhonePlayDesign.gradient(HotPotatoStyle.flame))
                .frame(width: 150, height: 150)
                .overlay(
                    Image(systemName: "flame.fill")
                        .font(.system(size: 70, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: PhonePlayDesign.red.opacity(0.6), radius: 20)
                .scaleEffect(CGFloat(tick % 2 == 0 ? 1.0 : 1.08 + 0.08 * heat))
                .rotationEffect(.degrees(tick % 2 == 0 ? -3 * heat : 3 * heat))
                .animation(.spring(response: 0.16, dampingFraction: 0.4), value: tick)
        }
        .frame(height: 220)
    }
}

// MARK: - Boom

private struct HotPotatoShake: GeometryEffect {
    var travel: CGFloat = 14
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t: Double = Double(shakes)
        let dx: CGFloat = travel * CGFloat(sin(t * Double.pi * 6))
        let dy: CGFloat = travel * 0.5 * CGFloat(sin(t * Double.pi * 4))
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: dy))
    }
}

private struct HotPotatoBoomView: View {
    @ObservedObject var game: HotPotatoViewModel

    @State private var blown: Bool = false
    @State private var shake: CGFloat = 0
    @State private var flash: Bool = true

    private let sparks: Int = 14

    var body: some View {
        ZStack {
            LinearGradient(colors: [PhonePlayDesign.red.opacity(0.55), PhonePlayDesign.bg],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { ring in
                            Circle()
                                .strokeBorder(PhonePlayDesign.yellow.opacity(0.8), lineWidth: 6)
                                .frame(width: 120, height: 120)
                                .scaleEffect(blown ? 2.6 + CGFloat(ring) * 0.6 : 0.2)
                                .opacity(blown ? 0 : 1)
                                .animation(.easeOut(duration: 0.9).delay(Double(ring) * 0.12), value: blown)
                        }
                        ForEach(0..<sparks, id: \.self) { i in
                            let angle: Double = Double(i) / Double(sparks) * 2 * Double.pi
                            Circle()
                                .fill(i % 2 == 0 ? PhonePlayDesign.yellow : PhonePlayDesign.orange)
                                .frame(width: 14, height: 14)
                                .offset(x: blown ? CGFloat(cos(angle)) * 150 : 0,
                                        y: blown ? CGFloat(sin(angle)) * 150 : 0)
                                .opacity(blown ? 0 : 1)
                                .animation(.easeOut(duration: 0.8), value: blown)
                        }
                        Text("BOOM!")
                            .font(.system(size: 84, weight: .black, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(HotPotatoStyle.flame))
                            .shadow(color: PhonePlayDesign.red.opacity(0.7), radius: 20)
                            .scaleEffect(blown ? 1 : 0.2)
                            .rotationEffect(.degrees(blown ? -6 : 10))
                            .animation(.spring(response: 0.45, dampingFraction: 0.45), value: blown)
                    }
                    .frame(height: 260)
                    .modifier(HotPotatoShake(shakes: shake))

                    VStack(spacing: 6) {
                        Text("\(game.loserName) got burned!")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        Text("+1 burn  |  \(game.passes) passes this round")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                    }
                    .opacity(blown ? 1 : 0)
                    .animation(PhonePlayDesign.smooth.delay(0.35), value: blown)

                    HotPotatoStandings(game: game)

                    PhonePlayBigButton(title: "Next round", symbol: "arrow.clockwise",
                                       colors: HotPotatoStyle.colors) {
                        game.nextRound()
                    }
                    PhonePlayGhostButton(title: "Edit players", symbol: "person.2.fill") {
                        game.editPlayers()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }

            Color.white
                .ignoresSafeArea()
                .opacity(flash ? 0.85 : 0)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.35), value: flash)
        }
        .onAppear {
            blown = true
            flash = false
            withAnimation(.linear(duration: 0.6)) {
                shake = 1
            }
        }
    }
}
