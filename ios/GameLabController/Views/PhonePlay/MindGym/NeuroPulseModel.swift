import Foundation

// MARK: - NeuroPulse: the daily ten-step brain workout (Mind Gym)
//
// Server side: games/neuropulse.py. The phone grades its own answers (each
// step carries `answer` and `accepts`) so a session plays with no signal at
// all; the server rates the session when the results arrive.
//
// Everything here is parsed out of untyped JSON (`[String: Any]`), the same
// way the TV-game controllers read `privateData`: the server's `visual` is a
// different shape for every task kind, so a defensive read is both simpler
// and safer than one Codable type with ten optional faces. The same models
// serialise straight back to JSON, which is how a session is cached for
// offline play and how a finished session is queued for a later POST.

// MARK: - Untyped JSON helpers

/// Reads the shapes NeuroPulse sends. Numbers arrive as `NSNumber`, so an
/// int field may bridge as `Int` or `Double`; both are accepted.
enum NeuroJSON {
    static func int(_ value: Any?, _ fallback: Int = 0) -> Int {
        if let n = value as? Int { return n }
        if let d = value as? Double { return Int(d.rounded()) }
        if let s = value as? String, let n = Int(s) { return n }
        return fallback
    }

    static func bool(_ value: Any?, _ fallback: Bool = false) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? Int { return n != 0 }
        return fallback
    }

    static func string(_ value: Any?, _ fallback: String = "") -> String {
        value as? String ?? fallback
    }

    static func ints(_ value: Any?) -> [Int] {
        guard let raw = value as? [Any] else { return [] }
        return raw.map { NeuroJSON.int($0) }
    }

    static func strings(_ value: Any?) -> [String] {
        guard let raw = value as? [Any] else { return [] }
        return raw.compactMap { $0 as? String }
    }

    static func dicts(_ value: Any?) -> [[String: Any]] {
        guard let raw = value as? [Any] else { return [] }
        return raw.compactMap { $0 as? [String: Any] }
    }

    static func intMap(_ value: Any?) -> [String: Int] {
        guard let raw = value as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (key, item) in raw { out[key] = NeuroJSON.int(item) }
        return out
    }

    static func stringMap(_ value: Any?) -> [String: String] {
        guard let raw = value as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (key, item) in raw {
            if let text = item as? String { out[key] = text }
        }
        return out
    }

    /// `[[x, y], ...]` (the rotation puzzle's cells).
    static func pairs(_ value: Any?) -> [[Int]] {
        guard let raw = value as? [Any] else { return [] }
        var out: [[Int]] = []
        for item in raw {
            let pair = NeuroJSON.ints(item)
            if pair.count >= 2 { out.append([pair[0], pair[1]]) }
        }
        return out
    }

    /// `[[[x, y], ...], ...]` (the four rotation answer shapes).
    static func shapes(_ value: Any?) -> [[[Int]]] {
        guard let raw = value as? [Any] else { return [] }
        return raw.map { NeuroJSON.pairs($0) }
    }

    static func data(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object)
    }

    static func dict(_ data: Data?) -> [String: Any]? {
        guard let data, !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }
}

// MARK: - Disciplines

/// The five rating tracks (`DISCIPLINES` in games/neuropulse.py). Kept as
/// plain strings, because the server also sends its own display names.
enum NeuroDiscipline {
    static let all: [String] = ["logic", "math", "memory", "pattern", "zen"]

    /// Used until the server's `names` map arrives (offline on a fresh install).
    static let fallbackNames: [String: String] = [
        "logic": "Logic",
        "math": "Number Speed",
        "memory": "Memory",
        "pattern": "Patterns",
        "zen": "Calm Focus",
    ]

    static func name(_ key: String, names: [String: String]) -> String {
        names[key] ?? fallbackNames[key] ?? key.capitalized
    }

    static func symbol(_ key: String) -> String {
        switch key {
        case "logic":   return "puzzlepiece.extension.fill"
        case "math":    return "plus.forwardslash.minus"
        case "memory":  return "square.grid.3x3.fill"
        case "pattern": return "chart.line.uptrend.xyaxis"
        case "zen":     return "wind"
        default:        return "brain.head.profile"
        }
    }
}

// MARK: - Input styles

