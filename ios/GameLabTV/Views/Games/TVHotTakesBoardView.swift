import SwiftUI

/// Hot Takes: two players debate a prompt out loud, the room votes.
///
/// Server contract (games/native_hub/engines/talk.py, HotTakesEngine
/// public_state): `phase` runs intro -> for -> switch -> against -> vote ->
/// reveal each round, then "final". `forID`/`againstID` name the debaters,
/// `speakingSide` is "for" / "against" / null, `debateSecondsLeft` counts the
/// whole 60 s debate, `votesSoFar`/`voterCount` track the ballot without
/// saying who voted for whom, and `roundResult` (vote counts, winner,
/// landslide, points) is only present during the reveal.

// MARK: - State

struct HotTakesRoundResult: Equatable {
    var forVotes: Int = 0
    var againstVotes: Int = 0
    var totalVotes: Int = 0
    var winnerSide: String? = nil
    var winnerID: String? = nil
    var winnerName: String = ""
    var tie: Bool = false
    var landslide: Bool = false
    var forPoints: Int = 0
    var againstPoints: Int = 0

    static func parse(_ value: Any?) -> HotTakesRoundResult? {
        guard let d = value as? [String: Any] else { return nil }
        var r = HotTakesRoundResult()
        r.forVotes = d["forVotes"] as? Int ?? 0
        r.againstVotes = d["againstVotes"] as? Int ?? 0
        r.totalVotes = d["totalVotes"] as? Int ?? (r.forVotes + r.againstVotes)
        r.winnerSide = d["winnerSide"] as? String
        r.winnerID = d["winnerID"] as? String
        r.winnerName = d["winnerName"] as? String ?? ""
        r.tie = d["tie"] as? Bool ?? false
        r.landslide = d["landslide"] as? Bool ?? false
        r.forPoints = d["forPoints"] as? Int ?? 0
        r.againstPoints = d["againstPoints"] as? Int ?? 0
        return r
    }
}

struct HotTakesBoardState {
    var round: Int = 0
    var totalRounds: Int = 0
    var phase: String = ""
    var secondsLeft: Int = 0
    var phaseSeconds: Int = 0
    var deadline: Double = 0
    var players: [TalkPlayer] = []
    var submitted: Set<String> = []
    var prompt: String = ""
    var forLabel: String = "YES"
    var againstLabel: String = "NO"
    var forID: String = ""
    var forName: String = ""
    var againstID: String = ""
    var againstName: String = ""
    var speakingSide: String? = nil
    var debateSecondsLeft: Int = 60
    var debateSeconds: Int = 60
    var sideSeconds: Int = 30
    var votesSoFar: Int = 0
    var voterCount: Int = 0
    var result: HotTakesRoundResult? = nil
    var hostPrompt: String = ""

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["round"]?.value as? Int { round = v }
        if let v = d["totalRounds"]?.value as? Int { totalRounds = v }
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["phaseSeconds"]?.value as? Int { phaseSeconds = v }
        deadline = TalkPalette.number(d["deadline"]?.value) ?? 0
        players = TalkPlayer.list(from: d["players"]?.value)
        let ids: [Any] = d["submittedPlayerIDs"]?.value as? [Any] ?? []
        submitted = Set(ids.compactMap { $0 as? String })
        if let v = d["prompt"]?.value as? String { prompt = v }
        if let v = d["forLabel"]?.value as? String { forLabel = v }
        if let v = d["againstLabel"]?.value as? String { againstLabel = v }
        forID = d["forID"]?.value as? String ?? ""
        forName = d["forName"]?.value as? String ?? ""
        againstID = d["againstID"]?.value as? String ?? ""
        againstName = d["againstName"]?.value as? String ?? ""
        speakingSide = d["speakingSide"]?.value as? String
        if let v = d["debateSecondsLeft"]?.value as? Int { debateSecondsLeft = v }
        if let v = d["debateSeconds"]?.value as? Int { debateSeconds = v }
        if let v = d["sideSeconds"]?.value as? Int { sideSeconds = v }
        if let v = d["votesSoFar"]?.value as? Int { votesSoFar = v }
        if let v = d["voterCount"]?.value as? Int { voterCount = v }
        result = HotTakesRoundResult.parse(d["roundResult"]?.value)
        if let v = d["hostPrompt"]?.value as? String { hostPrompt = v }
    }
}

// MARK: - Board

