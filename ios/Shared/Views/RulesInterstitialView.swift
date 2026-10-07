import SwiftUI

/// The design tokens this file is allowed to use.
///
/// `Shared/` compiles into BOTH targets, so it can reference neither
/// `PhonePlayDesign` (phone) nor `ShellTheme` (TV). One palette therefore
/// exists in three copies, and these are the third: every hex below is the
/// same number those two kits carry for the same role, and the radii are
/// Phone Play's cards-24 / buttons-18 / chips-14. If a token moves in one
/// kit, move it in all three.
private enum RulesDesign {
    static let bg = Color(hex: "0B0B12")
    static let surface = Color(hex: "15151F")
    static let surface2 = Color(hex: "1E1E2B")
    static let text2 = Color(hex: "A7A7B8")
    static let text3 = Color(hex: "6B6B7E")
    static let green = Color(hex: "2FE07A")
    static let cyan = Color(hex: "38D6F5")
    static let indigo = Color(hex: "6C5CFF")
    static let pink = Color(hex: "FF5FC8")
    /// The TV shell's own accent pair (ShellTheme.cyan / ShellTheme.violet).
    static let tvAccent = Color(hex: "38D6F5")
    static let tvViolet = Color(hex: "7C3AED")

    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 18
    static let chipRadius: CGFloat = 14
}

/// How-to-play interstitial shown once, right after Start Game is pressed.
///
/// The TV presents the `.tv` layout (full screen, large type); the phone
/// controller presents the same data as a compact `.card`. Both read the
/// same `GameRules` decoded from the server's `game_started` payload -- the
/// backend is the single source of truth and neither app keeps its own
/// copy of the text.
///
/// The primary action begins the game for real: the server holds the engine
/// (no clocks, nothing dealt) until the host taps it. Pass a non-nil
/// `onPrimary` for the host's Begin button; pass nil for everyone else and
/// the interstitial shows a "waiting for host" indicator instead. The room
/// lifts the gate on `game_begun`, which is when both clients dismiss this.
struct RulesInterstitialView: View {
    enum Layout {
        case tv
        case card
    }

    let rules: GameRules
    let layout: Layout
    let primaryTitle: String
    let onPrimary: (() -> Void)?

    @FocusState private var startFocused: Bool
    /// Drives the TV layout's entrance (panel tilt-in, staggered rules).
    @State private var rulesShown: Bool = false

    var body: some View {
        switch layout {
        case .tv:
            tvBody
        case .card:
            cardBody
        }
    }

    // MARK: - TV layout

    // The TV layout is a glass panel floating over a dimmed, softly lit
    // backdrop: rules arrive one by one as numbered 3D chips, and the Begin
    // button lifts and glows on focus. Everything here is plain SwiftUI that
    // exists on both iOS 17 and tvOS 17 -- this file compiles into the phone
    // app too -- so it cannot use the TV-only ShellTheme kit.

