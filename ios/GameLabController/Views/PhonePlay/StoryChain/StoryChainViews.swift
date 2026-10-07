import SwiftUI
import UIKit

// MARK: - Story Chain screens

private enum StoryChainStyle {
    static let colors: [Color] = [PhonePlayDesign.indigo, PhonePlayDesign.pink]
    static let twist: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.orange]
    static let finale: [Color] = [PhonePlayDesign.purple, PhonePlayDesign.pink]
    static let crown: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.orange]
    static let go: [Color] = [PhonePlayDesign.green, PhonePlayDesign.cyan]
}

struct StoryChainRootView: View {
    @ObservedObject var game: StoryChainViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                StoryChainSetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .opening:
                StoryChainOpeningView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .ready:
                StoryChainReadyView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .telling:
                StoryChainTellingView(game: game)
                    .transition(.opacity)
            case .theEnd:
                StoryChainEndView(game: game)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .vote:
                StoryChainVoteView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .crowned:
                StoryChainCrownView(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct StoryChainSetupView: View {
    @ObservedObject var game: StoryChainViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Story Chain", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed.fill")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(StoryChainStyle.colors))
                            .phonePlayIdle(dy: 3, degrees: 5, duration: 1.1)
                        Text("Story Chain")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("The phone starts a silly story. Take turns adding one sentence out loud before the buzzer, then pass the phone on. Two turns each, twists along the way, then vote for the funniest storyteller.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    PhonePlayNamesEditor(names: $game.names, range: game.playerRange,
                                         accent: PhonePlayDesign.pink)

                    Toggle(isOn: $game.soundOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Buzzer sound")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("Haptics always play; the sound follows your ringer")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                        }
                    }
                    .tint(PhonePlayDesign.pink)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface))

                    Text("\(StoryChainDeck.openers.count) openers and \(StoryChainDeck.twists.count) twists ready. \(StoryChainViewModel.turnSeconds) seconds a turn.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PhonePlayBigButton(title: "Start a story", symbol: "book.fill",
                                       colors: StoryChainStyle.colors, enabled: game.canStart) {
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

// MARK: - Opening line

private struct StoryChainOpeningView: View {
    @ObservedObject var game: StoryChainViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Story Chain", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    StoryChainOpenerCard(text: game.opener, large: true)
                        .id(game.opener)
                        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                                removal: .opacity))

                    Text("Read it out loud to everyone. Dramatically.")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 4) {
                        Text("First storyteller")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                        Text(game.currentName)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }

                    PhonePlayBigButton(title: "Begin the story", symbol: "play.fill",
                                       colors: StoryChainStyle.colors) {
                        game.beginStory()
                    }
                    PhonePlayGhostButton(title: "Different opener", symbol: "shuffle") {
                        game.newOpener()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
        }
        .animation(PhonePlayDesign.pop, value: game.opener)
    }
}

private struct StoryChainOpenerCard: View {
    let text: String
    var large: Bool = false

    var body: some View {
        VStack(spacing: large ? 14 : 6) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: large ? 14 : 11, weight: .heavy, design: .rounded))
                Text(large ? "ONCE UPON A TIME" : "THE STORY BEGAN")
                    .font(.system(size: large ? 14 : 11, weight: .heavy, design: .rounded))
                    .tracking(3)
            }
            .foregroundColor(.white.opacity(0.75))
            Text(text)
                .font(.system(size: large ? 30 : 17, weight: large ? .black : .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(large ? 0.2 : 0), radius: 6, y: 3)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, large ? 34 : 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(large ? PhonePlayDesign.gradient(StoryChainStyle.colors)
                            : PhonePlayDesign.gradient([PhonePlayDesign.surface, PhonePlayDesign.surface]))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(large ? 0.2 : 0.06), lineWidth: 1)
        )
        .shadow(color: large ? PhonePlayDesign.pink.opacity(0.35) : .clear, radius: 18, y: 8)
    }
}

// MARK: - Pass to the next storyteller

private struct StoryChainReadyView: View {
    @ObservedObject var game: StoryChainViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Story Chain", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    StoryChainProgress(turn: game.turn, total: game.totalTurns, round: game.round)

