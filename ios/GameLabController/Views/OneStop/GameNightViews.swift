import SwiftUI

// MARK: - Game Night on the phone
//
// Server: games/game_night.py + start_night / next_game / end_night in
// games/native_hub/socket_events.py. The night rides along in room_updated
// as Room.night. The host's phone plans and steers it; every phone sees the
// running scoreboard.

// MARK: Planner (host only, lobby, no night yet)

struct GameNightPlannerCard: View {
    let room: Room

    @State private var expanded = false
    @State private var kids = false
    @State private var minutes = 45
    @State private var playlist: [GameID] = []
    @State private var gameMinutes: [GameID: Int] = [:]
    @State private var loading = false
    @State private var reloadToken = 0
    @State private var starting = false

    private static let minuteOptions = [30, 45, 60]

    private var playerCount: Int { max(1, room.players.count) }
    private var totalMinutes: Int { playlist.reduce(0) { $0 + (gameMinutes[$1] ?? 0) } }
    private var loadKey: String { "\(expanded)-\(kids)-\(minutes)-\(playerCount)-\(reloadToken)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $kids) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Kids learning mode", systemImage: "figure.and.child.holdinghands")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                            Text("Only quizzes, puzzles, words and brain games, with kid-level questions")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .tint(PhonePlayDesign.pink)

                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill").foregroundColor(.white.opacity(0.5))
                        ForEach(Self.minuteOptions, id: \.self) { m in
                            OneStopChip(title: "\(m) min", selected: minutes == m, tint: PhonePlayDesign.orange) {
                                minutes = m
                            }
                        }
                    }

                    playlistPreview

                    OneStopPrimaryButton(title: starting ? "Starting..." : "Start Game Night",
                                         systemImage: "sparkles",
                                         colors: OneStopTheme.nightGradient,
                                         enabled: !starting && !loading) {
                        start()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .oneStopCard(tint: PhonePlayDesign.purple)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: expanded)
        .task(id: loadKey) { await loadPlaylist() }
    }

    private var header: some View {
        Button {
            PhonePlayHaptics.tap()
            expanded.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: OneStopTheme.nightGradient,
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.bounce, value: expanded)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game Night")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("A playlist of games with one big scoreboard")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var playlistPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TONIGHT'S PLAYLIST")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if loading {
                    ProgressView().scaleEffect(0.7).tint(.white.opacity(0.6))
                } else {
                    Button {
                        PhonePlayHaptics.tap()
                        reloadToken += 1
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundColor(PhonePlayDesign.orange)
                    }
                    .buttonStyle(.plain)
                }
            }

            if playlist.isEmpty && !loading {
                Text("The TV will pick a balanced mix for \(playerCount) player\(playerCount == 1 ? "" : "s") when you start.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            } else {
                ForEach(Array(playlist.enumerated()), id: \.element) { index, game in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(.caption, design: .rounded, weight: .heavy))
                            .foregroundColor(.black)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(PhonePlayDesign.orange))
                        Image(systemName: game.sfSymbol)
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 24)
                        Text(game.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        if let m = gameMinutes[game] {
                            Text("\(m) min")
                                .font(.system(.caption, design: .rounded))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        if playlist.count > 1 {
                            Button {
                                PhonePlayHaptics.tap()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    playlist.removeAll { $0 == game }
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(game.displayName)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous).fill(Color.white.opacity(0.05)))
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity),
                                            removal: .opacity))
                }
                if totalMinutes > 0 {
                    Text("About \(totalMinutes) minutes, \(playlist.count) game\(playlist.count == 1 ? "" : "s")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
    }

    /// Mirrors games/game_night.build_playlist closely enough for a preview:
    /// best-fit games first, about `minutes` long, at most 8. Only ids this
    /// build knows are kept (an unknown id would not decode on the phones).
    private func loadPlaylist() async {
        guard expanded else { loading = false; return }
        loading = true
        let picks = await OneStopAPI.pick(players: playerCount, kids: kids, minutes: nil)
        guard !Task.isCancelled else { return }
        var out: [GameID] = []
        var lengths: [GameID: Int] = [:]
        var spent = 0
        for pick in picks {
            if spent >= minutes || out.count >= 8 { break }
            guard let game = pick.game, !out.contains(game) else { continue }
            out.append(game)
            lengths[game] = pick.minutes
            spent += pick.minutes
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            playlist = out
            gameMinutes = lengths
        }
        loading = false
    }

    private func start() {
        starting = true
        let ids = playlist.map(\.rawValue)
        OneStopEvents.startNight(StartNightPayload(roomCode: room.code,
                                                   playlist: ids.isEmpty ? nil : ids,
                                                   minutes: minutes,
                                                   kids: kids))
        // room_updated swaps this card for the running scoreboard; re-enable
        // the button in case the server refused (e.g. no games fit).
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            starting = false
        }
    }
}

