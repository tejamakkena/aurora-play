import SwiftUI

/// Trivia as a TV game show.
///
/// Server contract: games/native_hub/engines/trivia_show.py `public_state`.
/// `phase` walks intro -> category_vote -> category_reveal -> (power_pick ->
/// power_reveal) -> question -> reveal -> ... -> standings (between rounds)
/// -> finale_intro -> finale_question / finale_reveal -> summary. Every
/// phase carries `secondsLeft` and `phaseSeconds`. `correctIndex` and
/// `lastResults` are only present during a reveal, and scores only move at
/// the reveal, so nothing on this screen gives an answer away early.
///
/// The voice host speaks `questionText` + `choices` when a new `questionID`
/// lands, and grades the mic phone's spoken answer once `correctIndex`
/// arrives with the reveal.

// MARK: - State

struct TShowPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    let isHost: Bool
    let isBot: Bool
    let rank: Int
    let prevRank: Int
    let rung: Int
}

struct TShowDoorInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    let votes: Int
}

struct TShowPowerEvent: Identifiable, Equatable {
    let id: Int
    let power: String
    let fromID: String
    let fromName: String
    let toID: String
    let toName: String
    let blocked: Bool
}

struct TShowResultRow: Equatable {
    let playerID: String
    let choice: Int?
    let correct: Bool
    let points: Int
}

struct TShowState {
    var phase: String = ""
    var secondsLeft: Int = 0
    var phaseSeconds: Int = 0
    var round: Int = 0
    var totalRounds: Int = 0
    var questionNumber: Int = 0
    var totalQuestions: Int = 0
    var isCustom: Bool = false
    var quizName: String = ""
    var questionID: String = ""
    var questionText: String = ""
    var choices: [String] = []
    var category: String = ""
    var showChoices: Bool = false
    var answeredIDs: Set<String> = []
    var doors: [TShowDoorInfo] = []
    var votedIDs: Set<String> = []
    var chosenCategory: String = ""
    var chosenIndex: Int = -1
    var pickedPowerIDs: Set<String> = []
    var powerEvents: [TShowPowerEvent] = []
    var towerHeight: Int = 7
    var finaleNumber: Int = 0
    var finaleTotal: Int = 0
    var finaleMoves: [String: Int] = [:]
    var winnerID: String? = nil
    var players: [TShowPlayer] = []
    var correctIndex: Int? = nil
    var lastResults: [TShowResultRow] = []

    mutating func update(from d: [String: AnyCodable]) {
        phase = d["phase"]?.value as? String ?? phase
        secondsLeft = TShowState.int(d["secondsLeft"]?.value) ?? secondsLeft
        phaseSeconds = TShowState.int(d["phaseSeconds"]?.value) ?? phaseSeconds
        round = TShowState.int(d["round"]?.value) ?? round
        totalRounds = TShowState.int(d["totalRounds"]?.value) ?? totalRounds
        questionNumber = TShowState.int(d["questionNumber"]?.value) ?? questionNumber
        totalQuestions = TShowState.int(d["totalQuestions"]?.value) ?? totalQuestions
        isCustom = d["custom"]?.value as? Bool ?? false
        quizName = d["quizName"]?.value as? String ?? ""
        questionID = d["questionID"]?.value as? String ?? ""
        questionText = d["questionText"]?.value as? String ?? ""
        choices = TShowState.strings(d["choices"]?.value)
        category = d["category"]?.value as? String ?? ""
        showChoices = d["showChoices"]?.value as? Bool ?? false
        answeredIDs = Set(TShowState.strings(d["answeredPlayerIDs"]?.value))
        votedIDs = Set(TShowState.strings(d["votedPlayerIDs"]?.value))
        pickedPowerIDs = Set(TShowState.strings(d["pickedPowerPlayerIDs"]?.value))
        chosenCategory = d["chosenCategory"]?.value as? String ?? ""
        chosenIndex = TShowState.int(d["chosenIndex"]?.value) ?? -1
        towerHeight = max(1, TShowState.int(d["towerHeight"]?.value) ?? 7)
        finaleNumber = TShowState.int(d["finaleNumber"]?.value) ?? 0
        finaleTotal = TShowState.int(d["finaleTotal"]?.value) ?? 0
        winnerID = d["winnerID"]?.value as? String
        correctIndex = TShowState.int(d["correctIndex"]?.value)
        doors = TShowState.parseDoors(d["categories"]?.value)
        powerEvents = TShowState.parseEvents(d["powerEvents"]?.value)
        players = TShowState.parsePlayers(d["players"]?.value)
        lastResults = TShowState.parseResults(d["lastResults"]?.value)
        var moves: [String: Int] = [:]
        if let raw = d["finaleMoves"]?.value as? [String: Any] {
            for (key, value) in raw {
                if let step = TShowState.int(value) { moves[key] = step }
            }
        }
        finaleMoves = moves
    }

