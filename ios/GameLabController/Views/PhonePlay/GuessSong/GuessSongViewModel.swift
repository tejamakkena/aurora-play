import AudioToolbox
import SwiftUI

// MARK: - Guess the Song (phone)
//
// The TV game (games/native_hub/engines/guess_the_song.py) on one phone, no TV
// needed. Two teams take turns. On a team's turn the phone shows a word
// ("Rain") and the team sings any song that fits it: the word in the title or
// lyrics, its meaning in the song's language (baarish), or the word in the scene (a train ->
// "Chaiyya Chaiyya"). The other team holds the phone and judges: Sung it, or
// Pass. A hint shows the word in Hindi or Telugu for half the points. Like
// Forehead Charades, the words come in themes (Bollywood, Tollywood, English,
// or Mixed). When the clock runs
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
    /// A theme id (GuessSongDeck.themes) or `GuessSongViewModel.mixed` for all of them.
    @Published var themeID: String {
        didSet { UserDefaults.standard.set(themeID, forKey: GuessSongViewModel.themeKey) }
    }
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: GuessSongViewModel.soundKey) }
    }

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var scores: [Int] = [0, 0]
    @Published private(set) var team: Int = 0
    @Published private(set) var turn: Int = 0
    @Published private(set) var current: GuessSongWord? = nil
    /// The current word's hint language ("Hindi", "Telugu"; empty: no hint).
    @Published private(set) var hintLabel: String = ""
    @Published private(set) var hintShown: Bool = false
    @Published private(set) var secondsLeft: Int = 60
    /// This turn's words, in order.
    @Published private(set) var outcomes: [Outcome] = []
    /// The word just played, shown with its songs for a moment.
    @Published private(set) var lastOutcome: Outcome? = nil

    static let mixed = "mix"

    /// The themes in play: the picked one, or every theme for Mixed.
    var themes: [GuessSongTheme] {
        let picked = GuessSongDeck.themes.filter { $0.id == themeID }
        return picked.isEmpty ? GuessSongDeck.themes : picked
    }
    var wordCount: Int { themes.reduce(0) { $0 + $1.words.count } }
    var canHint: Bool { !(current?.hint.isEmpty ?? true) }

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
    private static let themeKey = "phoneplay_guesssong_theme"
    private static let tickSound: SystemSoundID = 1104
    private static let endSound: SystemSoundID = 1005

    init() {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.string(forKey: GuessSongViewModel.themeKey) ?? GuessSongViewModel.mixed
        themeID = GuessSongDeck.themes.contains { $0.id == savedTheme } ? savedTheme : GuessSongViewModel.mixed
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
        guard stage == .singing, !hintShown, canHint else { return }
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

    /// A word from the themes in play, never one this phone showed recently.
    /// The dealer's key carries the theme, so "Rain" in Bollywood and "Rain" in
    /// English are different cards.
    private func deal() {
        var byKey: [String: (GuessSongWord, String)] = [:]
        for theme in themes {
            for word in theme.words { byKey["\(theme.id)|\(word.word)"] = (word, theme.hintLabel) }
        }
        guard let key = dealer.draw(from: Array(byKey.keys)), let picked = byKey[key] else { return }
        current = picked.0
        hintLabel = picked.1
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
