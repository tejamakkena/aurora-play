import SwiftUI

/// Brain Battle: twelve generated puzzles on the big screen.
///
/// Server contract (games/native_hub/engines/brain_battle.py, public_state):
/// `phase` is "memorize" (memory rounds only), "answer", "reveal", then
/// "summary" after the last round. `puzzle` carries prompt/kind/skill/level/
/// options/visual but never the answer; `memoryDigits` is non-empty only
/// while memorizing; `reveal` (answer, explain, correctIDs, fastestID, ...)
/// only during the reveal; `results` (with brain titles) only at summary.

// MARK: - State

struct BrainBattleAnswerRow: Identifiable, Equatable {
    let id: String
    let name: String
    let choice: String
    let correct: Bool
    let points: Int
}

struct BrainBattleResultRow: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    let rank: Int
    let brainTitle: String
    let brainScore: Int
    let personalBest: Bool
    let bestSkill: String
}

struct BrainBattleBoardState {
    var base = RoundBoardState()
    var puzzleID: String = ""
    var kind: String = ""
    var skill: String = ""
    var level: Int = 1
    var prompt: String = ""
    var options: [String] = []
    var target: [BrainCell] = []
    var choiceShapes: [[BrainCell]] = []
    var memoryDigits: [Int] = []
    var memoryBackwards: Bool = false
    var phaseSeconds: Int = 20
    var lockedCount: Int = 0
    var activeCount: Int = 0
    var hasReveal: Bool = false
    var answer: String = ""
    var explain: String = ""
    var correctIDs: Set<String> = []
    var fastestID: String? = nil
    var fastestName: String? = nil
    var fastestSeconds: Double? = nil
    var answers: [BrainBattleAnswerRow] = []
    var results: [BrainBattleResultRow] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        updatePuzzle(d["puzzle"]?.value as? [String: Any])
        let rawDigits: [Any] = d["memoryDigits"]?.value as? [Any] ?? []
        memoryDigits = rawDigits.compactMap { $0 as? Int }
        if let v = d["memoryBackwards"]?.value as? Bool { memoryBackwards = v }
        if let v = d["phaseSeconds"]?.value as? Int { phaseSeconds = v }
        if let v = d["lockedCount"]?.value as? Int { lockedCount = v }
        if let v = d["activeCount"]?.value as? Int { activeCount = v }
        updateReveal(d["reveal"]?.value as? [String: Any])
        results = BrainBattleBoardState.parseResults(d["results"]?.value)
    }

    private mutating func updatePuzzle(_ p: [String: Any]?) {
        guard let p else {
            options = []
            target = []
            choiceShapes = []
            return
        }
        if let v = p["id"] as? String { puzzleID = v }
        kind = p["kind"] as? String ?? ""
        skill = p["skill"] as? String ?? ""
        level = p["level"] as? Int ?? 1
        prompt = p["prompt"] as? String ?? ""
        let rawOptions: [Any] = p["options"] as? [Any] ?? []
        options = rawOptions.compactMap { $0 as? String }
        if let visual = p["visual"] as? [String: Any] {
            target = BrainCell.list(from: visual["target"])
            choiceShapes = BrainCell.shapes(from: visual["choices"])
        } else {
            target = []
            choiceShapes = []
        }
    }

    private mutating func updateReveal(_ r: [String: Any]?) {
        guard let r else {
            hasReveal = false
            answer = ""
            explain = ""
            correctIDs = []
            fastestID = nil
            fastestName = nil
            fastestSeconds = nil
            answers = []
            return
        }
        hasReveal = true
        answer = r["answer"] as? String ?? ""
        explain = r["explain"] as? String ?? ""
        let ids: [Any] = r["correctIDs"] as? [Any] ?? []
        correctIDs = Set(ids.compactMap { $0 as? String })
        fastestID = r["fastestID"] as? String
        fastestName = r["fastestName"] as? String
        fastestSeconds = BrainBattleBoardState.number(r["fastestSeconds"])
        let rows: [Any] = r["answers"] as? [Any] ?? []
        answers = rows.compactMap { item -> BrainBattleAnswerRow? in
            guard let a = item as? [String: Any], let pid = a["playerID"] as? String else { return nil }
            return BrainBattleAnswerRow(id: pid,
                                        name: a["name"] as? String ?? "Player",
                                        choice: a["choice"] as? String ?? "",
                                        correct: a["correct"] as? Bool ?? false,
                                        points: a["points"] as? Int ?? 0)
        }
    }

    static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    static func parseResults(_ value: Any?) -> [BrainBattleResultRow] {
        let rows: [Any] = value as? [Any] ?? []
        return rows.compactMap { item -> BrainBattleResultRow? in
            guard let r = item as? [String: Any], let pid = r["playerID"] as? String else { return nil }
            return BrainBattleResultRow(id: pid,
                                        name: r["name"] as? String ?? "Player",
                                        score: r["score"] as? Int ?? 0,
                                        rank: r["rank"] as? Int ?? 0,
                                        brainTitle: r["brainTitle"] as? String ?? "Brain in Training",
                                        brainScore: r["brainScore"] as? Int ?? 0,
                                        personalBest: r["personalBest"] as? Bool ?? false,
                                        bestSkill: r["bestSkill"] as? String ?? "")
        }
    }

    func pickCount(for option: String) -> Int {
        answers.filter { $0.choice == option }.count
    }
}

