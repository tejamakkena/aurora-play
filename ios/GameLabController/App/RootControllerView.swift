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
            PhonePlayDesign.bg.ignoresSafeArea()

            switch vm.screen {
            case .join:
                // The app's home: Phone Play's games with a "Play on TV"
                // hero on top. Joining a TV room happens in a sheet over it
                // (see the .sheet below), so a deep link or an error retry
                // just opens that sheet again.
                PhonePlayRootView(play: vm.phonePlay)

            case .travel:
                if let travel = vm.travelVM {
                    TravelModeRootView(travel: travel)
                }

            case .loading:
                LoadingJoinView(onCancel: vm.returnHome)

            case .error(let message):
                ErrorJoinView(message: message, onRetry: vm.returnToJoin, onHome: vm.returnHome)

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
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .accessibilityLabel("Leave game")
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
                // Voice quizmaster: any phone can claim the mic for TV
                // games. The bar is inert until someone taps it.
                .safeAreaInset(edge: .bottom) {
                    MicClaimBar(roomCode: room.code, playerID: vm.playerID)
                }
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button { showLeaveConfirm = true } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .accessibilityLabel("Leave game")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

            case .results(let room):
                ResultsControllerView(room: room, onLeave: vm.leaveRoom, onPlayAgain: vm.playAgain)
            }
        }
        .environmentObject(vm)
        // Joining a TV room: room code, name and the QR hint, over the home.
        .sheet(isPresented: joinSheetBinding) {
            JoinRoomView(onJoin: vm.joinRoom,
                         onClose: { vm.showJoinSheet = false },
                         initialCode: vm.pendingJoinCode)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(PhonePlayDesign.cardRadius + 8)
                .presentationBackground(PhonePlayDesign.bg)
        }
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

    /// The join sheet only ever shows over the home screen; once a join
    /// moves the app to .loading it goes away with it.
    private var joinSheetBinding: Binding<Bool> {
        Binding(
            get: { vm.showJoinSheet && vm.screen == .join },
            set: { presented in
                if !presented { vm.showJoinSheet = false }
            }
        )
    }
}

// MARK: - Screen enum

enum ControllerScreen: Equatable {
    case join
    case travel
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
        case .travel:            return "travel"
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
    var onCancel: (() -> Void)? = nil

    @State private var dotCount = 0
    @State private var appeared = false
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([PhonePlayDesign.cyan, PhonePlayDesign.indigo]))
                    .frame(width: 120, height: 120)
                    .shadow(color: PhonePlayDesign.cyan.opacity(0.45), radius: 24, y: 8)
                Image(systemName: "tv.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
                    .phonePlayIdle(dy: 4, scale: 0.05, duration: 0.9)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            VStack(spacing: 8) {
                Text("Joining room" + String(repeating: ".", count: dotCount))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .onReceive(timer) { _ in dotCount = (dotCount + 1) % 4 }
                Text("Finding your seat at the TV")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            ProgressView().tint(PhonePlayDesign.cyan)
            Spacer()
            if let onCancel {
                PhonePlayGhostButton(title: "Cancel", symbol: "xmark", action: onCancel)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { appeared = true }
        }
    }
}

