import SwiftUI

/// 20 Questions: the room asks yes or no questions out loud; the Answerer
/// taps the verdicts on their phone.
///
/// Server contract (games/native_hub/engines/talk.py, TwentyQuestionsEngine
/// public_state): `phase` runs intro -> ask -> reveal each round, then
/// "final". `category` is the only clue the TV ever shows; `log` holds one
/// entry per question used (`kind` "answer" with yes / no / sometimes, or
/// "guess" for a wrong guess), `tally` the running counts, `typingNames` who
/// has tapped "I know it!", and `secret` plus `roundResult` appear only in
/// the reveal.

// MARK: - State

struct TwentyQLogEntry: Identifiable, Equatable {
    let id: Int
    let kind: String
    let answer: String
    let text: String
    let name: String
}

struct TwentyQRoundResult: Equatable {
    var secret: String = ""
    var solved: Bool = false
    var solverID: String = ""
    var solverName: String = ""
    var questionNumber: Int = 0
    var solverPoints: Int = 0
    var answererID: String = ""
    var answererName: String = ""
    var answererPoints: Int = 0
    var goodGame: Bool = false

    static func parse(_ value: Any?) -> TwentyQRoundResult? {
        guard let d = value as? [String: Any] else { return nil }
        var r = TwentyQRoundResult()
        r.secret = d["secret"] as? String ?? ""
        r.solved = d["solved"] as? Bool ?? false
        r.solverID = d["solverID"] as? String ?? ""
        r.solverName = d["solverName"] as? String ?? ""
        r.questionNumber = d["questionNumber"] as? Int ?? 0
        r.solverPoints = d["solverPoints"] as? Int ?? 0
        r.answererID = d["answererID"] as? String ?? ""
        r.answererName = d["answererName"] as? String ?? ""
        r.answererPoints = d["answererPoints"] as? Int ?? 0
        r.goodGame = d["goodGame"] as? Bool ?? false
        return r
    }
}

struct TwentyQBoardState {
    var round: Int = 0
    var totalRounds: Int = 0
    var phase: String = ""
    var secondsLeft: Int = 0
    var phaseSeconds: Int = 0
    var deadline: Double = 0
    var players: [TalkPlayer] = []
    var answererID: String = ""
    var answererName: String = ""
    var category: String = ""
    var categoryKey: String = ""
    var maxQuestions: Int = 20
    var questionsUsed: Int = 0
    var log: [TwentyQLogEntry] = []
    var yesCount: Int = 0
    var noCount: Int = 0
    var sometimesCount: Int = 0
    var wrongGuessCount: Int = 0
    var typingNames: [String] = []
    var typingIDs: Set<String> = []
    var secret: String = ""
    var result: TwentyQRoundResult? = nil
    var hostPrompt: String = ""

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["round"]?.value as? Int { round = v }
        if let v = d["totalRounds"]?.value as? Int { totalRounds = v }
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["phaseSeconds"]?.value as? Int { phaseSeconds = v }
        deadline = TalkPalette.number(d["deadline"]?.value) ?? 0
        players = TalkPlayer.list(from: d["players"]?.value)
        answererID = d["answererID"]?.value as? String ?? ""
        answererName = d["answererName"]?.value as? String ?? ""
        if let v = d["category"]?.value as? String { category = v }
        if let v = d["categoryKey"]?.value as? String { categoryKey = v }
        if let v = d["maxQuestions"]?.value as? Int, v > 0 { maxQuestions = v }
        if let v = d["questionsUsed"]?.value as? Int { questionsUsed = v }
        log = TwentyQBoardState.parseLog(d["log"]?.value)
        if let t = d["tally"]?.value as? [String: Any] {
            yesCount = t["yes"] as? Int ?? 0
            noCount = t["no"] as? Int ?? 0
            sometimesCount = t["sometimes"] as? Int ?? 0
            wrongGuessCount = t["wrongGuesses"] as? Int ?? 0
        }
        let names: [Any] = d["typingNames"]?.value as? [Any] ?? []
        typingNames = names.compactMap { $0 as? String }
        let ids: [Any] = d["typingIDs"]?.value as? [Any] ?? []
        typingIDs = Set(ids.compactMap { $0 as? String })
        secret = d["secret"]?.value as? String ?? ""
        result = TwentyQRoundResult.parse(d["roundResult"]?.value)
        if let v = d["hostPrompt"]?.value as? String { hostPrompt = v }
    }

    static func parseLog(_ value: Any?) -> [TwentyQLogEntry] {
        let raw: [Any] = value as? [Any] ?? []
        return raw.compactMap { item -> TwentyQLogEntry? in
            guard let e = item as? [String: Any], let n = e["n"] as? Int else { return nil }
            return TwentyQLogEntry(id: n,
                                   kind: e["kind"] as? String ?? "answer",
                                   answer: e["answer"] as? String ?? "",
                                   text: e["text"] as? String ?? "",
                                   name: e["name"] as? String ?? "")
        }
    }

    /// The colour of question light `index` (0-based), or nil if unused.
    func lightColor(_ index: Int) -> Color? {
        guard index < log.count else { return nil }
        let entry: TwentyQLogEntry = log[index]
        if entry.kind == "guess" { return TalkPalette.wrongGuess }
        return TalkPalette.verdictColor(entry.answer)
    }
}

