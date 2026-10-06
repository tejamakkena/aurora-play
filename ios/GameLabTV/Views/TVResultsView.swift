import SwiftUI

// Lives in the TV target (it used to sit in Shared/Views/ResultsView.swift):
// only RootTVView shows it, and its 3D shell styling uses the TV-only
// ShellTheme kit in Views/Theme/TVShellTheme.swift.

/// One name on the podium or the ranking list: a player's score for this
/// game, or (on the Game Night champion screen) their night total.
struct TVResultsEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    let isBot: Bool

    init(player: Player) {
        id = player.id
        name = player.name
        score = player.score
        isBot = player.isBot
    }

    init(standing: NightStanding) {
        id = standing.playerID
        name = standing.name
        score = standing.points
        isBot = standing.isBot ?? false
    }
}

/// End-of-game results: a 3D podium whose blocks rise in sequence (3rd, 2nd,
/// then 1st with a confetti burst), the rest of the ranking sliding in as
/// cards, and Play Again / Back to Games.
///
/// During a Game Night (room.night) the podium is followed by the night's
/// standings, totals counting up by the points just earned, and the main
/// button moves the room to the next game. When the night is finished the
/// whole screen becomes the Champion screen: the night's podium, everyone's
/// total, confetti, and End night.
struct TVResultsView: View {
    let room: Room
    let onPlayAgain: () -> Void
    let onBackToGames: () -> Void
    /// Night totals from before this game (TVRootViewModel's snapshot), for
    /// the "+N" animation. Empty outside a night.
    var nightTotalsBefore: [String: Int] = [:]
    var onNextGame: (() -> Void)? = nil
    var onEndNight: (() -> Void)? = nil

    /// Reveal sequence: 0 nothing, 1 third place, 2 second, 3 first +
    /// confetti, 4 the rest of the ranking, 5 (night games only) the night
    /// standings.
    @State private var stage: Int = 0
    /// Bumped to replay the reveal (when the champion screen takes over).
    @State private var revealRun: Int = 0
    @Namespace private var resultsFocus

    private var isChampion: Bool { room.night?.finished ?? false }
    private var isNightGame: Bool { room.night != nil && !isChampion }

    private var entries: [TVResultsEntry] {
        if isChampion, let night = room.night {
            return night.standings
                .sorted { $0.points > $1.points }
                .map { TVResultsEntry(standing: $0) }
        }
        return room.players
            .sorted { $0.score > $1.score }
            .map { TVResultsEntry(player: $0) }
    }

    private var podiumEntries: [TVResultsEntry] { Array(entries.prefix(3)) }
    private var restEntries: [TVResultsEntry] { Array(entries.dropFirst(3)) }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                header

                if let teams = room.teams {
                    TVTeamScoreStrip(teams: teams, isShown: stage >= 3)
                }

                middle
                    .frame(maxHeight: .infinity)