// MARK: - Palette

enum BrainPalette {
    static let tiles: [Color] = [
        Color(hex: "FF3D7F"),   // A
        Color(hex: "3D8BFF"),   // B
        Color(hex: "FFB020"),   // C
        Color(hex: "22C77A"),   // D
    ]
    static let letters: [String] = ["A", "B", "C", "D"]

    static func tile(_ index: Int) -> Color {
        tiles[((index % tiles.count) + tiles.count) % tiles.count]
    }

    static func letter(_ index: Int) -> String {
        index >= 0 && index < letters.count ? letters[index] : "\(index + 1)"
    }

    static func skillColor(_ skill: String) -> Color {
        switch skill {
        case "Patterns":     return Color(hex: "A855F7")
        case "Number Speed": return Color(hex: "F59E0B")
        case "Memory":       return Color(hex: "EC4899")
        case "Logic":        return Color(hex: "22D3EE")
        case "Word Smarts":  return Color(hex: "34D399")
        case "Spatial":      return Color(hex: "60A5FA")
        default:             return Color(hex: "818CF8")
        }
    }

    static func skillSymbol(_ skill: String) -> String {
        switch skill {
        case "Patterns":     return "waveform.path.ecg"
        case "Number Speed": return "bolt.fill"
        case "Memory":       return "brain.head.profile"
        case "Logic":        return "lightbulb.fill"
        case "Word Smarts":  return "textformat"
        case "Spatial":      return "cube.fill"
        default:             return "brain"
        }
    }
}

// MARK: - Board

