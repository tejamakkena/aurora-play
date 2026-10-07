import SwiftUI

// Game Night on the TV (server: games/game_night.py, which rides along in
// room_updated as Room.night). These pieces are shared by the home screen,
// the lobby and the results screen, all in the Shell 3D style.

// MARK: - Playlist

/// One playlist entry, keeping its position in the server's playlist so the
/// "current game" highlight stays right even if an id from a newer server is
/// unknown to this build (and skipped).
struct TVNightSlot: Identifiable, Equatable {
    let index: Int
    let game: GameID
    var id: Int { index }

    static func slots(from ids: [String]) -> [TVNightSlot] {
        var result: [TVNightSlot] = []
        for (offset, raw) in ids.enumerated() {
            if let game = GameID(rawValue: raw) {
                result.append(TVNightSlot(index: offset, game: game))
            }
        }
        return result
    }
}

enum TVNightTileStatus {
    case done
    case current
    case upcoming
}

/// A row of small 3D game tiles. `currentIndex` highlights the game being
/// played; earlier ones are ticked off, later ones wait. nil = a preview,
/// every tile shown as upcoming.
struct TVNightPlaylistStrip: View {
    let slots: [TVNightSlot]
    let currentIndex: Int?
    var tileSize: CGFloat = 60

    private func status(for slot: TVNightSlot) -> TVNightTileStatus {
        guard let currentIndex else { return .upcoming }
        if slot.index < currentIndex { return .done }
        if slot.index == currentIndex { return .current }
        return .upcoming
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(slots) { slot in
                TVNightGameTile(game: slot.game, status: status(for: slot), size: tileSize)
                    .frame(width: tileSize + 12)
            }
        }
    }
}

struct TVNightGameTile: View {
    let game: GameID
    let status: TVNightTileStatus
    var size: CGFloat = 60

    private var style: TVCategoryStyle { game.category.tvStyle }
    private var isCurrent: Bool { status == .current }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 8) {
            tile
                .scaleEffect(isCurrent ? 1.12 : 1.0)
                .phaseAnimator([false, true]) { content, phase in
                    content.offset(y: (isCurrent && phase) ? -5 : 0)
                } animation: { _ in
                    Animation.easeInOut(duration: 1.0)
                }

            Text(game.displayName)
                .font(.system(size: 14, weight: isCurrent ? .bold : .medium, design: .rounded))
                .foregroundColor(isCurrent ? Color.white : Color.white.opacity(status == .done ? 0.4 : 0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.displayName)
    }

    private var tile: some View {
        ZStack {
            shape
                .fill(style.bottom)
                .overlay { shape.fill(Color.black.opacity(0.5)) }
                .offset(y: size * 0.08)
            shape
                .fill(LinearGradient(colors: [style.top, style.bottom],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .opacity(status == .upcoming ? 0.7 : (status == .done ? 0.35 : 1.0))
            shape
                .fill(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0)],
                                     startPoint: .top,
                                     endPoint: .center))
            shape
                .strokeBorder(Color.white.opacity(isCurrent ? 0.9 : 0.3), lineWidth: isCurrent ? 2.5 : 1)
            Image(systemName: status == .done ? "checkmark" : game.sfSymbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(Color.white.opacity(status == .done ? 0.8 : 1.0))
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 2)
        }
        .frame(width: size, height: size)
        .shellShine(isActive: isCurrent, cornerRadius: size * 0.26, period: 2.6, intensity: 0.4)
        .compositingGroup()
        .shadow(color: style.accent.opacity(isCurrent ? 0.8 : 0), radius: 16)
        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 6)
    }
}

// MARK: - Standings

/// Compact night standings: rank, player-coloured token, name, points.
struct TVNightStandingsMini: View {
    let standings: [NightStanding]
    var maxRows: Int = 4

