import Foundation

// MARK: - The house leaderboard
//
// Who has played on THIS Apple TV, signed in with Game Center on their phone,
// and what they have won. It is kept on the TV itself: the phone sends a short
// hash of its Game Center player (`Player.gcID`) when it joins, and the TV
// folds every finished game and Game Night into this table. No server is
// involved, so it survives a server restart, costs nothing, and never leaves
// the living room.
//
// Pure Foundation on purpose (no UIKit, no GameKit): it compiles in the shared
// package on any platform.

/// One player on the house leaderboard.
struct HousePlayer: Codable, Equatable, Identifiable {
    /// The hashed Game Center id the phone sent (`Player.gcID`).
    let id: String
    var name: String
    var games: Int = 0
    var wins: Int = 0
    var podiums: Int = 0
    var nights: Int = 0
    var nightWins: Int = 0
    /// House points: see `HouseBoardData.points(forRank:)`.
    var points: Int = 0
    /// Games played, by game id, for the "favourite game" line.
    var byGame: [String: Int] = [:]
    /// Seconds since 1970 of the last finished game.
    var lastPlayed: Double = 0

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    // Written out so a board saved by an older build (fewer fields) still decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Player"
        games = try c.decodeIfPresent(Int.self, forKey: .games) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        podiums = try c.decodeIfPresent(Int.self, forKey: .podiums) ?? 0
        nights = try c.decodeIfPresent(Int.self, forKey: .nights) ?? 0
        nightWins = try c.decodeIfPresent(Int.self, forKey: .nightWins) ?? 0
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
        byGame = try c.decodeIfPresent([String: Int].self, forKey: .byGame) ?? [:]
        lastPlayed = try c.decodeIfPresent(Double.self, forKey: .lastPlayed) ?? 0
    }

    /// The game this player has played most (ties: the first by id), if any.
    var favouriteGame: String? {
        byGame.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        })?.key
    }
}

/// Everything the board remembers. A value type so recording a game is a plain
/// function of (board, room) that can be reasoned about on its own.
struct HouseBoardData: Codable, Equatable {
    var players: [String: HousePlayer] = [:]
    /// Games finished on this TV since the board started.
    var games: Int = 0
    /// Seats filled by people who were not signed in to Game Center. They are
    /// counted, not ranked, so the board can say how many were left out.
    var guestSeats: Int = 0
    /// Recent finished games and nights already counted, so the same results
    /// screen arriving twice (a reconnect, a repeated room_updated) counts once.
    var seen: [String] = []

    private static let seenLimit = 40

    /// 10 for the win, 6 for second, 4 for third, 2 for taking part. Chosen so
    /// a lucky win beats a lot of showing up, but showing up still adds up.
    static func points(forRank rank: Int) -> Int {
        switch rank {
        case 1: return 10
        case 2: return 6
        case 3: return 4
        default: return 2
        }
    }

    /// Ranked best first: points, then wins, then games, then name.
    var ranked: [HousePlayer] {
        players.values.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.wins != b.wins { return a.wins > b.wins }
            if a.games != b.games { return a.games > b.games }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var isEmpty: Bool { players.isEmpty }

    private mutating func claim(_ token: String) -> Bool {
        if seen.contains(token) { return false }
        seen.append(token)
        if seen.count > Self.seenLimit { seen.removeFirst(seen.count - Self.seenLimit) }
        return true
    }

    /// Folds a finished game into the board. Returns true when something
    /// changed (false for a room that is not at results, one already counted,
    /// or a game with no human players).
    @discardableResult
    mutating func recordGame(_ room: Room, now: Date = Date()) -> Bool {
        guard room.state == .results else { return false }
        let ranking = room.finalRanking
        let humans = ranking.filter { (row: RoomResult) -> Bool in
            guard let player = room.players.first(where: { $0.id == row.playerID }) else { return false }
            return !player.isBot
        }
        guard !humans.isEmpty else { return false }

        let scores = humans.map { "\($0.playerID):\($0.score)" }.joined(separator: ",")
        let token = "g|\(room.code)|\(room.gameID.rawValue)|\(room.night?.gamesPlayed ?? 0)|\(scores)"
        guard claim(token) else { return false }

        games += 1
        for row in humans {
            guard let player = room.players.first(where: { $0.id == row.playerID }) else { continue }
            guard let gc = player.gcID, !gc.isEmpty else {
                guestSeats += 1
                continue
            }
            var entry = players[gc] ?? HousePlayer(id: gc, name: player.name)
            entry.name = player.name
            entry.games += 1
            if row.rank == 1 { entry.wins += 1 }
            if row.rank <= 3 { entry.podiums += 1 }
            entry.points += Self.points(forRank: row.rank)
            entry.byGame[room.gameID.rawValue, default: 0] += 1
            entry.lastPlayed = now.timeIntervalSince1970
            players[gc] = entry
        }
        return true
    }

    /// Folds a finished Game Night into the board: a night played for everyone
    /// on the standings, a night won for the champion. (The games inside the
    /// night were already counted one by one by `recordGame`.)
    @discardableResult
    mutating func recordNight(_ room: Room) -> Bool {
        guard let night = room.night, night.finished, !night.standings.isEmpty else { return false }
        let token = "n|\(room.code)|\(night.playlist.joined(separator: ","))|\(night.gamesPlayed)"
        guard claim(token) else { return false }

        var changed = false
        for standing in night.standings where standing.isBot != true {
            guard let player = room.players.first(where: { $0.id == standing.playerID }),
                  let gc = player.gcID, !gc.isEmpty else { continue }
            var entry = players[gc] ?? HousePlayer(id: gc, name: player.name)
            entry.name = player.name
            entry.nights += 1
            if standing.rank == 1 { entry.nightWins += 1 }
            players[gc] = entry
            changed = true
        }
        return changed
    }
}

/// Where the board lives on the TV, and the one call the TV makes.
enum HouseBoardStore {
    static let key = "aurora_house_board_v1"

    static func load(_ defaults: UserDefaults = .standard) -> HouseBoardData {
        guard let data = defaults.data(forKey: key),
              let board = try? JSONDecoder().decode(HouseBoardData.self, from: data) else {
            return HouseBoardData()
        }
        return board
    }

    static func save(_ board: HouseBoardData, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(board) {
            defaults.set(data, forKey: key)
        }
    }

    /// Counts a results screen. Cheap and idempotent: safe to call on every
    /// room_updated while the room is at results.
    static func record(_ room: Room, _ defaults: UserDefaults = .standard) {
        guard room.state == .results else { return }
        var board = load(defaults)
        let game = board.recordGame(room)
        let night = board.recordNight(room)
        if game || night { save(board, defaults) }
    }

    static func reset(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
