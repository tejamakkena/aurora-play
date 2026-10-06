import AudioToolbox
import SwiftUI

// MARK: - Hot Potato
//
// A category goes up ("Things in a kitchen"). The holder names one thing
// in it and passes the phone on. A hidden fuse of 15 to 45 seconds ticks
// faster and faster; whoever is holding the phone when it goes off takes
// a burn. Fewest burns wins. Ticks are a haptic plus an optional click.

@MainActor
final class HotPotatoViewModel: ObservableObject {

    enum Stage { case setup, ready, burning, boom }

    @Published var names: [String] {
        didSet { PhonePlayRoster.save(names) }
    }
    @Published var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: HotPotatoViewModel.soundKey) }
    }

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var category: String = ""
    @Published private(set) var holder: Int = 0
    @Published private(set) var loser: Int? = nil
    @Published private(set) var burns: [String: Int] = [:]
    @Published private(set) var tick: Int = 0
    /// 0 when the fuse is lit, 1 when it goes off; drives the colour.
    @Published private(set) var heat: Double = 0
    @Published private(set) var passes: Int = 0
    @Published private(set) var round: Int = 0
    @Published private(set) var aiState: PhonePlayAIState = .idle

    let playerRange: ClosedRange<Int> = 2...12

    var canStart: Bool { playerRange.contains(names.count) }
    var holderName: String { names.indices.contains(holder) ? names[holder] : "" }
    var loserName: String {
        guard let index = loser, names.indices.contains(index) else { return "" }
        return names[index]
    }
    var categoryCount: Int { HotPotatoDeck.categories.count + extras.count }

    /// Everyone's burns, fewest first (ties keep seating order).
    var standings: [(name: String, burns: Int)] {
        let rows = names.enumerated().map { (offset: $0.offset, name: $0.element, burns: burns[$0.element] ?? 0) }
        return rows
            .sorted { $0.burns != $1.burns ? $0.burns < $1.burns : $0.offset < $1.offset }
            .map { (name: $0.name, burns: $0.burns) }
    }

    private var extras: [String] = []
    private var dealer = PhonePlayDealer()
    private var fuse: Double = 30
    private var litAt: Date = Date()
    private var loop: Task<Void, Never>? = nil
    private var aiTask: Task<Void, Never>? = nil
    private var token: Int = 0
    private var isActive: Bool = true

    private static let soundKey = "phoneplay_hotpotato_sound"
    /// The keyboard click: short, and silent when the ringer is off.
    private static let tickSound: SystemSoundID = 1104

    init() {
        names = Array(PhonePlayRoster.load().prefix(12))
        let defaults = UserDefaults.standard
        soundOn = defaults.object(forKey: HotPotatoViewModel.soundKey) == nil
            ? true : defaults.bool(forKey: HotPotatoViewModel.soundKey)
    }

    // MARK: - Flow

    func start() {
        guard canStart else { return }
        stopLoop()
        burns = [:]
        round = 0
        loser = nil
        holder = Int.random(in: 0..<names.count)
        dealCategory()
        PhonePlayHaptics.thump()
        stage = .ready
    }

    func newCategory() {
        guard stage == .ready else { return }
        dealCategory()
        PhonePlayHaptics.tap()
    }

    func light() {
        guard stage == .ready, names.count >= 2 else { return }
        fuse = Double.random(in: 15...45)
        litAt = Date()
        tick = 0
        heat = 0
        passes = 0
        loser = nil
        round += 1
        PhonePlayHaptics.thump()
        stage = .burning
        startLoop()
    }

    func pass() {
        guard stage == .burning, names.count >= 2 else { return }
        holder = (holder + 1) % names.count
        passes += 1
        PhonePlayHaptics.tap()
    }

    /// Put the fuse out without anyone scoring.
    func stopRound() {
        guard stage == .burning else { return }
        stopLoop()
        heat = 0
        stage = .ready
    }

    func nextRound() {
        guard stage == .boom else { return }
        // Whoever got burned starts the next round.
        if let burned = loser, names.indices.contains(burned) { holder = burned }
        dealCategory()
        stage = .ready
    }

    func editPlayers() {
        stopLoop()
        stage = .setup
    }

    func shutdown() {
        isActive = false
        stopLoop()
        aiTask?.cancel()
        aiTask = nil
    }

    private func dealCategory() {
        let pool = HotPotatoDeck.categories + extras
        category = dealer.draw(from: pool) ?? "Things you find in a kitchen"
    }

    // MARK: - The fuse

    private func startLoop() {
        stopLoop()
        token += 1
        let myToken = token
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive, myToken == self.token, self.stage == .burning else { return }
                let wait = self.nextWait()
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.step(token: myToken)
            }
        }
    }

    private func stopLoop() {
        token += 1
        loop?.cancel()
        loop = nil
    }

    /// Seconds until the next tick: about one a second at first, five a
    /// second at the end, never past the moment the fuse runs out.
    private func nextWait() -> Double {
        let elapsed = Date().timeIntervalSince(litAt)
        let fraction = min(1, max(0, elapsed / fuse))
        let interval = 0.95 - 0.75 * pow(fraction, 1.4)
        let remaining = max(0.02, fuse - elapsed)
        return min(max(0.18, interval), remaining)
    }

    private func step(token myToken: Int) {
        guard isActive, myToken == token, stage == .burning else { return }
        let elapsed = Date().timeIntervalSince(litAt)
        heat = min(1, max(0, elapsed / fuse))
        if elapsed >= fuse {
            explode()
            return
        }
        tick += 1
        if heat > 0.7 {
            PhonePlayHaptics.rigid()
        } else {
            PhonePlayHaptics.tap()
        }
        if soundOn {
            AudioServicesPlaySystemSound(HotPotatoViewModel.tickSound)
        }
    }

    private func explode() {
        stopLoop()
        heat = 1
        loser = holder
        let name = holderName
        if !name.isEmpty {
            burns[name, default: 0] += 1
        }
        stage = .boom
        PhonePlayHaptics.thump()
        PhonePlayHaptics.error()
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        // A short rumble of heavy hits after the bang.
        let myToken = token
        Task { [weak self] in
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self, self.isActive, myToken == self.token else { return }
                PhonePlayHaptics.thump()
            }
        }
    }

    // MARK: - Fresh AI categories

    func fetchFreshCards() {
        guard aiState != .loading else { return }
        aiState = .loading
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            let items: [String] = await OneStopAPI.deck(kind: "hotpotato",
                                                        topic: "everyday life, food, films, sport and fun",
                                                        count: 25, familySafe: true, language: "en")
            guard let self, self.isActive else { return }
            var known = HotPotatoDeck.categories + self.extras
            let start = known.count
            let added = PhonePlayAIDecks.merge(items, into: &known)
            if added > 0 {
                self.extras.append(contentsOf: known[start...])
                PhonePlayHaptics.success()
            }
            self.aiState = added > 0 ? .added(added) : .idle
        }
    }
}
