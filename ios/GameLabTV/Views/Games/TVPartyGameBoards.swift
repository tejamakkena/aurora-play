import SwiftUI

/// Boards for the party and mid-group games.
///
/// Each one renders only what the whole room may see. Anything secret — a
/// colour key, a hidden target, a spy's identity — arrives on phones through
/// `private_state` and deliberately never reaches these views.

// MARK: - Shared chrome

struct TVRoundHeader: View {
    let symbol: String
    let title: String
    let round: Int
    let totalRounds: Int
    let secondsLeft: Int
    var phaseLabel: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                if let phaseLabel {
                    Text(phaseLabel.uppercased())
                        .font(.system(.caption, design: .rounded, weight: .bold)).tracking(3)
                        .foregroundColor(TVTheme.cyan.opacity(0.8))
                        // A long player name in "X's turn" must truncate,
                        // never wrap mid-word.
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 12) {
                        Image(systemName: symbol).foregroundColor(.white.opacity(0.85))
                        Text(title)
                    }
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
            if totalRounds > 0 {
                VStack(spacing: 2) {
                    Text("ROUND").font(.system(.caption, design: .rounded, weight: .bold)).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(round)/\(totalRounds)")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(.white)
                }
            }
            if secondsLeft > 0 {
                Text("\(secondsLeft)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundColor(secondsLeft <= 5 ? TVTheme.red : TVTheme.cyan)
                    .frame(minWidth: 90)
                    .contentTransition(.numericText())
                    .animation(.default, value: secondsLeft)
            }
        }
        .padding(.horizontal, 70).padding(.top, 44)
    }
}

/// A scoreboard strip. Used by every round-based board.
struct TVScoreStrip: View {
    let players: [BoardPlayer]
    var highlight: Set<String> = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(players.sorted { $0.score > $1.score }) { p in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(highlight.contains(p.id) ? TVTheme.green : Color.white.opacity(0.15))
                            .frame(width: 12, height: 12)
                        Text(p.name).font(.system(.headline, design: .rounded)).foregroundColor(.white)
                        Text("\(p.score)").font(.system(.headline, design: .rounded, weight: .bold)).foregroundColor(TVTheme.cyan)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 70)
        }
        .padding(.bottom, 40)
    }
}

/// A player row as it appears inside `boardState`.
struct BoardPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    var score: Int = 0
    var extra: String? = nil

    static func list(from value: Any?) -> [BoardPlayer] {
        guard let raw = value as? [Any] else { return [] }
        return raw.compactMap { item in
            guard let d = item as? [String: Any],
                  let id = d["id"] as? String ?? d["playerID"] as? String
            else { return nil }
            return BoardPlayer(id: id,
                               name: d["name"] as? String ?? "Player",
                               score: d["score"] as? Int ?? 0)
        }
    }
}

/// Boilerplate every round-based board shares.
struct RoundBoardState {
    var round = 0
    var totalRounds = 0
    var phase = ""
    var secondsLeft = 0
    var submitted: Set<String> = []
    var players: [BoardPlayer] = []

    mutating func updateBase(from data: [String: AnyCodable]) {
        if let v = data["round"]?.value as? Int        { round = v }
        if let v = data["totalRounds"]?.value as? Int  { totalRounds = v }
        if let v = data["phase"]?.value as? String     { phase = v }
        if let v = data["secondsLeft"]?.value as? Int  { secondsLeft = v }
        if let v = data["submittedPlayerIDs"]?.value as? [Any] {
            submitted = Set(v.compactMap { $0 as? String })
        }
        players = BoardPlayer.list(from: data["players"]?.value)
    }
}

/// Every board here binds the same way; this removes 19 copies of the closure.
@MainActor
class TVBoardModel<S>: ObservableObject {
    @Published var state: S
    private let socket = GameSocketManager.shared
    private let apply: (inout S, [String: AnyCodable]) -> Void

    init(initial: S, apply: @escaping (inout S, [String: AnyCodable]) -> Void) {
        self.state = initial
        self.apply = apply
    }

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard let self, r.roomCode == roomCode else { return }
            self.apply(&self.state, r.boardState)
        }
    }
}

// MARK: - Bluff It