/// How one step is answered (`inputStyle` on the server).
enum NeuroInputStyle: String, Equatable {
    case choice
    case number
    case grid
    case breathe
    case reflect

    /// Anything a newer server adds falls back to four tappable options.
    init(server: String) {
        self = NeuroInputStyle(rawValue: server.lowercased()) ?? .choice
    }

    /// Breathing and the sensory reset are completion-only.
    var isGraded: Bool {
        switch self {
        case .choice, .number, .grid: return true
        case .breathe, .reflect:      return false
        }
    }
}

// MARK: - Visual payload

/// The per-kind drawing data. Every field is optional in the wire format,
/// so each one has a harmless default and the views check what they need.
struct NeuroVisual: Equatable {
    // flash
    var flashDigits: [Int] = []
    var reversed: Bool = false
    // nback
    var flashLetters: [String] = []
    // flash / nback / grid
    var flashMs: Int = 0
    // grid
    var rows: Int = 0
    var cols: Int = 0
    var cells: [Int] = []
    // dead reckoning: the dot's start cell and the moves in words. Nothing is
    // lit (`cells` is empty); `start` is optional because cell 0 is a real
    // place to start.
    var start: Int? = nil
    var moves: [String] = []
    // stroop
    var word: String = ""
    var ink: String = ""
    var askInk: Bool = true
    // breathing
    var pattern: [Int] = []
    var cycles: Int = 0
    var labels: [String] = []
    // sensory
    var seconds: Int = 0
    // rotation (games/brain_puzzles.py)
    var target: [[Int]] = []
    var choices: [[[Int]]] = []

    static let empty = NeuroVisual()

    init() {}

    init(json: [String: Any]?) {
        guard let json else { return }
        flashDigits = NeuroJSON.ints(json["flashDigits"])
        reversed = NeuroJSON.bool(json["reversed"])
        flashLetters = NeuroJSON.strings(json["flashLetters"])
        flashMs = NeuroJSON.int(json["flashMs"])
        rows = NeuroJSON.int(json["rows"])
        cols = NeuroJSON.int(json["cols"])
        cells = NeuroJSON.ints(json["cells"])
        if json["start"] != nil { start = NeuroJSON.int(json["start"]) }
        moves = NeuroJSON.strings(json["moves"])
        word = NeuroJSON.string(json["word"])
        ink = NeuroJSON.string(json["ink"]).lowercased()
        askInk = NeuroJSON.bool(json["askInk"], true)
        pattern = NeuroJSON.ints(json["pattern"])
        cycles = NeuroJSON.int(json["cycles"])
        labels = NeuroJSON.strings(json["labels"])
        seconds = NeuroJSON.int(json["seconds"])
        target = NeuroJSON.pairs(json["target"])
        choices = NeuroJSON.shapes(json["choices"])
    }

    /// Back to JSON, for the offline session cache.
    var json: [String: Any] {
        var out: [String: Any] = [:]
        if !flashDigits.isEmpty { out["flashDigits"] = flashDigits }
        if reversed { out["reversed"] = true }
        if !flashLetters.isEmpty { out["flashLetters"] = flashLetters }
        if flashMs > 0 { out["flashMs"] = flashMs }
        if rows > 0 { out["rows"] = rows }
        if cols > 0 { out["cols"] = cols }
        if !cells.isEmpty { out["cells"] = cells }
        if let start { out["start"] = start }
        if !moves.isEmpty { out["moves"] = moves }
        if !word.isEmpty { out["word"] = word }
        if !ink.isEmpty { out["ink"] = ink }
        if !word.isEmpty || !ink.isEmpty { out["askInk"] = askInk }
        if !pattern.isEmpty { out["pattern"] = pattern }
        if cycles > 0 { out["cycles"] = cycles }
        if !labels.isEmpty { out["labels"] = labels }
        if seconds > 0 { out["seconds"] = seconds }
        if !target.isEmpty { out["target"] = target }
        if !choices.isEmpty { out["choices"] = choices }
        return out
    }

    var isEmpty: Bool { json.isEmpty }

    /// The breathing pattern as [in, hold, out, hold], always four entries.
    var breathPattern: [Int] {
        guard pattern.count >= 4 else { return [4, 4, 4, 4] }
        return Array(pattern.prefix(4)).map { max(1, $0) }
    }