struct TVBrainBattleBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: BrainBattleBoardState()) { $0.update(from: $1) }

    @State private var cardFlip: Double = 0
    @State private var burstKey: Int = 0

    private var phase: String { vm.state.base.phase }
    private var isSummary: Bool { phase == "summary" || phase == "final" }
    private var isMemorize: Bool { phase == "memorize" }
    private var isReveal: Bool { phase == "reveal" && vm.state.hasReveal }
    private var accent: Color { BrainPalette.skillColor(vm.state.skill) }

    var body: some View {
        ZStack {
            BrainNebulaBackground(accent: accent)
            if isSummary {
                BrainSummaryView(results: vm.state.results)
                    .transition(.opacity)
            } else {
                playfield
                    .transition(.opacity)
            }
            if burstKey > 0 {
                BrainConfettiBurst()
                    .id(burstKey)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: isSummary)
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: vm.state.puzzleID) { _, _ in
            flipIn()
        }
        .onChange(of: vm.state.base.phase) { _, newPhase in
            phaseChanged(newPhase)
        }
        .onChange(of: vm.state.lockedCount) { oldValue, newValue in
            if newValue > oldValue {
                SoundPlayer.shared.playClick(volume: 0.45)
            }
        }
    }

    // MARK: Layout

    private var playfield: some View {
        VStack(spacing: 26) {
            BrainHeader(round: vm.state.base.round,
                        totalRounds: vm.state.base.totalRounds,
                        skill: vm.state.skill,
                        level: vm.state.level,
                        accent: accent)
            HStack(alignment: .top, spacing: 40) {
                mainColumn
                    .frame(maxWidth: .infinity)
                sidePanel
                    .frame(width: 460)
            }
            .padding(.horizontal, 70)
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
    }

    private var mainColumn: some View {
        VStack(spacing: 26) {
            puzzleCard
            if !isMemorize && !vm.state.options.isEmpty {
                answerGrid
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isMemorize)
    }

    private var sidePanel: some View {
        VStack(spacing: 26) {
            BrainTimerRing(secondsLeft: vm.state.base.secondsLeft,
                           total: vm.state.phaseSeconds,
                           label: timerLabel,
                           tint: accent)
            if phase == "answer" {
                BrainLockedPanel(players: vm.state.base.players,
                                 locked: vm.state.base.submitted,
                                 lockedCount: vm.state.lockedCount,
                                 activeCount: vm.state.activeCount)
                    .transition(.opacity)
            }
            BrainLeaderboard(players: vm.state.base.players,
                             correctIDs: vm.state.correctIDs,
                             fastestID: vm.state.fastestID,
                             showMarks: isReveal)
        }
        .animation(.easeInOut(duration: 0.4), value: phase)
    }

    private var timerLabel: String {
        switch phase {
        case "memorize": return "MEMORIZE"
        case "reveal":   return "NEXT"
        default:         return "SECONDS"
        }
    }

    // MARK: Puzzle card

    private var puzzleCard: some View {
        ZStack {
            if isMemorize {
                BrainMemoryDigitsView(digits: vm.state.memoryDigits,
                                      backwards: vm.state.memoryBackwards,
                                      accent: accent)
                    .id("mem-\(vm.state.puzzleID)")
                    .transition(AnyTransition.brainDissolve)
            } else {
                promptContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.7), value: isMemorize)
        .padding(.horizontal, 44)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 250)
        .background(BrainGlassCard(accent: accent))
        .rotation3DEffect(.degrees(cardFlip), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        .opacity(abs(cardFlip) > 85 ? 0 : 1)
    }

    private var promptContent: some View {
        VStack(spacing: 20) {
            Text(vm.state.prompt)
                .font(.system(size: promptSize, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            if vm.state.kind == "rotation" && !vm.state.target.isEmpty {
                BrainShapeView(cells: vm.state.target, color: Color(hex: "E2E8F0"), depth: 4)
                    .frame(width: 280, height: 130)
            }
            if isReveal {
                BrainRevealBanner(answer: revealAnswerText,
                                  explain: vm.state.explain,
                                  nobody: vm.state.correctIDs.isEmpty,
                                  fastestName: vm.state.fastestName,
                                  fastestSeconds: vm.state.fastestSeconds,
                                  color: revealColor)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isReveal)
    }

    private var promptSize: CGFloat {
        let n: Int = vm.state.prompt.count
        if n < 60 { return 50 }
        if n < 120 { return 40 }
        return 32
    }

    private var revealIndex: Int? {
        vm.state.options.firstIndex(of: vm.state.answer)
    }

    private var revealColor: Color {
        guard let i = revealIndex else { return Color.white }
        return BrainPalette.tile(i)
    }

    private var revealAnswerText: String {
        if vm.state.kind == "rotation" { return "Shape \(vm.state.answer)" }
        return vm.state.answer
    }

    // MARK: Answer tiles

    private var answerGrid: some View {
        let options: [String] = vm.state.options
        let rows: Int = (options.count + 1) / 2
        return VStack(spacing: 20) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 20) {
                    tileOrSpacer(row * 2, options: options)
                    tileOrSpacer(row * 2 + 1, options: options)
                }
            }
        }
    }

    @ViewBuilder
    private func tileOrSpacer(_ index: Int, options: [String]) -> some View {
        if index < options.count {
            BrainAnswerTile(letter: BrainPalette.letter(index),
                            text: options[index],
                            color: BrainPalette.tile(index),
                            shape: shapeFor(index),
                            mode: tileMode(options[index]),
                            pickCount: vm.state.pickCount(for: options[index]),
                            showPicks: isReveal)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    private func shapeFor(_ index: Int) -> [BrainCell] {
        guard vm.state.kind == "rotation", index < vm.state.choiceShapes.count else { return [] }
        return vm.state.choiceShapes[index]
    }

    private func tileMode(_ option: String) -> BrainTileMode {
        guard isReveal else { return .live }
        return option == vm.state.answer ? .correct : .wrong
    }

    // MARK: Motion and sound

    private func flipIn() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { cardFlip = -90 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(.spring(response: 0.8, dampingFraction: 0.72)) { cardFlip = 0 }
        }
    }

    private func phaseChanged(_ newPhase: String) {
        if newPhase == "reveal" {
            if !vm.state.correctIDs.isEmpty {
                burstKey += 1
            }
            SoundPlayer.shared.play(.ladderClimb, volume: 0.7)
        } else if newPhase == "summary" {
            burstKey += 1
        }
    }
}

// MARK: - Header

private struct BrainHeader: View {
    let round: Int
    let totalRounds: Int
    let skill: String
    let level: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 26) {
            HStack(spacing: 14) {
                Image(systemName: "brain")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "F0ABFC"), Color(hex: "67E8F9")],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("BRAIN BATTLE")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .tracking(5)
                    .foregroundColor(.white)
            }
            if !skill.isEmpty {
                skillChip
            }
            levelPips
            Spacer()
            roundBadge
        }
        .padding(.horizontal, 70)
    }

    private var skillChip: some View {
        HStack(spacing: 10) {
            Image(systemName: BrainPalette.skillSymbol(skill))
            Text(skill.uppercased()).tracking(2)
        }
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundColor(.white)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Capsule().fill(accent.opacity(0.35)))
        .overlay(Capsule().stroke(accent.opacity(0.9), lineWidth: 2))
        .shadow(color: accent.opacity(0.6), radius: 12)
        .animation(.easeInOut(duration: 0.5), value: skill)
    }

    private var levelPips: some View {
        HStack(spacing: 5) {
            Text("LV")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
            ForEach(1..<11, id: \.self) { i in
                Capsule()
                    .fill(i <= level ? accent : Color.white.opacity(0.12))
                    .frame(width: 10, height: i <= level ? 26 : 18)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: level)
    }

    private var roundBadge: some View {
        HStack(spacing: 10) {
            Text("ROUND")
                .font(.system(size: 20, weight: .bold)).tracking(3)
                .foregroundColor(.white.opacity(0.5))
            Text("\(round) / \(totalRounds)")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(.default, value: round)
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - Background

/// Slow-drifting nebula: a deep-space gradient with three soft colour
/// clouds and a twinkling starfield, driven by a 30 fps TimelineView.
struct BrainNebulaBackground: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            BrainNebulaLayer(time: timeline.date.timeIntervalSinceReferenceDate, accent: accent)
        }
        .ignoresSafeArea()
    }
}

