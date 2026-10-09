import SwiftUI

/// TV board for Truth or Dare.
///
/// One phone (the host) types the names, picks a level, taps Start and judges
/// every card. Everyone else just watches. So the TV is the show: it picks the
/// next player at random, asks "truth or dare?", then reads the card out loud
/// through `TVVoiceHost`, huge enough to read from the sofa. A player caught
/// lying gets a red PUNISHMENT card instead.
///
/// Server side: games/native_hub/engines/truth_dare.py. `say.seq` increases on
/// every line the TV should speak, so the same sentence twice in a row is still
/// spoken twice.

struct TruthDareBoardState {
    struct Person: Identifiable, Equatable {
        let id: String
        let name: String
        let score: Int
    }

    var phase = "setup"
    var level = "family"
    var people: [Person] = []
    var currentID = ""
    var currentName = ""
    var kind = ""
    var prompt = ""
    var sayText = ""
    var saySeq = 0
    var lastOutcome = ""
    var lastName = ""

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["phase"]?.value as? String { phase = v }
        if let v = d["level"]?.value as? String { level = v }
        currentID = d["currentID"]?.value as? String ?? ""
        currentName = d["currentName"]?.value as? String ?? ""
        kind = d["kind"]?.value as? String ?? ""
        prompt = d["prompt"]?.value as? String ?? ""
        people = (d["participants"]?.value as? [Any] ?? []).compactMap { raw in
            guard let p = raw as? [String: Any], let id = p["id"] as? String,
                  let name = p["name"] as? String else { return nil }
            return Person(id: id, name: name, score: p["score"] as? Int ?? 0)
        }
        if let say = d["say"]?.value as? [String: Any] {
            sayText = say["text"] as? String ?? ""
            saySeq = say["seq"] as? Int ?? 0
        }
        if let last = d["lastResult"]?.value as? [String: Any] {
            lastOutcome = last["outcome"] as? String ?? ""
            lastName = last["name"] as? String ?? ""
        } else {
            lastOutcome = ""
            lastName = ""
        }
    }
}

struct TVTruthDareBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: TruthDareBoardState()) { $0.update(from: $1) }
    @StateObject private var voice = TVVoiceHost()

    private var state: TruthDareBoardState { vm.state }

    private var accent: Color {
        switch state.kind {
        case "truth":  return TVTheme.cyan
        case "dare":   return TVTheme.orange
        case "punish": return TVTheme.red
        default:       return ShellTheme.pink
        }
    }

    private var kindLabel: String {
        switch state.kind {
        case "truth":  return "TRUTH"
        case "dare":   return "DARE"
        case "punish": return "PUNISHMENT"
        default:       return ""
        }
    }

    private var levelLabel: String {
        switch state.level {
        case "teens":  return "Teens"
        case "adults": return "Adults"
        default:       return "Family"
        }
    }

    var body: some View {
        ZStack {
            ShellAmbientBackground()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                stage
                Spacer(minLength: 16)
                scoreStrip
            }
            .padding(.horizontal, 90)
            .padding(.top, 44)
            .padding(.bottom, 44)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: state.phase)
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: state.saySeq) { _, _ in speakLatest() }
        .onDisappear { voice.stopSpeaking() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 24) {
            ShellIconOrb(symbol: "bubble.left.and.bubble.right.fill",
                         top: ShellTheme.pink, bottom: ShellTheme.violet,
                         accent: ShellTheme.pink, size: 76, isLit: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Truth or Dare")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("\(levelLabel) level")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        switch state.phase {
        case "setup":
            setupStage
        case "choose":
            chooseStage
        case "prompt", "punish":
            cardStage
        default:
            VStack(spacing: 18) {
                Text("Game over")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Thanks for playing")
                    .font(.system(.title2, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var setupStage: some View {
        VStack(spacing: 26) {
            Text("Add everyone's name on the host phone")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            Text("Pick a level, then press Start. Nobody else needs the app.")
                .font(.system(.title2, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            if !state.people.isEmpty {
                HStack(spacing: 16) {
                    ForEach(state.people) { person in
                        Text(person.name)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22).padding(.vertical, 12)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var chooseStage: some View {
        VStack(spacing: 30) {
            if !state.lastOutcome.isEmpty {
                Text(outcomeLine)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
            Text(state.currentName)
                .font(.system(size: 110, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text("Truth or dare?")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(ShellTheme.pink)
        }
    }

    private var cardStage: some View {
        VStack(spacing: 28) {
            HStack(spacing: 18) {
                Text(state.currentName)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(kindLabel)
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .tracking(4)
                    .foregroundColor(.black)
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .background(Capsule().fill(accent))
            }
            TVGlassCard(cornerRadius: ShellTheme.cardRadius, tint: accent, padding: 0) {
                Text(state.prompt)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 64)
                    .padding(.vertical, 48)
                    .frame(maxWidth: .infinity)
            }
            if state.phase == "punish" {
                Text("Caught lying!")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(TVTheme.red)
            }
        }
    }

    private var outcomeLine: String {
        switch state.lastOutcome {
        case "truth":    return "\(state.lastName) told the truth"
        case "dare":     return "\(state.lastName) did the dare"
        case "punished": return "\(state.lastName) took the punishment"
        case "refused":  return "\(state.lastName) chickened out of the punishment"
        case "skipped":  return "\(state.lastName) passed"
        default:         return ""
        }
    }

    // MARK: Scores

    private var scoreStrip: some View {
        HStack(spacing: 14) {
            ForEach(state.people.sorted { $0.score > $1.score }) { person in
                let isCurrent = person.id == state.currentID && state.phase != "setup"
                HStack(spacing: 10) {
                    Text(person.name)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(person.score)")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundColor(ShellTheme.pink)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(isCurrent ? ShellTheme.pink.opacity(0.28)
                                                       : Color.white.opacity(0.08)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Voice

    /// Reads whatever the server last asked the TV to say.
    private func speakLatest() {
        guard state.saySeq > 0, !state.sayText.isEmpty else { return }
        voice.speak(state.sayText)
    }
}
