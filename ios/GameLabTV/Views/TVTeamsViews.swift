import SwiftUI

// MARK: - Teams mode on the TV
//
// The lobby roster becomes one column per team (TVTeamsRoster), and the
// results screen gets a team scoreboard (TVTeamScoreStrip) with the team
// points from the game just played. Data: Room.teams (games/teams.py).

/// The lobby roster in teams mode: a column per team.
struct TVTeamsRoster: View {
    let teams: RoomTeams
    let players: [Player]

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(teams.teams) { team in
                TVTeamColumn(team: team, players: players)
            }
        }
    }
}

private struct TVTeamColumn: View {
    let team: TeamInfo
    let players: [Player]

    private var members: [Player] {
        team.members.compactMap { id in players.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(team.tint)
                    .frame(width: 18, height: 18)
                    .shadow(color: team.tint.opacity(0.8), radius: 8)
                Text(team.name)
                    .font(ShellTheme.display(26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                if team.points > 0 {
                    Text("\(team.points)")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(team.tint)
                }
            }
            ForEach(members) { player in
                HStack(spacing: 10) {
                    Image(systemName: player.isBot ? "cpu" : "person.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(team.tint.opacity(0.9))
                    Text(player.name)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .transition(.scale.combined(with: .opacity))
            }
            if members.isEmpty {
                Text("Nobody yet")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(team.tint.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .strokeBorder(team.tint.opacity(0.55), lineWidth: 2)
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: team.members)
    }
}

/// Team totals on the results screen, best first, with "+N" for the game
/// just played.
struct TVTeamScoreStrip: View {
    let teams: RoomTeams
    var isShown: Bool = true

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(ShellTheme.gold)
            ForEach(Array(teams.ranked.enumerated()), id: \.element.id) { index, team in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.black.opacity(0.75))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(team.tint))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.name)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text("\(team.points) pts")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(team.tint)
                            if let gained = team.lastGained, gained > 0 {
                                Text("+\(gained)")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundColor(.black.opacity(0.8))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(team.tint))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(team.tint.opacity(index == 0 ? 0.22 : 0.12))
                )
                .overlay(
                    Capsule().strokeBorder(team.tint.opacity(index == 0 ? 0.8 : 0.35), lineWidth: 2)
                )
                .scaleEffect(isShown ? 1 : 0.85)
                .opacity(isShown ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.12),
                           value: isShown)
            }
        }
    }
}
