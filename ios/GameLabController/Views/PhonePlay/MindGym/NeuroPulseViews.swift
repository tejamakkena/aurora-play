import SwiftUI

// MARK: - Mind Gym screens
//
// One runner drives all ten steps: a ten-dot rail, the discipline and
// level, a cosmetic countdown ring, then whichever input the step asks
// for (four cards, a keypad, a grid, the breathing pacer or a grounding
// prompt). Everything is drawn from PhonePlayDesign tokens and the shared
// Phone Play components, so the Mind Gym looks like the rest of the app.

/// The Mind Gym's slice of the Phone Play palette.
enum NeuroStyle {
    static let colors: [Color] = [PhonePlayDesign.indigo, PhonePlayDesign.cyan]
    static let flame: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.orange]
    static let calm: [Color] = [PhonePlayDesign.cyan, PhonePlayDesign.green]

    /// One accent per discipline, from the Phone Play palette.
    static func tint(_ discipline: String) -> Color {
        switch discipline {
        case "logic":   return PhonePlayDesign.indigo
        case "math":    return PhonePlayDesign.cyan
        case "memory":  return PhonePlayDesign.pink
        case "pattern": return PhonePlayDesign.yellow
        case "zen":     return PhonePlayDesign.green
        default:        return PhonePlayDesign.blue
        }
    }

    /// The Stroop ink names the server sends, mapped to the palette.
    static func ink(_ name: String) -> Color {
        switch name.lowercased() {
        case "red":    return PhonePlayDesign.red
        case "blue":   return PhonePlayDesign.blue
        case "green":  return PhonePlayDesign.green
        case "yellow": return PhonePlayDesign.yellow
        case "purple": return PhonePlayDesign.purple
        case "orange": return PhonePlayDesign.orange
        default:       return .white
        }
    }
}

extension NeuroVisual {
    /// The rotation puzzle's target shape, for BrainShapeView.
    var targetBrainCells: [BrainCell] { NeuroVisual.brainCells(from: target) }

    /// One of the four candidate shapes.
    func choiceBrainCells(_ index: Int) -> [BrainCell] {
        guard choices.indices.contains(index) else { return [] }
        return NeuroVisual.brainCells(from: choices[index])
    }

    static func brainCells(from pairs: [[Int]]) -> [BrainCell] {
        pairs.compactMap { pair in
            pair.count >= 2 ? BrainCell(x: pair[0], y: pair[1]) : nil
        }
    }
}

// MARK: - Root