                    VStack(spacing: 14) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.pink, .white]))
                            .phonePlayIdle(dx: 10, duration: 0.9)
                        VStack(spacing: 4) {
                            Text("Pass the phone to")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text2)
                            Text(game.currentName)
                                .font(.system(size: 46, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .id(game.turn)
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                        removal: .opacity))
                        }
                    }
                    .padding(.top, 4)

                    if let twist = game.twist {
                        StoryChainTwistCard(text: twist)
                            .id("twist-\(game.turn)")
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }

                    if game.isFinalTurn {
                        StoryChainFinalBanner()
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    PhonePlayBigButton(title: "Go! Start my \(StoryChainViewModel.turnSeconds) seconds",
                                       symbol: "timer", colors: StoryChainStyle.go) {
                        game.startTelling()
                    }

                    StoryChainOpenerCard(text: game.opener)
                }
                .padding(.horizontal, 22)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
        }
        .animation(PhonePlayDesign.pop, value: game.turn)
    }
}

/// "Round 1 of 2", "Turn 3 of 10" and a bar of turn dots.
private struct StoryChainProgress: View {
    let turn: Int
    let total: Int
    let round: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("ROUND \(round) OF \(StoryChainViewModel.turnsEach)")
                Spacer()
                Text("TURN \(min(turn + 1, max(total, 1))) OF \(max(total, 1))")
            }
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(1.5)
            .foregroundColor(PhonePlayDesign.text3)

            GeometryReader { geo in
                let count: Int = max(1, total)
                let gap: CGFloat = 3
                let width: CGFloat = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
                HStack(spacing: gap) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule()
                            .fill(i < turn ? AnyShapeStyle(PhonePlayDesign.gradient(StoryChainStyle.colors))
                                  : (i == turn ? AnyShapeStyle(Color.white)
                                               : AnyShapeStyle(Color.white.opacity(0.1))))
                            .frame(width: width, height: 6)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}

private struct StoryChainTwistCard: View {
    let text: String

    @State private var angle: Double = 80

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "tornado")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.75))
                .phonePlayIdle(degrees: 10, duration: 0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text("TWIST")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(.black.opacity(0.6))
                Text(text)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient(StoryChainStyle.twist))
        )
        .shadow(color: PhonePlayDesign.orange.opacity(0.4), radius: 14, y: 6)
        .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.15)) {
                angle = 0
            }
        }
    }
}

private struct StoryChainFinalBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Last line! Bring the story to an end.")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient(StoryChainStyle.finale))
        )
    }
}

// MARK: - Telling (the 20 second turn)

private struct StoryChainShake: GeometryEffect {
    var travel: CGFloat = 12
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t: Double = Double(shakes)
        let dx: CGFloat = travel * CGFloat(sin(t * Double.pi * 8))
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

private struct StoryChainTellingView: View {
    @ObservedObject var game: StoryChainViewModel

    @State private var shake: CGFloat = 0

    private var backdrop: [Color] {
        game.timeUp
            ? [PhonePlayDesign.red.opacity(0.55), PhonePlayDesign.bg]
            : [PhonePlayDesign.indigo.opacity(0.35), PhonePlayDesign.bg]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: backdrop, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.25), value: game.timeUp)

