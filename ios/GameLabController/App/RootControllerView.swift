import SwiftUI

struct RootControllerView: View {
    @StateObject private var vm = ControllerRootViewModel()

    // Mirrors the TV's mid-game quit confirmation (RootTVView): leaving a
    // game in progress has real consequences (the room, and anyone else in
    // it, loses this seat), so it's confirmed the same way rather than a
    // bare exposed leave button like WaitingView's -- nothing is lost yet
    // there.
    @State private var showLeaveConfirm = false

    var body: some View {
        ZStack {
            Color(hex: "0a0a14").ignoresSafeArea()

            switch vm.screen {
            case .join:
                JoinRoomView(onJoin: vm.joinRoom, initialCode: vm.pendingJoinCode)

            case .loading:
                LoadingJoinView()

            case .error(let message):
                ErrorJoinView(message: message, onRetry: vm.returnToJoin)

            case .waiting(let room):
                WaitingView(room: room, onReady: vm.markReady, onLeave: vm.leaveRoom)

            case .rules(_, let rules):
                // Host-gated rules card: the engine is held server-side
                // until the host taps Begin. The host's phone gets the
                // button; everyone else gets the waiting indicator. The
                // leave button stays in the top safe area so the card never
                // traps anyone.
                RulesInterstitialView(
                    rules: rules,
                    layout: .card,
                    primaryTitle: "Begin Game",
                    onPrimary: vm.isHost ? { vm.beginGame() } : nil
                )
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button { showLeaveConfirm = true } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

            case .playing(let room, let privateData):
                ControllerGameView(
                    room: room,
                    privateData: privateData,
                    onAction: vm.sendAction
                )
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button { showLeaveConfirm = true } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

            case .results(let room):
                ResultsControllerView(room: room, onPlayAgain: vm.playAgain, onLeave: vm.leaveRoom)
            }
        }
        .environmentObject(vm)
        // auroraplay://join/<CODE> from the TV lobby's QR landing page.
        .onOpenURL { vm.handleOpenURL($0) }
        .animation(.easeInOut(duration: 0.3), value: vm.screen.id)
        .confirmationDialog(
            "Leave this game?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Game", role: .destructive) { vm.leaveRoom() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Screen enum

enum ControllerScreen: Equatable {
    case join
    case loading
    case error(String)
    case waiting(Room)
    case rules(Room, GameRules)
    case playing(Room, [String: Any])
    case results(Room)

    static func == (lhs: ControllerScreen, rhs: ControllerScreen) -> Bool {
        lhs.id == rhs.id
    }

    var id: String {
        switch self {
        case .join:              return "join"
        case .loading:           return "loading"
        case .error(let msg):    return "error-\(msg)"
        case .waiting(let r):    return "waiting-\(r.code)"
        case .rules(let r, _):   return "rules-\(r.code)"
        case .playing(let r, _): return "playing-\(r.code)"
        case .results(let r):    return "results-\(r.code)"
        }
    }
}

// MARK: - Loading & Error views

struct LoadingJoinView: View {
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ProgressView().scaleEffect(2.2).tint(.cyan)
            Text("Joining room" + String(repeating: ".", count: dotCount))
                .font(.title3).foregroundColor(.white.opacity(0.7))
                .onReceive(timer) { _ in dotCount = (dotCount + 1) % 4 }
            Spacer()
        }
    }
}

struct ErrorJoinView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60)).foregroundColor(.red)
            Text(message)
                .font(.title3.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(.headline).frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.cyan))
                    .foregroundColor(.black)
            }
            .buttonStyle(.plain).padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ControllerRootViewModel: ObservableObject {
    @Published var screen: ControllerScreen = .join
    /// Room code handed over by a deep link, pre-filled on the join screen.
    @Published var pendingJoinCode: String? = nil

    /// Rules interstitial data from the last `game_started` broadcast. Set
    /// on start; cleared on `game_begun` (the host tapped Begin), when the
    /// player leaves the room, or on return to the join screen. Kept in the
    /// view model, not the view, because `room_updated` rebuilds screens
    /// repeatedly.
    @Published var pendingRules: GameRules?

    private let socket = GameSocketManager.shared
    let playerID = AppConstants.deviceID

    private static let nameKey = "aurora_player_name"
    /// The name used for the last join, so a reconnect can re-send it.
    private var playerName: String {
        get { UserDefaults.standard.string(forKey: Self.nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.nameKey) }
    }

    /// The room this phone is seated in, whatever screen it is on.
    var currentRoom: Room? {
        switch screen {
        case .waiting(let r), .rules(let r, _), .playing(let r, _), .results(let r): return r
        default: return nil
        }
    }

    var isHost: Bool {
        currentRoom?.players.first(where: { $0.id == playerID })?.isHost ?? false
    }

    /// See joinRoom(code:name:)'s own comment: a bounded fallback for a join
    /// that never gets any response back at all.
    private var joinTimeoutTask: Task<Void, Never>?

    init() {
        // Server confirms the join (or a reconnect re-seat) -- route by the
        // room's state so a phone that rejoins mid-game stays on its
        // controller instead of flashing back to the lobby.
        socket.on(.roomJoined) { [weak self] (response: RoomJoinedResponse) in
            guard let self else { return }
            self.joinTimeoutTask?.cancel()
            self.pendingJoinCode = nil
            let room = response.room
            switch (room.state, self.screen) {
            case (.playing, .playing(_, let data)):
                self.screen = .playing(room, data)
            case (.results, _):
                self.screen = .results(room)
            default:
                self.screen = .waiting(room)
            }
        }

        // Every reconnect gets a fresh socket id that is in no room; re-send
        // join_room so the server re-attaches this playerID to its seat.
        socket.onConnected("controller") { [weak self] in
            self?.rejoinIfSeated()
        }

        // Room state changes (more players join, game ends, etc.)
        socket.on(.roomUpdated) { [weak self] (room: Room) in
            guard let self else { return }
            switch room.state {
            case .lobby:
                if case .waiting = self.screen { self.screen = .waiting(room) }
            case .results:
                self.screen = .results(room)
            case .playing:
                break  // privateState event drives the playing transition
            }
        }

        // The server carries the how-to-play payload on game_started (see
        // games/native_hub/socket_events.py). The server holds the engine
        // until the host taps Begin, so the phone parks on the rules card
        // instead of jumping straight to the controller; game_begun (below)
        // and the pump's first private_state then drive rules -> playing.
        // A phone joining mid-rules gets this re-sent to it directly.
        socket.on(.gameStarted) { [weak self] (response: GameStartedResponse) in
            guard let self else { return }
            self.pendingRules = response.rules
            switch self.screen {
            case .waiting(let room), .results(let room):
                self.screen = .rules(room, response.rules)
            default:
                break
            }
        }

        // The host tapped Begin: drop the rules card and fall back to the
        // waiting screen; the pump's first private_state (right behind this)
        // moves the phone onto its controller as before.
        socket.on(.gameBegun) { [weak self] (_: GameBegunResponse) in
            guard let self else { return }
            self.pendingRules = nil
            if case .rules(let room, _) = self.screen {
                self.screen = .waiting(room)
            }
        }

        // Private screen update — drives waiting → playing and results → playing
        // (Play Again path: the TV rematches the same room and the pump pushes
        // private_state again; a phone on its results screen needs this too).
        socket.on(.privateState) { [weak self] (r: PrivateStateResponse) in
            guard let self, r.playerID == self.playerID else { return }
            switch self.screen {
            case .waiting(let room), .playing(let room, _), .results(let room):
                self.screen = .playing(room, r.privateData.mapValues(\.value))
            default:
                break
            }
        }

        // Server-side errors (room not found, room full, invalid action, etc.)
        socket.on(.error) { [weak self] (r: ErrorResponse) in
            guard let self else { return }
            self.joinTimeoutTask?.cancel()
            // Only show error overlay from loading state; in-game errors stay silent
            if case .loading = self.screen {
                self.screen = .error(r.message)
            }
        }
    }

    func joinRoom(code: String, name: String) {
        playerName = name
        pendingRules = nil
        screen = .loading
        socket.emit(.joinRoom, payload: JoinRoomPayload(
            roomCode: code.uppercased(),
            playerName: name,
            playerID: playerID,
            isTV: false
        ))

        // Reported directly: the screen got stuck on "Joining room..."
        // forever with no way out but force-quitting. Whatever the exact
        // cause on a given attempt -- a dropped emit, a lost reply, a code
        // for a room that's since moved on -- neither roomJoined nor error
        // ever arriving left this screen with no path forward at all. A
        // bounded wait with a clear, actionable error is a safety net
        // regardless of the underlying cause.
        joinTimeoutTask?.cancel()
        joinTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .loading = self.screen {
                self.screen = .error("Couldn't join — check the room code and try again.")
            }
        }
    }

    func markReady() {
        guard case .waiting(let room) = screen else { return }
        socket.emit(.playerReady, payload: ["roomCode": room.code, "playerID": playerID])
    }

    /// Lift the rules gate from the host's phone. The server authorizes by
    /// socket (host flag), mirroring start_game; non-hosts never see this
    /// button, and a stray emit from one is rejected server-side.
    func beginGame() {
        guard let room = currentRoom else { return }
        socket.emit(.beginGame, payload: ["roomCode": room.code, "playerID": playerID])
    }

    /// Phone "Play Again": the exact same rematch flow as the TV button
    /// (TVRootViewModel.playAgain). Re-emits start_game against the same
    /// room code -- the room and its player list never go away when a round
    /// ends, so the backend re-spins a fresh engine for the exact same
    /// group, resetting scores in handle_start_game. The existing
    /// .privateState handler then moves this phone results -> playing, and
    /// .gameStarted arms the rules interstitial again. Server-side this is
    /// host-or-TV-only, so the results screen only offers the button to the
    /// host (everyone else just waits).
    func playAgain() {
        guard case .results(let room) = screen else { return }
        pendingRules = nil   // replaced by the game_started payload, if the start succeeds
        socket.emit(.startGame, payload: ["roomCode": room.code])
    }

    func sendAction(action: String, data: [String: Any]) {
        guard case .playing(let room, _) = screen else { return }
        socket.emit(.gameAction, payload: GameActionPayload(
            roomCode: room.code,
            playerID: playerID,
            action: action,
            data: data.mapValues { AnyCodable($0) }
        ))
    }

    func leaveRoom() {
        switch screen {
        case .playing(let room, _), .waiting(let room), .rules(let room, _):
            socket.emit(.leaveRoom, payload: ["roomCode": room.code, "playerID": playerID])
        default:
            break
        }
        pendingRules = nil
        screen = .join
    }

    func returnToJoin() {
        pendingRules = nil
        screen = .join
    }

    private func rejoinIfSeated() {
        guard let room = currentRoom else { return }
        socket.emit(.joinRoom, payload: JoinRoomPayload(
            roomCode: room.code,
            playerName: playerName.isEmpty ? "Player" : playerName,
            playerID: playerID,
            isTV: false
        ))
    }

    func handleOpenURL(_ url: URL) {
        // auroraplay://join/ABC234  (host "join", code as the path)
        guard url.scheme?.lowercased() == "auroraplay" else { return }
        let parts = ([url.host ?? ""] + url.pathComponents).filter { $0 != "/" && !$0.isEmpty }
        guard let code = parts.last?.uppercased(), code.count == 6 else { return }
        if case .join = screen {
            pendingJoinCode = code
        } else if currentRoom?.code != code {
            leaveRoom()
            pendingJoinCode = code
        }
    }

    // MARK: Host lobby controls

    func addBot() {
        guard let room = currentRoom else { return }
        socket.emit(.addBot, payload: ["roomCode": room.code])
    }

    func removeBot(_ botID: String) {
        guard let room = currentRoom else { return }
        socket.emit(.removeBot, payload: ["roomCode": room.code, "botID": botID])
    }

    func setContentPack(_ pack: ContentPack) {
        guard let room = currentRoom else { return }
        socket.emit(.setContentPack, payload: ["roomCode": room.code, "contentPack": pack.rawValue])
    }
}
