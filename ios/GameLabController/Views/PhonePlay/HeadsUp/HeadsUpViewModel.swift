import CoreMotion
import SwiftUI

// MARK: - Forehead Charades
//
// The guesser holds the phone to their forehead, screen facing the group.
// Tilt the screen DOWN towards the floor = got it; tilt it UP towards the
// ceiling = pass. CoreMotion's gravity vector reads this directly: its z
// axis points out of the screen, so z near +1 means the screen faces the
// floor and z near -1 means it faces the sky, whichever way the phone is
// turned sideways. Device motion needs no permission prompt.
//
// A tilt only counts when it is deliberate (past the threshold and held
// for a few frames) and the next card waits until the phone comes back
// to level, so a wobble never burns two cards.

struct HeadsUpResult: Identifiable {
    let id: Int
    let word: String
    let correct: Bool
}

@MainActor
final class HeadsUpViewModel: ObservableObject {

    enum Stage { case pick, ready, countdown, playing, summary }
    enum Flash { case correct, pass }

    @Published private(set) var stage: Stage = .pick
    @Published private(set) var deck: HeadsUpDeck = HeadsUpDecks.hollywoodMovies
    @Published private(set) var word: String = ""
    @Published private(set) var secondsLeft: Int = 300
    @Published private(set) var countdown: Int = 3
    @Published private(set) var flash: Flash? = nil
    @Published private(set) var results: [HeadsUpResult] = []
    /// False until the phone has come back to level after a tilt.
    @Published private(set) var armed: Bool = false
    /// Tilt control is on when the phone supports it; tap buttons otherwise.
    @Published var useTilt: Bool

    /// Seconds per round: 1, 2, 3 or 5 minutes, remembered between games.
    @Published var roundLength: Int {
        didSet { UserDefaults.standard.set(roundLength, forKey: HeadsUpViewModel.lengthKey) }
    }
    static let lengthOptions: [Int] = [60, 120, 180, 300]
    private static let lengthKey = "headsup_round_seconds"
    let motionAvailable: Bool

    var correctCount: Int { results.filter { $0.correct }.count }
    var passCount: Int { results.filter { !$0.correct }.count }

    private let motion: CMMotionManager
    private var loop: Task<Void, Never>? = nil
    private var countdownEnds: Date = Date()
    private var roundEnds: Date = Date()
    private var queue: [String] = []
    private var dealers: [String: PhonePlayDealer] = [:]

    private func dealer(for deck: HeadsUpDeck) -> PhonePlayDealer {
        dealers[deck.id] ?? PhonePlayDealer(deck: "headsup_" + deck.id)
    }
    private var tiltFrames: Int = 0
    private var levelFrames: Int = 0
    private var pendingTilt: Flash? = nil
    private var flashToken: Int = 0
    private var isActive: Bool = true

    /// Gravity z beyond this counts as a tilt (about 45 degrees).
    private let tiltThreshold: Double = 0.7
    /// Gravity z inside this counts as level again (about 25 degrees).
    private let levelThreshold: Double = 0.42
    private let framesToTilt: Int = 3
    private let framesToLevel: Int = 4

    init() {
        let saved = UserDefaults.standard.integer(forKey: HeadsUpViewModel.lengthKey)
        roundLength = HeadsUpViewModel.lengthOptions.contains(saved) ? saved : 300
        let manager = CMMotionManager()
        let available: Bool = manager.isDeviceMotionAvailable
        motion = manager
        motionAvailable = available
        useTilt = available
    }

    // MARK: - Flow

    func choose(_ deck: HeadsUpDeck) {
        guard stage == .pick else { return }
        self.deck = deck
        PhonePlayHaptics.tap()
        stage = .ready
    }

    func backToDecks() {
        stopLoop()
        stopMotion()
        flash = nil
        stage = .pick
    }

    /// 3, 2, 1 -- then the first card.
    func startRound() {
        guard stage == .ready || stage == .summary else { return }
        results = []
        flash = nil
        refillQueue()
        countdown = 3
        countdownEnds = Date().addingTimeInterval(3)
        stage = .countdown
        PhonePlayHaptics.thump()
        if useTilt { startMotion() }
        startLoop()
    }