struct BluffState {
    var base = RoundBoardState()
    var prompt = ""
    var options: [String] = []
    var truth: String? = nil
    var truthIndex: Int? = nil
    var owners: [(index: Int, name: String)] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["prompt"]?.value as? String { prompt = v }
        truth = d["truth"]?.value as? String
        truthIndex = d["truthIndex"]?.value as? Int
        options = (d["options"]?.value as? [Any] ?? []).compactMap {
            ($0 as? [String: Any])?["text"] as? String
        }
        owners = (d["optionOwners"]?.value as? [Any] ?? []).compactMap {
            guard let o = $0 as? [String: Any], let i = o["index"] as? Int else { return nil }
            return (i, o["ownerName"] as? String ?? "")
        }
    }
}

struct TVBluffItBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: BluffState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "eye.slash.fill", title: "Bluff It",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: vm.state.base.phase == "write" ? "write a lie"
                                    : vm.state.base.phase == "pick" ? "find the truth" : "reveal")
            Spacer()
            VStack(spacing: 34) {
                // The reveal view carries the prompt as its own headline.
                if vm.state.base.phase != "reveal" {
                    PartyPromptCard(text: vm.state.prompt, size: 46, accent: TVTheme.festival.accent)
                }

                if vm.state.base.phase == "write" {
                    PartySubmissionTracker(players: vm.state.base.players,
                                           submitted: vm.state.base.submitted,
                                           verb: "have written", accent: TVTheme.festival.accent)
                } else if vm.state.base.phase == "reveal" {
                    stagedReveal
                } else {
                    optionsGrid
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .background(TVAnimatedBackground(palette: TVTheme.festival))
        .onAppear { vm.bind(roomCode: room.code) }
    }

    /// The answers to pick from, dealt in one by one as lettered glass cards.
    private var optionsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 22), GridItem(.flexible(), spacing: 22)],
                  spacing: 22) {
            ForEach(Array(vm.state.options.enumerated()), id: \.offset) { idx, text in
                BluffOptionCard(index: idx, text: text)
                    .tvStaggeredAppear(index: idx, step: 0.1)
            }
        }
        .padding(.horizontal, 120)
        .id("options-\(vm.state.base.round)-\(vm.state.prompt)")
    }

    /// The staged big-screen reveal: each lie appears one by one with its
    /// author, then the truth gets the spotlight.
    private var stagedReveal: some View {
        let rows = vm.state.options.enumerated().compactMap { idx, text -> TVRevealRow? in
            guard idx != vm.state.truthIndex,
                  let owner = vm.state.owners.first(where: { $0.index == idx })
            else { return nil }
            return TVRevealRow(id: "opt-\(idx)", name: owner.name, detail: text)
        }
        let spotlight: TVRevealSpotlight? = {
            guard let truth = vm.state.truth, !truth.isEmpty else { return nil }
            return TVRevealSpotlight(title: "THE TRUTH", name: truth)
        }()
        return TVRevealBoardView(
            roundKey: "bluff-\(vm.state.base.round)-\(vm.state.prompt)",
            header: "reveal",
            headline: vm.state.prompt,
            rows: rows,
            spotlight: spotlight,
            emptyMessage: "Nobody wrote a lie this round")
    }
}

// MARK: - Last Tap Standing

struct LastTapState {
    var phase = "arming"
    var round = 0
    var aliveCount = 0
    var alive: Set<String> = []
    var eliminated: [String] = []
    var results: [(name: String, ms: Int, falseStart: Bool)] = []
    var players: [BoardPlayer] = []
    var winner: String? = nil

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["round"]?.value as? Int { round = v }
        if let v = d["aliveCount"]?.value as? Int { aliveCount = v }
        if let v = d["alivePlayerIDs"]?.value as? [Any] {
            alive = Set(v.compactMap { $0 as? String })
        }
        eliminated = (d["eliminatedPlayerIDs"]?.value as? [Any] ?? []).compactMap { $0 as? String }
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
        results = (d["results"]?.value as? [Any] ?? []).compactMap {
            guard let r = $0 as? [String: Any] else { return nil }
            return (r["name"] as? String ?? "", r["ms"] as? Int ?? 0,
                    r["falseStart"] as? Bool ?? false)
        }
    }
}

