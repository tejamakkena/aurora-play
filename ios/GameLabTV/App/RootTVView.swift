import SwiftUI

struct RootTVView: View {
    @StateObject private var vm = TVRootViewModel()

    // Menu on the Siri Remote had no handler at all originally, so tvOS
    // fell back to its own default: exit straight to the system Home
    // Screen, mid-game, with no warning. Two SwiftUI .onExitCommand
    // attempts then failed on real hardware for focus-related reasons --
    // MenuPressInterceptor (used below) documents both and why a
    // window-level UIKit press recognizer is what finally works.
    @State private var showQuitConfirm = false

    /// Menu means "back to the game list" during a game, and keeps its
    /// normal platform meaning (exit the app) on the list itself.
    private var interceptsMenu: Bool {
        if case .gameSelection = vm.screen { return false }
        return true
    }

    private var isAmbientAnimated: Bool {
        if case .playing = vm.screen { return false }
        return true
    }

    private func handleMenuPress() {
        switch vm.screen {
        case .gameSelection:
            break
        case .results:
            // "Play Again" on TVResultsView now actually rematches the same
            // group instead of leaving (see TVRootViewModel.playAgain) --
            // Menu still means "leave", same as it does mid-game, which is
            // why results also has its own explicit "Back to Games" link
            // for anyone without a remote in hand.
            vm.quitToSelection()
        case .lobby, .playing:
            showQuitConfirm = true
        }
    }

