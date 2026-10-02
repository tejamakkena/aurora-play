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
            Task { await startTrivia() }
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
        let fetch = await fetchTravelQuestions(topic: topic, count: 10)
        guard isActive else { return }
        guard !fetch.questions.isEmpty else {
            // Unreachable in practice — the offline deck always yields
            // questions — but never strand the UI on loading.
            errorMessage = "Could not load questions. Check your connection and try again."
            stage = .setup
            return
        }
        questions = fetch.questions
        usedOfflineQuestions = fetch.source == .offline
        questionIndex = 0
        pickedChoice = nil
        stage = .trivia
    }

    var currentQuestion: TravelQuestion? {
        guard questionIndex < questions.count else { return nil }
        return questions[questionIndex]
    }

    func pickChoice(_ index: Int) {
        guard pickedChoice == nil else { return }
        pickedChoice = index
        if index == currentQuestion?.correctIndex {
            speech.speak("Correct.")
        } else {
            speech.speak("Not quite.")
        }
    }

    func advanceQuestion() {
        speech.stop()
        pickedChoice = nil
        if questionIndex + 1 < questions.count {
            questionIndex += 1
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

    /// The TTS-safe line for the current prompt, per game.
    func speakablePrompt() -> String {
        if selectedGame == .trivia, let q = currentQuestion {
            let opts = q.options.enumerated()
                .map { "\(["A", "B", "C", "D"][$0.offset]). \($0.element)" }
                .joined(separator: " ")
            return "Question. \(q.question) \(opts)"
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
}

// MARK: - game_ended payload

struct TravelGameEndedPayload: Decodable {
    let roomCode: String
    let results: [AnyCodable]?
}
