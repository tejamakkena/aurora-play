import Foundation

// MARK: - Game Night builder: what the host chooses before the night starts
//
// Used by the host's phone (GameNightPlannerCard) and the TV home screen
// (TVNightSetupPanel). Server: games/game_night.py (clean_settings, POINT_MODES)
// and games/native_hub/options.py (the per-game Rounds pick).

/// How a night turns each game's placings into points (server POINT_MODES).
enum NightPoints: String, CaseIterable, Identifiable {
    case classic
    case fair
    case comeback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .fair: return "Fair share"
        case .comeback: return "Big finish"
        }
    }

    var hint: String {
        switch self {
        case .classic: return "10, 7, 5, 3 points, 1 for the rest"
        case .fair: return "Every place counts, 10 down to 1"
        case .comeback: return "Classic, with the last game worth double"
        }
    }
}

/// The host's plan for the night: which games, in what order, how many rounds
/// of each, and how it scores.
struct NightPlan: Equatable {
    /// The server accepts at most this many games in a night.
    static let maxGames: Int = 10

    var games: [PickedGame] = []
    /// Rounds the host chose, by game id. A game with no entry plays its own length.
    var rounds: [String: String] = [:]
    var points: NightPoints = .classic

    var playlist: [String] { games.map { $0.id } }

    /// The per-game picks to send with start_night (nil when nothing was changed).
    var settings: [String: [String: String]]? {
        var out: [String: [String: String]] = [:]
        for game in games {
            if let pick = rounds[game.id] { out[game.id] = ["rounds": pick] }
        }
        return out.isEmpty ? nil : out
    }

    func contains(_ id: String) -> Bool {
        games.contains { $0.id == id }
    }

    /// The rounds this game will play: the host's pick, else the game's own length.
    func roundsValue(for game: PickedGame) -> String? {
        guard let option = game.roundsOption else { return nil }
        return rounds[game.id] ?? option.defaultValue
    }

    /// Rough minutes for a game, scaled by how far the rounds differ from its own.
    func minutes(for game: PickedGame) -> Int {
        guard let option = game.roundsOption,
              let picked = rounds[game.id].flatMap({ Int($0) }),
              let base = Int(option.defaultValue), base > 0 else { return game.minutes }
        return max(2, Int((Double(game.minutes) * Double(picked) / Double(base)).rounded()))
    }

    var totalMinutes: Int {
        games.reduce(0) { $0 + minutes(for: $1) }
    }

    mutating func setRounds(_ value: String, for game: PickedGame) {
        guard let option = game.roundsOption,
              option.choices.contains(where: { $0.value == value }) else { return }
        if value == option.defaultValue {
            rounds[game.id] = nil
        } else {
            rounds[game.id] = value
        }
    }

    /// Adds a game to the end. False when it is already in or the night is full.
    @discardableResult
    mutating func add(_ game: PickedGame) -> Bool {
        guard game.game != nil, !contains(game.id), games.count < Self.maxGames else { return false }
        games.append(game)
        return true
    }

    mutating func remove(_ id: String) {
        games.removeAll { $0.id == id }
        rounds[id] = nil
    }

    /// Moves a game earlier (-1) or later (+1) in the order.
    mutating func move(_ id: String, by step: Int) {
        guard let from = games.firstIndex(where: { $0.id == id }) else { return }
        let to = from + step
        guard games.indices.contains(to) else { return }
        games.swapAt(from, to)
    }
}

extension PickedGame {
    /// The "Rounds" pick, for a game whose length is counted in rounds.
    var roundsOption: PickedOption? {
        options?.first { $0.key == "rounds" }
    }
}
