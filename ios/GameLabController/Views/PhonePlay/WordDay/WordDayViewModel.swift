import AVFoundation
import SwiftUI

// MARK: - Word of the Day
//
// One word a day from a bundled list of 365, the same word on every phone
// for the same date. Like the Daily Brain Challenge it is seeded from the
// date key ("2026-10-06"), never the clock: the list is shuffled once per
// 365-day cycle with a seeded generator and the day number picks the
// slot, so no word repeats within a cycle. The word is spoken with the
// phone's own voice (AVSpeechSynthesizer), so it works offline.

struct WordDayEntry: Identifiable, Equatable {
    let word: String
    let partOfSpeech: String
    let meaning: String
    let example: String
    let origin: String

    var id: String { word }
}

enum WordDayList {

    static let all: [WordDayEntry] = partOne + partTwo + partThree

    static func entry(_ word: String, _ partOfSpeech: String, _ meaning: String,
                      _ example: String, _ origin: String) -> WordDayEntry {
        WordDayEntry(word: word, partOfSpeech: partOfSpeech, meaning: meaning,
                     example: example, origin: origin)
    }

    private static let fallback = WordDayEntry(
        word: "serendipity", partOfSpeech: "noun",
        meaning: "Finding something good or useful by happy accident.",
        example: "It was pure serendipity that we met.",
        origin: "Coined in 1754 by Horace Walpole.")

    /// Whole days since 1 January 1970 for a "YYYY-MM-DD" key, counted in
    /// UTC so daylight saving can never shift it.
    static func dayNumber(for key: String) -> Int {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return 0 }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        guard let date = calendar.date(from: components) else { return 0 }
        return Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// The word for a date key: identical on every phone.
    static func word(for key: String) -> WordDayEntry {
        let words = all
        let count = words.count
        guard count > 0 else { return fallback }
        let day = dayNumber(for: key)
        // Floor division, so dates before 1970 still land in range.
        let cycle = day >= 0 ? day / count : (day - count + 1) / count
        let slot = ((day % count) + count) % count
        var rng = PhonePlaySeededRandom(text: "aurora-word-v1-cycle-\(cycle)")
        let order = rng.shuffled(Array(0..<count))
        let index = order.indices.contains(slot) ? order[slot] : slot
        return words.indices.contains(index) ? words[index] : fallback
    }

    private static let challenges: [String] = [
        "Use %@ in a conversation before lunch.",
        "Text a friend a sentence with %@ in it.",
        "Teach %@ to someone in your family tonight.",
        "Slip %@ into a sentence at dinner without anyone noticing.",
        "Write a one-line story that uses %@.",
        "Use %@ to describe something you see today.",
        "Ask someone if they know what %@ means, then tell them.",
        "Use %@ in a message to the family group.",
        "Find something today that you could describe with %@, and say it out loud.",
        "Use %@ twice today: once seriously, once as a joke.",
    ]

    /// Today's "use it" challenge, also seeded by date.
    static func challenge(for key: String, word: String) -> String {
        var rng = PhonePlaySeededRandom(text: "aurora-word-challenge-v1-" + key)
        let template = rng.pick(challenges) ?? "Use %@ today."
        return template.replacingOccurrences(of: "%@", with: "'\(word)'")
    }
}

// MARK: - Remembered progress

enum WordDayStore {
    private static let seenKey = "phoneplay_word_seen_date"
    private static let usedKey = "phoneplay_word_used_dates"

    static func markSeen(_ key: String) {
        UserDefaults.standard.set(key, forKey: seenKey)
    }

    static func seen(_ key: String) -> Bool {
        UserDefaults.standard.string(forKey: seenKey) == key
    }

    static var usedDates: [String] {
        UserDefaults.standard.stringArray(forKey: usedKey) ?? []
    }

    static func used(_ key: String) -> Bool {
        usedDates.contains(key)
    }

    static func markUsed(_ key: String) {
        var dates = usedDates
        guard !dates.contains(key) else { return }
        dates.append(key)
        if dates.count > 1000 { dates.removeFirst(dates.count - 1000) }
        UserDefaults.standard.set(dates, forKey: usedKey)
    }
}

// MARK: - View model

@MainActor
final class WordDayViewModel: ObservableObject {

    let todayKey: String
    let today: WordDayEntry
    let yesterday: WordDayEntry
    let challenge: String

    @Published private(set) var usedToday: Bool
    @Published private(set) var totalUsed: Int
    /// Bumped on every spoken line, to animate the speaker icons.
    @Published private(set) var spoken: Int = 0

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionActive: Bool = false

    init() {
        let now = Date()
        let key = DailyBrain.dateKey(for: now)
        let before = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterdayKey = DailyBrain.dateKey(for: before)
        let word = WordDayList.word(for: key)
        todayKey = key
        today = word
        yesterday = WordDayList.word(for: yesterdayKey)
        challenge = WordDayList.challenge(for: key, word: word.word)
        usedToday = WordDayStore.used(key)
        totalUsed = WordDayStore.usedDates.count
        WordDayStore.markSeen(key)
    }

    // MARK: - Speech

    func sayWord(slowly: Bool = false) {
        speak(today.word, rate: slowly ? 0.32 : 0.45)
    }

    func sayExample() {
        speak(today.example, rate: 0.48)
    }

    func sayYesterday() {
        speak(yesterday.word, rate: 0.45)
    }

    private func speak(_ text: String, rate: Float) {
        activateSession()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        // AVSpeechUtteranceDefaultSpeechRate is 0.5; a touch slower is clearer.
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))
        utterance.preUtteranceDelay = 0.05
        synthesizer.speak(utterance)
        spoken += 1
        PhonePlayHaptics.tap()
    }

    /// Plays through the ring/silent switch, like any spoken-audio app,
    /// and ducks other audio while speaking.
    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            // Speech still works on the default session.
        }
    }

    // MARK: - Challenge

    func markUsed() {
        guard !usedToday else { return }
        WordDayStore.markUsed(todayKey)
        usedToday = true
        totalUsed = WordDayStore.usedDates.count
        PhonePlayHaptics.success()
    }

    func shutdown() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
    }
}