                actionButtons
            }
            // Small outer padding: tvOS adds its own overscan safe area.
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .padding(.bottom, 20)

            if stage >= 3 && !entries.isEmpty {
                ShellConfetti(particleCount: isChampion ? 220 : 160,
                              duration: isChampion ? 7.0 : 5.5,
                              origin: UnitPoint(x: restEntries.isEmpty ? 0.5 : 0.34, y: 0.42))
                    .id(isChampion)
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusScope(resultsFocus)
        .onChange(of: isChampion) { _, nowChampion in
            // The last night game's "Crown the champion" lands on this same
            // screen: replay the reveal for the night's podium.
            if nowChampion {
                stage = 0
                revealRun += 1
            }
        }
        .task(id: revealRun) { await runReveal() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Text(eyebrowText)
                .font(ShellTheme.eyebrow(24))
                .tracking(8)
                .foregroundColor(isChampion ? ShellTheme.gold : ShellTheme.textSecondary)
            Text(winnerLine)
                .font(ShellTheme.display(64, weight: .black))
                .foregroundStyle(LinearGradient(colors: [Color.white, ShellTheme.gold],
                                                startPoint: .top,
                                                endPoint: .bottom))
                .shadow(color: ShellTheme.gold.opacity(0.4), radius: 20)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .opacity(stage >= 3 ? 1 : 0)
                .scaleEffect(stage >= 3 ? 1 : 0.8)
            Text(subtitleText)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.textTertiary)
        }
    }

    private var eyebrowText: String {
        if isChampion { return "GAME NIGHT CHAMPION" }
        if let night = room.night {
            let total: Int = night.playlist.count
            let number: Int = min(total, night.index + 1)
            return "GAME NIGHT  ·  GAME \(number) OF \(total)"
        }
        return "FINAL RESULTS"
    }

    private var subtitleText: String {
        if isChampion, let night = room.night {
            return night.gamesPlayed == 1 ? "1 game played" : "\(night.gamesPlayed) games played"
        }
        return room.gameID.displayName
    }

    private var winnerLine: String {
        guard let winner = entries.first else {
            return isChampion ? "Night over" : "Game over"
        }
        if entries.count > 1, entries[1].score == winner.score {
            return "It's a tie!"
        }
        return isChampion ? "\(winner.name) wins the night!" : "\(winner.name) wins!"
    }

    // MARK: Middle

    @ViewBuilder
    private var middle: some View {
        if isNightGame && stage >= 5, let night = room.night {
            nightBoard(night)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
        } else {
            HStack(alignment: .bottom, spacing: 56) {
                ResultsPodium(entries: podiumEntries, stage: stage)
                    .frame(maxWidth: .infinity)

                if !restEntries.isEmpty {
                    ResultsRankingList(title: isChampion ? "EVERYONE TONIGHT" : "LEADERBOARD",
                                       entries: restEntries,
                                       startRank: 4,
                                       isShown: stage >= 4)
                        .frame(width: 620)
                }
            }
            .transition(.opacity)
        }
    }

    private func nightBoard(_ night: GameNight) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(ShellTheme.gold)
                Text("NIGHT STANDINGS")
                    .font(ShellTheme.eyebrow(24))
                    .tracking(6)
                    .foregroundColor(.white)
                Spacer(minLength: 16)
                TVNightPlaylistStrip(slots: TVNightSlot.slots(from: night.playlist),
                                     currentIndex: night.index,
                                     tileSize: 44)
            }
            TVNightStandingsBoard(standings: night.standings, totalsBefore: nightTotalsBefore)
        }
        .frame(maxWidth: 1240, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if isChampion {
            HStack(spacing: 32) {
                Button(action: onBackToGames) {
                    Label("Back to Games", systemImage: "square.grid.2x2.fill")
                }
                .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.gold))
                .prefersDefaultFocus(true, in: resultsFocus)

                if let onEndNight {
                    Button(action: onEndNight) {
                        Label("End night", systemImage: "moon.zzz.fill")
                    }
                    .buttonStyle(ShellGlassButtonStyle(tint: ShellTheme.pink, fontSize: 22))
                }
            }
        } else if isNightGame, let night = room.night, let onNextGame {
            HStack(spacing: 32) {
                Button(action: onNextGame) {
                    Label(nextGameTitle(night),
                          systemImage: night.next == nil ? "crown.fill" : "forward.fill")
                }
                .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.pink))
                .prefersDefaultFocus(true, in: resultsFocus)

                if let onEndNight {
                    Button(action: onEndNight) {
                        Label("End night", systemImage: "moon.zzz.fill")
                    }
                    .buttonStyle(ShellGlassButtonStyle(tint: ShellTheme.cyan, fontSize: 22))
                }
            }
        } else {
            HStack(spacing: 32) {
                Button(action: onPlayAgain) {
                    Label("Play Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.gold))
                .prefersDefaultFocus(true, in: resultsFocus)

                // Reported directly: "Play Again" always took everyone back to
                // the game list -- it does a real rematch now, so this is the
                // screen's only way back to it, for whoever doesn't already
                // know Menu on the remote does the same thing.
                Button(action: onBackToGames) {
                    Label("Back to Games", systemImage: "square.grid.2x2.fill")
                }
                .buttonStyle(ShellGlassButtonStyle(tint: ShellTheme.cyan, fontSize: 26))
            }
        }
    }

    private func nextGameTitle(_ night: GameNight) -> String {
        if let next = night.nextGame {
            return "Next game: \(next.displayName)"
        }
        if night.next != nil {
            return "Next game"
        }
        return "Crown the champion"
    }

    // MARK: Reveal

    /// Steps the reveal once per run. `.task(id:)` cancels it if the screen
    /// goes away (Next game, Play Again, Menu), which ends the sequence early.
    private func runReveal() async {
        for next in 1...5 {
            if next == 5 && !isNightGame { return }
            let delay: UInt64
            switch next {
            case 1: delay = 400_000_000
            case 5: delay = 2_400_000_000
            default: delay = 750_000_000
            }
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                stage = next
            }
        }
    }
}


