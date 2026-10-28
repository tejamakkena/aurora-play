import SwiftUI

/// Guess the Song on the TV.
///
/// A word goes up; the team shouts out a song that fits it (the Hindi meaning,
/// the word in the title, or the word as a prop in the scene). A judge on a phone
/// taps Guessed or Not guessed. The answers stay off this screen until the judge
/// says the team missed -- then they are revealed here, with a joke.

// MARK: - State

struct GTSTeam: Identifiable, Equatable {
    let id: Int
    let name: String
    let emoji: String
    let score: Int
    let members: [String]

    init?(_ any: Any?) {
        guard let d = any as? [String: Any], let id = d["id"] as? Int else { return nil }
        self.id = id
        name = d["name"] as? String ?? ""
        emoji = d["emoji"] as? String ?? ""
        score = d["score"] as? Int ?? 0
        members = (d["members"] as? [Any] ?? []).compactMap { $0 as? String }
    }
}

struct GuessSongState {
    var base = RoundBoardState()
    var word = ""
    var hint: String? = nil
    var isTeamMode = false
    var activeTeam: GTSTeam? = nil
    var teams: [GTSTeam] = []
    var judgeName: String? = nil
    var outcome: String? = nil
    var answers: [String] = []
    var humor = ""
    var filler = ""

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        word = d["word"]?.value as? String ?? ""
        hint = d["hint"]?.value as? String
        isTeamMode = (d["mode"]?.value as? String) == "teams"
        activeTeam = GTSTeam(d["activeTeam"]?.value)
        teams = (d["teams"]?.value as? [Any] ?? []).compactMap { GTSTeam($0) }
        judgeName = d["judgeName"]?.value as? String
        outcome = d["outcome"]?.value as? String
        answers = (d["answers"]?.value as? [Any] ?? []).compactMap { $0 as? String }
        humor = d["humor"]?.value as? String ?? ""
        filler = d["filler"]?.value as? String ?? ""
    }

    /// Changes once per verdict, so the joke is read aloud once per round.
    var verdictKey: String {
        outcome == nil ? "" : "\(base.round)-\(outcome ?? "")"
    }
}

// MARK: - Board

struct TVGuessTheSongBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: GuessSongState()) { $0.update(from: $1) }

    private var state: GuessSongState { vm.state }

    private var phaseLabel: String {
        if state.isTeamMode, let team = state.activeTeam {
            return "\(team.emoji) \(team.name) is up"
        }
        return "everyone guesses"
    }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(emoji: "🎧", title: "Guess the Song",
                          round: state.base.round, totalRounds: state.base.totalRounds,
                          secondsLeft: state.base.phase == "reveal" ? 0 : state.base.secondsLeft,
                          phaseLabel: phaseLabel)
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            GTSTeamStrip(teams: state.teams, activeID: state.activeTeam?.id)
        }
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: state.word) { _, word in
            guard !word.isEmpty, state.base.phase == "guess" else { return }
            Announcer.shared.say("Your word is \(word)")
        }
        .onChange(of: state.verdictKey) { _, key in
            // The reaction and its joke, read in the night's voice.
            guard !key.isEmpty, !state.humor.isEmpty else { return }
            let opener = state.outcome == "guessed" ? "Good job!" : "Not guessed."
            Announcer.shared.speak([opener, state.humor], style: Announcer.shared.style)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.base.phase {
        case "reveal":
            GTSReveal(state: state)
        case "verdict":
            GTSWord(state: state, banner: "⏰ Time's up! Waiting for the judge...")
        default:
            GTSWord(state: state, banner: nil)
        }
    }
}

// MARK: - Pieces

/// The word, big, with how it can be answered.
private struct GTSWord: View {
    let state: GuessSongState
    let banner: String?

    var body: some View {
        VStack(spacing: 22) {
            Text("NAME A SONG WITH...")
                .font(.system(size: 28, weight: .bold)).tracking(8)
                .foregroundColor(.white.opacity(0.55))

            Text(state.word)
                .font(.system(size: 150, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "FF3CAC"), Color(hex: "FFB347"), Color(hex: "22D3EE")],
                                   startPoint: .leading, endPoint: .trailing))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, 100)

            Text("its Hindi meaning   •   the word in the title   •   or in the scene")
                .font(.system(size: 26))
                .foregroundColor(.white.opacity(0.55))

            if let hint = state.hint {
                Text("💡 Hindi: \(hint)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.yellow)
            }

            if let banner {
                Text(banner)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.orange)
            } else if let judge = state.judgeName {
                Text("🎤 \(judge) is judging")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }
}

private struct GTSReveal: View {
    let state: GuessSongState

    private var guessed: Bool { state.outcome == "guessed" }

    var body: some View {
        VStack(spacing: 24) {
            Text(state.word)
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            if guessed {
                Text("🎉 Good job!")
                    .font(.system(size: 110, weight: .black, design: .rounded))
                    .foregroundColor(.green)
            } else {
                Text("❌ Not guessed")
                    .font(.system(size: 90, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                if !state.answers.isEmpty {
                    VStack(spacing: 10) {
                        Text("IT COULD HAVE BEEN")
                            .font(.system(size: 22, weight: .bold)).tracking(6)
                            .foregroundColor(.white.opacity(0.5))
                        ForEach(state.answers, id: \.self) { song in
                            Text("🎵 \(song)")
                                .font(.system(size: 38, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
            }

            Text(state.humor)
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(.yellow)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 160)

            if !state.filler.isEmpty {
                Text(state.filler)
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 200)
            }
        }
    }
}

private struct GTSTeamStrip: View {
    let teams: [GTSTeam]
    let activeID: Int?

    var body: some View {
        HStack(spacing: 24) {
            ForEach(teams) { team in
                HStack(spacing: 12) {
                    Text(team.emoji).font(.system(size: 34))
                    Text(team.name)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(team.score)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.cyan)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(team.id == activeID ? Color.cyan.opacity(0.18) : Color.white.opacity(0.06))
                )
            }
        }
        .padding(.bottom, 40)
    }
}