enum TwentyQCategoryArt {
    static func symbol(_ key: String) -> String {
        switch key {
        case "animals": return "pawprint.fill"
        case "foods":   return "fork.knife"
        case "places":  return "mappin.and.ellipse"
        case "movies":  return "film.fill"
        case "objects": return "star.fill"
        default:        return "questionmark"
        }
    }

    static func color(_ key: String) -> Color {
        switch key {
        case "animals": return TVTheme.green
        case "foods":   return TVTheme.orange
        case "places":  return TVTheme.blue
        case "movies":  return TVTheme.pink
        case "objects": return TVTheme.gold
        default:        return ShellTheme.cyan
        }
    }
}

// MARK: - Board

struct TVTwentyQuestionsBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: TwentyQBoardState()) { $0.update(from: $1) }
    /// The TV reads the category and the reveal aloud.
    @StateObject private var voice = TVVoiceHost()
    @State private var confettiKey: Int = 0
    @State private var spokenKey: String = ""

    private var state: TwentyQBoardState { vm.state }
    private var phase: String { vm.state.phase }
    private var accent: Color { TwentyQCategoryArt.color(state.categoryKey) }

    var body: some View {
        ZStack {
            TalkStageBackground(leftColor: accent, leftStrength: 0.7,
                                rightColor: ShellTheme.violet, rightStrength: 0.5)
            VStack(spacing: 18) {
                TalkTopBar(symbol: "questionmark.bubble.fill", title: "20 Questions",
                           round: state.round, totalRounds: state.totalRounds,
                           phaseLabel: phaseLabel, accent: accent)
                content
                    .padding(.horizontal, 70)
                    .frame(maxHeight: .infinity)
                TalkPodRow(players: state.players, badges: podBadges,
                           checked: [], spotlight: spotlight)
                    .padding(.bottom, 12)
            }
            if confettiKey > 0 {
                ShellConfetti(particleCount: 150, duration: 4.5,
                              origin: UnitPoint(x: 0.5, y: 0.35), seed: confettiKey)
                    .id(confettiKey)
                    .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: phase)
        .onAppear { vm.bind(roomCode: room.code) }
        .onDisappear { voice.stopSpeaking() }
        .onChange(of: vm.state.phase) { _, newPhase in
            phaseChanged(newPhase)
        }
        .onChange(of: vm.state.questionsUsed) { oldValue, newValue in
            if newValue > oldValue { SoundPlayer.shared.playClick(volume: 0.55) }
        }
    }

    // MARK: Derived

    private var phaseLabel: String {
        switch phase {
        case "intro": return "New secret"
        case "ask": return "Ask out loud"
        case "reveal": return "The reveal"
        case "final": return "Final scores"
        default: return ""
        }
    }

    private var podBadges: [String: TalkPodBadge] {
        var out: [String: TalkPodBadge] = [:]
        for pid in state.typingIDs {
            out[pid] = TalkPodBadge(text: "I KNOW IT", color: TalkPalette.wrongGuess)
        }
        if !state.answererID.isEmpty {
            out[state.answererID] = TalkPodBadge(text: "ANSWERER", color: accent)
        }
        if phase == "reveal", let r = state.result, r.solved, !r.solverID.isEmpty {
            out[r.solverID] = TalkPodBadge(text: "GOT IT", color: TalkPalette.gold)
        }
        return out
    }

    private var spotlight: Set<String> {
        if phase == "reveal", let r = state.result, r.solved, !r.solverID.isEmpty {
            return [r.solverID]
        }
        return state.answererID.isEmpty ? [] : [state.answererID]
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case "reveal":
            TwentyQRevealStage(state: state, accent: accent)
                .id("reveal-\(state.round)")
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        case "final":
            VStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 90, weight: .bold, design: .rounded))
                    .foregroundColor(TalkPalette.gold)
                    .shadow(color: TalkPalette.gold.opacity(0.7), radius: 20)
                Text("That is a wrap!")
                    .font(ShellTheme.display(52, weight: .black))
                    .foregroundColor(.white)
            }
            .transition(.opacity)
        default:
            HStack(alignment: .top, spacing: 40) {
                TwentyQCategoryPanel(state: state, accent: accent)
                    .frame(width: 520)
                VStack(spacing: 26) {
                    TwentyQQuestionMeter(state: state, accent: accent)
                    TwentyQTypingBanner(names: state.typingNames)
                }
                .frame(maxWidth: .infinity)
                TwentyQTallyPanel(state: state)
                    .frame(width: 440)
            }
            .transition(.opacity)
        }
    }

    // MARK: Beats

    private func phaseChanged(_ newPhase: String) {
        switch newPhase {
        case "intro":
            SoundPlayer.shared.play(.ladderClimb, volume: 0.6)
        case "reveal":
            if let r = state.result, r.solved {
                confettiKey += 1
                SoundPlayer.shared.play(.winFanfare, volume: 0.8)
            } else {
                SoundPlayer.shared.play(.snakeDoomSting, volume: 0.5)
            }
        default:
            break
        }
        guard newPhase == "intro" || newPhase == "reveal" else { return }
        let key: String = "\(state.round)-\(newPhase)"
        guard key != spokenKey else { return }
        spokenKey = key
        voice.speak(state.hostPrompt)
    }
}

