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
            // Background gradient — persists across all screens
            LinearGradient(
                colors: [Color(hex: "0d0d1a"), Color(hex: "1a0d2e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch vm.screen {
            case .gameSelection:
                TVGameSelectionView(onSelect: vm.createRoom,
                                    onSelectSolo: vm.createSoloRoom)

            case .lobby(let room):
                TVLobbyView(room: room, isSolo: vm.isSolo, onStart: vm.startGame)

            case .playing(let room):
                TVGameBoardView(room: room)

            case .results(let room):
                TVResultsView(room: room, onPlayAgain: vm.playAgain, onBackToGames: vm.quitToSelection)
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

    /// True while a remote-only game is running with no phones connected.
    @Published private(set) var isSolo = false

    private let socket = GameSocketManager.shared

    init() {
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
            case .playing: self.screen = .playing(response)
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
        socket.emit(.createRoom, payload: SoloRoomPayload(
            gameID: game.rawValue,
            hostName: "Player 1",
            hostID: AppConstants.deviceID,
            solo: true
        ))
    }

    func startGame() {
        guard case .lobby(let room) = screen else { return }
        socket.emit(.startGame, payload: ["roomCode": room.code])
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

    func returnToSelection() {
        isSolo = false
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
