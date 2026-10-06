import SwiftUI

// MARK: - Truth or Dare
//
// Players sit round the phone. A spinning arrow picks whose turn it is;
// they choose Truth or Dare and the card is read out. No card repeats
// within a session (per level pool), and a player can skip a card for a
// fresh one of the same kind. "Fresh AI cards" asks the server for new
// truths and dares in the level's tone and merges them into the pool;
// offline it quietly does nothing.

@MainActor
final class TruthDareViewModel: ObservableObject {

    enum Stage { case setup, play }
    enum Phase { case ready, spinning, choosing, card }

    struct Prompt: Identifiable, Equatable {
        let id: Int
        let kind: TruthDareKind
        let text: String
        let player: String
    }

    @Published var names: [String] {
        didSet { PhonePlayRoster.save(names) }
    }
    @Published private(set) var level: TruthDareLevel

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var phase: Phase = .ready
    /// Cumulative arrow rotation in degrees; the view animates changes.
    @Published private(set) var spinAngle: Double = 0
    @Published private(set) var chosen: Int? = nil
    @Published private(set) var prompt: Prompt? = nil
    @Published private(set) var aiState: PhonePlayAIState = .idle
    @Published private(set) var turns: Int = 0
    @Published private(set) var skips: Int = 0

    let playerRange: ClosedRange<Int> = 2...16
    static let spinDuration: Double = 2.8

    var canStart: Bool { playerRange.contains(names.count) }

    var chosenName: String {
        guard let index = chosen, names.indices.contains(index) else { return "" }
        return names[index]
    }

    var truthCount: Int { truthPool.count }
    var dareCount: Int { darePool.count }

    private var extraTruths: [TruthDareLevel: [String]] = [:]
    private var extraDares: [TruthDareLevel: [String]] = [:]
    private var truthDealer = PhonePlayDealer()
    private var dareDealer = PhonePlayDealer()
    private var promptCounter: Int = 0
    private var spinToken: Int = 0
    private var spinTask: Task<Void, Never>? = nil
    private var aiTask: Task<Void, Never>? = nil
    private var isActive: Bool = true

    private static let levelKey = "phoneplay_truthdare_level"

    init() {
        names = Array(PhonePlayRoster.load().prefix(16))
        let saved = UserDefaults.standard.integer(forKey: TruthDareViewModel.levelKey)
        level = TruthDareLevel(rawValue: saved) ?? .family
    }

    // MARK: - Pools

    private var truthPool: [String] {
        var pool = TruthDareDeck.truths(upTo: level)
        for extraLevel in TruthDareLevel.allCases where extraLevel.rawValue <= level.rawValue {
            pool.append(contentsOf: extraTruths[extraLevel] ?? [])
        }
        return pool
    }

    private var darePool: [String] {
        var pool = TruthDareDeck.dares(upTo: level)
        for extraLevel in TruthDareLevel.allCases where extraLevel.rawValue <= level.rawValue {
            pool.append(contentsOf: extraDares[extraLevel] ?? [])
        }
        return pool
    }

    // MARK: - Setup

    func setLevel(_ newLevel: TruthDareLevel) {
        guard newLevel != level else { return }
        level = newLevel
        UserDefaults.standard.set(newLevel.rawValue, forKey: TruthDareViewModel.levelKey)
        if aiState != .loading { aiState = .idle }
    }

    func start() {
        guard canStart else { return }
        chosen = nil
        prompt = nil
        phase = .ready
        PhonePlayHaptics.thump()
        stage = .play
    }

    func editPlayers() {
        cancelSpin()
        prompt = nil
        chosen = nil
        phase = .ready
        stage = .setup
    }

    func shutdown() {
        isActive = false
        cancelSpin()
        aiTask?.cancel()
        aiTask = nil
    }

    // MARK: - Spin

