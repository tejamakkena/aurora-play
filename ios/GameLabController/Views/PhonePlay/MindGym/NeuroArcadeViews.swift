import SwiftUI

// MARK: - The Mind Gym arcade: screens
//
// The shelf on the Mind Score screen, then one full-screen flow per game:
// how it works, the run itself, and the result. The rules live in
// NeuroArcadeEngine.swift; everything here is drawn from Phone Play tokens.

// MARK: - The shelf

/// Two tiles on the Mind Score screen, one per arcade game.
struct NeuroArcadeShelf: View {
    let onOpen: (NeuroArcadeGame) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhonePlaySectionLabel(text: "Arcade")
            ForEach(NeuroArcadeGame.allCases) { game in
                tile(game)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    private func tile(_ game: NeuroArcadeGame) -> some View {
        let stats = NeuroArcadeStore.stats(game)
        let ready = !NeuroArcadeStore.ratedToday(game)
        return Button {
            PhonePlayHaptics.tap()
            onOpen(game)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: game.symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                            .fill(PhonePlayDesign.gradient(game.colors))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle(game: game, stats: stats))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text(ready ? "Rated run" : "Practice")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(ready ? .black : PhonePlayDesign.text2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(ready ? Color.white.opacity(0.92) : PhonePlayDesign.surface2)
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface2.opacity(0.6))
            )
        }
        .buttonStyle(PhonePlayPressStyle())
    }

    private func subtitle(game: NeuroArcadeGame, stats: NeuroArcadeStats) -> String {
        guard stats.plays > 0 else { return game.skill }
        return "\(game.skill)  |  best \(Int((stats.best * 100).rounded()))%"
    }
}

// MARK: - The flow around a run

@MainActor
final class NeuroArcadeFlow: ObservableObject {
    enum Phase: Equatable {
        case intro
        case playing
        case result
    }

    let game: NeuroArcadeGame

    @Published private(set) var phase: Phase = .intro
    /// True when today's counting run is already used up.
    @Published private(set) var practice: Bool
    @Published private(set) var level: Int
    @Published private(set) var runID: Int = 0
    @Published private(set) var seed: String = ""
    @Published private(set) var score: Double = 0
    @Published private(set) var detail: String = ""
    @Published private(set) var outcome: NeuroArcadeOutcome? = nil
    @Published private(set) var posting: Bool = false

    private var startedAt = Date()

    init(game: NeuroArcadeGame) {
        self.game = game
        practice = NeuroArcadeStore.ratedToday(game)
        level = NeuroArcadeStore.level(for: game)
    }

    func begin() {
        practice = NeuroArcadeStore.ratedToday(game)
        level = NeuroArcadeStore.level(for: game)
        // Today's counting run is the same puzzle on every visit; practice
        // runs are always fresh.
        seed = practice
            ? UUID().uuidString
            : "\(game.rawValue)|\(NeuroStore.todayKey())|\(AppConstants.deviceID)"
        score = 0
        detail = ""
        outcome = nil
        startedAt = Date()
        runID += 1
        phase = .playing
    }

    func finish(score: Double, detail: String) {
        guard phase == .playing else { return }
        let clamped = max(0, min(1, score))
        self.score = clamped
        self.detail = detail
        let rated = !practice
        NeuroArcadeStore.record(game, score: clamped, rated: rated)
        phase = .result
        PhonePlayHaptics.success()

        let body: [String: Any] = [
            "device": AppConstants.deviceID,
            "game": game.rawValue,
            "level": level,
            "score": clamped,
            "seconds": max(0, Int(Date().timeIntervalSince(startedAt))),
            "date": NeuroStore.todayKey(),
            "name": NeuroStore.playerName,
            "practice": practice,
        ]
        guard let payload = NeuroJSON.data(body) else { return }
        posting = true
        Task { [weak self] in
            let reply = await NeuroAPI.post(arcadeData: payload)
            guard let self else { return }
            self.posting = false
            if let reply {
                self.outcome = reply
            } else if rated {
                NeuroArcadeStore.queue(body)
            }
        }
    }
}

// MARK: - Root

