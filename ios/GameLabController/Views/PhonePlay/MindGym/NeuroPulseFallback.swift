import Foundation

// MARK: - A workout the phone can build on its own
//
// If the daily fetch fails and there is no cached session for today, the
// Mind Gym still opens: these ten steps are built on the phone from the
// generators it already ships with -- the Daily Brain Challenge's seeded
// puzzles (Daily/DailyBrain.swift) and Travel Mode's mental maths
// (Travel/TravelBrain.swift) -- plus three memory tasks and a breathing
// reset in the server's own shapes.
//
// The order of disciplines matches the server's `_GRADED_ORDER`
// (logic, math, memory, pattern, math, memory, pattern, logic, memory)
// with the Zen reset last, so an offline session feels the same as an
// online one. The result is queued and posted on the next launch that
// reaches the server, so nothing is lost.

enum NeuroFallback {

    /// Ten steps for `date`, pitched at the last ratings this phone saw.
    static func session(date: String, profile: NeuroProfile?) -> NeuroSession {
        var rng = PhonePlaySeededRandom(text: "aurora-neuro-v1-" + date)
        let daily = DailyBrain.puzzles(for: date)
        let extra = DailyBrain.puzzles(for: date + "-mindgym")

        func level(_ discipline: String) -> Int {
            guard let profile else { return 3 }
            return profile.level(discipline)
        }

        /// `daily[index]`, falling back to the second seeded set and then
        /// to a generated maths step, so this never traps on an empty array.
        func puzzle(_ index: Int) -> DailyPuzzle? {
            if daily.indices.contains(index) { return daily[index] }
            if extra.indices.contains(index) { return extra[index] }
            return nil
        }

        var steps: [NeuroStep] = []

        func add(_ step: NeuroStep?) {
            guard let step else { return }
            steps.append(step)
        }

        // 0 logic: the Daily Brain line-up puzzle.
        add(choiceStep(index: 0, discipline: "logic", kind: "relative",
                       level: level("logic"), puzzle: puzzle(3)))
        // 1 math: Travel Mode's mental maths, typed on the keypad.
        add(numberStep(index: 1, discipline: "math", kind: "chain",
                       level: level("math")))
        // 2 memory: digits that flash and then have to be tapped back.
        add(flashStep(index: 2, level: level("memory"), rng: &rng))
        // 3 pattern: the Daily Brain sequence.
        add(choiceStep(index: 3, discipline: "pattern", kind: "sequence",
                       level: level("pattern"), puzzle: puzzle(0)))
        // 4 math: the Daily Brain quick-maths puzzle.
        add(choiceStep(index: 4, discipline: "math", kind: "estimate",
                       level: level("math"), puzzle: puzzle(1)))
        // 5 memory: a spatial grid.
        add(gridStep(index: 5, level: level("memory"), rng: &rng))
        // 6 pattern: odd one out.
        add(choiceStep(index: 6, discipline: "pattern", kind: "odd_word",
                       level: level("pattern"), puzzle: puzzle(2)))
        // 7 logic: the calendar hop.
        add(choiceStep(index: 7, discipline: "logic", kind: "calendar",
                       level: level("logic"), puzzle: puzzle(4)))
        // 8 memory: an n-back probe.
        add(nbackStep(index: 8, level: level("memory"), rng: &rng))

        // Any step that could not be built is replaced, so the rail always
        // has its ten dots and the indices stay 0...9.
        var filled: [NeuroStep] = []
        for index in 0..<NeuroScoring.gradedSteps {
            if let step = steps.first(where: { $0.index == index }) {
                filled.append(step)
            } else {
                let discipline = index < fallbackDisciplines.count
                    ? fallbackDisciplines[index] : "math"
                filled.append(numberStep(index: index, discipline: discipline,
                                         kind: discipline == "math" ? "chain" : "sequence",
                                         level: level(discipline)))
            }
        }
        filled.append(breathingStep(index: NeuroScoring.gradedSteps, level: level("zen"),
                                    rng: &rng))

        var ratings: [String: Int] = [:]
        var levels: [String: Int] = [:]
        for key in NeuroDiscipline.all {
            ratings[key] = profile?.rating(key) ?? NeuroScoring.startRating
            levels[key] = level(key)
        }
        let cachedNames: [String: String] = profile?.names ?? [:]
        return NeuroSession(date: date,
                            seed: 0,
                            steps: filled,
                            ratings: ratings,
                            levels: levels,
                            streak: profile?.streak ?? 0,
                            completed: false,
                            names: cachedNames.isEmpty ? NeuroDiscipline.fallbackNames : cachedNames,
                            local: true)
    }

    private static let fallbackDisciplines: [String] = [
        "logic", "math", "memory", "pattern", "math", "memory", "pattern", "logic", "memory",
    ]

    private static let letters: [String] = [
        "A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L",
        "M", "N", "P", "R", "S", "T", "U", "V", "W", "X", "Z",
    ]

    // MARK: Four options, from the Daily Brain Challenge

    private static func choiceStep(index: Int, discipline: String, kind: String,
                                   level: Int, puzzle: DailyPuzzle?) -> NeuroStep? {
        guard let puzzle, !puzzle.options.isEmpty, !puzzle.answer.isEmpty else { return nil }
        return NeuroStep(index: index,
                         discipline: discipline,
                         kind: kind,
                         skill: NeuroDiscipline.fallbackNames[discipline] ?? "",
                         level: level,
                         prompt: puzzle.prompt,
                         answer: puzzle.answer,
                         options: puzzle.options,
                         inputStyle: .choice,
                         hint: "Take it one piece at a time.",
                         explain: puzzle.explain)
    }

    // MARK: A typed number, from Travel Mode

