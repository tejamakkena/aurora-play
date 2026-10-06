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

    /// The playlist as known games (unknown ids from a newer server are skipped).
    var games: [GameID] { playlist.compactMap { GameID(rawValue: $0) } }
    var nextGame: GameID? { next.flatMap { GameID(rawValue: $0) } }
    var champion: NightStanding? { finished ? standings.first : nil }
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
    var game: GameID? { GameID(rawValue: id) }
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

    static func pick(players: Int, kids: Bool, minutes: Int?) async -> [PickedGame] {
        var q = [URLQueryItem(name: "players", value: String(players)),
                 URLQueryItem(name: "kids", value: kids ? "1" : "0")]
        if let minutes { q.append(URLQueryItem(name: "minutes", value: String(minutes))) }
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
