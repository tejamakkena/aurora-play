import SwiftUI

/// Boards for the mid-group deduction and negotiation games.

// MARK: - Cipher Grid

struct CipherGridState {
    var words: [String] = []
    var revealed: [Int: String] = [:]        // index -> colour, revealed only
    var turn = "red"
    var clue = (word: "", count: 0)
    var guessesLeft = 0
    var redLeft = 0
    var blueLeft = 0
    var winner: String? = nil
    var spymasters: [String: String] = [:]
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        words = (d["words"]?.value as? [Any] ?? []).compactMap { $0 as? String }
        if let v = d["turn"]?.value as? String { turn = v }
        if let c = d["clue"]?.value as? [String: Any] {
            clue = (c["word"] as? String ?? "", c["count"] as? Int ?? 0)
        }
        if let v = d["guessesLeft"]?.value as? Int { guessesLeft = v }
        if let v = d["redLeft"]?.value as? Int { redLeft = v }
        if let v = d["blueLeft"]?.value as? Int { blueLeft = v }
        winner = d["winner"]?.value as? String
        if let m = d["spymasterNames"]?.value as? [String: Any] {
            spymasters = m.compactMapValues { $0 as? String }
        }
        // Only revealed tiles carry a colour; the key itself is never sent here.
        revealed = [:]
        for item in (d["revealed"]?.value as? [Any] ?? []) {
            if let r = item as? [String: Any],
               let i = r["index"] as? Int, let c = r["colour"] as? String {
                revealed[i] = c
            }
        }
        players = BoardPlayer.list(from: d["players"]?.value)
    }
}