struct TVLastTapBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: LastTapState()) { $0.update(from: $1) }

    private var background: Color {
        switch vm.state.phase {
        case "go":     return TVTheme.green
        case "arming": return Color(hex: "1a0d2e")
        default:       return .black.opacity(0.4)
        }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
                .animation(.easeIn(duration: 0.05), value: vm.state.phase)

            VStack(spacing: 0) {
                TVRoundHeader(symbol: "bolt.fill", title: "Last Tap Standing",
                              round: vm.state.round, totalRounds: 0, secondsLeft: 0,
                              phaseLabel: "\(vm.state.aliveCount) still in")
                Spacer()
                switch vm.state.phase {
                case "arming":
                    Text("WAIT…")
                        .font(.system(size: 120, weight: .heavy, design: .rounded)).tracking(10)
                        .foregroundColor(.white.opacity(0.25))
                case "go":
                    Text("TAP!")
                        .font(.system(size: 190, weight: .heavy, design: .rounded)).tracking(12)
                        .foregroundColor(.black)
                case "final":
                    VStack(spacing: 16) {
                        Image(systemName: "trophy.fill").font(.system(size: 100, weight: .regular, design: .rounded)).foregroundColor(TVTheme.yellow)
                        Text(vm.state.players.first { $0.id == vm.state.winner }?.name ?? "Winner")
                            .font(.system(size: 62, weight: .heavy, design: .rounded)).foregroundColor(TVTheme.yellow)
                    }
                default:
                    VStack(spacing: 14) {
                        ForEach(Array(vm.state.results.prefix(8).enumerated()), id: \.offset) { i, r in
                            HStack(spacing: 20) {
                                Text("\(i + 1)").font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4)).frame(width: 44)
                                Text(r.name).font(.system(.title2, design: .rounded)).foregroundColor(.white)
                                Spacer()
                                Text(r.falseStart ? "too early" : "\(r.ms) ms")
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                    .foregroundColor(r.falseStart ? TVTheme.red : TVTheme.cyan)
                            }
                            .padding(.horizontal, 30).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
                        }
                    }
                    .padding(.horizontal, 200)
                }
                Spacer()
                TVScoreStrip(players: vm.state.players, highlight: vm.state.alive)
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Herd

struct HerdState {
    var base = RoundBoardState()
    var prompt = ""
    var clusters: [(text: String, size: Int, names: [String])] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["prompt"]?.value as? String { prompt = v }
        clusters = (d["clusters"]?.value as? [Any] ?? []).compactMap {
            guard let c = $0 as? [String: Any] else { return nil }
            return (c["text"] as? String ?? "", c["size"] as? Int ?? 0,
                    (c["names"] as? [Any] ?? []).compactMap { $0 as? String })
        }
    }
}

struct TVHerdBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: HerdState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "person.3.fill", title: "Herd",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: "match the majority")
            Spacer()
            VStack(spacing: 32) {
                if vm.state.base.phase == "answer" {
                    HerdFlock(count: vm.state.base.players.count, answered: vm.state.base.submitted.count)
                    PartyPromptCard(text: vm.state.prompt, size: 52, accent: TVTheme.aurora.accent)
                    PartySubmissionTracker(players: vm.state.base.players,
                                           submitted: vm.state.base.submitted,
                                           verb: "answered", accent: TVTheme.aurora.accent)
                } else {
                    // The reveal view carries the prompt as its own headline.
                    stagedReveal
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .background(TVAnimatedBackground(palette: TVTheme.aurora))
        .onAppear { vm.bind(roomCode: room.code) }
    }

    /// The staged big-screen reveal: clusters appear one by one, biggest
    /// herd first, then the biggest herd gets the spotlight.
    private var stagedReveal: some View {
        let rows = vm.state.clusters.enumerated().map { i, c in
            TVRevealRow(id: "cluster-\(i)", name: c.text,
                        detail: c.names.joined(separator: ", "),
                        sublabel: c.size == 1 ? "1 player" : "\(c.size) players",
                        isWinner: i == 0 && c.size >= 2)
        }
        let spotlight: TVRevealSpotlight? = {
            guard let top = vm.state.clusters.first, top.size >= 2 else { return nil }
            return TVRevealSpotlight(title: "BIGGEST HERD", name: top.text,
                                     detail: "\(top.size) players thought alike")
        }()
        return TVRevealBoardView(
            roundKey: "herd-\(vm.state.base.round)-\(vm.state.prompt)",
            header: "reveal",
            headline: vm.state.prompt,
            rows: rows,
            spotlight: spotlight,
            emptyMessage: "Nobody answered this round")
    }
}

