import SwiftUI

// MARK: - Travel Mode views
//
// Every travel screen shares three things: a dark high-contrast canvas
// readable at arm's length, oversized touch targets, and the persistent
// safety footer ("Driver: voice only — never touch the phone.").

// MARK: - Design tokens (quizmaster spec §5)

/// The visual contract for Travel Mode. All new UI uses these; existing
/// components are migrated opportunistically.
enum TravelDesign {
    static let bg        = Color(hex: "0B0B12")
    static let surface   = Color(hex: "15151F")
    static let surface2  = Color(hex: "1E1E2B")
    static let primary   = Color(hex: "2FE07A")
    static let onPrimary = Color(hex: "06210F")
    static let info      = Color(hex: "38D6F5")
    static let warning   = Color(hex: "FFC531")
    static let danger    = Color(hex: "FF5A5A")
    static let text2     = Color(hex: "A7A7B8")
    static let text3     = Color(hex: "6B6B7E")

    /// 8pt grid; cards 20, buttons 18.
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 18
}

// MARK: - Root

struct TravelModeRootView: View {
    @EnvironmentObject var vm: ControllerRootViewModel
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        ZStack {
            Color(hex: "0a0a14").ignoresSafeArea()

            VStack(spacing: 0) {
                travelTopBar

                Group {
                    switch travel.stage {
                    case .setup:
                        TravelSetupView(travel: travel)
                    case .loading:
                        TravelLoadingView(travel: travel)
                    case .trivia:
                        TravelTriviaView(travel: travel)
                    case .hosted:
                        TravelHostView(travel: travel)
                    case .results:
                        TravelResultsView(travel: travel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TravelSafetyFooter()
            }
        }
    }

    private var travelTopBar: some View {
        HStack {
            Label("Travel Mode", systemImage: "car.fill")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            if let code = travel.roomCode {
                Text(code)
                    .font(.subheadline.monospaced().bold())
                    .foregroundColor(.white.opacity(0.5))
            }
            Button("End") { vm.endTravel() }
                .font(.subheadline.bold())
                .foregroundColor(.red.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }
}

/// Shown if a phone joins a travel-game room through the normal join flow
/// instead of Travel Mode: the game is playable, but only from the
/// Travel Mode host screen.
struct TravelExternalControllerView: View {
    let gameID: GameID

    var body: some View {
        WaitingState(
            systemIcon: "car.fill",
            text: "\(gameID.displayName) runs in Travel Mode",
            detail: "Leave this room and start Travel Mode from the join screen to host it in the car."
        )
    }
}

// MARK: - Safety footer

struct TravelSafetyFooter: View {
    var body: some View {
        Text(TravelCopy.safetyLine)
            .font(.callout.bold())
            .foregroundColor(.yellow.opacity(0.95))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.yellow.opacity(0.08))
    }
}

// MARK: - Loading

struct TravelLoadingView: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .scaleEffect(2.2)
                .tint(.cyan)
            Text(travel.loadingMessage)
                .font(.title3.bold())
                .foregroundColor(.white)
            if travel.selectedGame.isServerHosted {
                Text("The phone is creating a room and seating every player.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }
}

// MARK: - Setup (game picker + roster + topic)

struct TravelSetupView: View {
    @ObservedObject var travel: TravelModeViewModel
    @ObservedObject private var socket = GameSocketManager.shared
    @FocusState private var focusedField: Bool

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Game picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick a game")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(TravelGame.allCases) { game in
                            TravelGameCard(
                                game: game,
                                selected: travel.selectedGame == game
                            ) {
                                travel.selectedGame = game
                                travel.errorMessage = nil
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Topic picker — trivia only.
                if travel.selectedGame.usesTopic {
                    TravelTopicPicker(travel: travel, focusedField: $focusedField)
                }

                // Roster
                TravelRosterEditor(travel: travel, focusedField: $focusedField)

                // Start
                VStack(spacing: 10) {
                    if travel.selectedGame == .trivia {
                        Toggle(isOn: $travel.quizmasterOn) {
                            HStack(spacing: 10) {
                                Image(systemName: "waveform")
                                    .foregroundColor(TravelDesign.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Voice quizmaster")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text("The host asks aloud -- answer by voice. Tap answers still work.")
                                        .font(.caption)
                                        .foregroundColor(TravelDesign.text2)
                                }
                            }
                        }
                        .tint(TravelDesign.primary)
                        .padding(.horizontal, 20)
                    }
                    if let error = travel.errorMessage {
                        Text(error)
                            .font(.callout.bold())
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    if travel.selectedGame.isServerHosted && !socket.isConnected {
                        Text("Waiting for the server connection…")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    BigButton(
                        title: travel.selectedGame.usesTopic ? "Get Questions & Start" : "Start Game",
                        systemImage: "play.fill",
                        tint: .green,
                        enabled: travel.canStart
                            && (!travel.selectedGame.isServerHosted || socket.isConnected)
                    ) {
                        focusedField = false
                        travel.startGame()
                    }
                    if !travel.canStart {
                        Text("\(travel.selectedGame.displayName) needs at least \(travel.selectedGame.minPlayers) players.")
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
        .onTapGesture { focusedField = false }
    }
}

struct TravelGameCard: View {
    let game: TravelGame
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: game.sfSymbol)
                    .font(.system(size: 34))
                    .foregroundColor(selected ? .black : .cyan)
                Text(game.displayName)
                    .font(.headline.bold())
                    .foregroundColor(selected ? .black : .white)
                    .multilineTextAlignment(.center)
                Text(game.blurb)
                    .font(.caption)
                    .foregroundColor(selected ? .black.opacity(0.7) : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 128)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? Color.green : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? Color.green : Color.white.opacity(0.12),
                                          lineWidth: selected ? 3 : 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: Topic picker (trivia)

struct TravelTopicPicker: View {
    @ObservedObject var travel: TravelModeViewModel
    var focusedField: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Topic")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            TextField("e.g. Tollywood movies", text: $travel.topic)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundColor(.white)
                .focused(focusedField)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1.5))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(travel.topicChips, id: \.self) { chip in
                        Button {
                            travel.topic = chip
                            focusedField.wrappedValue = false
                        } label: {
                            Text(chip)
                                .font(.headline)
                                .foregroundColor(travel.topic == chip ? .black : .cyan)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(travel.topic == chip
                                              ? Color.cyan
                                              : Color.cyan.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Text("Fresh questions are generated on your topic. Leave it blank for general knowledge.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 20)
        }
    }
}

// MARK: Roster editor

struct TravelRosterEditor: View {
    @ObservedObject var travel: TravelModeViewModel
    var focusedField: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Players in the car")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            Text("The first player holds the phone and operates every seat.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.45))
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(Array(travel.roster.enumerated()), id: \.element.id) { index, player in
                    HStack(spacing: 12) {
                        if index == 0 {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.4))
                                .font(.title3)
                        }
                        TextField("Name", text: binding(for: player))
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .foregroundColor(.white)
                            .focused(focusedField)
                        if index == 0 {
                            Text("Phone holder")
                                .font(.caption2.bold())
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.15)))
                        }
                        if travel.roster.count > 1 {
                            Button {
                                travel.removePlayer(player)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06)))
                }

                if travel.roster.count < 8 {
                    HStack(spacing: 12) {
                        TextField("Add player", text: $travel.newPlayerName)
                            .textFieldStyle(.plain)
                            .font(.title3)
                            .foregroundColor(.white)
                            .focused(focusedField)
                            .onSubmit { travel.addPlayer() }
                        Button(action: travel.addPlayer) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func binding(for player: TravelPlayer) -> Binding<String> {
        Binding(
            get: {
                travel.roster.first(where: { $0.id == player.id })?.name ?? ""
            },
            set: { newValue in
                if let i = travel.roster.firstIndex(where: { $0.id == player.id }) {
                    travel.roster[i].name = String(newValue.prefix(20))
                }
            }
        )
    }
}

// MARK: - Scoreboard (shared)

/// Local +1 tally. The roster can grow or shrink mid-game; that only
/// affects this phone's scoreboard, never the room's seats.
struct TravelScoreboard: View {
    @ObservedObject var travel: TravelModeViewModel
    @FocusState private var addingPlayer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scoreboard")
                .font(.title3.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 20)

            VStack(spacing: 8) {
                ForEach(travel.rankedRoster) { player in
                    HStack(spacing: 14) {
                        Text(player.name)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(travel.scores[player.id] ?? 0)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.cyan)
                            .frame(minWidth: 48)
                        Button {
                            travel.awardPlusOne(player)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("1")
                            }
                            .font(.title3.bold())
                            .foregroundColor(.black)
                            .frame(width: 76, height: 56)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.green))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05)))
                }

                HStack(spacing: 12) {
                    TextField("Add player", text: $travel.newPlayerName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundColor(.white)
                        .focused($addingPlayer)
                        .onSubmit { addAndClear() }
                    Button("Add", action: addAndClear)
                        .font(.body.bold())
                        .foregroundColor(.cyan)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }
            .padding(.horizontal, 20)
        }
    }

    private func addAndClear() {
        travel.addPlayer()
        addingPlayer = false
    }
}

