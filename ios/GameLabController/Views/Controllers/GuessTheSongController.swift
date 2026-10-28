import SwiftUI

/// Controller for Guess the Song. Everyone sees the word, so a round works on
/// phones alone. The judge also sees the example songs and the two verdict
/// buttons, which is the "guessed or not" tap that scores the round.
/// Server side: games/native_hub/engines/guess_the_song.py.
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
    private var guessed: Bool { privateData.str("outcome") == "guessed" }
    private var humor: String { privateData.str("humor") }
    private var filler: String { privateData.str("filler") }
    private var judgeName: String { privateData.str("judgeName", "The judge") }

    private var activeTeamName: String {
        let team = privateData["activeTeam"] as? [String: Any] ?? [:]
        return team["name"] as? String ?? "Everyone"
    }

    private var subtitle: String {
        if phase == "reveal" { return "The verdict" }
        if isJudge { return "You're the judge" }
        return isGuesser ? "Your turn. Shout a song!" : "\(activeTeamName) is guessing"
    }

    var body: some View {
        ControllerShell(title: "Guess the Song", subtitle: subtitle,
                        secondsLeft: phase == "reveal" ? nil : seconds) {
            if phase == "reveal" { revealPanel } else { playPanel }
        }
    }

    // MARK: Playing

    private var playPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("NAME A SONG WITH...")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(3)
                    .foregroundColor(PhonePlayDesign.text2)
                    .padding(.top, 22)
                Text(word)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .padding(.horizontal, 20)
                Text("its Hindi meaning, the word in the title, or in the scene")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                if let hint {
                    Text("Hindi: \(hint)")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.yellow)
                }
                if phase == "verdict" {
                    Text(isJudge ? "Time is up! Your call." : "Time is up! Waiting for \(judgeName)...")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.orange)
                }

                if isJudge {
                    judgePanel
                } else if isGuesser {
                    Text("\(judgeName) is judging. Say your answers out loud.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.cyan)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                } else {
                    Text("Listen in. \(activeTeamName) is guessing.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
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
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                    .foregroundColor(PhonePlayDesign.text2)
                ForEach(answers, id: \.self) { song in
                    Text(song)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text("Other songs that fit are fair game too.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface))
            .padding(.horizontal, 20)

            if hint == nil, let hindi, !hindi.isEmpty, phase == "guess" {
                Button {
                    PhonePlayHaptics.tap()
                    onAction("hint", [:])
                } label: {
                    Label("Give the Hindi hint (\(hindi))", systemImage: "lightbulb.fill")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.yellow)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(PhonePlayDesign.yellow.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PhonePlayPressStyle())
            }

            verdictButton("Guessed!", symbol: "checkmark.circle.fill", tint: PhonePlayDesign.green, result: "guessed")
            verdictButton("Not guessed", symbol: "xmark.circle.fill", tint: PhonePlayDesign.red, result: "missed")
        }
    }

    private func verdictButton(_ title: String, symbol: String, tint: Color, result: String) -> some View {
        Button {
            PhonePlayHaptics.tap()
            onAction("judge", ["result": result])
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous).fill(tint))
        }
        .buttonStyle(PhonePlayPressStyle())
        .padding(.horizontal, 20)
    }

    // MARK: Reveal

    private var revealPanel: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: guessed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(guessed ? PhonePlayDesign.green : PhonePlayDesign.red)
                    .padding(.top, 28)
                Text(guessed ? "Good job!" : "Not guessed")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(word)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)

                if !guessed && !answers.isEmpty {
                    VStack(spacing: 6) {
                        Text("IT COULD HAVE BEEN")
                            .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                            .foregroundColor(PhonePlayDesign.text2)
                        ForEach(answers, id: \.self) { song in
                            Text(song)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                Text(humor)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.yellow)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                if !filler.isEmpty {
                    Text(filler)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                }
            }
            .padding(.bottom, 24)
        }
    }
}
