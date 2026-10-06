import SwiftUI

// MARK: - Daily Brain Challenge screens

private enum DailyStyle {
    static let colors: [Color] = [PhonePlayDesign.green, PhonePlayDesign.cyan]
    static let flame: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.orange]
}

struct DailyRootView: View {
    @ObservedObject var game: DailyViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PhonePlayTopBar(title: "Daily Brain", backTitle: "Games", onBack: onExit)
                Group {
                    switch game.stage {
                    case .intro:
                        DailyIntroView(game: game)
                            .transition(.opacity)
                    case .playing:
                        DailyPlayView(game: game)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    case .finished:
                        DailyFinishedView(game: game)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Streak badge

private struct DailyStreakBadge: View {
    let streak: Int
    var large: Bool = false

    @State private var bump: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: large ? 30 : 20, weight: .bold))
                .foregroundStyle(PhonePlayDesign.gradient(DailyStyle.flame))
                .symbolEffect(.bounce, value: bump)
            Text("\(streak)")
                .font(.system(size: large ? 34 : 22, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text("day streak")
                .font(.system(size: large ? 17 : 14, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .padding(.horizontal, large ? 22 : 16)
        .padding(.vertical, large ? 14 : 10)
        .background(Capsule().fill(PhonePlayDesign.orange.opacity(0.14)))
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                bump += 1
            }
        }
    }
}

// MARK: - Intro

private struct DailyIntroView: View {
    @ObservedObject var game: DailyViewModel

    @State private var appeared: Bool = false

    private let kinds: [(String, String)] = [
        ("chart.line.uptrend.xyaxis", "Pattern"),
        ("plus.forwardslash.minus", "Maths"),
        ("circle.grid.cross.fill", "Odd one"),
        ("person.3.sequence.fill", "Logic"),
        ("calendar", "Calendar"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(PhonePlayDesign.text3)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 70, weight: .bold))
                        .foregroundStyle(PhonePlayDesign.gradient(DailyStyle.colors))
                        .scaleEffect(appeared ? 1 : 0.6)
                        .rotationEffect(.degrees(appeared ? 0 : -15))
                    Text("Today's challenge")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Five puzzles, the same for everyone today. Be quick: speed earns bonus points.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                DailyStreakBadge(streak: game.streak)

                HStack(spacing: 8) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { pair in
                        VStack(spacing: 6) {
                            Image(systemName: pair.element.0)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(PhonePlayDesign.cyan)
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(PhonePlayDesign.surface))
                            Text(pair.element.1)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)
                        .animation(PhonePlayDesign.pop.delay(0.1 + Double(pair.offset) * 0.06), value: appeared)
                    }
                }

                PhonePlayBigButton(title: "Start", symbol: "play.fill", colors: DailyStyle.colors) {
                    game.begin()
                }

                if game.bestStreak > 0 {
                    Text("Best streak: \(game.bestStreak) days")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }
}

// MARK: - Play

private struct DailyPlayView: View {
    @ObservedObject var game: DailyViewModel

    var body: some View {
        VStack(spacing: 16) {
            header
            if let puzzle = game.current {
                DailyPuzzleCard(puzzle: puzzle, number: game.index + 1,
                                total: game.puzzles.count,
                                selected: game.selected,
                                onAnswer: game.answer)
                    .id(puzzle.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .animation(PhonePlayDesign.smooth, value: game.index)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<game.puzzles.count, id: \.self) { i in
                    Capsule()
                        .fill(segmentColor(i))
                        .frame(height: 8)
                }
            }
            TimelineView(.periodic(from: game.startedAt, by: 1)) { context in
                let elapsed: Int = max(0, Int(context.date.timeIntervalSince(game.startedAt)))
                Text(PhonePlayTime.clock(elapsed))
                    .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(PhonePlayDesign.surface))
            }
        }
        .padding(.top, 6)
    }

    private func segmentColor(_ i: Int) -> Color {
        if i < game.answers.count {
            return game.answers[i] ? PhonePlayDesign.green : PhonePlayDesign.red
        }
        if i == game.index { return Color.white.opacity(0.6) }
        return Color.white.opacity(0.12)
    }
}

private struct DailyPuzzleCard: View {
    let puzzle: DailyPuzzle
    let number: Int
    let total: Int
    let selected: Int?
    let onAnswer: (Int) -> Void

