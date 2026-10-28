import SwiftUI

/// TV board for Guess the Song. A word goes up; the team shouts a song that fits
/// it (the Hindi meaning, the word in the title, or the word as a prop in the
/// scene). A judge on a phone taps Guessed or Not guessed. The answers stay off
/// this screen until the judge says the team missed. Then they appear here with a
/// joke, and a guess gets praise and a joke.
///
/// Server side: games/native_hub/engines/guess_the_song.py.

struct GTSTeam: Identifiable, Equatable {
    let id: Int
    let name: String
    let symbol: String
    let score: Int

    init?(_ any: Any?) {
        guard let d = any as? [String: Any], let id = d["id"] as? Int else { return nil }
        self.id = id
        name = d["name"] as? String ?? ""
        symbol = d["symbol"] as? String ?? "music.note"
        score = d["score"] as? Int ?? 0
    }
}

struct GuessSongBoardState {
    var base = RoundBoardState()
    var word = ""
    var hint: String? = nil
    /// The deck's language for the hint ("Hindi", "Telugu"); empty for a deck
    /// without hints. Older servers send none: Hindi.
    var hintLabel = "Hindi"
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
        hintLabel = d["hintLabel"]?.value as? String ?? "Hindi"
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
        guard let outcome else { return "" }
        return "\(base.round)-\(outcome)"
    }
}

struct TVGuessTheSongBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: GuessSongBoardState()) { $0.update(from: $1) }
    @StateObject private var voice = TVVoiceHost()

    private var state: GuessSongBoardState { vm.state }
    private var phase: String { state.base.phase }
    private var guessed: Bool { state.outcome == "guessed" }

    private var phaseLabel: String {
        if state.isTeamMode, let team = state.activeTeam { return "\(team.name) is up" }
        return "everyone guesses"
    }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "music.mic", title: "Guess the Song",
                          round: state.base.round, totalRounds: state.base.totalRounds,
                          secondsLeft: phase == "reveal" ? 0 : state.base.secondsLeft,
                          phaseLabel: phaseLabel)
            Spacer(minLength: 12)
            if phase == "reveal" { reveal } else { wordView }
            Spacer(minLength: 12)
            teamStrip
        }
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: state.word) { _, word in
            guard !word.isEmpty, phase == "guess" else { return }
            voice.speak("Your word is \(word).")
        }
        .onChange(of: state.verdictKey) { _, key in
            guard !key.isEmpty, !state.humor.isEmpty else { return }
            voice.speak((guessed ? "Good job! " : "Not guessed. ") + state.humor)
        }
    }

    private var wordView: some View {
        VStack(spacing: 22) {
            Text("NAME A SONG WITH...")
                .font(.system(size: 28, weight: .heavy, design: .rounded)).tracking(8)
                .foregroundColor(.white.opacity(0.55))
            Text(state.word)
                .font(.system(size: 150, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [ShellTheme.pink, ShellTheme.orange, ShellTheme.cyan],
                                                startPoint: .leading, endPoint: .trailing))
                .lineLimit(1).minimumScaleFactor(0.4)
                .padding(.horizontal, 100)
            Text(state.hintLabel.isEmpty ? "the word in the title, or in the scene"
                 : "its \(state.hintLabel) meaning, the word in the title, or in the scene")
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
            if let hint = state.hint {
                Text("\(state.hintLabel.isEmpty ? "Hint" : state.hintLabel): \(hint)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(ShellTheme.gold)
            }
            if phase == "verdict" {
                Text("Time is up! Waiting for the judge...")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(ShellTheme.orange)
            } else if let judge = state.judgeName {
                Text("\(judge) is judging")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    private var reveal: some View {
        VStack(spacing: 24) {
            Text(state.word)
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            if guessed {
                Label("Good job!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 100, weight: .heavy, design: .rounded))
                    .foregroundColor(ShellTheme.mint)
            } else {
                Label("Not guessed", systemImage: "xmark.circle.fill")
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .foregroundColor(ShellTheme.red)
                if !state.answers.isEmpty {
                    VStack(spacing: 10) {
                        Text("IT COULD HAVE BEEN")
                            .font(.system(size: 22, weight: .heavy, design: .rounded)).tracking(6)
                            .foregroundColor(.white.opacity(0.5))
                        ForEach(state.answers, id: \.self) { song in
                            Text(song)
                                .font(.system(size: 38, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }
                }
            }
            Text(state.humor)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.gold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 160)
            if !state.filler.isEmpty {
                Text(state.filler)
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 200)
            }
        }
    }

    private var teamStrip: some View {
        HStack(spacing: 24) {
            ForEach(state.teams) { team in
                HStack(spacing: 12) {
                    Image(systemName: team.symbol)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(ShellTheme.cyan)
                    Text(team.name)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(team.score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(ShellTheme.gold)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(team.id == state.activeTeam?.id ? ShellTheme.cyan.opacity(0.2) : Color.white.opacity(0.06)))
            }
        }
        .padding(.bottom, 30)
    }
}