// MARK: - Read Aloud button (shared)

struct TravelReadAloudButton: View {
    @ObservedObject var speech: TravelSpeech
    let text: () -> String

    var body: some View {
        Button {
            if speech.isSpeaking { speech.stop() } else { speech.speak(text()) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.title2)
                Text(speech.isSpeaking ? "Stop" : "Read Aloud")
                    .font(.title3.bold())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

// MARK: - Quizmaster mic (push-to-talk)

/// The 96pt centerpiece of the voice round. States are unmistakable at a
/// glance: color + motion + label, never color alone (spec §5.1).
/// Press-and-hold re-arms the listening window; release finalizes --
/// the reliable input in a noisy car.
struct QuizmasterMicButton: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        Button(action: {}) {
            ZStack {
                if travel.quizPhase == .listening {
                    Circle()
                        .fill(TravelDesign.primary.opacity(0.35))
                        .frame(width: 116, height: 116)
                        .scaleEffect(1.12)
                        .opacity(0.6)
                        .animation(.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: true),
                            value: travel.quizPhase == .listening)
                }
                Circle()
                    .fill(TravelDesign.surface2)
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(ringColor, lineWidth: 2.5))
                Group {
                    if travel.quizPhase == .locked || travel.quizPhase == .grading {
                        ProgressView()
                            .tint(TravelDesign.primary)
                            .scaleEffect(1.6)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in travel.holdToTalkBegan() }
                .onEnded { _ in travel.holdToTalkEnded() }
        )
        .disabled(travel.quizPhase != .listening)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Press and hold while answering, release when done.")
    }

    private var iconName: String {
        switch travel.quizPhase {
        case .idle:      return "mic.slash.fill"
        case .asking:    return "speaker.wave.2.fill"
        case .listening: return "mic.fill"
        case .locked:    return "checkmark.circle.fill"
        case .grading:   return "ellipsis"
        }
    }

    private var iconColor: Color {
        switch travel.quizPhase {
        case .listening: return TravelDesign.primary
        case .asking:    return TravelDesign.info
        default:         return TravelDesign.text3
        }
    }

    private var ringColor: Color {
        switch travel.quizPhase {
        case .listening: return TravelDesign.primary
        case .asking:    return TravelDesign.info.opacity(0.6)
        default:         return Color.white.opacity(0.12)
        }
    }

    private var accessibilityLabel: String {
        switch travel.quizPhase {
        case .asking:    return "Asking the question"
        case .listening: return "Listening for your answer"
        case .locked:    return "Answer locked in"
        case .grading:   return "Checking your answer"
        case .idle:      return "Microphone off"
        }
    }
}

/// One-line status under the mic: what the quizmaster is doing right now,
/// plus the live "hearing: ..." caption while listening.
struct QuizmasterStatusLine: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.headline)
                .foregroundColor(statusColor)
            if travel.quizPhase == .listening && !travel.liveTranscript.isEmpty {
                Text("Hearing: \(travel.liveTranscript)")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 32)
            }
        }
        .frame(minHeight: 56)
    }

    private var statusText: String {
        switch travel.quizPhase {
        case .asking:    return "Asking..."
        case .listening: return "Listening -- hold the mic and answer"
        case .locked:    return "Locked in"
        case .grading:   return "Checking..."
        case .idle:
            return travel.liveTranscript.isEmpty
                ? "Tap an answer below"
                : travel.liveTranscript
        }
    }

    private var statusColor: Color {
        switch travel.quizPhase {
        case .listening: return TravelDesign.primary
        case .asking:    return TravelDesign.info
        default:         return TravelDesign.text2
        }
    }
}

