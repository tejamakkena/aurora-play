import Foundation

struct Room: Codable, Equatable {
    let code: String
    let gameID: GameID
    var players: [Player]
    var state: RoomState
    // "rules" while the room waits for the host's Begin after Start Game;
    // "play" once the engine is actually running. Optional so older servers
    // that omit it still decode.
    var phase: String? = nil
    // Lobby options. Optional so older servers that omit them still decode.
    var contentPack: String? = nil
    var botsAllowed: Bool? = nil
    var usesContentPack: Bool? = nil
    // Free-text question topic (Trivia / Travel Mode), set via set_topic.
    // "" or nil means the usual mixed questions.
    var topic: String? = nil
    // Game Night (games/game_night.py). nil outside a Game Night.
    var night: GameNight? = nil
    // Teams mode (games/teams.py). nil when everyone plays for themselves.
    var teams: RoomTeams? = nil
    // Per-game lobby picks (Poker: hands, chips, re-buys). nil or empty for
    // games without any.
    var options: [GameOption]? = nil
    // False while no TV board is attached (the TV app was switched away or
    // lost Wi-Fi). Phones show a "waiting for the TV" banner. nil on older servers.
    var tvConnected: Bool? = nil
    // The finished game's ranking, best first (only while state is
    // .results). Every results screen shows this as-is: rank and score come
    // from the game itself, so a game that only knows its winner, or keeps
    // its own score, still ranks right. nil on older servers.
    var results: [RoomResult]? = nil

    var hostPlayerID: String { players.first?.id ?? "" }

    /// The ranking to show at the end: the server's when it sent one, else
    /// (older servers) the players sorted by score.
    var finalRanking: [RoomResult] {
        if let results, !results.isEmpty { return results }
        var rows: [RoomResult] = []
        for player in players.sorted(by: { $0.score > $1.score }) {
            let tied: Bool = rows.last.map { $0.score == player.score } ?? false
            rows.append(RoomResult(playerID: player.id, name: player.name, score: player.score,
                                   rank: tied ? (rows.last?.rank ?? 1) : rows.count + 1, detail: nil))
        }
        return rows
    }
}

/// One row of a finished game's ranking. Equal ranks are a tie.
struct RoomResult: Codable, Equatable, Identifiable {
    let playerID: String
    let name: String
    let score: Int
    let rank: Int
    /// A short note shown with the score ("Winner", "Out in round 3").
    var detail: String? = nil
    /// What the score means in this game ("12 pts", "Winner", "42 chips"); empty
    /// when the game has no score to show. Older servers send none: "N pts".
    var scoreLabel: String? = nil

    var id: String { playerID }
}

/// One lobby pick for a game (games/native_hub/options.py): a short menu the
/// TV or host cycles through before the game starts.
struct GameOption: Codable, Equatable, Identifiable {
    struct Choice: Codable, Equatable {
        let value: String
        let label: String
    }

    let key: String
    let label: String
    let value: String
    let choices: [Choice]

    var id: String { key }

    var currentLabel: String {
        choices.first(where: { $0.value == value })?.label ?? value
    }

    /// The value after the current one, wrapping round.
    var nextValue: String {
        guard !choices.isEmpty else { return value }
        let index: Int = choices.firstIndex(where: { $0.value == value }) ?? -1
        return choices[(index + 1) % choices.count].value
    }
}

/// Question languages the server ships (games/native_hub/engines/content_packs.py).
enum ContentPack: String, CaseIterable, Identifiable {
    case en, te, hi
    var id: String { rawValue }
    var label: String {
        switch self {
        case .en: return "English"
        case .te: return "Telugu"
        case .hi: return "Hindi"
        }
    }
    var next: ContentPack {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}

struct Player: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var isReady: Bool
    var score: Int
    var isHost: Bool
    // Bot seat-filler added by the host. Decoded with decodeIfPresent so
    // rooms created before this field existed still decode.
    var isBot: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, isReady, score, isHost, isBot
    }
}

// Custom decoding lives in an extension so Player keeps its synthesized
// memberwise initializer (TV boards build Player values directly).
extension Player {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isReady = try c.decode(Bool.self, forKey: .isReady)
        score = try c.decode(Int.self, forKey: .score)
        isHost = try c.decode(Bool.self, forKey: .isHost)
        isBot = try c.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
    }
}

enum RoomState: String, Codable {
    case lobby    = "lobby"
    case playing  = "playing"
    case results  = "results"
}
