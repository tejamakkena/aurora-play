import Foundation

// MARK: - Game Night, profiles, picker and AI decks: shared models + API
//
// Server side: games/game_night.py, games/profiles.py, games/ai_decks.py,
// games/daily.py. Everything here is additive and optional so an older
// server simply returns nothing and the apps carry on without it.

// MARK: Game Night (rides along in room_updated as Room.night)

struct GameNight: Codable, Equatable {
    var playlist: [String]
    var index: Int
    var current: String?
    var next: String?
    var finished: Bool
    var standings: [NightStanding]
    var gamesPlayed: Int
    /// The occasion, guest of honour and spoken script, when the host set up a
    /// party (games/night_party.py). nil for a plain Game Night. Optional so
    /// older servers still decode.
    var party: NightParty? = nil
    /// How the night scores ("classic", "fair" or "comeback") and what the game
    /// now up is worth (2 on the last game of a "comeback" night). Optional so
    /// older servers still decode.
    var points: String? = nil
    var pointsLabel: String? = nil
    var multiplier: Int? = nil
    /// The rounds the host picked, by game id.
    var rounds: [String: String]? = nil

    /// The playlist as known games (unknown ids from a newer server are skipped).
    var games: [GameID] { playlist.compactMap { GameID(rawValue: $0) } }
    var nextGame: GameID? { next.flatMap { GameID(rawValue: $0) } }
    var champion: NightStanding? { finished ? standings.first : nil }
}

/// A Game Night dressed as an occasion. The TV holds a welcome screen until the
/// host begins, then speaks `welcomeLines` and `lineupLines`; at the end it speaks
/// `finaleLines`. The server fixes the wording, so every device agrees.
struct NightParty: Codable, Equatable {
    var occasion: String
    var honoree: String
    var title: String
    var cheer: String
    var welcomed: Bool
    var welcomeLines: [String]
    var lineupLines: [String]
    var finaleLines: [String]
    /// How each line above is said ("welcome", "cheer", "roast", "indian"...), one
    /// per line, by index. Optional so older servers still decode.
    var welcomeCues: [String]? = nil
    var lineupCues: [String]? = nil
    var finaleCues: [String]? = nil
    /// True when the guest of honour's name is said in the Indian voice.
    var indianVoice: Bool? = nil
    /// Name on screen -> how the voice says it (the host's "Say it as" spelling).
    var sayAs: [String: String]? = nil

    /// The cue for line `index` of a list, or `fallback` when the server sent none.
    static func cue(_ cues: [String]?, _ index: Int, fallback: String) -> String {
        guard let cues, cues.indices.contains(index) else { return fallback }
        return cues[index]
    }
}

/// The host's party choices, sent with start_night (server: night_party.clean_party).
struct NightPartyPayload: Encodable {
    var occasion: String
    var honoree: String
    var style: String
    var humor: String
    var nhiePack: String
    var nhieRounds: Int
    /// How the name is said: "auto" (Indian names in the Indian voice),
    /// "indian" or "standard".
    var accent: String = "auto"
    /// How to say the name, when the voice gets it wrong ("Ven-kut"). Blank: as written.
    var honoreeSaid: String = ""
}

struct NightStanding: Codable, Equatable, Identifiable {
    let playerID: String
    let name: String
    let points: Int
    let rank: Int
    var isBot: Bool? = nil
    var id: String { playerID }
}

struct StartNightPayload: Encodable {
    let roomCode: String
    var playlist: [String]? = nil
    var minutes: Int? = nil
    var kids: Bool? = nil
    var party: NightPartyPayload? = nil
    /// The host's per-game picks, by game id then option key (server:
    /// game_night.clean_settings), e.g. ["trivia": ["rounds": "4"]].
    var settings: [String: [String: String]]? = nil
    /// How the night scores (NightPoints.rawValue).
    var points: String? = nil
}

struct RoomCodePayload: Encodable {
    let roomCode: String
}

// MARK: Make-your-own quiz

/// One trivia question in the server's shape (topic_gen.validate_question).
struct QuizQuestion: Codable, Equatable, Identifiable {
    var question: String
    var options: [String]
    var correct_answer: Int
    var id: String { question }

    var isComplete: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty
            && options.count == 4
            && options.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            && Set(options.map { $0.lowercased() }).count == 4
            && (0...3).contains(correct_answer)
    }
}

struct CustomQuestionsPayload: Encodable {
    let roomCode: String
    let questions: [QuizQuestion]
}

// MARK: Profiles

struct PlayerProfile: Codable, Equatable {
    var id: String
    var name: String
    var color: String
    var avatar: String
    var stats: ProfileStats?
}

