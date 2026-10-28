import SwiftUI

/// Guess the Song on the phone.
///
/// Everyone sees the word, so the game works on phones alone. The judge also
/// sees the 2-3 example songs and the two verdict buttons -- that is the "guessed
/// or not" choice that scores the round. Guessers just shout.
struct GuessTheSongControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "guess") }
    private var word: String { privateData.str("word") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var isJudge: Bool { privateData.bool("isJudge") }
    private var isGuesser: Bool { privateData.bool("isGuesser") }
    private var answers: [String] { privateData.strings("answers") }
    private var hint: String? { privateData["hint"] as? String }
    private var hindi: String? { privateData["hindi"] as? String }
    private var outcome: String? { privateData["outcome"] as? String }
    private var humor: String { privateData.str("humor") }
    private var filler: String { privateData.str("filler") }
    private var judgeName: String { privateData.str("judgeName", "The judge") }
    private var isTeamMode: Bool { privateData.str("mode") == "teams" }

    private var activeTeamName: String {
        let team = privateData["activeTeam"] as? [String: Any] ?? [:]
        return "\(team["emoji"] as? String ?? "") \(team["name"] as? String ?? "Everyone")"
    }

    private var subtitle: String {
        if phase == "reveal" { return "The verdict" }
        if isJudge { return "You're the judge" }
        return isGuesser ? "Your turn. Shout a song!" : "\(activeTeamName) is guessing"
    }

    var body: some View {
        ControllerShell(title: "🎧 Guess the Song", subtitle: subtitle,
                        secondsLeft: phase == "reveal" ? nil : seconds) {
            if phase == "reveal" {
                RevealPanel(outcome: outcome, humor: humor, filler: filler,
                            word: word, answers: answers)
            } else {
                playPanel
            }
        }
    }

    // MARK: Playing

    private var playPanel: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("NAME A SONG WITH...")
                    .font(.caption.bold()).tracking(4)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 24)
                Text(word)
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.horizontal, 20)
                Text("its Hindi meaning, the word in the title, or in the scene")
                    .font(.footnote).foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if let hint {
                    Text("💡 Hindi: \(hint)")
                        .font(.title3.bold()).foregroundColor(.yellow)
                }

                if phase == "verdict" {
                    Text("⏰ Time's up!" + (isJudge ? " Your call." : " Waiting for \(judgeName)..."))
                        .font(.headline).foregroundColor(.orange)
                }

                if isJudge {
                    judgePanel
                } else if isGuesser {
                    Text("🎤 \(judgeName) is judging. Say your answers out loud.")
                        .font(.subheadline).foregroundColor(.cyan)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                } else {
                    Text("👂 Listen in. \(activeTeamName) is guessing.")
                        .font(.subheadline).foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                }
            }
            .padding(.bottom, 24)
        }
    }

    /// Only the judge ever sees this.
    private var judgePanel: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ANY OF THESE COUNTS")
                    .font(.caption.bold()).tracking(3)
                    .foregroundColor(.white.opacity(0.45))
                ForEach(answers, id: \.self) { song in
                    Text("🎵 \(song)")
                        .font(.body.weight(.semibold)).foregroundColor(.white)
                }
                Text("Other songs that fit are fair game too.")
                    .font(.caption).foregroundColor(.white.opacity(0.4))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
            .padding(.horizontal, 20)

            if hint == nil, let hindi, !hindi.isEmpty {
                Button {
                    onAction("hint", [:])
                } label: {
                    Label("Give the Hindi hint (\(hindi))", systemImage: "lightbulb.fill")
                        .font(.subheadline.bold()).foregroundColor(.yellow)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().stroke(Color.yellow.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(phase != "guess")
            }

            BigButton(title: "Guessed!", systemImage: "checkmark.circle.fill", tint: .green) {
                onAction("judge", ["result": "guessed"])
            }
            BigButton(title: "Not guessed", systemImage: "xmark.circle.fill", tint: .red) {
                onAction("judge", ["result": "missed"])
            }
        }
    }
}

/// The outcome, the joke, and (on a miss) what the answers were.
private struct RevealPanel: View {
    let outcome: String?
    let humor: String
    let filler: String
    let word: String
    let answers: [String]

    private var guessed: Bool { outcome == "guessed" }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(guessed ? "🎉" : "❌").font(.system(size: 70)).padding(.top, 28)
                Text(guessed ? "Good job!" : "Not guessed")
                    .font(.largeTitle.bold())
                    .foregroundColor(guessed ? .green : .red)
                Text(word).font(.headline).foregroundColor(.white.opacity(0.55))

                if !guessed && !answers.isEmpty {
                    VStack(spacing: 6) {
                        Text("IT COULD HAVE BEEN")
                            .font(.caption.bold()).tracking(3)
                            .foregroundColor(.white.opacity(0.45))
                        ForEach(answers, id: \.self) { song in
                            Text("🎵 \(song)")
                                .font(.body.weight(.semibold)).foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 4)
                }

                Text(humor)
                    .font(.headline).foregroundColor(.yellow)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                if !filler.isEmpty {
                    Text(filler)
                        .font(.footnote).foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                }
            }
            .padding(.bottom, 24)
        }
    }
}
