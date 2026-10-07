import SwiftUI
import UIKit

// MARK: - Phone Play
//
// Games that run on ONE phone with no TV and no signal: the phone is
// passed around the group (Spy, Mafia, Truth or Dare, Would You Rather,
// Hot Potato, Story Chain), held to a forehead (Heads Up) or played solo
// (Daily Brain Challenge, Word of the Day, Pocket Arcade). Nothing here
// touches the socket or the room; ControllerRootViewModel only creates
// and tears down a PhonePlayViewModel, exactly like Travel Mode.

// MARK: - Design tokens

/// Phone Play shares Travel Mode's dark surfaces and accents, and adds a
/// few louder party colours of its own.
enum PhonePlayDesign {
    static let bg        = TravelDesign.bg
    static let surface   = TravelDesign.surface
    static let surface2  = TravelDesign.surface2
    static let text2     = TravelDesign.text2
    static let text3     = TravelDesign.text3

    static let green     = TravelDesign.primary
    static let cyan      = TravelDesign.info
    static let yellow    = TravelDesign.warning
    static let purple    = TravelDesign.riddle
    static let orange    = Color(hex: "FF8A3D")
    static let red       = Color(hex: "FF4D6D")
    static let pink      = Color(hex: "FF5FC8")
    static let blue      = Color(hex: "4D7CFF")
    static let indigo    = Color(hex: "6C5CFF")

    /// Three radii and no others: a card or panel is 24, a button or a
    /// full-width row is 18, and a chip or inline pill is 14. Anything
    /// smaller belongs to a game piece (a playing card, a board tile) and is
    /// sized from that piece, not from here.
    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 18
    static let chipRadius: CGFloat = 14

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The party springs used throughout Phone Play.
    static let pop: Animation = .spring(response: 0.38, dampingFraction: 0.68)
    static let smooth: Animation = .spring(response: 0.5, dampingFraction: 0.86)
}

// MARK: - Haptics

/// Callable from any context: each one hops to the main actor, where
/// UIKit's feedback generators live, so no call site has to be isolated.
enum PhonePlayHaptics {
    static func tap() { impact(.light) }
    static func thump() { impact(.heavy) }
    static func rigid() { impact(.rigid) }
    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error() { notify(.error) }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    private static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(kind)
        }
    }
}

// MARK: - Games

enum PhonePlayGame: String, CaseIterable, Identifiable {
    case headsUp
    case spy
    case mafia
    case truthOrDare
    case wouldYouRather
    case hotPotato
    case storyChain
    case daily
    case wordOfDay
    case arcade

    var id: String { rawValue }

    /// Solo games sit in their own section of the home grid.
    var isSolo: Bool {
        switch self {
        case .daily, .wordOfDay, .arcade:
            return true
        case .headsUp, .spy, .mafia, .truthOrDare, .wouldYouRather, .hotPotato, .storyChain:
            return false
        }
    }

    var title: String {
        switch self {
        case .headsUp:        return "Heads Up"
        case .spy:            return "Spy"
        case .mafia:          return "Mafia"
        case .truthOrDare:    return "Truth or Dare"
        case .wouldYouRather: return "Would You Rather"
        case .hotPotato:      return "Hot Potato"
        case .storyChain:     return "Story Chain"
        case .daily:          return "Daily Brain"
        case .wordOfDay:      return "Word of the Day"
        case .arcade:         return "Pocket Arcade"
        }
    }

    var blurb: String {
        switch self {
        case .headsUp:        return "Phone on your forehead. Tilt down if you got it."
        case .spy:            return "Everyone knows the place except the spy."
        case .mafia:          return "A narrated night of secrets and a day of votes."
        case .truthOrDare:    return "Spin to pick a player, then truth or dare."
        case .wouldYouRather: return "Two choices, one phone. Pick a side."
        case .hotPotato:      return "Name one and pass before it blows."
        case .storyChain:     return "One silly story, one line each, out loud."
        case .daily:          return "Five fresh puzzles a day. Keep your streak."
        case .wordOfDay:      return "One new word a day. Hear it, then use it."
        case .arcade:         return "Reflex games and 2048. Beat your best."
        }
    }