            VStack(spacing: 0) {
                PhonePlayTopBar(title: "Story Chain", backTitle: "Setup", onBack: game.editPlayers)
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 2) {
                            Text(game.currentName)
                                .font(.system(size: 38, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                            Text(game.timeUp ? "Buzzed! Finish the thought and pass it on."
                                             : "Say one sentence out loud")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                        }

                        StoryChainTimerRing(ends: game.turnEnds,
                                            total: Double(StoryChainViewModel.turnSeconds),
                                            secondsLeft: game.secondsLeft,
                                            timeUp: game.timeUp)
                            .frame(width: 210, height: 210)
                            .modifier(StoryChainShake(shakes: shake))

                        if let twist = game.twist {
                            StoryChainTwistCard(text: twist)
                        }
                        if game.isFinalTurn {
                            StoryChainFinalBanner()
                        }

                        PhonePlayBigButton(title: game.isFinalTurn ? "The End" : "Next storyteller",
                                           symbol: game.isFinalTurn ? "book.closed.fill" : "arrow.right.circle.fill",
                                           colors: game.timeUp ? [PhonePlayDesign.red, PhonePlayDesign.orange]
                                                               : StoryChainStyle.colors) {
                            game.nextStoryteller()
                        }

                        StoryChainOpenerCard(text: game.opener)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 6)
                    .padding(.bottom, 30)
                }
            }
        }
        .onChange(of: game.timeUp) { _, up in
            guard up else { return }
            withAnimation(.linear(duration: 0.55)) {
                shake += 1
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

private struct StoryChainTimerRing: View {
    let ends: Date
    let total: Double
    let secondsLeft: Int
    let timeUp: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: timeUp)) { context in
            let remaining: Double = timeUp ? 0 : max(0, ends.timeIntervalSince(context.date))
            let fraction: Double = total > 0 ? min(1, remaining / total) : 0
            let urgent: Bool = secondsLeft <= 5
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.surface)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 16)
                    .padding(8)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(urgent ? PhonePlayDesign.red : PhonePlayDesign.cyan,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(8)
                    .shadow(color: (urgent ? PhonePlayDesign.red : PhonePlayDesign.cyan).opacity(0.6), radius: 8)
                if timeUp {
                    VStack(spacing: 0) {
                        Image(systemName: "bell.and.waves.left.and.right.fill")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                        Text("TIME!")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow, PhonePlayDesign.red]))
                    }
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        Text("\(secondsLeft)")
                            .font(.system(size: 76, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundColor(urgent ? PhonePlayDesign.red : .white)
                            .contentTransition(.numericText(countsDown: true))
                        Text("seconds")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                    }
                    .scaleEffect(urgent ? 1.06 : 1)
                    .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.55), value: secondsLeft)
            .animation(.spring(response: 0.35, dampingFraction: 0.45), value: timeUp)
        }
    }
}

// MARK: - The End

private struct StoryChainEndView: View {
    @ObservedObject var game: StoryChainViewModel

    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Story Chain", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(StoryChainStyle.colors))
                            .rotationEffect(.degrees(appeared ? 0 : -25))
                            .scaleEffect(appeared ? 1 : 0.3)
                        Text("The End")
                            .font(.system(size: 64, weight: .black, design: .serif))
                            .italic()
                            .foregroundColor(.white)
                            .scaleEffect(appeared ? 1 : 1.6)
                            .opacity(appeared ? 1 : 0)
                        Text("What a story. Probably.")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .opacity(appeared ? 1 : 0)
                    }
                    .padding(.top, 16)

                    HStack(spacing: 10) {
                        StoryChainStat(value: game.totalTurns, label: "lines")
                        StoryChainStat(value: game.twistsPlayed, label: game.twistsPlayed == 1 ? "twist" : "twists")
                        StoryChainStat(value: game.buzzers, label: game.buzzers == 1 ? "buzzer" : "buzzers")
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)

                    StoryChainOpenerCard(text: game.opener)

                    PhonePlayBigButton(title: "Vote for the funniest", symbol: "crown.fill",
                                       colors: StoryChainStyle.crown) {
                        game.startVote()
                    }
                    PhonePlayGhostButton(title: "Skip the vote, new story", symbol: "arrow.clockwise") {
                        game.start()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1)) {
                appeared = true
            }
        }
    }
}

private struct StoryChainStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
            .fill(PhonePlayDesign.surface))
    }
}

// MARK: - Vote

private struct StoryChainVoteView: View {
    @ObservedObject var game: StoryChainViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Funniest storyteller", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                StoryChainBallot(name: game.voterName,
                                 index: game.voter,
                                 total: game.order.count,
                                 candidates: game.order.filter { $0 != game.voterName },
                                 onVote: { game.vote(for: $0) })
                    .id(game.voter)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .padding(.top, 6)
                    .padding(.bottom, 30)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.voter)
    }
}