struct TVHotTakesBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: HotTakesBoardState()) { $0.update(from: $1) }
    /// The TV reads the prompt and the big beats aloud.
    @StateObject private var voice = TVVoiceHost()
    @State private var confettiKey: Int = 0
    @State private var spokenKey: String = ""

    private var state: HotTakesBoardState { vm.state }
    private var phase: String { vm.state.phase }

    var body: some View {
        ZStack {
            TalkStageBackground(leftColor: TalkPalette.forColor,
                                leftStrength: forLight,
                                rightColor: TalkPalette.againstColor,
                                rightStrength: againstLight)
            VStack(spacing: 22) {
                TalkTopBar(symbol: "flame.fill", title: "Hot Takes",
                           round: state.round, totalRounds: state.totalRounds,
                           phaseLabel: phaseLabel, accent: accent)
                HotTakesPromptCard(prompt: state.prompt, round: state.round,
                                   forLabel: state.forLabel, againstLabel: state.againstLabel)
                    .padding(.horizontal, 110)
                arena
                    .padding(.horizontal, 70)
                    .frame(maxHeight: .infinity)
                TalkPodRow(players: state.players, badges: podBadges,
                           checked: phase == "vote" ? state.submitted : [],
                           spotlight: spotlight)
                    .padding(.bottom, 26)
            }
            if phase == "switch" {
                HotTakesSwitchOverlay(nextName: state.againstName)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if confettiKey > 0 {
                ShellConfetti(particleCount: 140, duration: 4.5,
                              origin: UnitPoint(x: 0.5, y: 0.35), seed: confettiKey)
                    .id(confettiKey)
                    .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: phase)
        .onAppear { vm.bind(roomCode: room.code) }
        .onDisappear { voice.stopSpeaking() }
        .onChange(of: vm.state.phase) { _, newPhase in
            phaseChanged(newPhase)
        }
        .onChange(of: vm.state.votesSoFar) { oldValue, newValue in
            if newValue > oldValue { SoundPlayer.shared.playClick(volume: 0.45) }
        }
    }

    // MARK: Derived

    private var accent: Color {
        switch phase {
        case "against": return TalkPalette.againstColor
        case "vote", "reveal": return ShellTheme.violet
        default: return TalkPalette.forColor
        }
    }

    private var forLight: Double {
        switch phase {
        case "for": return 1.0
        case "against", "switch": return 0.25
        case "reveal": return state.result?.winnerSide == "for" ? 1.0 : 0.3
        default: return 0.6
        }
    }

    private var againstLight: Double {
        switch phase {
        case "against": return 1.0
        case "for": return 0.25
        case "switch": return 0.8
        case "reveal": return state.result?.winnerSide == "against" ? 1.0 : 0.3
        default: return 0.6
        }
    }

    private var phaseLabel: String {
        switch phase {
        case "intro": return "Get ready"
        case "for": return "\(state.forName) argues FOR"
        case "switch": return "Switch"
        case "against": return "\(state.againstName) argues AGAINST"
        case "vote": return "Vote on your phone"
        case "reveal": return "The verdict"
        case "final": return "Final scores"
        default: return ""
        }
    }

    private var podBadges: [String: TalkPodBadge] {
        var out: [String: TalkPodBadge] = [:]
        if !state.forID.isEmpty {
            out[state.forID] = TalkPodBadge(text: "FOR", color: TalkPalette.forColor)
        }
        if !state.againstID.isEmpty {
            out[state.againstID] = TalkPodBadge(text: "AGAINST", color: TalkPalette.againstColor)
        }
        if phase == "reveal", let winner = state.result?.winnerID, !winner.isEmpty {
            out[winner] = TalkPodBadge(text: "WINNER", color: TalkPalette.gold)
        }
        return out
    }

    private var spotlight: Set<String> {
        switch phase {
        case "for": return state.forID.isEmpty ? [] : [state.forID]
        case "against": return state.againstID.isEmpty ? [] : [state.againstID]
        case "reveal":
            if let winner = state.result?.winnerID, !winner.isEmpty { return [winner] }
            return []
        default: return []
        }
    }

    // MARK: Arena

    private var arena: some View {
        HStack(alignment: .center, spacing: 36) {
            HotTakesDebaterPanel(side: "FOR", stance: state.forLabel,
                                 playerID: state.forID, name: state.forName,
                                 color: TalkPalette.forColor, color2: TalkPalette.forColor2,
                                 isActive: phase == "for",
                                 isDimmed: phase == "against" || phase == "switch",
                                 isWinner: phase == "reveal" && state.result?.winnerSide == "for",
                                 points: phase == "reveal" ? state.result?.forPoints : nil,
                                 entranceEdge: .leading)
                .frame(maxWidth: .infinity)
            center
                .frame(width: 560)
            HotTakesDebaterPanel(side: "AGAINST", stance: state.againstLabel,
                                 playerID: state.againstID, name: state.againstName,
                                 color: TalkPalette.againstColor, color2: TalkPalette.againstColor2,
                                 isActive: phase == "against",
                                 isDimmed: phase == "for",
                                 isWinner: phase == "reveal" && state.result?.winnerSide == "against",
                                 points: phase == "reveal" ? state.result?.againstPoints : nil,
                                 entranceEdge: .trailing)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var center: some View {
        switch phase {
        case "vote":
            HotTakesVoteStatus(votesSoFar: state.votesSoFar, voterCount: state.voterCount,
                               secondsLeft: state.secondsLeft, phaseSeconds: state.phaseSeconds)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        case "reveal":
            if let result = state.result {
                HotTakesRevealBars(result: result,
                                   forName: state.forName, againstName: state.againstName)
                    .id("reveal-\(state.round)")
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        case "final":
            VStack(spacing: 14) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 80, weight: .bold))
                    .foregroundColor(TalkPalette.gold)
                    .shadow(color: TalkPalette.gold.opacity(0.7), radius: 20)
                Text("That is a wrap!")
                    .font(ShellTheme.display(46, weight: .black))
                    .foregroundColor(.white)
            }
            .transition(.opacity)
        default:
            HotTakesDebateClock(phase: phase,
                                secondsLeft: state.secondsLeft,
                                debateSecondsLeft: state.debateSecondsLeft,
                                sideSeconds: max(1, state.sideSeconds))
                .transition(.opacity)
        }
    }

    // MARK: Beats

    private func phaseChanged(_ newPhase: String) {
        switch newPhase {
        case "for", "against":
            SoundPlayer.shared.play(.ladderClimb, volume: 0.6)
        case "switch":
            SoundPlayer.shared.play(.connect4Drop, volume: 0.9)
        case "reveal":
            if let result = state.result, !result.tie {
                confettiKey += 1
                SoundPlayer.shared.play(.winFanfare, volume: result.landslide ? 0.9 : 0.6)
            }
        default:
            break
        }
        speakIfNeeded(newPhase)
    }

    private func speakIfNeeded(_ newPhase: String) {
        guard ["intro", "switch", "vote", "reveal"].contains(newPhase) else { return }
        let key: String = "\(state.round)-\(newPhase)"
        guard key != spokenKey else { return }
        spokenKey = key
        if newPhase == "switch" {
            voice.speak("Switch!")
        } else {
            voice.speak(state.hostPrompt)
        }
    }
}

// MARK: - Prompt

private struct HotTakesPromptCard: View {
    let prompt: String
    let round: Int
    let forLabel: String
    let againstLabel: String

    @State private var flip: Double = 0

    private var fontSize: CGFloat {
        let n: Int = prompt.count
        if n < 40 { return 66 }
        if n < 70 { return 56 }
        return 46
    }

    var body: some View {
        ShellGlassCard(cornerRadius: 40, tint: ShellTheme.pink, padding: 34) {
            VStack(spacing: 14) {
                Text("THE HOT TAKE")
                    .font(ShellTheme.eyebrow(22))
                    .tracking(6)
                    .foregroundColor(TalkPalette.forColor)
                Text(prompt.isEmpty ? " " : prompt)
                    .font(ShellTheme.display(fontSize, weight: .black))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                    .frame(maxWidth: .infinity)
            }
        }
        .rotation3DEffect(.degrees(flip), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .opacity(abs(flip) > 80 ? 0 : 1)
        .onChange(of: prompt) { _, _ in
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { flip = -90 }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.05)) { flip = 0 }
        }
    }
}