    func playAgain() {
        stage = .ready
        startRound()
    }

    func shutdown() {
        isActive = false
        stopLoop()
        stopMotion()
    }

    /// Tap fallback (and the on-screen buttons when tilt is off).
    func markCorrect() {
        guard stage == .playing, flash == nil else { return }
        record(.correct)
    }

    func markPass() {
        guard stage == .playing, flash == nil else { return }
        record(.pass)
    }

    func endEarly() {
        guard stage == .playing || stage == .countdown else { return }
        finishRound()
    }

    // MARK: - Loop

    private func startLoop() {
        stopLoop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_000_000)
                guard let self, self.isActive else { return }
                self.tick()
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    private func startMotion() {
        guard motionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        // Pull mode: the game loop reads the latest sample each frame.
        motion.startDeviceMotionUpdates()
    }

    private func stopMotion() {
        if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }
    }

    private func tick() {
        let now = Date()
        switch stage {
        case .countdown:
            let remaining = Int(ceil(countdownEnds.timeIntervalSince(now)))
            if remaining <= 0 {
                beginPlaying()
            } else if remaining != countdown {
                countdown = remaining
                PhonePlayHaptics.thump()
            }
        case .playing:
            let left = max(0, Int(ceil(roundEnds.timeIntervalSince(now))))
            if left != secondsLeft {
                secondsLeft = left
                if left > 0 && left <= 5 { PhonePlayHaptics.rigid() }
            }
            if left == 0 {
                finishRound()
                return
            }
            if useTilt { readTilt() }
        default:
            break
        }
    }

    private func beginPlaying() {
        secondsLeft = roundLength
        roundEnds = Date().addingTimeInterval(TimeInterval(roundLength))
        // The first card waits for the phone to be level on the forehead.
        armed = !useTilt
        levelFrames = 0
        tiltFrames = 0
        pendingTilt = nil
        nextWord()
        PhonePlayHaptics.success()
        stage = .playing
    }

    private func readTilt() {
        guard let sample = motion.deviceMotion else { return }
        let z: Double = sample.gravity.z
        if !armed {
            if abs(z) < levelThreshold {
                levelFrames += 1
                if levelFrames >= framesToLevel {
                    armed = true
                    tiltFrames = 0
                    pendingTilt = nil
                }
            } else {
                levelFrames = 0
            }
            return
        }
        guard flash == nil else { return }
        var detected: Flash? = nil
        if z > tiltThreshold {
            detected = .correct      // screen faces the floor
        } else if z < -tiltThreshold {
            detected = .pass         // screen faces the ceiling
        }
        guard let tilt = detected else {
            tiltFrames = 0
            pendingTilt = nil
            return
        }
        if tilt == pendingTilt {
            tiltFrames += 1
        } else {
            pendingTilt = tilt
            tiltFrames = 1
        }
        if tiltFrames >= framesToTilt {
            record(tilt)
        }
    }

    private func record(_ outcome: Flash) {
        let next = results.count
        results.append(HeadsUpResult(id: next, word: word, correct: outcome == .correct))
        if outcome == .correct {
            PhonePlayHaptics.success()
        } else {
            PhonePlayHaptics.warning()
        }
        flash = outcome
        tiltFrames = 0
        pendingTilt = nil
        if useTilt {
            armed = false
            levelFrames = 0
        }
        flashToken += 1
        let token = flashToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard let self, token == self.flashToken, self.stage == .playing else { return }
            self.nextWord()
            self.flash = nil
        }
    }

    private func finishRound() {
        stopLoop()
        stopMotion()
        flashToken += 1
        flash = nil
        secondsLeft = 0
        PhonePlayHaptics.thump()
        stage = .summary
    }

    // MARK: - Cards

    private func refillQueue() {
        // Unseen words first, then the longest-ago ones; remembered across
        // rounds, games and app launches.
        queue = dealer(for: deck).ordered(deck.words)
    }

    private func nextWord() {
        if queue.isEmpty { refillQueue() }
        guard !queue.isEmpty else {
            word = "?"
            return
        }
        let next = queue.removeFirst()
        var dealt = dealer(for: deck)
        dealt.mark(next)
        dealers[deck.id] = dealt
        word = next
    }
}
