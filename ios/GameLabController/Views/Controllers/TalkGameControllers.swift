import SwiftUI

/// Phone controllers for the two talk games (games/native_hub/engines/
/// talk.py). The talking happens out loud in the room; the phone only
/// carries what one player needs: a debater's side and argument starters,
/// a vote, the Answerer's secret and YES / NO / SOMETIMES buttons, or a
/// guess box.

// MARK: - Shared bits

private enum TalkPad {
    static let forColors: [Color] = [PhonePlayDesign.orange, PhonePlayDesign.red]
    static let againstColors: [Color] = [PhonePlayDesign.cyan, PhonePlayDesign.blue]
    static let yesColors: [Color] = [PhonePlayDesign.green, Color(hex: "0FA968")]
    static let noColors: [Color] = [PhonePlayDesign.red, Color(hex: "C81E4A")]
    static let sometimesColors: [Color] = [PhonePlayDesign.yellow, PhonePlayDesign.orange]

    static func verdictColor(_ answer: String) -> Color {
        switch answer {
        case "yes":       return PhonePlayDesign.green
        case "no":        return PhonePlayDesign.red
        case "sometimes": return PhonePlayDesign.yellow
        default:          return PhonePlayDesign.purple
        }
    }
}

/// A big centred status card: icon, headline, optional detail.
private struct TalkPadStatusCard: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = PhonePlayDesign.cyan

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(PhonePlayDesign.gradient([tint, .white]))
                .phonePlayIdle(dy: 3, scale: 0.03, duration: 1.4)
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .phonePlaySurfaceCard(tint: tint, padding: 0)
    }
}

// MARK: - Hot Takes

