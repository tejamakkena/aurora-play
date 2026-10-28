import SwiftUI

/// Never Have I Ever on the TV.
///
/// The statement goes up (and is read aloud); everyone answers privately on their
/// phone; then the room finds out who has. During the answer phase this only ever
/// shows *how many* have answered -- who said what stays on the phones until the
/// reveal.

// MARK: - State

struct NHIEPack: Identifiable, Equatable {
    let id: String
    let name: String
    let emoji: String
    let blurb: String
    let adult: Bool
}

struct NHIEState {
    var base = RoundBoardState()
    var statement = ""
    var packName = ""
    var packEmoji = ""
    var packChoices: [NHIEPack] = []
    var haveCount: Int? = nil
    var neverCount: Int? = nil
    var confessors: [String] = []
    var spotlight: String? = nil
    var verdict = ""

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        statement = d["statement"]?.value as? String ?? ""
        if let pack = d["pack"]?.value as? [String: Any] {
            packName = pack["name"] as? String ?? ""
            packEmoji = pack["emoji"] as? String ?? ""
        }
        packChoices = (d["packChoices"]?.value as? [Any] ?? []).compactMap { item in
            guard let p = item as? [String: Any], let id = p["id"] as? String else { return nil }
            return NHIEPack(id: id,
                            name: p["name"] as? String ?? "",
                            emoji: p["emoji"] as? String ?? "",
                            blurb: p["blurb"] as? String ?? "",
                            adult: p["adult"] as? Bool ?? false)
        }
        haveCount = d["haveCount"]?.value as? Int
        neverCount = d["neverCount"]?.value as? Int
        confessors = (d["confessors"]?.value as? [Any] ?? []).compactMap { $0 as? String }
        spotlight = d["spotlight"]?.value as? String
        verdict = d["verdict"]?.value as? String ?? ""
    }
}

// MARK: - Board

struct TVNeverHaveIEverBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: NHIEState()) { $0.update(from: $1) }

    private var phase: String { vm.state.base.phase }

    private var phaseLabel: String {
        switch phase {
        case "pack":   return "choose a pack"
        case "answer": return vm.state.packName
        default:       return "the reveal"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(emoji: "🙋", title: "Never Have I Ever",
                          round: vm.state.base.round, totalRounds: vm.state.base.totalRounds,
                          secondsLeft: vm.state.base.secondsLeft,
                          phaseLabel: phaseLabel)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            TVScoreStrip(players: vm.state.base.players, highlight: vm.state.base.submitted)
        }
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: vm.state.statement) { _, statement in
            // Read each new statement aloud, in whatever voice the night picked.
            guard !statement.isEmpty else { return }
            Announcer.shared.say("Never have I ever \(statement)")
        }
        // Deliberately no onDisappear { stop() } here: inside a Game Night this
        // board disappears at the very moment the night's next announcement
        // starts, and stopping the shared voice would cut that off.
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case "pack":
            PackChooser(packs: vm.state.packChoices)
        case "answer":
            VStack(spacing: 30) {
                Statement(text: vm.state.statement)
                Text("\(vm.state.base.submitted.count) of \(vm.state.base.players.count) answered")
                    .font(.title2).foregroundColor(.white.opacity(0.5))
            }
        default:
            Reveal(state: vm.state)
        }
    }
}

// MARK: - Pieces

/// "Never have I ever ..." with the statement under it.
private struct Statement: View {
    let text: String

    var body: some View {
        VStack(spacing: 18) {
            Text("NEVER HAVE I EVER...")
                .font(.system(size: 30, weight: .bold)).tracking(8)
                .foregroundColor(.orange)
            Text(text)
                .font(.system(size: 62, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 120)
        }
    }
}

private struct PackChooser: View {
    let packs: [NHIEPack]

    var body: some View {
        VStack(spacing: 30) {
            Text("The host is choosing a pack")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4),
                      spacing: 20) {
                ForEach(packs) { pack in
                    VStack(spacing: 8) {
                        Text(pack.emoji).font(.system(size: 50))
                        Text(pack.name)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        if pack.adult {
                            Text("18+")
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10).padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        } else {
                            Text(pack.blurb)
                                .font(.system(size: 17))
                                .foregroundColor(.white.opacity(0.55))
                                .lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.07)))
                }
            }
            .padding(.horizontal, 100)
        }
    }
}

private struct Reveal: View {
    let state: NHIEState

    var body: some View {
        VStack(spacing: 26) {
            Statement(text: state.statement)

            HStack(spacing: 70) {
                CountBadge(emoji: "🙋", label: "HAVE", count: state.haveCount ?? 0, tint: .orange)
                CountBadge(emoji: "🙅", label: "NEVER", count: state.neverCount ?? 0, tint: .cyan)
            }

            if !state.confessors.isEmpty {
                HStack(spacing: 12) {
                    ForEach(state.confessors.prefix(8), id: \.self) { name in
                        Text(name)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(Color.orange))
                    }
                    if state.confessors.count > 8 {
                        Text("+\(state.confessors.count - 8)")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            if let spotlight = state.spotlight {
                Text("🎤 \(spotlight), tell us the story!")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
            }

            Text(state.verdict)
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.white.opacity(0.75))
        }
    }
}

private struct CountBadge: View {
    let emoji: String
    let label: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 54))
            Text("\(count)")
                .font(.system(size: 84, weight: .black, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 22, weight: .bold)).tracking(5)
                .foregroundColor(.white.opacity(0.55))
        }
    }
}
