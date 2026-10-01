import Foundation
import SocketIO

/// Shared Socket.IO client used by both the TV app and the phone controller app.
/// Call `connect(to:)` once on launch; then use `emit` / `on` for game events.
final class GameSocketManager: ObservableObject {

    static let shared = GameSocketManager()

    @Published var isConnected = false

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    /// The real decode-and-dispatch closure for each event, keyed by its raw
    /// socket.io event name -- not a placeholder. This is what makes `on(_:handler:)`
    /// safe to call before `connect(to:)` has ever run.
    ///
    /// SwiftUI evaluates a view's `@StateObject` initializer (and therefore, for
    /// example, `TVRootViewModel.init()`'s own `socket.on(.roomUpdated) { ... }`
    /// call) before that view's `.onAppear` ever fires -- and `connect(to:)` was
    /// only ever called from `.onAppear`. `socket` here was still `nil` at that
    /// point, so `socket?.on(key) { ... }` was a silent no-op: the handler was
    /// never actually attached to anything, permanently, for the lifetime of the
    /// app. The previous `handlers` dict existed only as an inert per-event
    /// marker (`{ _ in _ = self }`) that `reattachHandlers()` never even read --
    /// its body was just a comment. Server events like `room_updated` were
    /// arriving at the transport layer the whole time; nothing on the Swift side
    /// was ever listening for them, on every single game, unconditionally.
    ///
    /// Storing the actual dispatch closure here means `attachAllHandlers()` can
    /// wire up everything that was registered -- before `connect(to:)`, after
    /// it, or on a prior connection that then dropped -- the moment a real
    /// socket exists, and identically on every reconnect.
    private var handlers: [String: ([Any]) -> Void] = [:]

    /// Run on every successful connect, including each automatic reconnect.
    /// The server gives a reconnected socket a new sid that is in no room,
    /// so a view model that was mid-game uses this to re-send join_room
    /// (the server re-attaches the same playerID to its seat). Without it a
    /// phone that locked its screen came back deaf: no private_state, and
    /// every action rejected as "Not in this room".
    private var connectHooks: [String: () -> Void] = [:]

    func onConnected(_ key: String, _ hook: @escaping () -> Void) {
        connectHooks[key] = hook
    }

    private init() {}

    // MARK: - Connection

    func connect(to serverURL: URL) {
        manager = SocketManager(
            socketURL: serverURL,
            config: [.log(false), .compress, .reconnects(true), .reconnectWait(2)]
        )
        // The hub lives on its own namespace: five browser games register the
        // same create_room/join_room names on the default namespace, where only
        // the last registration survives.
        socket = manager?.socket(forNamespace: AppConstants.socketNamespace)

        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isConnected = true
                for hook in self.connectHooks.values { hook() }
            }
        }
        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            DispatchQueue.main.async { self?.isConnected = false }
        }

        // Re-attach every registered handler after a reconnect -- socket.io
        // itself doesn't remember per-event listeners across a fresh
        // connection the way this layer needs it to.
        socket?.on(clientEvent: .reconnect) { [weak self] _, _ in
            self?.attachAllHandlers()
        }

        // Wire up anything registered via on(_:handler:) before this socket
        // existed at all -- the exact scenario a view model's init() hits.
        attachAllHandlers()

        socket?.connect()
    }

    func disconnect() {
        socket?.disconnect()
    }

    // MARK: - Emit

    func emit(_ event: ClientEvent, payload: Encodable) {
        guard let socket, let data = try? JSONEncoder().encode(payload),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        socket.emit(event.rawValue, dict)
    }

    // MARK: - Listen

    /// Register a typed handler for a server event. Replaces any previous
    /// handler for the same event. Safe to call at any time, including
    /// before `connect(to:)` has ever run -- see `handlers`' own doc comment.
    func on<T: Decodable>(_ event: ServerEvent, handler: @escaping (T) -> Void) {
        let key = event.rawValue
        handlers[key] = { data in
            guard let raw = data.first,
                  let jsonData = try? JSONSerialization.data(withJSONObject: raw),
                  let decoded = try? JSONDecoder().decode(T.self, from: jsonData)
            else { return }
            DispatchQueue.main.async { handler(decoded) }
        }
        attach(key)
    }

    func off(_ event: ServerEvent) {
        socket?.off(event.rawValue)
        handlers.removeValue(forKey: event.rawValue)
    }

    // MARK: - Private

    /// Attaches a single stored handler to the real socket, if one exists yet.
    /// A no-op (handler stays queued in `handlers`) when called before
    /// `connect(to:)` -- `attachAllHandlers()` picks it up once a socket does.
    private func attach(_ key: String) {
        guard let socket, let dispatch = handlers[key] else { return }
        socket.off(key)
        socket.on(key) { data, _ in dispatch(data) }
    }

    private func attachAllHandlers() {
        for key in handlers.keys {
            attach(key)
        }
    }
}