struct TVCipherGridBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: CipherGridState()) { $0.update(from: $1) }

    private func tileColor(_ index: Int) -> Color {
        switch vm.state.revealed[index] {
        case "red":      return TVTheme.red
        case "blue":     return TVTheme.blue
        // The bystander card's tan card stock, matching the phone's key.
        case "neutral":  return Color(hex: "8d7f6d")
        case "assassin": return .black
        default:         return .white.opacity(0.08)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 30) {
                teamPill("RED", left: vm.state.redLeft, color: TVTheme.red,
                         active: vm.state.turn == "red")
                Spacer()
                VStack(spacing: 4) {
                    Text("CLUE").font(.system(.caption, design: .rounded, weight: .bold)).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    Text(vm.state.clue.word.isEmpty ? "—"
                         : "\(vm.state.clue.word.uppercased())  \(vm.state.clue.count)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(TVTheme.yellow)
                    if vm.state.guessesLeft > 0 {
                        Text("\(vm.state.guessesLeft) guesses left")
                            .font(.system(.caption, design: .rounded)).foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                teamPill("BLUE", left: vm.state.blueLeft, color: TVTheme.blue,
                         active: vm.state.turn == "blue")
            }
            .padding(.horizontal, 70).padding(.top, 44)

            Spacer()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
                      spacing: 12) {
                ForEach(Array(vm.state.words.enumerated()), id: \.offset) { idx, word in
                    Text(word)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(vm.state.revealed[idx] == nil ? .white : .white.opacity(0.9))
                        .frame(maxWidth: .infinity).frame(height: 110)
                        .background(RoundedRectangle(cornerRadius: 12).fill(tileColor(idx)))
                        .opacity(vm.state.revealed[idx] == nil ? 1 : 0.75)
                        .animation(.easeOut(duration: 0.25), value: vm.state.revealed[idx])
                }
            }
            .padding(.horizontal, 90)

            if let winner = vm.state.winner {
                Text("\(winner.uppercased()) TEAM WINS")
                    .font(.system(size: 46, weight: .heavy, design: .rounded)).tracking(4)
                    .foregroundColor(winner == "red" ? TVTheme.red : TVTheme.blue)
                    .padding(.top, 24)
            }

            Spacer()
            HStack(spacing: 40) {
                ForEach(["red", "blue"], id: \.self) { team in
                    if let name = vm.state.spymasters[team] {
                        Text("\(team == "red" ? "Red" : "Blue") spymaster: \(name)")
                            .font(.system(.headline, design: .rounded)).foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private func teamPill(_ title: String, left: Int, color: Color, active: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(.caption, design: .rounded, weight: .bold)).tracking(3).foregroundColor(color)
            Text("\(left)").font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundColor(.white)
        }
        .frame(width: 160).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius)
            .fill(color.opacity(active ? 0.35 : 0.12)))
        .overlay(RoundedRectangle(cornerRadius: ShellTheme.buttonRadius)
            .stroke(color, lineWidth: active ? 3 : 0))
    }
}

// MARK: - Odd One Out

struct OddOneOutState {
    var phase = "question"
    var round = 0
    var totalRounds = 0
    var secondsLeft = 0
    var voted: Set<String> = []
    var tally: [(name: String, votes: Int)] = []
    var location: String? = nil
    var spyName: String? = nil
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["round"]?.value as? Int { round = v }
        if let v = d["totalRounds"]?.value as? Int { totalRounds = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["votedPlayerIDs"]?.value as? [Any] {
            voted = Set(v.compactMap { $0 as? String })
        }
        location = d["location"]?.value as? String
        spyName = d["spyName"]?.value as? String
        winner = d["winner"]?.value as? String
        tally = (d["tally"]?.value as? [Any] ?? []).compactMap {
            guard let t = $0 as? [String: Any] else { return nil }
            return (t["name"] as? String ?? "", t["votes"] as? Int ?? 0)
        }
        players = BoardPlayer.list(from: d["players"]?.value)
    }
}

struct TVOddOneOutBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: OddOneOutState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "eyeglasses", title: "Odd One Out",
                          round: vm.state.round, totalRounds: vm.state.totalRounds,
                          secondsLeft: vm.state.secondsLeft,
                          phaseLabel: vm.state.phase == "question" ? "ask questions"
                                    : vm.state.phase == "vote" ? "vote" : "reveal")
            Spacer()
            if let location = vm.state.location {
                // Revealed only once the round is over.
                VStack(spacing: 20) {
                    Text("THE LOCATION WAS").font(.system(.caption, design: .rounded, weight: .bold)).tracking(4)
                        .foregroundColor(.white.opacity(0.4))
                    Text(location).font(.system(size: 62, weight: .heavy, design: .rounded))
                        .foregroundColor(TVTheme.cyan)
                    if let spy = vm.state.spyName {
                        Text("The spy was \(spy)").font(.system(.title2, design: .rounded))
                            .foregroundColor(TVTheme.yellow)
                    }
                    Text(vm.state.winner == "spy" ? "Spy wins" : "Players win")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(vm.state.winner == "spy" ? TVTheme.red : TVTheme.green)
                }
            } else if vm.state.phase == "vote" {
                VStack(spacing: 14) {
                    Text("Who is the spy?").font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(.white).padding(.bottom, 10)
                    ForEach(Array(vm.state.tally.enumerated()), id: \.offset) { _, t in
                        HStack {
                            Text(t.name).font(.system(.title2, design: .rounded)).foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 6) {
                                ForEach(0..<max(0, t.votes), id: \.self) { _ in
                                    Circle().fill(TVTheme.red).frame(width: 18, height: 18)
                                }
                            }
                        }
                        .padding(.horizontal, 28).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 250)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "questionmark.circle.fill").font(.system(size: 100, weight: .regular, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    Text("Question each other")
                        .font(.system(size: 44, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("Everyone knows the location — except one of you")
                        .font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.players, highlight: vm.state.voted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Sealed Auction

struct AuctionState {
    var base = RoundBoardState()
    var lotName = ""
    var lotValue = 0
    var bids: [(name: String, amount: Int)] = []
    var winnerName: String? = nil
    var tied = false
    var budgets: [(name: String, budget: Int)] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["lotName"]?.value as? String { lotName = v }
        if let v = d["lotValue"]?.value as? Int { lotValue = v }
        budgets = (d["budgets"]?.value as? [Any] ?? []).compactMap {
            guard let b = $0 as? [String: Any] else { return nil }
            return (b["name"] as? String ?? "", b["budget"] as? Int ?? 0)
        }
        if let r = d["result"]?.value as? [String: Any] {
            winnerName = r["winnerName"] as? String
            tied = r["tied"] as? Bool ?? false
            bids = (r["bids"] as? [Any] ?? []).compactMap {
                guard let b = $0 as? [String: Any] else { return nil }
                return (b["name"] as? String ?? "", b["amount"] as? Int ?? 0)
            }
        } else {
            bids = []; winnerName = nil; tied = false
        }
    }
}

struct TVSealedAuctionBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: AuctionState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "hammer.fill", title: "Sealed Auction",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: vm.state.base.phase == "bid" ? "bids are sealed" : "reveal")
            Spacer()
            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    Text("LOT").font(.system(.caption, design: .rounded, weight: .bold)).tracking(4)
                        .foregroundColor(.white.opacity(0.4))
                    Text(vm.state.lotName).font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundColor(.white).multilineTextAlignment(.center)
                    Text("worth \(vm.state.lotValue * 10) points")
                        .font(.system(.title3, design: .rounded)).foregroundColor(TVTheme.yellow.opacity(0.8))
                }

                if vm.state.base.phase == "bid" {
                    Text("\(vm.state.base.submitted.count) of \(vm.state.base.players.count) have bid")
                        .font(.system(.title2, design: .rounded)).foregroundColor(.white.opacity(0.45))
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(vm.state.bids.enumerated()), id: \.offset) { i, b in
                            HStack {
                                Text(b.name).font(.system(.title3, design: .rounded)).foregroundColor(.white)
                                Spacer()
                                Text("\(b.amount)").font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundColor(i == 0 && !vm.state.tied ? TVTheme.green : .white.opacity(0.5))
                            }
                            .padding(.horizontal, 28).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(i == 0 && !vm.state.tied ? TVTheme.green.opacity(0.15)
                                                               : .white.opacity(0.05)))
                        }
                        if vm.state.tied {
                            Text("Tied — nobody wins the lot")
                                .font(.system(.title3, design: .rounded)).foregroundColor(TVTheme.orange)
                        }
                    }
                    .padding(.horizontal, 260)
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Spectrum

