import SwiftUI

// MARK: - Would You Rather
//
// One big split-screen dilemma at a time. Two ways to play:
//  - Pick a side: tap your side and defend it (great for two or three).
//  - Pass and count: the phone goes round, everyone taps a side, and the
//    tally stays hidden until the group taps Reveal.
// No dilemma repeats within a session. "Fresh AI cards" adds AI-written
// dilemmas when the server is reachable; offline nothing changes.

@MainActor
final class WouldRatherViewModel: ObservableObject {

    enum Stage { case setup, play }
    enum Side { case a, b }

    enum Mode: String, CaseIterable, Identifiable {
        case pick
        case count

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pick:  return "Pick a side"
            case .count: return "Pass and count"
            }
        }

        var subtitle: String {
            switch self {
            case .pick:  return "Tap and defend it"
            case .count: return "Secret group vote"
            }
        }
    }

    @Published private(set) var mode: Mode
    @Published private(set) var stage: Stage = .setup
    @Published private(set) var current: WouldRatherDilemma
    @Published private(set) var cardNumber: Int = 0
    @Published private(set) var picked: Side? = nil
    @Published private(set) var votesA: Int = 0
    @Published private(set) var votesB: Int = 0
    @Published private(set) var revealed: Bool = false
    @Published private(set) var aiState: PhonePlayAIState = .idle

    var totalVotes: Int { votesA + votesB }
    var poolCount: Int { WouldRatherDeck.all.count + extras.count }

    /// Share of the votes for a side, 0...1.
    func share(_ side: Side) -> Double {
        guard totalVotes > 0 else { return 0.5 }
        switch side {
        case .a: return Double(votesA) / Double(totalVotes)
        case .b: return Double(votesB) / Double(totalVotes)
        }
    }

    func votes(_ side: Side) -> Int {
        switch side {
        case .a: return votesA
        case .b: return votesB
        }
    }

    private var extras: [WouldRatherDilemma] = []
    private var dealer = PhonePlayDealer()
    private var aiTask: Task<Void, Never>? = nil
    private var isActive: Bool = true

    private static let modeKey = "phoneplay_wyr_mode"

    init() {
        let saved = UserDefaults.standard.string(forKey: WouldRatherViewModel.modeKey) ?? ""
        mode = Mode(rawValue: saved) ?? .pick
        current = WouldRatherDeck.all.first ?? WouldRatherDilemma(a: "be able to fly", b: "be invisible")
    }

    // MARK: - Flow

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: WouldRatherViewModel.modeKey)
        clearVotes()
    }

    func start() {
        dealNext()
        PhonePlayHaptics.thump()
        stage = .play
    }

    func backToSetup() {
        stage = .setup
    }

    func next() {
        guard stage == .play else { return }
        dealNext()
        PhonePlayHaptics.rigid()
    }

    func tap(_ side: Side) {
        guard stage == .play else { return }
        switch mode {
        case .pick:
            picked = side
            PhonePlayHaptics.thump()
        case .count:
            guard !revealed else { return }
            switch side {
            case .a: votesA += 1
            case .b: votesB += 1
            }
            PhonePlayHaptics.rigid()
        }
    }

    func reveal() {
        guard stage == .play, mode == .count, !revealed, totalVotes > 0 else { return }
        revealed = true
        PhonePlayHaptics.success()
    }

    func clearVotes() {
        votesA = 0
        votesB = 0
        revealed = false
        picked = nil
    }

    func shutdown() {
        isActive = false
        aiTask?.cancel()
        aiTask = nil
    }

    private func dealNext() {
        let pool = WouldRatherDeck.all + extras
        var byKey: [String: WouldRatherDilemma] = [:]
        for item in pool { byKey[item.id] = item }
        if let key = dealer.draw(from: pool.map { $0.id }), let found = byKey[key] {
            current = found
        }
        cardNumber += 1
        clearVotes()
    }

    // MARK: - Fresh AI cards

    func fetchFreshCards() {
        guard aiState != .loading else { return }
        aiState = .loading
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            let lines: [String] = await OneStopAPI.deck(kind: "wyr", topic: "anything fun for friends and family",
                                                        count: 25, familySafe: true, language: "en")
            guard let self, self.isActive else { return }
            var known = Set((WouldRatherDeck.all + self.extras).map { $0.id })
            var added = 0
            for line in lines {
                guard let dilemma = WouldRatherDilemma.parse(line), !known.contains(dilemma.id) else { continue }
                known.insert(dilemma.id)
                self.extras.append(dilemma)
                added += 1
            }
            self.aiState = added > 0 ? .added(added) : .idle
            if added > 0 { PhonePlayHaptics.success() }
        }
    }
}