    var body: some View {
        ZStack {
            // Ambient background -- persists across all screens. Drifts
            // slowly on the shell screens; frozen on one frame behind a
            // running game, whose board draws its own backdrop and should
            // get the whole GPU budget.
            ShellAmbientBackground(isAnimated: isAmbientAnimated)

            switch vm.screen {
            case .gameSelection:
                TVGameSelectionView(onSelect: vm.createRoom,
                                    onSelectSolo: vm.createSoloRoom,
                                    onGameNight: vm.createNightRoom)

            case .lobby(let room):
                TVLobbyView(room: room, isSolo: vm.isSolo, onStart: vm.startGame)

            case .playing(let room):
                ZStack {
                    TVGameBoardView(room: room)
                    // How-to-play interstitial: the group has already
                    // committed (Start Game was pressed), but the engine is
                    // still gated server-side -- no clocks, nothing dealt --
                    // until the host taps Begin. The TV shows the button only
                    // when this device is the host (solo rooms, whose
                    // synthetic player carries the TV's own device id); in a
                    // group game the host's phone holds the button and the
                    // TV shows the waiting state. game_begun lifts the gate
                    // and drops this overlay.
                    if let rules = vm.pendingRules {
                        RulesInterstitialView(
                            rules: rules,
                            layout: .tv,
                            primaryTitle: "Begin Game",
                            onPrimary: TVRootViewModel.canBegin(room: room) ? { vm.beginGame() } : nil
                        )
                    }
                }

            case .results(let room):
                TVResultsView(room: room,
                              onPlayAgain: vm.playAgain,
                              onBackToGames: vm.quitToSelection,
                              nightTotalsBefore: vm.nightTotalsBeforeGame,
                              onNextGame: vm.nextGame,
                              onEndNight: vm.endNight)
            }
        }
        .environmentObject(vm)
        // Menu is intercepted through a window-level UIKit press
        // recognizer rather than SwiftUI's .onExitCommand -- see
        // MenuPressInterceptor for why two focus-based attempts failed on
        // real hardware. Inactive on the selection screen so Menu still
        // exits the app there, which is the platform-standard behavior
        // tvOS expects from a top-level screen.
        .overlay(
            MenuPressInterceptor(isActive: interceptsMenu) { handleMenuPress() }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .confirmationDialog(
            "Quit to Home Screen?",
            isPresented: $showQuitConfirm,
            titleVisibility: .visible
        ) {
            Button("Yes, Quit to Home Screen", role: .destructive) {
                vm.quitToSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll leave this game and return to the game list. Anyone else playing will be disconnected.")
        }
    }
}

// MARK: - View Model

enum TVScreen {
    case gameSelection
    case lobby(Room)
    case playing(Room)
    case results(Room)
}

@MainActor
final class TVRootViewModel: ObservableObject {
    @Published var screen: TVScreen = .gameSelection

    /// Rules interstitial data from the last `game_started` broadcast.
    /// Set on start and cleared on `game_begun` (the host tapped Begin) or
    /// when leaving the room. Kept in the view model, not the view, because
    /// `room_updated` rebuilds the `.playing` screen repeatedly.
    @Published var pendingRules: GameRules?

    /// True while a remote-only game is running with no phones connected.
    @Published private(set) var isSolo = false

    /// The room was created from the home screen's Game Night card: the
    /// lobby shows the night setup panel until `start_night` lands (after
    /// which `Room.night` drives everything).
    @Published private(set) var isNightSetup = false

    /// Each player's Game Night total as it stood when the current game
    /// started, so the results screen can animate the points just earned.
    /// (The server's night JSON carries totals only, not per-game history.)
    @Published private(set) var nightTotalsBeforeGame: [String: Int] = [:]

    private let socket = GameSocketManager.shared

    init() {
        // The server carries the how-to-play payload on game_started (see
        // games/native_hub/socket_events.py) -- the single source of truth
        // for the rules interstitial. It arrives just before the
        // room_updated that flips the screen to .playing, so the overlay
        // below is already armed when the board appears.
        socket.on(.gameStarted) { [weak self] (response: GameStartedResponse) in
            self?.pendingRules = response.rules
        }

        // The host tapped Begin (on the TV or on their phone): the engine is
        // running for real now, so drop the interstitial. The pump's first
        // game_state (a beat later) builds the real board underneath.
        socket.on(.gameBegun) { [weak self] (_: GameBegunResponse) in
            self?.pendingRules = nil
        }

        socket.on(.roomUpdated) { [weak self] (response: Room) in
            guard let self else { return }
            switch response.state {
            case .lobby:
                // Used to auto-emit startGame instantly here for a solo
                // room, skipping the lobby (and its room code) entirely.
                // Reported directly: that left Atlas -- whose only input is
                // typed text -- with no way to ever bring in a phone,
                // because the room had already started before one could
                // join it. Letting the lobby show normally, same as any
                // other room, means the code stays up long enough for a
                // phone to join for real (the server only creates the solo
                // placeholder player if nobody has, in handle_start_game) --
                // and "Start Game" is already enabled the instant this
                // screen appears (TVLobbyView's own isSolo-driven canStart),
                // so a single Select still starts it immediately for anyone
                // who just wants to play with the remote alone.
                self.screen = .lobby(response)
            case .playing:
                // Snapshot night totals on the way into a game (not on
                // every room_updated during it).
                let wasPlaying: Bool
                if case .playing = self.screen { wasPlaying = true } else { wasPlaying = false }
                if !wasPlaying {
                    self.nightTotalsBeforeGame = TVRootViewModel.nightTotals(response.night)
                }
                self.screen = .playing(response)
            case .results: self.screen = .results(response)
            }
        }

        // After a dropped connection (Wi-Fi blip, Render waking up) the TV
        // comes back on a new socket that is in no room: no game_state, and
        // a solo game's remote input is rejected. Re-attach as the board.
        socket.onConnected("tv") { [weak self] in
            self?.rejoinAsBoard()
        }
    }

    private var currentRoomCode: String? {
        switch screen {
        case .lobby(let room), .playing(let room), .results(let room): return room.code
        case .gameSelection: return nil
        }
    }

    private func rejoinAsBoard() {
        guard let code = currentRoomCode else { return }
        socket.emit(.joinRoom, payload: JoinRoomPayload(
            roomCode: code, playerName: "TV",
            playerID: AppConstants.deviceID, isTV: true
        ))
    }

    // MARK: Lobby options

    func addBot() {
        guard let code = currentRoomCode else { return }
        socket.emit(.addBot, payload: ["roomCode": code])
    }

    func removeBot(_ botID: String) {
        guard let code = currentRoomCode else { return }
        socket.emit(.removeBot, payload: ["roomCode": code, "botID": botID])
    }

    func setContentPack(_ pack: ContentPack) {
        guard let code = currentRoomCode else { return }
        socket.emit(.setContentPack, payload: ["roomCode": code, "contentPack": pack.rawValue])
    }

    func createRoom(game: GameID) {
        isSolo = false
        isNightSetup = false
        let payload = CreateRoomPayload(
            gameID: game.rawValue,
            hostName: "TV",
            hostID: AppConstants.deviceID
        )
        socket.emit(.createRoom, payload: payload)
    }

    /// Start a game with no phones at all — the TV is the only player and the
    /// Siri Remote is the controller.
    func createSoloRoom(game: GameID) {
        isSolo = true
        isNightSetup = false
        socket.emit(.createRoom, payload: SoloRoomPayload(
            gameID: game.rawValue,
            hostName: "Player 1",
            hostID: AppConstants.deviceID,
            solo: true
        ))
    }

    func startGame() {
        guard case .lobby(let room) = screen else { return }
        pendingRules = nil   // replaced by the game_started payload, if the start succeeds
        socket.emit(.startGame, payload: ["roomCode": room.code])
    }

    /// The TV shows the rules gate's Begin button only when this device is
    /// the host: solo rooms (whose synthetic player carries the TV's own
    /// device id) or a room with no players left at all, where the board is
    /// the only device that can still begin. In a group game the host's
    /// phone holds the button and the TV shows the waiting state; the server
    /// still authorizes the TV socket either way, mirroring start_game.
    static func canBegin(room: Room) -> Bool {
        room.players.isEmpty
            || room.players.first(where: { $0.id == AppConstants.deviceID })?.isHost == true
    }

    /// Lift the rules gate: the server starts the engine for real.
    func beginGame() {
        guard case .playing(let room) = screen else { return }
        socket.emit(.beginGame, payload: ["roomCode": room.code])
    }

    /// What the "Play Again" button on TVResultsView is supposed to do:
    /// rematch the same room and the same players, not quit to the
    /// selection grid -- reported directly as "always taking back to Home
    /// Screen" (it used to just call returnToSelection). The room and its
    /// players never actually go away when a round ends (finish_game only
    /// moves room.state to RESULTS), so start_game against the same code
    /// spins up a fresh engine instance for the exact same group; scores
    /// are reset server-side in handle_start_game. .on(.roomUpdated)'s
    /// existing .playing case picks the resulting room_updated back up the
    /// same way it does for a first-time start.
    func playAgain() {
        guard case .results(let room) = screen else { return }
        pendingRules = nil   // replaced by the game_started payload, if the start succeeds
        socket.emit(.startGame, payload: ["roomCode": room.code])
    }

    /// Send a game action on the TV's own behalf. Used by the remote-controlled
    /// solo games, which have no phone to send for them.
    func sendAction(_ action: String, _ data: [String: Any] = [:]) {
        let code: String
        switch screen {
        case .playing(let room), .lobby(let room), .results(let room): code = room.code
        case .gameSelection: return
        }
        socket.emit(.gameAction, payload: GameActionPayload(
            roomCode: code,
            playerID: AppConstants.deviceID,
            action: action,
            data: data.mapValues { AnyCodable($0) }
        ))
    }

    // MARK: Game Night

    /// Home screen's Game Night card: a normal room (Trivia, through the
    /// usual create_room path) whose lobby then offers the night setup.
    /// start_night swaps the room's game for the playlist's first one.
    func createNightRoom() {
        createRoom(game: .trivia)
        isNightSetup = true
    }

    /// `playlist` is the previewed lineup the lobby showed, so the night
    /// plays exactly what was on screen; empty lets the server's picker
    /// build one from `minutes` and `kids`.
    func startNight(minutes: Int, kids: Bool, playlist: [String]) {
        guard case .lobby(let room) = screen else { return }
        socket.emit(.startNight, payload: StartNightPayload(
            roomCode: room.code,
            playlist: playlist.isEmpty ? nil : playlist,
            minutes: minutes,
            kids: kids
        ))
    }

    /// After a night game's results: on to the next game's lobby, or (after
    /// the last one) the night is marked finished and results shows the
    /// champion.
    func nextGame() {
        guard case .results(let room) = screen else { return }
        pendingRules = nil
        socket.emit(.nextGame, payload: RoomCodePayload(roomCode: room.code))
    }

    /// Stops the night early (or closes a finished one); the room stays.
    func endNight() {
        guard let code = currentRoomCode else { return }
        isNightSetup = false
        socket.emit(.endNight, payload: RoomCodePayload(roomCode: code))
    }

    /// Trivia's question topic ("" = the usual mixed questions).
    func setTopic(_ topic: String) {
        guard case .lobby(let room) = screen else { return }
        let payload: [String: String] = ["roomCode": room.code, "topic": topic]
        socket.emit(.setTopic, payload: payload)
    }

    /// Teams mode: 2-4 teams dealt by the server, or 0 to switch it off.
    func setTeams(count: Int) {
        guard case .lobby(let room) = screen else { return }
        if count < 2 {
            socket.emit(.clearTeams, payload: RoomCodePayload(roomCode: room.code))
        } else {
            socket.emit(.setTeams, payload: SetTeamsPayload(roomCode: room.code, count: count))
        }
    }

    func moveToTeam(playerID: String, teamID: String) {
        guard case .lobby(let room) = screen else { return }
        socket.emit(.moveToTeam, payload: MoveToTeamPayload(roomCode: room.code,
                                                             playerID: playerID,
                                                             teamID: teamID))
    }

    nonisolated static func nightTotals(_ night: GameNight?) -> [String: Int] {
        var totals: [String: Int] = [:]
        for standing in night?.standings ?? [] {
            totals[standing.playerID] = standing.points
        }
        return totals
    }

    func returnToSelection() {
        isSolo = false
        isNightSetup = false
        nightTotalsBeforeGame = [:]
        pendingRules = nil
        screen = .gameSelection
    }

    /// Menu-button quit, after the user confirms. Tells the server the TV is
    /// leaving (so the room doesn't linger forever waiting for a board that's
    /// gone -- see room_manager.detach_sid) before dropping back to the
    /// selection screen locally.
    func quitToSelection() {
        let code: String?
        switch screen {
        case .lobby(let room), .playing(let room), .results(let room): code = room.code
        case .gameSelection: code = nil
        }
        if let code {
            socket.emit(.leaveRoom, payload: ["roomCode": code])
        }
        returnToSelection()
    }
}

/// create_room with the solo flag. Kept separate from CreateRoomPayload so the
/// shared struct stays exactly what the phone sends.
private struct SoloRoomPayload: Encodable {
    let gameID: String
    let hostName: String
    let hostID: String
    let solo: Bool
}