    static func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }

    static func strings(_ value: Any?) -> [String] {
        let raw: [Any] = value as? [Any] ?? []
        return raw.compactMap { $0 as? String }
    }

    static func parseDoors(_ value: Any?) -> [TShowDoorInfo] {
        let raw: [Any] = value as? [Any] ?? []
        var out: [TShowDoorInfo] = []
        for (index, item) in raw.enumerated() {
            guard let d = item as? [String: Any] else { continue }
            let name: String = d["name"] as? String ?? "Mystery"
            let votes: Int = int(d["votes"]) ?? 0
            out.append(TShowDoorInfo(id: index, name: name, votes: votes))
        }
        return out
    }

    static func parseEvents(_ value: Any?) -> [TShowPowerEvent] {
        let raw: [Any] = value as? [Any] ?? []
        var out: [TShowPowerEvent] = []
        for (index, item) in raw.enumerated() {
            guard let d = item as? [String: Any] else { continue }
            out.append(TShowPowerEvent(id: index,
                                       power: d["power"] as? String ?? "",
                                       fromID: d["fromID"] as? String ?? "",
                                       fromName: d["fromName"] as? String ?? "Someone",
                                       toID: d["toID"] as? String ?? "",
                                       toName: d["toName"] as? String ?? "someone",
                                       blocked: d["blocked"] as? Bool ?? false))
        }
        return out
    }

    static func parsePlayers(_ value: Any?) -> [TShowPlayer] {
        let raw: [Any] = value as? [Any] ?? []
        return raw.compactMap { item -> TShowPlayer? in
            guard let d = item as? [String: Any], let id = d["id"] as? String else { return nil }
            let rank: Int = int(d["rank"]) ?? 0
            return TShowPlayer(id: id,
                               name: d["name"] as? String ?? "Player",
                               score: int(d["score"]) ?? 0,
                               isHost: d["isHost"] as? Bool ?? false,
                               isBot: d["isBot"] as? Bool ?? false,
                               rank: rank,
                               prevRank: int(d["prevRank"]) ?? rank,
                               rung: int(d["rung"]) ?? 0)
        }
    }

    static func parseResults(_ value: Any?) -> [TShowResultRow] {
        let raw: [Any] = value as? [Any] ?? []
        return raw.compactMap { item -> TShowResultRow? in
            guard let d = item as? [String: Any], let pid = d["playerID"] as? String else { return nil }
            return TShowResultRow(playerID: pid,
                                  choice: int(d["choice"]),
                                  correct: d["correct"] as? Bool ?? false,
                                  points: int(d["points"]) ?? 0)
        }
    }

    // MARK: Derived

    var isReveal: Bool { phase == "reveal" || phase == "finale_reveal" }
    var isFinale: Bool { phase.hasPrefix("finale") }

    /// Who has locked something in for the current decision.
    var lockedIDs: Set<String> {
        switch phase {
        case "category_vote": return votedIDs
        case "power_pick": return pickedPowerIDs
        case "question", "finale_question": return answeredIDs
        default: return []
        }
    }

    /// Landed (not blocked) powers per target, for the pod badges.
    var hitPowers: [String: [String]] {
        var out: [String: [String]] = [:]
        for event in powerEvents where !event.blocked {
            out[event.toID, default: []].append(event.power)
        }
        return out
    }

    var resultsByPlayer: [String: TShowResultRow] {
        var out: [String: TShowResultRow] = [:]
        for row in lastResults { out[row.playerID] = row }
        return out
    }

    func player(_ id: String?) -> TShowPlayer? {
        guard let id else { return nil }
        return players.first { $0.id == id }
    }
}

// MARK: - Palette

enum TShowPalette {
    /// Answer tiles A-D and the three doors: this game's own identity, not
    /// the shared palette. `QuizPadStyle` on the phone carries the same four
    /// hexes so a tile is the same colour in your hand and on the wall.
    static let tileColors: [Color] = [
        Color(hex: "FF3D7F"), Color(hex: "3D8BFF"), Color(hex: "FFB020"), Color(hex: "22C77A"),
    ]
    static let tileShapes: [String] = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    static let letters: [String] = ["A", "B", "C", "D"]
    static let doorColors: [Color] = [Color(hex: "FF4D8D"), Color(hex: "3DA5FF"), Color(hex: "FFB020")]
    static let gold = TVTheme.gold

    // The studio set: a violet stage under warm spotlights. Also identity,
    // and also named here rather than repeated as hexes down the file.
    static let stageInk = Color(hex: "1A0640")
    static let stageDeep = Color(hex: "3B1585")
    static let stageShadow = Color(hex: "120328")
    static let stageBack = Color(hex: "3B0A63")
    static let stageFloor = Color(hex: "1E0A4F")
    static let stageNight = Color(hex: "0C0322")
    static let spotlight = Color(hex: "FFF3B0")
    static let spotlightCore = Color(hex: "FFF6C8")
    static let goldWarm = Color(hex: "FF9F1C")
    static let goldDeep = Color(hex: "B45309")
    /// The host's hot pink, and the slightly softer magenta of the doors.
    static let hotPink = Color(hex: "FF3D7F")
    static let magenta = Color(hex: "FF4D8D")

    static func tile(_ index: Int) -> Color {
        tileColors[((index % tileColors.count) + tileColors.count) % tileColors.count]
    }

    static func shape(_ index: Int) -> String {
        tileShapes[((index % tileShapes.count) + tileShapes.count) % tileShapes.count]
    }

    static func letter(_ index: Int) -> String {
        index >= 0 && index < letters.count ? letters[index] : "\(index + 1)"
    }

    static func powerSymbol(_ power: String) -> String {
        switch power {
        case "freeze": return "snowflake"
        case "scramble": return "shuffle"
        case "fog": return "cloud.fog.fill"
        case "shield": return "shield.fill"
        default: return "bolt.fill"
        }
    }

    /// The shared tokens, matching `QuizPadStyle.powerColor` on the phone.
    static func powerColor(_ power: String) -> Color {
        switch power {
        case "freeze": return TVTheme.cyan
        case "scramble": return TVTheme.pink
        case "fog": return TVTheme.purple
        case "shield": return TVTheme.yellow
        default: return TVTheme.cyan
        }
    }

    static func powerVerb(_ power: String) -> String {
        switch power {
        case "freeze": return "froze"
        case "scramble": return "scrambled"
        case "fog": return "fogged"
        default: return "zapped"
        }
    }

    static func eventLine(_ event: TShowPowerEvent) -> String {
        if event.blocked {
            return "\(event.toName)'s shield blocked \(event.fromName)!"
        }
        return "\(event.fromName) \(powerVerb(event.power)) \(event.toName)!"
    }
}

// MARK: - Voice cue

/// Holds a spoken answer that arrived before the reveal: the TV only learns
/// the correct answer at the reveal, so grading waits until then.
@MainActor
final class TShowVoiceCue: ObservableObject {
    var questionID: String = ""
    var transcript: String? = nil
}

// MARK: - Board

