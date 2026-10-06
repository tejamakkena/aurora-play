import SwiftUI

// Lives in the TV target (it used to sit in Shared/Views/ResultsView.swift):
// only RootTVView shows it, and its 3D shell styling uses the TV-only
// ShellTheme kit in Views/Theme/TVShellTheme.swift.

/// End-of-game results: a 3D podium whose blocks rise in sequence (3rd, 2nd,
/// then 1st with a confetti burst), the rest of the ranking sliding in as
/// cards, and Play Again / Back to Games.
struct TVResultsView: View {
    let room: Room
    let onPlayAgain: () -> Void
    let onBackToGames: () -> Void

    /// Reveal sequence: 0 nothing, 1 third place, 2 second, 3 first +
    /// confetti, 4 the rest of the ranking.
    @State private var stage: Int = 0
    @State private var hasStartedReveal: Bool = false
    @Namespace private var resultsFocus

    private var ranked: [Player] {
        room.players.sorted { $0.score > $1.score }
    }

    private var podiumPlayers: [Player] { Array(ranked.prefix(3)) }
    private var restPlayers: [Player] { Array(ranked.dropFirst(3)) }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                header

                HStack(alignment: .bottom, spacing: 56) {
                    ResultsPodium(players: podiumPlayers, stage: stage)
                        .frame(maxWidth: .infinity)

                    if !restPlayers.isEmpty {
                        ResultsRankingList(players: restPlayers,
                                           startRank: 4,
                                           isShown: stage >= 4)
                            .frame(width: 620)
                    }
                }
                .frame(maxHeight: .infinity)

                actionButtons
            }
            // Small outer padding: tvOS adds its own overscan safe area.
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .padding(.bottom, 20)

            if stage >= 3 && !room.players.isEmpty {
                ShellConfetti(particleCount: 160,
                              duration: 5.5,
                              origin: UnitPoint(x: restPlayers.isEmpty ? 0.5 : 0.34, y: 0.42))
                    .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusScope(resultsFocus)
        .task { await runReveal() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("FINAL RESULTS")
                .font(ShellTheme.eyebrow(24))
                .tracking(8)
                .foregroundColor(ShellTheme.textSecondary)
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
            Text(room.gameID.displayName)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.textTertiary)
        }
    }

    private var winnerLine: String {
        guard let winner = ranked.first else { return "Game over" }
        if ranked.count > 1, ranked[1].score == winner.score {
            return "It's a tie!"
        }
        return "\(winner.name) wins!"
    }

    private var actionButtons: some View {
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

    /// Steps the reveal once per appearance. `.task` is cancelled if the
    /// screen goes away (Play Again, Menu), which ends the sequence early.
    private func runReveal() async {
        guard !hasStartedReveal else { return }
        hasStartedReveal = true
        for next in 1...4 {
            let delay: UInt64 = next == 1 ? 400_000_000 : 750_000_000
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
    let players: [Player]
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
        let player: Player? = index < players.count ? players[index] : nil
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
    let player: Player?
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
    let players: [Player]
    let startRank: Int
    let isShown: Bool

    private var isCompact: Bool { players.count > 7 }

    private var columns: [GridItem] {
        if isCompact {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LEADERBOARD")
                .font(ShellTheme.eyebrow(20))
                .tracking(6)
                .foregroundColor(ShellTheme.textTertiary)
                .opacity(isShown ? 1 : 0)

            LazyVGrid(columns: columns, alignment: .leading, spacing: isCompact ? 10 : 14) {
                ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
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
    let player: Player
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
