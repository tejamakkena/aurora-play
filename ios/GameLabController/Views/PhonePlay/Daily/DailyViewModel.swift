import SwiftUI

// MARK: - Daily Brain Challenge
//
// Five seeded puzzles per date, tap one of four answers. Score is 100 per
// right answer plus a small speed bonus. Today's result and the streak
// live in UserDefaults, so the challenge is fully offline; when the
// server is reachable the score is also posted and today's leaderboard
// shown. Any network failure is silent.

struct DailyResult: Equatable {
    let date: String
    let correct: Int
    let seconds: Int
    let score: Int
}

struct DailyLeaderRow: Identifiable {
    let id: Int
    let name: String
    let score: Int
    let seconds: Int?
}

enum DailyStore {
    private static let lastDateKey = "phoneplay_daily_last_date"
    private static let correctKey = "phoneplay_daily_last_correct"
    private static let secondsKey = "phoneplay_daily_last_seconds"
    private static let scoreKey = "phoneplay_daily_last_score"
    private static let streakKey = "phoneplay_daily_streak"
    private static let bestKey = "phoneplay_daily_best_streak"

    static func lastResult() -> DailyResult? {
        let defaults = UserDefaults.standard
        guard let date = defaults.string(forKey: lastDateKey) else { return nil }
        return DailyResult(date: date,
                           correct: defaults.integer(forKey: correctKey),
                           seconds: defaults.integer(forKey: secondsKey),
                           score: defaults.integer(forKey: scoreKey))
    }

    static func result(for date: String) -> DailyResult? {
        guard let last = lastResult(), last.date == date else { return nil }
        return last
    }

    /// The streak as it stands today: it survives until a whole day is missed.
    static func currentStreak(today: String, yesterday: String) -> Int {
        guard let last = lastResult() else { return 0 }
        if last.date == today || last.date == yesterday {
            return UserDefaults.standard.integer(forKey: streakKey)
        }
        return 0
    }

    static var bestStreak: Int {
        UserDefaults.standard.integer(forKey: bestKey)
    }

    /// Saves today's result and returns the new streak.
    @discardableResult
    static func record(_ result: DailyResult, yesterday: String) -> Int {
        let defaults = UserDefaults.standard
        let previous = lastResult()
        var streak = defaults.integer(forKey: streakKey)
        if let previous, previous.date == result.date {
            // Already counted today.
        } else if let previous, previous.date == yesterday {
            streak += 1
        } else {
            streak = 1
        }
        streak = max(1, streak)
        defaults.set(result.date, forKey: lastDateKey)
        defaults.set(result.correct, forKey: correctKey)
        defaults.set(result.seconds, forKey: secondsKey)
        defaults.set(result.score, forKey: scoreKey)
        defaults.set(streak, forKey: streakKey)
        if streak > defaults.integer(forKey: bestKey) {
            defaults.set(streak, forKey: bestKey)
        }
        return streak
    }
}

@MainActor
final class DailyViewModel: ObservableObject {

    enum Stage { case intro, playing, finished }

    @Published private(set) var stage: Stage = .intro
    @Published private(set) var puzzles: [DailyPuzzle] = []
    @Published private(set) var index: Int = 0
    @Published private(set) var selected: Int? = nil
    @Published private(set) var correct: Int = 0
    @Published private(set) var answers: [Bool] = []
    @Published private(set) var startedAt: Date = Date()
    @Published private(set) var result: DailyResult? = nil
    @Published private(set) var streak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var leaderboard: [DailyLeaderRow] = []

    let today: String
    private let yesterday: String
    private var advanceToken: Int = 0
    private var network: Task<Void, Never>? = nil
    private var isActive: Bool = true

    init() {
        let now = Date()
        today = DailyBrain.dateKey(for: now)
        let before = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        yesterday = DailyBrain.dateKey(for: before)
        puzzles = DailyBrain.dailySet(for: today)
        streak = DailyStore.currentStreak(today: today, yesterday: yesterday)
        bestStreak = DailyStore.bestStreak
        if let done = DailyStore.result(for: today) {
            result = done
            stage = .finished
            loadLeaderboard()
        }
    }