struct NeuroPulseRootView: View {
    @ObservedObject var game: NeuroPulseViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Group {
                    switch game.stage {
                    case .running:
                        NeuroRunnerView(game: game)
                            .transition(.opacity)
                    case .results:
                        NeuroResultsView(game: game, onDone: {
                            game.deliverResult()
                            onExit()
                        })
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                    case .progress:
                        NeuroMindScoreView(game: game)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
        .fullScreenCover(item: $game.arcadeRequest) { request in
            NeuroArcadeRootView(game: request, onClose: { game.arcadeRequest = nil })
        }
    }

    private var title: String {
        switch game.stage {
        case .running:  return "Mind Gym"
        case .results:  return "Today's pulse"
        case .progress: return "Mind Score"
        }
    }

    private var topBar: some View {
        PhonePlayTopBar(title: title,
                        backTitle: backTitle,
                        onBack: onBack,
                        trailing: trailing)
    }

    private var backTitle: String {
        game.stage == .progress && !game.progressIsRoot ? "Back" : "Home"
    }

    private func onBack() {
        if game.stage == .progress && !game.progressIsRoot {
            game.closeProgress()
        } else {
            onExit()
        }
    }

    private var trailing: AnyView? {
        guard game.stage == .running else { return nil }
        return AnyView(
            Button {
                game.showProgress()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Progress")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PhonePlayPressStyle())
        )
    }
}

// MARK: - The runner

private struct NeuroRunnerView: View {
    @ObservedObject var game: NeuroPulseViewModel

    var body: some View {
        VStack(spacing: 14) {
            NeuroRail(game: game)
            if let step = game.step {
                NeuroStepHeader(game: game, step: step)
                ScrollView {
                    VStack(spacing: 16) {
                        NeuroPromptCard(step: step, phase: game.phase)
                        NeuroVisualPanel(game: game, step: step)
                        if game.hintShown, !step.hint.isEmpty {
                            hintCard(step.hint)
                        }
                        inputArea(step)
                        if game.hintAvailable {
                            PhonePlayGhostButton(title: "Hint", symbol: "lightbulb.fill") {
                                game.revealHint()
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 26)
                }
            } else {
                Spacer()
            }
        }
        .padding(.top, 4)
        .animation(PhonePlayDesign.pop, value: game.stepIndex)
        .animation(PhonePlayDesign.pop, value: game.phase)
        .animation(PhonePlayDesign.pop, value: game.hintShown)
    }

    @ViewBuilder
    private func inputArea(_ step: NeuroStep) -> some View {
        if case .feedback(let correct) = game.phase {
            NeuroFeedbackCard(step: step, correct: correct, onNext: game.nextNow)
        } else if game.phase == .flash {
            Text("Watch closely")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else {
            switch step.inputStyle {
            case .choice:
                NeuroChoiceArea(step: step, chosen: game.chosen) { option in
                    game.choose(option)
                }
            case .number:
                NeuroNumberArea(typed: game.typed,
                                enabled: game.canSubmitNumber,
                                onDigit: game.tapDigit,
                                onDelete: game.deleteDigit,
                                onSubmit: game.submitNumber)
            case .grid:
                NeuroGridArea(step: step, mode: .answer, tapped: game.tapped) { cell in
                    game.tapCell(cell)
                }
            case .breathe:
                NeuroBreatheArea(game: game, step: step)
            case .reflect:
                NeuroReflectArea(game: game, step: step)
            }
        }
    }

    private func hintCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.yellow)
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PhonePlayDesign.yellow.opacity(0.1))
        )
        .transition(.opacity)
    }
}

// MARK: - The ten-dot rail

private struct NeuroRail: View {
    @ObservedObject var game: NeuroPulseViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<game.totalSteps, id: \.self) { index in
                Capsule()
                    .fill(color(game.mark(at: index)))
                    .frame(height: index == game.stepIndex ? 9 : 7)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(index == game.stepIndex ? 0.5 : 0),
                                          lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 20)
        .animation(PhonePlayDesign.pop, value: game.stepIndex)
    }

    private func color(_ mark: NeuroRailMark) -> Color {
        switch mark {
        case .right:    return PhonePlayDesign.green
        case .wrong:    return PhonePlayDesign.red
        case .rested:   return PhonePlayDesign.cyan
        case .current:  return Color.white.opacity(0.7)
        case .upcoming: return Color.white.opacity(0.12)
        }
    }
}

// MARK: - Discipline, level and the cosmetic ring