// MARK: - Category panel

private struct TwentyQCategoryPanel: View {
    let state: TwentyQBoardState
    let accent: Color

    var body: some View {
        ShellGlassCard(cornerRadius: ShellTheme.cardRadius, tint: accent, padding: 26) {
            VStack(spacing: 14) {
                Text("CATEGORY")
                    .font(ShellTheme.eyebrow(24))
                    .tracking(6)
                    .foregroundColor(accent)
                ShellIconOrb(symbol: TwentyQCategoryArt.symbol(state.categoryKey),
                             top: accent, bottom: accent.opacity(0.5), accent: accent,
                             size: 112, isLit: true)
                    .phaseAnimator([false, true]) { content, up in
                        content.offset(y: up ? -6 : 6)
                    } animation: { _ in
                        Animation.easeInOut(duration: 1.6)
                    }
                Text(state.category.isEmpty ? "?" : state.category)
                    .font(ShellTheme.display(66, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: accent.opacity(0.7), radius: 18)
                    .id(state.category)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                Divider().background(Color.white.opacity(0.2))
                HStack(spacing: 16) {
                    if !state.answererID.isEmpty {
                        ShellAvatarToken(id: state.answererID, name: state.answererName, size: 64)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THE ANSWERER")
                            .font(ShellTheme.eyebrow(18))
                            .tracking(3)
                            .foregroundColor(ShellTheme.textTertiary)
                        Text(state.answererName.isEmpty ? "Waiting" : state.answererName)
                            .font(ShellTheme.display(36, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(state.phase == "intro" ? "is reading the secret..." : "knows the answer")
                            .font(ShellTheme.display(22, weight: .semibold))
                            .foregroundColor(ShellTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: state.category)
    }
}

// MARK: - Question meter

/// Twenty lights in two rows of ten. Used lights take the colour of their
/// verdict and pop in; the next light breathes.
private struct TwentyQQuestionMeter: View {
    let state: TwentyQBoardState
    let accent: Color

    private var left: Int { max(0, state.maxQuestions - state.questionsUsed) }

    var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("\(left)")
                    .font(ShellTheme.display(110, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(left <= 5 ? TalkPalette.no : .white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: left)
                Text(left == 1 ? "QUESTION LEFT" : "QUESTIONS LEFT")
                    .font(ShellTheme.eyebrow(28))
                    .tracking(4)
                    .foregroundColor(ShellTheme.textSecondary)
            }
            VStack(spacing: 18) {
                lightRow(start: 0)
                lightRow(start: 10)
            }
            if state.phase == "intro" {
                Text("Get ready to ask yes or no questions out loud")
                    .font(ShellTheme.display(28, weight: .bold))
                    .foregroundColor(ShellTheme.textSecondary)
                    .multilineTextAlignment(.center)
            } else if state.phase == "ask" && state.secondsLeft > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                    Text(TwentyQClock.text(state.secondsLeft))
                        .monospacedDigit()
                }
                .font(ShellTheme.display(26, weight: .bold))
                .foregroundColor(state.secondsLeft <= 30 ? TalkPalette.no : ShellTheme.textTertiary)
            }
        }
    }

    private func lightRow(start: Int) -> some View {
        HStack(spacing: 16) {
            ForEach(start..<(start + 10), id: \.self) { index in
                TwentyQLight(number: index + 1,
                             color: state.lightColor(index),
                             isNext: index == state.questionsUsed && state.phase == "ask",
                             accent: accent)
            }
        }
    }
}

private struct TwentyQLight: View {
    let number: Int
    let color: Color?
    let isNext: Bool
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color ?? Color.white.opacity(0.07))
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(color == nil ? 0.05 : 0.55), Color.clear],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0, endRadius: 40))
            Circle()
                .strokeBorder(isNext ? accent : Color.white.opacity(color == nil ? 0.18 : 0.5),
                              lineWidth: isNext ? 4 : 2)
            Text("\(number)")
                .font(ShellTheme.display(24, weight: .heavy))
                .foregroundColor(color == nil ? Color.white.opacity(0.45) : Color.black.opacity(0.75))
        }
        .frame(width: 66, height: 66)
        .shadow(color: (color ?? Color.clear).opacity(0.75), radius: 14)
        .scaleEffect(color == nil ? 0.92 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.45), value: color == nil)
        .phaseAnimator([false, true]) { content, on in
            content.scaleEffect(isNext && on ? 1.1 : 1.0)
        } animation: { _ in
            Animation.easeInOut(duration: 0.6)
        }
    }
}