// MARK: - Emoji Charades

struct EmojiMovieState {
    var base = RoundBoardState()
    var entries: [(emoji: String, owner: String, title: String?)] = []
    var composedCount = 0

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["composedCount"]?.value as? Int { composedCount = v }
        entries = (d["entries"]?.value as? [Any] ?? []).compactMap {
            guard let e = $0 as? [String: Any] else { return nil }
            return (e["emoji"] as? String ?? "", e["ownerName"] as? String ?? "",
                    e["title"] as? String)
        }
    }
}

struct TVEmojiMovieBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: EmojiMovieState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "clapperboard.fill", title: "Emoji Charades",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: vm.state.base.phase)
            Spacer()
            if vm.state.base.phase == "compose" {
                VStack(spacing: 18) {
                    Image(systemName: "pencil").font(.system(size: 90, weight: .regular, design: .rounded)).foregroundColor(.white.opacity(0.7))
                    Text("Everyone is describing their secret title")
                        .font(.system(.title2, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    Text("\(vm.state.composedCount) submitted")
                        .font(.system(.title3, design: .rounded)).foregroundColor(TVTheme.cyan)
                }
            } else if vm.state.base.phase == "reveal" {
                stagedReveal
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                    ForEach(Array(vm.state.entries.enumerated()), id: \.offset) { _, e in
                        VStack(spacing: 10) {
                            Text(e.emoji).font(.system(size: 62, weight: .regular, design: .rounded))
                            if let title = e.title {
                                Text(title).font(.system(.headline, design: .rounded, weight: .bold)).foregroundColor(TVTheme.green)
                            }
                            Text(e.owner).font(.system(.caption, design: .rounded)).foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                        .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius).fill(.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 90)
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    /// The staged big-screen reveal: each emoji clue appears with its
    /// revealed title, one by one. No single winner in this game.
    private var stagedReveal: some View {
        let rows = vm.state.entries.enumerated().map { i, e in
            TVRevealRow(id: "entry-\(i)",
                        name: e.owner.isEmpty ? "Player" : e.owner,
                        detail: e.emoji,
                        sublabel: e.title)
        }
        return TVRevealBoardView(
            roundKey: "emoji-\(vm.state.base.round)",
            header: "reveal",
            headline: "The films",
            rows: rows,
            spotlight: nil,
            emptyMessage: "Nobody composed a clue this round")
    }
}

// MARK: - Name Place Animal Thing

struct NPATState {
    var base = RoundBoardState()
    var letter = ""
    var answers: [(id: String, name: String, values: [String])] = []
    var totals: [String: Int] = [:]   // playerID -> points this round

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["letter"]?.value as? String { letter = v }
        answers = (d["answers"]?.value as? [Any] ?? []).compactMap {
            guard let a = $0 as? [String: Any] else { return nil }
            return (a["playerID"] as? String ?? "",
                    a["name"] as? String ?? "",
                    ["name", "place", "animal", "thing"].map { a[$0] as? String ?? "—" })
        }
        totals = [:]
        for item in (d["breakdown"]?.value as? [Any] ?? []) {
            guard let b = item as? [String: Any],
                  let pid = b["playerID"] as? String else { continue }
            totals[pid, default: 0] += b["points"] as? Int ?? 0
        }
    }
}

struct TVNPATBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: NPATState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "a.circle.fill", title: "Name Place Animal Thing",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft)
            Spacer()
            if vm.state.base.phase == "fill" {
                VStack(spacing: 26) {
                    Text("LETTER").font(.system(.caption, design: .rounded, weight: .bold)).tracking(5)
                        .foregroundColor(TVTheme.textSecondary)
                    TVHeroLetter(letter: vm.state.letter, palette: TVTheme.aurora, tileSize: 230)
                    categoryChips
                    PartySubmissionTracker(players: vm.state.base.players,
                                           submitted: vm.state.base.submitted,
                                           verb: "submitted", accent: TVTheme.aurora.accent)
                }
            } else {
                stagedReveal
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .background(TVAnimatedBackground(palette: TVTheme.aurora))
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private static let categories: [(title: String, symbol: String)] = [
        ("Name", "person.fill"), ("Place", "mappin.and.ellipse"),
        ("Animal", "pawprint.fill"), ("Thing", "cube.fill"),
    ]

    /// The four columns everyone is filling in, dealt in per round.
    private var categoryChips: some View {
        HStack(spacing: 22) {
            ForEach(Array(TVNPATBoardView.categories.enumerated()), id: \.offset) { index, category in
                TVGlassCard(cornerRadius: ShellTheme.cardRadius, tint: TVTheme.aurora.blobs[index % 3], padding: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: category.symbol)
                            .foregroundColor(TVTheme.aurora.accent)
                        Text(category.title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 26).padding(.vertical, 14)
                }
                .tvStaggeredAppear(index: index, step: 0.1)
            }
        }
        .id("npat-chips-\(vm.state.base.round)")
    }

    /// The staged big-screen reveal: each player's answers appear one by
    /// one with their points, then the top scorer gets the spotlight.
    private var stagedReveal: some View {
        let rows = vm.state.answers.map { a in
            let pts = vm.state.totals[a.id] ?? 0
            return TVRevealRow(id: a.id, name: a.name,
                               detail: a.values.joined(separator: "  ·  "),
                               sublabel: pts == 1 ? "1 pt" : "\(pts) pts")
        }
        let spotlight: TVRevealSpotlight? = {
            let ranked = vm.state.answers.sorted {
                (vm.state.totals[$0.id] ?? 0) > (vm.state.totals[$1.id] ?? 0)
            }
            guard let best = ranked.first,
                  (vm.state.totals[best.id] ?? 0) > 0 else { return nil }
            let pts = vm.state.totals[best.id] ?? 0
            return TVRevealSpotlight(title: "TOP SCORER", name: best.name,
                                     detail: pts == 1 ? "1 pt" : "\(pts) pts")
        }()
        return TVRevealBoardView(
            roundKey: "npat-\(vm.state.base.round)-\(vm.state.letter)",
            header: "reveal",
            headline: "Letter \(vm.state.letter)",
            rows: rows,
            spotlight: spotlight,
            emptyMessage: "Nobody submitted this round")
    }
}

