import SwiftUI

// MARK: - Spy (pass and reveal)
//
// Everyone but one player is shown the same secret location; the spy is
// only told they are the spy. Players take turns asking each other
// questions, trying to flush out the spy without giving the place away,
// while the spy tries to blend in and work out where they are.

enum SpyLocations {
    static let all: [String] = [
        "Airport", "Beach", "Bank", "Cricket Stadium", "Cinema Hall",
        "Hospital", "School", "Train Station", "Space Station", "Pirate Ship",
        "Zoo", "Circus", "Library", "Museum", "Restaurant",
        "Wedding", "Supermarket", "Police Station", "Fire Station", "Temple",
        "Hotel", "Submarine", "Farm", "Amusement Park", "Bakery",
        "Movie Set", "Swimming Pool", "Gym", "Hair Salon", "Post Office",
        "Mountain Camp", "Desert Safari", "Jungle Trek", "Ice Rink", "Aquarium",
        "Bus Stop", "Petrol Pump", "Car Wash", "Birthday Party", "Classroom",
        "Dentist Clinic", "Railway Sleeper Coach", "Houseboat", "Tea Estate", "Night Market",
        "Concert", "Science Lab", "Palace", "Lighthouse", "Ferris Wheel",
    ]
}

@MainActor
final class SpyViewModel: ObservableObject {

    enum Stage { case setup, reveal, discuss, vote, result }

    @Published var names: [String] {
        didSet { PhonePlayRoster.save(names) }
    }
    @Published var discussMinutes: Int = 5

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var revealIndex: Int = 0
    @Published private(set) var location: String = ""
    @Published private(set) var spyIndex: Int = 0
    @Published private(set) var firstAsker: Int = 0
    @Published private(set) var secondsLeft: Int = 0
    @Published private(set) var paused: Bool = false
    @Published private(set) var accused: Int? = nil
    @Published private(set) var roundsPlayed: Int = 0

    let playerRange: ClosedRange<Int> = 2...12
    let minuteChoices: [Int] = [3, 5, 8]

    var canStart: Bool { playerRange.contains(names.count) }
    var spyName: String { names.indices.contains(spyIndex) ? names[spyIndex] : "" }
    var accusedName: String {
        guard let index = accused, names.indices.contains(index) else { return "" }
        return names[index]
    }
    var spyCaught: Bool { accused == spyIndex }

    private var timer: Task<Void, Never>? = nil
    private var lastLocations: [String] = []

    init() {
        let saved = PhonePlayRoster.load()
        names = Array(saved.prefix(12))
    }

    // MARK: - Flow

    func start() {
        guard canStart else { return }
        stopTimer()
        let fresh = SpyLocations.all.filter { !lastLocations.contains($0) }
        location = (fresh.randomElement() ?? SpyLocations.all.randomElement()) ?? "Beach"
        lastLocations.append(location)
        if lastLocations.count > 10 { lastLocations.removeFirst() }
        spyIndex = Int.random(in: 0..<names.count)
        firstAsker = Int.random(in: 0..<names.count)
        revealIndex = 0
        accused = nil
        paused = false
        stage = .reveal
    }

    /// The current player has seen their card and hidden it again.
    func nextReveal() {
        guard stage == .reveal else { return }
        if revealIndex + 1 < names.count {
            revealIndex += 1
        } else {
            beginDiscussion()
        }
    }

    func togglePause() {
        guard stage == .discuss else { return }
        paused.toggle()
        PhonePlayHaptics.tap()
    }

    func goToVote() {
        guard stage == .discuss else { return }
        stopTimer()
        PhonePlayHaptics.thump()
        stage = .vote
    }

    func accuse(_ index: Int) {
        guard stage == .vote, names.indices.contains(index) else { return }
        accused = index
        roundsPlayed += 1
        if index == spyIndex {
            PhonePlayHaptics.success()
        } else {
            PhonePlayHaptics.error()
        }
        stage = .result
    }

    func playAgain() {
        stage = .setup
        start()
    }

    func editPlayers() {
        stopTimer()
        stage = .setup
    }

    func shutdown() {
        stopTimer()
    }

    // MARK: - Discussion timer

    private func beginDiscussion() {
        secondsLeft = discussMinutes * 60
        paused = false
        stage = .discuss
        PhonePlayHaptics.success()
        stopTimer()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.second()
            }
        }
    }

    private func second() {
        guard stage == .discuss, !paused else { return }
        secondsLeft = max(0, secondsLeft - 1)
        if secondsLeft <= 10 && secondsLeft > 0 {
            PhonePlayHaptics.rigid()
        }
        if secondsLeft == 0 {
            PhonePlayHaptics.warning()
            goToVote()
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}