private struct BrainNebulaLayer: View {
    let time: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: "05010F"), Color(hex: "0E0630"), Color(hex: "021623")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                cloud(color: Color(hex: "7C3AED"), size: geo.size,
                      fx: 0.22 + 0.08 * sin(time * 0.11), fy: 0.30 + 0.07 * cos(time * 0.09), scale: 0.55)
                cloud(color: Color(hex: "0891B2"), size: geo.size,
                      fx: 0.78 + 0.07 * cos(time * 0.08), fy: 0.65 + 0.08 * sin(time * 0.12), scale: 0.6)
                cloud(color: accent, size: geo.size,
                      fx: 0.5 + 0.18 * sin(time * 0.05), fy: 0.85 + 0.05 * cos(time * 0.07), scale: 0.45)
                BrainStarfield(time: time)
            }
        }
    }

    private func cloud(color: Color, size: CGSize, fx: Double, fy: Double, scale: Double) -> some View {
        let radius: CGFloat = size.width * CGFloat(scale)
        return RadialGradient(colors: [color.opacity(0.38), color.opacity(0.0)],
                              center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: size.width * CGFloat(fx), y: size.height * CGFloat(fy))
            .blendMode(.screen)
    }
}

private struct BrainStarfield: View {
    let time: Double
    private static let count: Int = 110