// MARK: - Party chrome (Bluff It, Herd, NPAT)

/// The round's question on a frosted card that swings in whenever the
/// prompt changes.
private struct PartyPromptCard: View {
    let text: String
    let size: CGFloat
    let accent: Color

    var body: some View {
        TVGlassCard(cornerRadius: ShellTheme.cardRadius, tint: accent, padding: 0) {
            Text(text)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .shadow(color: accent.opacity(0.35), radius: 14)
                .padding(.horizontal, 56)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 110)
        .tvStaggeredAppear(index: 0)
        // Outermost, so a new prompt is a new view and the entrance replays.
        .id(text)
    }
}

/// "3 of 6 answered", with the count popping and one chip per player that
/// lights up the moment they lock in.
private struct PartySubmissionTracker: View {
    let players: [BoardPlayer]
    let submitted: Set<String>
    let verb: String
    let accent: Color

    private var doneCount: Int {
        players.filter { submitted.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TVPopNumber(value: doneCount, size: 44, color: accent)
                Text("of \(players.count) \(verb)")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundColor(TVTheme.textSecondary)
            }
            // Wraps onto a second row for a big room instead of running off
            // the screen.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 14)], spacing: 14) {
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                    PartyPlayerChip(name: player.name, done: submitted.contains(player.id), accent: accent)
                        .tvStaggeredAppear(index: index, step: 0.05)
                }
            }
            .padding(.horizontal, 120)
        }
    }
}

private struct PartyPlayerChip: View {
    let name: String
    let done: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "ellipsis.circle")
                .foregroundColor(done ? accent : TVTheme.textTertiary)
            Text(name)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(done ? Color.white : TVTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(
            Capsule().fill(done ? accent.opacity(0.22) : Color.white.opacity(0.06))
        )
        .overlay(Capsule().strokeBorder(done ? accent.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1.5))
        .shadow(color: done ? accent.opacity(0.55) : Color.clear, radius: 12)
        .scaleEffect(done ? 1.06 : 1)
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: done)
    }
}

/// A lettered answer card for Bluff It's pick phase.
private struct BluffOptionCard: View {
    let index: Int
    let text: String

    private var letter: String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        return index < letters.count ? letters[index] : "\(index + 1)"
    }

    var body: some View {
        TVGlassCard(cornerRadius: ShellTheme.cardRadius, tint: TVTheme.festival.blobs[index % 3], padding: 0) {
            HStack(spacing: 18) {
                Text(letter)
                    .font(TVTheme.display(30))
                    .foregroundColor(.black)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(TVTheme.festival.accent2))
                    .shadow(color: TVTheme.festival.accent2.opacity(0.6), radius: 10)
                Text(text)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
        }
    }
}

