import Foundation
import SwiftUI

// MARK: - TravelModeViewModel
//
// Owns a whole Travel Mode session. Two play styles:
//
//  - Trivia (client-side): fetches topic questions over REST, then runs the
//    round locally on the phone. No room, no socket game flow.
//  - Server-hosted games (most_likely_to, story_chain, twenty_questions,
//    hot_takes, wavelength): the phone creates a room itself and joins one
//    seat per car player — all seats share this phone's socket, and the
//    passenger operates every seat on the car's behalf. This uses only the
//    existing protocol: create_room / join_room / start_game / game_action /
//    leave_room. `handle_game_action` authorizes by matching the seat's
//    recorded sid, so seats on the same socket are all legal.
//
// Socket-handler ownership: GameSocketManager.on replaces the handler per
// event, so this VM only registers events the root VM doesn't own
// (.gameState, .gameEnded). roomJoined / privateState / roomUpdated / error
// stay owned by ControllerRootViewModel, which forwards travel traffic here.

@MainActor
final class TravelModeViewModel: ObservableObject {

    enum Stage {
        case setup      // picker + roster (+ topic for trivia)
        case loading    // fetching questions or creating the room
        case trivia     // client-side trivia round
        case hosted     // server-driven game screen
        case results    // final scores
    }

    // MARK: Setup state

    @Published var stage: Stage = .setup
    @Published var selectedGame: TravelGame = .trivia
    @Published var topic: String = ""
    @Published var roster: [TravelPlayer] = [
        TravelPlayer(name: "Driver"),
        TravelPlayer(name: "Passenger"),
    ]
    @Published var newPlayerName = ""
    @Published var loadingMessage = ""
    @Published var errorMessage: String? = nil

    // MARK: Trivia state

    @Published var questions: [TravelQuestion] = []
    @Published var questionIndex = 0
    @Published var pickedChoice: Int? = nil
    @Published var usedOfflineQuestions = false

    // MARK: Hosted-game state

    @Published var roomCode: String? = nil
    /// The engine's public state (game_state boardState), untyped like the
    /// rest of the controller app — read through ControllerKit's helpers.
    @Published var board: [String: Any] = [:]
    @Published var seatPrivate: [String: [String: Any]] = [:]
    @Published var hostSeatID: String? = nil

    // MARK: Shared

    /// Local +1 tally, keyed by roster player id. This is the scoreboard
    /// the car sees; engine seat scores are secondary.
    @Published var scores: [String: Int] = [:]
    let speech = TravelSpeech()
    let voice = TravelVoiceListener()

    init() {
        // The hosted server sleeps when idle and needs 30-60s to wake;
        // the cloud-voice path gives up after 5s and falls back to the
        // device voice. Warm it the moment Travel Mode opens -- the user
        // spends the setup screen picking a topic and seats, so the first
        // real question gets a warm server and the AI voice.
        speech.warmUpServer()
    }

    // MARK: Quizmaster (voice loop)

    /// The turn-based voice loop: ASK -> LISTEN -> LOCK -> GRADE. The mic
    /// is armed only inside .listening -- deaf by design everywhere else,
    /// which is what makes the game immune to side conversations.
    enum QuizmasterPhase {
        case idle, asking, listening, locked, grading
    }
    @Published var quizPhase: QuizmasterPhase = .idle
    /// Live caption of what the mic hears ("hearing: ...").
    @Published var liveTranscript = ""
    /// Set after a voice answer is graded; drives the same "tap +1"
    /// scoreboard flow as a tapped answer.
    @Published var voiceVerdict: Bool?
    /// Master toggle. Tap-to-answer always works regardless.
    @Published var quizmasterOn = true
    private var didReprompt = false

    /// Suggested topics for the trivia topic picker.
    let topicChips = ["Cricket", "World Capitals", "90s Music", "Tollywood"]

    private let socket = GameSocketManager.shared
    private let deviceID = AppConstants.deviceID

    /// False after endTravel(); every handler and the reconnect hook no-op.
    private(set) var isActive = true

    private var joinsEmitted = false
    private var joinedSeats = Set<String>()

