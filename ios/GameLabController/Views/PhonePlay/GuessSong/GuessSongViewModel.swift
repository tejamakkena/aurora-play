import AudioToolbox
import SwiftUI

// MARK: - Guess the Song (phone)
//
// The TV game (games/native_hub/engines/guess_the_song.py) on one phone, no TV
// needed. Two teams take turns. On a team's turn the phone shows a word
// ("Rain") and the team sings any song that fits it: the word in the title or
// lyrics, its Hindi meaning (baarish), or the word in the scene (a train ->
// "Chaiyya Chaiyya"). The other team holds the phone and judges: Sung it, or
// Pass. A hint shows the Hindi word for half the points. When the clock runs
// out the other team's turn begins. Each word shows a few songs that fit
// afterwards, so everyone learns a few more for next time.
//
// The words are the server's list, copied by tools/gen_song_deck_swift.py.

@MainActor
final class GuessSongViewModel: ObservableObject {

    enum Stage { case setup, ready, singing, turnOver, final }

    struct Outcome: Identifiable, Equatable {
        let id = UUID()
        let word: GuessSongWord
        let points: Int
        let usedHint: Bool
        var sung: Bool { points > 0 }
    }

    static let fullPoints = 2
    static let hintPoints = 1
    static let turnChoices = [45, 60, 90]
    static let roundChoices = [2, 3, 4]

    @Published var teamNames: [String] = ["Team Chai", "Team Lassi"]
    @Published var oneTeam: Bool = false
    @Published var turnSeconds: Int = 60
    @Published var roundsEach: Int = 3
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: GuessSongViewModel.soundKey) }
    }

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var scores: [Int] = [0, 0]
    @Published private(set) var team: Int = 0
    @Published private(set) var turn: Int = 0
    @Published private(set) var current: GuessSongWord? = nil
    @Published private(set) var hintShown: Bool = false
    @Published private(set) var secondsLeft: Int = 60
    /// This turn's words, in order.
    @Published private(set) var outcomes: [Outcome] = []
    /// The word just played, shown with its songs for a moment.
    @Published private(set) var lastOutcome: Outcome? = nil

    var teamCount: Int { oneTeam ? 1 : 2 }
    var totalTurns: Int { roundsEach * teamCount }
    var teamName: String { name(of: team) }
    var turnPoints: Int { outcomes.reduce(0) { $0 + $1.points } }
    var isLastTurn: Bool { turn >= totalTurns - 1 }
    var winnerText: String {
        if teamCount == 1 { return "\(scores[0]) points" }
        if scores[0] == scores[1] { return "It is a tie!" }
        return "\(name(of: scores[0] > scores[1] ? 0 : 1)) wins!"
    }

    private var dealer = PhonePlayDealer(deck: "guesssong")
    private var loop: Task<Void, Never>? = nil
    private var token: Int = 0
    private var isActive: Bool = true
    private static let soundKey = "phoneplay_guesssong_sound"
    private static let tickSound: SystemSoundID = 1104
    private static let endSound: SystemSoundID = 1005

    init() {
        let defaults = UserDefaults.standard
        soundOn = defaults.object(forKey: GuessSongViewModel.soundKey) == nil
            ? true : defaults.bool(forKey: GuessSongViewModel.soundKey)
    }

    func name(of index: Int) -> String {
        if teamCount == 1 { return "Everyone" }
        let raw = teamNames.indices.contains(index) ? teamNames[index] : ""
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Team \(index + 1)" : trimmed
    }

    // MARK: - Flow

    func start() {
        stopLoop()
        scores = Array(repeating: 0, count: teamCount)
        turn = 0
        team = 0
        outcomes = []
        lastOutcome = nil
        PhonePlayHaptics.thump()
        stage = .ready
    }

    func beginTurn() {
        guard stage == .ready else { return }
        outcomes = []
        lastOutcome = nil
        secondsLeft = turnSeconds
        deal()
        PhonePlayHaptics.thump()
        stage = .singing
        startClock()
    }

    func showHint() {
        guard stage == .singing, !hintShown else { return }
        hintShown = true
        PhonePlayHaptics.tap()
    }

    func sung() { score(hintShown ? GuessSongViewModel.hintPoints : GuessSongViewModel.fullPoints) }

    func pass() { score(0) }

    func nextTurn() {
        guard stage == .turnOver else { return }
        if isLastTurn {
            stage = .final
            PhonePlayHaptics.success()
            return
        }
        turn += 1
        team = turn % teamCount
        stage = .ready
    }

    func playAgain() { start() }

    func editSetup() {
        stopLoop()
        stage = .setup
    }

    func shutdown() {
        isActive = false
        stopLoop()
    }

    private func score(_ points: Int) {
        guard stage == .singing, let word = current else { return }
        let outcome = Outcome(word: word, points: points, usedHint: hintShown)
        outcomes.append(outcome)
        lastOutcome = outcome
        scores[team] += points
        if points > 0 { PhonePlayHaptics.success() } else { PhonePlayHaptics.tap() }
        deal()
    }

    private func deal() {
        let pool = GuessSongDeck.words.map(\.word)
        let pick = dealer.draw(from: pool)
        current = GuessSongDeck.words.first { $0.word == pick } ?? GuessSongDeck.words.randomElement()
        hintShown = false
    }

    private func endTurn() {
        stopLoop()
        secondsLeft = 0
        if soundOn { AudioServicesPlaySystemSound(GuessSongViewModel.endSound) }
        PhonePlayHaptics.warning()
        stage = .turnOver
    }

    // MARK: - Clock

    private func startClock() {
        stopLoop()
        token += 1
        let myToken = token
        let endsAt = Date().addingTimeInterval(TimeInterval(turnSeconds))
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.isActive, myToken == self.token, self.stage == .singing else { return }
                let left = max(0, Int(ceil(endsAt.timeIntervalSinceNow)))
                if left != self.secondsLeft {
                    self.secondsLeft = left
                    if left > 0 && left <= 5 {
                        PhonePlayHaptics.rigid()
                        if self.soundOn { AudioServicesPlaySystemSound(GuessSongViewModel.tickSound) }
                    }
                }
                if left == 0 {
                    self.endTurn()
                    return
                }
            }
        }
    }

    private func stopLoop() {
        token += 1
        loop?.cancel()
        loop = nil
    }
}
