import Foundation

// MARK: - Saved Game Night lineups, and the last party's settings
//
// Kept on this device (UserDefaults): the TV and the host's phone each keep
// their own. A lineup is the games in order, the options changed for each
// (rounds, time limit...) and the scoring rule.

struct SavedNight: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var games: [String]
    var picks: [String: [String: String]]
    var points: String
}

enum SavedNights {
    private static let defaultsKey = "aurora_saved_nights_v1"
    /// The most lineups kept; saving one more drops the oldest.
    static let cap = 8

    static func all() -> [SavedNight] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([SavedNight].self, from: data) else { return [] }
        return saved
    }

    private static func store(_ nights: [SavedNight]) {
        if let data = try? JSONEncoder().encode(nights) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Saves `plan` (newest first) and returns it; an identical lineup is not saved twice.
    @discardableResult
    static func save(_ plan: NightPlan) -> SavedNight? {
        guard !plan.games.isEmpty else { return nil }
        let night = SavedNight(id: UUID().uuidString, name: name(for: plan),
                               games: plan.playlist, picks: plan.picks, points: plan.points.rawValue)
        var nights = all().filter { !($0.games == night.games && $0.picks == night.picks && $0.points == night.points) }
        nights.insert(night, at: 0)
        store(Array(nights.prefix(cap)))
        return night
    }

    static func delete(_ id: String) {
        store(all().filter { $0.id != id })
    }

    static func deleteAll() {
        store([])
    }

    /// "Herd, Trivia and 3 more".
    static func name(for plan: NightPlan) -> String {
        let names = plan.games.compactMap { $0.game?.displayName }
        guard let first = names.first else { return "Game Night" }
        if names.count == 1 { return first }
        let lead = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(lead) and \(names.count - 2) more" : lead
    }
}

extension NightPlan {
    /// The saved lineup as a plan, with each game's options from `catalog` (the
    /// picker's list of every game). Games this build or server no longer has are left out.
    static func restored(_ saved: SavedNight, from catalog: [PickedGame]) -> NightPlan {
        var plan = NightPlan()
        for id in saved.games {
            if let game = catalog.first(where: { $0.id == id }) {
                _ = plan.add(game)
            }
        }
        for game in plan.games {
            guard let chosen = saved.picks[game.id] else { continue }
            for option in game.options ?? [] {
                if let value = chosen[option.key] { plan.set(value, for: option, in: game) }
            }
        }
        plan.points = NightPoints(rawValue: saved.points) ?? .classic
        return plan
    }
}

/// The last party's settings, so a second party night does not start from blank.
struct LastParty: Codable, Equatable {
    var occasion: String
    var honoree: String
    var honoreeSaid: String
    var style: String
    var accent: String

    private static let defaultsKey = "aurora_last_party_v1"

    static func load() -> LastParty? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LastParty.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
