import SwiftUI

// MARK: - Point at Them
//
// Nobody passes the phone. It lies flat in the middle of the group and shows
// "Who is most likely to ...?". Someone taps Ready, the phone counts 3, 2, 1,
// and on "Point!" everyone points at someone at the same moment. The person
// with the most fingers on them gets a follow-up to answer out loud, and the
// next prompt is one tap away.

@MainActor
final class PointAtViewModel: ObservableObject {

    enum Stage { case setup, prompt, counting, pointed }

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var level: TruthDareLevel
    @Published private(set) var prompt: String = ""
    @Published private(set) var follow: String = ""
    /// 3, 2, 1 while counting; 0 on "Point!".
    @Published private(set) var count: Int = 3
    @Published private(set) var roundsPlayed: Int = 0

    var poolCount: Int { PointAtDeck.prompts(upTo: level).count }

    /// What the person with the most fingers on them does next.
    static let followUps: [String] = [
        "Defend yourself in ten seconds.",
        "Say thank you, in a very dramatic voice.",
        "Tell everyone why they are wrong.",
        "Take a bow, then name your biggest fan.",
        "Admit it. Was it true?",
        "Point back at the person who pointed first.",
        "Give a short, proud acceptance speech.",
        "Do your best innocent face for five seconds.",
        "Tell the story that made everyone point at you.",
        "Choose someone to swap places with.",
    ]

    private var dealer = PhonePlayDealer(deck: "pointat")
    private var countTask: Task<Void, Never>? = nil
    private var isActive: Bool = true
    private static let levelKey = "phoneplay_pointat_level"

    init() {
        let saved = UserDefaults.standard.object(forKey: PointAtViewModel.levelKey) as? Int ?? 0
        level = TruthDareLevel(rawValue: saved) ?? .family
    }

    // MARK: Flow

    func setLevel(_ newLevel: TruthDareLevel) {
        level = newLevel
        UserDefaults.standard.set(newLevel.rawValue, forKey: PointAtViewModel.levelKey)
    }

    func start() {
        roundsPlayed = 0
        dealNext()
        PhonePlayHaptics.thump()
    }

    func backToSetup() {
        countTask?.cancel()
        stage = .setup
    }

    /// Ready: count 3, 2, 1, then "Point!".
    func ready() {
        guard stage == .prompt else { return }
        stage = .counting
        count = 3
        PhonePlayHaptics.rigid()
        countTask?.cancel()
        countTask = Task { @MainActor [weak self] in
            for number in stride(from: 3, through: 1, by: -1) {
                guard let self, self.isActive, !Task.isCancelled else { return }
                self.count = number
                PhonePlayHaptics.tap()
                try? await Task.sleep(nanoseconds: 900_000_000)
            }
            guard let self, self.isActive, !Task.isCancelled else { return }
            self.count = 0
            self.stage = .pointed
            self.roundsPlayed += 1
            PhonePlayHaptics.thump()
        }
    }

    func next() {
        guard stage == .pointed else { return }
        dealNext()
        PhonePlayHaptics.rigid()
    }

    func shutdown() {
        isActive = false
        countTask?.cancel()
        countTask = nil
    }

    private func dealNext() {
        let pool = PointAtDeck.prompts(upTo: level)
        prompt = dealer.draw(from: pool) ?? "Who is most likely to win this game?"
        follow = PointAtViewModel.followUps.randomElement() ?? "Defend yourself."
        count = 3
        stage = .prompt
    }
}