enum TwentyQClock {
    static func text(_ seconds: Int) -> String {
        let s: Int = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Typing banner

private struct TwentyQTypingBanner: View {
    let names: [String]

    var body: some View {
        ZStack {
            if !names.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(TalkPalette.gold)
                        .symbolEffect(.pulse, options: .repeating)
                    Text(bannerText)
                        .font(ShellTheme.display(32, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Capsule().fill(TalkPalette.wrongGuess.opacity(0.35)))
                .overlay(Capsule().strokeBorder(TalkPalette.wrongGuess, lineWidth: 2))
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .frame(height: 74)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: names)
    }

    private var bannerText: String {
        if names.count == 1 { return "\(names[0]) thinks they know it!" }
        return "\(names.count) players think they know it!"
    }
}

// MARK: - Tally

private struct TwentyQTallyPanel: View {
    let state: TwentyQBoardState

    var body: some View {
        ShellGlassCard(cornerRadius: ShellTheme.cardRadius, tint: ShellTheme.violet, padding: 26) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    tallyChip("YES", state.yesCount, TalkPalette.yes)
                    tallyChip("NO", state.noCount, TalkPalette.no)
                    tallyChip("SOMETIMES", state.sometimesCount, TalkPalette.sometimes)
                }
                Text("THE STORY SO FAR")
                    .font(ShellTheme.eyebrow(18))
                    .tracking(4)
                    .foregroundColor(ShellTheme.textTertiary)
                VStack(alignment: .leading, spacing: 10) {
                    if state.log.isEmpty {
                        Text("No questions yet")
                            .font(ShellTheme.display(24, weight: .semibold))
                            .foregroundColor(ShellTheme.textTertiary)
                    }
                    ForEach(Array(state.log.suffix(7))) { entry in
                        TwentyQLogRow(entry: entry)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: state.log)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tallyChip(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(ShellTheme.display(46, weight: .black))
                .foregroundColor(color)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: count)
            Text(label)
                .font(ShellTheme.eyebrow(label.count > 5 ? 13 : 17))
                .tracking(2)
                .foregroundColor(ShellTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius, style: .continuous).fill(color.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius, style: .continuous)
            .strokeBorder(color.opacity(0.5), lineWidth: 1.5))
    }
}

private struct TwentyQLogRow: View {
    let entry: TwentyQLogEntry

    var body: some View {
        HStack(spacing: 14) {
            Text("Q\(entry.id)")
                .font(ShellTheme.mono(20, weight: .bold))
                .foregroundColor(ShellTheme.textTertiary)
                .frame(width: 56, alignment: .leading)
            if entry.kind == "guess" {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(TalkPalette.wrongGuess)
                Text("\(entry.name): \(entry.text)?")
                    .font(ShellTheme.display(22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .strikethrough(true, color: TalkPalette.wrongGuess)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text(entry.answer.uppercased())
                    .font(ShellTheme.display(24, weight: .black))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TalkPalette.verdictColor(entry.answer)))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Reveal

/// The secret flips over from a question mark, then the verdict and the
/// points land.
private struct TwentyQRevealStage: View {
    let state: TwentyQBoardState
    let accent: Color

    @State private var faceUp: Bool = false
    @State private var detailsShown: Bool = false

    private var secretText: String {
        if !state.secret.isEmpty { return state.secret }
        return state.result?.secret ?? ""
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("IT WAS...")
                .font(ShellTheme.eyebrow(30))
                .tracking(8)
                .foregroundColor(accent)
            TVFlipCard(isFaceUp: faceUp) {
                card(text: secretText, glow: accent, big: true)
            } back: {
                card(text: "?", glow: ShellTheme.violet, big: true)
            }
            .frame(width: 1100, height: 230)
            if let r = state.result {
                verdict(r)
                    .opacity(detailsShown ? 1 : 0)
                    .offset(y: detailsShown ? 0 : 40)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.4)) { faceUp = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(1.2)) { detailsShown = true }
        }
    }

    private func card(text: String, glow: Color, big: Bool) -> some View {
        ZStack {
            ShellGlassSurface(cornerRadius: ShellTheme.cardRadius, tint: glow)
            Text(text)
                .font(ShellTheme.display(big ? 110 : 60, weight: .black))
                .foregroundStyle(LinearGradient(colors: [Color.white, glow],
                                                startPoint: .top, endPoint: .bottom))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .shadow(color: glow.opacity(0.8), radius: 24)
                .padding(.horizontal, 50)
        }
    }

    @ViewBuilder
    private func verdict(_ r: TwentyQRoundResult) -> some View {
        if r.solved {
            VStack(spacing: 18) {
                HStack(spacing: 20) {
                    ShellAvatarToken(id: r.solverID, name: r.solverName, size: 90)
                    Text("\(r.solverName) got it on question \(r.questionNumber)!")
                        .font(ShellTheme.display(46, weight: .heavy))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    TalkPointsChip(points: r.solverPoints)
                }
                if r.goodGame {
                    HStack(spacing: 14) {
                        Image(systemName: "hand.thumbsup.fill")
                            .foregroundColor(accent)
                        Text("Good game, \(r.answererName)! Answerer bonus")
                            .font(ShellTheme.display(32, weight: .bold))
                            .foregroundColor(ShellTheme.textSecondary)
                        TalkPointsChip(points: r.answererPoints, color: accent)
                    }
                }
            }
        } else {
            Text("Nobody got it this time")
                .font(ShellTheme.display(46, weight: .heavy))
                .foregroundColor(ShellTheme.textSecondary)
        }
    }
}