// MARK: - Client-side trivia

struct TravelTriviaView: View {
    @ObservedObject var travel: TravelModeViewModel

    private let letters = ["A", "B", "C", "D"]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let q = travel.currentQuestion {
                    // Progress
                    HStack {
                        Text("Question \(travel.questionIndex + 1) of \(travel.questions.count)")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        if travel.usedOfflineQuestions {
                            Text("Using offline questions")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // The question — large, high contrast.
                    Text(q.question)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)

                    if travel.quizmasterOn {
                        // The question is read automatically; the mic is
                        // the input. Tap answers below still work as the
                        // manual override.
                        QuizmasterMicButton(travel: travel)
                            .padding(.top, 8)
                        QuizmasterStatusLine(travel: travel)
                    } else {
                        TravelReadAloudButton(speech: travel.speech) {
                            travel.speakablePrompt()
                        }
                    }

                    // Answers
                    VStack(spacing: 14) {
                        ForEach(0..<4, id: \.self) { i in
                            TravelAnswerButton(
                                letter: letters[i],
                                text: q.options[i],
                                state: answerState(i, correct: q.correctIndex)
                            ) {
                                travel.pickChoice(i)
                            }
                            .disabled(travel.pickedChoice != nil)
                        }
                    }
                    .padding(.horizontal, 20)

                    if let picked = travel.pickedChoice {
                        Text(picked == q.correctIndex
                             ? "Correct — tap +1 for who got it right."
                             : "The answer was \(letters[q.correctIndex]).")
                            .font(.title3.bold())
                            .foregroundColor(picked == q.correctIndex ? .green : .white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let explanation = q.explanation, !explanation.isEmpty {
                            Text(explanation)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    } else if let verdict = travel.voiceVerdict {
                        // Voice round graded: same +1 scoreboard flow.
                        Text(verdict
                             ? "Correct — tap +1 for who got it right."
                             : "The answer was \(letters[q.correctIndex]).")
                            .font(.title3.bold())
                            .foregroundColor(verdict ? TravelDesign.primary
                                                    : .white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Button(travel.pickedChoice == nil && travel.voiceVerdict == nil
                           ? "Skip Question" : "Next Question") {
                        travel.advanceQuestion()
                    }
                    .font(.title3.bold())
                    .foregroundColor(.cyan)
                    .padding(.vertical, 14)
                }

                TravelScoreboard(travel: travel)
                    .padding(.bottom, 24)
            }
        }
    }

    private func answerState(_ index: Int, correct: Int) -> TravelAnswerState {
        guard let picked = travel.pickedChoice else { return .idle }
        if index == correct { return .correct }
        if index == picked { return .wrong }
        return .dimmed
    }
}

enum TravelAnswerState { case idle, correct, wrong, dimmed }

struct TravelAnswerButton: View {
    let letter: String
    let text: String
    let state: TravelAnswerState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text(letter)
                    .font(.title2.bold())
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(letterBG))
                    .foregroundColor(.white)
                Text(text)
                    .font(.title3)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(tileBG)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(tileBorder, lineWidth: 2))
            )
        }
        .buttonStyle(.plain)
    }

    private var letterBG: Color {
        switch state {
        case .idle:    return Color.white.opacity(0.15)
        case .correct: return Color.green
        case .wrong:   return Color.red
        case .dimmed:  return Color.white.opacity(0.08)
        }
    }

    private var tileBG: Color {
        switch state {
        case .idle:    return Color.white.opacity(0.06)
        case .correct: return Color.green.opacity(0.15)
        case .wrong:   return Color.red.opacity(0.10)
        case .dimmed:  return Color.white.opacity(0.03)
        }
    }

    private var tileBorder: Color {
        switch state {
        case .idle:    return Color.white.opacity(0.12)
        case .correct: return Color.green
        case .wrong:   return Color.red.opacity(0.6)
        case .dimmed:  return Color.white.opacity(0.05)
        }
    }
}

