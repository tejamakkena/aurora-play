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

/// The host's plan for the night: which games, in what order, what each game's
/// options are set to (rounds, time limit, decks, chips...), and how it scores.
struct NightPlan: Equatable {
    /// The server accepts at most this many games in a night.
    static let maxGames: Int = 10

    var games: [PickedGame] = []
    /// What the host changed, by game id then option key. An option left at its
    /// default has no entry, so the game plays as it normally does.
    var picks: [String: [String: String]] = [:]
    var points: NightPoints = .classic

    var playlist: [String] { games.map { $0.id } }

    /// The per-game picks to send with start_night (nil when nothing was changed).
    var settings: [String: [String: String]]? {
        var out: [String: [String: String]] = [:]
        for game in games {
            if let chosen = picks[game.id], !chosen.isEmpty { out[game.id] = chosen }
        }
        return out.isEmpty ? nil : out
    }

    func contains(_ id: String) -> Bool {
        games.contains { $0.id == id }
    }

    /// The value this option will have: the host's pick, else the game's own.
    func value(of option: PickedOption, in game: PickedGame) -> String {
        picks[game.id]?[option.key] ?? option.defaultValue
    }

    /// What to show on the option's button, e.g. "6 rounds" or "Time limit: 5 minutes".
    func caption(of option: PickedOption, in game: PickedGame) -> String {
        let current = value(of: option, in: game)
        let label = option.choices.first { $0.value == current }?.label ?? current
        return option.key == "rounds" ? label : "\(option.label): \(label)"
    }

    func isChanged(_ option: PickedOption, in game: PickedGame) -> Bool {
        picks[game.id]?[option.key] != nil
    }

    /// Rough minutes for a game: a time limit is the answer; rounds scale the
    /// game's usual length.
    func minutes(for game: PickedGame) -> Int {
        if let option = game.options?.first(where: { $0.key == "minutes" }),
           let limit = Int(value(of: option, in: game)), limit > 0 {
            return limit
        }
        guard let option = game.roundsOption,
              let picked = Int(value(of: option, in: game)),
              let base = Int(option.defaultValue), base > 0 else { return game.minutes }
        return max(2, Int((Double(game.minutes) * Double(picked) / Double(base)).rounded()))
    }

    var totalMinutes: Int {
        games.reduce(0) { $0 + minutes(for: $1) }
    }

    mutating func set(_ value: String, for option: PickedOption, in game: PickedGame) {
        guard option.choices.contains(where: { $0.value == value }) else { return }
        var chosen = picks[game.id] ?? [:]
        if value == option.defaultValue {
            chosen[option.key] = nil
        } else {
            chosen[option.key] = value
        }
        picks[game.id] = chosen.isEmpty ? nil : chosen
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
        picks[id] = nil
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