struct ErrorJoinView: View {
    let message: String
    let onRetry: () -> Void
    var onHome: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([PhonePlayDesign.red, PhonePlayDesign.orange]))
                    .frame(width: 112, height: 112)
                    .shadow(color: PhonePlayDesign.red.opacity(0.45), radius: 22, y: 8)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)
                    .phonePlayIdle(degrees: 5, duration: 0.8)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            VStack(spacing: 8) {
                Text("Could not join")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 12) {
                PhonePlayBigButton(title: "Try Again", symbol: "arrow.counterclockwise",
                                   colors: [PhonePlayDesign.cyan, PhonePlayDesign.indigo],
                                   action: onRetry)
                if let onHome {
                    PhonePlayGhostButton(title: "Back to home", symbol: "house.fill", action: onHome)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .onAppear {
            PhonePlayHaptics.error()
            withAnimation(PhonePlayDesign.pop) { appeared = true }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ControllerRootViewModel: ObservableObject {
    /// `.join` is the app's home: the Phone Play games with the "Play on
    /// TV" hero; the join form itself is a sheet over it (showJoinSheet).
    @Published var screen: ControllerScreen = .join {
        didSet {
            // Leaving the home for anything else (a join, an incoming room
            // event) must not leave a Phone Play game talking underneath.
            if oldValue == .join, screen != .join, phonePlay.active != nil {
                phonePlay.shutdown()
            }
        }
    }
    /// Room code handed over by a deep link (or the last attempt, for an
    /// error retry), pre-filled in the join sheet.
    @Published var pendingJoinCode: String? = nil
    /// The "Play on TV" join sheet over the home screen. RootControllerView
    /// only presents it while the screen is .join.
    @Published var showJoinSheet: Bool = false
    /// A TV room this phone was seated in when the app last went away
    /// (killed or crashed mid-game). Drives the home's "Back to your TV
    /// game" banner; cleared on an explicit leave or a failed rejoin.
    @Published private(set) var resumableRoomCode: String? = nil

    /// Rules interstitial data from the last `game_started` broadcast. Set
    /// on start; cleared on `game_begun` (the host tapped Begin), when the
    /// player leaves the room, or on return to the join screen. Kept in the
    /// view model, not the view, because `room_updated` rebuilds screens
    /// repeatedly.
    @Published var pendingRules: GameRules?

    private let socket = GameSocketManager.shared

    /// This phone's seat on the server. It starts as the device id and
    /// becomes whatever seat `room_joined` hands back: two phones restored
    /// from one backup send the same device id, and the server seats the
    /// second one separately (`<id>-2`) rather than letting them share a
    /// seat, a colour and a score. Everything this phone sends -- actions,
    /// ready, team moves, reconnects -- is keyed on the seat it was given.
    @Published private(set) var playerID = AppConstants.deviceID

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

    /// Non-nil while Travel Mode is active. Travel Mode is phone-only (no
    /// room), so none of the socket handlers below involve it.
    @Published var travelVM: TravelModeViewModel? = nil

    /// Phone Play (single-phone, no-TV games) is the home screen, so it
    /// lives as long as the app. Like Travel Mode it is phone-only, so no
    /// socket handler involves it; leaving the home (joining a room,
    /// starting Road Trip Quiz) shuts its current game down.
    let phonePlay: PhonePlayViewModel

    var isHost: Bool {
        currentRoom?.players.first(where: { $0.id == playerID })?.isHost ?? false
    }

    /// See joinRoom(code:name:)'s own comment: a bounded fallback for a join
    /// that never gets any response back at all.
    private var joinTimeoutTask: Task<Void, Never>?

    init() {
        phonePlay = PhonePlayViewModel()
        resumableRoomCode = Self.loadResumableRoom()

        // Server confirms the join (or a reconnect re-seat) -- route by the
        // room's state so a phone that rejoins mid-game stays on its
        // controller instead of flashing back to the lobby.
        socket.on(.roomJoined) { [weak self] (response: RoomJoinedResponse) in
            guard let self else { return }
            self.joinTimeoutTask?.cancel()
            self.pendingJoinCode = nil
            self.showJoinSheet = false
            let room = response.room
            if !response.playerID.isEmpty { self.playerID = response.playerID }
            self.rememberRoom(room.code)
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
                // results -> lobby is Game Night's next_game moving the room on.
                switch self.screen {
                case .waiting, .results: self.screen = .waiting(room)
                default: break
                }
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
            guard let self else { return }
            guard r.playerID == self.playerID else { return }
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
                if let attempted = self.pendingJoinCode {
                    self.forgetResumableRoom(ifCode: attempted)
                }
                self.screen = .error(r.message)
            }
        }
    }

    func joinRoom(code: String, name: String) {
        let upper = code.uppercased()
        playerName = name
        pendingRules = nil
        // Start from the device id: a seat suffix the server handed out in
        // one room means nothing in the next one.
        playerID = AppConstants.deviceID
        // Kept until room_joined so an error retry re-opens the sheet with
        // the same code already filled in.
        pendingJoinCode = upper
        showJoinSheet = false
        screen = .loading
        socket.emit(.joinRoom, payload: JoinRoomPayload(
            roomCode: upper,
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
                self.forgetResumableRoom(ifCode: upper)
                self.screen = .error("Couldn't join. Check the room code and try again.")
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

    /// Back to the home screen from anywhere: leaves the TV room (if
    /// seated) or ends Road Trip Quiz.
    func leaveRoom() {
        // A deep link mid-travel (or any other path here) must tear the
        // travel session down, not just switch screens under it.
        if travelVM != nil {
            endTravel()
            return
        }
        switch screen {
        case .playing(let room, _), .waiting(let room), .rules(let room, _):
            socket.emit(.leaveRoom, payload: ["roomCode": room.code, "playerID": playerID])
            forgetResumableRoom(ifCode: room.code)
        case .results(let room):
            // The seat is given up on purpose, so the home must not offer
            // "Back to your TV game" for it.
            forgetResumableRoom(ifCode: room.code)
        default:
            break
        }
        pendingRules = nil
        showJoinSheet = false
        screen = .join
    }

    /// Error "Try Again": back home with the join sheet open again.
    func returnToJoin() {
        pendingRules = nil
        screen = .join
        showJoinSheet = true
    }

    /// Error "Back to home" / loading "Cancel".
    func returnHome() {
        joinTimeoutTask?.cancel()
        pendingRules = nil
        showJoinSheet = false
        screen = .join
    }

    /// The home's "Play on TV" hero.
    func openJoinSheet() {
        showJoinSheet = true
    }

    // MARK: - Back to your TV game

    private static let lastRoomKey = "aurora_last_room_code"
    private static let lastRoomAtKey = "aurora_last_room_at"
    /// A seat older than this is long gone server-side.
    private static let resumableWindow: TimeInterval = 3 * 60 * 60

    private static func loadResumableRoom() -> String? {
        let d = UserDefaults.standard
        guard let code = d.string(forKey: lastRoomKey), code.count == 6 else { return nil }
        let at = d.double(forKey: lastRoomAtKey)
        guard at > 0, Date().timeIntervalSince1970 - at < resumableWindow else { return nil }
        return code
    }

    private func rememberRoom(_ code: String) {
        let d = UserDefaults.standard
        d.set(code, forKey: Self.lastRoomKey)
        d.set(Date().timeIntervalSince1970, forKey: Self.lastRoomAtKey)
        // The banner is for the NEXT launch; while seated, no banner.
        resumableRoomCode = nil
    }

    /// Forgets the remembered room (only if it is `code`, when given).
    func forgetResumableRoom(ifCode code: String? = nil) {
        let d = UserDefaults.standard
        if let code, d.string(forKey: Self.lastRoomKey) != code { return }
        d.removeObject(forKey: Self.lastRoomKey)
        d.removeObject(forKey: Self.lastRoomAtKey)
        resumableRoomCode = nil
    }

    /// "Back to your TV game": re-sends join_room for the remembered seat,
    /// exactly like the reconnect path (rejoinIfSeated). Without a saved
    /// name it opens the join sheet with the code filled in instead.
    func resumeTVGame() {
        guard let code = resumableRoomCode else { return }
        let name = playerName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            pendingJoinCode = code
            showJoinSheet = true
        } else {
            joinRoom(code: code, name: name)
        }
    }

    // MARK: - Road Trip Quiz (Travel Mode)

    func startTravel() {
        pendingRules = nil
        showJoinSheet = false
        phonePlay.shutdown()
        travelVM = TravelModeViewModel()
        screen = .travel
    }

    func endTravel() {
        travelVM?.shutdown()
        travelVM = nil
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
            // Straight to joining: close any Phone Play game and open the
            // join sheet with the code filled in.
            if phonePlay.active != nil { phonePlay.closeGame() }
            pendingJoinCode = code
            showJoinSheet = true
        } else if currentRoom?.code != code {
            leaveRoom()
            pendingJoinCode = code
            showJoinSheet = true
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
