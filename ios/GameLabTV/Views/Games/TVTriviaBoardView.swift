import SwiftUI

struct TVTriviaBoardView: View {
    let room: Room
    @StateObject private var vm = TriviaboardViewModel()
    /// Voice quizmaster: the TV speaks, one phone listens (spec §13).
    @StateObject private var voiceHost = TVVoiceHost()

    var body: some View {
        VStack(spacing: 32) {
            // Score bar
            HStack {
                ForEach(vm.players) { p in
                    PlayerScoreChip(player: p, isAnswered: vm.answeredIDs.contains(p.id))
                }
            }
            .padding(.horizontal, 60)

            if let q = vm.currentQuestion {
                // Category tag
                Text(q.category.uppercased())
                    .font(.caption.bold())
                    .tracking(3)
                    .foregroundColor(.cyan.opacity(0.8))

                // Question
                Text(q.text)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 100)
                    .fixedSize(horizontal: false, vertical: true)

                // Choices — revealed one second after question appears
                if vm.showChoices {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 20
                    ) {
                        ForEach(Array(q.choices.enumerated()), id: \.offset) { idx, choice in
                            ChoiceTile(
                                label: choice,
                                index: idx,
                                state: vm.choiceState(for: idx, correctIndex: q.correctIndex)
                            )
                        }
                    }
                    .padding(.horizontal, 80)
                }

                // Timer ring
                TimerRing(secondsLeft: vm.secondsLeft, total: 20)

            } else {
                Text("Loading question…")
                    .foregroundColor(.white.opacity(0.3))
            }

            Spacer()
        }
        .padding(.top, 48)
        .background(Color(hex: "0a0a14").ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            TVVoiceOverlay(host: voiceHost)
        }
        .onAppear {
            vm.bind(roomCode: room.code)
            voiceHost.attach(roomCode: room.code)
            // Grade on the TV: it owns the question + correct answer.
            voiceHost.onFinalTranscript = { [weak vm] transcript in
                guard let q = vm?.currentQuestion else { return }
                voiceHost.gradeVoiceAnswer(transcript: transcript,
                                           question: q.text,
                                           options: q.choices,
                                           correctIndex: q.correctIndex)
            }
        }
        .onDisappear { voiceHost.detach() }
        .onChange(of: vm.currentQuestion?.text) { _ in
            if let q = vm.currentQuestion {
                voiceHost.askQuestion(speakableQuestion(q))
            }
        }
    }

    /// Host phrasing: spoken through the TV speakers when the question lands.
    private func speakableQuestion(_ q: TriviaQuestion) -> String {
        let letters = ["A", "B", "C", "D"]
        let opts = q.choices.enumerated()
            .map { "\(letters[$0.offset % letters.count]): \($0.element)" }
            .joined(separator: ". ")
        return "\(q.text). \(opts)."
    }
}

private struct PlayerScoreChip: View {
    let player: Player
    let isAnswered: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isAnswered ? Color.green.opacity(0.4) : Color.white.opacity(0.1))
                .frame(width: 10, height: 10)
            Text(player.name)
                .font(.body)
                .foregroundColor(isAnswered ? .white : .white.opacity(0.4))
            Text("\(player.score)")
                .font(.headline.bold())
                .foregroundColor(.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

private struct ChoiceTile: View {
    enum ChoiceState { case idle, correct, wrong }
    let label: String
    let index: Int
    let state: ChoiceState

    private let letters = ["A", "B", "C", "D"]

    var body: some View {
        HStack(spacing: 16) {
            // A question could carry more choices than the four letter
            // badges we draw; fall back to a numbered badge instead of
            // crashing on letters[index].
            Text(index < letters.count ? letters[index] : "\(index + 1)")
                .font(.headline.bold())
                .frame(width: 40, height: 40)
                .background(Circle().fill(badgeColor))
                .foregroundColor(.white)

            Text(label)
                .font(.title3)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tileFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(borderColor, lineWidth: 2)
                )
        )
    }

    private var badgeColor: Color {
        switch state {
        case .idle:    return Color.white.opacity(0.15)
        case .correct: return .green
        case .wrong:   return .red
        }
    }

    private var tileFill: Color {
        switch state {
        case .idle:    return Color.white.opacity(0.06)
        case .correct: return Color.green.opacity(0.15)
        case .wrong:   return Color.red.opacity(0.1)
        }
    }

    private var borderColor: Color {
        switch state {
        case .idle:    return Color.white.opacity(0.08)
        case .correct: return .green.opacity(0.8)
        case .wrong:   return .red.opacity(0.5)
        }
    }
}

// MARK: - ViewModel

struct TriviaQuestion {
    let text: String
    let choices: [String]
    let correctIndex: Int
    let category: String
}

@MainActor
final class TriviaboardViewModel: ObservableObject {
    @Published var players: [Player] = []
    @Published var currentQuestion: TriviaQuestion? = nil
    @Published var showChoices = false
    @Published var secondsLeft = 20
    @Published var answeredIDs: Set<String> = []
    @Published var revealedCorrectIndex: Int? = nil

    private let socket = GameSocketManager.shared

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.updateState(from: r.boardState)
        }
    }

    fileprivate func choiceState(for index: Int, correctIndex: Int) -> ChoiceTile.ChoiceState {
        guard let revealed = revealedCorrectIndex else { return .idle }
        if index == revealed { return .correct }
        return .idle
    }

    private func updateState(from data: [String: AnyCodable]) {
        if let s = data["secondsLeft"]?.value as? Int { secondsLeft = s }
        if let show = data["showChoices"]?.value as? Bool { showChoices = show }

        // Reveal correct answer -- gated on the engine's own reveal phase,
        // not merely on correctIndex being present. TriviaEngine now only
        // ever includes correctIndex in this payload while phase == "reveal"
        // (see legacy_social.py), but checking phase explicitly here too
        // means this stays correct even if that ever changes, rather than
        // depending on an implicit contract with the server. Reported
        // directly: the correct choice used to paint green the instant a
        // question's choices appeared, before anyone had answered.
        if data["phase"]?.value as? String == "reveal",
           let idx = data["correctIndex"]?.value as? Int {
            revealedCorrectIndex = idx
        }

        // Players who have answered this round
        if let answered = data["answeredPlayerIDs"]?.value as? [String] {
            answeredIDs = Set(answered)
        }

        // Player score list
        if let playerData = data["players"]?.value as? [[String: Any]] {
            players = playerData.compactMap { d -> Player? in
                guard let id   = d["id"]   as? String,
                      let name = d["name"] as? String else { return nil }
                return Player(id: id, name: name, isReady: true,
                              score: d["score"] as? Int ?? 0,
                              isHost: d["isHost"] as? Bool ?? false)
            }
        }

        // New question — reset answer state and schedule choice reveal
        let incomingQID = data["questionID"]?.value as? String ?? ""
        let incomingText = data["questionText"]?.value as? String ?? ""
        if !incomingQID.isEmpty, incomingText != currentQuestion?.text {
            answeredIDs = []
            revealedCorrectIndex = nil
            showChoices = false
            currentQuestion = TriviaQuestion(
                text: incomingText,
                choices: data["choices"]?.value as? [String] ?? [],
                correctIndex: data["correctIndex"]?.value as? Int ?? 0,
                category: data["category"]?.value as? String ?? "General"
            )
            // Brief delay so TV readers can read the question before choices appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                [weak self] in self?.showChoices = true
            }
        }
    }
}