// MARK: Running night (lobby, everyone)

struct GameNightStatusCard: View {
    let room: Room
    let night: GameNight
    let isHost: Bool
    /// This phone's seat (ControllerRootViewModel.playerID), which is the
    /// device id for the first phone on a device and a seat of its own for
    /// a second phone sharing that id.
    var myID: String = AppConstants.deviceID

    @State private var confirmEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: night.finished ? "crown.fill" : "moon.stars.fill")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: OneStopTheme.nightGradient,
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.pulse, isActive: !night.finished)
                VStack(alignment: .leading, spacing: 2) {
                    Text(night.finished ? "Game Night is over" : "Game Night")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
            }

            if night.finished {
                if let champ = night.champion {
                    NightChampionBanner(standing: champ)
                }
            } else {
                NightPlaylistStrip(night: night)
                upNext
            }

            if !night.standings.isEmpty {
                NightStandingsList(standings: night.standings,
                                   limit: night.finished ? 8 : 5, myID: myID)
            }

            if isHost {
                if night.finished {
                    OneStopSecondaryButton(title: "Close Game Night", systemImage: "xmark.circle", tint: PhonePlayDesign.pink) {
                        OneStopEvents.endNight(roomCode: room.code)
                    }
                } else {
                    HStack(spacing: 10) {
                        OneStopSecondaryButton(title: night.next == nil ? "Finish night" : "Skip game",
                                               systemImage: "forward.fill", tint: PhonePlayDesign.orange) {
                            OneStopEvents.nextGame(roomCode: room.code)
                        }
                        OneStopSecondaryButton(title: "End night", systemImage: "stop.fill", tint: PhonePlayDesign.pink) {
                            confirmEnd = true
                        }
                    }
                }
            }
        }
        .oneStopCard(tint: PhonePlayDesign.purple)
        .confirmationDialog("End Game Night now?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End night", role: .destructive) { OneStopEvents.endNight(roomCode: room.code) }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The scoreboard is cleared for everyone.")
        }
    }

    private var subtitle: String {
        if night.finished {
            let n = night.gamesPlayed
            return n == 1 ? "1 game played" : "\(n) games played"
        }
        return "Game \(min(night.index + 1, night.playlist.count)) of \(night.playlist.count)"
    }

    @ViewBuilder
    private var upNext: some View {
        let current = night.current.flatMap { GameID(rawValue: $0) }
        VStack(alignment: .leading, spacing: 8) {
            if let current {
                NightGameRow(label: "UP NOW", game: current, highlight: true)
            }
            if let next = night.nextGame {
                NightGameRow(label: "THEN", game: next, highlight: false)
            } else if current != nil {
                Text("Last game of the night")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundColor(PhonePlayDesign.orange)
            }
        }
    }
}

// MARK: Between games (results screen)

/// Shown on the phone's results screen while a Game Night is on: the
/// running standings, and for the host the Next game / End night controls
/// (they replace Play Again, which would replay the same game).
struct GameNightResultsPanel: View {
    let room: Room
    let night: GameNight
    let isHost: Bool
    var myID: String = AppConstants.deviceID