    var symbol: String {
        switch self {
        case .headsUp:        return "person.fill.questionmark"
        case .spy:            return "binoculars.fill"
        case .mafia:          return "theatermasks.fill"
        case .truthOrDare:    return "flame.fill"
        case .wouldYouRather: return "arrow.left.arrow.right"
        case .hotPotato:      return "timer"
        case .storyChain:     return "text.book.closed.fill"
        case .daily:          return "brain.head.profile"
        case .wordOfDay:      return "textformat.abc"
        case .arcade:         return "gamecontroller.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .headsUp:        return [PhonePlayDesign.orange, PhonePlayDesign.pink]
        case .spy:            return [PhonePlayDesign.indigo, PhonePlayDesign.cyan]
        case .mafia:          return [PhonePlayDesign.red, PhonePlayDesign.purple]
        case .truthOrDare:    return [PhonePlayDesign.pink, PhonePlayDesign.purple]
        case .wouldYouRather: return [PhonePlayDesign.blue, PhonePlayDesign.orange]
        case .hotPotato:      return [PhonePlayDesign.yellow, PhonePlayDesign.red]
        case .storyChain:     return [PhonePlayDesign.indigo, PhonePlayDesign.pink]
        case .daily:          return [PhonePlayDesign.green, PhonePlayDesign.cyan]
        case .wordOfDay:      return [PhonePlayDesign.purple, PhonePlayDesign.blue]
        case .arcade:         return [PhonePlayDesign.cyan, PhonePlayDesign.indigo]
        }
    }

    var players: String {
        switch self {
        case .headsUp:        return "2+ players"
        case .spy:            return "2-12 players"
        case .mafia:          return "5-15 players"
        case .truthOrDare:    return "2-16 players"
        case .wouldYouRather: return "2+ players"
        case .hotPotato:      return "2-12 players"
        case .storyChain:     return "3-10 players"
        case .daily:          return "Solo"
        case .wordOfDay:      return "Solo"
        case .arcade:         return "Solo"
        }
    }
}

// MARK: - Remembered player names

/// Spy, Mafia, Truth or Dare, Hot Potato and Story Chain share one
/// remembered roster, so a group only types its names once per phone.
enum PhonePlayRoster {
    private static let key = "phoneplay_player_names"

    static func load() -> [String] {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        return saved.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func save(_ names: [String]) {
        let clean = names
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        UserDefaults.standard.set(clean, forKey: key)
    }
}

// MARK: - Deterministic random numbers

/// SplitMix64. Seeded generators make the Daily Brain Challenge identical
/// on every phone for a given date. The helpers below never use the
/// standard library's `random(in:using:)`, whose internal algorithm is
/// free to change between OS versions.
struct PhonePlaySeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// A stable seed from text (FNV-1a), unlike `hashValue`, which is
    /// randomised per launch.
    init(text: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z: UInt64 = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform-enough integer in `range` (modulo bias is irrelevant here).
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        guard span > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % span)
    }

    mutating func bool() -> Bool {
        next() % 2 == 0
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[int(0...(items.count - 1))]
    }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var out = items
        guard out.count > 1 else { return out }
        var i = out.count - 1
        while i > 0 {
            let j = int(0...i)
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }
}

// MARK: - No-repeat dealing

/// Hands out items from a pool without repeating any within a session.
/// Items are compared case-insensitively; when every item in the pool has
/// been dealt, the pool starts over.
struct PhonePlayDealer {
    private var used: Set<String> = []

    func remaining(in pool: [String]) -> Int {
        pool.filter { !used.contains(PhonePlayDealer.key($0)) }.count
    }