/// Herd's mascot row: one glowing figure per player that fills in as they
/// answer, bobbing gently so the waiting screen is never static.
private struct HerdFlock: View {
    let count: Int
    let answered: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t: Double = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 18) {
                ForEach(0..<max(count, 0), id: \.self) { i in
                    figure(index: i, time: t)
                }
            }
        }
        .frame(height: 70)
    }

    private func figure(index: Int, time: Double) -> some View {
        let lit: Bool = index < answered
        let bob: CGFloat = CGFloat(sin(time * 2.2 + Double(index) * 0.7)) * 5
        let tint: Color = lit ? TVTheme.aurora.accent : Color.white.opacity(0.22)
        return Image(systemName: "figure.stand")
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .foregroundColor(tint)
            .shadow(color: lit ? tint.opacity(0.8) : Color.clear, radius: 10)
            .offset(y: lit ? bob : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: lit)
    }
}

// MARK: - Most Likely To

struct MostLikelyResult: Identifiable {
    let id: String
    let name: String
    let votes: Int
    let topVoted: Bool
}

struct MostLikelyState {
    var base = RoundBoardState()
    var prompt = ""
    var votesSoFar = 0
    var results: [MostLikelyResult] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["prompt"]?.value as? String { prompt = v }
        if let v = d["votesSoFar"]?.value as? Int { votesSoFar = v }
        let raw = d["roundResults"]?.value as? [Any] ?? []
        results = raw.compactMap { item -> MostLikelyResult? in
            guard let r = item as? [String: Any],
                  let id = r["playerID"] as? String else { return nil }
            return MostLikelyResult(id: id,
                                    name: r["name"] as? String ?? "Player",
                                    votes: r["votes"] as? Int ?? 0,
                                    topVoted: r["topVoted"] as? Bool ?? false)
        }
    }
}

struct TVMostLikelyToBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: MostLikelyState()) { $0.update(from: $1) }

    private var isReveal: Bool { vm.state.base.phase == "reveal" }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "hand.thumbsup.fill", title: "Most Likely To",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: isReveal ? "the room has spoken" : "secret ballot")
            Spacer()
            VStack(spacing: 40) {
                // Prompts already read "Most likely to ...".
                Text("Who is…")
                    .font(.system(.title2, design: .rounded, weight: .bold)).foregroundColor(.white.opacity(0.5))
                Text(vm.state.prompt)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 120)

                if isReveal {
                    stagedReveal
                } else {
                    ballotProgress
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private var ballotProgress: some View {
        let total = vm.state.base.players.count
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(vm.state.base.players) { p in
                    let voted = vm.state.base.submitted.contains(p.id)
                    Image(systemName: voted ? "checkmark.seal.fill" : "hourglass")
                        .font(.system(size: 30, weight: .regular, design: .rounded))
                        .foregroundColor(voted ? TVTheme.green : .white.opacity(0.25))
                }
            }
            Text("\(vm.state.votesSoFar) of \(total) votes in. Vote on your phone.")
                .font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.5))
        }
    }

    /// The staged big-screen reveal: tallies appear one by one, then the
    /// top-voted player gets the spotlight.
    private var stagedReveal: some View {
        let rows = vm.state.results.map { r in
            TVRevealRow(id: r.id, name: r.name,
                        detail: r.votes == 1 ? "1 vote" : "\(r.votes) votes",
                        isWinner: r.topVoted)
        }
        let tops = vm.state.results.filter(\.topVoted)
        let spotlight: TVRevealSpotlight? = {
            guard let first = tops.first else { return nil }
            return TVRevealSpotlight(
                title: "MOST VOTED",
                name: tops.map(\.name).joined(separator: ", "),
                detail: first.votes == 1 ? "1 vote" : "\(first.votes) votes")
        }()
        return TVRevealBoardView(
            roundKey: "most-likely-\(vm.state.base.round)-\(vm.state.prompt)",
            header: "the room has spoken",
            headline: vm.state.prompt,
            rows: rows,
            spotlight: spotlight,
            emptyMessage: "Nobody voted this round")
    }
}
