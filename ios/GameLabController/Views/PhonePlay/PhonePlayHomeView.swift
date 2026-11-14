import SwiftUI

// MARK: - Phone Play root and home grid
//
// This is the app's home screen (ControllerScreen.join): a "Play on TV"
// hero that opens the join sheet, then the party games (with Road Trip Quiz,
// Travel Mode, as a wide card), then "Brain and solo": the Mind Gym card and
// every solo game as its own tile.

struct PhonePlayRootView: View {
    @EnvironmentObject var vm: ControllerRootViewModel
    @ObservedObject var play: PhonePlayViewModel

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            content
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .opacity))
        }
        .animation(PhonePlayDesign.smooth, value: play.active)
    }

    @ViewBuilder
    private var content: some View {
        if play.active == .headsUp, let game = play.headsUp {
            HeadsUpRootView(game: game, onExit: play.closeGame)
        } else if play.active == .guessSong, let game = play.guessSong {
            GuessSongRootView(game: game, onExit: play.closeGame)
        } else if play.active == .spy, let game = play.spy {
            SpyRootView(game: game, onExit: play.closeGame)
        } else if play.active == .mafia, let game = play.mafia {
            MafiaRootView(game: game, onExit: play.closeGame)
        } else if play.active == .daily, let game = play.daily {
            DailyRootView(game: game, onExit: play.closeGame)
        } else if play.active == .truthOrDare, let game = play.truthOrDare {
            TruthDareRootView(game: game, onExit: play.closeGame)
        } else if play.active == .wouldYouRather, let game = play.wouldYouRather {
            WouldRatherRootView(game: game, onExit: play.closeGame)
        } else if play.active == .hotPotato, let game = play.hotPotato {
            HotPotatoRootView(game: game, onExit: play.closeGame)
        } else if play.active == .storyChain, let game = play.storyChain {
            StoryChainRootView(game: game, onExit: play.closeGame)
        } else if play.active == .wordOfDay, let game = play.wordOfDay {
            WordDayRootView(game: game, onExit: play.closeGame)
        } else if play.active == .arcade, let game = play.arcade {
            PocketArcadeRootView(game: game, onExit: play.closeGame)
        } else if play.active == .mindGym, let game = play.mindGym {
            NeuroPulseRootView(game: game, onExit: play.closeGame)
        } else {
            PhonePlayHomeView(play: play,
                              resumableRoomCode: vm.resumableRoomCode,
                              onPlayOnTV: vm.openJoinSheet,
                              onResumeTV: vm.resumeTVGame,
                              onDismissResume: { vm.forgetResumableRoom() },
                              onRoadTrip: vm.startTravel)
        }
    }
}

struct PhonePlayHomeView: View {
    @ObservedObject var play: PhonePlayViewModel
    /// Non-nil when the phone was seated in a TV room when the app last
    /// went away: shows the "Back to your TV game" banner.
    let resumableRoomCode: String?
    let onPlayOnTV: () -> Void
    let onResumeTV: () -> Void
    let onDismissResume: () -> Void
    /// Opens Road Trip Quiz (Travel Mode).
    let onRoadTrip: () -> Void

    @State private var appeared: Bool = false
    @State private var dailyDone: Bool = false
    @State private var dailyStreak: Int = 0
    @State private var wordSeen: Bool = false
    @State private var mindGym: NeuroHomeState = NeuroHomeState(mode: .start, streak: 0)
    @State private var today = PhoneTodayState(mindGymPulse: nil, mindGymStep: nil, mindGymStreak: 0,
                                               quickCorrect: nil, quickStreak: 0, wordSeen: false)
    @State private var recents: [PhoneRecentItem] = []
    @State private var groupSize: PhoneGroupSize? = PhoneGroupSize.saved
    @State private var showStats = false