    @State private var angle: Double = 80

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: puzzle.symbol)
                        .font(.system(size: 15, weight: .bold))
                    Text(puzzle.kind.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2)
                    Spacer()
                    Text("\(number) / \(total)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                .foregroundColor(PhonePlayDesign.cyan)

                Text(puzzle.prompt)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .strokeBorder(PhonePlayDesign.cyan.opacity(0.25), lineWidth: 1)
                    )
            )
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.5)

            VStack(spacing: 10) {
                ForEach(Array(puzzle.options.enumerated()), id: \.offset) { pair in
                    DailyOptionButton(text: pair.element,
                                      letter: optionLetter(pair.offset),
                                      state: state(for: pair.offset)) {
                        onAnswer(pair.offset)
                    }
                }
            }

            if selected != nil {
                Text(puzzle.explain)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.pop, value: selected)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                angle = 0
            }
        }
    }

    private func optionLetter(_ i: Int) -> String {
        let letters = ["A", "B", "C", "D"]
        return letters.indices.contains(i) ? letters[i] : ""
    }

    private func state(for i: Int) -> DailyOptionButton.Mark {
        guard let chosen = selected else { return .idle }
        if i == puzzle.answerIndex { return .right }
        if i == chosen { return .wrong }
        return .dimmed
    }
}

private struct DailyOptionButton: View {
    enum Mark { case idle, right, wrong, dimmed }

    let text: String
    let letter: String
    let state: Mark
    let action: () -> Void

    private var fill: Color {
        switch state {
        case .idle:   return PhonePlayDesign.surface2
        case .right:  return PhonePlayDesign.green
        case .wrong:  return PhonePlayDesign.red
        case .dimmed: return PhonePlayDesign.surface
        }
    }

    private var textColor: Color {
        switch state {
        case .right:  return .black
        case .dimmed: return PhonePlayDesign.text3
        default:      return .white
        }
    }

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Text(letter)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(textColor.opacity(0.8))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                Text(text)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if state == .right {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)
                        .transition(.scale.combined(with: .opacity))
                } else if state == .wrong {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .scaleEffect(state == .right ? 1.03 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(state != .idle)
    }
}

// MARK: - Finished

private struct DailyFinishedView: View {
    @ObservedObject var game: DailyViewModel

    @State private var appeared: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let result = game.result {
                    VStack(spacing: 4) {
                        Text("TODAY'S SCORE")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(2)
                            .foregroundColor(PhonePlayDesign.text3)
                        Text("\(result.score)")
                            .font(.system(size: 90, weight: .black, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(DailyStyle.colors))
                            .scaleEffect(appeared ? 1 : 0.5)
                            .opacity(appeared ? 1 : 0)
                        Text("\(result.correct) of \(DailyBrain.puzzlesPerDay) right in \(PhonePlayTime.clock(result.seconds))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    if !game.answers.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(game.answers.enumerated()), id: \.offset) { pair in
                                Image(systemName: pair.element ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 26, weight: .bold))
                                    .foregroundColor(pair.element ? PhonePlayDesign.green : PhonePlayDesign.red)
                            }
                        }
                    }
                }

                DailyStreakBadge(streak: game.streak, large: true)

                comeBackCard

                if !game.leaderboard.isEmpty {
                    leaderboardCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.1)) {
                appeared = true
            }
        }
    }

    private var comeBackCard: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(spacing: 8) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(PhonePlayDesign.yellow)
                Text("Come back tomorrow")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Next challenge in \(Self.untilTomorrow(from: context.date))")
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(PhonePlayDesign.text2)
                if game.bestStreak > 0 {
                    Text("Best streak: \(game.bestStreak) days")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface))
        }
    }

    private var leaderboardCard: some View {
        VStack(spacing: 10) {
            PhonePlaySectionLabel(text: "Today's leaderboard")
            ForEach(game.leaderboard) { row in
                HStack(spacing: 12) {
                    Text("\(row.id + 1)")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(row.id == 0 ? .black : .white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(row.id == 0 ? PhonePlayDesign.yellow : PhonePlayDesign.surface2))
                    Text(row.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(row.score)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.cyan)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
            .fill(PhonePlayDesign.surface))
        .transition(.opacity)
    }

    nonisolated private static func untilTomorrow(from now: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        let total = max(0, Int(tomorrow.timeIntervalSince(now)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%dh %02dm %02ds", h, m, s)
    }
}