struct NeuroArcadeRootView: View {
    let game: NeuroArcadeGame
    let onClose: () -> Void

    @StateObject private var flow: NeuroArcadeFlow

    init(game: NeuroArcadeGame, onClose: @escaping () -> Void) {
        self.game = game
        self.onClose = onClose
        _flow = StateObject(wrappedValue: NeuroArcadeFlow(game: game))
    }

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PhonePlayTopBar(title: game.title, backTitle: "Back", onBack: onClose)
                Group {
                    switch flow.phase {
                    case .intro:
                        NeuroArcadeIntro(flow: flow)
                    case .playing:
                        playing
                    case .result:
                        NeuroArcadeResult(flow: flow, onClose: onClose)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(PhonePlayDesign.smooth, value: flow.phase)
    }

    @ViewBuilder
    private var playing: some View {
        switch game {
        case .probe:
            ProbePlayView(level: flow.level, seed: flow.seed) { score, detail in
                flow.finish(score: score, detail: detail)
            }
            .id(flow.runID)
        case .drift:
            DriftPlayView(level: flow.level, seed: flow.seed) { score, detail in
                flow.finish(score: score, detail: detail)
            }
            .id(flow.runID)
        }
    }
}

// MARK: - Intro

private struct NeuroArcadeIntro: View {
    @ObservedObject var flow: NeuroArcadeFlow

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: flow.game.symbol)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 76, height: 76)
                        .background(Circle().fill(PhonePlayDesign.gradient(flow.game.colors)))
                    Text(flow.game.title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(flow.game.blurb)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 10)

                VStack(alignment: .leading, spacing: 12) {
                    PhonePlaySectionLabel(text: "How it works")
                    ForEach(Array(flow.game.howTo.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(pair.offset + 1)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                                .foregroundColor(.black)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.white.opacity(0.9)))
                            Text(pair.element)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface)
                )

                Text(flow.practice
                     ? "Today's rated run is done. This one is for practice and will not change your rating."
                     : "Your first run each day moves your \(NeuroDiscipline.name(flow.game.discipline, names: [:])) rating.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PhonePlayBigButton(title: flow.practice ? "Practice" : "Start",
                                   symbol: "play.fill",
                                   colors: flow.game.colors) {
                    flow.begin()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }
}

// MARK: - Result

private struct NeuroArcadeResult: View {
    @ObservedObject var flow: NeuroArcadeFlow
    let onClose: () -> Void