    private let partyGames: [PhonePlayGame] = PhonePlayGame.allCases
        .filter { !$0.isSolo && $0.isGridCard }
    private let soloGames: [PhonePlayGame] = PhonePlayGame.allCases
        .filter { $0.isSolo && $0.isGridCard }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PhoneHomeTopBar(onStats: { showStats = true })
            ScrollView {
                VStack(spacing: 22) {
                    if let code = resumableRoomCode {
                        PhoneHomeResumeBanner(code: code, onResume: onResumeTV, onDismiss: onDismissResume)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    PhoneHomeTVEntry(appeared: appeared, action: onPlayOnTV)

                    PhoneTodayCard(state: today,
                                   onMindGym: { play.open(.mindGym) },
                                   onQuick: { play.open(.daily) },
                                   onWord: { play.open(.wordOfDay) },
                                   onMindScore: play.openMindScore)

                    if !recents.isEmpty {
                        PhoneContinueRow(items: recents, onOpen: play.openRecent)
                    }

                    PhonePlaySectionLabel(text: "Party games")
                        .padding(.top, 4)

                    PhoneGroupSizePicker(size: $groupSize)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(sortedPartyGames.enumerated()), id: \.element.id) { pair in
                            let note: String? = groupSize?.note(for: pair.element)
                            PhonePlayGameCard(game: pair.element,
                                              badge: note ?? badge(for: pair.element),
                                              index: pair.offset,
                                              appeared: appeared) {
                                play.open(pair.element)
                            }
                            .opacity(note == nil ? 1 : 0.4)
                        }
                    }

                    // Travel Mode, as a party game: one phone reads riddles
                    // and quiz questions aloud for the whole car.
                    PhonePlayGameCard(info: PhonePlayCardInfo.roadTrip,
                                      badge: "Hands-free",
                                      index: partyGames.count,
                                      appeared: appeared,
                                      wide: true,
                                      action: onRoadTrip)

                    // The arcade games, each as its own tile. Mind Gym, Quick 5
                    // and Word of the Day live on the Today card at the top.
                    PhonePlaySectionLabel(text: "Arcade")
                        .padding(.top, 6)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(soloGames.enumerated()), id: \.element.id) { pair in
                            PhonePlayGameCard(game: pair.element,
                                              badge: badge(for: pair.element),
                                              index: partyGames.count + 1 + pair.offset,
                                              appeared: appeared) {
                                play.open(pair.element)
                            }
                        }
                        ForEach(Array(PocketArcadeGame.allCases.enumerated()), id: \.element.id) { pair in
                            PhonePlayGameCard(info: PhonePlayCardInfo(arcade: pair.element),
                                              badge: arcadeBadge(for: pair.element),
                                              index: partyGames.count + 1 + soloGames.count + pair.offset,
                                              appeared: appeared) {
                                play.openArcade(pair.element)
                            }
                        }
                    }

                    Text("Phone games work offline. No TV or Wi-Fi needed.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 34)
                .animation(PhonePlayDesign.smooth, value: resumableRoomCode)
            }
        }
        .sheet(isPresented: $showStats) {
            PhoneStatsSheet(today: today)
        }
        .onAppear {
            refreshDaily()
            mindGym = NeuroHomeState.load()
            today = PhoneTodayState.load()
            recents = PhonePlayRecents.ids.compactMap(PhoneRecentItem.from)
            withAnimation(PhonePlayDesign.pop) {
                appeared = true
            }
        }
    }

    /// The party games, the ones that suit the chosen group size first.
    private var sortedPartyGames: [PhonePlayGame] {
        guard let size = groupSize else { return partyGames }
        return partyGames.filter { size.fits($0) } + partyGames.filter { !size.fits($0) }
    }

    /// The best score so far, once there is one.
    private func arcadeBadge(for game: PocketArcadeGame) -> String? {
        switch game {
        case .lights:
            let best = PocketArcadeStore.bestLights
            return best > 0 ? "Best \(best)" : nil
        case .rush:
            let best = PocketArcadeStore.bestRush
            return best > 0 ? "Best " + PocketArcadeStore.rushText(best) : nil
        case .twenty48:
            let best = PocketArcadeStore.bestTiles
            return best > 0 ? "Best \(best)" : nil
        }
    }

    private func badge(for game: PhonePlayGame) -> String? {
        switch game {
        case .daily:
            if dailyDone { return "Done today" }
            if dailyStreak > 0 { return "\(dailyStreak) day streak" }
            return "New today"
        case .wordOfDay:
            return wordSeen ? nil : "New word"
        case .guessSong:
            return "New"
        case .headsUp, .spy, .mafia, .truthOrDare, .wouldYouRather, .hotPotato,
             .storyChain, .arcade, .mindGym:
            return nil
        }
    }

    private func refreshDaily() {
        let now = Date()
        let today = DailyBrain.dateKey(for: now)
        let before = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterday = DailyBrain.dateKey(for: before)
        dailyDone = DailyStore.result(for: today) != nil
        dailyStreak = DailyStore.currentStreak(today: today, yesterday: yesterday)
        wordSeen = WordDayStore.seen(today)
    }
}

