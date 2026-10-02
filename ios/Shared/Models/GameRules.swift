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
struct GameStartedResponse: Decodable {
    let roomCode: String
    let gameID: String
    let rules: GameRules
}