    private var shown: [NightStanding] { Array(standings.prefix(max(0, maxRows))) }
    private var hiddenCount: Int { max(0, standings.count - shown.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if standings.isEmpty {
                Text("Standings appear after the first game")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
            } else {
                ForEach(shown) { standing in
                    HStack(spacing: 14) {
                        Text("\(standing.rank)")
                            .font(ShellTheme.display(20, weight: .heavy))
                            .foregroundColor(standing.rank == 1 ? ShellTheme.gold : ShellTheme.textSecondary)
                            .frame(width: 28)
                        ShellAvatarToken(id: standing.playerID,
                                         name: standing.name,
                                         size: 36,
                                         isBot: standing.isBot ?? false)
                        Text(standing.name)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(standing.points) pts")
                            .font(ShellTheme.display(21, weight: .bold))
                            .foregroundColor(ShellTheme.avatarColor(for: standing.playerID))
                    }
                }
                if hiddenCount > 0 {
                    Text("and \(hiddenCount) more")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(ShellTheme.textTertiary)
                        .padding(.leading, 42)
                }
            }
        }
    }
}

/// Full-size night standings for the results screen. Each total counts up
/// from where it stood before this game, with the points just earned
/// popping in as a "+N" badge and the bar growing to match.
struct TVNightStandingsBoard: View {
    let standings: [NightStanding]
    let totalsBefore: [String: Int]

    @State private var isRevealed: Bool = false

    /// Up to 5 full rows fit under the results header; more switch to two
    /// compact columns, capped so a 20-player room never overflows.
    private static let maxVisible: Int = 14
    private var isCompact: Bool { standings.count > 5 }
    private var visible: [NightStanding] { Array(standings.prefix(Self.maxVisible)) }
    private var hiddenCount: Int { max(0, standings.count - visible.count) }

    private var maxPoints: Int {
        max(1, standings.map { $0.points }.max() ?? 1)
    }

    private var columns: [GridItem] {
        if isCompact {
            return [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
        }
        return [GridItem(.flexible(), spacing: 16)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if standings.isEmpty {
                Text("No night points yet")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: isCompact ? 10 : 14) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, standing in
                    TVNightStandingRow(standing: standing,
                                       before: totalsBefore[standing.playerID] ?? 0,
                                       maxPoints: maxPoints,
                                       isRevealed: isRevealed,
                                       isCompact: isCompact,
                                       delay: Double(min(index, 10)) * 0.08)
                }
            }
            if hiddenCount > 0 {
                Text("and \(hiddenCount) more")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textTertiary)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                isRevealed = true
            }
        }
    }
}

private struct TVNightStandingRow: View {
    let standing: NightStanding
    let before: Int
    let maxPoints: Int
    let isRevealed: Bool
    let isCompact: Bool
    let delay: Double

    private var gained: Int { max(0, standing.points - before) }
    private var shownPoints: Int { isRevealed ? standing.points : min(before, standing.points) }
    private var color: Color { ShellTheme.avatarColor(for: standing.playerID) }

    private var fraction: CGFloat {
        let value: Double = Double(shownPoints) / Double(max(1, maxPoints))
        return CGFloat(min(1.0, max(0.0, value)))
    }

