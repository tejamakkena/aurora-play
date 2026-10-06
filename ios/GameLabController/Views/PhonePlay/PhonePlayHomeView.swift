import SwiftUI

// MARK: - Phone Play root and home grid

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
        } else if play.active == .wordOfDay, let game = play.wordOfDay {
            WordDayRootView(game: game, onExit: play.closeGame)
        } else if play.active == .arcade, let game = play.arcade {
            PocketArcadeRootView(game: game, onExit: play.closeGame)
        } else {
            PhonePlayHomeView(play: play, onExit: vm.endPhonePlay)
        }
    }
}

struct PhonePlayHomeView: View {
    @ObservedObject var play: PhonePlayViewModel
    let onExit: () -> Void

    @State private var appeared: Bool = false
    @State private var dailyDone: Bool = false
    @State private var dailyStreak: Int = 0
    @State private var wordSeen: Bool = false

    private let partyGames: [PhonePlayGame] = PhonePlayGame.allCases.filter { !$0.isSolo }
    private let soloGames: [PhonePlayGame] = PhonePlayGame.allCases.filter { $0.isSolo }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "", backTitle: "Home", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    header

                    PhonePlaySectionLabel(text: "Party games")

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

                    PhonePlaySectionLabel(text: "Solo")
                        .padding(.top, 6)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(soloGames.enumerated()), id: \.element.id) { pair in
                            PhonePlayGameCard(game: pair.element,
                                              badge: badge(for: pair.element),
                                              index: partyGames.count + pair.offset,
                                              appeared: appeared) {
                                play.open(pair.element)
                            }
                        }
                    }

                    Text("Works offline. No TV or Wi-Fi needed.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .onAppear {
            refreshDaily()
            withAnimation(PhonePlayDesign.pop) {
                appeared = true
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Phone Play")
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [PhonePlayDesign.orange, PhonePlayDesign.pink, PhonePlayDesign.purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("One phone. No TV. Pass it around.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
    }

    private func badge(for game: PhonePlayGame) -> String? {
        switch game {
        case .daily:
            if dailyDone { return "Done today" }
            if dailyStreak > 0 { return "\(dailyStreak) day streak" }
            return "New today"
        case .wordOfDay:
            return wordSeen ? nil : "New word"
        case .headsUp, .spy, .mafia, .truthOrDare, .wouldYouRather, .hotPotato, .arcade:
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

private struct PhonePlayGameCard: View {
    let game: PhonePlayGame
    let badge: String?
    let index: Int
    let appeared: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: game.symbol)
                        .font(.system(size: 34, weight: .bold))
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
                Text(game.title)
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(game.blurb)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(game.players)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(game.colors))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: (game.colors.first ?? .clear).opacity(0.35), radius: 14, y: 8)
        }
        .buttonStyle(PhonePlayPressStyle())
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
        .rotation3DEffect(.degrees(appeared ? 0 : 25), axis: (x: 1, y: 0, z: 0))
        .animation(PhonePlayDesign.pop.delay(Double(index) * 0.07), value: appeared)
    }
}