struct HotTakesControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "intro") }
    private var role: String { privateData.str("role", "voter") }
    private var prompt: String { privateData.str("prompt") }
    private var stance: String { privateData.str("stance") }
    private var hints: [String] { privateData.strings("hints") }
    private var isSpeaking: Bool { privateData.bool("isSpeaking") }
    private var canVote: Bool { privateData.bool("canVote") }
    private var hasVoted: Bool { privateData.bool("hasVoted") }
    private var myVote: String? { privateData["myVote"] as? String }
    private var forName: String { privateData.str("forName", "FOR") }
    private var againstName: String { privateData.str("againstName", "AGAINST") }
    private var forLabel: String { privateData.str("forLabel", "YES") }
    private var againstLabel: String { privateData.str("againstLabel", "NO") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var result: [String: Any]? { privateData["roundResult"] as? [String: Any] }

    private var isDebater: Bool { role == "for" || role == "against" }
    private var sideColors: [Color] { role == "for" ? TalkPad.forColors : TalkPad.againstColors }

    private var subtitle: String {
        switch role {
        case "for": return "You argue FOR"
        case "against": return "You argue AGAINST"
        default: return phase == "vote" ? "Vote for the better argument" : "Get ready to vote"
        }
    }

    var body: some View {
        ControllerShell(title: "Hot Takes", subtitle: subtitle, secondsLeft: seconds) {
            ScrollView {
                VStack(spacing: 16) {
                    if phase == "final" {
                        TalkPadStatusCard(symbol: "trophy.fill", title: "That is a wrap!",
                                          detail: "Final scores are on the TV",
                                          tint: PhonePlayDesign.yellow)
                    } else if isDebater {
                        debaterContent
                    } else {
                        voterContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .animation(PhonePlayDesign.pop, value: phase)
                .animation(PhonePlayDesign.pop, value: hasVoted)
                .animation(PhonePlayDesign.pop, value: myVote)
            }
        }
        .onChange(of: isSpeaking) { _, nowSpeaking in
            if nowSpeaking { PhonePlayHaptics.thump() }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == "vote" && canVote { PhonePlayHaptics.success() }
        }
    }

    // MARK: Debater

    @ViewBuilder
    private var debaterContent: some View {
        HotTakesPadSideCard(side: role == "for" ? "FOR" : "AGAINST", stance: stance,
                            prompt: prompt, colors: sideColors)
        switch phase {
        case "intro":
            TalkPadStatusCard(symbol: role == "for" ? "1.circle.fill" : "2.circle.fill",
                              title: role == "for" ? "You go first" : "You go second",
                              detail: "Argue out loud for 30 seconds. Use a starter below if you get stuck.",
                              tint: sideColors[0])
        case "for", "against":
            if isSpeaking {
                HotTakesPadSpeakingCard(colors: sideColors)
                PhonePlayBigButton(title: "I am done", symbol: "checkmark.circle.fill",
                                   colors: sideColors) {
                    onAction("done_speaking", [:])
                }
            } else if phase == "for" {
                TalkPadStatusCard(symbol: "ear.fill", title: "Listen closely",
                                  detail: "Your turn is next. Get your comeback ready.",
                                  tint: sideColors[0])
            } else {
                TalkPadStatusCard(symbol: "ear.fill", title: "Nice work",
                                  detail: "Now listen to \(againstName).",
                                  tint: sideColors[0])
            }
        case "switch":
            TalkPadStatusCard(symbol: "arrow.left.arrow.right",
                              title: role == "against" ? "Your turn now!" : "Switch!",
                              detail: role == "against" ? "Get ready to fight back." : "Over to \(againstName).",
                              tint: sideColors[0])
        case "vote":
            TalkPadStatusCard(symbol: "hourglass", title: "The room is voting",
                              detail: "Fingers crossed.", tint: sideColors[0])
        case "reveal":
            revealCard
        default:
            EmptyView()
        }
        if !hints.isEmpty && ["intro", "for", "switch", "against"].contains(phase) {
            HotTakesPadHints(hints: hints, tint: sideColors[0])
        }
    }

    // MARK: Voter

    @ViewBuilder
    private var voterContent: some View {
        switch phase {
        case "vote":
            if !prompt.isEmpty {
                HotTakesPadPromptCard(prompt: prompt)
            }
            Text(hasVoted ? "Vote counted. Tap the other side to change it." : "Who argued better?")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(hasVoted ? PhonePlayDesign.green : .white)
                .frame(maxWidth: .infinity)
            HotTakesPadVoteButton(side: "FOR", name: forName, stance: forLabel,
                                  colors: TalkPad.forColors,
                                  selected: myVote == "for", enabled: canVote) {
                onAction("vote", ["side": "for"])
            }
            HotTakesPadVoteButton(side: "AGAINST", name: againstName, stance: againstLabel,
                                  colors: TalkPad.againstColors,
                                  selected: myVote == "against", enabled: canVote) {
                onAction("vote", ["side": "against"])
            }
        case "reveal":
            revealCard
        default:
            TalkPadStatusCard(symbol: "hand.raised.fill", title: "Get ready to vote",
                              detail: "Listen to both sides. You will pick the better argument.",
                              tint: PhonePlayDesign.purple)
            if !prompt.isEmpty {
                HotTakesPadPromptCard(prompt: prompt)
            }
            HotTakesPadVersus(forName: forName, againstName: againstName,
                              forLabel: forLabel, againstLabel: againstLabel,
                              speaking: phase == "for" ? "for" : (phase == "against" ? "against" : ""))
        }
    }

    // MARK: Reveal

    @ViewBuilder
    private var revealCard: some View {
        let winnerSide: String? = result?["winnerSide"] as? String
        let landslide: Bool = result?["landslide"] as? Bool ?? false
        if let winnerSide {
            if isDebater {
                let won: Bool = winnerSide == role
                let points: Int = (role == "for" ? result?["forPoints"] : result?["againstPoints"]) as? Int ?? 0
                TalkPadStatusCard(symbol: won ? "trophy.fill" : "hand.thumbsup.fill",
                                  title: won ? (landslide ? "Landslide win!" : "You won the debate!")
                                             : "Tough crowd",
                                  detail: points > 0 ? "+\(points) points" : "Better luck next time",
                                  tint: won ? PhonePlayDesign.yellow : sideColors[0])
            } else {
                let agreed: Bool = myVote == winnerSide
                TalkPadStatusCard(symbol: agreed ? "checkmark.seal.fill" : "tv",
                                  title: agreed ? "Your pick won!" : "The room disagreed",
                                  detail: "Check the TV for the votes",
                                  tint: agreed ? PhonePlayDesign.green : PhonePlayDesign.purple)
            }
        } else {
            TalkPadStatusCard(symbol: "equal.circle.fill", title: "Dead heat",
                              detail: "Check the TV for the votes", tint: PhonePlayDesign.yellow)
        }
    }
}

private struct HotTakesPadSideCard: View {
    let side: String
    let stance: String
    let prompt: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 10) {
            Text("YOU ARGUE")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.white.opacity(0.8))
            Text(side)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            if !stance.isEmpty {
                Text(stance)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(colors.first ?? .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white))
            }
            Text(prompt)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient(colors))
        )
        .shadow(color: (colors.first ?? .clear).opacity(0.4), radius: 18, y: 8)
    }
}

