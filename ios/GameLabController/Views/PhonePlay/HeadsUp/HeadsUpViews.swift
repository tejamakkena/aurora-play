import SwiftUI
import UIKit

// MARK: - Heads Up screens
//
// The play screen is laid out from its own size, so the word reads well
// whether the phone is held sideways (the usual forehead pose) or upright.

struct HeadsUpRootView: View {
    @ObservedObject var game: HeadsUpViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .pick:
                HeadsUpPickView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .ready:
                HeadsUpReadyView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .countdown:
                HeadsUpCountdownView(game: game)
                    .transition(.opacity)
            case .playing:
                HeadsUpPlayView(game: game)
                    .transition(.opacity)
            case .summary:
                HeadsUpSummaryView(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Pick a deck

private struct HeadsUpPickView: View {
    @ObservedObject var game: HeadsUpViewModel
    let onExit: () -> Void

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Heads Up", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Pick a deck")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Hold the phone to your forehead. Your friends act it out.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(HeadsUpDecks.all.enumerated()), id: \.element.id) { pair in
                            HeadsUpDeckCard(deck: pair.element, index: pair.offset) {
                                game.choose(pair.element)
                            }
                        }
                    }

                    if game.motionAvailable {
                        Toggle(isOn: $game.useTilt) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tilt to answer")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Off: tap Correct and Pass buttons instead")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(PhonePlayDesign.text3)
                            }
                        }
                        .tint(PhonePlayDesign.orange)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct HeadsUpDeckCard: View {
    let deck: HeadsUpDeck
    let index: Int
    let action: () -> Void

    @State private var appeared: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: deck.symbol)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text(deck.title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Text("\(deck.words.count) cards")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(deck.colors))
            )
            .shadow(color: (deck.colors.first ?? .clear).opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(PhonePlayPressStyle())
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(PhonePlayDesign.pop.delay(Double(index) * 0.05)) {
                appeared = true
            }
        }
    }
}

// MARK: - Ready

private struct HeadsUpReadyView: View {
    @ObservedObject var game: HeadsUpViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: game.deck.title, backTitle: "Decks", onBack: game.backToDecks)
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "iphone.landscape")
                        .font(.system(size: 80, weight: .regular, design: .rounded))
                        .foregroundStyle(PhonePlayDesign.gradient(game.deck.colors))
                        .phonePlayIdle(tilt: 22, duration: 0.7)
                        .padding(.top, 20)

                    Text("Hold it to your forehead")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    if game.useTilt {
                        HStack(spacing: 12) {
                            HeadsUpRuleTile(symbol: "arrow.down.circle.fill", title: "Tilt down",
                                            subtitle: "Got it", color: PhonePlayDesign.green)
                            HeadsUpRuleTile(symbol: "arrow.up.circle.fill", title: "Tilt up",
                                            subtitle: "Pass", color: PhonePlayDesign.orange)
                        }
                        Text("Bring the phone back to level between cards.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                            .multilineTextAlignment(.center)
                    } else {
                        HStack(spacing: 12) {
                            HeadsUpRuleTile(symbol: "checkmark.circle.fill", title: "Tap Correct",
                                            subtitle: "Got it", color: PhonePlayDesign.green)
                            HeadsUpRuleTile(symbol: "forward.fill", title: "Tap Pass",
                                            subtitle: "Skip it", color: PhonePlayDesign.orange)
                        }
                    }

                    Text("\(game.roundLength) seconds. Guess as many as you can.")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)

                    PhonePlayBigButton(title: "Start", symbol: "play.fill",
                                       colors: game.deck.colors) {
                        game.startRound()
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct HeadsUpRuleTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
            .fill(color.opacity(0.12)))
    }
}

// MARK: - Countdown

private struct HeadsUpCountdownView: View {
    @ObservedObject var game: HeadsUpViewModel

