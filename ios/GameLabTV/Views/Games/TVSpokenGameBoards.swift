import SwiftUI

/// TV boards for the two SPOKEN games: Atlas and Antakshari.
///
/// Nobody types in either game. People talk (Atlas) or sing (Antakshari)
/// out loud; the TV is the host and the scoreboard; phones only tap
/// (Valid / Out!, Sang it / Missed, and a 26-letter grid for the last
/// letter). So the TV carries everything the room needs to see from across
/// the sofa: a huge animated letter, whose turn it is, a timer ring, the
/// chain so far, lives or team scores, and a big verdict flash. It also
/// says the next letter out loud through `TVVoiceHost`.
///
/// Server side: games/native_hub/engines/spoken.py.

// MARK: - Shared pieces

/// A verdict from `boardState["verdict"]`. `seq` increases on every new
/// verdict, so the flash replays even for two Valid!s in a row.
struct SpokenVerdict: Equatable {
    let kind: String
    let seq: Int
    let name: String
    let team: Int
    let livesLeft: Int
    let eliminated: Bool

    static func parse(_ value: Any?) -> SpokenVerdict? {
        guard let d = value as? [String: Any],
              let kind = d["kind"] as? String else { return nil }
        let name: String = (d["name"] as? String) ?? (d["teamName"] as? String) ?? ""
        return SpokenVerdict(kind: kind,
                             seq: d["seq"] as? Int ?? 0,
                             name: name,
                             team: d["team"] as? Int ?? -1,
                             livesLeft: d["livesLeft"] as? Int ?? 0,
                             eliminated: d["eliminated"] as? Bool ?? false)
    }
}

/// The "skip to a new letter" rule firing (Q, X, Z, or nobody tapped one).
struct SpokenSkip: Equatable {
    let from: String
    let to: String
    let reason: String

    static func parse(_ value: Any?) -> SpokenSkip? {
        guard let d = value as? [String: Any],
              let to = d["to"] as? String else { return nil }
        return SpokenSkip(from: d["from"] as? String ?? "", to: to,
                          reason: d["reason"] as? String ?? "")
    }

    var caption: String {
        if from.isEmpty || reason == "timeout" {
            return "No letter tapped -- new letter \(to)"
        }
        return "\(from) is too tough -- new letter \(to)"
    }
}

enum SpokenTVStyle {
    static let valid: Color = TVTheme.green
    static let out: Color = TVTheme.red
    static let warn: Color = TVTheme.orange

    /// Team colour names come from games/teams.py ("red", "blue", ...).
    static func teamColor(_ name: String, index: Int) -> Color {
        switch name.lowercased() {
        case "red": return TVTheme.red
        case "blue": return TVTheme.blue
        case "green": return TVTheme.green
        case "yellow", "gold": return TVTheme.yellow
        default: return index == 0 ? ShellTheme.cyan : ShellTheme.pink
        }
    }

    static func clock(_ seconds: Int) -> String {
        let safe: Int = max(0, seconds)
        return String(format: "%d:%02d", safe / 60, safe % 60)
    }
}