    var body: some View {
        Canvas { context, size in
            for i in 0..<BrainStarfield.count {
                let seed: Double = Double(i)
                let fx: Double = BrainStarfield.fract(sin(seed * 12.9898) * 43758.5453)
                let fy: Double = BrainStarfield.fract(sin(seed * 78.233) * 12543.1234)
                let speed: Double = 0.4 + BrainStarfield.fract(seed * 0.37) * 1.2
                let twinkle: Double = 0.25 + 0.6 * (0.5 + 0.5 * sin(time * speed + seed))
                let r: CGFloat = 1.0 + CGFloat(BrainStarfield.fract(seed * 0.61)) * 2.2
                let x: CGFloat = CGFloat(fx) * size.width
                let y: CGFloat = CGFloat(fy) * size.height
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(twinkle)))
            }
        }
        .allowsHitTesting(false)
    }

    private static func fract(_ v: Double) -> Double {
        let a: Double = abs(v)
        return a - floor(a)
    }
}

// MARK: - Glass card

private struct BrainGlassCard: View {
    let accent: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        return ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.stroke(LinearGradient(colors: [accent.opacity(0.9), Color.white.opacity(0.15), accent.opacity(0.5)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing),
                         lineWidth: 2.5)
        }
        .shadow(color: accent.opacity(0.35), radius: 30, y: 12)
    }
}

private extension AnyTransition {
    /// Memory digits appear with a fade and leave by dissolving.
    static var brainDissolve: AnyTransition {
        AnyTransition.asymmetric(
            insertion: AnyTransition.opacity,
            removal: AnyTransition.modifier(active: BrainDissolve(blur: 30, opacity: 0, scale: 1.35),
                                            identity: BrainDissolve(blur: 0, opacity: 1, scale: 1)))
    }
}

/// Removal effect for the memory digits: blur out, fade, and grow.
private struct BrainDissolve: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

// MARK: - Memory digits

private struct BrainMemoryDigitsView: View {
    let digits: [Int]
    let backwards: Bool
    let accent: Color
    @State private var shown: Int = 0

    var body: some View {
        VStack(spacing: 28) {
            Text("MEMORIZE")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .tracking(10)
                .foregroundColor(accent)
            HStack(spacing: 14) {
                ForEach(Array(digits.enumerated()), id: \.offset) { pair in
                    BrainDigitBubble(digit: pair.element, visible: pair.offset < shown, accent: accent)
                }
            }
            Text(backwards ? "You will need them BACKWARDS" : "Remember them in order")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .onAppear { popIn() }
    }

    private func popIn() {
        shown = 0
        let total: Int = digits.count
        guard total > 0 else { return }
        for i in 0..<total {
            let delay: Double = 0.2 + Double(i) * 0.24
            let nanos: UInt64 = UInt64(delay * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanos)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.55)) { shown = i + 1 }
            }
        }
    }
}

private struct BrainDigitBubble: View {
    let digit: Int
    let visible: Bool
    let accent: Color

    var body: some View {
        Text("\(digit)")
            .font(.system(size: 88, weight: .black, design: .rounded))
            .foregroundColor(.white)
            .frame(width: 104, height: 132)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.35)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 2))
            .shadow(color: accent.opacity(0.7), radius: 18, y: 6)
            .scaleEffect(visible ? 1.0 : 0.2)
            .opacity(visible ? 1.0 : 0.0)
            .rotation3DEffect(.degrees(visible ? 0 : 70), axis: (x: 1, y: 0, z: 0))
    }
}

// MARK: - Answer tile

enum BrainTileMode {
    case live
    case correct
    case wrong
}

private struct BrainAnswerTile: View {
    let letter: String
    let text: String
    let color: Color
    let shape: [BrainCell]
    let mode: BrainTileMode
    let pickCount: Int
    let showPicks: Bool
    @State private var pulse: Bool = false

    private var tall: Bool { !shape.isEmpty }
    private var corner: RoundedRectangle { RoundedRectangle(cornerRadius: 28, style: .continuous) }

