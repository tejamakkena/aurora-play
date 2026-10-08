import Foundation

// MARK: - Mind Gym offline storage
//
// Everything the workout needs to run with no signal lives in
// UserDefaults as plain JSON:
//
//   session   today's ten steps, as fetched (or as the phone built them)
//   progress  the step reached and the answers so far, for a resume
//   done      today's finished summary, for the home card's tick
//   profile   the last ratings/levels/history the server sent
//   pending   finished sessions that could not be posted yet
//
// Nothing here ever throws or blocks: a missing or corrupt value simply
// reads as nil and the workout carries on.

/// A session in progress: the step reached and the answers given so far.
struct NeuroProgress: Equatable {
    let date: String
    var index: Int
    var answers: [NeuroAnswer]
    var seconds: Int
    var zenSeconds: Int

    init(date: String, index: Int = 0, answers: [NeuroAnswer] = [],
         seconds: Int = 0, zenSeconds: Int = 0) {
        self.date = date
        self.index = index
        self.answers = answers
        self.seconds = seconds
        self.zenSeconds = zenSeconds
    }

    init?(json: [String: Any]) {
        let date = NeuroJSON.string(json["date"])
        guard !date.isEmpty else { return nil }
        self.init(date: date,
                  index: NeuroJSON.int(json["index"]),
                  answers: NeuroJSON.dicts(json["answers"]).compactMap { NeuroAnswer(json: $0) },
                  seconds: NeuroJSON.int(json["seconds"]),
                  zenSeconds: NeuroJSON.int(json["zenSeconds"]))
    }

    var json: [String: Any] {
        [
            "date": date,
            "index": index,
            "answers": answers.map { $0.json },
            "seconds": seconds,
            "zenSeconds": zenSeconds,
        ]
    }

    var isStarted: Bool { index > 0 || !answers.isEmpty }
}

enum NeuroStore {
    private static let sessionKey = "neuro_session_json"
    private static let progressKey = "neuro_progress_json"
    private static let doneKey = "neuro_done_json"
    private static let profileKey = "neuro_profile_json"
    private static let pendingKey = "neuro_pending_results"

    /// "YYYY-MM-DD" in the phone's own calendar day, the same key the
    /// Daily Brain Challenge uses.
    static func todayKey(_ now: Date = Date()) -> String {
        DailyBrain.dateKey(for: now)
    }

    // MARK: Session

    static func session(for date: String) -> NeuroSession? {
        guard let json = NeuroJSON.dict(UserDefaults.standard.data(forKey: sessionKey)),
              let session = NeuroSession(json: json), session.date == date else { return nil }
        return session
    }

    static func saveSession(_ session: NeuroSession) {
        guard let data = NeuroJSON.data(session.json) else { return }
        UserDefaults.standard.set(data, forKey: sessionKey)
    }

    // MARK: Resume

    static func progress(for date: String) -> NeuroProgress? {
        guard let json = NeuroJSON.dict(UserDefaults.standard.data(forKey: progressKey)),
              let progress = NeuroProgress(json: json), progress.date == date else { return nil }
        return progress
    }

    static func saveProgress(_ progress: NeuroProgress) {
        guard let data = NeuroJSON.data(progress.json) else { return }
        UserDefaults.standard.set(data, forKey: progressKey)
    }

    static func clearProgress() {
        UserDefaults.standard.removeObject(forKey: progressKey)
    }

    // MARK: Today's result

    static func done(for date: String) -> NeuroSummary? {
        guard let json = NeuroJSON.dict(UserDefaults.standard.data(forKey: doneKey)) else { return nil }
        let summary = NeuroSummary(json: json)
        return summary.date == date ? summary : nil
    }

    static func saveDone(_ summary: NeuroSummary) {
        guard !summary.date.isEmpty, let data = NeuroJSON.data(summary.json) else { return }
        UserDefaults.standard.set(data, forKey: doneKey)
    }

    // MARK: Profile

    static func profile() -> NeuroProfile? {
        guard let json = NeuroJSON.dict(UserDefaults.standard.data(forKey: profileKey)) else { return nil }
        let profile = NeuroProfile(json: json)
        return profile.isEmpty ? nil : profile
    }

    static func saveProfile(_ profile: NeuroProfile) {
        guard let data = NeuroJSON.data(profile.json) else { return }
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    // MARK: Results waiting to be posted

    static func pending() -> [[String: Any]] {
        guard let data = UserDefaults.standard.data(forKey: pendingKey),
              let object = try? JSONSerialization.jsonObject(with: data),
              let list = object as? [Any] else { return [] }
        return list.compactMap { $0 as? [String: Any] }
    }

    static func queue(_ body: [String: Any]) {
        var all = pending()
        // One entry per date: a replay overwrites the queued attempt.
        let date = NeuroJSON.string(body["date"])
        all.removeAll { NeuroJSON.string($0["date"]) == date }
        all.append(body)
        if all.count > 14 { all = Array(all.suffix(14)) }
        savePending(all)
    }

    static func savePending(_ bodies: [[String: Any]]) {
        guard JSONSerialization.isValidJSONObject(bodies),
              let data = try? JSONSerialization.data(withJSONObject: bodies) else { return }
        UserDefaults.standard.set(data, forKey: pendingKey)
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    // MARK: The player's name, shared with the rest of the app

    static var playerName: String {
        let saved = UserDefaults.standard.string(forKey: "aurora_player_name") ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Player" : trimmed
    }
}
