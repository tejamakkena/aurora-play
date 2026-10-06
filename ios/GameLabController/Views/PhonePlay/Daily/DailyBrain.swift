import Foundation

// MARK: - Daily Brain Challenge puzzles
//
// Five puzzles a day, identical on every phone for the same date: the
// generator is seeded from the date ("2026-10-06"), never from the clock
// or the system random source. The puzzle families are TravelBrain's
// (sequences, quick maths, logic line-ups, calendar hops) re-expressed
// with a seeded generator and four tap-to-answer options, plus an
// odd-one-out word round. TravelBrain itself is untouched: Travel Mode
// keeps its own fresh-every-time puzzles.

struct DailyPuzzle: Identifiable {
    let id: Int
    let kind: String
    let symbol: String
    let prompt: String
    let options: [String]
    let answerIndex: Int
    let explain: String

    var answer: String {
        options.indices.contains(answerIndex) ? options[answerIndex] : ""
    }
}

enum DailyBrain {

    static let puzzlesPerDay: Int = 5

    /// "YYYY-MM-DD" in the phone's own calendar day.
    static func dateKey(for date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        let y = parts.year ?? 2000
        let m = parts.month ?? 1
        let d = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func puzzles(for key: String) -> [DailyPuzzle] {
        var rng = PhonePlaySeededRandom(text: "aurora-daily-v1-" + key)
        // Difficulty climbs through the set; the order of kinds is fixed so
        // every day has the same rhythm.
        return [
            sequence(id: 0, level: 3, rng: &rng),
            math(id: 1, level: 4, rng: &rng),
            oddOneOut(id: 2, rng: &rng),
            logic(id: 3, level: 6, rng: &rng),
            calendar(id: 4, level: 7, rng: &rng),
        ]
    }

    // MARK: - Options

    /// Four options with the answer at a seeded position.
    private static func build(id: Int, kind: String, symbol: String, prompt: String,
                              answer: String, distractors: [String], explain: String,
                              rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        var wrong: [String] = []
        for d in distractors where d != answer && !wrong.contains(d) {
            wrong.append(d)
            if wrong.count == 3 { break }
        }
        var filler = 1
        while wrong.count < 3 {
            let extra = "\(answer) (\(filler))"
            if !wrong.contains(extra) { wrong.append(extra) }
            filler += 1
        }
        var options = rng.shuffled(wrong)
        let slot = rng.int(0...3)
        options.insert(answer, at: slot)
        return DailyPuzzle(id: id, kind: kind, symbol: symbol, prompt: prompt,
                           options: options, answerIndex: slot, explain: explain)
    }

    /// Plausible wrong numbers near `answer`.
    private static func numberDistractors(_ answer: Int, step: Int,
                                          rng: inout PhonePlaySeededRandom) -> [String] {
        let s = max(1, abs(step))
        var pool: [Int] = [answer + 1, answer - 1, answer + 2, answer - 2,
                           answer + s, answer - s, answer + 10, answer - 10]
        if s > 2 { pool.append(answer + s / 2) }
        pool = pool.filter { $0 != answer && $0 >= 0 }
        var seen: [Int] = []
        for n in rng.shuffled(pool) where !seen.contains(n) {
            seen.append(n)
        }
        return seen.map { String($0) }
    }

    // MARK: - Sequences

    private static func sequence(id: Int, level: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        var seq: [Int] = []
        var why = ""
        var step = 1
        switch rng.int(0...5) {
        case 0:
            step = rng.int(2...(3 + level))
            let start = step * 5 + rng.int(5...(20 + level * 5))
            seq = (0..<5).map { start - step * $0 }
            why = "take away \(step) each time"
        case 1:
            let start = rng.int(1...4)
            let r = rng.int(2...3)
            var x = start
            for _ in 0..<5 { seq.append(x); x *= r }
            step = seq[3]
            why = "multiply by \(r) each time"
        case 2:
            let a = rng.int(3...(4 + level))
            let b = rng.int(1...(a - 1))
            var x = rng.int(1...10)
            for i in 0..<5 { seq.append(x); x += (i % 2 == 0) ? a : -b }
            step = a
            why = "add \(a), then take away \(b), and repeat"
        case 3:
            var x = rng.int(1...10)
            var gap = rng.int(1...3)
            for _ in 0..<5 { seq.append(x); x += gap; gap += 1 }
            step = gap
            why = "the gap grows by one each time"
        case 4:
            let k = rng.int(1...(4 + level / 2))
            seq = (0..<5).map { ($0 + k) * ($0 + k) }
            step = 2 * (k + 4)
            why = "they are square numbers"
        default:
            let start = rng.int(1...(5 + level * 3))
            step = rng.int(2...(3 + level))
            seq = (0..<5).map { start + step * $0 }
            why = "add \(step) each time"
        }
        let shown = seq.prefix(4).map { String($0) }.joined(separator: ", ")
        let answer = seq[4]
        let wrong: [String] = numberDistractors(answer, step: step, rng: &rng)
        return build(id: id, kind: "Pattern", symbol: "chart.line.uptrend.xyaxis",
                     prompt: "What comes next?\n\(shown), ...",
                     answer: String(answer),
                     distractors: wrong,
                     explain: "It's \(answer): \(why).", rng: &rng)
    }

    // MARK: - Quick maths

    private static func math(id: Int, level: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        var text = ""
        var answer = 0
        var step = 1
        switch rng.int(0...3) {
        case 0:
            let a = rng.int(3...12), b = rng.int(3...12), c = rng.int(2...20)
            text = "\(a) x \(b) + \(c)"
            answer = a * b + c
            step = a
        case 1:
            let base: Int = rng.pick([20, 40, 60, 80, 120, 200]) ?? 40
            let n = base * rng.int(1...3)
            text = "half of \(n)"
            answer = n / 2
            step = 5
        case 2:
            let base: Int = rng.pick([10, 20, 50]) ?? 10
            let n = base * rng.int(2...10)
            text = "10% of \(n)"
            answer = n / 10
            step = 5
        default:
            let big = rng.int(40...99), a = rng.int(3...12), b = rng.int(3...12)
            text = "\(big) - \(a) - \(b)"
            answer = big - a - b
            step = a
        }
        _ = level
        let wrong: [String] = numberDistractors(answer, step: step, rng: &rng)
        return build(id: id, kind: "Quick maths", symbol: "plus.forwardslash.minus",
                     prompt: "What is \(text)?",
                     answer: String(answer),
                     distractors: wrong,
                     explain: "\(text) = \(answer).", rng: &rng)
    }

    // MARK: - Odd one out

    private static let groups: [(String, [String])] = [
        ("fruits", ["Mango", "Banana", "Guava", "Papaya", "Apple", "Grapes", "Orange"]),
        ("vehicles", ["Bus", "Train", "Scooter", "Truck", "Bicycle", "Auto", "Tractor"]),
        ("colours", ["Red", "Blue", "Green", "Yellow", "Purple", "Orange", "Pink"]),
        ("animals", ["Tiger", "Elephant", "Monkey", "Giraffe", "Zebra", "Camel", "Deer"]),
        ("planets", ["Mars", "Venus", "Jupiter", "Saturn", "Mercury", "Neptune", "Earth"]),
        ("instruments", ["Guitar", "Tabla", "Flute", "Violin", "Veena", "Drums", "Piano"]),
        ("birds", ["Parrot", "Sparrow", "Eagle", "Crow", "Peacock", "Pigeon", "Owl"]),
        ("vegetables", ["Carrot", "Potato", "Onion", "Brinjal", "Okra", "Cabbage", "Spinach"]),
        ("sports", ["Cricket", "Football", "Tennis", "Hockey", "Kabaddi", "Badminton", "Chess"]),
        ("body parts", ["Elbow", "Knee", "Ankle", "Wrist", "Shoulder", "Thumb", "Ear"]),
    ]

    private static func oddOneOut(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let indices: [Int] = Array(0..<groups.count)
        let picked = rng.shuffled(indices)
        let main = groups[picked[0]]
        var outlierGroup = groups[picked[1]]
        // Words that sit in two groups ("Orange") would make it unfair.
        var odd = rng.pick(outlierGroup.1) ?? "Chair"
        var tries = 0
        while main.1.contains(odd) && tries < 10 {
            outlierGroup = groups[picked[2 + tries % (picked.count - 2)]]
            odd = rng.pick(outlierGroup.1) ?? "Chair"
            tries += 1
        }
        let members = Array(rng.shuffled(main.1.filter { $0 != odd }).prefix(3))
        return build(id: id, kind: "Odd one out", symbol: "circle.grid.cross.fill",
                     prompt: "Which one does not belong?",
                     answer: odd, distractors: members,
                     explain: "\(members.joined(separator: ", ")) are all \(main.0). \(odd) is one of the \(outlierGroup.0).",
                     rng: &rng)
    }

    // MARK: - Logic

    private static let names = ["Asha", "Ben", "Chen", "Divya", "Eli", "Farah", "Gopi", "Hana",
                                "Ira", "Jay", "Kiran", "Leo", "Maya", "Nikhil", "Omar", "Priya",
                                "Ravi", "Sara", "Tara", "Vik"]
    private static let relations: [(String, String, String, String)] = [
        ("taller", "shorter", "tallest", "shortest"),
        ("faster", "slower", "fastest", "slowest"),
        ("older", "younger", "oldest", "youngest"),
    ]

    private static func logic(id: Int, level: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let n = level <= 3 ? 3 : (level <= 6 ? 4 : 5)
        let people = Array(rng.shuffled(names).prefix(n))   // people[0] is "the most"
        let rel = rng.pick(relations) ?? relations[0]
        var facts: [String] = []
        for i in 0..<(n - 1) {
            let a = people[i], b = people[i + 1]
            facts.append(rng.bool() ? "\(a) is \(rel.0) than \(b)." : "\(b) is \(rel.1) than \(a).")
        }
        facts = rng.shuffled(facts)
        let askMost = rng.bool()
        let answer = askMost ? people[0] : people[n - 1]
        let question = askMost ? rel.2 : rel.3
        let others: [String] = rng.shuffled(people.filter { $0 != answer })
        return build(id: id, kind: "Logic", symbol: "person.3.sequence.fill",
                     prompt: facts.joined(separator: " ") + "\nWho is the \(question)?",
                     answer: answer, distractors: others,
                     explain: "In order: \(people.joined(separator: ", ")). So \(answer) is the \(question).",
                     rng: &rng)
    }

    // MARK: - Calendar

    private static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                               "Saturday", "Sunday"]

    private static func calendar(id: Int, level: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let start = rng.int(0...6)
        var text = ""
        var steps = 0
        if level <= 6 || rng.bool() {
            let k = rng.int(8...20)
            text = "If today is \(days[start]), what day will it be in \(k) days?"
            steps = k
        } else {
            let k = rng.int(2...5)
            text = "If the day before yesterday was \(days[start]), what day will it be \(k) days after tomorrow?"
            steps = k + 3
        }
        let answer = days[(start + steps) % 7]
        let near = [days[(start + steps + 1) % 7], days[(start + steps + 6) % 7],
                    days[(start + steps + 2) % 7], days[start]]
        return build(id: id, kind: "Calendar", symbol: "calendar",
                     prompt: text, answer: answer, distractors: near,
                     explain: "Counting \(steps) days on from \(days[start]) lands on \(answer).",
                     rng: &rng)
    }
}
