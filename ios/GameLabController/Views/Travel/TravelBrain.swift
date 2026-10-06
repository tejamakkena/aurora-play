import Foundation

// MARK: - Brain Teasers (offline generator)
//
// Travel Mode's third style. These puzzles are GENERATED on the phone, so
// they work with no signal, never repeat, and their answers are always
// right. Difficulty is a dial (`level` 1-10) that the quizmaster turns up
// after right answers and down after misses. The server's
// games/brain_puzzles.py is the same design; it also serves analogies and
// odd-one-out words (fetchBrainLibraryPuzzles) when the phone is online.

enum TravelBrain {

    /// One puzzle at `level`, cycling through the generated kinds.
    static func make(level: Int, kindIndex: Int) -> TravelItem {
        let lvl = max(1, min(10, level))
        switch kindIndex % 5 {
        case 0: return sequence(lvl)
        case 1: return math(lvl)
        case 2: return memory(lvl)
        case 3: return logic(lvl)
        default: return calendar(lvl)
        }
    }

    // MARK: Number words (so "fourteen" and "14" both count)

    private static let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven",
                               "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
                               "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    private static let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty",
                               "seventy", "eighty", "ninety"]

    static func words(_ n: Int) -> String {
        if n < 0 { return "minus " + words(-n) }
        if n < 20 { return ones[n] }
        if n < 100 { return tens[n / 10] + (n % 10 == 0 ? "" : " " + ones[n % 10]) }
        if n < 1000 {
            let rest = n % 100
            return ones[n / 100] + " hundred" + (rest == 0 ? "" : " " + words(rest))
        }
        let rest = n % 1000
        return words(n / 1000) + " thousand" + (rest == 0 ? "" : " " + words(rest))
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    private static func numberAccepts(_ n: Int) -> [String] {
        let w = words(n)
        var out = [w]
        if w.contains(" hundred ") { out.append(w.replacingOccurrences(of: " hundred ", with: " hundred and ")) }
        return out
    }

    private static func item(_ prompt: String, answer: String, accepts: [String] = [],
                             hint: String, explain: String, spoken: String? = nil) -> TravelItem {
        TravelItem(kind: .brain, prompt: prompt, answer: answer, accepts: accepts,
                   hint: hint, fact: explain, spoken: spoken)
    }

    // MARK: Sequences

    private static func sequence(_ level: Int) -> TravelItem {
        var families: [Int] = [0, 1]                  // add, subtract
        if level >= 3 { families += [2, 3] }          // multiply, alternating
        if level >= 5 { families += [4, 5] }          // growing gaps, squares
        if level >= 7 { families.append(6) }          // fibonacci
        var seq: [Int] = []
        var why = ""
        switch families.randomElement() ?? 0 {
        case 1:
            let step = Int.random(in: 2...(3 + level))
            let start = step * 5 + Int.random(in: 5...(20 + level * 5))
            seq = (0..<5).map { start - step * $0 }
            why = "take away \(step) each time"
        case 2:
            let start = Int.random(in: 1...4)
            let r = level < 6 ? Int.random(in: 2...3) : Int.random(in: 2...4)
            var x = start
            for _ in 0..<5 { seq.append(x); x *= r }
            why = "multiply by \(r) each time"
        case 3:
            let a = Int.random(in: 3...(4 + level))
            let b = Int.random(in: 1...(a - 1))
            var x = Int.random(in: 1...10)
            for i in 0..<5 { seq.append(x); x += (i % 2 == 0) ? a : -b }
            why = "add \(a), then take away \(b), and repeat"
        case 4:
            var x = Int.random(in: 1...10)
            var gap = Int.random(in: 1...3)
            for _ in 0..<5 { seq.append(x); x += gap; gap += 1 }
            why = "the gap grows by one each time"
        case 5:
            let k = Int.random(in: 1...(4 + level / 2))
            seq = (0..<5).map { ($0 + k) * ($0 + k) }
            why = "they are square numbers"
        case 6:
            seq = [Int.random(in: 1...4), Int.random(in: 1...5)]
            while seq.count < 5 { seq.append(seq[seq.count - 1] + seq[seq.count - 2]) }
            why = "each number is the two before it added together"
        default:
            let start = Int.random(in: 1...(5 + level * 3))
            let step = Int.random(in: 2...(3 + level))
            seq = (0..<5).map { start + step * $0 }
            why = "add \(step) each time"
        }
        let shown = seq.prefix(4).map(String.init).joined(separator: ", ")
        let answer = seq[4]
        return item("What comes next? \(shown) ...", answer: String(answer),
                    accepts: numberAccepts(answer),
                    hint: level <= 3 ? "Look at how much it changes each time."
                                     : "Look at the gap between each pair of numbers.",
                    explain: "It's \(answer): \(why).")
    }

    // MARK: Mental maths

    private static func math(_ level: Int) -> TravelItem {
        var text = ""
        var answer = 0
        if level <= 2 {
            let a = Int.random(in: 2...(9 + level * 5)), b = Int.random(in: 2...(9 + level * 5))
            text = "\(a) plus \(b)"; answer = a + b
        } else if level <= 4 {
            let a = Int.random(in: 3...12), b = Int.random(in: 3...12)
            if Bool.random() {
                text = "\(a) times \(b)"; answer = a * b
            } else {
                let big = Int.random(in: 30...99)
                text = "\(big) minus \(a + b)"; answer = big - a - b
            }
        } else if level <= 7 {
            let a = Int.random(in: 3...12), b = Int.random(in: 3...12), c = Int.random(in: 2...20)
            switch Int.random(in: 0...2) {
            case 0:
                text = "\(a) times \(b), plus \(c)"; answer = a * b + c
            case 1:
                let n = ([20, 40, 60, 80, 120, 200].randomElement() ?? 40) * Int.random(in: 1...3)
                text = "half of \(n)"; answer = n / 2
            default:
                let n = ([10, 20, 50].randomElement() ?? 10) * Int.random(in: 2...10)
                text = "ten percent of \(n)"; answer = n / 10
            }
        } else {
            let a = Int.random(in: 11...25), b = Int.random(in: 3...9), c = Int.random(in: 2...30)
            if Bool.random() {
                text = "\(a) times \(b), minus \(c)"; answer = a * b - c
            } else {
                let n = [40, 60, 80, 120, 200, 300].randomElement() ?? 80
                text = "a quarter of \(n), plus \(c)"; answer = n / 4 + c
            }
        }
        return item("Quick maths: what is \(text)?", answer: String(answer),
                    accepts: numberAccepts(answer),
                    hint: "Break it into smaller steps.",
                    explain: "\(capitalized(text)) is \(answer).")
    }

    // MARK: Memory

    private static func memory(_ level: Int) -> TravelItem {
        let length = min(3 + (level + 1) / 2, 8)
        let digits: [Int] = (0..<length).map { _ in Int.random(in: 1...9) }
        let backwards = level >= 4
        let target: [Int] = backwards ? Array(digits.reversed()) : digits
        let how = backwards ? "backwards" : "in the same order"
        let answer = target.map(String.init).joined(separator: " ")
        // The digits are only SPOKEN: the screen must not give them away.
        let spoken = "Memory test. Listen carefully, then say them \(how). "
            + digits.map { words($0) }.joined(separator: "... ") + "."
        return item("Memory test: say the numbers \(how).", answer: answer,
                    accepts: [target.map(String.init).joined(),
                              target.map(String.init).joined(separator: ", "),
                              target.map { words($0) }.joined(separator: " ")],
                    hint: "It starts with \(target[0]).",
                    explain: "\(capitalized(how)), it was \(answer).",
                    spoken: spoken)
    }

    // MARK: Logic

    private static let names = ["Asha", "Ben", "Chen", "Divya", "Eli", "Farah", "Gopi", "Hana",
                                "Ira", "Jay", "Kiran", "Leo", "Maya", "Nikhil", "Omar", "Priya",
                                "Ravi", "Sara", "Tara", "Vik"]
    private static let relations: [(String, String, String, String)] = [
        ("taller", "shorter", "tallest", "shortest"),
        ("faster", "slower", "fastest", "slowest"),
        ("older", "younger", "oldest", "youngest"),
    ]

    private static func logic(_ level: Int) -> TravelItem {
        let n = level <= 3 ? 3 : (level <= 6 ? 4 : 5)
        let people = Array(names.shuffled().prefix(n))   // people[0] is "the most"
        let rel = relations.randomElement() ?? relations[0]
        var facts: [String] = []
        for i in 0..<(n - 1) {
            let a = people[i], b = people[i + 1]
            facts.append(Bool.random() ? "\(a) is \(rel.0) than \(b)" : "\(b) is \(rel.1) than \(a)")
        }
        facts.shuffle()
        let askMost = Bool.random()
        let answer = askMost ? people[0] : people[n - 1]
        let question = askMost ? rel.2 : rel.3
        return item(facts.joined(separator: ". ") + ". Who is the \(question)?",
                    answer: answer,
                    hint: "Line them up from \(rel.2) to \(rel.3).",
                    explain: "In order: \(people.joined(separator: ", ")). So \(answer) is the \(question).")
    }

    // MARK: Calendar

    private static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                               "Saturday", "Sunday"]

    private static func calendar(_ level: Int) -> TravelItem {
        let start = Int.random(in: 0..<7)
        var text = ""
        var steps = 0
        if level <= 6 {
            let k = level <= 3 ? Int.random(in: 2...6) : Int.random(in: 8...20)
            text = "If today is \(days[start]), what day will it be in \(k) days?"
            steps = k
        } else {
            let k = Int.random(in: 2...5)
            text = "If the day before yesterday was \(days[start]), what day will it be \(k) days after tomorrow?"
            steps = k + 3
        }
        let answer = days[(start + steps) % 7]
        return item(text, answer: answer,
                    hint: "Every 7 days the week starts again.",
                    explain: "Counting \(steps) days on from \(days[start]) lands on \(answer).")
    }
}