    var current: DailyPuzzle? {
        puzzles.indices.contains(index) ? puzzles[index] : nil
    }

    var playedToday: Bool { result != nil }

    // MARK: - Play

    func begin() {
        guard stage == .intro, !playedToday else { return }
        index = 0
        correct = 0
        answers = []
        selected = nil
        startedAt = Date()
        PhonePlayHaptics.thump()
        stage = .playing
    }

    func answer(_ option: Int) {
        guard stage == .playing, selected == nil, let puzzle = current else { return }
        selected = option
        let right = option == puzzle.answerIndex
        answers.append(right)
        if right {
            correct += 1
            PhonePlayHaptics.success()
        } else {
            PhonePlayHaptics.error()
        }
        advanceToken += 1
        let token = advanceToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: right ? 900_000_000 : 1_900_000_000)
            guard let self, self.isActive, token == self.advanceToken else { return }
            self.next()
        }
    }

    private func next() {
        guard stage == .playing else { return }
        if index + 1 < puzzles.count {
            selected = nil
            index += 1
        } else {
            finish()
        }
    }

    private func finish() {
        let seconds = max(1, Int(Date().timeIntervalSince(startedAt).rounded()))
        let bonus = correct > 0 ? max(0, 120 - seconds) : 0
        let done = DailyResult(date: today, correct: correct, seconds: seconds,
                               score: correct * 100 + bonus)
        streak = DailyStore.record(done, yesterday: yesterday)
        bestStreak = DailyStore.bestStreak
        result = done
        selected = nil
        PhonePlayHaptics.success()
        stage = .finished
        postScore(done)
    }

    func shutdown() {
        isActive = false
        advanceToken += 1
        network?.cancel()
    }

    // MARK: - Optional online leaderboard

    private var playerName: String {
        let saved = UserDefaults.standard.string(forKey: "aurora_player_name") ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Player" : trimmed
    }

    private func postScore(_ done: DailyResult) {
        let body: [String: Any] = [
            "device": AppConstants.deviceID,
            "name": playerName,
            "date": done.date,
            "score": done.score,
            "seconds": done.seconds,
        ]
        let url = AppConstants.serverURL.appendingPathComponent("api/daily/score")
        let payload: Data? = try? JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = payload
        let post: URLRequest = request
        network?.cancel()
        network = Task { [weak self] in
            _ = try? await URLSession.shared.data(for: post)
            guard let self, self.isActive, !Task.isCancelled else { return }
            let rows = await DailyViewModel.fetchLeaderboard(date: done.date)
            guard self.isActive else { return }
            self.leaderboard = rows
        }
    }

    private func loadLeaderboard() {
        let date = today
        network?.cancel()
        network = Task { [weak self] in
            let rows = await DailyViewModel.fetchLeaderboard(date: date)
            guard let self, self.isActive else { return }
            self.leaderboard = rows
        }
    }

    nonisolated private static func fetchLeaderboard(date: String) async -> [DailyLeaderRow] {
        var components = URLComponents(
            url: AppConstants.serverURL.appendingPathComponent("api/daily/leaderboard"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let raw: Any = (json as? [String: Any])?["scores"]
            ?? (json as? [String: Any])?["leaderboard"]
            ?? json
        let list: [Any] = raw as? [Any] ?? []
        var rows: [DailyLeaderRow] = []
        for (i, item) in list.enumerated() {
            guard let dict = item as? [String: Any] else { continue }
            let name = (dict["name"] as? String) ?? "Player"
            let score = (dict["score"] as? Int) ?? Int((dict["score"] as? Double) ?? 0)
            let seconds = dict["seconds"] as? Int
            rows.append(DailyLeaderRow(id: i, name: name, score: score, seconds: seconds))
            if rows.count >= 10 { break }
        }
        return rows
    }
}
