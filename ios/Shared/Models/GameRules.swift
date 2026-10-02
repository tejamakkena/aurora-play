import Foundation

/// How-to-play data for one game, decoded from the server's `game_started`
/// payload. The backend is the single source of truth for this text --
/// neither the TV app nor the controller keeps its own copy, so updating
/// the wording in `games/native_hub/rules.py` updates both screens.
struct GameRules: Codable {
    let gameID: String
    let title: String
    let objective: String
    let rules: [String]
    let controls: String
}

/// The `game_started` broadcast the server emits right after a game starts.
/// `rules` is what drives the how-to-play interstitial on both clients.
/// The engine itself stays gated until the host taps Begin (`game_begun`).
struct GameStartedResponse: Decodable {
    let roomCode: String
    let gameID: String
    let rules: GameRules
}

/// The `game_begun` broadcast: the host tapped Begin, the engine started for
/// real, and the pump is about to push the first board state. Both clients
/// drop the rules interstitial on this.
struct GameBegunResponse: Decodable {
    let roomCode: String
    let gameID: String
}
