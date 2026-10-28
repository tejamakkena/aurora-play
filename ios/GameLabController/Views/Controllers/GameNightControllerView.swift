import SwiftUI

/// The phone / iPad side of Game Night.
///
/// For the host (normally the iPad) this is the main controller: set the
/// occasion, the guest of honour, the voice and the lineup, then start the
/// night and drive it (next / skip / end). For everyone else it is a companion
/// screen between games. While a hosted game is running it hands the whole
/// screen to that game's own controller, untouched.
struct GameNightControllerView: View {
    let room: Room
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var night: NightState {
        NightState(dict: privateData["night"] as? [String: Any] ?? [:])
    }

    var body: some View {
        let night = self.night
        content(night)
            .background(Color(hex: "00040d").ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { hostBar(night) }
    }

    // MARK: Screens

    @ViewBuilder
    private func content(_ night: NightState) -> some View {
        if night.playing, !night.spectating,
           let id = night.currentGame?.id, let game = GameID(rawValue: id) {
            // The hosted game's own controller, fed its own private data.
            ControllerGameView(
                room: Room(code: room.code, gameID: game, players: room.players, state: .playing),
                privateData: privateData,
                onAction: onAction
            )
        } else if night.playing {
            WaitingState(icon: "👀",
                         text: "\(night.currentGame?.name ?? "A game") is in progress",
                         detail: "You'll be dealt into the next one")
        } else {
            stage(night)
        }
    }

    @ViewBuilder
    private func stage(_ night: NightState) -> some View {
        switch night.phase {
        case "setup":
            if let setup = night.setup, night.isHost {
                NightSetupForm(setup: setup, title: night.title, onAction: onAction)
            } else {
                GuestWaitingForHost(night: night, onClaim: { onAction("night_claim_host", [:]) })
            }
        case "welcome":
            NightInfoCard(emoji: night.emoji, kicker: "WELCOME TO",
                          title: night.title, detail: night.cheer)
        case "lineup":
            NightLineupList(items: night.lineup)
        case "intro":
            NightInfoCard(emoji: night.currentGame?.emoji ?? "🎮",
                          kicker: "GAME \(night.gameIndex) OF \(night.gameCount)",
                          title: night.currentGame?.name ?? "",
                          detail: night.currentGame?.blurb ?? "")
        case "interlude":
            NightInterlude(night: night)
        case "finale", "done":
            NightStandings(title: "Tonight's final scores", standings: night.standings)
        default:
            WaitingState(icon: "🎉", text: night.title)
        }
    }

    // MARK: Host controls

    @ViewBuilder
    private func hostBar(_ night: NightState) -> some View {
        if night.isHost, night.phase != "setup", night.phase != "done" {
            HStack(spacing: 12) {
                if night.playing {
                    Button { onAction("night_skip", [:]) } label: {
                        Label("Skip this game", systemImage: "forward.end.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { onAction("night_next", [:]) } label: {
                        Label(night.phase == "finale" ? "Finish" : "Next",
                              systemImage: "forward.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.cyan))
                            .foregroundColor(.black)
                    }
                    .buttonStyle(.plain)
                }
                if night.phase != "finale" {
                    Menu {
                        Button("End the night", role: .destructive) { onAction("night_end", [:]) }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
        }
    }
}

// MARK: - Guest views

private struct GuestWaitingForHost: View {
    let night: NightState
    let onClaim: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            NightInfoCard(emoji: night.emoji, kicker: "WELCOME TO",
                          title: night.title, detail: "Waiting for the host to start the night")
            // The first phone in is host, which isn't always the iPad.
            Button(action: onClaim) {
                Text("I'm running the night")
                    .font(.footnote.bold())
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }
}

private struct NightInfoCard: View {
    let emoji: String
    let kicker: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 14) {
            Text(emoji).font(.system(size: 76))
            Text(kicker)
                .font(.caption.bold()).tracking(4)
                .foregroundColor(.white.opacity(0.5))
            Text(title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            if !detail.isEmpty {
                Text(detail)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NightLineupList: View {
    let items: [NightLineupItem]

    var body: some View {
        VStack(spacing: 14) {
            Text("TONIGHT'S GAMES")
                .font(.caption.bold()).tracking(4)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 28)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(.headline.bold()).foregroundColor(.black)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.cyan))
                            Text(item.emoji).font(.title2)
                            Text(item.name).font(.headline).foregroundColor(.white)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

private struct NightInterlude: View {
    let night: NightState

    var body: some View {
        VStack(spacing: 6) {
            if let recap = night.lastGame {
                Text("\(recap.emoji) \(recap.name)")
                    .font(.headline).foregroundColor(.white.opacity(0.7))
                    .padding(.top, 28)
                if let winner = recap.winner, !recap.skipped {
                    Text("🏆 \(winner) wins!")
                        .font(.title2.bold()).foregroundColor(.yellow)
                }
            }
            NightStandings(title: "The night so far", standings: night.standings)
        }
    }
}

private struct NightStandings: View {
    let title: String
    let standings: [NightStanding]

    private var myID: String { AppConstants.deviceID }

    private func medal(_ index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(index + 1)."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title.uppercased())
                .font(.caption.bold()).tracking(3)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 20)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            Text(medal(index)).font(.title3).frame(width: 40)
                            Text(row.name)
                                .font(.body)
                                .fontWeight(row.id == myID ? .bold : .regular)
                                .foregroundColor(row.id == myID ? .cyan : .white)
                            Spacer(minLength: 0)
                            Text("\(row.points)")
                                .font(.headline.bold()).foregroundColor(.white)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Host setup

/// The host's setup screen. Wide on an iPad (two columns), stacked on a phone.
///
/// Every change is sent to the server a moment after the last keystroke, so the
/// TV's welcome screen follows along live -- the host sees "Welcome to Venkat's
/// Birthday Party" appear on the big screen as they type it.
private struct NightSetupForm: View {
    let setup: NightSetup
    let title: String
    let onAction: (String, [String: Any]) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var config = NightConfig()
    @State private var lastPushed: NightConfig?
    @State private var seeded = false
    @State private var pushTask: Task<Void, Never>?

    private static let maxGames = 12
    private let chipColumns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
    private let gameColumns = [GridItem(.adaptive(minimum: 210), spacing: 12)]

    private var occasion: NightOption? {
        setup.occasions.first { $0.id == config.occasion }
    }

    private var showsName: Bool {
        !(occasion?.detail ?? "").isEmpty
    }

    private var hasNHIE: Bool {
        config.games.contains("never_have_i_ever")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 28) {
                        VStack(spacing: 22) {
                            occasionSection
                            voiceSection
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 22) {
                            gamesSection
                            nhieSection
                            humorSection
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    occasionSection
                    voiceSection
                    gamesSection
                    nhieSection
                    humorSection
                }
                BigButton(title: "Start the Night", systemImage: "play.fill",
                          enabled: !config.games.isEmpty) {
                    pushTask?.cancel()
                    onAction("night_start", ["config": config.payload])
                }
                .padding(.horizontal, -20)      // BigButton pads itself
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !seeded else { return }
            seeded = true
            config = setup.config
            lastPushed = setup.config
        }
        .onChange(of: config) { _ in schedulePush() }
        .onDisappear { pushTask?.cancel() }
    }

    // MARK: Sending

    private func schedulePush() {
        guard seeded, config != lastPushed else { return }
        pushTask?.cancel()
        let snapshot = config
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            lastPushed = snapshot
            onAction("night_configure", ["config": snapshot.payload])
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("Set up the night")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text("The TV shows: Welcome to \(title)")
                .font(.subheadline).foregroundColor(.cyan)
                .multilineTextAlignment(.center)
            Text("\(setup.guestCount) \(setup.guestCount == 1 ? "person" : "people") here so far. More can join any time.")
                .font(.caption).foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var occasionSection: some View {
        SetupSection(title: "What's the occasion?") {
            LazyVGrid(columns: chipColumns, spacing: 10) {
                ForEach(setup.occasions) { option in
                    ChoiceChip(emoji: option.emoji, title: option.title,
                               selected: option.id == config.occasion) {
                        config.occasion = option.id
                    }
                }
            }
            if showsName {
                AnswerField(placeholder: occasion?.detail ?? "Name", text: $config.honoree)
                    .padding(.horizontal, -20)      // AnswerField pads itself
                    .padding(.top, 4)
            }
        }
    }

    private var voiceSection: some View {
        SetupSection(title: "Pick the host voice") {
            LazyVGrid(columns: chipColumns, spacing: 10) {
                ForEach(setup.voicePacks) { option in
                    ChoiceChip(emoji: option.emoji, title: option.title, detail: option.detail,
                               selected: option.id == config.voicePack) {
                        config.voicePack = option.id
                    }
                }
            }
            Button {
                onAction("night_preview", ["config": config.payload])
            } label: {
                Label("Hear it on the TV", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var gamesSection: some View {
        SetupSection(title: "Pick tonight's games (\(config.games.count) chosen)") {
            Text("They play in the order you tap them.")
                .font(.caption).foregroundColor(.white.opacity(0.45))
            LazyVGrid(columns: gameColumns, spacing: 12) {
                ForEach(setup.catalog) { game in
                    GameToggleCard(
                        game: game,
                        order: config.games.firstIndex(of: game.id).map { $0 + 1 },
                        fits: setup.guestCount >= game.minPlayers && setup.guestCount <= game.maxPlayers
                    ) {
                        toggle(game.id)
                    }
                }
            }
            if config.games.isEmpty {
                Text("Pick at least one game to start.")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    private var nhieSection: some View {
        if hasNHIE {
            SetupSection(title: "🙋 Never Have I Ever") {
                LazyVGrid(columns: chipColumns, spacing: 10) {
                    ForEach(setup.nhiePacks) { pack in
                        ChoiceChip(emoji: pack.emoji, title: pack.title, detail: pack.detail,
                                   badge: pack.flag ? "18+" : nil,
                                   selected: pack.id == config.nhiePack) {
                            config.nhiePack = pack.id
                        }
                    }
                }
                HStack(spacing: 10) {
                    Text("Rounds")
                        .font(.subheadline).foregroundColor(.white.opacity(0.6))
                    ForEach(setup.roundChoices, id: \.self) { rounds in
                        Button {
                            config.nhieRounds = rounds
                        } label: {
                            Text("\(rounds)")
                                .font(.subheadline.bold())
                                .foregroundColor(config.nhieRounds == rounds ? .black : .white)
                                .frame(width: 44, height: 36)
                                .background(RoundedRectangle(cornerRadius: 10)
                                    .fill(config.nhieRounds == rounds ? Color.cyan : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The jokes between rounds and between games.
    private var humorSection: some View {
        SetupSection(title: "😄 Humor style") {
            LazyVGrid(columns: chipColumns, spacing: 10) {
                ForEach(setup.humorPacks) { option in
                    ChoiceChip(emoji: option.emoji, title: option.title, detail: option.detail,
                               selected: option.id == config.humor) {
                        config.humor = option.id
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = config.games.firstIndex(of: id) {
            config.games.remove(at: index)
        } else if config.games.count < Self.maxGames {
            config.games.append(id)
        }
    }
}

// MARK: - Setup pieces

private struct SetupSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline).foregroundColor(.white)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
    }
}

private struct ChoiceChip: View {
    let emoji: String
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(emoji).font(.title)
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let badge {
                        Text(badge)
                            .font(.caption2.bold()).foregroundColor(.black)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2).foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(selected ? Color.cyan.opacity(0.2) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? Color.cyan : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

private struct GameToggleCard: View {
    let game: NightGameOption
    /// 1-based position in the lineup, or nil when not picked.
    let order: Int?
    /// Whether the people here now suit this game's player range.
    let fits: Bool
    let action: () -> Void

    private var rangeText: String {
        game.minPlayers == game.maxPlayers
            ? "\(game.minPlayers) players"
            : "\(game.minPlayers)-\(game.maxPlayers) players"
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(order == nil ? Color.white.opacity(0.08) : Color.cyan)
                        .frame(width: 34, height: 34)
                    if let order {
                        Text("\(order)").font(.subheadline.bold()).foregroundColor(.black)
                    } else {
                        Text(game.emoji).font(.title3)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(game.emoji) \(game.name)")
                        .font(.subheadline.bold()).foregroundColor(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(game.blurb)
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(fits ? rangeText : "\(rangeText) - not enough here yet")
                        .font(.caption2.bold())
                        .foregroundColor(fits ? .white.opacity(0.35) : .orange)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(order == nil ? Color.white.opacity(0.06) : Color.cyan.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(order == nil ? Color.clear : Color.cyan, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}
