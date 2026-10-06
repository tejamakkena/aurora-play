import SwiftUI
import UIKit

// MARK: - Phone Play
//
// Games that run on ONE phone with no TV and no signal: the phone is
// passed around the group (Spy, Mafia), held to a forehead (Heads Up) or
// played solo once a day (Daily Brain Challenge). Nothing here touches the
// socket or the room; ControllerRootViewModel only creates and tears down
// a PhonePlayViewModel, exactly like Travel Mode.

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

    static let cardRadius: CGFloat = 24
    static let buttonRadius: CGFloat = 18

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The party springs used throughout Phone Play.
    static let pop: Animation = .spring(response: 0.38, dampingFraction: 0.68)
    static let smooth: Animation = .spring(response: 0.5, dampingFraction: 0.86)
}

// MARK: - Haptics

enum PhonePlayHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func thump() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Games

enum PhonePlayGame: String, CaseIterable, Identifiable {
    case headsUp
    case spy
    case mafia
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headsUp: return "Heads Up"
        case .spy:     return "Spy"
        case .mafia:   return "Mafia"
        case .daily:   return "Daily Brain"
        }
    }

    var blurb: String {
        switch self {
        case .headsUp: return "Phone on your forehead. Tilt down if you got it."
        case .spy:     return "Everyone knows the place except the spy."
        case .mafia:   return "A narrated night of secrets and a day of votes."
        case .daily:   return "Five fresh puzzles a day. Keep your streak."
        }
    }

    var symbol: String {
        switch self {
        case .headsUp: return "person.fill.questionmark"
        case .spy:     return "binoculars.fill"
        case .mafia:   return "theatermasks.fill"
        case .daily:   return "brain.head.profile"
        }
    }

    var colors: [Color] {
        switch self {
        case .headsUp: return [PhonePlayDesign.orange, PhonePlayDesign.pink]
        case .spy:     return [PhonePlayDesign.indigo, PhonePlayDesign.cyan]
        case .mafia:   return [PhonePlayDesign.red, PhonePlayDesign.purple]
        case .daily:   return [PhonePlayDesign.green, PhonePlayDesign.cyan]
        }
    }

    var players: String {
        switch self {
        case .headsUp: return "2+ players"
        case .spy:     return "2-12 players"
        case .mafia:   return "5-15 players"
        case .daily:   return "Solo"
        }
    }
}

/// Grid placeholders for games that are on the way.
struct PhonePlayComingSoon: Identifiable {
    let title: String
    let symbol: String
    let blurb: String

    var id: String { title }

    static let all: [PhonePlayComingSoon] = [
        PhonePlayComingSoon(title: "Truth or Dare", symbol: "flame.fill",
                            blurb: "Family-safe truths and silly dares"),
        PhonePlayComingSoon(title: "Hot Potato", symbol: "timer",
                            blurb: "Answer and pass before it goes off"),
        PhonePlayComingSoon(title: "Would You Rather", symbol: "arrow.left.arrow.right",
                            blurb: "Pick a side and defend it"),
        PhonePlayComingSoon(title: "Word of the Day", symbol: "textformat.abc",
                            blurb: "One new word, every day"),
    ]
}

// MARK: - Remembered player names

/// Spy and Mafia share one remembered roster, so a group only types its
/// names once per phone.
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

// MARK: - Root view model

@MainActor
final class PhonePlayViewModel: ObservableObject {
    @Published private(set) var active: PhonePlayGame? = nil

    @Published private(set) var headsUp: HeadsUpViewModel? = nil
    @Published private(set) var spy: SpyViewModel? = nil
    @Published private(set) var mafia: MafiaViewModel? = nil
    @Published private(set) var daily: DailyViewModel? = nil

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
        headsUp = nil
        spy = nil
        mafia = nil
        daily = nil
        active = nil
    }

    /// Leaving Phone Play altogether.
    func shutdown() {
        closeGame()
        speech.reset()
        speech.deactivateSession()
    }
}