/// A big countdown ring that turns orange, then red, in the last seconds.
struct SpokenTimerRing: View {
    let secondsLeft: Int
    let total: Int
    var tint: Color = ShellTheme.cyan
    var size: CGFloat = 190

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        let ratio: Double = Double(secondsLeft) / Double(total)
        return CGFloat(min(1.0, max(0.0, ratio)))
    }

    private var ringColor: Color {
        if secondsLeft <= 3 { return SpokenTVStyle.out }
        if secondsLeft <= 5 { return SpokenTVStyle.warn }
        return tint
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: ringColor.opacity(0.8), radius: 14)
                .animation(.linear(duration: 1), value: secondsLeft)
            VStack(spacing: 0) {
                TVPopNumber(value: secondsLeft, size: size * 0.34, color: ringColor)
                Text("SEC")
                    .font(ShellTheme.eyebrow(18))
                    .tracking(4)
                    .foregroundColor(ShellTheme.textTertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// The full-screen "Valid!" / "Out!" stamp. Plays whenever `seq` changes,
/// then fades by itself; a board that appears mid-game never flashes a
/// stale verdict because `onChange` does not fire for the initial value.
struct SpokenVerdictFlash: View {
    let seq: Int
    let text: String
    let detail: String
    let tint: Color
    let symbol: String

    @State private var visible: Bool = false
    @State private var shownSeq: Int = 0

    var body: some View {
        ZStack {
            if visible {
                VStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 110, weight: .heavy, design: .rounded))
                    Text(text)
                        .font(ShellTheme.display(150))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(LinearGradient(colors: [Color.white, tint],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: tint.opacity(0.9), radius: 30)
                .padding(.horizontal, 100)
                .padding(.vertical, 50)
                .background {
                    RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                        .fill(ShellTheme.ink.opacity(0.78))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.85), lineWidth: 5)
                }
                .rotationEffect(.degrees(-4))
                .transition(.scale(scale: 0.35).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .onChange(of: seq) { _, newSeq in
            guard newSeq > 0 else { return }
            shownSeq = newSeq
            withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                visible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                guard shownSeq == newSeq else { return }
                withAnimation(.easeIn(duration: 0.3)) {
                    visible = false
                }
            }
        }
    }
}

/// A small pill: the "skip to a new letter" rule firing, or a hint.
private struct SpokenBanner: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(text)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background { Capsule().fill(tint.opacity(0.16)) }
        .overlay { Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1.5) }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

// MARK: - Atlas state

struct SpokenAtlasPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    let lives: Int
    let isOut: Bool
    let places: Int
    let isSpeaker: Bool
}

struct SpokenAtlasStop: Identifiable, Equatable {
    /// Position in the whole chain (0 = the seed), stable as the window slides.
    let id: Int
    let name: String
    let place: String
    let letter: String
    let endLetter: String
    let isSeed: Bool
}

struct SpokenAtlasBoardState {
    var phase: String = ""
    var round: Int = 0
    var letter: String = ""
    var secondsLeft: Int = 0
    var phaseSeconds: Int = 10
    var currentPlayerID: String = ""
    var currentName: String = ""
    var chain: [SpokenAtlasStop] = []
    var chainLength: Int = 0
    var maxLives: Int = 3
    var players: [SpokenAtlasPlayer] = []
    var validVotes: Int = 0
    var outVotes: Int = 0
    var votesNeeded: Int = 0
    var verdict: SpokenVerdict? = nil
    var skipped: SpokenSkip? = nil
    var spelling: Bool = false
    var finished: Bool = false
    var winnerName: String = ""

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["round"]?.value as? Int { round = v }
        if let v = d["letter"]?.value as? String { letter = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["phaseSeconds"]?.value as? Int { phaseSeconds = v }
        currentPlayerID = d["currentPlayerID"]?.value as? String ?? ""
        if let v = d["currentName"]?.value as? String { currentName = v }
        if let v = d["chainLength"]?.value as? Int { chainLength = v }
        if let v = d["maxLives"]?.value as? Int { maxLives = v }
        if let v = d["spelling"]?.value as? Bool { spelling = v }
        if let v = d["finished"]?.value as? Bool { finished = v }
        winnerName = d["winnerName"]?.value as? String ?? ""
        verdict = SpokenVerdict.parse(d["verdict"]?.value)
        skipped = SpokenSkip.parse(d["skipped"]?.value)

        if let votes = d["votes"]?.value as? [String: Any] {
            validVotes = votes["valid"] as? Int ?? 0
            outVotes = votes["out"] as? Int ?? 0
            votesNeeded = votes["needed"] as? Int ?? 0
        }

        let rawChain: [Any] = d["chain"]?.value as? [Any] ?? []
        let firstID: Int = max(0, chainLength + 1 - rawChain.count)
        var stops: [SpokenAtlasStop] = []
        for (offset, item) in rawChain.enumerated() {
            guard let c = item as? [String: Any] else { continue }
            let isSeed: Bool = !(c["playerID"] is String)
            stops.append(SpokenAtlasStop(id: firstID + offset,
                                         name: c["name"] as? String ?? "",
                                         place: c["place"] as? String ?? "",
                                         letter: c["letter"] as? String ?? "",
                                         endLetter: c["endLetter"] as? String ?? "",
                                         isSeed: isSeed))
        }
        chain = stops

        let rawPlayers: [Any] = d["players"]?.value as? [Any] ?? []
        players = rawPlayers.compactMap { item -> SpokenAtlasPlayer? in
            guard let p = item as? [String: Any], let id = p["id"] as? String else { return nil }
            return SpokenAtlasPlayer(id: id,
                                     name: p["name"] as? String ?? "Player",
                                     lives: p["lives"] as? Int ?? 0,
                                     isOut: p["isOut"] as? Bool ?? false,
                                     places: p["places"] as? Int ?? 0,
                                     isSpeaker: p["isSpeaker"] as? Bool ?? false)
        }
    }
}