    var body: some View {
        ZStack {
            PhonePlayDesign.gradient(game.deck.colors).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Place on forehead")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                ZStack {
                    Text("\(game.countdown)")
                        .font(.system(size: 160, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .id(game.countdown)
                        .transition(.asymmetric(insertion: .scale(scale: 1.8).combined(with: .opacity),
                                                removal: .scale(scale: 0.4).combined(with: .opacity)))
                }
                .frame(height: 200)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: game.countdown)
        .statusBarHidden(true)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}

// MARK: - Play

private struct HeadsUpPlayView: View {
    @ObservedObject var game: HeadsUpViewModel

    var body: some View {
        GeometryReader { geo in
            let shortSide: CGFloat = min(geo.size.width, geo.size.height)
            ZStack {
                PhonePlayDesign.gradient(game.deck.colors).ignoresSafeArea()

                VStack(spacing: 0) {
                    playHeader
                    Spacer(minLength: 0)
                    Text(game.word)
                        .font(.system(size: max(40, shortSide * 0.2), weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.3)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .padding(.horizontal, 24)
                        .id(game.word)
                        .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity),
                                                removal: .opacity))
                    Spacer(minLength: 0)
                    playFooter
                }

                if let flash = game.flash {
                    HeadsUpFlashView(flash: flash, word: game.word, shortSide: shortSide)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: game.word)
            .animation(.easeOut(duration: 0.15), value: game.flash)
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var timerColor: Color {
        game.secondsLeft <= 10 ? PhonePlayDesign.red : .white
    }

    private var playHeader: some View {
        HStack {
            Button {
                PhonePlayHaptics.tap()
                game.endEarly()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.black.opacity(0.2)))
            }
            .buttonStyle(.plain)
            Spacer()
            Text(PhonePlayTime.clock(game.secondsLeft))
                .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(timerColor)
                .contentTransition(.numericText(countsDown: true))
                .animation(.easeOut(duration: 0.2), value: game.secondsLeft)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.22)))
            Spacer()
            Text("\(game.correctCount)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(PhonePlayDesign.green.opacity(0.5)))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var playFooter: some View {
        if !game.useTilt {
            HStack(spacing: 14) {
                Button {
                    game.markPass()
                } label: {
                    Label("Pass", systemImage: "forward.fill")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(PhonePlayDesign.orange))
                }
                .buttonStyle(PhonePlayPressStyle())
                Button {
                    game.markCorrect()
                } label: {
                    Label("Correct", systemImage: "checkmark")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(PhonePlayDesign.green))
                }
                .buttonStyle(PhonePlayPressStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        } else if !game.armed && game.flash == nil {
            Text("Hold it level")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.25)))
                .padding(.bottom, 18)
        } else {
            Color.clear.frame(height: 50)
        }
    }
}

private struct HeadsUpFlashView: View {
    let flash: HeadsUpViewModel.Flash
    let word: String
    let shortSide: CGFloat

    @State private var popped: Bool = false

    private var isCorrect: Bool { flash == .correct }

    var body: some View {
        ZStack {
            (isCorrect ? PhonePlayDesign.green : PhonePlayDesign.orange)
                .ignoresSafeArea()
            VStack(spacing: 8) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "arrow.uturn.right.circle.fill")
                    .font(.system(size: max(50, shortSide * 0.18), weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .scaleEffect(popped ? 1 : 0.4)
                Text(isCorrect ? "CORRECT" : "PASS")
                    .font(.system(size: max(36, shortSide * 0.14), weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                popped = true
            }
        }
    }
}

// MARK: - Summary

private struct HeadsUpSummaryView: View {
    @ObservedObject var game: HeadsUpViewModel

    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: game.deck.title, backTitle: "Decks", onBack: game.backToDecks)
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text("\(game.correctCount)")
                            .font(.system(size: 96, weight: .black, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(game.deck.colors))
                            .scaleEffect(appeared ? 1 : 0.5)
                            .opacity(appeared ? 1 : 0)
                        Text(game.correctCount == 1 ? "card guessed" : "cards guessed")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                        Text("\(game.passCount) passed")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                    }
                    .padding(.top, 10)

                    VStack(spacing: 8) {
                        ForEach(game.results) { result in
                            HeadsUpResultRow(result: result)
                        }
                        if game.results.isEmpty {
                            Text("No cards this round")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                                .padding(.vertical, 20)
                        }
                    }

                    PhonePlayBigButton(title: "Play again", symbol: "arrow.clockwise",
                                       colors: game.deck.colors) {
                        game.playAgain()
                    }
                    PhonePlayGhostButton(title: "Change deck", symbol: "square.grid.2x2.fill") {
                        game.backToDecks()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                appeared = true
            }
        }
    }
}

private struct HeadsUpResultRow: View {
    let result: HeadsUpResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.correct ? "checkmark.circle.fill" : "arrow.uturn.right.circle.fill")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(result.correct ? PhonePlayDesign.green : PhonePlayDesign.orange)
            Text(result.word)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(result.correct ? .white : PhonePlayDesign.text2)
                .strikethrough(!result.correct, color: PhonePlayDesign.text3)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
            .fill(PhonePlayDesign.surface))
    }
}
