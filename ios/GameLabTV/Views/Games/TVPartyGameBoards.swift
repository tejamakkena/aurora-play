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
                        .font(.caption.bold()).tracking(3)
                        .foregroundColor(.cyan.opacity(0.8))
                }
                HStack(spacing: 12) {
                        Image(systemName: symbol).foregroundColor(.white.opacity(0.85))
                        Text(title)
                    }
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            if totalRounds > 0 {
                VStack(spacing: 2) {
                    Text("ROUND").font(.caption.bold()).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(round)/\(totalRounds)")
                        .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                }
            }
            if secondsLeft > 0 {
                Text("\(secondsLeft)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundColor(secondsLeft <= 5 ? .red : .cyan)
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
                            .fill(highlight.contains(p.id) ? Color.green : Color.white.opacity(0.15))
                            .frame(width: 12, height: 12)
                        Text(p.name).font(.headline).foregroundColor(.white)
                        Text("\(p.score)").font(.headline.bold()).foregroundColor(.cyan)
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
                Text(vm.state.prompt)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 120)

                if vm.state.base.phase == "write" {
                    Text("\(vm.state.base.submitted.count) of \(vm.state.base.players.count) have written")
                        .font(.title3).foregroundColor(.white.opacity(0.45))
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(Array(vm.state.options.enumerated()), id: \.offset) { idx, text in
                            let isTruth = vm.state.truthIndex == idx
                            VStack(spacing: 6) {
                                Text(text).font(.title3.bold())
                                    .foregroundColor(isTruth ? .black : .white)
                                if let owner = vm.state.owners.first(where: { $0.index == idx }) {
                                    Text(owner.name).font(.caption)
                                        .foregroundColor(isTruth ? .black.opacity(0.6)
                                                                 : .white.opacity(0.4))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(isTruth ? Color.green : Color.white.opacity(0.07)))
                        }
                    }
                    .padding(.horizontal, 120)
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
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
        case "go":     return .green
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
                        .font(.system(size: 120, weight: .heavy)).tracking(10)
                        .foregroundColor(.white.opacity(0.25))
                case "go":
                    Text("TAP!")
                        .font(.system(size: 190, weight: .heavy)).tracking(12)
                        .foregroundColor(.black)
                case "final":
                    VStack(spacing: 16) {
                        Image(systemName: "trophy.fill").font(.system(size: 100)).foregroundColor(.yellow)
                        Text(vm.state.players.first { $0.id == vm.state.winner }?.name ?? "Winner")
                            .font(.system(size: 62, weight: .heavy)).foregroundColor(.yellow)
                    }
                default:
                    VStack(spacing: 14) {
                        ForEach(Array(vm.state.results.prefix(8).enumerated()), id: \.offset) { i, r in
                            HStack(spacing: 20) {
                                Text("\(i + 1)").font(.title2.bold())
                                    .foregroundColor(.white.opacity(0.4)).frame(width: 44)
                                Text(r.name).font(.title2).foregroundColor(.white)
                                Spacer()
                                Text(r.falseStart ? "too early" : "\(r.ms) ms")
                                    .font(.title3.bold())
                                    .foregroundColor(r.falseStart ? .red : .cyan)
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
                Text(vm.state.prompt)
                    .font(.system(size: 52, weight: .bold)).foregroundColor(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, 120)

                if vm.state.base.phase == "answer" {
                    Text("\(vm.state.base.submitted.count) of \(vm.state.base.players.count) answered")
                        .font(.title2).foregroundColor(.white.opacity(0.45))
                } else {
                    HStack(alignment: .bottom, spacing: 18) {
                        ForEach(Array(vm.state.clusters.prefix(6).enumerated()), id: \.offset) { i, c in
                            VStack(spacing: 8) {
                                Text("\(c.size)").font(.system(size: 34, weight: .heavy))
                                    .foregroundColor(i == 0 ? .black : .white)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(i == 0 ? Color.yellow : Color.cyan.opacity(0.5))
                                    .frame(width: 130, height: CGFloat(40 + c.size * 34))
                                Text(c.text).font(.headline).foregroundColor(.white)
                                    .lineLimit(1).frame(width: 140)
                            }
                        }
                    }
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Emoji Movie

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
            TVRoundHeader(symbol: "clapperboard.fill", title: "Emoji Movie",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: vm.state.base.phase)
            Spacer()
            if vm.state.base.phase == "compose" {
                VStack(spacing: 18) {
                    Image(systemName: "pencil").font(.system(size: 90)).foregroundColor(.white.opacity(0.7))
                    Text("Everyone is describing their secret title")
                        .font(.title2).foregroundColor(.white.opacity(0.6))
                    Text("\(vm.state.composedCount) submitted")
                        .font(.title3).foregroundColor(.cyan)
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                    ForEach(Array(vm.state.entries.enumerated()), id: \.offset) { _, e in
                        VStack(spacing: 10) {
                            Text(e.emoji).font(.system(size: 62))
                            if let title = e.title {
                                Text(title).font(.headline.bold()).foregroundColor(.green)
                            }
                            Text(e.owner).font(.caption).foregroundColor(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 90)
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Name Place Animal Thing

struct NPATState {
    var base = RoundBoardState()
    var letter = ""
    var answers: [(name: String, values: [String])] = []
    let fields = ["name", "place", "animal", "thing"]

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["letter"]?.value as? String { letter = v }
        answers = (d["answers"]?.value as? [Any] ?? []).compactMap {
            guard let a = $0 as? [String: Any] else { return nil }
            return (a["name"] as? String ?? "",
                    ["name", "place", "animal", "thing"].map { a[$0] as? String ?? "—" })
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
                VStack(spacing: 20) {
                    Text("LETTER").font(.caption.bold()).tracking(5)
                        .foregroundColor(.white.opacity(0.4))
                    Text(vm.state.letter)
                        .font(.system(size: 210, weight: .heavy, design: .rounded))
                        .foregroundColor(.cyan)
                    Text("\(vm.state.base.submitted.count) of \(vm.state.base.players.count) submitted")
                        .font(.title3).foregroundColor(.white.opacity(0.45))
                }
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Text("").frame(width: 170, alignment: .leading)
                        ForEach(["Name", "Place", "Animal", "Thing"], id: \.self) { h in
                            Text(h).font(.caption.bold()).tracking(2)
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(vm.state.answers.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.name).font(.headline).foregroundColor(.cyan)
                                .frame(width: 170, alignment: .leading)
                            ForEach(Array(row.values.enumerated()), id: \.offset) { _, v in
                                Text(v).font(.body).foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                    }
                }
                .padding(.horizontal, 90)
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Antakshari

struct AntakshariState {
    var base = RoundBoardState()
    var letter = ""
    var teamScores = [0, 0]
    var chain: [(name: String, song: String, team: Int)] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["letter"]?.value as? String { letter = v }
        if let v = d["teamScores"]?.value as? [Any] {
            teamScores = v.compactMap { $0 as? Int }
        }
        chain = (d["chain"]?.value as? [Any] ?? []).compactMap {
            guard let c = $0 as? [String: Any] else { return nil }
            return (c["name"] as? String ?? "", c["song"] as? String ?? "",
                    c["team"] as? Int ?? 0)
        }
    }
}

struct TVAntakshariBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: AntakshariState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "music.note", title: "Antakshari",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft)
            Spacer()
            VStack(spacing: 30) {
                HStack(spacing: 60) {
                    teamCard("Team A", score: vm.state.teamScores.first ?? 0, color: .cyan)
                    VStack(spacing: 6) {
                        Text("SING A SONG STARTING WITH")
                            .font(.caption.bold()).tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                        Text(vm.state.letter)
                            .font(.system(size: 140, weight: .heavy, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    teamCard("Team B", score: vm.state.teamScores.last ?? 0, color: .pink)
                }

                VStack(spacing: 8) {
                    ForEach(Array(vm.state.chain.suffix(4).enumerated()), id: \.offset) { _, c in
                        HStack(spacing: 14) {
                            Circle().fill(c.team == 0 ? Color.cyan : Color.pink)
                                .frame(width: 12, height: 12)
                            Text(c.song).font(.title3).foregroundColor(.white)
                            Text("— \(c.name)").font(.body)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private func teamCard(_ title: String, score: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundColor(color)
            Text("\(score)").font(.system(size: 60, weight: .heavy)).foregroundColor(.white)
        }
        .frame(width: 200).padding(.vertical, 24)
        .background(RoundedRectangle(cornerRadius: 18).fill(color.opacity(0.15)))
    }
}