struct TVTriviaBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: TShowState()) { $0.update(from: $1) }
    /// Voice quizmaster: the TV speaks, one phone listens (spec section 13).
    @StateObject private var voiceHost = TVVoiceHost()
    @StateObject private var voiceCue = TShowVoiceCue()
    @State private var confettiKey: Int = 0

    private var state: TShowState { vm.state }
    private var phase: String { vm.state.phase }

    var body: some View {
        ZStack {
            TShowStageBackground(accent: stageAccent)
            VStack(spacing: 0) {
                TShowTopBar(state: state)
                phaseContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsPods {
                    TShowPodRow(state: state)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            if confettiKey > 0 {
                ShellConfetti(particleCount: phase == "summary" ? 160 : 110,
                              duration: 4.5,
                              origin: UnitPoint(x: 0.5, y: 0.3),
                              seed: confettiKey)
                    .id(confettiKey)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.45), value: phase)
        .overlay(alignment: .topTrailing) {
            TVVoiceOverlay(host: voiceHost)
        }
        .onAppear {
            vm.bind(roomCode: room.code)
            voiceHost.attach(roomCode: room.code)
            voiceHost.onFinalTranscript = { [weak vm, weak voiceCue, weak voiceHost] transcript in
                guard let vm, let voiceCue, let voiceHost else { return }
                let current: TShowState = vm.state
                guard !current.questionID.isEmpty else { return }
                if let correct = current.correctIndex {
                    voiceHost.gradeVoiceAnswer(transcript: transcript,
                                               question: current.questionText,
                                               options: current.choices,
                                               correctIndex: correct)
                } else {
                    // Correctness is secret until the reveal: hold the
                    // answer and grade it then.
                    voiceCue.questionID = current.questionID
                    voiceCue.transcript = transcript
                    voiceHost.drive(state: "lock", questionID: current.questionID)
                }
            }
        }
        .onDisappear {
            voiceHost.onFinalTranscript = nil
            voiceHost.detach()
        }
        .onChange(of: vm.state.questionID) { _, newID in
            questionArrived(newID)
        }
        .onChange(of: vm.state.phase) { _, newPhase in
            phaseChanged(newPhase)
        }
        .onChange(of: vm.state.lockedIDs.count) { oldValue, newValue in
            if newValue > oldValue {
                SoundPlayer.shared.playClick(volume: 0.45)
            }
        }
    }

    // MARK: Layout

    private var showsPods: Bool {
        switch phase {
        case "standings", "finale_intro", "finale_question", "finale_reveal", "summary":
            return false
        default:
            return !state.players.isEmpty
        }
    }

    private var stageAccent: Color {
        switch phase {
        case "category_vote", "category_reveal": return TShowPalette.magenta
        case "power_pick", "power_reveal": return TVTheme.cyan
        case "finale_intro", "finale_question", "finale_reveal": return TShowPalette.gold
        case "summary": return TShowPalette.gold
        default: return TVTheme.purple
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case "category_vote", "category_reveal":
            TShowDoorsStage(state: state)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        case "power_pick":
            TShowPowerPickStage(state: state)
                .transition(.opacity)
        case "power_reveal":
            TShowPowerRevealStage(events: state.powerEvents)
                .transition(.opacity)
        case "question", "reveal":
            TShowQuestionStage(state: state)
                .transition(.opacity)
        case "standings":
            TShowStandingsStage(state: state)
                .transition(.opacity)
        case "finale_intro", "finale_question", "finale_reveal":
            TShowFinaleStage(state: state)
                .transition(.opacity)
        case "summary":
            TShowWinnerStage(state: state)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        default:
            TShowTitleCard(isCustom: state.isCustom, quizName: state.quizName)
                .transition(.opacity)
        }
    }

    // MARK: Events

    private func questionArrived(_ newID: String) {
        guard !newID.isEmpty else { return }
        voiceCue.questionID = ""
        voiceCue.transcript = nil
        let current: TShowState = vm.state
        if current.phase == "question" {
            voiceHost.askQuestion(speakableQuestion(current), questionID: newID)
        } else if current.phase == "finale_question" {
            voiceHost.speak(current.questionText)
        }
    }

    private func phaseChanged(_ newPhase: String) {
        let current: TShowState = vm.state
        switch newPhase {
        case "category_reveal":
            if !current.chosenCategory.isEmpty {
                voiceHost.speak("\(current.chosenCategory)!")
            }
        case "power_reveal":
            if let first = current.powerEvents.first {
                voiceHost.speak(TShowPalette.eventLine(first))
            }
        case "reveal", "finale_reveal":
            gradeHeldVoiceAnswer(current)
            if current.lastResults.contains(where: { $0.correct }) {
                confettiKey += 1
            }
            if newPhase == "finale_reveal" && current.finaleMoves.values.contains(1) {
                SoundPlayer.shared.play(.ladderClimb, volume: 0.6)
            }
        case "finale_intro":
            voiceHost.speak("Time for the Final Climb!")
            SoundPlayer.shared.play(.ladderClimb, volume: 0.7)
        case "summary":
            confettiKey += 1
            SoundPlayer.shared.play(.winFanfare, volume: 0.8)
            if let winner = current.player(current.winnerID) {
                voiceHost.speak("\(winner.name) wins the show!")
            }
        default:
            break
        }
    }

    private func gradeHeldVoiceAnswer(_ current: TShowState) {
        guard let transcript = voiceCue.transcript,
              voiceCue.questionID == current.questionID,
              let correct = current.correctIndex else { return }
        voiceCue.transcript = nil
        voiceCue.questionID = ""
        voiceHost.gradeVoiceAnswer(transcript: transcript,
                                   question: current.questionText,
                                   options: current.choices,
                                   correctIndex: correct)
    }

    /// Host phrasing: spoken through the TV speakers when the question lands.
    private func speakableQuestion(_ s: TShowState) -> String {
        let options: String = s.choices.enumerated()
            .map { "\(TShowPalette.letter($0.offset)): \($0.element)" }
            .joined(separator: ". ")
        return "\(s.questionText). \(options)."
    }
}

// MARK: - Stage background

/// A game-show stage: a violet backdrop, sweeping spotlight cones, a row of
/// marquee bulbs and a glowing floor. One Canvas, redrawn by a TimelineView.
struct TShowStageBackground: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t: Double = timeline.date.timeIntervalSinceReferenceDate
                TShowStagePainter.paint(&context, size: size, time: t, accent: accent)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum TShowStagePainter {
    static let coneColors: [Color] = [
        TShowPalette.magenta, TVTheme.cyan, TShowPalette.gold, TVTheme.purple,
    ]

    static func paint(_ context: inout GraphicsContext, size: CGSize, time: Double, accent: Color) {
        let full = Path(CGRect(origin: .zero, size: size))
        let backdrop = Gradient(colors: [TShowPalette.stageInk, TShowPalette.stageBack, TShowPalette.stageShadow])
        context.fill(full, with: .linearGradient(backdrop,
                                                 startPoint: CGPoint(x: size.width / 2, y: 0),
                                                 endPoint: CGPoint(x: size.width / 2, y: size.height)))
        // Accent glow behind the host plate.
        let glow = Gradient(colors: [accent.opacity(0.35), accent.opacity(0)])
        context.fill(full, with: .radialGradient(glow,
                                                 center: CGPoint(x: size.width / 2, y: size.height * 0.42),
                                                 startRadius: 0,
                                                 endRadius: size.width * 0.55))
        paintCones(&context, size: size, time: time)
        paintFloor(&context, size: size, time: time, accent: accent)
        paintBulbs(&context, size: size, time: time)
    }

    private static func paintCones(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        var layer = context
        layer.blendMode = .plusLighter
        let count: Int = coneColors.count
        for i in 0..<count {
            let fraction: CGFloat = (CGFloat(i) + 0.5) / CGFloat(count)
            let source = CGPoint(x: size.width * fraction, y: -40)
            let swing: Double = sin(time * 0.45 + Double(i) * 1.7) * 0.42
            let length: CGFloat = size.height * 1.1
            let spread: CGFloat = size.width * 0.075
            let tipX: CGFloat = source.x + CGFloat(sin(swing)) * length
            let tipY: CGFloat = source.y + CGFloat(cos(swing)) * length
            var cone = Path()
            cone.move(to: source)
            cone.addLine(to: CGPoint(x: tipX - spread, y: tipY))
            cone.addLine(to: CGPoint(x: tipX + spread, y: tipY))
            cone.closeSubpath()
            let color: Color = coneColors[i]
            let shade = Gradient(colors: [color.opacity(0.32), color.opacity(0.0)])
            layer.fill(cone, with: .linearGradient(shade,
                                                   startPoint: source,
                                                   endPoint: CGPoint(x: tipX, y: tipY)))
        }
    }

    private static func paintFloor(_ context: inout GraphicsContext, size: CGSize, time: Double, accent: Color) {
        let floorRect = CGRect(x: -size.width * 0.1, y: size.height * 0.78,
                               width: size.width * 1.2, height: size.height * 0.5)
        let pulse: Double = 0.4 + 0.1 * sin(time * 1.3)
        let floorGlow = Gradient(colors: [accent.opacity(pulse), TShowPalette.stageShadow.opacity(0)])
        context.fill(Path(ellipseIn: floorRect),
                     with: .radialGradient(floorGlow,
                                           center: CGPoint(x: size.width / 2, y: size.height * 0.92),
                                           startRadius: 0,
                                           endRadius: size.width * 0.5))
    }

    private static func paintBulbs(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        let count: Int = 28
        let radius: CGFloat = 7
        for i in 0..<count {
            let x: CGFloat = size.width * (CGFloat(i) + 0.5) / CGFloat(count)
            let sag: CGFloat = 26 * sin(.pi * CGFloat(i) / CGFloat(count - 1))
            let y: CGFloat = 14 + sag
            let phase: Double = time * 3.0 + Double(i % 2) * .pi
            let lit: Double = 0.45 + 0.55 * max(0, sin(phase))
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)),
                         with: .color(TShowPalette.gold.opacity(0.18 * lit)))
            context.fill(Path(ellipseIn: rect), with: .color(TShowPalette.spotlight.opacity(lit)))
        }
    }
}