private struct NeuroStepHeader: View {
    @ObservedObject var game: NeuroPulseViewModel
    let step: NeuroStep

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: NeuroDiscipline.symbol(step.discipline))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(NeuroStyle.tint(step.discipline))
                .frame(width: 38, height: 38)
                .background(Circle().fill(PhonePlayDesign.surface))
            VStack(alignment: .leading, spacing: 2) {
                Text(game.disciplineName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Level \(step.level) of 10  -  Step \(step.index + 1) of \(game.totalSteps)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            if game.phase == .answer, game.targetSeconds > 0, step.isGraded {
                NeuroCountdownRing(start: game.stepStartedAt,
                                   seconds: game.targetSeconds,
                                   tint: NeuroStyle.tint(step.discipline))
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// Fills up over the step's target time. Running over does not fail the
/// step: the ring simply sits full and goes quiet.
private struct NeuroCountdownRing: View {
    let start: Date
    let seconds: Double
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed: Double = max(0, context.date.timeIntervalSince(start))
            let fraction: Double = seconds > 0 ? min(1, elapsed / seconds) : 0
            let left: Int = max(0, Int((seconds - elapsed).rounded(.up)))
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(fraction >= 1 ? PhonePlayDesign.text3 : tint,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                Text(fraction >= 1 ? "-" : "\(left)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(fraction >= 1 ? PhonePlayDesign.text3 : .white)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The prompt

private struct NeuroPromptCard: View {
    let step: NeuroStep
    let phase: NeuroPulseViewModel.Phase

    var body: some View {
        VStack(spacing: 12) {
            if step.kind == "stroop", !step.visual.word.isEmpty {
                Text(step.visual.word.uppercased())
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(NeuroStyle.ink(step.visual.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(step.prompt)
                .font(.system(size: promptSize, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(step.kind == "liars_row" ? .leading : .center)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity,
                       alignment: step.kind == "liars_row" ? .leading : .center)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .strokeBorder(NeuroStyle.tint(step.discipline).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var promptSize: CGFloat {
        if step.prompt.count > 150 { return 16 }
        if step.prompt.count > 90 { return 18 }
        return 21
    }
}

// MARK: - What has to be remembered

/// The flash digits, the n-back run, the grid that lights up and the
/// rotation target. Empty for a step with nothing to show.
private struct NeuroVisualPanel: View {
    @ObservedObject var game: NeuroPulseViewModel
    let step: NeuroStep

    var body: some View {
        switch step.kind {
        case "flash":
            if game.phase == .flash {
                digits
            }
        case "nback":
            if game.phase == .flash {
                letter
            }
        case "grid":
            if game.phase == .flash {
                NeuroGridArea(step: step, mode: .flash, tapped: [], onTap: { _ in })
            } else if case .feedback = game.phase {
                NeuroGridArea(step: step, mode: .reveal, tapped: game.tapped, onTap: { _ in })
            }
        case "rotation":
            if !step.visual.targetBrainCells.isEmpty {
                target
            }
        case "dead_reckoning":
            VStack(spacing: 14) {
                NeuroMoveChips(moves: step.visual.moves)
                if case .feedback = game.phase {
                    NeuroGridArea(step: step, mode: .reveal, tapped: game.tapped, onTap: { _ in })
                }
            }
        default:
            EmptyView()
        }
    }

    private var digits: some View {
        HStack(spacing: 10) {
            ForEach(Array(step.visual.flashDigits.enumerated()), id: \.offset) { pair in
                Text("\(pair.element)")
                    .font(.system(size: 36, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(width: 44, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(PhonePlayDesign.surface2)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.scale.combined(with: .opacity))
    }

    private var letter: some View {
        let run = step.visual.flashLetters
        let index = min(max(0, game.flashLetterIndex), max(0, run.count - 1))
        return Text(run.isEmpty ? "" : run[index])
            .font(.system(size: 92, weight: .black, design: .rounded))
            .foregroundStyle(PhonePlayDesign.gradient(NeuroStyle.colors))
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .id(index)
            .transition(.scale.combined(with: .opacity))
    }

    private var target: some View {
        VStack(spacing: 8) {
            Text("THIS SHAPE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
            BrainShapeView(cells: step.visual.targetBrainCells,
                           color: NeuroStyle.tint(step.discipline), depth: 2)
                .frame(height: 110)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }
}

// MARK: - Four tappable cards

private struct NeuroChoiceArea: View {
    let step: NeuroStep
    let chosen: String?
    let onChoose: (String) -> Void

    private var hasShapes: Bool { !step.visual.choices.isEmpty }

    private var isWide: Bool {
        if hasShapes { return false }
        let longest = step.options.map { $0.count }.max() ?? 0
        return longest > 12
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        if isWide {
            VStack(spacing: 12) {
                ForEach(Array(step.options.enumerated()), id: \.offset) { pair in
                    card(index: pair.offset, text: pair.element, tall: false)
                }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(step.options.enumerated()), id: \.offset) { pair in
                    card(index: pair.offset, text: pair.element, tall: true)
                }
            }
        }
    }

    private func card(index: Int, text: String, tall: Bool) -> some View {
        NeuroOptionCard(text: text,
                        letter: NeuroChoiceArea.letter(index),
                        shape: step.visual.choiceBrainCells(index),
                        tint: NeuroStyle.tint(step.discipline),
                        tall: tall,
                        picked: chosen == text,
                        dimmed: chosen != nil && chosen != text) {
            onChoose(text)
        }
    }

    static func letter(_ index: Int) -> String {
        let letters: [String] = ["A", "B", "C", "D", "E", "F"]
        return letters.indices.contains(index) ? letters[index] : "\(index + 1)"
    }
}

private struct NeuroOptionCard: View {
    let text: String
    let letter: String
    let shape: [BrainCell]
    let tint: Color
    let tall: Bool
    let picked: Bool
    let dimmed: Bool
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(letter)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(picked ? .black : tint)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(picked ? Color.white : Color.white.opacity(0.1)))
                    if shape.isEmpty {
                        Text(text)
                            .font(.system(size: tall ? 19 : 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                if !shape.isEmpty {
                    BrainShapeView(cells: shape, color: .white, depth: 2)
                        .frame(height: 78)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: tall ? 92 : 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(picked ? PhonePlayDesign.gradient([tint, tint.opacity(0.6)])
                                 : PhonePlayDesign.gradient([PhonePlayDesign.surface2,
                                                             PhonePlayDesign.surface2]))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(picked ? 0.35 : 0.08), lineWidth: 1)
            )
            .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(dimmed || picked)
    }
}

// MARK: - Keypad

struct NeuroNumberArea: View {
    let typed: String
    let enabled: Bool
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    let onSubmit: () -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text(typed.isEmpty ? " " : typed)
                .font(.system(size: 40, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PhonePlayDesign.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .contentTransition(.numericText())
                .animation(PhonePlayDesign.pop, value: typed)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...9, id: \.self) { digit in
                    key(title: "\(digit)") { onDigit(digit) }
                }
                key(symbol: "delete.left.fill", muted: true) { onDelete() }
                key(title: "0") { onDigit(0) }
                key(symbol: "checkmark", accent: true) { onSubmit() }
            }
        }
    }

    private func key(title: String? = nil, symbol: String? = nil, muted: Bool = false,
                     accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                        .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(accent ? (enabled ? .black : .white.opacity(0.3)) : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill(muted: muted, accent: accent))
            )
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(accent && !enabled)
    }

    private func fill(muted: Bool, accent: Bool) -> Color {
        if accent { return enabled ? PhonePlayDesign.green : PhonePlayDesign.surface }
        if muted { return PhonePlayDesign.surface }
        return PhonePlayDesign.surface2
    }
}

// MARK: - Dead Reckoning moves

/// The moves in words, numbered, in the order the dot takes them.
private struct NeuroMoveChips: View {
    let moves: [String]

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 8) {
            ForEach(Array(moves.enumerated()), id: \.offset) { pair in
                HStack(spacing: 6) {
                    Text("\(pair.offset + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.text3)
                    Text(pair.element)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule().fill(PhonePlayDesign.surface2)
                )
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Spatial grid

private struct NeuroGridArea: View {
    enum Mode: Equatable {
        case flash      // the cells that lit up
        case answer     // tap them back
        case reveal     // right, missed and wrong, after the answer
    }

    let step: NeuroStep
    let mode: Mode
    let tapped: [Int]
    let onTap: (Int) -> Void

    private var rows: Int { step.gridRows }
    private var cols: Int { step.gridCols }
    /// The cells that were lit; for Dead Reckoning, where nothing is lit, the
    /// one cell the dot ends on.
    private var lit: Set<Int> {
        step.visual.start != nil ? Set(NeuroStep.gridIndices(step.answer)) : Set(step.visual.cells)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<cols, id: \.self) { col in
                        cell(row * cols + col)
                    }
                }
            }
            if mode == .answer {
                Text("\(tapped.count) of \(step.gridAnswerCount) tapped")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    private func cell(_ index: Int) -> some View {
        Button {
            guard mode == .answer else { return }
            onTap(index)
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fill(index))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(border(index), lineWidth: 2)
                )
                .overlay(startDot(index))
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(mode != .answer)
    }

    /// Dead Reckoning's starting point: a white dot on a blank grid.
    @ViewBuilder
    private func startDot(_ index: Int) -> some View {
        if step.visual.start == index {
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
    }

    private func fill(_ index: Int) -> Color {
        switch mode {
        case .flash:
            return lit.contains(index) ? PhonePlayDesign.pink : PhonePlayDesign.surface2
        case .answer:
            return tapped.contains(index) ? PhonePlayDesign.cyan : PhonePlayDesign.surface2
        case .reveal:
            if lit.contains(index) && tapped.contains(index) { return PhonePlayDesign.green }
            if tapped.contains(index) { return PhonePlayDesign.red }
            return PhonePlayDesign.surface2
        }
    }

    private func border(_ index: Int) -> Color {
        guard mode == .reveal, lit.contains(index), !tapped.contains(index) else {
            return Color.clear
        }
        return PhonePlayDesign.green.opacity(0.8)
    }
}

// MARK: - Breathing pacer

private struct NeuroBreatheArea: View {
    @ObservedObject var game: NeuroPulseViewModel
    let step: NeuroStep

    private var expanded: Bool {
        // Phase 0 breathes in, 1 holds full, 2 breathes out, 3 holds empty.
        game.breathPhase == 0 || game.breathPhase == 1
    }

    private var label: String {
        let labels = step.visual.breathLabels
        let index = max(0, min(labels.count - 1, game.breathPhase))
        return labels[index]
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(PhonePlayDesign.cyan.opacity(0.18), lineWidth: 2)
                    .frame(width: 230, height: 230)
                Circle()
                    .fill(PhonePlayDesign.gradient([PhonePlayDesign.cyan.opacity(0.75),
                                                    PhonePlayDesign.green.opacity(0.5)]))
                    .frame(width: expanded ? 220 : 110, height: expanded ? 220 : 110)
                    .animation(.easeInOut(duration: game.breathPhaseSeconds), value: game.breathPhase)
                VStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(game.breathSecondsLeft)")
                        .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
            }
            .frame(height: 240)

            Text("Round \(game.breathCycle) of \(game.breathCycles)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)

            PhonePlayGhostButton(title: "Skip", symbol: "forward.fill") {
                game.skipRest()
            }
        }
    }
}

// MARK: - Sensory reset

private struct NeuroReflectArea: View {
    @ObservedObject var game: NeuroPulseViewModel
    let step: NeuroStep

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .strokeBorder(PhonePlayDesign.green.opacity(0.18), lineWidth: 2)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(PhonePlayDesign.gradient(NeuroStyle.calm))
                    .phonePlayIdle(dy: 4, degrees: 4, duration: 2.2)
            }
            .frame(width: 150, height: 150)

            Text(PhonePlayTime.clock(game.reflectSecondsLeft))
                .font(.system(size: 32, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .contentTransition(.numericText())

            Text("No score here. Take the time.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)

            PhonePlayBigButton(title: "Done", symbol: "checkmark",
                               colors: NeuroStyle.calm) {
                game.skipRest()
            }
        }
    }
}

// MARK: - Right or wrong, with the explanation

private struct NeuroFeedbackCard: View {
    let step: NeuroStep
    let correct: Bool
    let onNext: () -> Void

    private var graded: Bool { step.isGraded }

    private var tint: Color {
        if !graded { return PhonePlayDesign.cyan }
        return correct ? PhonePlayDesign.green : PhonePlayDesign.red
    }

    private var title: String {
        if !graded { return "Nicely done" }
        return correct ? "Correct" : "Not this time"
    }

    private var symbol: String {
        if !graded { return "wind" }
        return correct ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            }
            if graded, !correct, !step.answer.isEmpty {
                HStack(spacing: 6) {
                    Text("Answer")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundColor(PhonePlayDesign.text3)
                    Text(step.answer)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
            }
            if !step.explain.isEmpty {
                Text(step.explain)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PhonePlayGhostButton(title: "Next", symbol: "arrow.right") {
                onNext()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient([tint.opacity(0.14), Color.clear]))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Streak badge

/// The flame and the day count, shared by the results and Mind Score
/// screens (the Daily Brain Challenge has the same badge).
struct NeuroStreakBadge: View {
    let streak: Int
    var large: Bool = false

    @State private var bump: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: large ? 28 : 18, weight: .bold))
                .foregroundStyle(PhonePlayDesign.gradient(NeuroStyle.flame))
                .symbolEffect(.bounce, value: bump)
            Text("\(streak)")
                .font(.system(size: large ? 32 : 20, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            Text(streak == 1 ? "day" : "day streak")
                .font(.system(size: large ? 16 : 13, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .padding(.horizontal, large ? 20 : 14)
        .padding(.vertical, large ? 12 : 9)
        .background(Capsule().fill(PhonePlayDesign.orange.opacity(0.14)))
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                bump += 1
            }
        }
    }
}

// MARK: - Results

private struct NeuroResultsView: View {
    @ObservedObject var game: NeuroPulseViewModel
    let onDone: () -> Void

    @State private var shownPulse: Int = 0
    @State private var appeared: Bool = false

    private var summary: NeuroSummary { game.summary ?? NeuroSummary() }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pulseBlock
                NeuroStreakBadge(streak: max(game.streak, summary.streak), large: true)
                if !summary.movedDisciplines.isEmpty {
                    deltaBlock
                }
                if !summary.improvedMost.isEmpty {
                    improvedBlock
                }
                moodBlock
                PhonePlayBigButton(title: "Done", symbol: "checkmark",
                                   colors: NeuroStyle.colors) {
                    onDone()
                }
                if summary.alreadyPlayed {
                    Text("Today's ratings were already counted. This run was just for fun.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { appeared = true }
            countUp(to: summary.pulse)
        }
        .onChange(of: game.summary) { _, _ in
            countUp(to: summary.pulse)
        }
    }

    private var pulseBlock: some View {
        VStack(spacing: 4) {
            Text("TODAY'S PULSE")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
            Text("\(shownPulse)")
                .font(.system(size: 84, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(PhonePlayDesign.gradient(NeuroStyle.colors))
                .contentTransition(.numericText())
                .scaleEffect(appeared ? 1 : 0.6)
            Text("\(summary.correct) of \(max(summary.graded, 1)) right in \(PhonePlayTime.clock(game.finishedSeconds))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.top, 6)
    }

    private var deltaBlock: some View {
        VStack(spacing: 10) {
            PhonePlaySectionLabel(text: "Ratings")
            ForEach(summary.movedDisciplines, id: \.self) { key in
                HStack(spacing: 10) {
                    Image(systemName: NeuroDiscipline.symbol(key))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(NeuroStyle.tint(key))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PhonePlayDesign.surface2))
                    Text(summary.displayName(key))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text("\(summary.ratings[key] ?? 0)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.text2)
                    NeuroDeltaChip(delta: summary.deltas[key] ?? 0)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    private var improvedBlock: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.green)
            Text("You improved most in \(summary.displayName(summary.improvedMost))")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(PhonePlayDesign.green.opacity(0.12))
        )
    }

    private var moodBlock: some View {
        VStack(spacing: 10) {
            PhonePlaySectionLabel(text: "How do you feel?")
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    PhonePlayChip(title: "\(value)",
                                  subtitle: NeuroResultsView.moodWords[value - 1],
                                  selected: game.mood == value,
                                  colors: NeuroStyle.colors) {
                        game.setMood(value)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    private static let moodWords: [String] = ["Rough", "Low", "Fine", "Good", "Great"]

    /// Counts the headline number up, and recounts if the server's own
    /// number lands while the screen is still open.
    private func countUp(to target: Int) {
        guard target > 0 else {
            shownPulse = 0
            return
        }
        let steps = 22
        shownPulse = 0
        Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: 28_000_000)
                let eased = Double(i) / Double(steps)
                shownPulse = Int((Double(target) * eased).rounded())
            }
            shownPulse = target
        }
    }
}

// MARK: - A rating move

struct NeuroDeltaChip: View {
    let delta: Int

    private var tint: Color {
        if delta > 0 { return PhonePlayDesign.green }
        if delta < 0 { return PhonePlayDesign.red }
        return PhonePlayDesign.text3
    }

    private var text: String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return "0"
    }

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}