private struct HotTakesPadSpeakingCard: View {
    let colors: [Color]

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(PhonePlayDesign.gradient(colors))
                .symbolEffect(.variableColor.iterative, options: .repeating)
            Text("You are on! Talk out loud")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Look at the room, not the phone.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .phonePlaySurfaceCard(tint: colors.first, padding: 0)
    }
}

private struct HotTakesPadHints: View {
    let hints: [String]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhonePlaySectionLabel(text: "Argument starters")
            ForEach(Array(hints.enumerated()), id: \.offset) { pair in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(tint)
                        .padding(.top, 2)
                    Text(pair.element)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface)
                )
            }
        }
    }
}

private struct HotTakesPadPromptCard: View {
    let prompt: String

    var body: some View {
        VStack(spacing: 6) {
            Text("THE HOT TAKE")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.orange)
            Text(prompt)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .phonePlaySurfaceCard(tint: PhonePlayDesign.orange)
    }
}

private struct HotTakesPadVersus: View {
    let forName: String
    let againstName: String
    let forLabel: String
    let againstLabel: String
    let speaking: String

    var body: some View {
        HStack(spacing: 10) {
            column(side: "FOR", name: forName, label: forLabel,
                   colors: TalkPad.forColors, active: speaking == "for")
            Text("VS")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
            column(side: "AGAINST", name: againstName, label: againstLabel,
                   colors: TalkPad.againstColors, active: speaking == "against")
        }
        .animation(PhonePlayDesign.pop, value: speaking)
    }

    private func column(side: String, name: String, label: String,
                        colors: [Color], active: Bool) -> some View {
        VStack(spacing: 4) {
            Text(side)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(colors.first ?? .white)
            Text(name)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(active ? (colors.first ?? .clear).opacity(0.25) : PhonePlayDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .strokeBorder((colors.first ?? .clear).opacity(active ? 0.9 : 0.2), lineWidth: active ? 2 : 1)
        )
        .scaleEffect(active ? 1.04 : 1)
    }
}

private struct HotTakesPadVoteButton: View {
    let side: String
    let name: String
    let stance: String
    let colors: [Color]
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            PhonePlayHaptics.rigid()
            action()
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(side) - \(stance)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.85))
                    Text(name)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(colors))
                    .opacity(selected ? 1 : 0.55)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(selected ? 0.9 : 0), lineWidth: 3)
            )
            .shadow(color: (colors.first ?? .clear).opacity(selected ? 0.5 : 0.15), radius: 16, y: 6)
            .scaleEffect(selected ? 1.02 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!enabled)
        .animation(PhonePlayDesign.pop, value: selected)
    }
}

// MARK: - 20 Questions

