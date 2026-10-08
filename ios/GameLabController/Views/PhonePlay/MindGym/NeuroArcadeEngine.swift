import SwiftUI

// MARK: - The Mind Gym arcade: the game rules
//
// Short replayable games that sit beside the daily ten. Each trains one
// discipline and ends in a single score from 0 to 1, which the server turns
// into one rating move (games/neuropulse.py, `record_arcade`). Everything
// here is plain logic with no drawing, so a run is generated on the phone
// from a seed and plays with no signal at all.
//
//   Probe  (logic)    a hidden machine turns numbers into numbers; probe it,
//                     work out the rule, then predict its answer
//   Drift  (pattern)  sort cards onto piles by a hidden rule that changes
//                     without warning

enum NeuroArcadeGame: String, CaseIterable, Identifiable {
    case probe
    case drift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .probe: return "Probe"
        case .drift: return "Drift"
        }
    }

    var blurb: String {
        switch self {
        case .probe: return "Find the machine's hidden rule in as few probes as you can."
        case .drift: return "Sort the cards. The rule changes, and nobody tells you."
        }
    }

    /// What it trains, in the Mind Gym's own words.
    var skill: String {
        switch self {
        case .probe: return "Reasoning from evidence"
        case .drift: return "Mental flexibility"
        }
    }

    var symbol: String {
        switch self {
        case .probe: return "function"
        case .drift: return "arrow.left.arrow.right"
        }
    }

    /// The rating track this game moves. Must match `ARCADE_GAMES` on the
    /// server, which is the one that decides.
    var discipline: String {
        switch self {
        case .probe: return "logic"
        case .drift: return "pattern"
        }
    }

    var colors: [Color] {
        switch self {
        case .probe: return [PhonePlayDesign.indigo, PhonePlayDesign.cyan]
        case .drift: return [PhonePlayDesign.yellow, PhonePlayDesign.orange]
        }
    }

    var howTo: [String] {
        switch self {
        case .probe:
            return [
                "A machine turns every number into another number by a hidden rule.",
                "Feed it up to five numbers from 0 to 99 and watch what comes out.",
                "When you think you know the rule, predict what it gives for a new number.",
                "Right with fewer probes scores higher.",
            ]
        case .drift:
            return [
                "Sort each card onto the pile it belongs with.",
                "Only right and wrong tell you anything. The rule is hidden.",
                "After a while the rule changes without warning. Notice, and switch.",
                "Fewer wrong sorts scores higher.",
            ]
        }
    }
}

// MARK: - Probe

/// One hidden rule: what it gives for every input from 0 to 99.
struct ProbeRule: Equatable {
    let name: String
    let outputs: [Int]
}

struct ProbeSample: Equatable {
    let input: Int
    let output: Int
}

struct ProbePuzzle {
    let level: Int
    let pool: [ProbeRule]
    let rule: ProbeRule
}

enum ProbeEngine {
    static let domain = 100
    static let maxProbes = 5

    private struct Op {
        let name: String
        let tier: Int
        let apply: (Int) -> Int
    }

    private static func digitSum(_ value: Int) -> Int {
        var rest = abs(value)
        var total = 0
        while rest > 0 {
            total += rest % 10
            rest /= 10
        }
        return total
    }

    private static func reversedDigits(_ value: Int) -> Int {
        Int(String(String(abs(value)).reversed())) ?? 0
    }

    /// Tier 1 moves a number about, tier 2 folds it, tier 3 scrambles it.
    private static func makeOps() -> [Op] {
        var list: [Op] = []
        for k in 1...9 {
            list.append(Op(name: "add \(k)", tier: 1, apply: { $0 + k }))
        }
        for k in 2...5 {
            list.append(Op(name: "times \(k)", tier: 1, apply: { $0 * k }))
        }
        list.append(Op(name: "half, rounded down", tier: 1, apply: { $0 / 2 }))
        for k in 3...9 {
            list.append(Op(name: "remainder after dividing by \(k)", tier: 2, apply: { $0 % k }))
        }
        list.append(Op(name: "digit sum", tier: 2, apply: { ProbeEngine.digitSum($0) }))
        list.append(Op(name: "reverse the digits", tier: 3, apply: { ProbeEngine.reversedDigits($0) }))
        list.append(Op(name: "square", tier: 3, apply: { $0 * $0 }))
        list.append(Op(name: "itself plus its digit sum", tier: 3,
                       apply: { $0 + ProbeEngine.digitSum($0) }))
        return list
    }

