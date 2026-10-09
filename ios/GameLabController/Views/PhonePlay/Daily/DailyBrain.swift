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
        switch rng.int(0...7) {
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
        case 6:
            // Two patterns woven together: odd places climb by a, even places by b.
            let a = rng.int(2...6), b = rng.int(2...9)
            let first = rng.int(1...9), second = rng.int(10...30)
            seq = [first, second, first + a, second + b, first + 2 * a]
            step = a
            why = "two patterns are mixed: every other number adds \(a), the rest add \(b)"
        case 7:
            let a = rng.int(1...5), b = rng.int(2...6)
            seq = [a, b, a + b, a + 2 * b, 2 * a + 3 * b]
            step = b
            why = "each number is the sum of the two before it"
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
        switch rng.int(0...9) {
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
        case 3:
            let big = rng.int(40...99), a = rng.int(3...12), b = rng.int(3...12)
            text = "\(big) - \(a) - \(b)"
            answer = big - a - b
            step = a
        case 4:
            let n = rng.int(12...60), k = rng.int(5...30)
            text = "double \(n), then add \(k)"
            answer = 2 * n + k
            step = k
        case 5:
            let n = (rng.pick([40, 80, 120, 160, 200, 400]) ?? 80)
            text = "25% of \(n)"
            answer = n / 4
            step = 5
        case 6:
            let a = rng.int(11...19), b = rng.int(3...9)
            text = "\(a) x \(b)"
            answer = a * b
            step = b
        case 7:
            let pick: (Int, Int, Int) = rng.pick([(2, 3, 90), (3, 4, 80), (1, 5, 150), (3, 5, 100),
                                                   (2, 5, 60), (3, 4, 120), (2, 3, 60)]) ?? (2, 3, 90)
            text = "\(pick.0)/\(pick.1) of \(pick.2)"
            answer = pick.2 / pick.1 * pick.0
            step = pick.2 / pick.1
        case 8:
            let m = rng.int(10...40), d = rng.int(2...9)
            let shown: [Int] = rng.shuffled([m - d, m, m + d])
            text = "the average of \(shown[0]), \(shown[1]) and \(shown[2])"
            answer = m
            step = d
        default:
            let a = rng.int(6...15)
            text = "\(a) squared"
            answer = a * a
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
        ("heavier", "lighter", "heaviest", "lightest"),
        ("stronger", "weaker", "strongest", "weakest"),
        ("louder", "quieter", "loudest", "quietest"),
        ("richer", "poorer", "richest", "poorest"),
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
        // Most, least, the one in the middle, or second place: four different
        // questions about the same kind of line-up.
        var answer = people[0]
        var question = "Who is the \(rel.2)?"
        var phrase = "the \(rel.2)"
        switch rng.int(0...3) {
        case 0:
            break
        case 1:
            answer = people[n - 1]
            question = "Who is the \(rel.3)?"
            phrase = "the \(rel.3)"
        case 2:
            if n % 2 == 1 {
                answer = people[n / 2]
                question = "Who is in the middle?"
                phrase = "in the middle"
            } else {
                answer = people[1]
                question = "Who is second \(rel.2)?"
                phrase = "second \(rel.2)"
            }
        default:
            answer = people[n - 2]
            question = "Who is second \(rel.3)?"
            phrase = "second \(rel.3)"
        }
        let others: [String] = rng.shuffled(people.filter { $0 != answer })
        return build(id: id, kind: "Logic", symbol: "person.3.sequence.fill",
                     prompt: facts.joined(separator: " ") + "\n" + question,
                     answer: answer, distractors: others,
                     explain: "In order, from most to least: \(people.joined(separator: ", ")). So \(answer) is \(phrase).",
                     rng: &rng)
    }

    // MARK: - Calendar

    private static let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                               "Saturday", "Sunday"]

    private static let months = ["January", "February", "March", "April", "May", "June", "July",
                                 "August", "September", "October", "November", "December"]

    private static func calendar(id: Int, level: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        if rng.int(0...2) == 0 {
            let from = rng.int(0...11)
            let k = rng.int(3...17)
            let answer = months[(from + k) % 12]
            let near = [months[(from + k + 1) % 12], months[(from + k + 11) % 12],
                        months[(from + k + 2) % 12], months[from]]
            return build(id: id, kind: "Calendar", symbol: "calendar",
                         prompt: "Which month comes \(k) months after \(months[from])?",
                         answer: answer, distractors: near,
                         explain: "Counting \(k) months on from \(months[from]) lands on \(answer).",
                         rng: &rng)
        }
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

    // MARK: - The daily set
    //
    // Thirteen families of puzzle, five a day. The day's five are picked from
    // the families that did NOT appear yesterday, so two days in a row never
    // share a type, and they are put in order from easiest to hardest.

    enum Family: Int, CaseIterable {
        case sequence, math, oddWord, oddNumber, logic, calendar, letters
        case anagram, time, money, analogy, facts, units

        var rank: Int {
            switch self {
            case .letters, .facts:           return 1
            case .oddWord, .anagram, .money, .units: return 2
            case .math, .oddNumber, .time, .analogy: return 3
            case .sequence:                  return 4
            case .logic, .calendar:          return 5
            }
        }
    }

    static func dailySet(for key: String) -> [DailyPuzzle] {
        let chosen = families(for: key, depth: 3)
        var rng = PhonePlaySeededRandom(text: "aurora-daily-v2-" + key)
        return chosen.enumerated().map { pair in
            make(pair.element, id: pair.offset, level: 3 + pair.offset, rng: &rng)
        }
    }

    private static func families(for key: String, depth: Int) -> [Family] {
        var rng = PhonePlaySeededRandom(text: "aurora-daily-pick-" + key)
        var pool: [Family] = rng.shuffled(Family.allCases)
        if depth > 0, let prev = previousKey(of: key) {
            let yesterday = Set(families(for: prev, depth: depth - 1).map { $0.rawValue })
            pool = pool.filter { !yesterday.contains($0.rawValue) }
        }
        let five: [Family] = Array(pool.prefix(puzzlesPerDay))
        return five.sorted { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.rawValue < rhs.rawValue
        }
    }

    private static func previousKey(of key: String) -> String? {
        let parts: [Int] = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1],
                                                            day: parts[2], hour: 12)),
              let before = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: before)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    private static func make(_ family: Family, id: Int, level: Int,
                             rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        switch family {
        case .sequence:   return sequence(id: id, level: level, rng: &rng)
        case .math:       return math(id: id, level: level, rng: &rng)
        case .oddWord:    return oddOneOut(id: id, rng: &rng)
        case .oddNumber:  return oddNumber(id: id, rng: &rng)
        case .logic:      return logic(id: id, level: level, rng: &rng)
        case .calendar:   return calendar(id: id, level: level, rng: &rng)
        case .letters:    return letterPuzzle(id: id, rng: &rng)
        case .anagram:    return anagram(id: id, rng: &rng)
        case .time:       return clockPuzzle(id: id, rng: &rng)
        case .money:      return moneyPuzzle(id: id, rng: &rng)
        case .analogy:    return analogy(id: id, rng: &rng)
        case .facts:      return quickFact(id: id, rng: &rng)
        case .units:      return unitsPuzzle(id: id, rng: &rng)
        }
    }

    // MARK: - Odd number out

    private static func oddNumber(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let primes: [Int] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
        let squares: [Int] = [1, 4, 9, 16, 25, 36, 49, 64, 81, 100]
        var members: [Int] = []
        var odd = 0
        var why = ""
        switch rng.int(0...3) {
        case 0:
            members = Array(rng.shuffled([4, 8, 12, 16, 20, 24, 30, 34, 42, 56]).prefix(3))
            odd = rng.pick([7, 9, 15, 21, 25, 33, 45]) ?? 9
            why = "\(members.map { String($0) }.joined(separator: ", ")) are even. \(odd) is odd."
        case 1:
            let k = rng.int(3...6)
            members = (0..<3).map { _ in k * rng.int(2...12) }
            while Set(members).count < 3 { members = (0..<3).map { _ in k * rng.int(2...12) } }
            odd = k * rng.int(2...12) + rng.int(1...(k - 1))
            why = "\(members.map { String($0) }.joined(separator: ", ")) are all in the \(k) times table. \(odd) is not."
        case 2:
            members = Array(rng.shuffled(primes).prefix(3))
            odd = rng.pick([9, 15, 21, 25, 27, 33, 35, 39, 49]) ?? 15
            why = "\(members.map { String($0) }.joined(separator: ", ")) are prime. \(odd) is not."
        default:
            members = Array(rng.shuffled(squares).prefix(3))
            odd = rng.pick([8, 12, 20, 30, 50, 70]) ?? 20
            why = "\(members.map { String($0) }.joined(separator: ", ")) are square numbers. \(odd) is not."
        }
        return build(id: id, kind: "Odd number out", symbol: "circle.grid.cross.fill",
                     prompt: "Which number does not belong?",
                     answer: String(odd), distractors: members.map { String($0) },
                     explain: why, rng: &rng)
    }

    // MARK: - Letters

    private static let alphabet: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

    private static func letterPuzzle(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        var prompt = ""
        var index = 0
        var why = ""
        switch rng.int(0...2) {
        case 0:
            let step = rng.int(2...3)
            let start = rng.int(0...(25 - step * 4))
            let shown = (0..<4).map { alphabet[start + step * $0] }.joined(separator: ", ")
            index = start + step * 4
            prompt = "What letter comes next?\n\(shown), ..."
            why = "the letters jump \(step) places each time"
        case 1:
            let from = rng.int(0...19), k = rng.int(2...5)
            index = from + k
            prompt = "Which letter is \(k) places after \(alphabet[from])?"
            why = "\(k) places after \(alphabet[from])"
        default:
            let from = rng.int(6...25), k = rng.int(2...5)
            index = from - k
            prompt = "Which letter is \(k) places before \(alphabet[from])?"
            why = "\(k) places before \(alphabet[from])"
        }
        let near: [String] = [index + 1, index - 1, index + 2, index - 2]
            .filter { $0 >= 0 && $0 < 26 }.map { alphabet[$0] }
        return build(id: id, kind: "Letters", symbol: "textformat.abc",
                     prompt: prompt, answer: alphabet[index], distractors: near,
                     explain: "It's \(alphabet[index]): \(why).", rng: &rng)
    }

    // MARK: - Anagrams

    private static let anagramWords: [String] = [
        "PLANET", "ORANGE", "GARDEN", "CASTLE", "SILVER", "BRIDGE", "MARKET", "WINTER",
        "FLOWER", "JUNGLE", "CANDLE", "ISLAND", "ROCKET", "SPRING", "TEMPLE", "FOREST",
        "MIRROR", "BASKET", "PENCIL", "DOCTOR", "SCHOOL", "FRIEND", "WINDOW", "PILLOW",
        "DINNER", "YELLOW", "TICKET", "GUITAR", "BUTTER", "CARPET",
    ]

    private static func anagram(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let word: String = rng.pick(anagramWords) ?? "PLANET"
        var letters: [Character] = Array(word)
        var tries = 0
        repeat {
            letters = rng.shuffled(Array(word))
            tries += 1
        } while String(letters) == word && tries < 10
        // Look-alikes: the real word with one letter swapped, plus another real word.
        var wrong: [String] = []
        for _ in 0..<2 {
            var chars: [Character] = Array(word)
            let at = rng.int(0...(chars.count - 1))
            let replacement: Character = Array("AEIOURSTLNMDPB")[rng.int(0...13)]
            chars[at] = replacement == chars[at] ? "X" : replacement
            wrong.append(String(chars))
        }
        wrong.append(rng.pick(anagramWords.filter { $0 != word }) ?? "GARDEN")
        return build(id: id, kind: "Word scramble", symbol: "textformat.abc",
                     prompt: "Unscramble these letters:\n\(String(letters))",
                     answer: word, distractors: wrong,
                     explain: "\(String(letters)) unscrambles to \(word).", rng: &rng)
    }

    // MARK: - Clock

    private static func clockText(_ minutes: Int) -> String {
        let total = ((minutes % 1440) + 1440) % 1440
        let hour24 = total / 60
        let minute = total % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour12, minute, hour24 >= 12 ? "pm" : "am")
    }

    private static func clockPuzzle(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let startHour = rng.int(1...8)
        let startMinute: Int = rng.pick([0, 15, 30, 45]) ?? 0
        let hours = rng.int(1...3)
        let extra: Int = rng.pick([15, 30, 45]) ?? 30
        let start = (startHour + 12) * 60 + startMinute
        let end = start + hours * 60 + extra
        let thing: String = rng.pick(["A film", "A cricket match", "A train journey", "A class"]) ?? "A film"
        let near: [String] = [end + 15, end - 15, end + 60, end - 30, end + 30].map { clockText($0) }
        return build(id: id, kind: "Time", symbol: "clock.fill",
                     prompt: "\(thing) starts at \(clockText(start)) and lasts \(hours) hour\(hours == 1 ? "" : "s") \(extra) minutes. What time does it end?",
                     answer: clockText(end), distractors: near,
                     explain: "\(clockText(start)) plus \(hours) h \(extra) min is \(clockText(end)).",
                     rng: &rng)
    }

    // MARK: - Money

    private static func moneyPuzzle(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let price: Int = rng.pick([12, 15, 18, 24, 35, 45, 60, 75]) ?? 15
        let qty = rng.int(2...5)
        let cost = price * qty
        let paid: Int = [100, 200, 500].first { $0 > cost } ?? 500
        let item: String = rng.pick(["notebook", "toy car", "packet of biscuits", "box of pencils", "mango"]) ?? "notebook"
        let change = paid - cost
        let wrong: [String] = numberDistractors(change, step: price, rng: &rng)
        return build(id: id, kind: "Money", symbol: "indianrupeesign.circle.fill",
                     prompt: "A \(item) costs \u{20B9}\(price). You buy \(qty) and pay with \u{20B9}\(paid). How much change do you get?",
                     answer: "\u{20B9}\(change)", distractors: wrong.map { "\u{20B9}" + $0 },
                     explain: "\(qty) x \(price) = \(cost), and \(paid) - \(cost) = \(change).", rng: &rng)
    }

    // MARK: - Analogies

    private static let analogies: [(String, String, String, String, [String])] = [
        ("Bird", "Nest", "Bee", "Hive", ["Honey", "Wing", "Flower"]),
        ("Pen", "Write", "Knife", "Cut", ["Sharp", "Eat", "Kitchen"]),
        ("Day", "Night", "Hot", "Cold", ["Warm", "Sun", "Summer"]),
        ("Fish", "Water", "Bird", "Air", ["Nest", "Tree", "Feather"]),
        ("Eye", "See", "Ear", "Hear", ["Listen", "Sound", "Head"]),
        ("Teacher", "School", "Doctor", "Hospital", ["Medicine", "Nurse", "Patient"]),
        ("Cow", "Milk", "Hen", "Eggs", ["Feathers", "Chicken", "Farm"]),
        ("Up", "Down", "Left", "Right", ["Side", "Turn", "Back"]),
        ("Sun", "Day", "Moon", "Night", ["Stars", "Dark", "Sky"]),
        ("Painter", "Brush", "Writer", "Pen", ["Book", "Paper", "Story"]),
        ("Puppy", "Dog", "Kitten", "Cat", ["Mouse", "Lion", "Pet"]),
        ("Seed", "Plant", "Egg", "Chick", ["Nest", "Hen", "Yolk"]),
        ("Finger", "Hand", "Toe", "Foot", ["Shoe", "Leg", "Nail"]),
        ("Page", "Book", "Brick", "Wall", ["House", "Red", "Cement"]),
        ("Bark", "Dog", "Meow", "Cat", ["Kitten", "Purr", "Mouse"]),
        ("Pilot", "Plane", "Driver", "Bus", ["Road", "Ticket", "Wheel"]),
        ("Hungry", "Eat", "Thirsty", "Drink", ["Water", "Glass", "Hot"]),
        ("Winter", "Cold", "Summer", "Hot", ["Sun", "Rain", "Holiday"]),
    ]

    private static func analogy(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let item = rng.pick(analogies) ?? analogies[0]
        return build(id: id, kind: "Analogy", symbol: "arrow.left.arrow.right",
                     prompt: "\(item.0) is to \(item.1) as \(item.2) is to ...?",
                     answer: item.3, distractors: item.4,
                     explain: "\(item.0) goes with \(item.1) the way \(item.2) goes with \(item.3).",
                     rng: &rng)
    }

    // MARK: - Quick facts and units

    private static let facts: [(String, String, [String])] = [
        ("How many sides does a hexagon have?", "6", ["5", "7", "8"]),
        ("How many edges does a cube have?", "12", ["6", "8", "10"]),
        ("How many faces does a cube have?", "6", ["4", "8", "12"]),
        ("How many degrees are in a right angle?", "90", ["45", "180", "60"]),
        ("How many days are in a leap year?", "366", ["365", "364", "367"]),
        ("How many months have exactly 30 days?", "4", ["5", "6", "7"]),
        ("How many weeks are in a year?", "52", ["48", "50", "54"]),
        ("How many seconds are in 3 minutes?", "180", ["120", "240", "360"]),
        ("How many sides does an octagon have?", "8", ["6", "7", "10"]),
        ("How many corners does a triangle have?", "3", ["2", "4", "5"]),
        ("How many legs does a spider have?", "8", ["6", "10", "12"]),
        ("How many hours are in two days?", "48", ["24", "36", "72"]),
        ("What is half of a quarter?", "One eighth", ["One half", "One sixth", "One third"]),
        ("How many zeros are in one thousand?", "3", ["2", "4", "5"]),
    ]

    private static func quickFact(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        let item = rng.pick(facts) ?? facts[0]
        return build(id: id, kind: "Quick facts", symbol: "lightbulb.fill",
                     prompt: item.0, answer: item.1, distractors: item.2,
                     explain: "The answer is \(item.1).", rng: &rng)
    }

    private static func unitsPuzzle(id: Int, rng: inout PhonePlaySeededRandom) -> DailyPuzzle {
        switch rng.int(0...2) {
        case 0:
            let h = rng.int(2...5)
            let m: Int = rng.pick([10, 20, 30, 40, 50]) ?? 30
            let answer = h * 60 + m
            let wrong: [String] = numberDistractors(answer, step: 10, rng: &rng)
            return build(id: id, kind: "Units", symbol: "ruler.fill",
                         prompt: "How many minutes are in \(h) hours and \(m) minutes?",
                         answer: String(answer), distractors: wrong,
                         explain: "\(h) x 60 + \(m) = \(answer).", rng: &rng)
        case 1:
            let w = rng.int(3...9)
            let d = rng.int(1...6)
            let answer = w * 7 + d
            let wrong: [String] = numberDistractors(answer, step: 7, rng: &rng)
            return build(id: id, kind: "Units", symbol: "ruler.fill",
                         prompt: "How many days are in \(w) weeks and \(d) day\(d == 1 ? "" : "s")?",
                         answer: String(answer), distractors: wrong,
                         explain: "\(w) x 7 + \(d) = \(answer).", rng: &rng)
        default:
            let km = rng.int(2...9)
            let answer = km * 1000 + 500
            let wrong: [String] = numberDistractors(answer, step: 500, rng: &rng)
            return build(id: id, kind: "Units", symbol: "ruler.fill",
                         prompt: "How many metres are in \(km) and a half kilometres?",
                         answer: String(answer), distractors: wrong,
                         explain: "\(km) x 1000 + 500 = \(answer).", rng: &rng)
        }
    }
}