struct WavelengthState {
    var base = RoundBoardState()
    var leftLabel = ""
    var rightLabel = ""
    var clue = ""
    var dial: Int? = nil
    var target: Int? = nil
    var points: Int? = nil
    var psychicName = ""

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["leftLabel"]?.value as? String { leftLabel = v }
        if let v = d["rightLabel"]?.value as? String { rightLabel = v }
        if let v = d["clue"]?.value as? String { clue = v }
        if let v = d["psychicName"]?.value as? String { psychicName = v }
        dial = d["dial"]?.value as? Int
        target = d["target"]?.value as? Int
        points = d["pointsAwarded"]?.value as? Int
    }
}

struct TVWavelengthBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: WavelengthState()) { $0.update(from: $1) }

    private let width: CGFloat = 1100

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "antenna.radiowaves.left.and.right", title: "Spectrum",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: "\(vm.state.psychicName) is the psychic")
            Spacer()
            VStack(spacing: 34) {
                Text(vm.state.clue.isEmpty ? "waiting for a clue…" : "“\(vm.state.clue)”")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(vm.state.clue.isEmpty ? .white.opacity(0.3) : TVTheme.yellow)

                ZStack(alignment: .leading) {
                    LinearGradient(colors: [TVTheme.blue, TVTheme.purple, TVTheme.red],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width, height: 44)
                        .clipShape(Capsule())

                    // The target band appears only at reveal.
                    if let target = vm.state.target {
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: 60, height: 60)
                            .offset(x: width * CGFloat(target) / 100 - 30, y: 0)
                    }
                    if let dial = vm.state.dial {
                        RoundedRectangle(cornerRadius: 3).fill(.black)
                            .frame(width: 6, height: 74)
                            .offset(x: width * CGFloat(dial) / 100 - 3, y: 0)
                            .animation(.easeOut(duration: 0.2), value: dial)
                    }
                }
                .frame(width: width, height: 80)

                HStack {
                    Text(vm.state.leftLabel).font(.system(.title2, design: .rounded, weight: .bold)).foregroundColor(TVTheme.blue)
                    Spacer()
                    Text(vm.state.rightLabel).font(.system(.title2, design: .rounded, weight: .bold)).foregroundColor(TVTheme.red)
                }
                .frame(width: width)

                if let points = vm.state.points {
                    Text(points > 0 ? "+\(points)" : "Missed")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundColor(points > 0 ? TVTheme.green : .white.opacity(0.4))
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Bollywood Charades

struct CharadesState {
    var base = RoundBoardState()
    var actorName = ""
    var title: String? = nil
    var correctNames: [String] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["actorName"]?.value as? String { actorName = v }
        title = d["title"]?.value as? String
        correctNames = (d["correctNames"]?.value as? [Any] ?? []).compactMap { $0 as? String }
    }
}

struct TVBollywoodCharadesBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: CharadesState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "figure.dance", title: "Bollywood Charades",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: "\(vm.state.actorName) is acting")
            Spacer()
            VStack(spacing: 26) {
                if let title = vm.state.title {
                    VStack(spacing: 10) {
                        Text("THE FILM WAS").font(.system(.caption, design: .rounded, weight: .bold)).tracking(4)
                            .foregroundColor(.white.opacity(0.4))
                        Text(title).font(.system(size: 58, weight: .heavy, design: .rounded))
                            .foregroundColor(TVTheme.green)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "theatermasks.fill").font(.system(size: 110, weight: .regular, design: .rounded)).foregroundColor(.white.opacity(0.7))
                        Text("Act it out — no words!")
                            .font(.system(size: 44, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Text("Only \(vm.state.actorName) knows the film")
                            .font(.system(.title3, design: .rounded)).foregroundColor(.white.opacity(0.5))
                    }
                }

                if !vm.state.correctNames.isEmpty {
                    VStack(spacing: 8) {
                        Text("GOT IT").font(.system(.caption, design: .rounded, weight: .bold)).tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 12) {
                            ForEach(vm.state.correctNames, id: \.self) { name in
                                Text("\(name)").font(.system(.headline, design: .rounded)).foregroundColor(TVTheme.green)
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(Capsule().fill(TVTheme.green.opacity(0.15)))
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