    private var percent: Int { Int((flow.score * 100).rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: CGFloat(flow.score))
                        .stroke(PhonePlayDesign.gradient(flow.game.colors),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(percent)")
                            .font(.system(size: 54, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundColor(.white)
                        Text("score")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                    }
                }
                .frame(width: 170, height: 170)
                .padding(.top, 16)

                Text(flow.detail)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)

                ratingChip

                VStack(spacing: 10) {
                    PhonePlayBigButton(title: "Play again", symbol: "arrow.clockwise",
                                       colors: flow.game.colors) {
                        flow.begin()
                    }
                    PhonePlayGhostButton(title: "Done", symbol: "checkmark") {
                        onClose()
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private var ratingChip: some View {
        if let outcome = flow.outcome, outcome.rated {
            let sign = outcome.delta >= 0 ? "+" : ""
            chip(symbol: outcome.delta >= 0 ? "arrow.up.right" : "arrow.down.right",
                 text: "\(NeuroDiscipline.name(outcome.discipline, names: [:])) \(outcome.after) (\(sign)\(outcome.delta))",
                 tint: outcome.delta >= 0 ? PhonePlayDesign.green : PhonePlayDesign.orange)
        } else if flow.outcome != nil || flow.practice {
            chip(symbol: "figure.walk", text: "Practice run, rating unchanged",
                 tint: PhonePlayDesign.text2)
        } else if flow.posting {
            chip(symbol: "arrow.triangle.2.circlepath", text: "Rating your run",
                 tint: PhonePlayDesign.cyan)
        } else {
            chip(symbol: "icloud.slash", text: "Saved. It will be rated when you are back online.",
                 tint: PhonePlayDesign.text2)
        }
    }

    private func chip(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - Probe

private struct ProbePlayView: View {
    let level: Int
    let seed: String
    let onFinish: (Double, String) -> Void

    private enum Stage {
        case probing
        case predicting
    }

    @State private var puzzle: ProbePuzzle
    @State private var rng: PhonePlaySeededRandom
    @State private var samples: [ProbeSample] = []
    @State private var typed = ""
    @State private var stage: Stage = .probing
    @State private var testInput = 0
    @State private var done = false

    init(level: Int, seed: String, onFinish: @escaping (Double, String) -> Void) {
        self.level = level
        self.seed = seed
        self.onFinish = onFinish
        _puzzle = State(initialValue: ProbeEngine.puzzle(level: level, seed: seed))
        _rng = State(initialValue: PhonePlaySeededRandom(text: "probe-test|" + seed))
    }

    private var typedValue: Int? { Int(typed) }

    private var canRun: Bool {
        guard stage == .probing, let value = typedValue,
              value >= 0, value < ProbeEngine.domain,
              samples.count < ProbeEngine.maxProbes else { return false }
        return !samples.contains { $0.input == value }
    }

    private var canPredict: Bool {
        stage == .predicting && !typed.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                machine
                if !samples.isEmpty { log }
                if !done {
                    NeuroNumberArea(typed: typed,
                                    enabled: stage == .probing ? canRun : canPredict,
                                    onDigit: digit,
                                    onDelete: deleteDigit,
                                    onSubmit: submit)
                    if stage == .probing {
                        PhonePlayGhostButton(title: "I know the rule", symbol: "lightbulb.fill") {
                            startPrediction()
                        }
                        .opacity(samples.isEmpty ? 0.4 : 1)
                        .allowsHitTesting(!samples.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .animation(PhonePlayDesign.pop, value: samples.count)
        .animation(PhonePlayDesign.pop, value: stage)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text(stage == .probing ? "Probe the machine" : "Now predict")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(stage == .probing
                 ? "Probe \(min(samples.count + 1, ProbeEngine.maxProbes)) of \(ProbeEngine.maxProbes). Type a number from 0 to 99."
                 : "Type what the machine gives for \(testInput).")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private var machine: some View {
        HStack(spacing: 14) {
            Text(stage == .predicting ? "\(testInput)" : (typed.isEmpty ? "?" : typed))
                .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .frame(minWidth: 70)
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.cyan)
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
            Text(stage == .predicting ? (typed.isEmpty ? "?" : typed) : "?")
                .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(PhonePlayDesign.cyan)
                .frame(minWidth: 70)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhonePlaySectionLabel(text: "What you have seen")
            ForEach(Array(samples.enumerated()), id: \.offset) { pair in
                HStack(spacing: 10) {
                    Text("\(pair.offset + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.text3)
                        .frame(width: 18)
                    Text("\(pair.element.input)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                    Text("\(pair.element.output)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.cyan)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface2)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    // MARK: Input

    private var maxDigits: Int { stage == .probing ? 2 : 5 }

    private func digit(_ value: Int) {
        guard !done, typed.count < maxDigits else { return }
        PhonePlayHaptics.tap()
        // No leading zeros except a lone zero.
        if typed == "0" { typed = "\(value)" } else { typed += "\(value)" }
    }

    private func deleteDigit() {
        guard !typed.isEmpty else { return }
        PhonePlayHaptics.tap()
        typed.removeLast()
    }

    private func submit() {
        switch stage {
        case .probing: runProbe()
        case .predicting: predict()
        }
    }

    private func runProbe() {
        guard canRun, let value = typedValue else { return }
        PhonePlayHaptics.rigid()
        samples.append(ProbeSample(input: value, output: puzzle.rule.outputs[value]))
        typed = ""
        if samples.count >= ProbeEngine.maxProbes {
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                startPrediction()
            }
        }
    }

    private func startPrediction() {
        guard stage == .probing, !samples.isEmpty, !done else { return }
        var generator = rng
        testInput = ProbeEngine.testInput(for: puzzle, samples: samples, rng: &generator)
        rng = generator
        typed = ""
        stage = .predicting
    }

    private func predict() {
        guard canPredict, !done, let guess = typedValue else { return }
        done = true
        let answer = puzzle.rule.outputs[testInput]
        let correct = guess == answer
        let used = samples.count
        let score = ProbeEngine.score(correct: correct, probesUsed: used)
        let name = puzzle.rule.name
        let rule = name.prefix(1).uppercased() + name.dropFirst()
        let detail = correct
            ? "Right: \(testInput) gives \(answer). The rule was: \(rule). You used \(used) probe\(used == 1 ? "" : "s")."
            : "Not quite: \(testInput) gives \(answer). The rule was: \(rule)."
        onFinish(score, detail)
    }
}

// MARK: - Drift

private struct DriftTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A card drawn from three features: the shape, how many of it, and how it
/// is filled. One colour only, so nothing depends on telling colours apart.
private struct DriftCardView: View {
    let card: DriftCard
    let size: CGFloat

    private let tint = PhonePlayDesign.cyan

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(0..<(card.count + 1), id: \.self) { _ in
                mark
            }
        }
        .padding(size * 0.45)
        .frame(minWidth: size * 3.2)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                .fill(PhonePlayDesign.surface2)
        )
    }

    @ViewBuilder
    private var mark: some View {
        switch card.shape {
        case 0:
            styled(Circle())
        case 1:
            styled(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        default:
            styled(DriftTriangle())
        }
    }

    @ViewBuilder
    private func styled<S: Shape>(_ shape: S) -> some View {
        switch card.fill {
        case 0:
            shape.fill(tint).frame(width: size, height: size)
        case 1:
            shape.stroke(tint, lineWidth: 3).frame(width: size, height: size)
        default:
            shape.fill(tint.opacity(0.28))
                .overlay(shape.stroke(tint, lineWidth: 3))
                .frame(width: size, height: size)
        }
    }
}

private struct DriftPlayView: View {
    let level: Int
    let seed: String
    let onFinish: (Double, String) -> Void

    @State private var run: DriftRun
    @State private var flashPile: Int? = nil
    @State private var flashRight = true
    @State private var locked = false
    @State private var message = "Pick a pile."

    init(level: Int, seed: String, onFinish: @escaping (Double, String) -> Void) {
        self.level = level
        self.seed = seed
        self.onFinish = onFinish
        _run = State(initialValue: DriftRun(level: level, seed: seed))
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Sorted \(run.trials)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            .padding(.top, 6)

            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { pile in
                    pileButton(pile)
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Text("This card goes on...")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                DriftCardView(card: run.card, size: 34)
                    .id(run.trials)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .padding(.bottom, 40)
            .animation(PhonePlayDesign.pop, value: run.trials)
        }
        .frame(maxWidth: .infinity)
    }

    private func pileButton(_ pile: Int) -> some View {
        let reference = DriftCard(shape: pile, count: pile, fill: pile)
        return Button {
            tap(pile)
        } label: {
            VStack(spacing: 8) {
                DriftCardView(card: reference, size: 15)
                Text("Pile \(pile + 1)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(border(for: pile), lineWidth: 3)
            )
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(locked)
    }

    private func border(for pile: Int) -> Color {
        guard flashPile == pile else { return Color.white.opacity(0.08) }
        return flashRight ? PhonePlayDesign.green : PhonePlayDesign.red
    }

    private func tap(_ pile: Int) {
        guard !locked, !run.finished else { return }
        locked = true
        let right = run.sort(onto: pile)
        flashPile = pile
        flashRight = right
        message = right ? "Right" : "Not that one"
        if right { PhonePlayHaptics.tap() } else { PhonePlayHaptics.warning() }
        let finished = run.finished
        Task {
            try? await Task.sleep(nanoseconds: finished ? 700_000_000 : 380_000_000)
            flashPile = nil
            if finished {
                let found = run.completedStages
                let total = run.stages
                let detail = found >= total
                    ? "You found all \(total) rules with \(run.errors) wrong sort\(run.errors == 1 ? "" : "s")."
                    : "You found \(found) of \(total) rules in \(run.trials) sorts."
                onFinish(run.score, detail)
            } else {
                locked = false
            }
        }
    }
}
