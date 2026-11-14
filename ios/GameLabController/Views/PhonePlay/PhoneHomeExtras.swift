import SwiftUI

// MARK: - Home screen helpers: today, continue, group size, stats
//
// The home screen stays small (eight party games, the brain games and the
// arcade), so finding the right one is about presentation, not more games:
//   * Today: the three short daily habits, ticked off as they are done, with a
//     spoiler-free result to share.
//   * Continue: the last games played, one tap away.
//   * How many of you: dims the party games that do not suit the group.
//   * Stats: streaks, bests and the small print, out of the way.

// MARK: Facts each tile shows

extension PhonePlayGame {
    /// About how long one sitting takes, as shown on the tile.
    var minutes: String {
        switch self {
        case .headsUp:        return "5 min"
        case .guessSong:      return "10 min"
        case .spy:            return "10 min"
        case .mafia:          return "20 min"
        case .truthOrDare:    return "15 min"
        case .wouldYouRather: return "10 min"
        case .hotPotato:      return "5 min"
        case .pointAt:        return "10 min"
        case .daily:          return "2 min"
        case .wordOfDay:      return "1 min"
        case .arcade:         return "2 min"
        case .mindGym:        return "5 min"
        }
    }

    /// The group sizes the game works for (party games only).
    var playerRange: ClosedRange<Int> {
        switch self {
        case .headsUp:        return 2...30
        case .guessSong:      return 2...30
        case .spy:            return 3...12
        case .mafia:          return 5...15
        case .truthOrDare:    return 2...16
        case .wouldYouRather: return 2...30
        case .hotPotato:      return 2...12
        case .pointAt:        return 3...30
        case .daily, .wordOfDay, .arcade, .mindGym: return 1...1
        }
    }
}

// MARK: Group size

/// "How many of you?" on the home screen. Remembered on this phone.
enum PhoneGroupSize: String, CaseIterable, Identifiable {
    case two
    case few
    case many

    var id: String { rawValue }

    var title: String {
        switch self {
        case .two:  return "2 of us"
        case .few:  return "3 to 5"
        case .many: return "6 or more"
        }
    }

    /// The group sizes this choice stands for.
    var range: ClosedRange<Int> {
        switch self {
        case .two:  return 2...2
        case .few:  return 3...5
        case .many: return 6...30
        }
    }

    /// True when the game works for at least part of this range.
    func fits(_ game: PhonePlayGame) -> Bool {
        game.playerRange.overlaps(range)
    }

    /// Why a game is dimmed, e.g. "Needs 5+".
    func note(for game: PhonePlayGame) -> String? {
        guard !fits(game) else { return nil }
        let players = game.playerRange
        if players.lowerBound > range.upperBound { return "Needs \(players.lowerBound)+" }
        return "Up to \(players.upperBound)"
    }

    private static let key = "phoneplay_group_size"

    static var saved: PhoneGroupSize? {
        get { UserDefaults.standard.string(forKey: key).flatMap(PhoneGroupSize.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }
}

/// The group-size chips above the party games. Tapping the chosen one again clears it.
struct PhoneGroupSizePicker: View {
    @Binding var size: PhoneGroupSize?

    var body: some View {
        HStack(spacing: 8) {
            Text("How many of you?")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
            ForEach(PhoneGroupSize.allCases) { option in
                let on: Bool = size == option
                Button {
                    PhonePlayHaptics.tap()
                    withAnimation(PhonePlayDesign.smooth) { size = on ? nil : option }
                    PhoneGroupSize.saved = size
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(on ? .black : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(on ? Color.white : PhonePlayDesign.surface2))
                }
                .buttonStyle(PhonePlayPressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Recently played

/// The last games opened from the home screen, most recent first.
enum PhonePlayRecents {
    private static let key = "phoneplay_recent_games"
    private static let cap = 3

    /// "headsUp", or "arcade:rush" for one arcade game.
    static var ids: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ id: String) {
        var list = ids.filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(cap)), forKey: key)
    }
}

/// One "Continue" chip: what it shows and what it opens.
struct PhoneRecentItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let colors: [Color]

    static func from(_ id: String) -> PhoneRecentItem? {
        if id.hasPrefix("arcade:"), let game = PocketArcadeGame(rawValue: String(id.dropFirst(7))) {
            return PhoneRecentItem(id: id, title: game.title, symbol: game.symbol, colors: game.colors)
        }
        if let game = PhonePlayGame(rawValue: id) {
            return PhoneRecentItem(id: id, title: game.title, symbol: game.symbol, colors: game.colors)
        }
        return nil
    }
}

struct PhoneContinueRow: View {
    let items: [PhoneRecentItem]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PhonePlaySectionLabel(text: "Continue")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            PhonePlayHaptics.tap()
                            onOpen(item.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Text(item.title)
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(PhonePlayDesign.gradient(item.colors)))
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .accessibilityLabel("Continue \(item.title)")
                    }
                }
            }
        }
    }
}

// MARK: Today

/// Where today's three daily habits stand, read from their own stores.
struct PhoneTodayState: Equatable {
    var mindGymPulse: Int?          // today's Mind Score, once done
    var mindGymStep: Int?           // the step a half-done workout is on
    var mindGymStreak: Int
    var quickCorrect: Int?          // Quick 5, right answers out of 5
    var quickStreak: Int
    var wordSeen: Bool