    var body: some View {
        HStack(spacing: isCompact ? 12 : 18) {
            Text("\(standing.rank)")
                .font(ShellTheme.display(isCompact ? 22 : 28, weight: .heavy))
                .foregroundColor(standing.rank == 1 ? ShellTheme.gold : ShellTheme.textSecondary)
                .frame(width: isCompact ? 30 : 40)

            ShellAvatarToken(id: standing.playerID,
                             name: standing.name,
                             size: isCompact ? 42 : 56,
                             isBot: standing.isBot ?? false)

            VStack(alignment: .leading, spacing: 6) {
                Text(standing.name)
                    .font(.system(size: isCompact ? 21 : 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !isCompact {
                    bar
                }
            }

            Spacer(minLength: 8)

            if gained > 0 {
                Text("+\(gained)")
                    .font(ShellTheme.display(isCompact ? 18 : 22, weight: .heavy))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background { Capsule().fill(ShellTheme.mint) }
                    .scaleEffect(isRevealed ? 1.0 : 0.2)
                    .opacity(isRevealed ? 1.0 : 0.0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(delay + 0.2),
                               value: isRevealed)
            }

            Text("\(shownPoints)")
                .font(ShellTheme.display(isCompact ? 24 : 32, weight: .heavy))
                .foregroundColor(color)
                .contentTransition(.numericText(value: Double(shownPoints)))
                .frame(minWidth: isCompact ? 44 : 60, alignment: .trailing)
                .animation(.easeOut(duration: 0.9).delay(delay), value: isRevealed)
        }
        .padding(.horizontal, isCompact ? 14 : 22)
        .padding(.vertical, isCompact ? 8 : 12)
        .background {
            ShellGlassSurface(cornerRadius: isCompact ? 18 : 24, tint: color)
        }
    }

    private var bar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(width: 300, height: 10)
            Capsule()
                .fill(LinearGradient(colors: [color.opacity(0.7), color],
                                     startPoint: .leading,
                                     endPoint: .trailing))
                .frame(width: max(10, 300 * fraction), height: 10)
                .shadow(color: color.opacity(0.6), radius: 6)
                .animation(.easeOut(duration: 0.9).delay(delay), value: isRevealed)
        }
    }
}

// MARK: - Home screen card

/// The home screen's Game Night entry: a glowing 3D card that lifts and
/// shines on focus. Drawn by its ButtonStyle so it reads focus from the
/// environment, like the other shell buttons.
struct TVGameNightCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVGameNightCardBody(configuration: configuration)
    }
}

private struct TVGameNightCardBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isFocused) private var isFocused: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .offset(y: 4)
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "FDE68A"), Color(hex: "F59E0B")],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(hex: "3B1C7A"))
            }
            .frame(width: 56, height: 56)
            .rotation3DEffect(.degrees(isFocused ? 14 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)

            configuration.label
                .foregroundColor(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            ZStack {
                shape
                    .fill(Color(hex: "3B1C7A"))
                    .offset(y: 7)
                shape
                    .fill(LinearGradient(colors: [Color(hex: "7C3AED"), Color(hex: "DB2777")],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                shape
                    .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                         startPoint: .top,
                                         endPoint: .center))
                shape
                    .strokeBorder(Color.white.opacity(isFocused ? 0.9 : 0.35), lineWidth: isFocused ? 2.5 : 1.2)
            }
        }
        .shellShine(isActive: isFocused, cornerRadius: ShellTheme.cardRadius, period: 2.6, intensity: 0.45)
        .compositingGroup()
        .shadow(color: ShellTheme.pink.opacity(isFocused ? 0.7 : 0.3), radius: isFocused ? 28 : 12)
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
        .rotation3DEffect(.degrees(isFocused ? 6 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1.0))
        .animation(.spring(response: 0.3, dampingFraction: 0.66), value: isFocused)
    }
}

// MARK: - Lobby: setup

/// Shown in a Game Night room's lobby before the night starts: kids mode,
/// length, and a preview of the lineup from the server's picker
/// (OneStopAPI.pick). "Start the night" sends exactly the previewed lineup,
/// so what is on screen is what gets played; if the preview could not load
/// (offline, older server) it sends none and the server builds one.
struct TVNightSetupPanel: View {
    let playerCount: Int
    let focusNamespace: Namespace.ID
    let onStart: (_ minutes: Int, _ kids: Bool, _ playlist: [String]) -> Void

    @State private var kids: Bool = false
    @State private var minutes: Int = 45
    @State private var preview: [PickedGame] = []
    @State private var isLoading: Bool = false

    private static let lengths: [Int] = [30, 45, 60]
    private static let maxGames: Int = 8