struct TwentyQuestionsControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var guessing: Bool = false
    @State private var guessText: String = ""
    @State private var answerLocked: Bool = false
    @State private var secretHidden: Bool = false
    @State private var wrongFlash: Bool = false
    @FocusState private var guessFocused: Bool

    private var phase: String { privateData.str("phase", "intro") }
    private var isAnswerer: Bool { privateData.bool("isAnswerer") }
    private var secret: String { privateData.str("secret") }
    private var category: String { privateData.str("category") }
    private var answererName: String { privateData.str("answererName", "The Answerer") }
    private var questionsUsed: Int { privateData.int("questionsUsed") }
    private var questionsLeft: Int { privateData.int("questionsLeft", 20) }
    private var maxQuestions: Int { max(1, privateData.int("maxQuestions", 20)) }
    private var tally: [String: Any] { privateData["tally"] as? [String: Any] ?? [:] }
    private var lastAnswer: String? { privateData["lastAnswer"] as? String }
    private var canGuess: Bool { privateData.bool("canGuess") }
    private var wrongGuesses: Int { privateData.int("wrongGuesses") }
    private var penalty: Int { privateData.int("penalty", 50) }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var result: [String: Any]? { privateData["roundResult"] as? [String: Any] }
    private var myPlayerID: String { privateData.str("myPlayerID") }

    private var subtitle: String {
        if phase == "final" { return "Game over" }
        if isAnswerer { return "You are the Answerer" }
        return category.isEmpty ? "Ask out loud" : "Category: \(category)"
    }

    var body: some View {
        ControllerShell(title: "20 Questions", subtitle: subtitle,
                        secondsLeft: phase == "ask" ? nil : seconds) {
            ScrollView {
                VStack(spacing: 16) {
                    switch phase {
                    case "final":
                        TalkPadStatusCard(symbol: "trophy.fill", title: "That is a wrap!",
                                          detail: "Final scores are on the TV",
                                          tint: PhonePlayDesign.yellow)
                    case "reveal":
                        revealContent
                    default:
                        if isAnswerer {
                            answererContent
                        } else {
                            guesserContent
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .animation(PhonePlayDesign.pop, value: phase)
                .animation(PhonePlayDesign.pop, value: guessing)
                .animation(PhonePlayDesign.pop, value: wrongFlash)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase != "ask" {
                guessing = false
                guessText = ""
                guessFocused = false
            }
            if newPhase == "intro" {
                secretHidden = false
                if isAnswerer { PhonePlayHaptics.thump() }
            }
            if newPhase == "reveal" { PhonePlayHaptics.success() }
        }
        .onChange(of: wrongGuesses) { oldValue, newValue in
            guard newValue > oldValue else { return }
            PhonePlayHaptics.error()
            wrongFlash = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                wrongFlash = false
            }
        }
    }

    // MARK: Answerer

    @ViewBuilder
    private var answererContent: some View {
        TwentyQPadSecretCard(category: category, secret: secret, hidden: secretHidden) {
            secretHidden.toggle()
        }
        if phase == "intro" {
            TalkPadStatusCard(symbol: "lock.fill", title: "Keep it secret",
                              detail: "Everyone will ask you yes or no questions out loud. "
                                + "Answer each one with a tap.",
                              tint: PhonePlayDesign.purple)
        } else {
            Text(questionsLeft > 0 ? "Question \(min(questionsUsed + 1, maxQuestions)) of \(maxQuestions)"
                                   : "Out of questions")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .frame(maxWidth: .infinity)
            TwentyQPadAnswerButton(title: "YES", symbol: "checkmark", colors: TalkPad.yesColors,
                                   enabled: !answerLocked) { answer("yes") }
            TwentyQPadAnswerButton(title: "NO", symbol: "xmark", colors: TalkPad.noColors,
                                   enabled: !answerLocked) { answer("no") }
            TwentyQPadAnswerButton(title: "SOMETIMES", symbol: "arrow.left.arrow.right",
                                   colors: TalkPad.sometimesColors,
                                   enabled: !answerLocked) { answer("sometimes") }
            TwentyQPadTallyRow(tally: tally, lastAnswer: lastAnswer)
        }
    }

    private func answer(_ value: String) {
        guard !answerLocked, phase == "ask" else { return }
        answerLocked = true
        onAction("answer", ["value": value])
        // One tap is one question: ignore a quick double tap.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            answerLocked = false
        }
    }

    // MARK: Guesser

    @ViewBuilder
    private var guesserContent: some View {
        TwentyQPadCategoryCard(category: category, answererName: answererName,
                               questionsLeft: questionsLeft, questionsUsed: questionsUsed,
                               maxQuestions: maxQuestions, intro: phase == "intro")
        if phase == "ask" {
            TwentyQPadTallyRow(tally: tally, lastAnswer: lastAnswer)
            if wrongFlash {
                TalkPadStatusCard(symbol: "xmark.octagon.fill", title: "Not it!",
                                  detail: "-\(penalty) points and one question used",
                                  tint: PhonePlayDesign.red)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if guessing {
                guessBox
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                PhonePlayBigButton(title: "I know it!", symbol: "lightbulb.fill",
                                   colors: [PhonePlayDesign.purple, PhonePlayDesign.pink],
                                   enabled: canGuess) {
                    guessing = true
                    onAction("buzz", [:])
                    // The field only exists once the box has appeared.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guessFocused = true
                    }
                }
                Text("A wrong guess costs \(penalty) points and a question.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        } else {
            TalkPadStatusCard(symbol: "bubble.left.and.bubble.right.fill",
                              title: "Get your questions ready",
                              detail: "\(answererName) is reading the secret. Ask yes or no questions out loud.",
                              tint: PhonePlayDesign.cyan)
        }
    }

    private var trimmedGuess: String {
        guessText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var guessBox: some View {
        VStack(spacing: 12) {
            PhonePlaySectionLabel(text: "Your guess")
            TextField("", text: $guessText, prompt: Text("Type it here").foregroundColor(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .strokeBorder(PhonePlayDesign.purple.opacity(0.6), lineWidth: 1.5)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($guessFocused)
                .onSubmit { submitGuess() }
                .onChange(of: guessText) { _, newValue in
                    if newValue.count > 60 { guessText = String(newValue.prefix(60)) }
                }
            PhonePlayBigButton(title: "Guess", symbol: "paperplane.fill",
                               colors: [PhonePlayDesign.purple, PhonePlayDesign.pink],
                               enabled: canGuess && !trimmedGuess.isEmpty) {
                submitGuess()
            }
            PhonePlayGhostButton(title: "Cancel", symbol: "xmark") {
                guessing = false
                guessText = ""
                guessFocused = false
                onAction("cancel_buzz", [:])
            }
        }
        .phonePlaySurfaceCard(tint: PhonePlayDesign.purple)
    }

    private func submitGuess() {
        let text: String = trimmedGuess
        guard canGuess, !text.isEmpty else { return }
        onAction("guess", ["text": text])
        guessText = ""
        guessing = false
        guessFocused = false
    }

    // MARK: Reveal

    @ViewBuilder
    private var revealContent: some View {
        let solved: Bool = result?["solved"] as? Bool ?? false
        let solverID: String = result?["solverID"] as? String ?? ""
        let solverName: String = result?["solverName"] as? String ?? ""
        let solverPoints: Int = result?["solverPoints"] as? Int ?? 0
        let answererPoints: Int = result?["answererPoints"] as? Int ?? 0
        let secretText: String = secret.isEmpty ? (result?["secret"] as? String ?? "") : secret
        VStack(spacing: 8) {
            Text("IT WAS")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(.white.opacity(0.8))
            Text(secretText)
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient([PhonePlayDesign.purple, PhonePlayDesign.indigo]))
        )
        if solved && solverID == myPlayerID {
            TalkPadStatusCard(symbol: "star.fill", title: "You got it!",
                              detail: "+\(solverPoints) points", tint: PhonePlayDesign.yellow)
        } else if isAnswerer {
            TalkPadStatusCard(symbol: answererPoints > 0 ? "hand.thumbsup.fill" : "person.fill.questionmark",
                              title: answererPoints > 0 ? "Good game!" : (solved ? "Solved" : "Nobody got it"),
                              detail: answererPoints > 0 ? "+\(answererPoints) Answerer bonus"
                                                         : "Check the TV",
                              tint: PhonePlayDesign.green)
        } else {
            TalkPadStatusCard(symbol: "tv",
                              title: solved ? "\(solverName) got it" : "Nobody got it",
                              detail: "Check the TV", tint: PhonePlayDesign.cyan)
        }
    }
}

private struct TwentyQPadSecretCard: View {
    let category: String
    let secret: String
    let hidden: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("YOUR SECRET")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Button {
                    PhonePlayHaptics.tap()
                    onToggle()
                } label: {
                    Image(systemName: hidden ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(PhonePlayPressStyle())
            }
            Text(category.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(.white.opacity(0.75))
            Text(secret.isEmpty ? "..." : secret)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .blur(radius: hidden ? 14 : 0)
                .animation(PhonePlayDesign.smooth, value: hidden)
            Text(hidden ? "Tap the eye to peek" : "Do not let anyone see this")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient([PhonePlayDesign.purple, PhonePlayDesign.indigo]))
        )
        .shadow(color: PhonePlayDesign.purple.opacity(0.4), radius: 18, y: 8)
    }
}

private struct TwentyQPadAnswerButton: View {
    let title: String
    let symbol: String
    let colors: [Color]
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            PhonePlayHaptics.rigid()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .black))
                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
            }
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(colors))
            )
            .shadow(color: (colors.first ?? .clear).opacity(0.35), radius: 14, y: 6)
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!enabled)
    }
}