/// "Pass to NAME" -> "I am NAME" -> tap the funniest storyteller.
private struct StoryChainBallot: View {
    let name: String
    let index: Int
    let total: Int
    let candidates: [String]
    let onVote: (String) -> Void

    @State private var confirmed: Bool = false

    var body: some View {
        VStack(spacing: 22) {
            Text("VOTER \(index + 1) OF \(total)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)

            if confirmed {
                pickStep
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                passStep
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 22)
        .animation(PhonePlayDesign.pop, value: confirmed)
    }

    private var passStep: some View {
        VStack(spacing: 26) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow, .white]))
                .phonePlayIdle(dx: 10, duration: 0.9)
                .padding(.top, 30)
            VStack(spacing: 6) {
                Text("Pass the phone to")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                Text(name)
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text("Vote in secret")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            PhonePlayBigButton(title: "I am \(name)", symbol: "hand.raised.fill",
                               colors: StoryChainStyle.crown) {
                confirmed = true
            }
        }
    }

    private var pickStep: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Who was the funniest?")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Tap one name. Not yourself, \(name)!")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 4)

            ForEach(Array(candidates.enumerated()), id: \.offset) { pair in
                Button {
                    onVote(pair.element)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "crown")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                        Text(pair.element)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                    .strokeBorder(PhonePlayDesign.yellow.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PhonePlayPressStyle())
            }
        }
    }
}

// MARK: - Crowned

private struct StoryChainCrownView: View {
    @ObservedObject var game: StoryChainViewModel

    @State private var appeared: Bool = false

    private let rays: Int = 12

    private var headline: String {
        switch game.winners.count {
        case 0:  return "Everyone wins"
        case 1:  return game.winners[0]
        default: return game.winners.joined(separator: " and ")
        }
    }

    private var subline: String {
        game.winners.count > 1 ? "It's a tie! Share the crown." : "Funniest storyteller"
    }

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Story Chain", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    ZStack {
                        ForEach(0..<rays, id: \.self) { i in
                            Capsule()
                                .fill(PhonePlayDesign.yellow.opacity(0.35))
                                .frame(width: 6, height: 46)
                                .offset(y: appeared ? -96 : -40)
                                .rotationEffect(.degrees(Double(i) / Double(rays) * 360))
                                .opacity(appeared ? 1 : 0)
                        }
                        Circle()
                            .fill(RadialGradient(colors: [PhonePlayDesign.yellow.opacity(0.45), .clear],
                                                 center: .center, startRadius: 6, endRadius: 110))
                            .frame(width: 220, height: 220)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 84, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(StoryChainStyle.crown))
                            .shadow(color: PhonePlayDesign.orange.opacity(0.6), radius: 16)
                            .offset(y: appeared ? 0 : -220)
                            .rotationEffect(.degrees(appeared ? 0 : -20))
                            .phonePlayIdle(dy: 3, degrees: 3, duration: 1.2)
                    }
                    .frame(height: 230)

                    VStack(spacing: 6) {
                        Text(headline)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.4)
                        Text(subline)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                    }
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)

                    VStack(spacing: 8) {
                        PhonePlaySectionLabel(text: "Votes")
                        ForEach(Array(game.standings.enumerated()), id: \.offset) { pair in
                            let crowned: Bool = game.winners.contains(pair.element.name)
                            HStack(spacing: 12) {
                                Image(systemName: crowned ? "crown.fill" : "person.fill")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(crowned ? .black : .white.opacity(0.7))
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(crowned ? PhonePlayDesign.yellow : PhonePlayDesign.surface2))
                                Text(pair.element.name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(pair.element.votes == 1 ? "1 vote" : "\(pair.element.votes) votes")
                                    .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                                    .foregroundColor(crowned ? PhonePlayDesign.yellow : PhonePlayDesign.text3)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                .fill(PhonePlayDesign.surface))
                        }
                    }

                    PhonePlayBigButton(title: "New story", symbol: "book.fill",
                                       colors: StoryChainStyle.colors) {
                        game.start()
                    }
                    PhonePlayGhostButton(title: "Edit players", symbol: "person.2.fill") {
                        game.editPlayers()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.15)) {
                appeared = true
            }
        }
    }
}