    func spin() {
        guard stage == .play, phase != .spinning, names.count >= 2 else { return }
        var target = Int.random(in: 0..<names.count)
        if let last = chosen, target == last {
            // Never the same player twice in a row.
            target = (last + Int.random(in: 1..<names.count)) % names.count
        }
        let slice = 360.0 / Double(names.count)
        let fullTurns = (spinAngle / 360.0).rounded(.down) * 360.0
        var next = fullTurns + 360.0 * 4 + Double(target) * slice
        if next - spinAngle < 360.0 * 3 { next += 360.0 }

        prompt = nil
        chosen = nil
        phase = .spinning
        spinAngle = next
        PhonePlayHaptics.rigid()

        spinToken += 1
        let token = spinToken
        let duration = TruthDareViewModel.spinDuration
        spinTask?.cancel()
        spinTask = Task { [weak self] in
            // Ticks that slow down with the arrow.
            var delay: Double = 0.05
            var elapsed: Double = 0
            while elapsed + delay < duration - 0.2 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                elapsed += delay
                delay *= 1.17
                guard let self, self.isActive, token == self.spinToken, !Task.isCancelled else { return }
                PhonePlayHaptics.tap()
            }
            let rest = max(0, duration - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
            guard let self, self.isActive, token == self.spinToken, !Task.isCancelled else { return }
            self.land(on: target)
        }
    }

    private func land(on target: Int) {
        guard phase == .spinning else { return }
        chosen = names.indices.contains(target) ? target : nil
        phase = chosen == nil ? .ready : .choosing
        PhonePlayHaptics.thump()
    }

    private func cancelSpin() {
        spinToken += 1
        spinTask?.cancel()
        spinTask = nil
        if phase == .spinning { phase = .ready }
    }

    // MARK: - Cards

    func choose(_ kind: TruthDareKind) {
        guard phase == .choosing || phase == .card, chosen != nil else { return }
        deal(kind)
        PhonePlayHaptics.success()
    }

    /// A fresh card of the same kind for the same player.
    func skip() {
        guard phase == .card, let current = prompt else { return }
        skips += 1
        deal(current.kind)
        PhonePlayHaptics.warning()
    }

    /// The card is done: back to the arrow for the next player.
    func done() {
        guard phase == .card else { return }
        turns += 1
        prompt = nil
        phase = .ready
        PhonePlayHaptics.success()
    }

    private func deal(_ kind: TruthDareKind) {
        let text: String?
        switch kind {
        case .truth: text = truthDealer.draw(from: truthPool)
        case .dare:  text = dareDealer.draw(from: darePool)
        }
        promptCounter += 1
        prompt = Prompt(id: promptCounter, kind: kind,
                        text: text ?? "Tell everyone your favourite thing about today.",
                        player: chosenName)
        phase = .card
    }

    // MARK: - Fresh AI cards

    func fetchFreshCards() {
        guard aiState != .loading else { return }
        aiState = .loading
        let forLevel = level
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            async let truths: [String] = OneStopAPI.deck(kind: "truth", topic: forLevel.aiTopic, count: 20,
                                                         familySafe: forLevel.familySafe, language: "en")
            async let dares: [String] = OneStopAPI.deck(kind: "dare", topic: forLevel.aiTopic, count: 20,
                                                        familySafe: forLevel.familySafe, language: "en")
            let newTruths: [String] = await truths
            let newDares: [String] = await dares
            guard let self, self.isActive else { return }
            let added = self.mergeFresh(truths: newTruths, dares: newDares, level: forLevel)
            self.aiState = added > 0 ? .added(added) : .idle
            if added > 0 { PhonePlayHaptics.success() }
        }
    }

    private func mergeFresh(truths: [String], dares: [String], level forLevel: TruthDareLevel) -> Int {
        var knownTruths = TruthDareDeck.truths(upTo: .adults)
        var knownDares = TruthDareDeck.dares(upTo: .adults)
        for each in TruthDareLevel.allCases {
            knownTruths.append(contentsOf: extraTruths[each] ?? [])
            knownDares.append(contentsOf: extraDares[each] ?? [])
        }
        let truthStart = knownTruths.count
        let dareStart = knownDares.count
        let addedTruths = PhonePlayAIDecks.merge(truths, into: &knownTruths)
        let addedDares = PhonePlayAIDecks.merge(dares, into: &knownDares)
        if addedTruths > 0 {
            extraTruths[forLevel, default: []].append(contentsOf: knownTruths[truthStart...])
        }
        if addedDares > 0 {
            extraDares[forLevel, default: []].append(contentsOf: knownDares[dareStart...])
        }
        return addedTruths + addedDares
    }
}