// MARK: - Top bar

private struct TShowTopBar: View {
    let state: TShowState

    private var progress: String {
        switch state.phase {
        case "intro": return state.isCustom ? "YOUR QUIZ" : "GET READY"
        case "finale_intro": return "THE FINAL CLIMB"
        case "finale_question", "finale_reveal":
            return "FINAL CLIMB  \(state.finaleNumber) OF \(max(state.finaleTotal, 1))"
        case "summary": return "AND THE WINNER IS"
        case "standings": return "STANDINGS"
        case "category_vote", "category_reveal", "power_pick", "power_reveal":
            return "ROUND \(max(state.round, 1)) OF \(max(state.totalRounds, 1))"
        default:
            return "QUESTION \(max(state.questionNumber, 1)) OF \(max(state.totalQuestions, 1))"
        }
    }

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(TShowPalette.gold)
                Text("TRIVIA")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("SHOWDOWN")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .foregroundColor(TShowPalette.stageInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(TShowPalette.gold))
            }
            Text(progress)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .contentTransition(.numericText())
                .animation(.default, value: progress)
            Spacer()
        }
        .padding(.leading, 70)
        .padding(.trailing, 640)       // the voice overlay lives top-right
        .padding(.top, 52)
    }
}

// MARK: - Timer

private struct TShowTimer: View {
    let seconds: Int
    let total: Int
    var tint: Color = TVTheme.cyan
    var size: CGFloat = 130

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(seconds) / CGFloat(total)))
    }

    private var urgent: Bool { seconds <= 5 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(urgent ? TShowPalette.hotPink : tint,
                        style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1.0), value: fraction)
            Text("\(seconds)")
                .font(.system(size: size * 0.4, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.default, value: seconds)
        }
        .frame(width: size, height: size)
        .scaleEffect(urgent && seconds > 0 ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: seconds)
    }
}

// MARK: - Intro

private struct TShowTitleCard: View {
    let isCustom: Bool
    let quizName: String

    @State private var shown: Bool = false
    private let letters: [String] = ["T", "R", "I", "V", "I", "A"]

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 8) {
                ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                    Text(letter)
                        .font(.system(size: 170, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: TShowPalette.tile(index).opacity(0.9), radius: 0, x: 0, y: 10)
                        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 18)
                        .scaleEffect(shown ? 1 : 0.2)
                        .rotationEffect(.degrees(shown ? 0 : -25))
                        .opacity(shown ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.55)
                            .delay(0.08 * Double(index)), value: shown)
                }
            }
            Text("SHOWDOWN")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .tracking(14)
                .foregroundColor(TShowPalette.stageInk)
                .padding(.horizontal, 44)
                .padding(.vertical, 14)
                .background(Capsule().fill(TShowPalette.gold))
                .rotationEffect(.degrees(-3))
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.55, dampingFraction: 0.6).delay(0.6), value: shown)
            Text(subtitle)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(1.0), value: shown)
        }
        .onAppear { shown = true }
    }

    private var subtitle: String {
        if isCustom {
            let name: String = quizName.isEmpty ? "Your quiz" : quizName
            return "Tonight's quiz: \(name)\nSneaky powers. One Final Climb."
        }
        return "Three rounds. Sneaky powers. One Final Climb."
    }
}

// MARK: - Category doors

private struct TShowDoorsStage: View {
    let state: TShowState

    private var revealing: Bool { state.phase == "category_reveal" }