// MARK: - Podium

/// Top three on stepped blocks, laid out 2nd / 1st / 3rd, the whole stage
/// tipped back slightly in 3D so the block tops are visible.
private struct ResultsPodium: View {
    let entries: [TVResultsEntry]
    let stage: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 18) {
                column(rank: 2)
                column(rank: 1)
                column(rank: 3)
            }
            // Floor shadow the podium stands on.
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                                     center: .center,
                                     startRadius: 10,
                                     endRadius: 380))
                .frame(width: 820, height: 60)
                .offset(y: -18)
        }
        .rotation3DEffect(.degrees(8), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.4)
    }

    private func column(rank: Int) -> some View {
        let index: Int = rank - 1
        let player: TVResultsEntry? = index < entries.count ? entries[index] : nil
        return PodiumColumn(player: player, rank: rank, isRisen: stage >= Self.revealStage(for: rank))
    }

    /// Third place rises first, the winner last.
    static func revealStage(for rank: Int) -> Int {
        switch rank {
        case 3: return 1
        case 2: return 2
        default: return 3
        }
    }
}

private struct PodiumColumn: View {
    let player: TVResultsEntry?
    let rank: Int
    let isRisen: Bool

    private var blockHeight: CGFloat {
        switch rank {
        case 1: return 230
        case 2: return 165
        default: return 115
        }
    }

    private var width: CGFloat { rank == 1 ? 250 : 220 }
    private var tokenSize: CGFloat { rank == 1 ? 116 : 96 }

    private var lightColor: Color {
        switch rank {
        case 1: return Color(hex: "FDE68A")
        case 2: return Color(hex: "F1F5F9")
        default: return Color(hex: "FDBA74")
        }
    }