// MARK: - Hosted game screen (server-driven)

struct TravelHostView: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if travel.board.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        ProgressView().scaleEffect(1.6).tint(.cyan)
                        Text("Waiting for the first prompt…")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer().frame(height: 60)
                    }
                } else {
                    TravelPromptCard(travel: travel)
                    TravelGameActions(travel: travel)
                }

                TravelScoreboard(travel: travel)
                    .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
    }
}

/// The current prompt, large. Travel engines ship a TTS-written
/// `hostPrompt`; other engines fall back to their own prompt keys.
struct TravelPromptCard: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text(travel.selectedGame.displayName)
                .font(.caption.bold())
                .foregroundColor(.cyan)
                .tracking(2)

            Text(promptBody)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            if !promptDetail.isEmpty {
                Text(promptDetail)
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            TravelReadAloudButton(speech: travel.speech) {
                travel.speakablePrompt()
            }
        }
        .padding(.vertical, 8)
    }

    private var promptBody: String {
        let board = travel.board
        let host = board.str("hostPrompt")
        if !host.isEmpty { return host }
        switch travel.selectedGame {
        case .mostLikelyTo:
            return board.str("prompt").isEmpty ? "Waiting for the next prompt." : "Most likely to: \(board.str("prompt"))"
        case .wavelength:
            let clue = board.str("clue")
            if board.str("phase") == "reveal" {
                return "Target \(board.int("target")) — dial landed on \(board.int("dial"))."
            }
            if clue.isEmpty { return "Waiting for the psychic's clue…" }
            return "Clue: \(clue)"
        default:
            return "Waiting for the next prompt."
        }
    }

    private var promptDetail: String {
        let board = travel.board
        switch travel.selectedGame {
        case .wavelength:
            let left = board.str("leftLabel"), right = board.str("rightLabel")
            if !left.isEmpty { return "\(left)  ← →  \(right)" }
            return ""
        case .mostLikelyTo:
            let n = board.int("votesSoFar")
            if board.str("phase") == "vote" { return "\(n) vote\(n == 1 ? "" : "s") in so far" }
            return ""
        case .hotTakes:
            let s = board.int("secondsLeft")
            if board.str("phase") == "discuss", s > 0 { return "\(s) seconds left to argue" }
            return ""
        default:
            return ""
        }
    }
}