    var body: some View {
        VStack(spacing: 34) {
            HStack(alignment: .center, spacing: 30) {
                VStack(spacing: 6) {
                    Text(revealing ? "THE CATEGORY IS" : "PICK A DOOR!")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(revealing ? state.chosenCategory : "Vote on your phone")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(revealing ? TShowPalette.gold : .white.opacity(0.75))
                }
                if !revealing {
                    TShowTimer(seconds: state.secondsLeft, total: max(state.phaseSeconds, 1),
                               tint: TShowPalette.magenta, size: 110)
                }
            }
            HStack(spacing: 60) {
                ForEach(state.doors) { door in
                    TShowDoor(door: door,
                              isOpen: revealing && door.id == state.chosenIndex,
                              isDimmed: revealing && door.id != state.chosenIndex)
                }
            }
        }
    }
}

private struct TShowDoor: View {
    let door: TShowDoorInfo
    let isOpen: Bool
    let isDimmed: Bool

    private var color: Color { TShowPalette.doorColors[door.id % TShowPalette.doorColors.count] }
    private let width: CGFloat = 380
    private let height: CGFloat = 520

    var body: some View {
        ZStack {
            interior
            panel
                .rotation3DEffect(.degrees(isOpen ? -108 : 0),
                                  axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading,
                                  perspective: 0.45)
                .animation(.spring(response: 0.9, dampingFraction: 0.7), value: isOpen)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) { voteBadge }
        .scaleEffect(isOpen ? 1.08 : (isDimmed ? 0.88 : 1.0))
        .opacity(isDimmed ? 0.35 : 1.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isDimmed)
    }

    private var interior: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(RadialGradient(colors: [TShowPalette.spotlightCore, TShowPalette.gold, color.opacity(0.9)],
                                     center: .center, startRadius: 10, endRadius: 360))
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 70, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(door.name)
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .foregroundColor(TShowPalette.stageInk)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var panel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous).fill(Color.black.opacity(0.4)))
                .offset(x: 10, y: 12)
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.75)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 22) {
                RoundedRectangle(cornerRadius: ShellTheme.buttonRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 5)
                    .frame(height: 150)
                    .overlay(
                        Text("\(door.id + 1)")
                            .font(.system(size: 96, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    )
                Text(door.name)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius).fill(Color.black.opacity(0.25)))
                RoundedRectangle(cornerRadius: ShellTheme.buttonRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 5)
                    .frame(height: 110)
            }
            .padding(30)
            Circle()
                .fill(TShowPalette.gold)
                .frame(width: 30, height: 30)
                .shadow(color: Color.black.opacity(0.4), radius: 3, x: 0, y: 3)
                .offset(x: width / 2 - 44, y: 30)
        }
    }

    private var voteBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
            Text("\(door.votes)")
                .contentTransition(.numericText())
                .animation(.spring(), value: door.votes)
        }
        .font(.system(size: 30, weight: .black, design: .rounded))
        .foregroundColor(TShowPalette.stageInk)
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white))
        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 6)
        .offset(y: 30)
        .opacity(isOpen ? 0 : 1)
    }
}

// MARK: - Powers

private struct TShowPowerPickStage: View {
    let state: TShowState

    private struct PowerCard: Identifiable {
        let id: String
        let name: String
        let detail: String
    }

    private let cards: [PowerCard] = [
        PowerCard(id: "freeze", name: "Freeze", detail: "Tap 5 times to break the ice"),
        PowerCard(id: "scramble", name: "Scramble", detail: "Answers keep jumping around"),
        PowerCard(id: "fog", name: "Fog", detail: "Answers start blurry"),
        PowerCard(id: "shield", name: "Shield", detail: "Blocks one power"),
    ]

    @State private var bob: Bool = false

