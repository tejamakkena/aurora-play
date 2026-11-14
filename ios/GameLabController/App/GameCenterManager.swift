import SwiftUI
import GameKit
import CryptoKit

// MARK: - Game Center sign-in
//
// Game Center is the only login Aurora Play has: Apple shows its own prompt,
// the app never sees a password, and a player who says no (or has no Game
// Center) still plays exactly as before on the device id. Signing in adds
// two things:
//
//   * the Game Center name is used as the player's name until they pick one;
//   * the join message carries `gcID`, so the TV's house leaderboard
//     (Shared/Models/HouseBoard.swift) can count the same person across
//     rooms and nights.
//
// `gcID` is a short salted hash of Apple's team player id. The server and the
// other phones only ever see the hash, never Apple's id.

@MainActor
final class GameCenterManager: ObservableObject {
    static let shared = GameCenterManager()

    enum State: Equatable {
        /// Asked Apple, no answer yet.
        case unknown
        /// Not signed in, or the player declined.
        case signedOut
        case signedIn
    }

    @Published private(set) var state: State = .unknown
    /// The Game Center name ("" until signed in).
    @Published private(set) var alias = ""
    /// 16 hex characters, or nil for a guest.
    @Published private(set) var gcID: String? = nil

    private var started = false
    private static let nameKey = "aurora_player_name"

    var isSignedIn: Bool { state == .signedIn }

    /// Starts the sign-in. Safe to call more than once; Apple shows its own
    /// prompt the first time, and at most a few more times if it is dismissed.
    func start() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                self?.handle(viewController)
            }
        }
    }

    /// Asks again (the profile's "Try again" row), after a dismissed prompt.
    func retry() {
        started = false
        start()
    }

    private func handle(_ viewController: UIViewController?) {
        if let viewController {
            Self.present(viewController)
            return
        }
        let local = GKLocalPlayer.local
        guard local.isAuthenticated else {
            state = .signedOut
            alias = ""
            gcID = nil
            return
        }
        alias = local.alias
        gcID = Self.hash(local.teamPlayerID)
        state = .signedIn
        adoptNameIfEmpty()
    }

    /// The Game Center name becomes the player's name only while they have not
    /// chosen one; it never overwrites a name someone typed.
    private func adoptNameIfEmpty() {
        let defaults = UserDefaults.standard
        let saved = (defaults.string(forKey: Self.nameKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard saved.isEmpty else { return }
        let words = alias.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let name = String(words.joined(separator: " ").prefix(20))
        if !name.isEmpty { defaults.set(name, forKey: Self.nameKey) }
    }

    /// First 16 hex characters of a SHA-256 over a fixed salt and Apple's id.
    /// The server accepts exactly this shape (utils/validators.py gc_id).
    nonisolated static func hash(_ playerID: String) -> String {
        let digest = SHA256.hash(data: Data(("aurora-play|" + playerID).utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func present(_ viewController: UIViewController) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        top.present(viewController, animated: true)
    }
}

// MARK: - A line for the profile screen

/// "Game Center: signed in as X" / "Not signed in", with the reason it matters.
struct GameCenterStatusRow: View {
    @ObservedObject private var gc = GameCenterManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: gc.isSignedIn ? "checkmark.seal.fill" : "gamecontroller")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(gc.isSignedIn ? PhonePlayDesign.green : Color.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(gc.isSignedIn ? "Game Center: \(gc.alias)" : "Game Center: not signed in")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(gc.isSignedIn
                     ? "You will appear on the TV's house leaderboard."
                     : "Sign in to Game Center in Settings to join the TV's house leaderboard.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if gc.state == .signedOut {
                Button("Try again") { gc.retry() }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}