    private static func compose(_ first: Op, _ second: Op) -> (String, (Int) -> Int) {
        ("\(first.name), then \(second.name)", { second.apply(first.apply($0)) })
    }

    /// Every rule a puzzle at `level` can be drawn from. Levels 1-3 use single
    /// simple moves, 4-6 add folds and two-step rules, 7-10 everything.
    ///
    /// The pool doubles as the fairness guarantee: it was checked offline
    /// that a handful of well-chosen probes (1 for the first tier, 2 for the
    /// second and 4 for the third) tells every rule in it apart from every
    /// other, so a rule can always be found within `maxProbes` probes.
    static func pool(level: Int) -> [ProbeRule] {
        let ops = makeOps()
        let simple = ops.filter { $0.tier == 1 }
        var raw: [(String, (Int) -> Int)] = []

        if level <= 3 {
            raw = simple.map { ($0.name, $0.apply) }
        } else if level <= 6 {
            raw = ops.filter { $0.tier <= 2 }.map { ($0.name, $0.apply) }
            for first in simple {
                for second in simple {
                    raw.append(compose(first, second))
                }
            }
        } else {
            raw = ops.map { ($0.name, $0.apply) }
            let early = ops.filter { $0.tier <= 2 }
            let late = ops.filter { $0.tier >= 2 }
            for first in early {
                for second in simple {
                    raw.append(compose(first, second))
                }
            }
            for first in simple {
                for second in late {
                    raw.append(compose(first, second))
                }
            }
        }

        // Distinct behaviours only, in a stable order, and nothing that goes
        // negative, grows past four digits or barely changes.
        var seen = Set<[Int]>()
        var rules: [ProbeRule] = []
        for (name, apply) in raw {
            let outputs = (0..<domain).map { apply($0) }
            guard let low = outputs.min(), let high = outputs.max(),
                  low >= 0, high <= 9999,
                  Set(outputs).count >= 4,
                  !seen.contains(outputs) else { continue }
            seen.insert(outputs)
            rules.append(ProbeRule(name: name, outputs: outputs))
        }
        return rules
    }

    static func puzzle(level: Int, seed: String) -> ProbePuzzle {
        var rng = PhonePlaySeededRandom(text: "probe|" + seed)
        let pool = ProbeEngine.pool(level: level)
        let index = rng.int(0...(max(1, pool.count) - 1))
        return ProbePuzzle(level: level, pool: pool, rule: pool[index])
    }

    /// The rules that still fit everything seen so far.
    static func consistent(_ pool: [ProbeRule], with samples: [ProbeSample]) -> [ProbeRule] {
        pool.filter { rule in
            samples.allSatisfy { rule.outputs[$0.input] == $0.output }
        }
    }

    /// The number to predict. If the probes left several rules standing, it is
    /// one where they disagree the most, so guessing cannot beat working it
    /// out. If the rule is pinned down, it is any fresh number from 10 up.
    static func testInput(for puzzle: ProbePuzzle, samples: [ProbeSample],
                          rng: inout PhonePlaySeededRandom) -> Int {
        let used = Set(samples.map { $0.input })
        let open = (0..<domain).filter { !used.contains($0) }
        guard !open.isEmpty else { return 0 }
        let standing = consistent(puzzle.pool, with: samples)
        if standing.count <= 1 {
            let fresh = open.filter { $0 >= 10 }
            return rng.pick(fresh.isEmpty ? open : fresh) ?? open[0]
        }
        var best: [Int] = []
        var bestSpread = 0
        for x in open {
            let spread = Set(standing.map { $0.outputs[x] }).count
            if spread > bestSpread {
                bestSpread = spread
                best = [x]
            } else if spread == bestSpread {
                best.append(x)
            }
        }
        return rng.pick(best) ?? open[0]
    }

