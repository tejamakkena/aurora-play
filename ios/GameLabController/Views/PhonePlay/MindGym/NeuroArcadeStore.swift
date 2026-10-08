import Foundation

// MARK: - Arcade storage
//
// What the phone remembers about the arcade, in UserDefaults as plain JSON:
//
//   stats    per game: plays, best score, last score and the date of the last
//            run that counted towards the rating
//   pending  rated runs that could not be posted yet, replayed later
//
// Like the rest of the Mind Gym nothing here throws: a missing or corrupt
// value reads as "never played".

struct NeuroArcadeStats: Equatable {
    var plays: Int = 0
    var best: Double = 0
    var last: Double = 0
    /// The day (YYYY-MM-DD) of the last run that counted towards the rating.
    var ratedDate: String = ""

    init() {}

    init(json: [String: Any]) {
        plays = NeuroJSON.int(json["plays"])
        best = (json["best"] as? Double) ?? Double(NeuroJSON.int(json["best"]))
        last = (json["last"] as? Double) ?? Double(NeuroJSON.int(json["last"]))
        ratedDate = NeuroJSON.string(json["ratedDate"])
    }

    var json: [String: Any] {
        ["plays": plays, "best": best, "last": last, "ratedDate": ratedDate]
    }
}

/// What the server said about a run it rated.
struct NeuroArcadeOutcome: Equatable {
    let rated: Bool
    let alreadyRated: Bool
    let discipline: String
    let before: Int
    let after: Int
    let delta: Int

    init(json: [String: Any]) {
        rated = NeuroJSON.bool(json["rated"])
        alreadyRated = NeuroJSON.bool(json["alreadyRated"])
        discipline = NeuroJSON.string(json["discipline"])
        before = NeuroJSON.int(json["before"])
        after = NeuroJSON.int(json["after"])
        delta = NeuroJSON.int(json["delta"])
    }
}

enum NeuroArcadeStore {
    private static let statsKey = "neuro_arcade_stats_json"
    private static let pendingKey = "neuro_arcade_pending_results"

    // MARK: Stats

    private static func allStats() -> [String: Any] {
        NeuroJSON.dict(UserDefaults.standard.data(forKey: statsKey)) ?? [:]
    }

    static func stats(_ game: NeuroArcadeGame) -> NeuroArcadeStats {
        guard let raw = allStats()[game.rawValue] as? [String: Any] else { return NeuroArcadeStats() }
        return NeuroArcadeStats(json: raw)
    }

    /// True once today's counting run of this game has been played. The
    /// server enforces the same rule, so this only decides what the screen
    /// says before the run starts.
    static func ratedToday(_ game: NeuroArcadeGame) -> Bool {
        stats(game).ratedDate == NeuroStore.todayKey()
    }

    static func record(_ game: NeuroArcadeGame, score: Double, rated: Bool) {
        var all = allStats()
        var mine = stats(game)
        mine.plays += 1
        mine.best = max(mine.best, score)
        mine.last = score
        if rated { mine.ratedDate = NeuroStore.todayKey() }
        all[game.rawValue] = mine.json
        if let data = NeuroJSON.data(all) {
            UserDefaults.standard.set(data, forKey: statsKey)
        }
    }

    /// The level to pitch a run at: the discipline's level from the last
    /// profile the server sent, or the starting rating's level.
    static func level(for game: NeuroArcadeGame) -> Int {
        if let profile = NeuroStore.profile() {
            return profile.level(game.discipline)
        }
        return NeuroScoring.level(forRating: Double(NeuroScoring.startRating))
    }

    // MARK: Runs waiting to be posted

    static func pending() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let object = try? JSONSerialization.jsonObject(with: data),
              let list = object as? [Any] else { return [] }
        return list.compactMap { $0 as? [String: Any] }
    }

    static func queue(_ body: [String: Any]) {
        var all = pending()
        // One entry per game per date: the server only rates the first.
        let game = NeuroJSON.string(body["game"])
        let date = NeuroJSON.string(body["date"])
        all.removeAll { NeuroJSON.string($0["game"]) == game && NeuroJSON.string($0["date"]) == date }
        all.append(body)
        if all.count > 14 { all = Array(all.suffix(14)) }
        savePending(all)
    }

    static func savePending(_ bodies: [[String: Any]]) {
        guard JSONSerialization.isValidJSONObject(bodies),
              let data = try? JSONSerialization.data(withJSONObject: bodies) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }
}
