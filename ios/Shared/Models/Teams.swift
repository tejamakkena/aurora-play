import SwiftUI

// MARK: - Teams mode (games/teams.py)
//
// 2-4 named teams that score together. After each game the teams are
// ranked by their best-placed member and get 10 / 7 / 5 / 3 team points.
// The teams ride along in room_updated as `teams`; nil when everyone
// plays for themselves.

struct RoomTeams: Codable, Equatable {
    var teams: [TeamInfo]

    func team(of playerID: String) -> TeamInfo? {
        teams.first { $0.members.contains(playerID) }
    }

    /// Highest points first.
    var ranked: [TeamInfo] {
        teams.sorted { $0.points > $1.points }
    }
}

struct TeamInfo: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var color: String
    var members: [String]
    var points: Int
    /// Team points from the last finished game; nil before any game.
    var lastGained: Int?
    var rank: Int?

    var tint: Color { TeamPalette.color(named: color) }
}

enum TeamPalette {
    static func color(named name: String) -> Color {
        switch name {
        case "red":    return Color(red: 1.00, green: 0.33, blue: 0.40)
        case "blue":   return Color(red: 0.30, green: 0.58, blue: 1.00)
        case "green":  return Color(red: 0.28, green: 0.86, blue: 0.52)
        case "yellow": return Color(red: 1.00, green: 0.80, blue: 0.25)
        default:       return Color(red: 0.70, green: 0.55, blue: 1.00)
        }
    }
}

struct SetTeamsPayload: Encodable {
    let roomCode: String
    let count: Int
}

struct MoveToTeamPayload: Encodable {
    let roomCode: String
    let playerID: String
    let teamID: String
}