    private var darkColor: Color {
        switch rank {
        case 1: return Color(hex: "CA8A04")
        case 2: return Color(hex: "64748B")
        default: return Color(hex: "9A3412")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            playerHeader
                .padding(.bottom, 14)
                .opacity(isRisen ? 1 : 0)
                .scaleEffect(isRisen ? 1 : 0.4, anchor: .bottom)
                .shellHop(trigger: isRisen ? 1 : 0, height: rank == 1 ? 44 : 30)

            PodiumTopShape(inset: 18)
                .fill(LinearGradient(colors: [lightColor, lightColor.opacity(0.75)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .frame(width: width, height: 28)

            frontFace
                .frame(width: width, height: isRisen ? blockHeight : 0, alignment: .top)
                .clipped()
        }
        .frame(width: width + 20)
        .animation(.spring(response: 0.7, dampingFraction: 0.72), value: isRisen)
    }

    private var frontFace: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(LinearGradient(colors: [lightColor, darkColor],
                                     startPoint: .top,
                                     endPoint: .bottom))
            // Side shading so the block reads as solid, not a flat card.
            Rectangle()
                .fill(LinearGradient(stops: [
                    .init(color: Color.white.opacity(0.25), location: 0.0),
                    .init(color: Color.white.opacity(0), location: 0.25),
                    .init(color: Color.black.opacity(0), location: 0.7),
                    .init(color: Color.black.opacity(0.3), location: 1.0)
                ], startPoint: .leading, endPoint: .trailing))
            Text("\(rank)")
                .font(ShellTheme.display(rank == 1 ? 120 : 96, weight: .black))
                .foregroundColor(Color.white.opacity(0.9))
                .shadow(color: darkColor.opacity(0.9), radius: 0, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 8)
                .padding(.top, 18)
        }
        .frame(width: width, height: blockHeight)
    }

    @ViewBuilder
    private var playerHeader: some View {
        VStack(spacing: 8) {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "FEF08A"), Color(hex: "EAB308")],
                                                    startPoint: .top,
                                                    endPoint: .bottom))
                    .shadow(color: ShellTheme.gold.opacity(0.8), radius: 14)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .rotationEffect(.degrees(phase ? 6 : -6))
                            .offset(y: phase ? -4 : 2)
                    } animation: { _ in
                        Animation.easeInOut(duration: 1.2)
                    }
            }
            if let player {
                ShellAvatarToken(id: player.id, name: player.name, size: tokenSize, isBot: player.isBot)
                Text(player.name)
                    .font(ShellTheme.display(rank == 1 ? 32 : 26, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(player.score) pts")
                    .font(ShellTheme.display(rank == 1 ? 28 : 24, weight: .heavy))
                    .foregroundColor(rank == 1 ? ShellTheme.gold : ShellTheme.cyan)
            } else {
                ShellGhostToken(size: tokenSize)
                Text("--")
                    .font(ShellTheme.display(26, weight: .bold))
                    .foregroundColor(ShellTheme.textTertiary)
            }
        }
    }
}

/// The top face of a podium block, seen from slightly above: a trapezoid
/// narrowing toward the back.
private struct PodiumTopShape: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Ranking

/// Everyone from 4th place down, as cards that swing in from the right one
/// after another. Two compact columns when the room is big.
private struct ResultsRankingList: View {
    let title: String
    let entries: [TVResultsEntry]
    let startRank: Int
    let isShown: Bool

    private var isCompact: Bool { entries.count > 7 }

    private var columns: [GridItem] {
        if isCompact {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(ShellTheme.eyebrow(20))
                .tracking(6)
                .foregroundColor(ShellTheme.textTertiary)
                .opacity(isShown ? 1 : 0)

            LazyVGrid(columns: columns, alignment: .leading, spacing: isCompact ? 10 : 14) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, player in
                    RankingCard(rank: startRank + index, player: player, isCompact: isCompact)
                        .opacity(isShown ? 1 : 0)
                        .offset(x: isShown ? 0 : 140)
                        .rotation3DEffect(.degrees(isShown ? 0 : -40),
                                          axis: (x: 0, y: 1, z: 0),
                                          perspective: 0.5)
                        .animation(.spring(response: 0.55, dampingFraction: 0.78)
                                    .delay(Double(index) * 0.07),
                                   value: isShown)
                }
            }
        }
    }
}

private struct RankingCard: View {
    let rank: Int
    let player: TVResultsEntry
    let isCompact: Bool

    var body: some View {
        HStack(spacing: isCompact ? 10 : 18) {
            Text("\(rank)")
                .font(ShellTheme.display(isCompact ? 22 : 28, weight: .heavy))
                .foregroundColor(ShellTheme.textSecondary)
                .frame(width: isCompact ? 34 : 44)

            ShellAvatarToken(id: player.id,
                             name: player.name,
                             size: isCompact ? 40 : 54,
                             isBot: player.isBot)

            Text(player.name)
                .font(.system(size: isCompact ? 21 : 26, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 8)

            Text("\(player.score) pts")
                .font(ShellTheme.display(isCompact ? 21 : 26, weight: .bold))
                .foregroundColor(ShellTheme.cyan)
                .lineLimit(1)
        }
        .padding(.horizontal, isCompact ? 14 : 22)
        .padding(.vertical, isCompact ? 8 : 12)
        .background {
            ShellGlassSurface(cornerRadius: isCompact ? 18 : 22, tint: ShellTheme.avatarColor(for: player.id))
        }
    }
}
