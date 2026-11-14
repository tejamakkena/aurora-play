import SwiftUI

// MARK: - The house leaderboard on the TV
//
// Who has played on this Apple TV signed in with Game Center on their phone,
// with their games, wins and points. The numbers come from HouseBoardStore
// (Shared/Models/HouseBoard.swift), which the TV fills in as games finish; it
// is kept on the TV, so it needs no server and survives one restarting.

struct TVHouseBoardView: View {
    let onDone: () -> Void

    @State private var board = HouseBoardStore.load()
    @State private var confirmReset = false

    private static let rowLimit = 10

    private var rows: [HousePlayer] { Array(board.ranked.prefix(Self.rowLimit)) }
    private var nights: Int { board.players.values.reduce(0) { $0 + $1.nights } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .center) {
                    Text("HOUSE LEADERBOARD")
                        .font(ShellTheme.eyebrow(28))
                        .tracking(6)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onDone) {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.pink))
                    .accessibilityIdentifier("houseBoardDone")
                }

                if board.isEmpty {
                    emptyState
                } else {
                    summary
                    VStack(spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                            row(rank: index + 1, player: player)
                        }
                    }
                    footnote
                    resetButton
                }
            }
            .padding(70)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black.opacity(0.92).ignoresSafeArea())
    }

    // MARK: Pieces

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(ShellTheme.gold)
            Text("No one on the board yet")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text("Players who sign in to Game Center on their phone appear here after their first game, with their games, wins and points. Everyone else can still play, they just are not ranked.")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
            .fill(Color.white.opacity(0.06)))
    }

    private var summary: some View {
        HStack(spacing: 20) {
            stat("\(board.players.count)", board.players.count == 1 ? "player" : "players", ShellTheme.cyan)
            stat("\(board.games)", board.games == 1 ? "game played" : "games played", ShellTheme.violet)
            stat("\(nights)", nights == 1 ? "night played" : "nights played", ShellTheme.gold)
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(tint)
            Text(label.uppercased())
                .font(ShellTheme.eyebrow(18))
                .tracking(4)
                .foregroundColor(ShellTheme.textTertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
            .fill(Color.white.opacity(0.06)))
    }

    private func row(rank: Int, player: HousePlayer) -> some View {
        HStack(spacing: 24) {
            Text("\(rank)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(rank == 1 ? ShellTheme.gold : ShellTheme.textSecondary)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if let favourite = favouriteName(player) {
                    Text("Loves \(favourite)")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(ShellTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            figure("\(player.games)", "played")
            figure("\(player.wins)", "wins")
            figure("\(player.nightWins)", "night wins")
            figure("\(player.points)", "points", tint: ShellTheme.gold)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
            .fill(Color.white.opacity(rank == 1 ? 0.10 : 0.06)))
    }

    private func figure(_ value: String, _ label: String, tint: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
            Text(label.uppercased())
                .font(ShellTheme.eyebrow(15))
                .tracking(3)
                .foregroundColor(ShellTheme.textTertiary)
        }
        .frame(minWidth: 96)
    }

    private func favouriteName(_ player: HousePlayer) -> String? {
        guard let id = player.favouriteGame, player.games >= 2 else { return nil }
        return GameID(rawValue: id)?.displayName
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Points: 10 for a win, 6 for second, 4 for third, 2 for playing. Only players signed in to Game Center on their phone are ranked.")
            if board.guestSeats > 0 {
                Text("\(board.guestSeats) seats so far were played by people who were not signed in.")
            }
        }
        .font(.system(size: 21, weight: .medium, design: .rounded))
        .foregroundColor(ShellTheme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var resetButton: some View {
        Button {
            if confirmReset {
                HouseBoardStore.reset()
                board = HouseBoardStore.load()
                confirmReset = false
            } else {
                confirmReset = true
            }
        } label: {
            Label(confirmReset ? "Press again to clear the board" : "Clear the board",
                  systemImage: confirmReset ? "exclamationmark.triangle.fill" : "arrow.counterclockwise")
        }
        .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.pink, isSelected: confirmReset))
        .accessibilityIdentifier("houseBoardReset")
    }
}
