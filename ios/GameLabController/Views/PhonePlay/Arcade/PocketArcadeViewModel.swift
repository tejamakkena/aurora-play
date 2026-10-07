import SwiftUI

// MARK: - Pocket Arcade
//
// Three quick solo touch games with best scores kept in UserDefaults:
//  - Tap the Lights: one cell of a 4x4 grid lights up at a time; tap it
//    before it goes out. The window shrinks as you score. 30 seconds.
//  - Number Rush: tap 1 to 25 in order on a shuffled 5x5 grid as fast as
//    you can. A wrong tap adds a one-second penalty.
//  - 2048: swipe to slide and merge tiles (Arcade2048Model.swift). No
//    countdown and no clock; one undo per game.

enum PocketArcadeGame: String, CaseIterable, Identifiable {
    case lights
    case rush
    case twenty48

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lights: return "Tap the Lights"
        case .rush:   return "Number Rush"
        case .twenty48: return "2048"
        }
    }

    var blurb: String {
        switch self {
        case .lights: return "Tap each light before it fades. 30 seconds."
        case .rush:   return "Tap 1 to 25 in order. Wrong taps cost a second."
        case .twenty48: return "Swipe to slide and merge tiles. One undo per game."
        }
    }

    var symbol: String {
        switch self {
        case .lights: return "lightbulb.max.fill"
        case .rush:   return "number.square.fill"
        case .twenty48: return "square.grid.3x3.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .lights: return [PhonePlayDesign.yellow, PhonePlayDesign.orange]
        case .rush:   return [PhonePlayDesign.cyan, PhonePlayDesign.indigo]
        case .twenty48: return [PhonePlayDesign.orange, PhonePlayDesign.pink]
        }
    }
}

enum PocketArcadeStore {
    private static let lightsKey = "phoneplay_arcade_lights_best"
    private static let rushKey = "phoneplay_arcade_rush_best"
    private static let tilesKey = "phoneplay_arcade_2048_best"

    /// Most lights hit in a round; 0 when never played.
    static var bestLights: Int {
        UserDefaults.standard.integer(forKey: lightsKey)
    }

    /// Fastest Number Rush in seconds; 0 when never played.
    static var bestRush: Double {
        UserDefaults.standard.double(forKey: rushKey)
    }

    /// Highest 2048 score; 0 when never played.
    static var bestTiles: Int {
        UserDefaults.standard.integer(forKey: tilesKey)
    }

    /// Saves the score if it is a new best and says whether it was.
    static func submitLights(_ hits: Int) -> Bool {
        guard hits > bestLights else { return false }
        UserDefaults.standard.set(hits, forKey: lightsKey)
        return true
    }

    static func submitRush(_ seconds: Double) -> Bool {
        let best = bestRush
        guard seconds > 0, best <= 0 || seconds < best else { return false }
        UserDefaults.standard.set(seconds, forKey: rushKey)
        return true
    }

    static func submitTiles(_ score: Int) -> Bool {
        guard score > bestTiles else { return false }
        UserDefaults.standard.set(score, forKey: tilesKey)
        return true
    }

    static func rushText(_ seconds: Double) -> String {
        String(format: "%.2fs", max(0, seconds))
    }
}

@MainActor
final class PocketArcadeViewModel: ObservableObject {

    enum Stage { case menu, countdown, playing, finished }

    @Published private(set) var game: PocketArcadeGame = .lights
    @Published private(set) var stage: Stage = .menu
    @Published private(set) var countdown: Int = 3

    // Tap the Lights
    @Published private(set) var litCell: Int? = nil
    @Published private(set) var hitCell: Int? = nil
    @Published private(set) var wrongCell: Int? = nil
    @Published private(set) var hits: Int = 0
    @Published private(set) var misses: Int = 0
    @Published private(set) var secondsLeft: Int = 30

    // Number Rush
    @Published private(set) var numbers: [Int] = []
    @Published private(set) var nextNumber: Int = 1
    @Published private(set) var penalty: Double = 0
    @Published private(set) var startedAt: Date = Date()

    // Result
    @Published private(set) var resultSeconds: Double = 0
    @Published private(set) var newBest: Bool = false
    @Published private(set) var bestLights: Int = PocketArcadeStore.bestLights
    @Published private(set) var bestRush: Double = PocketArcadeStore.bestRush
    @Published private(set) var bestTiles: Int = PocketArcadeStore.bestTiles

    // 2048: the board has its own model; these are the finished game's.
    let twenty48 = Arcade2048Model()
    @Published private(set) var tilesScore: Int = 0
    @Published private(set) var tilesBiggest: Int = 0

    let lightsCells: Int = 16
    let lightsColumns: Int = 4
    let rushCount: Int = 25
    let rushColumns: Int = 5
    let roundLength: Int = 30

    /// Average reaction time of the hits, in milliseconds.
    var averageReactionMs: Int {
        guard !reactions.isEmpty else { return 0 }
        return Int((reactions.reduce(0, +) / Double(reactions.count) * 1000).rounded())
    }

    private var loop: Task<Void, Never>? = nil
    private var countdownEnds: Date = Date()
    private var roundEnds: Date = Date()
    private var litAt: Date = Date()
    private var lightDeadline: Date = Date()
    private var reactions: [Double] = []
    private var flashToken: Int = 0
    private var isActive: Bool = true

    // MARK: - Flow

