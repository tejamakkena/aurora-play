import AudioToolbox
import SwiftUI

// MARK: - Story Chain
//
// One phone, a silly opening line, and a story built one sentence at a
// time. Each storyteller says their sentence OUT LOUD (nothing is typed)
// while a 20 second timer runs, then taps "Next storyteller" and passes
// the phone on. Every few turns a twist card bends the story. After
// everyone has had two turns it is The End, and the phone goes round once
// more for a vote on the funniest storyteller, who gets crowned.
//
// No AI twists: the server's deck generator has no story or twist kind,
// so the bundled cards are the whole deck.

@MainActor
final class StoryChainViewModel: ObservableObject {

    enum Stage { case setup, opening, ready, telling, theEnd, vote, crowned }

    @Published var names: [String] {
        didSet { PhonePlayRoster.save(names) }
    }
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: StoryChainViewModel.soundKey) }
    }

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var opener: String = ""
    /// The storytellers in turn order, fixed for the whole story.
    @Published private(set) var order: [String] = []
    /// Zero-based turn across the whole story (two per storyteller).
    @Published private(set) var turn: Int = 0
    /// The twist card for the current turn, if it has one.
    @Published private(set) var twist: String? = nil
    @Published private(set) var turnEnds: Date = Date()
    @Published private(set) var secondsLeft: Int = 20
    @Published private(set) var timeUp: Bool = false
    @Published private(set) var buzzers: Int = 0
    @Published private(set) var twistsPlayed: Int = 0
    /// Who is voting right now (index into `order`).
    @Published private(set) var voter: Int = 0
    @Published private(set) var votes: [String: Int] = [:]
    @Published private(set) var winners: [String] = []

    let playerRange: ClosedRange<Int> = 3...10
    static let turnSeconds: Int = 20
    static let turnsEach: Int = 2
    static let twistEvery: Int = 3

    var canStart: Bool { playerRange.contains(names.count) }
    var totalTurns: Int { order.count * StoryChainViewModel.turnsEach }
    var isFinalTurn: Bool { totalTurns > 0 && turn >= totalTurns - 1 }
    var round: Int { order.isEmpty ? 1 : turn / order.count + 1 }

    var currentName: String {
        guard !order.isEmpty else { return "" }
        return order[turn % order.count]
    }

    var voterName: String {
        order.indices.contains(voter) ? order[voter] : ""
    }

    /// Everyone's votes, most first (ties keep turn order).
    var standings: [(name: String, votes: Int)] {
        let rows = order.enumerated().map { (offset: $0.offset, name: $0.element, votes: votes[$0.element] ?? 0) }
        return rows
            .sorted { $0.votes != $1.votes ? $0.votes > $1.votes : $0.offset < $1.offset }
            .map { (name: $0.name, votes: $0.votes) }
    }

    private var openerDealer = PhonePlayDealer()
    private var twistDealer = PhonePlayDealer()
    private var loop: Task<Void, Never>? = nil
    private var token: Int = 0
    private var isActive: Bool = true

    private static let soundKey = "phoneplay_storychain_sound"
    /// The keyboard click for the last five seconds.
    private static let tickSound: SystemSoundID = 1104
    /// A short negative "bonk" for the buzzer.
    private static let buzzerSound: SystemSoundID = 1053

    init() {
        names = Array(PhonePlayRoster.load().prefix(10))
        let defaults = UserDefaults.standard
        soundOn = defaults.object(forKey: StoryChainViewModel.soundKey) == nil
            ? true : defaults.bool(forKey: StoryChainViewModel.soundKey)
    }

    // MARK: - Flow

    /// A brand new story with the same players.
    func start() {
        guard canStart else { return }
        stopLoop()
        let first = Int.random(in: 0..<names.count)
        order = Array(names[first...] + names[..<first])
        opener = openerDealer.draw(from: StoryChainDeck.openers) ?? "Once upon a time, something very odd happened..."
        turn = 0
        twist = nil
        timeUp = false
        secondsLeft = StoryChainViewModel.turnSeconds
        buzzers = 0
        twistsPlayed = 0
        voter = 0
        votes = [:]
        winners = []
        PhonePlayHaptics.thump()
        stage = .opening
    }

    func newOpener() {
        guard stage == .opening else { return }
        opener = openerDealer.draw(from: StoryChainDeck.openers) ?? opener
        PhonePlayHaptics.tap()
    }

    /// The opener has been read out: hand over to the first storyteller.
    func beginStory() {
        guard stage == .opening, !order.isEmpty else { return }
        turn = 0
        prepareTurn()
        PhonePlayHaptics.success()
        stage = .ready
    }

    /// The storyteller has the phone: start their 20 seconds.
    func startTelling() {
        guard stage == .ready else { return }
        secondsLeft = StoryChainViewModel.turnSeconds
        timeUp = false
        turnEnds = Date().addingTimeInterval(TimeInterval(StoryChainViewModel.turnSeconds))
        PhonePlayHaptics.thump()
        stage = .telling
        startLoop()
    }

    /// Done talking (or buzzed): on to the next storyteller, or The End.
    func nextStoryteller() {
        guard stage == .telling else { return }
        stopLoop()
        if isFinalTurn {
            timeUp = false
            PhonePlayHaptics.success()
            stage = .theEnd
            return
        }
        turn += 1
        prepareTurn()
        PhonePlayHaptics.tap()
        stage = .ready
    }

    func startVote() {
        guard stage == .theEnd, order.count >= 2 else { return }
        voter = 0
        votes = [:]
        winners = []
        PhonePlayHaptics.tap()
        stage = .vote
    }

    /// The current voter picks the funniest storyteller (never themselves).
    func vote(for name: String) {
        guard stage == .vote, order.contains(name), name != voterName else { return }
        votes[name, default: 0] += 1
        PhonePlayHaptics.success()
        if voter + 1 >= order.count {
            crown()
        } else {
            voter += 1
        }
    }

    func editPlayers() {
        stopLoop()
        timeUp = false
        stage = .setup
    }

    func shutdown() {
        isActive = false
        stopLoop()
    }

    private func prepareTurn() {
        timeUp = false
        secondsLeft = StoryChainViewModel.turnSeconds
        // A twist every few turns, but never on the opening line or the
        // last one, which has to wrap the story up.
        if turn > 0, turn % StoryChainViewModel.twistEvery == 0, !isFinalTurn {
            twist = twistDealer.draw(from: StoryChainDeck.twists)
            if twist != nil { twistsPlayed += 1 }
        } else {
            twist = nil
        }
    }

    private func crown() {
        let top = votes.values.max() ?? 0
        winners = top > 0 ? order.filter { (votes[$0] ?? 0) == top } : []
        PhonePlayHaptics.thump()
        PhonePlayHaptics.success()
        stage = .crowned
    }

    // MARK: - The timer

    private func startLoop() {
        stopLoop()
        token += 1
        let myToken = token
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, self.isActive, myToken == self.token, !Task.isCancelled else { return }
                self.step()
            }
        }
    }

    private func stopLoop() {
        token += 1
        loop?.cancel()
        loop = nil
    }

    private func step() {
        guard stage == .telling, !timeUp else {
            stopLoop()
            return
        }
        let left = max(0, Int(ceil(turnEnds.timeIntervalSince(Date()))))
        if left != secondsLeft {
            secondsLeft = left
            if left > 0 && left <= 5 {
                PhonePlayHaptics.rigid()
                if soundOn { AudioServicesPlaySystemSound(StoryChainViewModel.tickSound) }
            }
        }
        if left == 0 {
            buzz()
        }
    }

    private func buzz() {
        stopLoop()
        timeUp = true
        buzzers += 1
        PhonePlayHaptics.error()
        if soundOn {
            AudioServicesPlaySystemSound(StoryChainViewModel.buzzerSound)
        }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        // A rattle of heavy hits, like a game-show buzzer.
        let myToken = token
        Task { [weak self] in
            for _ in 0..<4 {
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard let self, self.isActive, myToken == self.token else { return }
                PhonePlayHaptics.thump()
            }
        }
    }
}
