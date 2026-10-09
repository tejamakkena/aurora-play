import SwiftUI

// MARK: - Phone Play root and home grid
//
// This is the app's home screen (ControllerScreen.join): a "Play on TV"
// hero that opens the join sheet, then the Phone Play games, with Road
// Trip Quiz (Travel Mode) among the party games.

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
            PhoneHomeTopBar()
            ScrollView {
                VStack(spacing: 22) {
                    if let code = resumableRoomCode {
                        PhoneHomeResumeBanner(code: code, onResume: onResumeTV, onDismiss: onDismissResume)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    PhoneHomeTVEntry(appeared: appeared, action: onPlayOnTV)

                    PhonePlaySectionLabel(text: "Mind Gym")
                        .padding(.top, 4)

                    NeuroHomeCard(state: mindGym,
                                  appeared: appeared,
                                  onPlay: { play.open(.mindGym) },
                                  onProgress: play.openMindScore,
                                  quickDone: dailyDone,
                                  onQuick: { play.open(.daily) })

                    PhonePlaySectionLabel(text: "Party games")
                        .padding(.top, 4)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(partyGames.enumerated()), id: \.element.id) { pair in
                            PhonePlayGameCard(game: pair.element,
                                              badge: badge(for: pair.element),
                                              index: pair.offset,
                                              appeared: appeared) {
                                play.open(pair.element)
                            }
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

                    PhonePlaySectionLabel(text: "Solo")
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
                    }

                    Text("Phone games work offline. No TV or Wi-Fi needed.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .padding(.top, 4)

                    Text(BuildStamp.displayString)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3.opacity(0.7))
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 34)
                .animation(PhonePlayDesign.smooth, value: resumableRoomCode)
            }
        }
        .onAppear {
            refreshDaily()
            mindGym = NeuroHomeState.load()
            withAnimation(PhonePlayDesign.pop) {
                appeared = true
            }
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

    init(title: String, blurb: String, symbol: String, colors: [Color], players: String) {
        self.title = title
        self.blurb = blurb
        self.symbol = symbol
        self.colors = colors
        self.players = players
    }

    init(game: PhonePlayGame) {
        self.init(title: game.title, blurb: game.blurb, symbol: game.symbol,
                  colors: game.colors, players: game.players)
    }

    static let roadTrip = PhonePlayCardInfo(
        title: "Road Trip Quiz",
        blurb: "Hands-free riddles, quiz and brain teasers, spoken aloud. Everyone shouts the answer.",
        symbol: "car.fill",
        colors: [PhonePlayDesign.green, PhonePlayDesign.cyan],
        players: "Whole car"
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
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(info.players)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: wide ? 170 : 210, alignment: .topLeading)
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