    var body: some View {
        HStack(spacing: 22) {
            letterBadge
            content
            Spacer(minLength: 0)
            if showPicks {
                picksBadge
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: tall ? 160 : 112)
        .background(tileBackground)
        .overlay(corner.stroke(Color.white.opacity(mode == .correct ? 0.95 : 0.25),
                               lineWidth: mode == .correct ? 5 : 1.5))
        .overlay(alignment: .topTrailing) {
            if mode == .correct {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6)
                    .offset(x: 14, y: -14)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: color.opacity(mode == .correct ? (pulse ? 0.95 : 0.6) : 0.25),
                radius: mode == .correct ? (pulse ? 44 : 24) : 10)
        .scaleEffect(mode == .correct ? 1.04 : (mode == .wrong ? 0.96 : 1.0))
        .opacity(mode == .wrong ? 0.35 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: mode)
        .onChange(of: mode) { _, newMode in
            if newMode == .correct {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            } else {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { pulse = false }
            }
        }
    }

    private var letterBadge: some View {
        Text(letter)
            .font(.system(size: 38, weight: .black, design: .rounded))
            .foregroundColor(color)
            .frame(width: 68, height: 68)
            .background(Circle().fill(Color.white))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }

    @ViewBuilder
    private var content: some View {
        if tall {
            BrainShapeView(cells: shape, color: Color.white, depth: 3)
                .frame(width: 240, height: 128)
        } else {
            Text(text)
                .font(.system(size: text.count > 16 ? 32 : 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
    }

    private var picksBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
            Text("\(pickCount)")
        }
        .font(.system(size: 24, weight: .bold, design: .rounded))
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.3)))
    }

    private var tileBackground: some View {
        ZStack {
            corner.fill(LinearGradient(colors: [color, color.opacity(0.62)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            corner.fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.0)],
                                       startPoint: .top, endPoint: .center))
        }
    }
}

// MARK: - Reveal banner

private struct BrainRevealBanner: View {
    let answer: String
    let explain: String
    let nobody: Bool
    let fastestName: String?
    let fastestSeconds: Double?
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Text("ANSWER")
                    .font(.system(size: 22, weight: .heavy)).tracking(4)
                    .foregroundColor(.white.opacity(0.6))
                Text(answer)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 6)
                    .background(Capsule().fill(color))
                    .shadow(color: color.opacity(0.8), radius: 16)
                if let name = fastestName {
                    fastestBadge(name)
                } else if nobody {
                    Text("Nobody got it!")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "FCA5A5"))
                }
            }
            if !explain.isEmpty {
                Text(explain)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private func fastestBadge(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
            Text("FASTEST")
                .tracking(2)
            Text(name)
                .lineLimit(1)
            if let s = fastestSeconds {
                Text(String(format: "%.1fs", s))
                    .foregroundColor(.black.opacity(0.6))
            }
        }
        .font(.system(size: 24, weight: .heavy, design: .rounded))
        .foregroundColor(.black)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Capsule().fill(LinearGradient(colors: [Color(hex: "FDE047"), Color(hex: "F59E0B")],
                                                  startPoint: .top, endPoint: .bottom)))
        .shadow(color: Color(hex: "FDE047").opacity(0.7), radius: 14)
    }
}

// MARK: - Timer ring

private struct BrainTimerRing: View {
    let secondsLeft: Int
    let total: Int
    let label: String
    let tint: Color

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(secondsLeft) / Double(total)))
    }

    private var urgent: Bool { label == "SECONDS" && secondsLeft > 0 && secondsLeft <= 5 }
    private var ringColor: Color { urgent ? Color(hex: "F43F5E") : tint }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 18)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(gradient: Gradient(colors: [ringColor.opacity(0.5), ringColor, Color.white]),
                                        center: .center),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.75), radius: 16)
                .animation(.linear(duration: 1.0), value: secondsLeft)
            VStack(spacing: 0) {
                Text("\(secondsLeft)")
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .foregroundColor(urgent ? ringColor : .white)
                    .contentTransition(.numericText())
                    .animation(.default, value: secondsLeft)
                Text(label)
                    .font(.system(size: 18, weight: .bold)).tracking(3)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .frame(width: 210, height: 210)
        .scaleEffect(urgent && secondsLeft % 2 == 0 ? 1.07 : 1.0)
        .animation(.easeInOut(duration: 0.35), value: secondsLeft)
    }
}