struct ProfileStats: Codable, Equatable {
    var played: Int?
    var wins: Int?
    var podiums: Int?
    var nights: Int?
    var nightWins: Int?
}

// MARK: Picker

struct PickedGame: Codable, Equatable, Identifiable {
    let id: String
    let minutes: Int
    let kids: Bool
    let minPlayers: Int
    let maxPlayers: Int
    /// The game's lobby picks (rounds, decks...). Sent by a newer server.
    var options: [PickedOption]? = nil
    /// false for a game that does not suit this many players, listed only in
    /// the host's "all games" view.
    var fits: Bool? = nil
    var game: GameID? { GameID(rawValue: id) }
}

struct PickedOptionChoice: Codable, Equatable, Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct PickedOption: Codable, Equatable, Identifiable {
    let key: String
    let label: String
    let defaultValue: String
    let choices: [PickedOptionChoice]
    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key, label, choices
        case defaultValue = "default"
    }
}

// MARK: - API

enum OneStopAPI {
    private struct ProfileEnvelope: Decodable { let profile: PlayerProfile }
    private struct PickerEnvelope: Decodable { let games: [PickedGame] }
    private struct QuizEnvelope: Decodable { let items: [QuizQuestion] }
    private struct WordsEnvelope: Decodable { let items: [String] }

    private static func url(_ path: String, _ query: [URLQueryItem] = []) -> URL? {
        var c = URLComponents(url: AppConstants.serverURL.appendingPathComponent(path),
                              resolvingAgainstBaseURL: false)
        if !query.isEmpty { c?.queryItems = query }
        return c?.url
    }

    private static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async -> T? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func profile(device: String = AppConstants.deviceID) async -> PlayerProfile? {
        guard let u = url("api/profile/\(device)") else { return nil }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        return await send(r, as: ProfileEnvelope.self)?.profile
    }

    @discardableResult
    static func saveProfile(name: String, color: String, avatar: String,
                            device: String = AppConstants.deviceID) async -> PlayerProfile? {
        guard let u = url("api/profile/\(device)") else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = "PUT"
        r.timeoutInterval = 20
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": name, "color": color, "avatar": avatar,
        ])
        return await send(r, as: ProfileEnvelope.self)?.profile
    }

    /// `party`: a party night, so Never Have I Ever, Guess the Song and the
    /// other room-wide games come first (games/game_night.py pick_games).
    static func pick(players: Int, kids: Bool, minutes: Int?, party: Bool = false) async -> [PickedGame] {
        var q = [URLQueryItem(name: "players", value: String(players)),
                 URLQueryItem(name: "kids", value: kids ? "1" : "0")]
        if let minutes { q.append(URLQueryItem(name: "minutes", value: String(minutes))) }
        if party { q.append(URLQueryItem(name: "party", value: "1")) }
        guard let u = url("api/picker", q) else { return [] }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        return await send(r, as: PickerEnvelope.self)?.games ?? []
    }

    /// Every game, the ones that suit this group first, for the host's builder.
    static func pickAll(players: Int, kids: Bool) async -> [PickedGame] {
        let q = [URLQueryItem(name: "players", value: String(players)),
                 URLQueryItem(name: "kids", value: kids ? "1" : "0"),
                 URLQueryItem(name: "all", value: "1")]
        guard let u = url("api/picker", q) else { return [] }
        var r = URLRequest(url: u)
        r.timeoutInterval = 20
        return await send(r, as: PickerEnvelope.self)?.games ?? []
    }

    private static func deckRequest(kind: String, topic: String, count: Int,
                                    familySafe: Bool, language: String) -> URLRequest? {
        guard let u = url("api/decks/generate") else { return nil }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.timeoutInterval = 60
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [
            "kind": kind, "topic": topic, "count": count,
            "familySafe": familySafe, "language": language,
        ] as [String: Any])
        return r
    }

    /// AI-written quiz on a topic ([] when offline or no model on the server).
    static func quiz(topic: String, count: Int = 10, familySafe: Bool = true,
                     language: String = "en") async -> [QuizQuestion] {
        guard let r = deckRequest(kind: "quiz", topic: topic, count: count,
                                  familySafe: familySafe, language: language) else { return [] }
        return (await send(r, as: QuizEnvelope.self)?.items ?? []).filter { $0.isComplete }
    }

    /// AI-written word/prompt deck: kind is headsup, truth, dare, wyr or hotpotato.
    static func deck(kind: String, topic: String, count: Int = 30, familySafe: Bool = true,
                     language: String = "en") async -> [String] {
        guard let r = deckRequest(kind: kind, topic: topic, count: count,
                                  familySafe: familySafe, language: language) else { return [] }
        return await send(r, as: WordsEnvelope.self)?.items ?? []
    }
}