    static func load(now: Date = Date()) -> PhoneTodayState {
        let today = DailyBrain.dateKey(for: now)
        let before = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterday = DailyBrain.dateKey(for: before)
        let gym = NeuroHomeState.load()
        var pulse: Int? = nil
        var step: Int? = nil
        switch gym.mode {
        case .done(let value): pulse = value
        case .resume(let reached): step = reached
        case .start: break
        }
        return PhoneTodayState(mindGymPulse: pulse,
                               mindGymStep: step,
                               mindGymStreak: gym.streak,
                               quickCorrect: DailyStore.result(for: today)?.correct,
                               quickStreak: DailyStore.currentStreak(today: today, yesterday: yesterday),
                               wordSeen: WordDayStore.seen(today))
    }

    var doneCount: Int {
        (mindGymPulse != nil ? 1 : 0) + (quickCorrect != nil ? 1 : 0) + (wordSeen ? 1 : 0)
    }

    var bestStreak: Int { max(mindGymStreak, quickStreak) }

    /// A result to share that gives nothing away: no answers, no words.
    func shareText(now: Date = Date()) -> String {
        let day = now.formatted(.dateTime.month(.abbreviated).day())
        var parts: [String] = []
        if let pulse = mindGymPulse { parts.append("Mind Gym \(pulse)") }
        if let right = quickCorrect { parts.append("Quick 5: \(right)/5") }
        if wordSeen { parts.append("Word of the Day done") }
        var text = "Aurora Play, \(day). " + parts.joined(separator: ", ") + "."
        if bestStreak > 1 { text += " \(bestStreak)-day streak." }
        return text
    }
}

/// The top-of-home card: today's three short habits, each a tap to open.
struct PhoneTodayCard: View {
    let state: PhoneTodayState
    let onMindGym: () -> Void
    let onQuick: () -> Void
    let onWord: () -> Void
    /// Opens the Mind Score history (Mind Gym's progress screen).
    var onMindScore: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.text3)
                if state.bestStreak > 1 {
                    Label("\(state.bestStreak)-day streak", systemImage: "flame.fill")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.orange)
                }
                Spacer()
                if state.doneCount > 0 {
                    ShareLink(item: state.shareText()) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.cyan)
                    }
                    .accessibilityLabel("Share today's results")
                }
            }
            HStack(spacing: 10) {
                habit(title: "Mind Gym",
                      detail: state.mindGymPulse.map { "Score \($0)" }
                          ?? state.mindGymStep.map { "Step \($0) of 10" } ?? "5 min",
                      symbol: "brain.head.profile", done: state.mindGymPulse != nil, action: onMindGym)
                habit(title: "Quick 5", detail: state.quickCorrect.map { "\($0)/5" } ?? "2 min",
                      symbol: "bolt.fill", done: state.quickCorrect != nil, action: onQuick)
                habit(title: "Word", detail: state.wordSeen ? "Learned" : "1 min",
                      symbol: "text.book.closed.fill", done: state.wordSeen, action: onWord)
            }
            if let onMindScore {
                Button {
                    PhonePlayHaptics.tap()
                    onMindScore()
                } label: {
                    Label("Your Mind Score", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.cyan)
                }
                .buttonStyle(PhonePlayPressStyle())
            }
        }
        .phonePlaySurfaceCard(padding: 14)
    }

    private func habit(title: String, detail: String, symbol: String, done: Bool,
                       action: @escaping () -> Void) -> some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(done ? PhonePlayDesign.green : .white)
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                .fill(done ? PhonePlayDesign.green.opacity(0.14) : PhonePlayDesign.surface2))
        }
        .buttonStyle(PhonePlayPressStyle())
        .accessibilityLabel("\(title), \(done ? "done" : detail)")
    }
}

// MARK: Stats and small print

struct PhoneStatsSheet: View {
    let today: PhoneTodayState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Streaks") {
                    row("Mind Gym", value: today.mindGymStreak > 0 ? "\(today.mindGymStreak) days" : "Not started")
                    row("Quick 5", value: today.quickStreak > 0 ? "\(today.quickStreak) days" : "Not started")
                    row("Quick 5 best", value: DailyStore.bestStreak > 0 ? "\(DailyStore.bestStreak) days" : "None yet")
                }
                Section("Arcade bests") {
                    row("Tap the Lights", value: PocketArcadeStore.bestLights > 0 ? "\(PocketArcadeStore.bestLights)" : "None yet")
                    row("Number Rush", value: PocketArcadeStore.bestRush > 0
                        ? PocketArcadeStore.rushText(PocketArcadeStore.bestRush) : "None yet")
                    row("2048", value: PocketArcadeStore.bestTiles > 0 ? "\(PocketArcadeStore.bestTiles)" : "None yet")
                }
                Section("About") {
                    Text("Phone games work offline. No TV or Wi-Fi needed.")
                    Text("Some trivia questions come from Open Trivia DB (opentdb.com), licensed CC BY-SA 4.0.")
                    Text(BuildStamp.displayString)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Your stats")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
}