// MARK: - Locked-in panel

private struct BrainLockedPanel: View {
    let players: [BoardPlayer]
    let locked: Set<String>
    let lockedCount: Int
    let activeCount: Int

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("\(lockedCount) / \(max(activeCount, lockedCount)) LOCKED IN")
                    .tracking(2)
            }
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(.white.opacity(0.85))
            HStack(spacing: 8) {
                ForEach(players) { p in
                    Circle()
                        .fill(locked.contains(p.id) ? Color(hex: "22C77A") : Color.white.opacity(0.15))
                        .frame(width: 18, height: 18)
                        .scaleEffect(locked.contains(p.id) ? 1.2 : 1.0)
                        .shadow(color: locked.contains(p.id) ? Color(hex: "22C77A") : .clear, radius: 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: locked.contains(p.id))
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Leaderboard

private struct BrainLeaderboard: View {
    let players: [BoardPlayer]
    let correctIDs: Set<String>
    let fastestID: String?
    let showMarks: Bool

    private var sorted: [BoardPlayer] {
        players.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.name < b.name
        }
    }

    private var maxScore: Int { max(1, players.map { $0.score }.max() ?? 1) }
    private var orderKey: String { sorted.map { $0.id }.joined(separator: "|") }
    private var compact: Bool { players.count > 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            Text("LEADERBOARD")
                .font(.system(size: 20, weight: .heavy)).tracking(4)
                .foregroundColor(.white.opacity(0.5))
            ForEach(Array(sorted.enumerated()), id: \.element.id) { pair in
                BrainLeaderRow(rank: pair.offset + 1,
                               player: pair.element,
                               fraction: Double(pair.element.score) / Double(maxScore),
                               correct: showMarks && correctIDs.contains(pair.element.id),
                               fastest: showMarks && fastestID == pair.element.id,
                               compact: compact)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.05)))
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: orderKey)
    }
}

private struct BrainLeaderRow: View {
    let rank: Int
    let player: BoardPlayer
    let fraction: Double
    let correct: Bool
    let fastest: Bool
    let compact: Bool

    private var barColors: [Color] {
        rank == 1 ? [Color(hex: "FDE047"), Color(hex: "F59E0B")] : [Color(hex: "67E8F9"), Color(hex: "818CF8")]
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: compact ? 20 : 24, weight: .heavy, design: .rounded))
                .foregroundColor(rank == 1 ? Color(hex: "FDE047") : .white.opacity(0.55))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(player.name)
                        .font(.system(size: compact ? 20 : 24, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if fastest {
                        Image(systemName: "bolt.fill").foregroundColor(Color(hex: "FDE047"))
                            .transition(.scale)
                    }
                    if correct {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: "22C77A"))
                            .transition(.scale)
                    }
                    Spacer(minLength: 4)
                    Text("\(player.score)")
                        .font(.system(size: compact ? 20 : 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
                .font(.system(size: compact ? 18 : 22))
                bar
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: player.score)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: correct)
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: barColors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * CGFloat(min(1.0, max(0.0, fraction)))))
            }
        }
        .frame(height: compact ? 6 : 9)
    }
}

// MARK: - Confetti

/// A one-shot burst from the middle of the screen. Pure shapes, no emoji.
private struct BrainConfettiBurst: View {
    struct Piece {
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let colorIndex: Int
        let spin: Double
        let delay: Double
    }

    private static let palette: [Color] = [
        Color(hex: "FF3D7F"), Color(hex: "3D8BFF"), Color(hex: "FFB020"),
        Color(hex: "22C77A"), Color(hex: "F0ABFC"), Color(hex: "67E8F9"), Color.white,
    ]

    private let pieces: [Piece]
    @State private var fired: Bool = false