    var body: some View {
        VStack(spacing: 40) {
            HStack(spacing: 30) {
                VStack(spacing: 6) {
                    Text("POWER UP!")
                        .font(.system(size: 72, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("On your phone: throw a power at a rival, or raise a shield")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                TShowTimer(seconds: state.secondsLeft, total: max(state.phaseSeconds, 1),
                           tint: TVTheme.cyan, size: 110)
            }
            HStack(spacing: 44) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    VStack(spacing: 16) {
                        ShellIconOrb(symbol: TShowPalette.powerSymbol(card.id),
                                     top: TShowPalette.powerColor(card.id),
                                     bottom: TShowPalette.powerColor(card.id).opacity(0.6),
                                     accent: TShowPalette.powerColor(card.id),
                                     size: 150,
                                     isLit: true)
                            .offset(y: bob ? -12 : 12)
                            .animation(.easeInOut(duration: 1.1)
                                .repeatForever(autoreverses: true)
                                .delay(0.2 * Double(index)), value: bob)
                        Text(card.name)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text(card.detail)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .frame(width: 280)
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                }
            }
        }
        .onAppear { bob = true }
    }
}

private struct TShowPowerRevealStage: View {
    let events: [TShowPowerEvent]

    @State private var shownCount: Int = 0

    private var visible: [TShowPowerEvent] { Array(events.prefix(6)) }

    var body: some View {
        VStack(spacing: 22) {
            Text("POWERS UNLEASHED!")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.bottom, 10)
            ForEach(visible) { event in
                TShowPowerBanner(event: event)
                    .offset(x: event.id < shownCount ? 0 : -1400)
                    .opacity(event.id < shownCount ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.72), value: shownCount)
            }
            if events.count > visible.count {
                Text("+\(events.count - visible.count) more")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .task {
            shownCount = 0
            for index in 0..<visible.count {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                shownCount = index + 1
            }
        }
    }
}

private struct TShowPowerBanner: View {
    let event: TShowPowerEvent

    private var symbol: String { event.blocked ? "shield.fill" : TShowPalette.powerSymbol(event.power) }
    private var color: Color { event.blocked ? TShowPalette.powerColor("shield") : TShowPalette.powerColor(event.power) }

    var body: some View {
        HStack(spacing: 22) {
            ShellIconOrb(symbol: symbol, top: color, bottom: color.opacity(0.6),
                         accent: color, size: 84, isLit: true)
            Text(TShowPalette.eventLine(event))
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .frame(width: 1100)
        .background(
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0.55), Color.black.opacity(0.35)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(Capsule().strokeBorder(color.opacity(0.8), lineWidth: 3))
    }
}

// MARK: - Question

private struct TShowQuestionStage: View {
    let state: TShowState

    private var pickers: [Int: [TShowPlayer]] {
        guard state.isReveal else { return [:] }
        var out: [Int: [TShowPlayer]] = [:]
        let rows: [String: TShowResultRow] = state.resultsByPlayer
        for player in state.players {
            if let choice = rows[player.id]?.choice {
                out[choice, default: []].append(player)
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 30) {
            HStack(alignment: .center, spacing: 34) {
                TShowHostPlate(category: state.category,
                               text: state.questionText,
                               questionID: state.questionID,
                               fontSize: 48)
                VStack(spacing: 14) {
                    TShowTimer(seconds: state.isReveal ? 0 : state.secondsLeft,
                               total: max(state.phaseSeconds, 1),
                               tint: TVTheme.cyan,
                               size: 140)
                    Text("\(state.answeredIDs.count)/\(state.players.count) locked")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
                .frame(width: 180)
            }
            .padding(.horizontal, 70)
            TShowAnswerGrid(choices: state.choices,
                            questionID: state.questionID,
                            showChoices: state.showChoices,
                            correctIndex: state.isReveal ? state.correctIndex : nil,
                            pickers: pickers,
                            tileHeight: 120,
                            fontSize: 38)
                .padding(.horizontal, 70)
        }
    }
}

/// The host's big question plate: a glossy panel with a gold rim, a mic
/// badge and the question typed in.
private struct TShowHostPlate: View {
    let category: String
    let text: String
    let questionID: String
    var fontSize: CGFloat = 48

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(category.uppercased())
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .tracking(4)
                    .lineLimit(1)
            }
            .foregroundColor(TShowPalette.stageInk)
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(Capsule().fill(TShowPalette.gold))
            TShowTypewriter(text: text, fontSize: fontSize)
                .id(questionID)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                    .fill(TShowPalette.stageNight)
                    .offset(y: 12)
                RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                    .fill(LinearGradient(colors: [TShowPalette.stageDeep, TShowPalette.stageFloor],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [TShowPalette.gold, TShowPalette.goldWarm],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 6)
            }
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 16)
    }
}

/// Types the question in quickly (about a second whatever its length).
/// The untyped remainder is laid out but clear, so lines never reflow.
private struct TShowTypewriter: View {
    let text: String
    let fontSize: CGFloat

    @State private var visible: Int = 0

    private var attributed: AttributedString {
        let characters: [Character] = Array(text)
        let count: Int = min(visible, characters.count)
        var shown = AttributedString(String(characters.prefix(count)))
        shown.foregroundColor = Color.white
        var hidden = AttributedString(String(characters.dropFirst(count)))
        hidden.foregroundColor = Color.clear
        return shown + hidden
    }

    var body: some View {
        Text(attributed)
            .font(.system(size: fontSize, weight: .heavy, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: text) {
                let total: Int = Array(text).count
                visible = 0
                guard total > 0 else { return }
                let frames: Int = 30
                for frame in 1...frames {
                    try? await Task.sleep(nanoseconds: 33_000_000)
                    if Task.isCancelled { return }
                    visible = total * frame / frames
                }
                visible = total
            }
    }
}

private struct TShowAnswerGrid: View {
    let choices: [String]
    let questionID: String
    let showChoices: Bool
    let correctIndex: Int?
    let pickers: [Int: [TShowPlayer]]
    var tileHeight: CGFloat = 120
    var fontSize: CGFloat = 38

    private let columns: [GridItem] = [GridItem(.flexible(), spacing: 30), GridItem(.flexible(), spacing: 30)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 26) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                TShowAnswerTile(index: index,
                                text: choice,
                                isShown: showChoices,
                                correctIndex: correctIndex,
                                pickers: pickers[index] ?? [],
                                height: tileHeight,
                                fontSize: fontSize)
            }
        }
        .id(questionID)
    }
}

private struct TShowAnswerTile: View {
    let index: Int
    let text: String
    let isShown: Bool
    let correctIndex: Int?
    let pickers: [TShowPlayer]
    let height: CGFloat
    let fontSize: CGFloat