    /// Picker suggestions need at least a duel's worth of players.
    private var pickerPlayers: Int { max(2, playerCount) }

    private var previewKey: String { "\(pickerPlayers)-\(kids)-\(minutes)" }

    private var previewSlots: [TVNightSlot] {
        TVNightSlot.slots(from: preview.map { $0.id })
    }

    var body: some View {
        ShellGlassCard(cornerRadius: ShellTheme.cardRadius, tint: ShellTheme.pink, padding: 26) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(ShellTheme.gold)
                    Text("GAME NIGHT")
                        .font(ShellTheme.eyebrow(22))
                        .tracking(5)
                        .foregroundColor(.white)
                    Text("a playlist, one scoreboard")
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundColor(ShellTheme.textTertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    ForEach(Self.lengths, id: \.self) { length in
                        Button {
                            minutes = length
                        } label: {
                            Text("\(length) min")
                        }
                        .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.cyan, isSelected: minutes == length))
                    }
                    Spacer(minLength: 8)
                    Button {
                        kids.toggle()
                    } label: {
                        Label(kids ? "Kids learning: On" : "Kids learning: Off",
                              systemImage: kids ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.mint, isSelected: kids))
                }

                previewSection
                    .frame(height: 96, alignment: .topLeading)

                Button {
                    onStart(minutes, kids, preview.map { $0.id })
                } label: {
                    Label("Start the night", systemImage: "sparkles")
                }
                .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.pink))
                .prefersDefaultFocus(true, in: focusNamespace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: previewKey) {
            await loadPreview()
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if isLoading && preview.isEmpty {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(ShellTheme.cyan)
                Text("Picking games for \(pickerPlayers) players…")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textSecondary)
            }
        } else if previewSlots.isEmpty {
            Text("The server will pick the games when the night starts")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.textTertiary)
        } else {
            TVNightPlaylistStrip(slots: previewSlots, currentIndex: nil, tileSize: 58)
                .opacity(isLoading ? 0.5 : 1.0)
        }
    }

    private func loadPreview() async {
        isLoading = true
        let picked: [PickedGame] = await OneStopAPI.pick(players: pickerPlayers, kids: kids, minutes: minutes)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            preview = Self.lineup(from: picked, totalMinutes: minutes)
        }
        isLoading = false
    }

    /// The picker's best-first list trimmed to roughly the night's length.
    static func lineup(from picked: [PickedGame], totalMinutes: Int) -> [PickedGame] {
        var result: [PickedGame] = []
        var spent: Int = 0
        for game in picked {
            if spent >= totalMinutes || result.count >= maxGames { break }
            if game.game == nil { continue }
            result.append(game)
            spent += max(1, game.minutes)
        }
        return result
    }
}

// MARK: - Lobby: night in progress

/// Shown in the lobby while a night runs: where we are in the playlist and
/// the scoreboard so far.
struct TVNightLobbyPanel: View {
    let night: GameNight

    private var slots: [TVNightSlot] { TVNightSlot.slots(from: night.playlist) }

    private var progressText: String {
        let total: Int = night.playlist.count
        let number: Int = min(total, night.index + 1)
        return "Game \(number) of \(total)"
    }

    var body: some View {
        ShellGlassCard(cornerRadius: ShellTheme.cardRadius, tint: ShellTheme.pink, padding: 26) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(ShellTheme.gold)
                    Text("GAME NIGHT")
                        .font(ShellTheme.eyebrow(22))
                        .tracking(5)
                        .foregroundColor(.white)
                    Spacer(minLength: 8)
                    Text(progressText)
                        .font(ShellTheme.display(22, weight: .bold))
                        .foregroundColor(ShellTheme.cyan)
                }

                TVNightPlaylistStrip(slots: slots, currentIndex: night.index, tileSize: 58)
                    .frame(height: 96, alignment: .topLeading)

                TVNightStandingsMini(standings: night.standings, maxRows: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
