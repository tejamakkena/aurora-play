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

    var hostPlayerID: String { players.first?.id ?? "" }
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