    @State private var confirmEnd = false
    @State private var sent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: night.finished ? "crown.fill" : "moon.stars.fill")
                    .foregroundStyle(LinearGradient(colors: OneStopTheme.nightGradient,
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(night.finished ? "Game Night champion" : "Game Night standings")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(night.gamesPlayed)/\(night.playlist.count)")
                    .font(.system(.caption, design: .rounded).monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
            }

            if night.finished, let champ = night.champion {
                NightChampionBanner(standing: champ)
            }
            if !night.standings.isEmpty {
                NightStandingsList(standings: night.standings,
                                   limit: night.finished ? 5 : 3, myID: myID)
            }

            if isHost {
                if night.finished {
                    OneStopPrimaryButton(title: "Close Game Night", systemImage: "checkmark.circle.fill",
                                         colors: OneStopTheme.nightGradient) {
                        OneStopEvents.endNight(roomCode: room.code)
                    }
                } else {
                    OneStopPrimaryButton(title: nextTitle, systemImage: "forward.fill",
                                         colors: OneStopTheme.nightGradient, enabled: !sent) {
                        sent = true
                        OneStopEvents.nextGame(roomCode: room.code)
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            sent = false
                        }
                    }
                    Button {
                        PhonePlayHaptics.tap()
                        confirmEnd = true
                    } label: {
                        Text("End night early")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            } else if !night.finished {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8).tint(.white.opacity(0.5))
                    Text(waitingText)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .oneStopCard(tint: PhonePlayDesign.purple, padding: 14)
        .confirmationDialog("End Game Night now?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End night", role: .destructive) { OneStopEvents.endNight(roomCode: room.code) }
            Button("Keep playing", role: .cancel) {}
        }
    }

    private var waitingText: String {
        if let next = night.nextGame { return "Next up: \(next.displayName)" }
        return "Waiting for the host"
    }

    private var nextTitle: String {
        if let next = night.nextGame { return "Next game: \(next.displayName)" }
        return night.next == nil ? "Crown the champion" : "Next game"
    }
}

// MARK: - Pieces

struct NightGameRow: View {
    let label: String
    let game: GameID
    let highlight: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: game.sfSymbol)
                .font(.system(.title3, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(highlight
                              ? AnyShapeStyle(LinearGradient(colors: OneStopTheme.nightGradient,
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.white.opacity(0.08)))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundColor(.white.opacity(0.5))
                Text(game.displayName)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }
}

/// One dot per playlist game: done, current, upcoming.
struct NightPlaylistStrip: View {
    let night: GameNight

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            strip.padding(.vertical, 4).padding(.horizontal, 2)
        }
    }

    private var strip: some View {
        HStack(spacing: 6) {
            ForEach(Array(night.playlist.enumerated()), id: \.offset) { i, gid in
                let done = i < night.index
                let current = i == night.index
                Image(systemName: GameID(rawValue: gid)?.sfSymbol ?? "questionmark")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundColor(current ? .black : .white.opacity(done ? 0.4 : 0.8))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(current ? PhonePlayDesign.orange : Color.white.opacity(done ? 0.04 : 0.1))
                    )
                    .overlay(
                        Circle().strokeBorder(PhonePlayDesign.orange.opacity(current ? 0 : (done ? 0 : 0.3)), lineWidth: 1)
                    )
                    .scaleEffect(current ? 1.12 : 1)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: night.index)
    }
}

struct NightStandingsList: View {
    let standings: [NightStanding]
    var limit: Int = 5
    var myID: String = AppConstants.deviceID

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(standings.prefix(limit))) { row in
                let me = row.playerID == myID
                HStack(spacing: 10) {
                    Text("\(row.rank)")
                        .font(.system(.caption, design: .rounded, weight: .heavy))
                        .foregroundColor(row.rank <= 3 ? .black : .white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Self.rankColor(row.rank)))
                    Text(row.name)
                        .font(.system(.subheadline, design: .rounded, weight: me ? .bold : .regular))
                        .foregroundColor(me ? PhonePlayDesign.cyan : .white)
                        .lineLimit(1)
                    if row.isBot ?? false {
                        Text("BOT").font(.system(.caption2, design: .rounded)).foregroundColor(PhonePlayDesign.orange)
                    }
                    if me {
                        Text("YOU").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(PhonePlayDesign.cyan)
                    }
                    Spacer()
                    Text("\(row.points) pts")
                        .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(me ? PhonePlayDesign.cyan.opacity(0.12) : Color.white.opacity(0.04))
                )
            }
            if standings.count > limit {
                Text("+ \(standings.count - limit) more")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: standings)
    }

    static func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return PhonePlayDesign.yellow
        case 2: return Color(white: 0.8)
        case 3: return PhonePlayDesign.orange
        default: return Color.white.opacity(0.1)
        }
    }
}

struct NightChampionBanner: View {
    let standing: NightStanding

    @State private var glow = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.yellow)
                .shadow(color: PhonePlayDesign.yellow.opacity(glow ? 0.8 : 0.2), radius: glow ? 12 : 4)
                .symbolEffect(.bounce, value: glow)
            VStack(alignment: .leading, spacing: 2) {
                Text("CHAMPION")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.yellow.opacity(0.8))
                Text(standing.name)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(standing.points) night points")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(LinearGradient(colors: [PhonePlayDesign.yellow.opacity(0.25), PhonePlayDesign.orange.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
        }
    }
}