    private var tvBody: some View {
        ZStack {
            tvBackdrop
            // The Begin button sits OUTSIDE the scroll view so it is always
            // on screen and focusable; the rules scroll above it. tvOS only
            // scrolls by moving focus, so each rule row is focusable (see
            // TVRuleRow) -- swiping down walks the rules, then lands on Begin.
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    HStack(alignment: .top, spacing: 48) {
                        tvBadge
                        tvContent
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                }
                tvFooter
                    .padding(.horizontal, 56)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
            }
            .background { tvPanel }
            .frame(maxWidth: 1500)
            .padding(.horizontal, 90)
            .padding(.vertical, 50)
            // 2D entrance only: a 3D transform on the focus container
            // confuses the tvOS focus engine.
            .scaleEffect(rulesShown ? 1.0 : 0.94)
            .opacity(rulesShown ? 1.0 : 0.0)
        }
        .defaultFocus($startFocused, true)
        #if os(tvOS)
        // Play/Pause begins from anywhere on the screen.
        .onPlayPauseCommand { onPrimary?() }
        #endif
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                rulesShown = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                startFocused = true
            }
        }
    }

    @ViewBuilder
    private var tvFooter: some View {
        if let onPrimary {
            HStack(spacing: 28) {
                Button(action: onPrimary) {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill")
                        Text(primaryTitle)
                    }
                    .font(.title.bold())
                    .frame(width: 420)
                    .padding(.vertical, 22)
                    .background {
                        RoundedRectangle(cornerRadius: RulesDesign.buttonRadius, style: .continuous)
                            .fill(LinearGradient(colors: startFocused
                                                    ? [Color.white, Color.white]
                                                    : [Color.white.opacity(0.9), RulesDesign.tvAccent],
                                                 startPoint: .top,
                                                 endPoint: .bottom))
                    }
                    .foregroundColor(.black)
                    .compositingGroup()
                    .shadow(color: RulesDesign.tvAccent.opacity(startFocused ? 0.75 : 0.25),
                            radius: startFocused ? 34 : 12)
                    .scaleEffect(startFocused ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: startFocused)
                }
                .buttonStyle(.plain)
                .focused($startFocused)

                Text("or press Play/Pause")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.55))
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 16) {
                ProgressView()
                    .tint(RulesDesign.tvAccent)
                    .scaleEffect(1.4)
                Text("Waiting for host to begin...")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .phaseAnimator([false, true]) { content, phase in
                content.opacity(phase ? 1.0 : 0.55)
            } animation: { _ in
                Animation.easeInOut(duration: 1.2)
            }
        }
    }

    private var tvBackdrop: some View {
        ZStack {
            Color.black.opacity(0.8)
            RadialGradient(colors: [RulesDesign.tvViolet.opacity(0.35), Color.clear],
                           center: .topLeading,
                           startRadius: 0,
                           endRadius: 900)
            RadialGradient(colors: [RulesDesign.tvAccent.opacity(0.22), Color.clear],
                           center: .bottomTrailing,
                           startRadius: 0,
                           endRadius: 800)
        }
        .ignoresSafeArea()
    }

    private var tvPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: RulesDesign.cardRadius, style: .continuous)
                .fill(RulesDesign.surface.opacity(0.9))
            RoundedRectangle(cornerRadius: RulesDesign.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.01)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: RulesDesign.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.4),
                                                      Color.white.opacity(0.05),
                                                      RulesDesign.tvAccent.opacity(0.35)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.5), radius: 40, x: 0, y: 28)
    }

    /// A glossy controller orb that slowly turns in 3D beside the rules.
    private var tvBadge: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))
                .offset(y: 12)
            Circle()
                .fill(LinearGradient(colors: [RulesDesign.tvAccent, RulesDesign.tvViolet],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                                     center: UnitPoint(x: 0.3, y: 0.24),
                                     startRadius: 0,
                                     endRadius: 110))
            Circle()
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 3)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 78, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 4)
        }
        .frame(width: 180, height: 180)
        .shadow(color: RulesDesign.tvAccent.opacity(0.45), radius: 30)
        .phaseAnimator([false, true]) { content, phase in
            content
                .rotation3DEffect(.degrees(phase ? 14 : -14),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.5)
                .offset(y: phase ? -8 : 8)
        } animation: { _ in
            Animation.easeInOut(duration: 2.6)
        }
    }

    private var tvContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("HOW TO PLAY")
                .font(.title3).bold()
                .foregroundColor(.white.opacity(0.6))
                .tracking(6)

            Text(rules.title)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Color.white, RulesDesign.tvAccent],
                                                startPoint: .top,
                                                endPoint: .bottom))
                .shadow(color: RulesDesign.tvAccent.opacity(0.35), radius: 18)

            Text(rules.objective)
                .font(.title2)
                .foregroundColor(RulesDesign.tvAccent)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(rules.rules.enumerated()), id: \.offset) { index, rule in
                    TVRuleRow(number: index + 1, text: rule, accent: RulesDesign.tvAccent) {
                        tvRuleNumber(index + 1)
                    }
                    .opacity(rulesShown ? 1 : 0)
                    .offset(x: rulesShown ? 0 : 60)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8)
                                .delay(0.15 + Double(index) * 0.09),
                               value: rulesShown)
                }
            }

            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(RulesDesign.tvAccent.opacity(0.8))
                Text(rules.controls)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.78))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background {
                Capsule().fill(Color.white.opacity(0.07))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tvRuleNumber(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 54, height: 54)
            .background {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .offset(y: 4)
                    Circle()
                        .fill(LinearGradient(colors: [RulesDesign.tvAccent, RulesDesign.tvViolet],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                    Circle()
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5)
                }
            }
    }

    // MARK: - Phone card layout

    // The phone wears the Phone Play look (dark surface card, party
    // gradients, rounded heavy type, springy entrance), out of the
    // `RulesDesign` tokens at the top of this file.
    private var cardBody: some View {
        ZStack {
            RulesDesign.bg.opacity(0.92).ignoresSafeArea()
            // Centred when the rules are short, scrollable when long.
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: RulesDesign.buttonRadius, style: .continuous)
                                        .fill(LinearGradient(colors: [RulesDesign.cyan, RulesDesign.indigo],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                                )
                                .shadow(color: RulesDesign.cyan.opacity(0.4), radius: 10, y: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HOW TO PLAY")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .tracking(2)
                                    .foregroundColor(RulesDesign.text3)
                                Text(rules.title)
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.7)
                            }
                        }
    
                        Text(rules.objective)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(RulesDesign.cyan)
                            .fixedSize(horizontal: false, vertical: true)
    
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(rules.rules.enumerated()), id: \.offset) { index, rule in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundColor(.black)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            Circle().fill(LinearGradient(colors: [RulesDesign.green, RulesDesign.cyan],
                                                                         startPoint: .topLeading,
                                                                         endPoint: .bottomTrailing))
                                        )
                                    Text(rule)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.92))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 4)
                                    Spacer(minLength: 0)
                                }
                                .opacity(rulesShown ? 1 : 0)
                                .offset(x: rulesShown ? 0 : 24)
                                .animation(.spring(response: 0.38, dampingFraction: 0.68)
                                            .delay(0.1 + Double(index) * 0.06),
                                           value: rulesShown)
                            }
                        }
    
                        HStack(spacing: 10) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(RulesDesign.pink)
                            Text(rules.controls)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(RulesDesign.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: RulesDesign.chipRadius, style: .continuous)
                                .fill(RulesDesign.surface2)
                        )
    
                        if let onPrimary {
                            Button(action: onPrimary) {
                                HStack(spacing: 10) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text(primaryTitle)
                                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: RulesDesign.buttonRadius, style: .continuous)
                                        .fill(LinearGradient(colors: [RulesDesign.green, RulesDesign.cyan],
                                                             startPoint: .topLeading,
                                                             endPoint: .bottomTrailing))
                                )
                                .shadow(color: RulesDesign.green.opacity(0.35), radius: 14, y: 6)
                            }
                            .buttonStyle(RulesCardPressStyle())
                            .padding(.top, 4)
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(RulesDesign.cyan)
                                Text("Waiting for host to begin...")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(RulesDesign.text2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: RulesDesign.buttonRadius, style: .continuous)
                                    .fill(RulesDesign.surface2)
                            )
                            .phaseAnimator([false, true]) { content, phase in
                                content.opacity(phase ? 1.0 : 0.6)
                            } animation: { _ in
                                Animation.easeInOut(duration: 1.2)
                            }
                        }
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: RulesDesign.cardRadius, style: .continuous)
                            .fill(RulesDesign.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: RulesDesign.cardRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 24, y: 12)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .scaleEffect(rulesShown ? 1 : 0.9)
                    .opacity(rulesShown ? 1 : 0)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                rulesShown = true
            }
        }
    }
}

/// Squash-and-spring press for the phone card's Begin button (the phone's
/// PhonePlayPressStyle is not available to this shared file).
private struct RulesCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// One numbered rule on the TV. Focusable so the Siri Remote can scroll
/// the rules (tvOS scroll views only move with focus); the focused row
/// lifts and gets a soft highlight.
private struct TVRuleRow<Badge: View>: View {
    let number: Int
    let text: String
    let accent: Color
    @ViewBuilder let badge: () -> Badge

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            badge()
            Text(text)
                .font(.title2)
                .foregroundColor(.white.opacity(focused ? 1.0 : 0.88))
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: RulesDesign.buttonRadius, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.1 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: RulesDesign.buttonRadius, style: .continuous)
                .strokeBorder(accent.opacity(focused ? 0.6 : 0), lineWidth: 2)
        }
        .scaleEffect(focused ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        .focusable()
        .focused($focused)
    }
}