    var breathLabels: [String] {
        guard labels.count >= 4 else { return ["Breathe in", "Hold", "Breathe out", "Hold"] }
        return Array(labels.prefix(4))
    }
}

// MARK: - One step

struct NeuroStep: Identifiable, Equatable {
    let index: Int
    let discipline: String
    let kind: String
    let skill: String
    let level: Int
    let prompt: String
    let spoken: String
    let answer: String
    let accepts: [String]
    let options: [String]
    let inputStyle: NeuroInputStyle
    let visual: NeuroVisual
    let hint: String
    let explain: String
    let eloTarget: Int
    let targetResponseMs: Int

    var id: Int { index }

    init(index: Int, discipline: String, kind: String, skill: String, level: Int,
         prompt: String, spoken: String = "", answer: String, accepts: [String] = [],
         options: [String] = [], inputStyle: NeuroInputStyle, visual: NeuroVisual = .empty,
         hint: String = "", explain: String = "", eloTarget: Int = 0,
         targetResponseMs: Int = 0) {
        self.index = index
        self.discipline = discipline
        self.kind = kind
        self.skill = skill
        self.level = max(1, min(10, level))
        self.prompt = prompt
        self.spoken = spoken.isEmpty ? prompt : spoken
        self.answer = answer
        self.accepts = accepts
        self.options = options
        self.inputStyle = inputStyle
        self.visual = visual
        self.hint = hint
        self.explain = explain
        self.eloTarget = eloTarget > 0 ? eloTarget : NeuroScoring.eloTarget(forLevel: level)
        self.targetResponseMs = targetResponseMs > 0
            ? targetResponseMs
            : NeuroScoring.targetResponseMs(discipline: discipline, level: level)
    }

    init?(json: [String: Any], fallbackIndex: Int) {
        let discipline = NeuroJSON.string(json["discipline"])
        let style = NeuroInputStyle(server: NeuroJSON.string(json["inputStyle"], "choice"))
        let prompt = NeuroJSON.string(json["prompt"])
        guard !discipline.isEmpty, !prompt.isEmpty else { return nil }
        let level = NeuroJSON.int(json["level"], 1)
        self.init(index: NeuroJSON.int(json["index"], fallbackIndex),
                  discipline: discipline,
                  kind: NeuroJSON.string(json["kind"]),
                  skill: NeuroJSON.string(json["skill"],
                                          NeuroDiscipline.fallbackNames[discipline] ?? ""),
                  level: level,
                  prompt: prompt,
                  spoken: NeuroJSON.string(json["spoken"]),
                  answer: NeuroJSON.string(json["answer"]),
                  accepts: NeuroJSON.strings(json["accepts"]),
                  options: NeuroJSON.strings(json["options"]),
                  inputStyle: style,
                  visual: NeuroVisual(json: json["visual"] as? [String: Any]),
                  hint: NeuroJSON.string(json["hint"]),
                  explain: NeuroJSON.string(json["explain"]),
                  eloTarget: NeuroJSON.int(json["eloTarget"]),
                  targetResponseMs: NeuroJSON.int(json["targetResponseMs"]))
    }

    var json: [String: Any] {
        var out: [String: Any] = [
            "index": index,
            "discipline": discipline,
            "kind": kind,
            "skill": skill,
            "level": level,
            "prompt": prompt,
            "spoken": spoken,
            "answer": answer,
            "accepts": accepts,
            "inputStyle": inputStyle.rawValue,
            "hint": hint,
            "explain": explain,
            "eloTarget": eloTarget,
            "targetResponseMs": targetResponseMs,
        ]
        if !options.isEmpty { out["options"] = options }
        let drawing = visual.json
        if !drawing.isEmpty { out["visual"] = drawing }
        return out
    }

    /// Breathing and the sensory reset score but are never rated.
    var isGraded: Bool {
        !NeuroScoring.ungradedKinds.contains(kind) && inputStyle.isGraded
    }

    /// How many cells a grid answer wants tapped.
    var gridAnswerCount: Int {
        NeuroStep.gridIndices(answer).count
    }

    var gridRows: Int { max(1, visual.rows > 0 ? visual.rows : 3) }
    var gridCols: Int { max(1, visual.cols > 0 ? visual.cols : gridRows) }