// MARK: - Debater panel

private struct HotTakesDebaterPanel: View {
    let side: String
    let stance: String
    let playerID: String
    let name: String
    let color: Color
    let color2: Color
    let isActive: Bool
    let isDimmed: Bool
    let isWinner: Bool
    let points: Int?
    let entranceEdge: HorizontalEdge

    var body: some View {
        VStack(spacing: 16) {
            Text(side)
                .font(ShellTheme.display(44, weight: .black))
                .tracking(6)
                .foregroundStyle(LinearGradient(colors: [Color.white, color],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: color.opacity(0.8), radius: 14)
            Text(stance)
                .font(ShellTheme.eyebrow(22))
                .tracking(3)
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(color))
            ZStack {
                if isActive {
                    HotTakesSoundWaves(color: color)
                        .frame(width: 230, height: 230)
                }
                if playerID.isEmpty {
                    ShellGhostToken(size: 130)
                } else {
                    ShellAvatarToken(id: playerID, name: name, size: 130)
                }
            }
            .frame(height: 200)
            Text(name.isEmpty ? "Waiting" : name)
                .font(ShellTheme.display(40, weight: .heavy))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            ZStack {
                if isActive {
                    Text("TALK NOW")
                        .font(ShellTheme.eyebrow(22))
                        .tracking(5)
                        .foregroundColor(color)
                        .phaseAnimator([false, true]) { content, on in
                            content.opacity(on ? 1 : 0.45)
                        } animation: { _ in
                            Animation.easeInOut(duration: 0.6)
                        }
                } else if let points, points > 0 {
                    TalkPointsChip(points: points, color: isWinner ? TalkPalette.gold : color)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 44)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background {
            ShellGlassSurface(cornerRadius: 36, tint: color)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(LinearGradient(colors: [color, color2],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: isActive || isWinner ? 5 : 0)
        }
        .shadow(color: color.opacity(isActive || isWinner ? 0.6 : 0), radius: 40)
        .scaleEffect(isActive || isWinner ? 1.05 : (isDimmed ? 0.94 : 1.0))
        .opacity(isDimmed ? 0.55 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isActive)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isDimmed)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isWinner)
        .tvStaggeredAppear(index: entranceEdge == .leading ? 0 : 1, step: 0.15)
    }
}

/// Rings rippling out from the speaker's token.
private struct HotTakesSoundWaves: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t: Double = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius: CGFloat = min(size.width, size.height) / 2
                for i in 0..<3 {
                    let phase: Double = (t * 0.7 + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                    let radius: CGFloat = maxRadius * CGFloat(0.55 + 0.45 * phase)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect),
                                   with: .color(color.opacity(0.7 * (1 - phase))),
                                   lineWidth: 5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Debate clock

/// The 60 s debate as one ring: the FOR half (left, warm) drains first,
/// then the AGAINST half (right, cool). The number is the current side's
/// seconds.
private struct HotTakesDebateClock: View {
    let phase: String
    let secondsLeft: Int
    let debateSecondsLeft: Int
    let sideSeconds: Int

    private var forRemaining: CGFloat {
        let left: Int = max(0, debateSecondsLeft - sideSeconds)
        return min(1, CGFloat(left) / CGFloat(sideSeconds))
    }

    private var againstRemaining: CGFloat {
        let left: Int = min(sideSeconds, max(0, debateSecondsLeft))
        return min(1, CGFloat(left) / CGFloat(sideSeconds))
    }

    private var centerNumber: Int {
        switch phase {
        case "for", "against": return secondsLeft
        default: return sideSeconds
        }
    }

    private var centerLabel: String {
        switch phase {
        case "for": return "FOR"
        case "against": return "AGAINST"
        case "switch": return "SWITCH"
        default: return "GET READY"
        }
    }

    private var centerColor: Color {
        phase == "against" || phase == "switch" ? TalkPalette.againstColor : TalkPalette.forColor
    }

    private var urgent: Bool {
        (phase == "for" || phase == "against") && secondsLeft <= 5
    }

    var body: some View {
        let size: CGFloat = 400
        let line: CGFloat = 30
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: line)
            // Right half, anchored at the top: AGAINST.
            Circle()
                .trim(from: 0, to: 0.5 * againstRemaining)
                .stroke(LinearGradient(colors: [TalkPalette.againstColor, TalkPalette.againstColor2],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: TalkPalette.againstColor.opacity(phase == "against" ? 0.8 : 0.2), radius: 18)
            // Left half, anchored at the top: FOR.
            Circle()
                .trim(from: 1 - 0.5 * forRemaining, to: 1)
                .stroke(LinearGradient(colors: [TalkPalette.forColor, TalkPalette.forColor2],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: TalkPalette.forColor.opacity(phase == "for" ? 0.8 : 0.2), radius: 18)
            VStack(spacing: 4) {
                Text("\(centerNumber)")
                    .font(ShellTheme.display(150, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(urgent ? TalkPalette.no : .white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: centerNumber)
                Text(centerLabel)
                    .font(ShellTheme.eyebrow(28))
                    .tracking(6)
                    .foregroundColor(centerColor)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(urgent && secondsLeft % 2 == 1 ? 1.05 : 1.0)
        .animation(.linear(duration: 1), value: debateSecondsLeft)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: secondsLeft)
    }
}

// MARK: - Switch beat

private struct HotTakesSwitchOverlay: View {
    let nextName: String

    @State private var spin: Double = -30
    @State private var shown: Bool = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 120, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [TalkPalette.forColor, TalkPalette.againstColor],
                                                    startPoint: .leading, endPoint: .trailing))
                    .rotationEffect(.degrees(spin))
                Text("SWITCH!")
                    .font(ShellTheme.display(200, weight: .black))
                    .foregroundStyle(LinearGradient(colors: [TalkPalette.forColor, Color.white,
                                                             TalkPalette.againstColor],
                                                    startPoint: .leading, endPoint: .trailing))
                    .shadow(color: TalkPalette.againstColor.opacity(0.8), radius: 30)
                if !nextName.isEmpty {
                    Text("\(nextName), you are up")
                        .font(ShellTheme.display(46, weight: .heavy))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(shown ? 1.0 : 0.3)
            .rotationEffect(.degrees(shown ? 0 : -8))
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { shown = true }
            withAnimation(.easeInOut(duration: 1.2)) { spin = 180 }
        }
    }
}

// MARK: - Vote status

private struct HotTakesVoteStatus: View {
    let votesSoFar: Int
    let voterCount: Int
    let secondsLeft: Int
    let phaseSeconds: Int

    var body: some View {
        VStack(spacing: 22) {
            Text("WHO ARGUED BETTER?")
                .font(ShellTheme.display(36, weight: .black))
                .tracking(2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            TalkTimerRing(secondsLeft: secondsLeft, total: max(1, phaseSeconds),
                          tint: ShellTheme.violet, label: "VOTE", size: 220)
            HStack(spacing: 12) {
                ForEach(0..<max(voterCount, 0), id: \.self) { i in
                    Circle()
                        .fill(i < votesSoFar ? TalkPalette.gold : Color.white.opacity(0.15))
                        .frame(width: 26, height: 26)
                        .scaleEffect(i < votesSoFar ? 1.15 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: votesSoFar)
                }
            }
            Text("\(votesSoFar) of \(voterCount) votes in")
                .font(ShellTheme.display(28, weight: .bold))
                .foregroundColor(ShellTheme.textSecondary)
                .contentTransition(.numericText())
                .animation(.default, value: votesSoFar)
        }
    }
}

// MARK: - Reveal

/// Two vote columns that grow to their share, counted up one vote at a
/// time, then the verdict stamp.
private struct HotTakesRevealBars: View {
    let result: HotTakesRoundResult
    let forName: String
    let againstName: String

    @State private var grown: Bool = false
    @State private var stamped: Bool = false

    private var maxVotes: Int { max(1, max(result.forVotes, result.againstVotes)) }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .bottom, spacing: 50) {
                column(votes: result.forVotes, label: "FOR",
                       color: TalkPalette.forColor, isWinner: result.winnerSide == "for")
                column(votes: result.againstVotes, label: "AGAINST",
                       color: TalkPalette.againstColor, isWinner: result.winnerSide == "against")
            }
            .frame(height: 330)
            verdict
                .scaleEffect(stamped ? 1.0 : 2.2)
                .opacity(stamped ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.75).delay(0.2)) { grown = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55).delay(1.3)) { stamped = true }
        }
    }

    private func column(votes: Int, label: String, color: Color, isWinner: Bool) -> some View {
        let fullHeight: CGFloat = 240
        let height: CGFloat = grown ? max(14, fullHeight * CGFloat(votes) / CGFloat(maxVotes)) : 14
        return VStack(spacing: 10) {
            Text("\(grown ? votes : 0)")
                .font(ShellTheme.display(54, weight: .black))
                .foregroundColor(.white)
                .contentTransition(.numericText())
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.9), color],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 150, height: height)
                .shadow(color: color.opacity(isWinner ? 0.9 : 0.3), radius: isWinner ? 28 : 8)
            Text(label)
                .font(ShellTheme.eyebrow(24))
                .tracking(4)
                .foregroundColor(color)
        }
    }

    @ViewBuilder
    private var verdict: some View {
        if result.totalVotes == 0 {
            Text("NO VOTES")
                .font(ShellTheme.display(44, weight: .black))
                .foregroundColor(ShellTheme.textSecondary)
        } else if result.tie {
            Text("DEAD HEAT!")
                .font(ShellTheme.display(52, weight: .black))
                .foregroundColor(TalkPalette.gold)
        } else {
            VStack(spacing: 6) {
                if result.landslide {
                    Text("LANDSLIDE!")
                        .font(ShellTheme.display(56, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(TalkPalette.gold))
                        .rotationEffect(.degrees(-4))
                        .shadow(color: TalkPalette.gold.opacity(0.8), radius: 20)
                }
                Text("\(result.winnerName) wins!")
                    .font(ShellTheme.display(46, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }
}