    init(count: Int = 80) {
        var list: [Piece] = []
        for i in 0..<count {
            list.append(Piece(angle: Double.random(in: 0..<(2 * Double.pi)),
                              distance: CGFloat.random(in: 240...900),
                              size: CGFloat.random(in: 10...22),
                              colorIndex: i % BrainConfettiBurst.palette.count,
                              spin: Double.random(in: -720...720),
                              delay: Double.random(in: 0...0.18)))
        }
        pieces = list
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<pieces.count, id: \.self) { i in
                    piece(pieces[i], in: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { fired = true }
    }

    private func piece(_ p: Piece, in size: CGSize) -> some View {
        let cx: CGFloat = size.width / 2
        let cy: CGFloat = size.height * 0.42
        let dx: CGFloat = CGFloat(cos(p.angle)) * p.distance
        let dy: CGFloat = CGFloat(sin(p.angle)) * p.distance * 0.7 + 220
        return RoundedRectangle(cornerRadius: 3)
            .fill(BrainConfettiBurst.palette[p.colorIndex])
            .frame(width: p.size, height: p.size * 0.55)
            .rotationEffect(.degrees(fired ? p.spin : 0))
            .position(x: cx + (fired ? dx : 0), y: cy + (fired ? dy : 0))
            .animation(.easeOut(duration: 1.5).delay(p.delay), value: fired)
            .opacity(fired ? 0 : 1)
            .animation(.easeIn(duration: 2.2).delay(p.delay), value: fired)
    }
}

// MARK: - Final summary

private struct BrainSummaryView: View {
    let results: [BrainBattleResultRow]
    @State private var appeared: Bool = false

    private var columns: [GridItem] {
        let n: Int = max(1, min(4, results.count))
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: n)
    }

    private var headline: String {
        guard let top = results.first else { return "Tallying brains..." }
        return "\(top.name) wins!"
    }

    var body: some View {
        VStack(spacing: 34) {
            VStack(spacing: 10) {
                Text("BRAIN BATTLE RESULTS")
                    .font(.system(size: 26, weight: .heavy)).tracking(10)
                    .foregroundColor(.white.opacity(0.6))
                Text(headline)
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "FDE047"), Color(hex: "F0ABFC")],
                                                    startPoint: .leading, endPoint: .trailing))
                    .shadow(color: Color(hex: "F0ABFC").opacity(0.5), radius: 20)
            }
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(results.enumerated()), id: \.element.id) { pair in
                    BrainTitleCard(row: pair.element, compact: results.count > 8)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 70)
                        .scaleEffect(appeared ? 1 : 0.85)
                        .animation(.spring(response: 0.65, dampingFraction: 0.72)
                            .delay(0.12 * Double(pair.offset)), value: appeared)
                }
            }
            .padding(.horizontal, 80)
            Spacer(minLength: 0)
        }
        .padding(.top, 60)
        .onAppear {
            appeared = true
            SoundPlayer.shared.play(.winFanfare, volume: 0.8)
        }
    }
}

private struct BrainTitleCard: View {
    let row: BrainBattleResultRow
    let compact: Bool

    private var accent: Color { BrainPalette.skillColor(row.bestSkill) }

    private var medal: Color {
        switch row.rank {
        case 1: return Color(hex: "FDE047")
        case 2: return Color(hex: "E2E8F0")
        case 3: return Color(hex: "F59E0B")
        default: return Color.white.opacity(0.3)
        }
    }

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            HStack(spacing: 12) {
                Text("\(row.rank)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(medal))
                Text(row.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(row.score)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 10) {
                Image(systemName: BrainPalette.skillSymbol(row.bestSkill))
                Text(row.brainTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.system(size: compact ? 26 : 32, weight: .black, design: .rounded))
            .foregroundColor(accent)
            .shadow(color: accent.opacity(0.6), radius: 10)
            HStack(spacing: 10) {
                Text("BRAIN SCORE")
                    .font(.system(size: 18, weight: .bold)).tracking(2)
                    .foregroundColor(.white.opacity(0.5))
                Text("\(row.brainScore)")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                if row.personalBest {
                    Text("NEW BEST")
                        .font(.system(size: 16, weight: .heavy)).tracking(2)
                        .foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "22C77A")))
                }
            }
        }
        .padding(compact ? 16 : 22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.28), Color.white.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(row.rank == 1 ? medal : accent.opacity(0.5), lineWidth: row.rank == 1 ? 3 : 1.5))
        .shadow(color: (row.rank == 1 ? medal : accent).opacity(0.35), radius: 18)
    }
}