    // MARK: Grading, on the device

    /// Case- and whitespace-insensitive comparison; a grid answer compares
    /// the set of lit cell indices, so the tap order does not matter.
    func isCorrect(_ given: String) -> Bool {
        guard isGraded else { return false }
        if inputStyle == .grid {
            let mine = NeuroStep.gridIndices(given)
            let theirs = NeuroStep.gridIndices(answer)
            return !theirs.isEmpty && Set(mine) == Set(theirs)
        }
        let key = NeuroStep.key(given)
        guard !key.isEmpty else { return false }
        if NeuroStep.key(answer) == key { return true }
        return accepts.contains { NeuroStep.key($0) == key }
    }

    static func key(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    /// `"2,3,6,8"` to `[2, 3, 6, 8]`.
    static func gridIndices(_ text: String) -> [Int] {
        text.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func gridAnswer(_ cells: Set<Int>) -> String {
        cells.sorted().map(String.init).joined(separator: ",")
    }
}

// MARK: - A day's session

struct NeuroSession: Equatable {
    let date: String
    let seed: Int
    let steps: [NeuroStep]
    let ratings: [String: Int]
    let levels: [String: Int]
    let streak: Int
    let completed: Bool
    let names: [String: String]
    /// True when the phone built this itself because the fetch failed.
    let local: Bool

    init(date: String, seed: Int, steps: [NeuroStep], ratings: [String: Int] = [:],
         levels: [String: Int] = [:], streak: Int = 0, completed: Bool = false,
         names: [String: String] = [:], local: Bool = false) {
        self.date = date
        self.seed = seed
        self.steps = steps
        self.ratings = ratings
        self.levels = levels
        self.streak = streak
        self.completed = completed
        self.names = names
        self.local = local
    }

    init?(json: [String: Any]) {
        let date = NeuroJSON.string(json["date"])
        let rawSteps = NeuroJSON.dicts(json["steps"])
        guard !date.isEmpty, !rawSteps.isEmpty else { return nil }
        var steps: [NeuroStep] = []
        for (i, raw) in rawSteps.enumerated() {
            if let step = NeuroStep(json: raw, fallbackIndex: i) { steps.append(step) }
        }
        guard !steps.isEmpty else { return nil }
        self.init(date: date,
                  seed: NeuroJSON.int(json["seed"]),
                  steps: steps,
                  ratings: NeuroJSON.intMap(json["ratings"]),
                  levels: NeuroJSON.intMap(json["levels"]),
                  streak: NeuroJSON.int(json["streak"]),
                  completed: NeuroJSON.bool(json["completed"]),
                  names: NeuroJSON.stringMap(json["names"]),
                  local: NeuroJSON.bool(json["local"]))
    }

    var json: [String: Any] {
        [
            "date": date,
            "seed": seed,
            "steps": steps.map { $0.json },
            "ratings": ratings,
            "levels": levels,
            "streak": streak,
            "completed": completed,
            "names": names,
            "local": local,
        ]
    }

    func displayName(_ key: String) -> String {
        NeuroDiscipline.name(key, names: names)
    }

    func level(_ key: String) -> Int {
        if let level = levels[key] { return max(1, min(10, level)) }
        if let rating = ratings[key] { return NeuroScoring.level(forRating: Double(rating)) }
        return 3
    }
}

// MARK: - One answered step

struct NeuroAnswer: Equatable {
    let index: Int
    let discipline: String
    let kind: String
    let level: Int
    let eloTarget: Int
    let targetResponseMs: Int
    let responseMs: Int
    let correct: Bool
    let completed: Bool

    init(index: Int, discipline: String, kind: String, level: Int, eloTarget: Int,
         targetResponseMs: Int, responseMs: Int, correct: Bool, completed: Bool) {
        self.index = index
        self.discipline = discipline
        self.kind = kind
        self.level = level
        self.eloTarget = eloTarget
        self.targetResponseMs = targetResponseMs
        self.responseMs = responseMs
        self.correct = correct
        self.completed = completed
    }

    init?(json: [String: Any]) {
        let discipline = NeuroJSON.string(json["discipline"])
        guard !discipline.isEmpty else { return nil }
        self.init(index: NeuroJSON.int(json["index"]),
                  discipline: discipline,
                  kind: NeuroJSON.string(json["kind"]),
                  level: NeuroJSON.int(json["level"], 1),
                  eloTarget: NeuroJSON.int(json["eloTarget"]),
                  targetResponseMs: NeuroJSON.int(json["targetResponseMs"]),
                  responseMs: NeuroJSON.int(json["responseMs"]),
                  correct: NeuroJSON.bool(json["correct"]),
                  completed: NeuroJSON.bool(json["completed"], true))
    }

    var json: [String: Any] {
        [
            "index": index,
            "discipline": discipline,
            "kind": kind,
            "level": level,
            "eloTarget": eloTarget,
            "targetResponseMs": targetResponseMs,
            "responseMs": responseMs,
            "correct": correct,
            "completed": completed,
        ]
    }
}

// MARK: - What a finished session is worth

/// The reply from POST /api/neuro/result, or the phone's own estimate of it
/// when that POST could not go out.
struct NeuroSummary: Equatable {
    var date: String = ""
    var pulse: Int = 0
    var correct: Int = 0
    var graded: Int = 0
    var ratings: [String: Int] = [:]
    var before: [String: Int] = [:]
    var deltas: [String: Int] = [:]
    var levels: [String: Int] = [:]
    var best: [String: Int] = [:]
    var streak: Int = 0
    var improvedMost: String = ""
    var alreadyPlayed: Bool = false
    var names: [String: String] = [:]
    /// True while this is the phone's own estimate (no server reply yet).
    var estimated: Bool = false

    init() {}

    init(json: [String: Any], estimated: Bool = false) {
        date = NeuroJSON.string(json["date"])
        pulse = NeuroJSON.int(json["pulse"])
        correct = NeuroJSON.int(json["correct"])
        graded = NeuroJSON.int(json["graded"])
        ratings = NeuroJSON.intMap(json["ratings"])
        before = NeuroJSON.intMap(json["before"])
        deltas = NeuroJSON.intMap(json["deltas"])
        levels = NeuroJSON.intMap(json["levels"])
        best = NeuroJSON.intMap(json["best"])
        streak = NeuroJSON.int(json["streak"])
        improvedMost = NeuroJSON.string(json["improvedMost"])
        alreadyPlayed = NeuroJSON.bool(json["alreadyPlayed"])
        names = NeuroJSON.stringMap(json["names"])
        self.estimated = estimated
    }

    var json: [String: Any] {
        [
            "date": date, "pulse": pulse, "correct": correct, "graded": graded,
            "ratings": ratings, "before": before, "deltas": deltas, "levels": levels,
            "best": best, "streak": streak, "improvedMost": improvedMost,
            "alreadyPlayed": alreadyPlayed, "names": names,
        ]
    }

    func displayName(_ key: String) -> String {
        NeuroDiscipline.name(key, names: names)
    }

    /// The disciplines that moved, biggest gain first.
    var movedDisciplines: [String] {
        NeuroDiscipline.all
            .filter { (deltas[$0] ?? 0) != 0 }
            .sorted { (deltas[$0] ?? 0) > (deltas[$1] ?? 0) }
    }
}

// MARK: - The long-term picture

struct NeuroHistoryDay: Equatable, Identifiable {
    let date: String
    let pulse: Int
    let correct: Int
    let graded: Int
    let seconds: Int
    let mood: Int

    var id: String { date }

    init(json: [String: Any]) {
        date = NeuroJSON.string(json["date"])
        pulse = NeuroJSON.int(json["pulse"])
        correct = NeuroJSON.int(json["correct"])
        graded = NeuroJSON.int(json["graded"])
        seconds = NeuroJSON.int(json["seconds"])
        mood = NeuroJSON.int(json["mood"])
    }

    var json: [String: Any] {
        ["date": date, "pulse": pulse, "correct": correct,
         "graded": graded, "seconds": seconds, "mood": mood]
    }
}

struct NeuroProfile: Equatable {
    var name: String = ""
    var ratings: [String: Int] = [:]
    var levels: [String: Int] = [:]
    var games: [String: Int] = [:]
    var best: [String: Int] = [:]
    var streak: Int = 0
    var lastDate: String = ""
    var zenMinutes: Int = 0
    var names: [String: String] = [:]
    var history: [NeuroHistoryDay] = []

    init() {}

    init(json: [String: Any]) {
        name = NeuroJSON.string(json["name"])
        ratings = NeuroJSON.intMap(json["ratings"])
        levels = NeuroJSON.intMap(json["levels"])
        games = NeuroJSON.intMap(json["games"])
        best = NeuroJSON.intMap(json["best"])
        streak = NeuroJSON.int(json["streak"])
        lastDate = NeuroJSON.string(json["lastDate"])
        zenMinutes = NeuroJSON.int(json["zenMinutes"])
        names = NeuroJSON.stringMap(json["names"])
        history = NeuroJSON.dicts(json["history"]).map { NeuroHistoryDay(json: $0) }
    }

    var json: [String: Any] {
        [
            "name": name, "ratings": ratings, "levels": levels, "games": games,
            "best": best, "streak": streak, "lastDate": lastDate,
            "zenMinutes": zenMinutes, "names": names,
            "history": history.map { $0.json },
        ]
    }

    func displayName(_ key: String) -> String {
        NeuroDiscipline.name(key, names: names)
    }

    func rating(_ key: String) -> Int { ratings[key] ?? NeuroScoring.startRating }
    func bestRating(_ key: String) -> Int { max(best[key] ?? 0, rating(key)) }

    func level(_ key: String) -> Int {
        if let level = levels[key] { return max(1, min(10, level)) }
        return NeuroScoring.level(forRating: Double(rating(key)))
    }

    var isEmpty: Bool { ratings.isEmpty && history.isEmpty }
}

struct NeuroLeaderRow: Equatable, Identifiable {
    let device: String
    let name: String
    let pulse: Int
    let correct: Int
    let streak: Int
    let rank: Int

    var id: String { device.isEmpty ? "\(rank)-\(name)" : device }

    init(json: [String: Any]) {
        device = NeuroJSON.string(json["device"])
        name = NeuroJSON.string(json["name"], "Player")
        pulse = NeuroJSON.int(json["pulse"])
        correct = NeuroJSON.int(json["correct"])
        streak = NeuroJSON.int(json["streak"])
        rank = NeuroJSON.int(json["rank"])
    }

    var isMe: Bool { device == AppConstants.deviceID }
}

// MARK: - Scoring, mirrored from the server

/// The same arithmetic as games/neuropulse.py, so the phone can show a
/// believable pulse score and rating move the moment a session ends, even
/// with no signal. When the POST does land, the server's own numbers
/// replace these.
enum NeuroScoring {
    static let stepCount: Int = 10
    static let gradedSteps: Int = 9

    static let startRating: Int = 1000
    static let minRating: Int = 600
    static let maxRating: Int = 2400

    static let levelBase: Int = 800
    static let levelStep: Int = 160
    static let challengeOffset: Int = -120

    static let speedBonusFraction: Double = 0.6
    static let speedBonus: Double = 0.15
    static let slowDampener: Double = 0.75

    static let stepBasePoints: Int = 60
    static let stepLevelPoints: Int = 40
    static let stepSpeedPoints: Int = 100
    static let zenPoints: Int = 100

    static let ungradedKinds: Set<String> = ["breathing", "sensory"]

    static func level(forRating rating: Double) -> Int {
        let level = 1.0 + (rating + Double(challengeOffset) - Double(levelBase)) / Double(levelStep)
        return max(1, min(10, Int(level.rounded())))
    }

    static func eloTarget(forLevel level: Int) -> Int {
        let clamped = max(1, min(10, level))
        return levelBase + (clamped - 1) * levelStep
    }

    static func targetResponseMs(discipline: String, level: Int) -> Int {
        let clamped = max(1, min(10, level))
        let base: Int
        switch discipline {
        case "math":    base = 7000
        case "memory":  base = 9000
        case "pattern": base = 11000
        case "logic":   base = 13000
        case "zen":     base = 4000
        default:        base = 10000
        }
        return base + (clamped - 1) * 900
    }

    static func expectedScore(rating: Double, target: Double) -> Double {
        1.0 / (1.0 + pow(10.0, (target - rating) / 400.0))
    }

    static func kFactor(gamesPlayed: Int) -> Int {
        let games = max(0, gamesPlayed)
        if games < 10 { return 40 }
        if games < 30 { return 24 }
        return 16
    }

    private static func speedScale(correct: Bool, responseMs: Double, targetMs: Double) -> Double {
        guard correct, targetMs > 0 else { return 1.0 }
        if responseMs <= targetMs * speedBonusFraction { return 1.0 + speedBonus }
        if responseMs > targetMs { return slowDampener }
        return 1.0
    }

    static func rate(rating: Double, gamesPlayed: Int, eloTarget: Double, correct: Bool,
                     responseMs: Double, targetMs: Double) -> Int {
        let expected = expectedScore(rating: rating, target: eloTarget)
        let actual: Double = correct ? 1.0 : 0.0
        var move = Double(kFactor(gamesPlayed: gamesPlayed)) * (actual - expected)
        move *= speedScale(correct: correct, responseMs: responseMs, targetMs: targetMs)
        let fresh = rating + move
        return Int(max(Double(minRating), min(Double(maxRating), fresh)).rounded())
    }

    static func stepPoints(correct: Bool, level: Int, responseMs: Double, targetMs: Double) -> Int {
        guard correct else { return 0 }
        let clamped = max(1, min(10, level))
        var points = Double(stepBasePoints) + Double(stepLevelPoints) * Double(clamped) / 10.0
        if targetMs > 0 {
            let fresh = max(0.0, 1.0 - responseMs / targetMs)
            points += Double(stepSpeedPoints) * fresh
        }
        return Int(points.rounded())
    }

    /// The phone's estimate of what the server will say, from the answers
    /// just given and the last profile it saw.
    static func estimate(date: String, answers: [NeuroAnswer], profile: NeuroProfile,
                         names: [String: String]) -> NeuroSummary {
        var summary = NeuroSummary()
        summary.date = date
        summary.estimated = true
        summary.names = names.isEmpty ? NeuroDiscipline.fallbackNames : names

        var ratings: [String: Int] = [:]
        var games: [String: Int] = [:]
        var best: [String: Int] = [:]
        for key in NeuroDiscipline.all {
            ratings[key] = profile.rating(key)
            games[key] = profile.games[key] ?? 0
            best[key] = profile.bestRating(key)
        }
        summary.before = ratings

        var deltas: [String: Int] = [:]
        for key in NeuroDiscipline.all { deltas[key] = 0 }

        for answer in answers {
            guard NeuroDiscipline.all.contains(answer.discipline) else { continue }
            let targetMs = answer.targetResponseMs > 0
                ? Double(answer.targetResponseMs)
                : Double(targetResponseMs(discipline: answer.discipline, level: answer.level))
            if ungradedKinds.contains(answer.kind) {
                if answer.completed || answer.correct { summary.pulse += zenPoints }
                continue
            }
            summary.graded += 1
            if answer.correct { summary.correct += 1 }
            summary.pulse += stepPoints(correct: answer.correct, level: answer.level,
                                        responseMs: Double(answer.responseMs), targetMs: targetMs)
            let rating = Double(ratings[answer.discipline] ?? startRating)
            let target = answer.eloTarget > 0
                ? Double(answer.eloTarget)
                : Double(eloTarget(forLevel: answer.level))
            let fresh = rate(rating: rating, gamesPlayed: games[answer.discipline] ?? 0,
                             eloTarget: target, correct: answer.correct,
                             responseMs: Double(answer.responseMs), targetMs: targetMs)
            ratings[answer.discipline] = fresh
            games[answer.discipline] = (games[answer.discipline] ?? 0) + 1
            best[answer.discipline] = max(best[answer.discipline] ?? fresh, fresh)
            deltas[answer.discipline] = (deltas[answer.discipline] ?? 0) + (fresh - Int(rating))
        }

        summary.ratings = ratings
        summary.deltas = deltas
        summary.best = best
        var levels: [String: Int] = [:]
        for key in NeuroDiscipline.all {
            levels[key] = level(forRating: Double(ratings[key] ?? startRating))
        }
        summary.levels = levels

        var improved = ""
        var bestGain = 0
        for key in NeuroDiscipline.all where (deltas[key] ?? 0) > bestGain {
            bestGain = deltas[key] ?? 0
            improved = key
        }
        summary.improvedMost = improved
        summary.streak = max(1, profile.lastDate == date ? profile.streak : profile.streak + 1)
        return summary
    }
}
