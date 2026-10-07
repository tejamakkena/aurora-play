import SwiftUI

/// Brain Battle on the phone: four big coloured answer buttons (the same
/// colours as the TV tiles), drawn shapes for rotation puzzles, a lock-in
/// state, and right/wrong feedback at the reveal.
///
/// private_state (games/native_hub/engines/brain_battle.py): phase, round,
/// totalRounds, secondsLeft, kind, skill, prompt, options, visual, myAnswer,
/// locked, myScore, wasCorrect, pointsEarned, correctAnswer, isFastest, and
/// at the summary rank, brainTitle, brainScore, personalBest.
struct BrainBattleControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    /// Optimistic lock so a double tap never sends two answers; cleared when
    /// a new puzzle arrives.
    @State private var pendingChoice: String? = nil
    @State private var pendingPuzzle: String = ""

    private static let tileColors: [Color] = [
        Color(hex: "FF3D7F"), Color(hex: "3D8BFF"), Color(hex: "FFB020"), Color(hex: "22C77A"),
    ]
    private static let letters: [String] = ["A", "B", "C", "D"]

    private var phase: String { privateData.str("phase") }
    private var puzzleID: String { privateData.str("puzzleID") }
    private var round: Int { privateData.int("round") }
    private var totalRounds: Int { privateData.int("totalRounds", 12) }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var kind: String { privateData.str("kind") }
    private var skill: String { privateData.str("skill") }
    private var options: [String] { privateData.strings("options") }
    private var myScore: Int { privateData.int("myScore") }

    private var myAnswer: String? {
        if let server = privateData["myAnswer"] as? String { return server }
        return pendingPuzzle == puzzleID ? pendingChoice : nil
    }

    private var locked: Bool { privateData.bool("locked") || myAnswer != nil }

    private var shapes: [[BrainCell]] {
        guard kind == "rotation", let visual = privateData["visual"] as? [String: Any] else { return [] }
        return BrainCell.shapes(from: visual["choices"])
    }

    private var subtitle: String {
        if round <= 0 { return "Get ready" }
        let base: String = "Round \(round) of \(totalRounds)"
        return skill.isEmpty ? base : "\(base) - \(skill)"
    }

    var body: some View {
        ControllerShell(title: "Brain Battle",
                        subtitle: subtitle,
                        secondsLeft: phase == "answer" ? seconds : nil) {
            VStack(spacing: 16) {
                scoreLine
                phaseContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 12)
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: locked)
        }
    }

    private var scoreLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.yellow)
            Text("SCORE")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
            Spacer()
            Text("\(myScore)")
                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(.white)
                .contentTransition(.numericText())
                .animation(PhonePlayDesign.pop, value: myScore)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case "memorize":
            WaitingState(systemIcon: "eye.fill",
                         text: "Eyes on the TV!",
                         detail: "Memorize the digits before they vanish.")
        case "answer":
            if locked {
                lockedView
            } else {
                answerButtons
            }
        case "reveal":
            BrainRevealFeedback(wasCorrect: privateData["wasCorrect"] as? Bool,
                                answered: privateData["myAnswer"] is String,
                                points: privateData.int("pointsEarned"),
                                isFastest: privateData.bool("isFastest"),
                                correctAnswer: correctAnswerText)
        case "summary", "final":
            BrainFinalCard(rank: privateData.int("rank"),
                           title: privateData.str("brainTitle", "Brain in Training"),
                           brainScore: privateData.int("brainScore"),
                           personalBest: privateData.bool("personalBest"),
                           score: myScore)
        default:
            WaitingState(systemIcon: "brain", text: "Get ready", detail: "The first puzzle is on its way.")
        }
    }

    private var correctAnswerText: String {
        let answer: String = privateData.str("correctAnswer")
        if kind == "rotation" && !answer.isEmpty { return "Shape \(answer)" }
        return answer
    }

    // MARK: Answering

    private var answerButtons: some View {
        let opts: [String] = options
        let rows: Int = (opts.count + 1) / 2
        return VStack(spacing: 12) {
            Text(kind == "rotation" ? "Which shape is the first one turned?" : "Pick your answer")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 12) {
                    buttonOrSpacer(row * 2, options: opts)
                    buttonOrSpacer(row * 2 + 1, options: opts)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func buttonOrSpacer(_ index: Int, options opts: [String]) -> some View {
        if index < opts.count {
            BrainAnswerButton(letter: letter(index),
                              text: opts[index],
                              color: color(index),
                              shape: index < shapes.count ? shapes[index] : []) {
                choose(opts[index])
            }
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func choose(_ option: String) {
        guard !locked else { return }
        pendingChoice = option
        pendingPuzzle = puzzleID
        PhonePlayHaptics.rigid()
        onAction("answer", ["choice": option])
    }

    private var lockedView: some View {
        let answer: String = myAnswer ?? ""
        let index: Int = options.firstIndex(of: answer) ?? 0
        let tint: Color = color(index)
        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([tint.opacity(0.6), tint.opacity(0.25)]))
                    .frame(width: 100, height: 100)
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .shadow(color: tint.opacity(0.4), radius: 16, y: 6)
            .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
            Text("Locked in")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
            HStack(spacing: 12) {
                Text(letter(index))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                if kind == "rotation", index < shapes.count {
                    BrainShapeView(cells: shapes[index], color: .white, depth: 2)
                        .frame(width: 120, height: 80)
                } else {
                    Text(answer)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient([tint, tint.opacity(0.7)]))
            )
            .shadow(color: tint.opacity(0.35), radius: 14, y: 6)
            Text("Waiting for everyone else...")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .padding(24)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private func color(_ index: Int) -> Color {
        let all: [Color] = BrainBattleControllerView.tileColors
        return all[((index % all.count) + all.count) % all.count]
    }

    private func letter(_ index: Int) -> String {
        let all: [String] = BrainBattleControllerView.letters
        return index >= 0 && index < all.count ? all[index] : "\(index + 1)"
    }
}

// MARK: - Answer button

private struct BrainAnswerButton: View {
    let letter: String
    let text: String
    let color: Color
    let shape: [BrainCell]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(letter)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white))
                if shape.isEmpty {
                    Text(text)
                        .font(.system(size: text.count > 14 ? 20 : 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 8)
                } else {
                    BrainShapeView(cells: shape, color: .white, depth: 2)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient([color, color.opacity(0.65)]))
            )
            .overlay(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
            .shadow(color: color.opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

// MARK: - Reveal feedback

private struct BrainRevealFeedback: View {
    let wasCorrect: Bool?
    let answered: Bool
    let points: Int
    let isFastest: Bool
    let correctAnswer: String
    @State private var popped: Bool = false

    private var correct: Bool { wasCorrect ?? false }
    private var tint: Color { correct ? PhonePlayDesign.green : PhonePlayDesign.red }

    private var headline: String {
        if correct { return "Correct!" }
        return answered ? "Not quite" : "Too slow!"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .shadow(color: tint.opacity(0.6), radius: 18)
                .scaleEffect(popped ? 1.0 : 0.3)
            Text(headline)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
            if correct {
                Text("+\(points)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(tint)
            }
            if isFastest {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                    Text("FASTEST IN THE ROOM").tracking(1)
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(PhonePlayDesign.yellow))
            }
            if !correct && !correctAnswer.isEmpty {
                Text("Answer: \(correctAnswer)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface)
                    )
            }
        }
        .padding(24)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5)) { popped = true }
            if correct {
                PhonePlayHaptics.success()
            } else {
                PhonePlayHaptics.error()
            }
        }
    }
}

// MARK: - Final card

private struct BrainFinalCard: View {
    let rank: Int
    let title: String
    let brainScore: Int
    let personalBest: Bool
    let score: Int

    var body: some View {
        VStack(spacing: 16) {
            if rank > 0 {
                Text(rank == 1 ? "YOU WON!" : "You placed #\(rank)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(rank == 1 ? PhonePlayDesign.yellow : .white)
            }
            Image(systemName: "brain")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.pink, PhonePlayDesign.cyan]))
                .phonePlayIdle(dy: 4, scale: 0.04, duration: 1.6)
            Text(title)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                stat("BRAIN SCORE", "\(brainScore)")
                stat("POINTS", "\(score)")
            }
            if personalBest {
                Label("New personal best!", systemImage: "star.fill")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(PhonePlayDesign.green))
                    .shadow(color: PhonePlayDesign.green.opacity(0.4), radius: 10, y: 4)
            }
        }
        .padding(24)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }
}