    func play(_ choice: PocketArcadeGame) {
        game = choice
        PhonePlayHaptics.thump()
        if choice == .twenty48 {
            // Not against the clock, so no countdown.
            stopLoop()
            begin()
            return
        }
        countdown = 3
        countdownEnds = Date().addingTimeInterval(3)
        stage = .countdown
        startLoop()
    }

    func playAgain() {
        play(game)
    }

    func backToMenu() {
        stopLoop()
        if game == .twenty48 && stage == .playing {
            saveTilesBest()
        }
        litCell = nil
        stage = .menu
    }

    func shutdown() {
        isActive = false
        stopLoop()
        if game == .twenty48 && stage == .playing {
            saveTilesBest()
        }
        twenty48.shutdown()
    }

    // MARK: - Loop

    private func startLoop() {
        stopLoop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard let self, self.isActive, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    private func tick() {
        let now = Date()
        switch stage {
        case .countdown:
            let remaining = Int(ceil(countdownEnds.timeIntervalSince(now)))
            if remaining <= 0 {
                begin()
            } else if remaining != countdown {
                countdown = remaining
                PhonePlayHaptics.rigid()
            }
        case .playing:
            switch game {
            case .lights:
                let left = max(0, Int(ceil(roundEnds.timeIntervalSince(now))))
                if left != secondsLeft { secondsLeft = left }
                if left == 0 {
                    finishLights()
                    return
                }
                if now >= lightDeadline {
                    // Too slow: it fades and another lights up.
                    misses += 1
                    lightNext(after: litCell)
                }
            case .rush:
                // Number Rush is driven by taps; the view shows the clock.
                stopLoop()
            case .twenty48:
                // 2048 is driven by swipes and has no clock.
                stopLoop()
            }
        case .menu, .finished:
            stopLoop()
        }
    }

    private func begin() {
        PhonePlayHaptics.success()
        newBest = false
        switch game {
        case .lights:
            hits = 0
            misses = 0
            reactions = []
            hitCell = nil
            wrongCell = nil
            secondsLeft = roundLength
            roundEnds = Date().addingTimeInterval(TimeInterval(roundLength))
            stage = .playing
            lightNext(after: nil)
        case .rush:
            numbers = Array(1...rushCount).shuffled()
            nextNumber = 1
            penalty = 0
            wrongCell = nil
            startedAt = Date()
            stage = .playing
            stopLoop()
        case .twenty48:
            twenty48.newGame()
            stage = .playing
            stopLoop()
        }
    }

    // MARK: - Tap the Lights

    /// How long a light stays on: 1.1 s at first, down to 0.45 s.
    private var lightWindow: Double {
        max(0.45, 1.1 - Double(hits) * 0.025)
    }

    private func lightNext(after previous: Int?) {
        var cell = Int.random(in: 0..<lightsCells)
        if let previous, cell == previous {
            cell = (cell + Int.random(in: 1..<lightsCells)) % lightsCells
        }
        litCell = cell
        litAt = Date()
        lightDeadline = litAt.addingTimeInterval(lightWindow)
    }

    func tapLight(_ cell: Int) {
        guard stage == .playing, game == .lights else { return }
        if cell == litCell {
            hits += 1
            reactions.append(Date().timeIntervalSince(litAt))
            PhonePlayHaptics.tap()
            flash(hit: cell)
            lightNext(after: cell)
        } else {
            misses += 1
            PhonePlayHaptics.error()
            flash(wrong: cell)
        }
    }

    private func flash(hit: Int? = nil, wrong: Int? = nil) {
        if let hit { hitCell = hit }
        if let wrong { wrongCell = wrong }
        flashToken += 1
        let token = flashToken
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, token == self.flashToken else { return }
            self.hitCell = nil
            self.wrongCell = nil
        }
    }

    private func finishLights() {
        stopLoop()
        litCell = nil
        newBest = PocketArcadeStore.submitLights(hits)
        bestLights = PocketArcadeStore.bestLights
        if newBest { PhonePlayHaptics.success() } else { PhonePlayHaptics.thump() }
        stage = .finished
    }

    // MARK: - Number Rush

    func tapNumber(at index: Int) {
        guard stage == .playing, game == .rush, numbers.indices.contains(index) else { return }
        let value = numbers[index]
        if value < nextNumber { return }   // already cleared
        if value == nextNumber {
            PhonePlayHaptics.tap()
            if nextNumber >= rushCount {
                finishRush()
            } else {
                nextNumber += 1
            }
        } else {
            penalty += 1
            PhonePlayHaptics.error()
            flash(wrong: index)
        }
    }

    private func finishRush() {
        let raw = Date().timeIntervalSince(startedAt)
        resultSeconds = (raw + penalty) * 100
        resultSeconds = resultSeconds.rounded() / 100
        nextNumber = rushCount + 1
        newBest = PocketArcadeStore.submitRush(resultSeconds)
        bestRush = PocketArcadeStore.bestRush
        if newBest { PhonePlayHaptics.success() } else { PhonePlayHaptics.thump() }
        stage = .finished
    }

    // MARK: - 2048

    /// Ends the 2048 game (stuck, or finished after reaching 2048) and
    /// shows the result screen.
    func finishTiles() {
        guard stage == .playing, game == .twenty48 else { return }
        tilesScore = twenty48.score
        tilesBiggest = twenty48.biggestTile
        newBest = twenty48.commitBest()
        bestTiles = PocketArcadeStore.bestTiles
        if newBest { PhonePlayHaptics.success() } else { PhonePlayHaptics.thump() }
        stage = .finished
    }

    private func saveTilesBest() {
        twenty48.commitBest()
        bestTiles = PocketArcadeStore.bestTiles
    }
}
