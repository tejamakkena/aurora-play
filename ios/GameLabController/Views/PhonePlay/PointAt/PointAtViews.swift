import SwiftUI

// MARK: - Point at Them screens

private enum PointAtStyle {
    static let colors: [Color] = [PhonePlayDesign.pink, PhonePlayDesign.orange]
}

struct PointAtRootView: View {
    @ObservedObject var game: PointAtViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                PointAtSetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .prompt, .counting, .pointed:
                PointAtPlayView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage == .setup)
    }
}

// MARK: Setup

private struct PointAtSetupView: View {
    @ObservedObject var game: PointAtViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Point at Them", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 50, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(PointAtStyle.colors))
                            .phonePlayIdle(dy: 4, degrees: 6, duration: 0.9)
                        Text("Point at Them")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Put the phone in the middle. It asks who is most likely to do something. On three, everyone points at someone at the same time.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 10) {
                        PhonePlaySectionLabel(text: "Who is playing?")
                        HStack(spacing: 10) {
                            ForEach(TruthDareLevel.allCases) { level in
                                PhonePlayChip(title: level.title, subtitle: level.subtitle,
                                              selected: game.level == level,
                                              colors: PointAtStyle.colors) {
                                    game.setLevel(level)
                                }
                            }
                        }
                    }

                    Text("\(game.poolCount) prompts ready. No names to type, nothing to pass round.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PhonePlayBigButton(title: "Start", symbol: "play.fill", colors: PointAtStyle.colors) {
                        game.start()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: Play

private struct PointAtPlayView: View {
    @ObservedObject var game: PointAtViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Point at Them", backTitle: "Setup", onBack: game.backToSetup)

            Spacer(minLength: 8)

            // The prompt is big enough to read from across a table.
            Text(game.prompt)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
                .id(game.prompt)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))

            Spacer(minLength: 8)

            middle
                .frame(height: 180)
                .padding(.horizontal, 24)

            footer
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .animation(PhonePlayDesign.smooth, value: game.prompt)
        .animation(PhonePlayDesign.pop, value: game.stage == .pointed)
    }

    @ViewBuilder
    private var middle: some View {
        switch game.stage {
        case .counting:
            Text(game.count > 0 ? "\(game.count)" : "Point!")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient(PointAtStyle.colors))
                .id(game.count)
                .transition(.scale(scale: 1.6).combined(with: .opacity))
        case .pointed:
            VStack(spacing: 10) {
                Text("POINT!")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(PhonePlayDesign.gradient(PointAtStyle.colors))
                Text("Most fingers on you? " + game.follow)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
        default:
            Text("Everyone ready? Pick someone in your head.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch game.stage {
        case .pointed:
            PhonePlayBigButton(title: "Next one", symbol: "arrow.right", colors: PointAtStyle.colors) {
                game.next()
            }
        case .counting:
            Color.clear.frame(height: 56)
        default:
            PhonePlayBigButton(title: "Ready, 3 2 1", symbol: "hand.point.up.left.fill",
                               colors: PointAtStyle.colors) {
                game.ready()
            }
        }
    }
}