    /// Snapshot of seat names taken when a hosted game starts. The
    /// scoreboard roster stays editable mid-game, but room seats are
    /// fixed at start — every seat lookup goes through this snapshot so
    /// a mid-game roster edit can't shift seat indices under the game.
    private var activeSeatNames: [String]? = nil

    /// Seat names for the current (or upcoming) game: the snapshot while
    /// a hosted game is in flight, else the live roster.
    var seatNames: [String] { activeSeatNames ?? roster.map(\.name) }
    var seatCount: Int { seatNames.count }

    // MARK: - Seats

    /// Seat 0 (roster[0], the phone operator) uses the device id so the
    /// seat survives reconnects the same way the normal join flow does;
    /// the rest are derived and stay under the 64-char server limit.
    func seatID(for index: Int) -> String {
        index == 0 ? deviceID : "\(deviceID)-t\(index)"
    }

    private var seatIDs: [String] {
        let count = activeSeatNames?.count ?? roster.count
        return (0..<count).map { seatID(for: $0) }
    }

    func ownsSeat(_ playerID: String) -> Bool {
        isActive && seatIDs.contains(playerID)
    }

    func seatName(_ seatID: String) -> String {
        if let i = seatIDs.firstIndex(of: seatID) {
            if let names = activeSeatNames, i < names.count { return names[i] }
            if i < roster.count { return roster[i].name }
        }
        return "Player"
    }

    // MARK: - Setup actions

    var canStart: Bool {
        let names = roster.map { $0.name.trimmingCharacters(in: .whitespaces) }
        return roster.count >= selectedGame.minPlayers
            && names.allSatisfy { !$0.isEmpty }
    }

    func addPlayer() {
        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, roster.count < 8 else { return }
        roster.append(TravelPlayer(name: String(name.prefix(20))))
        newPlayerName = ""
        errorMessage = nil
    }

    func removePlayer(_ player: TravelPlayer) {
        guard roster.count > 1 else { return }
        roster.removeAll { $0.id == player.id }
    }

    func awardPlusOne(_ player: TravelPlayer) {
        scores[player.id, default: 0] += 1
    }

    var rankedRoster: [TravelPlayer] {
        roster.sorted {
            (scores[$0.id] ?? 0, $0.name) > (scores[$1.id] ?? 0, $1.name)
        }
    }

    func nextInPlaylist() -> TravelGame {
        let all = TravelGame.allCases
        let i = all.firstIndex(of: selectedGame) ?? 0
        return all[(i + 1) % all.count]
    }

    // MARK: - Start

    func startGame() {
        errorMessage = nil
        resetScores()
        if selectedGame == .trivia {
            Task {
                // Mic permission is settled before the first question --
                // never mid-round. Denied? The tap buttons still work.
                if quizmasterOn {
                    _ = await voice.requestAuthorization()
                    guard isActive else { return }
                }
                await startTrivia()
            }
        } else {
            startHostedGame()
        }
    }

