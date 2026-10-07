import SwiftUI
import UIKit

// MARK: - Teams mode and invites on the phone
//
// PhoneTeamsCard: everyone sees the teams; tap a team to switch to it
// (the server lets a phone move itself). HostTeamsControl: the host turns
// teams on (2-4), reshuffles, or switches them off. InviteShareButton:
// "play from anywhere" -- shares the room's /join/<code> link, which opens
// the app (or the web landing page) for friends who are not in the room.

enum TeamEvents {
    static func setTeams(roomCode: String, count: Int) {
        if count < 2 {
            GameSocketManager.shared.emit(.clearTeams, payload: RoomCodePayload(roomCode: roomCode))
        } else {
            GameSocketManager.shared.emit(.setTeams, payload: SetTeamsPayload(roomCode: roomCode, count: count))
        }
    }

    static func move(roomCode: String, playerID: String, teamID: String) {
        GameSocketManager.shared.emit(.moveToTeam,
                                      payload: MoveToTeamPayload(roomCode: roomCode,
                                                                 playerID: playerID,
                                                                 teamID: teamID))
    }
}

struct PhoneTeamsCard: View {
    let room: Room
    let teams: RoomTeams
    let myID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Teams", systemImage: "person.3.fill")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if let mine = teams.team(of: myID) {
                    Text("You're on \(mine.name)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(mine.tint)
                }
            }
            ForEach(teams.teams) { team in
                teamRow(team)
            }
            if room.state == .lobby {
                Text("Tap a team to switch")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .phonePlaySurfaceCard(tint: PhonePlayDesign.yellow)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: teams)
    }

    private func teamRow(_ team: TeamInfo) -> some View {
        let isMine: Bool = team.members.contains(myID)
        let names: [String] = team.members.compactMap { id in
            room.players.first(where: { $0.id == id })?.name
        }
        return Button {
            guard !isMine, room.state == .lobby else { return }
            PhonePlayHaptics.tap()
            TeamEvents.move(roomCode: room.code, playerID: myID, teamID: team.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(team.tint)
                    .frame(width: 14, height: 14)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(team.name)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        if team.points > 0 {
                            Text("\(team.points) pts")
                                .font(.caption.weight(.heavy))
                                .foregroundColor(team.tint)
                        }
                    }
                    Text(names.isEmpty ? "Nobody yet" : names.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius)
                    .fill(team.tint.opacity(isMine ? 0.22 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius)
                    .strokeBorder(team.tint.opacity(isMine ? 0.9 : 0.3), lineWidth: isMine ? 2 : 1)
            )
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

struct HostTeamsControl: View {
    let room: Room

    private var current: Int { room.teams?.teams.count ?? 0 }
    private var most: Int { min(4, room.players.count) }

    var body: some View {
        if room.players.count >= 2 {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.white.opacity(0.5))
                option(label: "Solo", count: 0)
                ForEach(2...4, id: \.self) { count in
                    if count <= most {
                        option(label: "\(count) teams", count: count)
                    }
                }
                if current > 0 {
                    Button {
                        TeamEvents.setTeams(roomCode: room.code, count: current)
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Shuffle teams")
                }
            }
        }
    }

    private func option(label: String, count: Int) -> some View {
        let selected: Bool = current == count
        return Button {
            guard !selected else { return }
            TeamEvents.setTeams(roomCode: room.code, count: count)
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(selected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(selected ? PhonePlayDesign.yellow : Color.white.opacity(0.08)))
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

/// Shares the room's join link so friends anywhere can jump in.
struct InviteShareButton: View {
    let room: Room

    private var link: URL {
        AppConstants.serverURL.appendingPathComponent("join").appendingPathComponent(room.code)
    }

    var body: some View {
        ShareLink(item: link,
                  subject: Text("Join my Aurora Play game"),
                  message: Text("Join my \(room.gameID.displayName) game on Aurora Play. Room code \(room.code).")) {
            Label("Invite", systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.cyan)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(PhonePlayDesign.cyan.opacity(0.12)))
        }
    }
}