    private var color: Color { TShowPalette.tile(index) }
    private var isCorrect: Bool { correctIndex == index }
    private var isDimmed: Bool { correctIndex != nil && !isCorrect }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous).fill(Color.black.opacity(0.42)))
                .offset(y: 12)
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [color, color.opacity(0.78)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
                .padding(4)
            HStack(spacing: 20) {
                ZStack {
                    Circle().fill(Color.white)
                    Image(systemName: TShowPalette.shape(index))
                        .font(.system(size: height * 0.22, weight: .black, design: .rounded))
                        .foregroundColor(color)
                }
                .frame(width: height * 0.6, height: height * 0.6)
                Text(text)
                    .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
                Spacer(minLength: 0)
                pickerStack
                if isCorrect {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: height * 0.42, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: height)
        .shadow(color: isCorrect ? TShowPalette.gold.opacity(0.9) : Color.clear, radius: 28)
        .rotation3DEffect(.degrees(isShown ? 0 : 75), axis: (x: 1, y: 0, z: 0),
                          anchor: .bottom, perspective: 0.5)
        .scaleEffect(isCorrect ? 1.05 : (isDimmed ? 0.95 : 1))
        .opacity(isShown ? (isDimmed ? 0.35 : 1) : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.62).delay(isShown && correctIndex == nil ? Double(index) * 0.09 : 0),
                   value: isShown)
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: correctIndex)
    }

    @ViewBuilder
    private var pickerStack: some View {
        if !pickers.isEmpty {
            HStack(spacing: -14) {
                ForEach(pickers.prefix(5)) { player in
                    ShellAvatarToken(id: player.id, name: player.name, size: height * 0.42)
                }
                if pickers.count > 5 {
                    Text("+\(pickers.count - 5)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

// MARK: - Player pods

private struct TShowPodRow: View {
    let state: TShowState

    var body: some View {
        let locked: Set<String> = state.lockedIDs
        let results: [String: TShowResultRow] = state.resultsByPlayer
        let hits: [String: [String]] = state.hitPowers
        let showHits: Bool = state.phase == "power_reveal" || state.phase == "question"
        let size: CGFloat = state.players.count > 7 ? 70 : 88
        HStack(alignment: .bottom, spacing: state.players.count > 7 ? 18 : 30) {
            ForEach(state.players) { player in
                TShowPod(player: player,
                         size: size,
                         isLocked: locked.contains(player.id),
                         result: state.phase == "reveal" ? results[player.id] : nil,
                         hits: showHits ? (hits[player.id] ?? []) : [])
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

private struct TShowPod: View {
    let player: TShowPlayer
    let size: CGFloat
    let isLocked: Bool
    let result: TShowResultRow?
    let hits: [String]

    @State private var hop: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let result {
                    if result.correct {
                        TShowCountUp(target: result.points)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(TShowPalette.hotPink)
                            .transition(.scale)
                    }
                } else if !hits.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(hits.enumerated()), id: \.offset) { _, power in
                            Image(systemName: TShowPalette.powerSymbol(power))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(7)
                                .background(Circle().fill(TShowPalette.powerColor(power)))
                        }
                    }
                }
            }
            .frame(height: 44)
            ShellAvatarToken(id: player.id, name: player.name, size: size,
                             isHost: player.isHost, isBot: player.isBot, isReady: isLocked)
                .shellHop(trigger: hop, height: 34)
            Text(player.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: size + 40)
            Text("\(player.score)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(TShowPalette.gold)
                .contentTransition(.numericText(value: Double(player.score)))
                .animation(.easeOut(duration: 0.8), value: player.score)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(isLocked ? Color.white.opacity(0.16) : Color.black.opacity(0.25))
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: result)
        .onChange(of: isLocked) { _, nowLocked in
            if nowLocked { hop += 1 }
        }
        .onChange(of: result?.correct) { _, correct in
            if correct == true { hop += 1 }
        }
    }
}

/// "+750" that rolls up from zero.
private struct TShowCountUp: View {
    let target: Int

    @State private var shown: Int = 0

    var body: some View {
        Text("+\(shown)")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundColor(TShowPalette.stageInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(TVTheme.green))
            .shadow(color: TVTheme.green.opacity(0.7), radius: 10)
            .task(id: target) {
                shown = 0
                let steps: Int = 18
                for step in 1...steps {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    if Task.isCancelled { return }
                    shown = target * step / steps
                }
            }
    }
}

// MARK: - Standings

private struct TShowStandingsStage: View {
    let state: TShowState

    @State private var settled: Bool = false

    private var heading: String {
        state.questionNumber >= state.totalQuestions
            ? "Next up: the Final Climb!"
            : "After round \(max(state.round, 1))"
    }

    var body: some View {
        let players: [TShowPlayer] = state.players
        let rowHeight: CGFloat = min(96, 760 / CGFloat(max(players.count, 1)))
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text("STANDINGS")
                    .font(.system(size: 70, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(heading)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(TShowPalette.gold)
            }
            ZStack(alignment: .top) {
                ForEach(players) { player in
                    let slot: Int = max(0, (settled ? player.rank : player.prevRank) - 1)
                    TShowStandingRow(player: player, height: rowHeight - 10, settled: settled)
                        .offset(y: CGFloat(slot) * rowHeight)
                        .zIndex(Double(100 - player.rank))
                }
            }
            .frame(width: 1100, height: rowHeight * CGFloat(max(players.count, 1)), alignment: .top)
            .animation(.spring(response: 0.8, dampingFraction: 0.72), value: settled)
        }
        .task {
            settled = false
            try? await Task.sleep(nanoseconds: 900_000_000)
            if Task.isCancelled { return }
            settled = true
        }
    }
}

private struct TShowStandingRow: View {
    let player: TShowPlayer
    let height: CGFloat
    let settled: Bool

    private var movement: Int { player.prevRank - player.rank }

    var body: some View {
        HStack(spacing: 22) {
            Text("\(player.rank)")
                .font(.system(size: height * 0.45, weight: .black, design: .rounded))
                .foregroundColor(player.rank == 1 ? TShowPalette.stageInk : .white)
                .frame(width: height * 0.8, height: height * 0.8)
                .background(Circle().fill(player.rank == 1 ? TShowPalette.gold : Color.white.opacity(0.15)))
            ShellAvatarToken(id: player.id, name: player.name, size: height * 0.78,
                             isHost: player.isHost, isBot: player.isBot)
            Text(player.name)
                .font(.system(size: height * 0.4, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            if settled && movement != 0 {
                Image(systemName: movement > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: height * 0.4, weight: .bold, design: .rounded))
                    .foregroundColor(movement > 0 ? TVTheme.green : TShowPalette.hotPink)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer(minLength: 0)
            Text("\(player.score)")
                .font(.system(size: height * 0.45, weight: .black, design: .rounded))
                .foregroundColor(TShowPalette.gold)
        }
        .padding(.horizontal, 26)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(player.rank == 1 ? TShowPalette.stageDeep : Color.black.opacity(0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .strokeBorder(player.rank == 1 ? TShowPalette.gold : Color.white.opacity(0.1), lineWidth: 3)
        )
    }
}

// MARK: - Finale

private struct TShowFinaleStage: View {
    let state: TShowState

    var body: some View {
        if state.phase == "finale_intro" {
            VStack(spacing: 20) {
                Text("THE FINAL CLIMB")
                    .font(.system(size: 76, weight: .black, design: .rounded))
                    .foregroundColor(TShowPalette.gold)
                    .shadow(color: TShowPalette.goldWarm.opacity(0.8), radius: 0, x: 0, y: 6)
                HStack(spacing: 18) {
                    ShellChip(systemImage: "arrow.up", text: "Right answer: climb a rung", tint: TVTheme.green)
                    ShellChip(systemImage: "arrow.down", text: "Wrong answer: slip a rung", tint: TShowPalette.hotPink)
                    ShellChip(systemImage: "flag.checkered", text: "First to the top wins", tint: TShowPalette.gold)
                }
                TShowTower(state: state)
                    .frame(width: 1300)
                    .padding(.bottom, 30)
            }
        } else {
            HStack(alignment: .top, spacing: 40) {
                TShowTower(state: state)
                    .frame(width: 900)
                VStack(spacing: 24) {
                    HStack(alignment: .center, spacing: 20) {
                        TShowHostPlate(category: state.category,
                                       text: state.questionText,
                                       questionID: state.questionID,
                                       fontSize: 36)
                        TShowTimer(seconds: state.isReveal ? 0 : state.secondsLeft,
                                   total: max(state.phaseSeconds, 1),
                                   tint: TShowPalette.gold,
                                   size: 110)
                    }
                    TShowAnswerStack(choices: state.choices,
                                     questionID: state.questionID,
                                     showChoices: state.showChoices,
                                     correctIndex: state.isReveal ? state.correctIndex : nil)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 30)
        }
    }
}

/// Four slim tiles in a column, for the finale's side panel.
private struct TShowAnswerStack: View {
    let choices: [String]
    let questionID: String
    let showChoices: Bool
    let correctIndex: Int?

    var body: some View {
        VStack(spacing: 18) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                TShowAnswerTile(index: index,
                                text: choice,
                                isShown: showChoices,
                                correctIndex: correctIndex,
                                pickers: [],
                                height: 92,
                                fontSize: 30)
            }
        }
        .id(questionID)
    }
}

/// One ladder per player; avatars sit on their rung and spring up or down.
private struct TShowTower: View {
    let state: TShowState

    var body: some View {
        GeometryReader { geo in
            let players: [TShowPlayer] = state.players
            let count: Int = max(players.count, 1)
            let height: Int = max(state.towerHeight, 1)
            let columnWidth: CGFloat = geo.size.width / CGFloat(count)
            let top: CGFloat = 70
            let bottom: CGFloat = geo.size.height - 60
            let step: CGFloat = (bottom - top) / CGFloat(height)
            let token: CGFloat = min(84, columnWidth * 0.62, step * 1.1)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    TShowTowerPainter.paint(&context, size: size, columns: count,
                                            rungs: height, top: top, bottom: bottom)
                }
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    let rung: Int = min(max(player.rung, 0), height)
                    let x: CGFloat = columnWidth * (CGFloat(index) + 0.5)
                    let y: CGFloat = bottom - CGFloat(rung) * step - token * 0.35
                    TShowClimber(player: player,
                                 size: token,
                                 move: state.phase == "finale_reveal" ? (state.finaleMoves[player.id] ?? 0) : 0,
                                 atTop: rung >= height)
                        .position(x: x, y: y)
                        .animation(.spring(response: 0.8, dampingFraction: 0.62), value: rung)
                }
            }
        }
        .frame(minHeight: 560)
        .drawingGroup(opaque: false)
    }
}

enum TShowTowerPainter {
    static func paint(_ context: inout GraphicsContext, size: CGSize, columns: Int,
                      rungs: Int, top: CGFloat, bottom: CGFloat) {
        let columnWidth: CGFloat = size.width / CGFloat(max(columns, 1))
        let step: CGFloat = (bottom - top) / CGFloat(max(rungs, 1))
        // Finish line platform.
        let platform = CGRect(x: 0, y: top - 18, width: size.width, height: 16)
        context.fill(Path(roundedRect: platform, cornerRadius: 8), with: .color(TShowPalette.gold))
        context.fill(Path(roundedRect: platform.insetBy(dx: 0, dy: 5).offsetBy(dx: 0, dy: 8), cornerRadius: 6),
                     with: .color(TShowPalette.goldDeep.opacity(0.7)))
        for column in 0..<max(columns, 1) {
            let center: CGFloat = columnWidth * (CGFloat(column) + 0.5)
            let half: CGFloat = min(46, columnWidth * 0.32)
            let railColor = Color.white.opacity(0.55)
            var rails = Path()
            rails.move(to: CGPoint(x: center - half, y: top))
            rails.addLine(to: CGPoint(x: center - half, y: bottom + 20))
            rails.move(to: CGPoint(x: center + half, y: top))
            rails.addLine(to: CGPoint(x: center + half, y: bottom + 20))
            context.stroke(rails, with: .color(railColor), lineWidth: 6)
            for rung in 0...max(rungs, 1) {
                let y: CGFloat = bottom - CGFloat(rung) * step
                var bar = Path()
                bar.move(to: CGPoint(x: center - half, y: y))
                bar.addLine(to: CGPoint(x: center + half, y: y))
                let color: Color = rung == rungs ? TShowPalette.gold : Color.white.opacity(0.35)
                context.stroke(bar, with: .color(color), lineWidth: rung == rungs ? 6 : 4)
            }
        }
    }
}

private struct TShowClimber: View {
    let player: TShowPlayer
    let size: CGFloat
    let move: Int
    let atTop: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                ShellAvatarToken(id: player.id, name: player.name, size: size, isBot: player.isBot)
                    .overlay(alignment: .top) {
                        if atTop {
                            Image(systemName: "crown.fill")
                                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                                .foregroundColor(TShowPalette.gold)
                                .offset(y: -size * 0.42)
                        }
                    }
                if move != 0 {
                    Image(systemName: move > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundColor(move > 0 ? TVTheme.green : TShowPalette.hotPink)
                        .background(Circle().fill(Color.white).padding(3))
                        .offset(x: size * 0.18, y: -size * 0.12)
                        .transition(.scale)
                }
            }
            Text(player.name)
                .font(.system(size: max(16, size * 0.24), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
    }
}

// MARK: - Winner

private struct TShowWinnerStage: View {
    let state: TShowState

    @State private var hop: Int = 0
    @State private var shown: Bool = false

    private var ranked: [TShowPlayer] {
        let winner: String = state.winnerID ?? ""
        return state.players.sorted { a, b in
            if (a.id == winner) != (b.id == winner) { return a.id == winner }
            if a.rung != b.rung { return a.rung > b.rung }
            return a.score > b.score
        }
    }

    var body: some View {
        let order: [TShowPlayer] = ranked
        VStack(spacing: 26) {
            if let winner = order.first {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [TShowPalette.gold.opacity(0.65), Color.clear],
                                             center: .center, startRadius: 0, endRadius: 260))
                        .frame(width: 520, height: 520)
                    ShellAvatarToken(id: winner.id, name: winner.name, size: 250,
                                     isBot: winner.isBot)
                        .overlay(alignment: .top) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 110, weight: .bold, design: .rounded))
                                .foregroundColor(TShowPalette.gold)
                                .shadow(color: TShowPalette.goldWarm, radius: 14)
                                .offset(y: -110)
                        }
                        .shellHop(trigger: hop, height: 60)
                }
                .frame(height: 420)
                .scaleEffect(shown ? 1 : 0.3)
                .opacity(shown ? 1 : 0)
                Text("\(winner.name) wins the show!")
                    .font(.system(size: 80, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: TShowPalette.magenta, radius: 0, x: 0, y: 6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 80)
            }
            HStack(spacing: 30) {
                ForEach(Array(order.prefix(5).enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(index == 0 ? TShowPalette.gold : .white.opacity(0.8))
                        ShellAvatarToken(id: player.id, name: player.name, size: 56, isBot: player.isBot)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(.system(size: 24, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(player.score) pts")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(TShowPalette.gold)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.3)))
                }
            }
            .opacity(shown ? 1 : 0)
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.6), value: shown)
        .task {
            shown = true
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if Task.isCancelled { return }
                hop += 1
            }
        }
    }
}