    private func resetScores() {
        scores = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, 0) })
    }

    // MARK: Trivia (client-side)

    private func startTrivia() async {
        stage = .loading
        loadingMessage = "Fetching questions…"
        let asked = askedQuestionTexts()
        let fetch = await fetchTravelQuestions(topic: topic, count: 10, exclude: asked)
        guard isActive else { return }
        guard !fetch.questions.isEmpty else {
            // Unreachable in practice — the offline deck always yields
            // questions — but never strand the UI on loading.
            errorMessage = "Could not load questions. Check your connection and try again."
            stage = .setup
            return
        }
        // The offline deck doesn't know the exclude list — filter it here
        // so a dead zone doesn't replay the same 24 questions either.
        let seen = Set(asked.map { $0.lowercased() })
        var fresh = fetch.questions.filter { !seen.contains($0.question.lowercased()) }
        if fresh.isEmpty { fresh = fetch.questions } // deck exhausted: replay beats nothing
        questions = fresh
        recordAskedQuestions(fresh.map(\.question))
        usedOfflineQuestions = fetch.source == .offline
        questionIndex = 0
        pickedChoice = nil
        stage = .trivia
        beginVoiceRound()
    }

    // MARK: Asked-question history (kills repeats across games)

    private static let askedHistoryKey = "travel_asked_questions"
    private static let askedHistoryCap = 300

    /// Question texts already asked on this device, most recent last.
    private func askedQuestionTexts() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.askedHistoryKey) ?? []
    }

    private func recordAskedQuestions(_ texts: [String]) {
        var history = askedQuestionTexts()
        history.append(contentsOf: texts)
        if history.count > Self.askedHistoryCap {
            history.removeFirst(history.count - Self.askedHistoryCap)
        }
        UserDefaults.standard.set(history, forKey: Self.askedHistoryKey)
    }

    var currentQuestion: TravelQuestion? {
        guard questionIndex < questions.count else { return nil }
        return questions[questionIndex]
    }

    func pickChoice(_ index: Int) {
        guard pickedChoice == nil else { return }
        cancelVoiceRound()
        pickedChoice = index
        if index == currentQuestion?.correctIndex {
            speech.speak(praise.randomElement() ?? "That's right!")
        } else if let q = currentQuestion {
            let letter = ["A", "B", "C", "D"][q.correctIndex]
            speech.speak("Not quite — it was \(letter). \(q.options[q.correctIndex]).")
        } else {
            speech.speak("Not quite.")
        }
    }

    /// Rotated so the host doesn't sound like a robot saying "Correct."
    /// twenty times in a row.
    private let praise = [
        "That's right!",
        "Nice one!",
        "Got it!",
        "Yes! Well done.",
        "Correct — you're on fire.",
    ]

    func advanceQuestion() {
        speech.stop()
        voice.stop()
        pickedChoice = nil
        voiceVerdict = nil
        liveTranscript = ""
        quizPhase = .idle
        didReprompt = false
        if questionIndex + 1 < questions.count {
            questionIndex += 1
            beginVoiceRound()
        } else {
            stage = .results
        }
    }

    // MARK: Hosted games (server room, one seat per player)

    private func startHostedGame() {
        stage = .loading
        loadingMessage = "Starting \(selectedGame.displayName)…"
        joinsEmitted = false
        joinedSeats = []
        activeSeatNames = roster.map { $0.name }
        board = [:]
        seatPrivate = [:]
        roomCode = nil

        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            self?.handleGameState(r)
        }
        socket.on(.gameEnded) { [weak self] (p: TravelGameEndedPayload) in
            self?.handleGameEnded(p)
        }
        // NOTE: .gameStarted stays owned by ControllerRootViewModel (it
        // replaces handlers per event). The root VM forwards travel games
        // here via handleGameStarted, which lifts the rules gate.
        socket.onConnected("travel") { [weak self] in
            self?.rejoinSeats()
        }

        let payload = TravelCreateRoomPayload(
            gameID: selectedGame.rawValue,
            hostName: roster[0].name,
            hostID: deviceID,
            solo: false,
            // Forward-compatible: today's server ignores unknown
            // create_room keys; a future backend can seed the room's
            // question pool from this for topic trivia.
            topic: selectedGame.usesTopic ? topic : nil
        )
        socket.emit(.createRoom, payload: payload)
    }

    /// Forwarded by ControllerRootViewModel's roomJoined handler while a
    /// travel session is active.
    func handleRoomJoined(_ response: RoomJoinedResponse) {
        guard isActive else { return }
        if roomCode == nil {
            // The create_room reply. Now seat every car player.
            roomCode = response.room.code
            joinsEmitted = true
            let names = activeSeatNames ?? roster.map(\.name)
            for i in names.indices {
                socket.emit(.joinRoom, payload: JoinRoomPayload(
                    roomCode: response.room.code,
                    playerName: names[i],
                    playerID: seatID(for: i),
                    isTV: false
                ))
            }
            return
        }
        // One seat's join_room reply. When every seat is in, start.
        guard joinsEmitted, seatIDs.contains(response.playerID) else { return }
        joinedSeats.insert(response.playerID)
        if joinedSeats.count >= seatIDs.count, let code = roomCode {
            socket.emit(.startGame, payload: ["roomCode": code])
            stage = .hosted
        }
    }

    /// Forwarded by ControllerRootViewModel's privateState handler for our seats.
    func handlePrivateState(_ response: PrivateStateResponse) {
        guard isActive, ownsSeat(response.playerID) else { return }
        seatPrivate[response.playerID] = response.privateData.mapValues { $0.value }
    }

    /// Forwarded by ControllerRootViewModel's roomUpdated handler.
    func handleRoomUpdated(_ room: Room) {
        guard isActive, room.code == roomCode else { return }
        hostSeatID = room.players.first(where: { $0.isHost })?.id
    }

    private func handleGameState(_ response: GameStateResponse) {
        guard isActive, response.roomCode == roomCode else { return }
        board = response.boardState.mapValues { $0.value }
    }

    /// The server announced the game (rules phase). Called by
    /// ControllerRootViewModel, which owns the .gameStarted event.
    /// Immediately begins — there is no rules card in the car, and this
    /// phone holds the room's board seat, so it is the host.
    func handleGameStarted(_ response: GameStartedResponse) {
        guard isActive, response.roomCode == roomCode, roomCode != nil else { return }
        socket.emit(.beginGame, payload: ["roomCode": response.roomCode])
    }

    private func handleGameEnded(_ payload: TravelGameEndedPayload) {
        guard isActive, payload.roomCode == roomCode else { return }
        speech.stop()
        stage = .results
    }

    /// Forwarded by ControllerRootViewModel's error handler.
    func handleError(_ message: String) {
        guard isActive else { return }
        if stage == .loading {
            errorMessage = message
            stage = .setup
        }
    }

    private func rejoinSeats() {
        // A reconnect gets a fresh sid that is in no room; re-seat every
        // car player so the game continues instead of stalling.
        guard isActive, let code = roomCode, stage == .hosted || stage == .loading else { return }
        let names = activeSeatNames ?? roster.map(\.name)
        for i in names.indices {
            socket.emit(.joinRoom, payload: JoinRoomPayload(
                roomCode: code,
                playerName: names[i],
                playerID: seatID(for: i),
                isTV: false
            ))
        }
    }

    /// A game_action as one of our seats. The server authorizes by
    /// matching the seat's recorded sid, and every seat shares this
    /// phone's socket, so the passenger can operate every seat.
    func sendAction(_ action: String, data: [String: Any] = [:], seat index: Int) {
        guard let code = roomCode, index < seatIDs.count else { return }
        socket.emit(.gameAction, payload: GameActionPayload(
            roomCode: code,
            playerID: seatID(for: index),
            action: action,
            data: data.mapValues { AnyCodable($0) }
        ))
    }

    /// Convenience: act as the host seat (host-gated actions like reveal
    /// or awarding). Falls back to seat 0 if the host id isn't known yet.
    func sendHostAction(_ action: String, data: [String: Any] = [:]) {
        let index: Int
        if let host = hostSeatID, let i = seatIDs.firstIndex(of: host) {
            index = i
        } else {
            index = 0
        }
        sendAction(action, data: data, seat: index)
    }

    // MARK: - Teardown

    func backToSetup() {
        cancelVoiceRound()
        speech.stop()
        // Leave the room seats behind (best effort) and drop the
        // travel-only socket handlers; the roster and topic are kept.
        if let code = roomCode {
            for i in roster.indices {
                socket.emit(.leaveRoom, payload: ["roomCode": code,
                                                  "playerID": seatID(for: i)])
            }
        }
        socket.off(.gameState)
        socket.off(.gameEnded)
        roomCode = nil
        activeSeatNames = nil
        board = [:]
        seatPrivate = [:]
        hostSeatID = nil
        questions = []
        questionIndex = 0
        pickedChoice = nil
        usedOfflineQuestions = false
        errorMessage = nil
        stage = .setup
    }

    func shutdown() {
        isActive = false
        backToSetup()
    }

    // MARK: - Speech helpers

    /// The TTS-safe line for the current prompt, per game. Phrased the way
    /// a host would actually say it — the ellipsis is a real pause for
    /// AVSpeechSynthesizer, which is what makes it sound conversational
    /// instead of read-out-loud.
    func speakablePrompt() -> String {
        if selectedGame == .trivia, let q = currentQuestion {
            let opts = q.options.enumerated()
                .map { "\(["A", "B", "C", "D"][$0.offset]): \($0.element)" }
                .joined(separator: " … ")
            return "Question \(questionIndex + 1). \(q.question) … \(opts)"
        }
        // The travel engines write hostPrompt for exactly this purpose:
        // short, spoken-style sentences with no markup.
        let host = board.str("hostPrompt")
        if !host.isEmpty { return host }
        switch selectedGame {
        case .mostLikelyTo:
            let p = board.str("prompt")
            return p.isEmpty ? "Waiting for the next prompt." : "Most likely to: \(p)"
        case .wavelength:
            let clue = board.str("clue")
            let left = board.str("leftLabel"), right = board.str("rightLabel")
            if clue.isEmpty { return "Waiting for the psychic's clue. The spectrum is \(left) to \(right)." }
            return "The clue is: \(clue). Spectrum: \(left) to \(right)."
        default:
            return "Waiting for the next prompt."
        }
    }

    // MARK: - Quizmaster voice loop (trivia)

    /// Ask the current question aloud, then arm the mic when it finishes.
    /// Called on entering the trivia stage and after every advance.
    func beginVoiceRound() {
        guard quizmasterOn, isActive, stage == .trivia,
              let q = currentQuestion else { return }
        quizPhase = .asking
        voiceVerdict = nil
        liveTranscript = ""
        didReprompt = false
        speech.enableQuizmasterAudio()
        // Zero dead air: the next question's audio is already cached by
        // the time we need it.
        if questionIndex + 1 < questions.count {
            let nq = questions[questionIndex + 1]
            speech.prefetch(voiceQuestionText(nq, number: questionIndex + 2))
        }
        // Mic permission was requested at game start; if it was denied,
        // the tap-to-answer buttons remain the input path.
        speech.speak(voiceQuestionText(q, number: questionIndex + 1)) {
            [weak self] in self?.startListening()
        }
    }

    private func voiceQuestionText(_ q: TravelQuestion, number: Int) -> String {
        let opts = q.options.enumerated()
            .map { "\(["A", "B", "C", "D"][$0.offset]): \($0.element)" }
            .joined(separator: " … ")
        return "Question \(number). \(q.question) … \(opts)"
    }

    private func startListening() {
        guard isActive, quizPhase == .asking, stage == .trivia else { return }
        quizPhase = .listening
        liveTranscript = ""
        voice.start(
            timeout: 8,
            onPartial: { [weak self] partial in
                self?.liveTranscript = partial
            },
            onFinal: { [weak self] transcript, confidence in
                self?.lockAnswer(transcript, confidence: confidence)
            }
        )
    }

    /// The LOCK step: the first final transcript wins. Everything the mic
    /// hears after this is ignored until the next question -- side
    /// conversations cannot derail the round.
    private func lockAnswer(_ transcript: String, confidence: Float) {
        guard quizPhase == .listening, stage == .trivia else { return }
        quizPhase = .locked
        voice.stop()
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || confidence < 0.35 {
            if !didReprompt {
                // One re-prompt, then the host taps.
                didReprompt = true
                quizPhase = .grading
                speech.speak("Didn't catch that -- say it again.") {
                    [weak self] in
                    guard let self, self.quizPhase == .grading else { return }
                    self.quizPhase = .asking
                    self.startListening()
                }
            } else {
                quizPhase = .idle
                liveTranscript = "Tap an answer below."
            }
            return
        }
        gradeVoiceAnswer(clean)
    }

    private func gradeVoiceAnswer(_ transcript: String) {
        quizPhase = .grading
        guard let q = currentQuestion else { quizPhase = .idle; return }
        // 1. Letter match: "B", "option B", "the second one".
        if let letter = voiceLetterIndex(transcript), (0...3).contains(letter) {
            finishVoiceGrade(correct: letter == q.correctIndex)
            return
        }
        // 2. Forgiving client-side match (free, instant).
        if voiceFuzzyMatches(transcript, q.options[q.correctIndex]) {
            finishVoiceGrade(correct: true)
            return
        }
        for (i, opt) in q.options.enumerated() where i != q.correctIndex {
            if voiceFuzzyMatches(transcript, opt) {
                finishVoiceGrade(correct: false)
                return
            }
        }
        // 3. One tiny server call for the genuinely ambiguous cases.
        Task {
            let correct = await serverGrade(transcript: transcript, question: q)
            await MainActor.run {
                self.finishVoiceGrade(correct: correct)
            }
        }
    }

    private func finishVoiceGrade(correct: Bool?) {
        guard stage == .trivia, let q = currentQuestion else { return }
        let letter = ["A", "B", "C", "D"][q.correctIndex]
        let verdict: String
        if correct == true {
            voiceVerdict = true
            verdict = "\(praise.randomElement() ?? "That's right!")"
        } else {
            // correct == false (wrong) and correct == nil (ungradable)
            // both reveal the answer; the host still taps +1 if it was right.
            voiceVerdict = false
            verdict = correct == nil
                ? "I couldn't quite judge that -- the answer was \(letter). \(q.options[q.correctIndex])."
                : "Not quite -- it was \(letter). \(q.options[q.correctIndex])."
        }
        quizPhase = .grading
        speech.speak(verdict)
        // The host taps +1 on the scoreboard for whoever got it right,
        // then Next Question -- same flow as a tapped answer.
    }

    /// Manual tap or teardown cancels the in-flight voice round.
    func cancelVoiceRound() {
        voice.stop()
        quizPhase = .idle
        liveTranscript = ""
        didReprompt = false
    }

    // MARK: Hold-to-talk

    /// Press-and-hold mic button: press re-arms the window, release
    /// finalizes. The reliable input in a noisy car.
    func holdToTalkBegan() {
        guard quizPhase == .listening else { return }
        startListening()
    }

    func holdToTalkEnded() {
        guard quizPhase == .listening else { return }
        voice.finishEarly()
    }

    // MARK: - Voice answer matching (client-side, free)

    private func voiceLetterIndex(_ transcript: String) -> Int? {
        let t = transcript.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = ["a", "b", "c", "d"]
        // "option B"
        if let m = t.range(of: #"option\s+([a-d])"#,
                           options: .regularExpression),
           let last = String(t[m]).last,
           let i = letters.firstIndex(of: String(last)) {
            return i
        }
        // Standalone letter, but only in a short transcript -- "a" as an
        // article inside a longer sentence must not count as answering A.
        if t.split(separator: " ").count <= 3 {
            let padded = " \(t) "
            for (i, l) in letters.enumerated()
            where padded.contains(" \(l) ") {
                return i
            }
        }
        let ordinals = ["first": 0, "second": 1, "third": 2, "fourth": 3]
        for (word, i) in ordinals where t.contains(word) {
            return i
        }
        return nil
    }

    private func voiceFuzzyMatches(_ transcript: String, _ answer: String) -> Bool {
        let g = voiceNormalize(transcript), a = voiceNormalize(answer)
        guard !g.isEmpty, !a.isEmpty else { return false }
        if g == a || g.replacingOccurrences(of: " ", with: "")
            == a.replacingOccurrences(of: " ", with: "") { return true }
        let words = a.split(separator: " ")
        if words.count >= 3,
           g.replacingOccurrences(of: " ", with: "")
            == words.map { String($0.prefix(1)) }.joined() { return true }
        if g.contains(a) || a.contains(g) { return true }
        return false
    }

    private func voiceNormalize(_ text: String) -> String {
        var words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if let first = words.first, ["the", "a", "an"].contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    // MARK: - Server grading fallback

    private struct VoiceGradeResponse: Decodable {
        let success: Bool
        let correct: Bool?
    }

    private func serverGrade(transcript: String,
                             question q: TravelQuestion) async -> Bool? {
        let url = AppConstants.serverURL.appendingPathComponent("api/voice/grade")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "question": q.question,
            "options": q.options,
            "correct_answer": q.correctIndex,
            "transcript": transcript,
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(VoiceGradeResponse.self,
                                                   from: data)
            return decoded.success ? decoded.correct : nil
        } catch {
            return nil
        }
    }
}

// MARK: - game_ended payload

struct TravelGameEndedPayload: Decodable {
    let roomCode: String
    let results: [AnyCodable]?
}