// MARK: - Cards

/// What a home card shows. Phone Play games build one from PhonePlayGame;
/// Road Trip Quiz (Travel Mode) is routed specially and has its own.
struct PhonePlayCardInfo {
    let title: String
    let blurb: String
    let symbol: String
    let colors: [Color]
    let players: String
    /// About how long a sitting takes ("5 min"); empty when it varies.
    let minutes: String

    init(title: String, blurb: String, symbol: String, colors: [Color], players: String,
         minutes: String = "") {
        self.title = title
        self.blurb = blurb
        self.symbol = symbol
        self.colors = colors
        self.players = players
        self.minutes = minutes
    }

    init(game: PhonePlayGame) {
        self.init(title: game.title, blurb: game.blurb, symbol: game.symbol,
                  colors: game.colors, players: game.players, minutes: game.minutes)
    }

    init(arcade game: PocketArcadeGame) {
        self.init(title: game.title, blurb: game.blurb, symbol: game.symbol,
                  colors: game.colors, players: "Solo", minutes: "2 min")
    }

    static let roadTrip = PhonePlayCardInfo(
        title: "Road Trip Quiz",
        blurb: "Hands-free riddles, quiz and brain teasers, spoken aloud. Everyone shouts the answer.",
        symbol: "car.fill",
        colors: [PhonePlayDesign.green, PhonePlayDesign.cyan],
        players: "Whole car",
        minutes: "As long as the drive"
    )
}

private struct PhonePlayGameCard: View {
    let info: PhonePlayCardInfo
    let badge: String?
    let index: Int
    let appeared: Bool
    var wide: Bool = false
    let action: () -> Void

    init(info: PhonePlayCardInfo, badge: String?, index: Int, appeared: Bool,
         wide: Bool = false, action: @escaping () -> Void) {
        self.info = info
        self.badge = badge
        self.index = index
        self.appeared = appeared
        self.wide = wide
        self.action = action
    }

    init(game: PhonePlayGame, badge: String?, index: Int, appeared: Bool,
         action: @escaping () -> Void) {
        self.init(info: PhonePlayCardInfo(game: game), badge: badge, index: index,
                  appeared: appeared, action: action)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: info.symbol)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .phonePlayIdle(dy: 3, degrees: 4, duration: 1.4 + Double(index) * 0.15)
                    Spacer(minLength: 4)
                    if let text = badge {
                        Text(text)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.9)))
                    }
                }
                Spacer(minLength: 0)
                Text(info.title)
                    .font(.system(size: wide ? 26 : 23, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.blurb)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.minutes.isEmpty ? info.players : "\(info.players)  \u{00B7}  \(info.minutes)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: wide ? 150 : 180, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(info.colors))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: (info.colors.first ?? .clear).opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(PhonePlayPressStyle())
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .rotation3DEffect(.degrees(appeared ? 0 : 25), axis: (x: 1, y: 0, z: 0))
        .animation(PhonePlayDesign.pop.delay(Double(index) * 0.07), value: appeared)
    }
}