    /// 1.0 for a right answer after one probe down to 0.5 after five; a wrong
    /// answer scores nothing.
    static func score(correct: Bool, probesUsed: Int) -> Double {
        guard correct else { return 0 }
        let used = max(1, min(maxProbes, probesUsed))
        return 0.5 + 0.5 * Double(maxProbes - used) / Double(maxProbes - 1)
    }
}

// MARK: - Drift

/// A card: each of its three features takes one of three values (0, 1, 2).
struct DriftCard: Equatable {
    let shape: Int      // circle, square, triangle
    let count: Int      // one, two or three marks
    let fill: Int       // solid, outline, faint

    func value(for dimension: Int) -> Int {
        switch dimension {
        case 0:  return shape
        case 1:  return count
        default: return fill
        }
    }
}

/// One run of Drift.
///
/// There are three piles, and pile `i` is the card with every feature set to
/// `i`. Each card to sort has its three features all different, so sorting
/// by shape, by count and by fill all point at a different pile and every
/// tap says something about the rule. After `criterion` right sorts in a row
/// the rule changes to a different feature. Colour is never a cue, so the
/// game plays the same for everyone.
struct DriftRun {
    static let dimensions = 3

    let stages: Int
    let criterion: Int
    let cap: Int

    private var rng: PhonePlaySeededRandom
    private(set) var rule: Int
    private(set) var card: DriftCard
    private(set) var streak = 0
    private(set) var errors = 0
    private(set) var trials = 0
    private(set) var completedStages = 0
    private(set) var finished = false

    init(level: Int, seed: String) {
        let clamped = max(1, min(10, level))
        stages = 3 + (clamped - 1) / 3
        criterion = clamped <= 3 ? 6 : (clamped <= 7 ? 5 : 4)
        cap = stages * (criterion + 6)
        var generator = PhonePlaySeededRandom(text: "drift|" + seed)
        rule = generator.int(0...2)
        card = DriftRun.deal(&generator, avoiding: nil)
        rng = generator
    }

    /// A card whose three features are a shuffle of 0, 1, 2, never the same
    /// card twice running.
    private static func deal(_ rng: inout PhonePlaySeededRandom, avoiding last: DriftCard?) -> DriftCard {
        var dealt = DriftCard(shape: 0, count: 1, fill: 2)
        for _ in 0..<8 {
            let values = rng.shuffled([0, 1, 2])
            dealt = DriftCard(shape: values[0], count: values[1], fill: values[2])
            if dealt != last { break }
        }
        return dealt
    }

    /// Sorts the current card onto `pile` and says whether that was right.
    @discardableResult
    mutating func sort(onto pile: Int) -> Bool {
        guard !finished else { return false }
        trials += 1
        let right = pile == card.value(for: rule)
        if right {
            streak += 1
            if streak >= criterion {
                completedStages += 1
                streak = 0
                if completedStages >= stages {
                    finished = true
                } else {
                    let others = (0..<DriftRun.dimensions).filter { $0 != rule }
                    rule = rng.pick(others) ?? ((rule + 1) % DriftRun.dimensions)
                }
            }
        } else {
            errors += 1
            streak = 0
        }
        if trials >= cap { finished = true }
        if !finished {
            let previous = card
            card = DriftRun.deal(&rng, avoiding: previous)
        }
        return right
    }

    /// One wrong sort per new rule is unavoidable (nobody can know it
    /// changed), so only the errors beyond that cost anything; unfinished
    /// stages scale the score down.
    var score: Double {
        let unavoidable = completedStages
        let extra = max(0, errors - unavoidable)
        let budget = Double(2 * stages + 3)
        let accuracy = max(0, 1 - Double(extra) / budget)
        return accuracy * Double(completedStages) / Double(stages)
    }
}