private struct TwentyQPadTallyRow: View {
    let tally: [String: Any]
    let lastAnswer: String?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                chip("YES", tally["yes"] as? Int ?? 0, PhonePlayDesign.green)
                chip("NO", tally["no"] as? Int ?? 0, PhonePlayDesign.red)
                chip("SOMETIMES", tally["sometimes"] as? Int ?? 0, PhonePlayDesign.yellow)
            }
            if let lastAnswer {
                HStack(spacing: 8) {
                    Text("Last answer")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                    Text(lastAnswer.uppercased())
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(TalkPad.verdictColor(lastAnswer)))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func chip(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(color)
                .contentTransition(.numericText())
                .animation(PhonePlayDesign.pop, value: count)
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundColor(PhonePlayDesign.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }
}

private struct TwentyQPadCategoryCard: View {
    let category: String
    let answererName: String
    let questionsLeft: Int
    let questionsUsed: Int
    let maxQuestions: Int
    let intro: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("CATEGORY")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(PhonePlayDesign.cyan)
            Text(category.isEmpty ? "?" : category)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
            Text("\(answererName) knows the answer")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
            if !intro {
                HStack(spacing: 3) {
                    ForEach(0..<maxQuestions, id: \.self) { i in
                        Capsule()
                            .fill(i < questionsUsed ? PhonePlayDesign.cyan : Color.white.opacity(0.1))
                            .frame(height: 8)
                    }
                }
                .animation(PhonePlayDesign.pop, value: questionsUsed)
                Text(questionsLeft == 1 ? "1 question left" : "\(questionsLeft) questions left")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(questionsLeft <= 5 ? PhonePlayDesign.red : .white)
                    .contentTransition(.numericText())
                    .animation(PhonePlayDesign.pop, value: questionsLeft)
            }
        }
        .frame(maxWidth: .infinity)
        .phonePlaySurfaceCard(tint: PhonePlayDesign.cyan)
    }
}
