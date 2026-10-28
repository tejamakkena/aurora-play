import SwiftUI

/// TV board for Never Have I Ever. The statement goes up (and is read aloud);
/// everyone answers privately on their phone; then the room finds out who has.
/// During the answer phase this only ever shows how many have answered. Who said
/// what stays on the phones until the reveal.
///
/// Server side: games/native_hub/engines/never_have_i_ever.py.

struct NHIEPack: Identifiable, Equatable {
    let id: String
    let name: String
    let symbol: String
    let blurb: String
    let adult: Bool
}

struct NHIEBoardState {
    var base = RoundBoardState()
    var statement = ""
    var packName = ""
    var packChoices: [NHIEPack] = []
    var haveCount = 0
    var neverCount = 0
    var confessors: [String] = []
    var spotlight: String? = nil
    var verdict = ""

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        statement = d["statement"]?.value as? String ?? ""
        if let pack = d["pack"]?.value as? [String: Any] {
            packName = pack["name"] as? String ?? ""
        }
        packChoices = (d["packChoices"]?.value as? [Any] ?? []).compactMap { item in
            guard let p = item as? [String: Any], let id = p["id"] as? String else { return nil }
            return NHIEPack(id: id,
                            name: p["name"] as? String ?? "",
                            symbol: p["symbol"] as? String ?? "questionmark",
                            blurb: p["blurb"] as? String ?? "",
                            adult: p["adult"] as? Bool ?? false)
        }
        haveCount = d["haveCount"]?.value as? Int ?? 0
        neverCount = d["neverCount"]?.value as? Int ?? 0
        confessors = (d["confessors"]?.value as? [Any] ?? []).compactMap { $0 as? String }
        spotlight = d["spotlight"]?.value as? String
        verdict = d["verdict"]?.value as? String ?? ""
    }
}

struct TVNeverHaveIEverBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: NHIEBoardState()) { $0.update(from: $1) }
    @StateObject private var voice = TVVoiceHost()

    private var state: NHIEBoardState { vm.state }
    private var phase: String { state.base.phase }

    private var phaseLabel: String {
        switch phase {
        case "pack": return "the host is choosing a pack"
        case "answer": return state.packName.isEmpty ? "answer on your phone" : state.packName
        default: return "the reveal"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "hand.raised.fill", title: "Never Have I Ever",
                          round: state.base.round, totalRounds: state.base.totalRounds,
                          secondsLeft: phase == "reveal" ? 0 : state.base.secondsLeft,
                          phaseLabel: phaseLabel)
            Spacer(minLength: 12)
            content
            Spacer(minLength: 12)
            TVScoreStrip(players: state.base.players, highlight: state.base.submitted)
                .padding(.bottom, 30)
        }
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: state.statement) { _, statement in
            guard !statement.isEmpty else { return }
            voice.speak("Never have I ever \(statement).")
        }
        // No stopSpeaking on disappear: inside a Game Night this board goes away
        // as the night's next announcement starts, and stopping would cut it off.
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case "pack":
            packChooser
        case "answer":
            VStack(spacing: 30) {
                statementView
                Text("\(state.base.submitted.count) of \(max(state.base.players.count, state.base.submitted.count)) answered")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        default:
            reveal
        }
    }

    private var statementView: some View {
        VStack(spacing: 18) {
            Text("NEVER HAVE I EVER...")
                .font(.system(size: 30, weight: .heavy, design: .rounded)).tracking(8)
                .foregroundColor(ShellTheme.orange)
            Text(state.statement)
                .font(.system(size: 62, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 120)
        }
    }

    private var packChooser: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4), spacing: 20) {
            ForEach(state.packChoices) { pack in
                VStack(spacing: 10) {
                    Image(systemName: pack.symbol)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(pack.adult ? ShellTheme.orange : ShellTheme.cyan)
                    Text(pack.name)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(pack.adult ? "18+" : pack.blurb)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(pack.adult ? ShellTheme.orange : .white.opacity(0.55))
                        .lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 170)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 100)
    }

    private var reveal: some View {
        VStack(spacing: 24) {
            statementView
            HStack(spacing: 80) {
                count("I HAVE", state.haveCount, ShellTheme.orange)
                count("NEVER", state.neverCount, ShellTheme.cyan)
            }
            if !state.confessors.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(state.confessors.prefix(8).enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(ShellTheme.orange))
                    }
                    if state.confessors.count > 8 {
                        Text("+\(state.confessors.count - 8)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            if let spotlight = state.spotlight {
                Text("\(spotlight), tell us the story!")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(ShellTheme.gold)
            }
            Text(state.verdict)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
        }
    }

    private func count(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 84, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 22, weight: .heavy, design: .rounded)).tracking(5)
                .foregroundColor(.white.opacity(0.55))
        }
    }
}