// MARK: - Atlas board

struct TVAtlasBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: SpokenAtlasBoardState()) { $0.update(from: $1) }
    /// The TV says the next letter out loud; it never listens.
    @StateObject private var voice = TVVoiceHost()
    @State private var spokenLetter: String = ""

    private let palette: TVPalette = TVTheme.jungle

    private var state: SpokenAtlasBoardState { vm.state }
    private var turnKey: String { "\(state.round):\(state.phase)" }
    private var aliveCount: Int { state.players.filter { !$0.isOut }.count }

    var body: some View {
        ZStack {
            ShellAmbientBackground()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 10)
                stage
                Spacer(minLength: 10)
                chainRibbon
                pods
            }
            .padding(.horizontal, 70)
            .padding(.top, 40)
            .padding(.bottom, 34)

            SpokenVerdictFlash(seq: state.verdict?.seq ?? 0,
                               text: verdictText,
                               detail: verdictDetail,
                               tint: verdictTint,
                               symbol: verdictSymbol)

            if state.finished {
                TVWinnerBanner(title: "Last one standing",
                               headline: state.winnerName.isEmpty ? "Game over" : state.winnerName,
                               detail: "\(state.chainLength) places in the chain",
                               symbol: "globe")
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.phase)
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: turnKey) { _, _ in announceTurn() }
        .onDisappear { voice.stopSpeaking() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 22) {
            ShellIconOrb(symbol: "globe", top: ShellTheme.mint, bottom: ShellTheme.blue,
                         accent: ShellTheme.cyan, size: 76, isLit: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ATLAS")
                    .font(ShellTheme.eyebrow(22))
                    .tracking(6)
                    .foregroundColor(ShellTheme.textTertiary)
                Text("Say a place out loud")
                    .font(ShellTheme.display(40))
                    .foregroundColor(.white)
            }
            Spacer()
            if state.spelling {
                ShellChip(systemImage: "textformat.abc", text: "Spelling mode", tint: ShellTheme.gold)
            }
            ShellChip(systemImage: "link", text: "\(state.chainLength) in the chain", tint: ShellTheme.cyan)
            ShellChip(systemImage: "person.3.fill",
                      text: "\(aliveCount) of \(state.players.count) still in",
                      tint: ShellTheme.mint)
        }
    }

    // MARK: Stage

    private var stage: some View {
        HStack(alignment: .center, spacing: 70) {
            VStack(spacing: 14) {
                Text(letterCaption)
                    .font(ShellTheme.eyebrow(26))
                    .tracking(6)
                    .foregroundColor(ShellTheme.textSecondary)
                TVHeroLetter(letter: state.letter, palette: palette, tileSize: 290)
                if let skip = state.skipped {
                    SpokenBanner(systemImage: "forward.fill", text: skip.caption, tint: ShellTheme.gold)
                }
            }
            .frame(width: 520)

            VStack(alignment: .leading, spacing: 26) {
                speakerCard
                if state.phase == "say" {
                    HStack(spacing: 34) {
                        SpokenTimerRing(secondsLeft: state.secondsLeft,
                                        total: state.phaseSeconds,
                                        tint: palette.accent,
                                        size: 180)
                        voteMeter
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if state.phase == "letter" {
                    SpokenBanner(systemImage: "hand.tap.fill",
                                 text: "\(state.currentName) is tapping the last letter",
                                 tint: ShellTheme.cyan)
                }
            }
            .frame(width: 780, alignment: .leading)
        }
    }

    private var letterCaption: String {
        state.phase == "letter" ? "THAT PLACE STARTED WITH" : "NEXT PLACE STARTS WITH"
    }

    private var speakerCard: some View {
        ShellGlassCard(cornerRadius: ShellTheme.cardRadius, tint: ShellTheme.cyan, padding: 26) {
            HStack(spacing: 24) {
                ShellAvatarToken(id: state.currentPlayerID.isEmpty ? "none" : state.currentPlayerID,
                                 name: state.currentName, size: 104)
                    .shellHop(trigger: state.round, height: 26)
                VStack(alignment: .leading, spacing: 6) {
                    Text(speakerEyebrow)
                        .font(ShellTheme.eyebrow(22))
                        .tracking(5)
                        .foregroundColor(ShellTheme.cyan)
                    Text(state.currentName.isEmpty ? "Get ready" : state.currentName)
                        .font(ShellTheme.display(56))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(speakerPrompt)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(ShellTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var speakerEyebrow: String {
        switch state.phase {
        case "say": return "YOUR TURN"
        case "letter": return "NICE ONE"
        case "verdict": return "THE ROOM HAS SPOKEN"
        default: return "ATLAS"
        }
    }

    private var speakerPrompt: String {
        switch state.phase {
        case "say": return "Say a place starting with \(state.letter)"
        case "letter": return "Tap the last letter of your place"
        case "verdict": return "Same letter for the next player"
        default: return ""
        }
    }

    private var voteMeter: some View {
        VStack(alignment: .leading, spacing: 14) {
            voteRow(symbol: "checkmark.circle.fill", label: "Valid",
                    count: state.validVotes, tint: SpokenTVStyle.valid)
            voteRow(symbol: "xmark.circle.fill", label: "Out!",
                    count: state.outVotes, tint: SpokenTVStyle.out)
            if state.votesNeeded > 0 {
                Text("\(state.votesNeeded) taps decide it")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
            }
        }
    }

    private func voteRow(symbol: String, label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 110, alignment: .leading)
            TVPopNumber(value: count, size: 44, color: tint)
        }
    }

    // MARK: Chain ribbon

    private var chainRibbon: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(state.chain) { stop in
                        SpokenAtlasStopView(stop: stop, isLatest: stop.id == state.chain.last?.id)
                            .id(stop.id)
                            .tvStaggeredAppear(index: 0)
                        if stop.id != state.chain.last?.id {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(palette.accent.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .onChange(of: state.chain.last?.id ?? -1) { _, newID in
                guard newID >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(newID, anchor: .trailing)
                }
            }
        }
        .frame(height: 150)
    }

    // MARK: Player pods

    private var pods: some View {
        let tokenSize: CGFloat = state.players.count > 8 ? 58 : 74
        return HStack(spacing: 22) {
            ForEach(state.players) { player in
                SpokenAtlasPod(player: player, maxLives: state.maxLives, tokenSize: tokenSize)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Verdict

    private var verdictText: String {
        switch state.verdict?.kind ?? "" {
        case "valid": return "VALID!"
        case "out": return "OUT!"
        case "timeout": return "TIME!"
        default: return ""
        }
    }

    private var verdictDetail: String {
        guard let verdict = state.verdict else { return "" }
        switch verdict.kind {
        case "valid":
            return "\(verdict.name) keeps the chain going"
        default:
            if verdict.eliminated { return "\(verdict.name) is out of the game" }
            let lives: String = verdict.livesLeft == 1 ? "1 life left" : "\(verdict.livesLeft) lives left"
            return "\(verdict.name): \(lives)"
        }
    }

    private var verdictTint: Color {
        switch state.verdict?.kind ?? "" {
        case "valid": return SpokenTVStyle.valid
        case "out": return SpokenTVStyle.out
        default: return SpokenTVStyle.warn
        }
    }

    private var verdictSymbol: String {
        switch state.verdict?.kind ?? "" {
        case "valid": return "checkmark.seal.fill"
        case "out": return "xmark.octagon.fill"
        default: return "timer"
        }
    }

    // MARK: Voice

    private func announceTurn() {
        guard state.phase == "say", !state.finished, !state.letter.isEmpty else { return }
        var line: String = ""
        if state.letter != spokenLetter {
            if let skip = state.skipped, skip.to == state.letter, !skip.from.isEmpty, skip.reason == "hard" {
                line = "\(skip.from) is too tough. "
            }
            line += "Next letter: \(state.letter)."
        } else {
            line = "Still \(state.letter)."
        }
        if !state.currentName.isEmpty {
            line += " \(state.currentName), your turn."
        }
        spokenLetter = state.letter
        voice.speak(line)
    }
}

private struct SpokenAtlasStopView: View {
    let stop: SpokenAtlasStop
    let isLatest: Bool

    var body: some View {
        let tint: Color = isLatest ? ShellTheme.gold : ShellTheme.cyan
        let shape = RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(stop.letter)
                    .font(ShellTheme.display(34))
                    .foregroundColor(.white)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
                Text(stop.endLetter.isEmpty ? "?" : stop.endLetter)
                    .font(ShellTheme.display(34))
                    .foregroundColor(ShellTheme.gold)
            }
            if !stop.place.isEmpty {
                Text(stop.place)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            Text(stop.isSeed ? "Start" : stop.name)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(ShellTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .frame(minWidth: 130)
        .background {
            ZStack {
                shape.fill(ShellTheme.panel.opacity(0.7))
                shape.fill(tint.opacity(isLatest ? 0.22 : 0.08))
                shape.strokeBorder(tint.opacity(isLatest ? 0.9 : 0.3), lineWidth: isLatest ? 3 : 1.5)
            }
        }
        .scaleEffect(isLatest ? 1.06 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isLatest)
    }
}

private struct SpokenAtlasPod: View {
    let player: SpokenAtlasPlayer
    let maxLives: Int
    let tokenSize: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ShellAvatarToken(id: player.id, name: player.name, size: tokenSize)
                .overlay {
                    Circle()
                        .strokeBorder(ShellTheme.gold, lineWidth: 4)
                        .padding(-9)
                        .opacity(player.isSpeaker ? 1 : 0)
                        .shadow(color: ShellTheme.gold.opacity(0.8), radius: 10)
                }
                .scaleEffect(player.isSpeaker ? 1.12 : 1.0)
            Text(player.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                ForEach(0..<max(maxLives, 0), id: \.self) { index in
                    Image(systemName: index < player.lives ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(index < player.lives ? SpokenTVStyle.out : Color.white.opacity(0.25))
                }
            }
        }
        .frame(width: 128)
        .saturation(player.isOut ? 0 : 1)
        .opacity(player.isOut ? 0.4 : 1)
        .overlay(alignment: .top) {
            if player.isOut {
                Text("OUT")
                    .font(ShellTheme.eyebrow(18))
                    .tracking(3)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(SpokenTVStyle.out) }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isSpeaker)
        .animation(.easeInOut(duration: 0.4), value: player.lives)
    }
}

// MARK: - Antakshari state

struct SpokenTeam: Identifiable, Equatable {
    let id: Int
    let name: String
    let colorName: String
    let score: Int
    let members: [String]

    var color: Color { SpokenTVStyle.teamColor(colorName, index: id) }
}

struct SpokenSongTurn: Identifiable, Equatable {
    let id: Int
    let team: Int
    let letter: String
    let result: String
    let endLetter: String
}

struct SpokenAntakshariBoardState {
    var phase: String = ""
    var round: Int = 0
    var letter: String = ""
    var secondsLeft: Int = 0
    var phaseSeconds: Int = 30
    var singingTeam: Int = 0
    var teams: [SpokenTeam] = []
    var target: Int = 8
    var history: [SpokenSongTurn] = []
    var verdict: SpokenVerdict? = nil
    var skipped: SpokenSkip? = nil
    var hint: String = ""
    var gameSecondsLeft: Int = 0
    var finished: Bool = false
    var winnerTeam: Int? = nil

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["round"]?.value as? Int { round = v }
        if let v = d["letter"]?.value as? String { letter = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["phaseSeconds"]?.value as? Int { phaseSeconds = v }
        if let v = d["singingTeam"]?.value as? Int { singingTeam = v }
        if let v = d["target"]?.value as? Int { target = v }
        if let v = d["gameSecondsLeft"]?.value as? Int { gameSecondsLeft = v }
        if let v = d["finished"]?.value as? Bool { finished = v }
        hint = d["hint"]?.value as? String ?? ""
        winnerTeam = d["winnerTeam"]?.value as? Int
        verdict = SpokenVerdict.parse(d["verdict"]?.value)
        skipped = SpokenSkip.parse(d["skipped"]?.value)

        let rawTeams: [Any] = d["teams"]?.value as? [Any] ?? []
        var parsedTeams: [SpokenTeam] = []
        for (offset, item) in rawTeams.enumerated() {
            guard let t = item as? [String: Any] else { continue }
            let members: [String] = (t["members"] as? [Any] ?? []).compactMap { member -> String? in
                guard let m = member as? [String: Any] else { return nil }
                return m["name"] as? String
            }
            parsedTeams.append(SpokenTeam(id: t["index"] as? Int ?? offset,
                                          name: t["name"] as? String ?? "Team",
                                          colorName: t["color"] as? String ?? "",
                                          score: t["score"] as? Int ?? 0,
                                          members: members))
        }
        teams = parsedTeams

        let rawHistory: [Any] = d["history"]?.value as? [Any] ?? []
        var turns: [SpokenSongTurn] = []
        for (offset, item) in rawHistory.enumerated() {
            guard let h = item as? [String: Any] else { continue }
            // "round" is the turn number: stable as the window slides.
            turns.append(SpokenSongTurn(id: h["round"] as? Int ?? offset,
                                        team: h["team"] as? Int ?? 0,
                                        letter: h["letter"] as? String ?? "",
                                        result: h["result"] as? String ?? "",
                                        endLetter: h["endLetter"] as? String ?? ""))
        }
        history = turns
    }

    func team(_ index: Int) -> SpokenTeam? {
        teams.indices.contains(index) ? teams[index] : nil
    }
}

// MARK: - Antakshari board

struct TVAntakshariBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: SpokenAntakshariBoardState()) { $0.update(from: $1) }
    @StateObject private var voice = TVVoiceHost()
    @State private var beatToken: Int = 0
    @State private var spokenLetter: String = ""

    private let palette: TVPalette = TVTheme.festival

    private var state: SpokenAntakshariBoardState { vm.state }
    private var phaseKey: String { "\(state.round):\(state.phase)" }
    private var singingName: String { state.team(state.singingTeam)?.name ?? "Team" }
    private var singingColor: Color { state.team(state.singingTeam)?.color ?? ShellTheme.cyan }

    var body: some View {
        ZStack {
            ShellAmbientBackground()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 40) {
                    teamPanel(0)
                    centerStage
                        .frame(maxWidth: .infinity)
                    teamPanel(1)
                }
                Spacer(minLength: 8)
                historyRibbon
            }
            .padding(.horizontal, 70)
            .padding(.top, 40)
            .padding(.bottom, 34)

            SpokenVerdictFlash(seq: state.verdict?.seq ?? 0,
                               text: verdictText,
                               detail: verdictDetail,
                               tint: verdictTint,
                               symbol: verdictSymbol)

            if state.finished {
                TVWinnerBanner(title: "Antakshari",
                               headline: winnerHeadline,
                               detail: finalScore,
                               symbol: "music.mic")
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.phase)
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: phaseKey) { _, _ in phaseChanged() }
        .onDisappear {
            beatToken += 1
            voice.stopSpeaking()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 22) {
            ShellIconOrb(symbol: "music.note", top: ShellTheme.pink, bottom: ShellTheme.violet,
                         accent: ShellTheme.gold, size: 76, isLit: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("ANTAKSHARI")
                    .font(ShellTheme.eyebrow(22))
                    .tracking(6)
                    .foregroundColor(ShellTheme.textTertiary)
                Text("Sing it out loud")
                    .font(ShellTheme.display(40))
                    .foregroundColor(.white)
            }
            Spacer()
            ShellChip(systemImage: "flag.checkered", text: "First to \(state.target)", tint: ShellTheme.gold)
            ShellChip(systemImage: "clock.fill",
                      text: "\(SpokenTVStyle.clock(state.gameSecondsLeft)) left",
                      tint: ShellTheme.cyan)
        }
    }

    // MARK: Teams

    @ViewBuilder
    private func teamPanel(_ index: Int) -> some View {
        if let team = state.team(index) {
            SpokenTeamPanel(team: team,
                            target: state.target,
                            isOnTurn: state.singingTeam == index && !state.finished,
                            phase: state.phase)
        } else {
            Color.clear.frame(width: 340)
        }
    }

    // MARK: Center

    private var centerStage: some View {
        VStack(spacing: 18) {
            Text(centerCaption)
                .font(ShellTheme.eyebrow(26))
                .tracking(5)
                .foregroundColor(singingColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 40) {
                TVHeroLetter(letter: state.phase == "letter" ? "?" : state.letter,
                             palette: palette, tileSize: 250)
                if state.phase == "sing" {
                    SpokenTimerRing(secondsLeft: state.secondsLeft, total: state.phaseSeconds,
                                    tint: singingColor, size: 170)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Group {
                if state.phase == "beat" {
                    SpokenBeatBars(tint: singingColor)
                        .frame(width: 420, height: 70)
                } else if state.phase == "sing" && !state.hint.isEmpty {
                    SpokenBanner(systemImage: "lightbulb.fill", text: state.hint, tint: ShellTheme.gold)
                } else if state.phase == "letter" {
                    SpokenBanner(systemImage: "hand.tap.fill",
                                 text: "\(singingName) is tapping the last letter",
                                 tint: singingColor)
                } else if let skip = state.skipped {
                    SpokenBanner(systemImage: "forward.fill", text: skip.caption, tint: ShellTheme.gold)
                }
            }
            .frame(height: 80)
        }
    }

    private var centerCaption: String {
        switch state.phase {
        case "beat": return "GET READY, \(singingName.uppercased())"
        case "sing": return "\(singingName.uppercased()), SING A SONG STARTING WITH"
        case "letter": return "WHAT DID YOUR SONG END WITH?"
        default: return "ANTAKSHARI"
        }
    }

    // MARK: History

    private var historyRibbon: some View {
        HStack(spacing: 12) {
            ForEach(state.history) { turn in
                SpokenSongTurnChip(turn: turn,
                                   color: state.team(turn.team)?.color ?? ShellTheme.cyan)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: state.history)
    }

    // MARK: Verdict

    private var verdictText: String {
        switch state.verdict?.kind ?? "" {
        case "sang": return "SANG IT!"
        case "missed": return "MISSED!"
        case "timeout": return "TIME!"
        default: return ""
        }
    }

    private var verdictDetail: String {
        guard let verdict = state.verdict else { return "" }
        switch verdict.kind {
        case "sang": return "+1 for \(verdict.name)"
        default: return "The letter goes to the other team"
        }
    }

    private var verdictTint: Color {
        switch state.verdict?.kind ?? "" {
        case "sang": return SpokenTVStyle.valid
        case "missed": return SpokenTVStyle.out
        default: return SpokenTVStyle.warn
        }
    }

    private var verdictSymbol: String {
        switch state.verdict?.kind ?? "" {
        case "sang": return "music.note"
        case "missed": return "xmark.octagon.fill"
        default: return "timer"
        }
    }

    // MARK: Final

    private var winnerHeadline: String {
        guard let winner = state.winnerTeam, let team = state.team(winner) else { return "It's a draw!" }
        return "\(team.name) win!"
    }

    private var finalScore: String {
        let a: Int = state.team(0)?.score ?? 0
        let b: Int = state.team(1)?.score ?? 0
        return "\(a) - \(b)"
    }

    // MARK: Sound and voice

    private func phaseChanged() {
        guard !state.finished else { return }
        switch state.phase {
        case "beat":
            playBeat()
        case "sing":
            announceTurn()
        default:
            break
        }
    }

    /// A short dhol-style groove between turns, built from the bundled
    /// clips (a low thud for the bass hits, the click for the off-beats).
    private func playBeat() {
        beatToken += 1
        let token: Int = beatToken
        let kicks: Set<Int> = [0, 3, 5]
        Task { @MainActor in
            for step in 0..<8 {
                guard token == beatToken else { return }
                if kicks.contains(step) {
                    SoundPlayer.shared.play(.connect4Drop, volume: 0.55)
                } else {
                    SoundPlayer.shared.playClick(volume: 0.4)
                }
                try? await Task.sleep(nanoseconds: 210_000_000)
            }
        }
    }

    private func announceTurn() {
        guard !state.letter.isEmpty else { return }
        let line: String
        if state.letter != spokenLetter {
            line = "\(singingName). Next letter: \(state.letter)."
        } else {
            line = "\(singingName), you get the letter \(state.letter)."
        }
        spokenLetter = state.letter
        voice.speak(line)
    }
}

private struct SpokenTeamPanel: View {
    let team: SpokenTeam
    let target: Int
    let isOnTurn: Bool
    let phase: String

    private var roleText: String {
        if !isOnTurn { return "JUDGING" }
        switch phase {
        case "sing": return "SINGING"
        case "letter": return "PICKING THE LETTER"
        default: return "UP NEXT"
        }
    }

    var body: some View {
        let color: Color = team.color
        return ShellGlassCard(cornerRadius: ShellTheme.cardRadius, tint: color, padding: 28) {
            VStack(spacing: 14) {
                Text(roleText)
                    .font(ShellTheme.eyebrow(18))
                    .tracking(4)
                    .foregroundColor(isOnTurn ? Color.black : color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background { Capsule().fill(isOnTurn ? color : color.opacity(0.15)) }
                Text(team.name)
                    .font(ShellTheme.display(36))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                TVPopNumber(value: team.score, size: 120, color: .white)
                HStack(spacing: 6) {
                    ForEach(0..<max(target, 1), id: \.self) { index in
                        Circle()
                            .fill(index < team.score ? color : Color.white.opacity(0.14))
                            .frame(width: 16, height: 16)
                    }
                }
                VStack(spacing: 4) {
                    ForEach(Array(team.members.prefix(5).enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(ShellTheme.textSecondary)
                            .lineLimit(1)
                    }
                    if team.members.count > 5 {
                        Text("+\(team.members.count - 5) more")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(ShellTheme.textTertiary)
                    }
                }
            }
            .frame(width: 300)
        }
        .scaleEffect(isOnTurn ? 1.04 : 0.94)
        .opacity(isOnTurn ? 1 : 0.78)
        .shadow(color: isOnTurn ? color.opacity(0.55) : Color.clear, radius: 40)
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: isOnTurn)
    }
}

private struct SpokenSongTurnChip: View {
    let turn: SpokenSongTurn
    let color: Color

    private var resultColor: Color {
        switch turn.result {
        case "sang": return SpokenTVStyle.valid
        case "missed": return SpokenTVStyle.out
        default: return SpokenTVStyle.warn
        }
    }

    private var resultSymbol: String {
        switch turn.result {
        case "sang": return "checkmark"
        case "missed": return "xmark"
        default: return "timer"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShellTheme.chipRadius, style: .continuous)
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 14, height: 14)
            Text(turn.letter)
                .font(ShellTheme.display(32))
                .foregroundColor(.white)
            if turn.result == "sang" {
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
                Text(turn.endLetter.isEmpty ? "?" : turn.endLetter)
                    .font(ShellTheme.display(32))
                    .foregroundColor(ShellTheme.gold)
            }
            Image(systemName: resultSymbol)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(resultColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background {
            ZStack {
                shape.fill(ShellTheme.panel.opacity(0.7))
                shape.strokeBorder(color.opacity(0.45), lineWidth: 1.5)
            }
        }
    }
}

/// Equaliser bars bouncing to the between-turns beat. Visual only, so the
/// beat still reads on a muted TV.
private struct SpokenBeatBars: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t: Double = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<12, id: \.self) { index in
                    let wave: Double = sin(t * 9.0 + Double(index) * 0.8)
                    let pulse: Double = abs(sin(t * 4.5))
                    let level: Double = 0.25 + 0.75 * abs(wave) * (0.6 + 0.4 * pulse)
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white, tint],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: max(8, 70 * CGFloat(level)))
                        .shadow(color: tint.opacity(0.7), radius: 8)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