// MARK: - Per-game actions (all real protocol actions)

struct TravelGameActions: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        Group {
            switch travel.selectedGame {
            case .mostLikelyTo:    TravelMLTActions(travel: travel)
            case .wavelength:      TravelWavelengthActions(travel: travel)
            case .storyChain:      TravelStoryActions(travel: travel)
            case .twentyQuestions: TravelTwentyActions(travel: travel)
            case .hotTakes:        TravelHotTakesActions(travel: travel)
            case .trivia:          EmptyView()
            }
        }
    }
}

/// Big selectable seat chips — thumb-sized targets for a moving car.
struct TravelSeatChips: View {
    let names: [String]
    @Binding var selection: Int
    var exclude: Int? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(names.indices, id: \.self) { i in
                    if exclude != i {
                        Button {
                            selection = i
                        } label: {
                            Text(names[i])
                                .font(.headline)
                                .foregroundColor(selection == i ? .black : .white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selection == i ? Color.cyan : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: Most Likely To — record each seat's vote

struct TravelMLTActions: View {
    @ObservedObject var travel: TravelModeViewModel
    @State private var voter = 0
    @State private var target = 1

    var body: some View {
        let board = travel.board
        VStack(spacing: 16) {
            if board.str("phase") == "reveal" {
                VStack(spacing: 8) {
                    ForEach(board.dicts("roundResults").indices, id: \.self) { i in
                        let r = board.dicts("roundResults")[i]
                        HStack {
                            Text(r.str("name")).font(.title3.bold()).foregroundColor(.white)
                            if r.bool("topVoted") {
                                Text("Top pick").font(.caption2.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow))
                            }
                            Spacer()
                            Text("\(r.int("votes")) votes")
                                .font(.headline).foregroundColor(.cyan)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 20)
                Text("Next prompt is coming…")
                    .font(.callout).foregroundColor(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Whose vote?").font(.headline).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                    TravelSeatChips(names: travel.seatNames, selection: $voter)
                    Text("Voting for").font(.headline).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 20)
                    TravelSeatChips(names: travel.seatNames, selection: $target, exclude: voter)
                    BigButton(title: "Cast Vote", systemImage: "checkmark.circle.fill", tint: .cyan) {
                        let targetSeat = travel.seatID(for: validTarget)
                        travel.sendAction("vote", data: ["targetID": targetSeat], seat: voter)
                    }
                    .onChange(of: voter) { _ in
                        if target == voter { target = (voter + 1) % travel.seatCount }
                    }
                }
            }
        }
    }

    private var validTarget: Int {
        target == voter ? (voter + 1) % max(travel.seatCount, 1) : target
    }
}

// MARK: Wavelength — clue + dial

struct TravelWavelengthActions: View {
    @ObservedObject var travel: TravelModeViewModel
    @State private var clueText = ""
    @State private var dialValue: Double = 50
    @State private var guesser = 0
    @State private var peekTarget = false
    @FocusState private var clueFocused: Bool

    var body: some View {
        let board = travel.board
        let phase = board.str("phase")
        let psychicID = board.str("psychicID")
        let psychicIndex = max(travel.roster.indices.first(where: {
            travel.seatID(for: $0) == psychicID
        }) ?? 0, 0)

        VStack(spacing: 16) {
            if phase == "clue" {
                VStack(spacing: 12) {
                    Text("Psychic: \(travel.seatName(psychicID))")
                        .font(.title3.bold()).foregroundColor(.white)
                    // The target lives on the phone (psychic's private
                    // state). In the car the psychic peeks when safe —
                    // e.g. at a red light — then gives the clue by voice.
                    let target = travel.seatPrivate[psychicID]?.str("target") ?? ""
                    Button {
                        peekTarget.toggle()
                    } label: {
                        Text(peekTarget && !target.isEmpty
                             ? "Target: \(target)"
                             : "Target hidden — psychic taps to peek when safe")
                            .font(.headline)
                            .foregroundColor(peekTarget ? .yellow : .white.opacity(0.6))
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)

                    TextField("Type the psychic's clue", text: $clueText)
                        .textFieldStyle(.plain)
                        .font(.title3).foregroundColor(.white)
                        .focused($clueFocused)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                        .padding(.horizontal, 20)

                    BigButton(title: "Send Clue", systemImage: "paperplane.fill",
                              enabled: !clueText.trimmingCharacters(in: .whitespaces).isEmpty) {
                        travel.sendAction("give_clue",
                                          data: ["clue": clueText.trimmingCharacters(in: .whitespaces)],
                                          seat: psychicIndex)
                        clueText = ""
                        clueFocused = false
                    }
                }
            } else if phase == "dial" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Who's setting the dial?").font(.headline)
                        .foregroundColor(.white.opacity(0.7)).padding(.horizontal, 20)
                    TravelSeatChips(names: travel.seatNames, selection: $guesser,
                                    exclude: psychicIndex)
                    HStack {
                        Text("0").foregroundColor(.white.opacity(0.5))
                        Slider(value: $dialValue, in: 0...100, step: 1)
                            .tint(.cyan)
                        Text("100").foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    Text("Dial: \(Int(dialValue))")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                    BigButton(title: "Set Dial", systemImage: "dial.max.fill") {
                        travel.sendAction("set_dial",
                                          data: ["value": Int(dialValue)],
                                          seat: validGuesser(psychic: psychicIndex))
                    }
                }
            } else if phase == "reveal" {
                let pts = board.int("pointsAwarded")
                Text(pts > 0 ? "+\(pts) points" : "No points this round")
                    .font(.title2.bold())
                    .foregroundColor(pts > 0 ? .green : .white.opacity(0.6))
                Text("Next round is coming…")
                    .font(.callout).foregroundColor(.white.opacity(0.5))
            }
        }
        .onChange(of: psychicID) { _ in peekTarget = false }
    }

    private func validGuesser(psychic: Int) -> Int {
        guesser == psychic ? (psychic + 1) % max(travel.seatCount, 1) : guesser
    }
}

// MARK: Story Chain — sentences + vote + reveal

struct TravelStoryActions: View {
    @ObservedObject var travel: TravelModeViewModel
    @State private var sentence = ""
    @State private var voter = 0
    @State private var target = 1
    @FocusState private var sentenceFocused: Bool

    var body: some View {
        let board = travel.board
        let phase = board.str("phase")

        VStack(spacing: 16) {
            // The story so far — the host reads this aloud before each turn.
            let story = Array(board.dicts("story").suffix(6))
            if !story.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(story.indices, id: \.self) { i in
                        let s = story[i]
                        Text("“\(s.str("text"))” — \(s.str("name"))")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05)))
                .padding(.horizontal, 20)
            }

            if phase == "adding" {
                let currentID = board.str("currentPlayerID")
                let currentIndex = travel.roster.indices.first(where: {
                    travel.seatID(for: $0) == currentID
                }) ?? 0
                Text("\(travel.seatName(currentID.isEmpty ? travel.seatID(for: currentIndex) : currentID))'s turn — add one sentence")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                TextField("Type the spoken sentence", text: $sentence)
                    .textFieldStyle(.plain)
                    .font(.title3).foregroundColor(.white)
                    .focused($sentenceFocused)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                    .padding(.horizontal, 20)

                BigButton(title: "Add Sentence", systemImage: "plus.bubble.fill",
                          enabled: !sentence.trimmingCharacters(in: .whitespaces).isEmpty) {
                    travel.sendAction("add_sentence",
                                      data: ["sentence": sentence.trimmingCharacters(in: .whitespaces)],
                                      seat: currentIndex)
                    sentence = ""
                    sentenceFocused = false
                }
            } else if phase == "vote" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Whose vote?").font(.headline)
                        .foregroundColor(.white.opacity(0.7)).padding(.horizontal, 20)
                    TravelSeatChips(names: travel.seatNames, selection: $voter)
                    Text("Funniest contributor").font(.headline)
                        .foregroundColor(.white.opacity(0.7)).padding(.horizontal, 20)
                    TravelSeatChips(names: travel.seatNames, selection: $target, exclude: voter)
                    BigButton(title: "Cast Vote", systemImage: "checkmark.circle.fill", tint: .cyan) {
                        travel.sendAction("vote",
                                          data: ["targetID": travel.seatID(for: validTarget)],
                                          seat: voter)
                    }
                    .onChange(of: voter) { _ in
                        if target == voter { target = (voter + 1) % travel.seatCount }
                    }
                    BigButton(title: "Reveal Winner", systemImage: "eye.fill", tint: .yellow) {
                        travel.sendHostAction("reveal")
                    }
                }
            } else if phase == "final" {
                VStack(spacing: 8) {
                    ForEach(board.dicts("roundResults").indices, id: \.self) { i in
                        let r = board.dicts("roundResults")[i]
                        HStack {
                            Text(r.str("name")).font(.title3.bold()).foregroundColor(.white)
                            if r.bool("funniest") {
                                Text("Funniest").font(.caption2.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow))
                            }
                            Spacer()
                            Text("\(r.int("votes")) votes")
                                .font(.headline).foregroundColor(.cyan)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var validTarget: Int {
        target == voter ? (voter + 1) % max(travel.seatCount, 1) : target
    }
}

// MARK: 20 Questions — record questions, yes/no, guess, give up

struct TravelTwentyActions: View {
    @ObservedObject var travel: TravelModeViewModel
    @State private var questionText = ""
    @State private var guessText = ""
    @State private var peekSecret = false
    @FocusState private var focused: Bool

    var body: some View {
        let board = travel.board
        let phase = board.str("phase")
        let answererID = board.str("answererID")
        let answererIndex = travel.roster.indices.first(where: {
            travel.seatID(for: $0) == answererID
        }) ?? 0
        // Anyone but the answerer asks and guesses; default to seat 0
        // unless seat 0 is answering.
        let askerIndex = answererIndex == 0 ? (travel.seatCount > 1 ? 1 : 0) : 0

        VStack(spacing: 16) {
            if phase == "play" {
                // Asked questions
                let qs = board.dicts("questions")
                if !qs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(qs.indices, id: \.self) { i in
                            let q = qs[i]
                            HStack {
                                Text(q.str("text"))
                                    .font(.body).foregroundColor(.white)
                                Spacer()
                                if let a = q["answer"] as? String {
                                    Text(a.uppercased())
                                        .font(.caption.bold())
                                        .foregroundColor(a == "yes" ? .green : .red)
                                } else {
                                    Text("…").foregroundColor(.white.opacity(0.4))
                                }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05)))
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Text("\(board.int("questionsLeft")) questions left")
                    .font(.headline).foregroundColor(.white.opacity(0.6))

                // The secret: only the answerer's seat may know it. The
                // phone holds every seat, so it stays masked unless the
                // answerer is the phone operator — otherwise the answerer
                // peeks only when safe.
                let secret = travel.seatPrivate[answererID]?.str("secret") ?? ""
                Button {
                    peekSecret.toggle()
                } label: {
                    Text(secretLabel(answererIndex: answererIndex, secret: secret))
                        .font(.headline)
                        .foregroundColor(peekSecret ? .yellow : .white.opacity(0.6))
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                // Record a spoken question (as a non-answerer seat).
                TextField("Type the spoken question", text: $questionText)
                    .textFieldStyle(.plain)
                    .font(.title3).foregroundColor(.white)
                    .focused($focused)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                    .padding(.horizontal, 20)
                BigButton(title: "Ask Question", systemImage: "questionmark.bubble.fill",
                          enabled: !questionText.trimmingCharacters(in: .whitespaces).isEmpty) {
                    travel.sendAction("question",
                                      data: ["text": questionText.trimmingCharacters(in: .whitespaces)],
                                      seat: askerIndex)
                    questionText = ""
                    focused = false
                }

                // The answerer answers yes/no.
                Text("Answerer: \(travel.seatName(answererID))")
                    .font(.headline).foregroundColor(.white.opacity(0.7))
                HStack(spacing: 14) {
                    ForEach(["yes", "no"], id: \.self) { value in
                        Button(value.capitalized) {
                            travel.sendAction("answer", data: ["value": value], seat: answererIndex)
                        }
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(value == "yes" ? Color.green : Color.red))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // Guess at any time.
                TextField("Type a guess", text: $guessText)
                    .textFieldStyle(.plain)
                    .font(.title3).foregroundColor(.white)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                    .padding(.horizontal, 20)
                BigButton(title: "Guess", systemImage: "lightbulb.fill", tint: .yellow,
                          enabled: !guessText.trimmingCharacters(in: .whitespaces).isEmpty) {
                    travel.sendAction("guess",
                                      data: ["text": guessText.trimmingCharacters(in: .whitespaces)],
                                      seat: askerIndex)
                    guessText = ""
                }

                Button("Give Up — Reveal Answer") {
                    travel.sendAction("give_up", seat: 0)
                }
                .font(.headline).foregroundColor(.white.opacity(0.5))
            } else if phase == "reveal" {
                let secret = board.str("secret")
                if !secret.isEmpty {
                    Text("The secret was")
                        .font(.headline).foregroundColor(.white.opacity(0.6))
                    Text(secret)
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                BigButton(title: "Next Round", systemImage: "arrow.right.circle.fill", tint: .green) {
                    travel.sendHostAction("next_round")
                }
            }
        }
        .onChange(of: answererID) { _ in peekSecret = false }
    }

    private func secretLabel(answererIndex: Int, secret: String) -> String {
        if answererIndex == 0, !secret.isEmpty { return "Secret: \(secret)" }
        if peekSecret, !secret.isEmpty { return "Secret: \(secret)" }
        return "Secret hidden — answerer taps to peek when safe"
    }
}

// MARK: Hot Takes — award the winner

struct TravelHotTakesActions: View {
    @ObservedObject var travel: TravelModeViewModel
    @State private var winner = 0

    var body: some View {
        let board = travel.board
        VStack(spacing: 16) {
            if board.str("phase") == "award" {
                let awarded = board.str("awardedToName")
                if !awarded.isEmpty {
                    Text("\(awarded) takes the round")
                        .font(.title2.bold()).foregroundColor(.yellow)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Most convincing arguer").font(.headline)
                            .foregroundColor(.white.opacity(0.7)).padding(.horizontal, 20)
                        TravelSeatChips(names: travel.seatNames, selection: $winner)
                        BigButton(title: "Award 200 Points", systemImage: "trophy.fill", tint: .yellow) {
                            travel.sendHostAction("award",
                                                  data: ["targetID": travel.seatID(for: winner)])
                        }
                    }
                }
            } else {
                Text("Argue your case out loud — the host awards points when time is up.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

// MARK: - Results

struct TravelResultsView: View {
    @EnvironmentObject var vm: ControllerRootViewModel
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.yellow)
                    Text("Final Scores")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                    Text(travel.selectedGame.displayName)
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 24)

                VStack(spacing: 10) {
                    ForEach(Array(travel.rankedRoster.enumerated()), id: \.element.id) { place, player in
                        HStack(spacing: 14) {
                            Text("\(place + 1)")
                                .font(.title2.bold())
                                .foregroundColor(place == 0 ? .yellow : .white.opacity(0.5))
                                .frame(width: 32)
                            Text(player.name)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(travel.scores[player.id] ?? 0)")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(.cyan)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(place == 0
                                      ? Color.yellow.opacity(0.12)
                                      : Color.white.opacity(0.05))
                        )
                    }
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    let next = travel.nextInPlaylist()
                    BigButton(title: "Next Up: \(next.displayName)",
                              systemImage: next.sfSymbol, tint: .green) {
                        travel.selectedGame = next
                        travel.backToSetup()
                    }
                    BigButton(title: "Back to Setup", systemImage: "gearshape.fill",
                              tint: .cyan) {
                        travel.backToSetup()
                    }
                    Button("End Travel Mode") { vm.endTravel() }
                        .font(.headline)
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}