    private static func numberStep(index: Int, discipline: String, kind: String,
                                   level: Int) -> NeuroStep {
        let item = TravelBrain.make(level: level, kindIndex: discipline == "math" ? 1 : 0)
        return NeuroStep(index: index,
                         discipline: discipline,
                         kind: kind,
                         skill: NeuroDiscipline.fallbackNames[discipline] ?? "",
                         level: level,
                         prompt: item.prompt,
                         answer: item.answer,
                         accepts: item.accepts,
                         inputStyle: .number,
                         hint: item.hint,
                         explain: item.fact ?? "")
    }

    // MARK: Memory, in the server's own shapes

    private static func flashStep(index: Int, level: Int,
                                  rng: inout PhonePlaySeededRandom) -> NeuroStep {
        let length = min(4 + (level + 1) / 2, 9)
        var digits: [Int] = []
        for _ in 0..<length { digits.append(rng.int(1...9)) }
        let backwards = level >= 5
        let target: [Int] = backwards ? Array(digits.reversed()) : digits
        let how = backwards ? "backwards" : "in the same order"
        let answer = target.map(String.init).joined()
        var visual = NeuroVisual()
        visual.flashDigits = digits
        visual.flashMs = max(1600, 3200 - level * 120)
        visual.reversed = backwards
        return NeuroStep(index: index,
                         discipline: "memory",
                         kind: "flash",
                         skill: NeuroDiscipline.fallbackNames["memory"] ?? "",
                         level: level,
                         prompt: "Watch the numbers, then tap them \(how).",
                         answer: answer,
                         accepts: [target.map(String.init).joined(separator: " ")],
                         inputStyle: .number,
                         visual: visual,
                         hint: "It starts with \(target.first ?? 0).",
                         explain: how.prefix(1).uppercased() + String(how.dropFirst())
                             + ", it was " + target.map(String.init).joined(separator: " ") + ".")
    }

    private static func gridStep(index: Int, level: Int,
                                 rng: inout PhonePlaySeededRandom) -> NeuroStep {
        let side = level <= 3 ? 3 : (level <= 7 ? 4 : 5)
        let litCount = max(3, min(3 + (level + 1) / 2, side * side - 2))
        var pool: [Int] = Array(0..<(side * side))
        pool = rng.shuffled(pool)
        let cells = Array(pool.prefix(litCount)).sorted()
        var visual = NeuroVisual()
        visual.rows = side
        visual.cols = side
        visual.cells = cells
        visual.flashMs = max(1500, 2800 - level * 110)
        return NeuroStep(index: index,
                         discipline: "memory",
                         kind: "grid",
                         skill: NeuroDiscipline.fallbackNames["memory"] ?? "",
                         level: level,
                         prompt: "Tap the \(litCount) squares that lit up.",
                         answer: cells.map(String.init).joined(separator: ","),
                         inputStyle: .grid,
                         visual: visual,
                         hint: "Remember the shape they made, not each square.",
                         explain: "The lit squares are shown again.")
    }

    private static func nbackStep(index: Int, level: Int,
                                  rng: inout PhonePlaySeededRandom) -> NeuroStep {
        let back = level <= 5 ? 2 : 3
        let length = max(back + 2, min(5 + level / 2, 9))
        var run: [String] = []
        for _ in 0..<length { run.append(rng.pick(letters) ?? "A") }
        let answerIndex = max(0, run.count - 1 - back)
        let answer = run[answerIndex]
        var options: [String] = [answer]
        for letter in run.reversed() where !options.contains(letter) {
            options.append(letter)
            if options.count == 4 { break }
        }
        while options.count < 4 {
            let extra = rng.pick(letters) ?? "Z"
            if !options.contains(extra) { options.append(extra) }
        }
        options = rng.shuffled(options)
        var visual = NeuroVisual()
        visual.flashLetters = run
        visual.flashMs = max(700, 1100 - level * 30)
        let ordinal = back == 2 ? "two" : "three"
        return NeuroStep(index: index,
                         discipline: "memory",
                         kind: "nback",
                         skill: NeuroDiscipline.fallbackNames["memory"] ?? "",
                         level: level,
                         prompt: "Which letter came \(ordinal) before the last one?",
                         answer: answer,
                         options: options,
                         inputStyle: .choice,
                         visual: visual,
                         hint: "Count back from the end of the run.",
                         explain: "The run was " + run.joined(separator: " ")
                             + ", so it was \(answer).")
    }

    // MARK: The Zen reset

    private static func breathingStep(index: Int, level: Int,
                                      rng: inout PhonePlaySeededRandom) -> NeuroStep {
        let patterns: [(String, [Int])] = [
            ("Box breathing", [4, 4, 4, 4]),
            ("Longer out-breath", [4, 2, 6, 2]),
            ("Steady square", [5, 5, 5, 5]),
        ]
        let picked = rng.pick(patterns) ?? patterns[0]
        let total = picked.1.reduce(0, +)
        let cycles = max(2, Int((45.0 / Double(max(1, total))).rounded()))
        let seconds = total * cycles
        var visual = NeuroVisual()
        visual.pattern = picked.1
        visual.cycles = cycles
        visual.labels = ["Breathe in", "Hold", "Breathe out", "Hold"]
        return NeuroStep(index: index,
                         discipline: "zen",
                         kind: "breathing",
                         skill: NeuroDiscipline.fallbackNames["zen"] ?? "",
                         level: level,
                         prompt: "\(picked.0). Follow the circle for \(seconds) seconds.",
                         answer: "",
                         inputStyle: .breathe,
                         visual: visual,
                         hint: "Let your shoulders drop.",
                         explain: "Slow breathing settles a racing mind in about a minute.")
    }
}