    mutating func draw(from pool: [String]) -> String? {
        guard !pool.isEmpty else { return nil }
        var fresh = pool.filter { !used.contains(PhonePlayDealer.key($0)) }
        if fresh.isEmpty {
            for item in pool { used.remove(PhonePlayDealer.key(item)) }
            fresh = pool
        }
        guard let pick = fresh.randomElement() else { return nil }
        used.insert(PhonePlayDealer.key(pick))
        return pick
    }

    mutating func reset() {
        used = []
    }

    static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

// MARK: - Fresh AI cards

/// The state of a "Fresh AI cards" button. Failures are silent: the
/// button simply goes back to idle and the bundled cards carry on.
enum PhonePlayAIState: Equatable {
    case idle
    case loading
    case added(Int)
}

enum PhonePlayAIDecks {
    /// Appends the new items that are not already in `pool` (ignoring case
    /// and spacing) and returns how many were added.
    @discardableResult
    static func merge(_ items: [String], into pool: inout [String]) -> Int {
        var seen = Set(pool.map { PhonePlayDealer.key($0) })
        var added = 0
        for raw in items {
            let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let key = PhonePlayDealer.key(text)
            guard text.count >= 2, !seen.contains(key) else { continue }
            seen.insert(key)
            pool.append(text)
            added += 1
        }
        return added
    }
}

// MARK: - Root view model

@MainActor
final class PhonePlayViewModel: ObservableObject {
    @Published private(set) var active: PhonePlayGame? = nil

    @Published private(set) var headsUp: HeadsUpViewModel? = nil
    @Published private(set) var spy: SpyViewModel? = nil
    @Published private(set) var mafia: MafiaViewModel? = nil
    @Published private(set) var daily: DailyViewModel? = nil
    @Published private(set) var truthOrDare: TruthDareViewModel? = nil
    @Published private(set) var wouldYouRather: WouldRatherViewModel? = nil
    @Published private(set) var hotPotato: HotPotatoViewModel? = nil
    @Published private(set) var storyChain: StoryChainViewModel? = nil
    @Published private(set) var wordOfDay: WordDayViewModel? = nil
    @Published private(set) var arcade: PocketArcadeViewModel? = nil

    /// Travel Mode's narrator voice, reused for the Mafia narrator: one
    /// consistent voice for the whole Phone Play session.
    let speech = TravelSpeech()

    func open(_ game: PhonePlayGame) {
        closeGame()
        switch game {
        case .headsUp: headsUp = HeadsUpViewModel()
        case .spy:     spy = SpyViewModel()
        case .mafia:   mafia = MafiaViewModel(speech: speech)
        case .daily:   daily = DailyViewModel()
        case .truthOrDare:    truthOrDare = TruthDareViewModel()
        case .wouldYouRather: wouldYouRather = WouldRatherViewModel()
        case .hotPotato:      hotPotato = HotPotatoViewModel()
        case .storyChain:     storyChain = StoryChainViewModel()
        case .wordOfDay:      wordOfDay = WordDayViewModel()
        case .arcade:         arcade = PocketArcadeViewModel()
        }
        PhonePlayHaptics.tap()
        active = game
    }

    /// Back to the Phone Play grid.
    func closeGame() {
        headsUp?.shutdown()
        spy?.shutdown()
        mafia?.shutdown()
        daily?.shutdown()
        truthOrDare?.shutdown()
        wouldYouRather?.shutdown()
        hotPotato?.shutdown()
        storyChain?.shutdown()
        wordOfDay?.shutdown()
        arcade?.shutdown()
        headsUp = nil
        spy = nil
        mafia = nil
        daily = nil
        truthOrDare = nil
        wouldYouRather = nil
        hotPotato = nil
        storyChain = nil
        wordOfDay = nil
        arcade = nil
        active = nil
    }

    /// Leaving Phone Play altogether.
    func shutdown() {
        closeGame()
        speech.reset()
        speech.deactivateSession()
    }
}
