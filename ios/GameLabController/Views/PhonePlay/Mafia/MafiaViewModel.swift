import SwiftUI

// MARK: - Mafia narrator
//
// One person narrates (and does not play). The phone deals roles by
// passing around, then the narrator holds it through the night: each step
// is read aloud in the Travel Mode voice while the narrator taps the
// players' silent choices. Day is open discussion and an elimination
// vote. The game ends when the Mafia are gone, or when they match the
// rest of the town in number.

enum MafiaRole: String {
    case mafia
    case doctor
    case detective
    case villager

    var title: String {
        switch self {
        case .mafia:     return "Mafia"
        case .doctor:    return "Doctor"
        case .detective: return "Detective"
        case .villager:  return "Villager"
        }
    }

    var symbol: String {
        switch self {
        case .mafia:     return "theatermasks.fill"
        case .doctor:    return "cross.case.fill"
        case .detective: return "magnifyingglass"
        case .villager:  return "house.fill"
        }
    }

    var color: Color {
        switch self {
        case .mafia:     return PhonePlayDesign.red
        case .doctor:    return PhonePlayDesign.green
        case .detective: return PhonePlayDesign.cyan
        case .villager:  return PhonePlayDesign.yellow
        }
    }

    var blurb: String {
        switch self {
        case .mafia:
            return "Each night, wake with the other Mafia and pick someone to eliminate. By day, act innocent."
        case .doctor:
            return "Each night, choose one person to save. You may save yourself."
        case .detective:
            return "Each night, point at a suspect. The narrator will tell you if they are Mafia."
        case .villager:
            return "Sleep through the night. By day, find the Mafia and vote them out."
        }
    }

    var isMafia: Bool { self == .mafia }
}

struct MafiaPlayer: Identifiable {
    let id: Int
    let name: String
    let role: MafiaRole
    var alive: Bool
}

enum MafiaWinner {
    case town
    case mafia
}

enum MafiaNightStep: Equatable {
    case sleep
    case mafiaWake
    case mafiaSleep
    case doctorWake
    case doctorSleep
    case detectiveWake
    case detectiveSleep

    static let order: [MafiaNightStep] = [
        .sleep, .mafiaWake, .mafiaSleep, .doctorWake, .doctorSleep, .detectiveWake, .detectiveSleep,
    ]

    var line: String {
        switch self {
        case .sleep:          return MafiaLines.sleep
        case .mafiaWake:      return MafiaLines.mafiaWake
        case .mafiaSleep:     return MafiaLines.mafiaSleep
        case .doctorWake:     return MafiaLines.doctorWake
        case .doctorSleep:    return MafiaLines.doctorSleep
        case .detectiveWake:  return MafiaLines.detectiveWake
        case .detectiveSleep: return MafiaLines.detectiveSleep
        }
    }

    var title: String {
        switch self {
        case .sleep:          return "Everyone sleeps"
        case .mafiaWake:      return "Mafia wake up"
        case .mafiaSleep:     return "Mafia sleep"
        case .doctorWake:     return "Doctor wakes up"
        case .doctorSleep:    return "Doctor sleeps"
        case .detectiveWake:  return "Detective wakes up"
        case .detectiveSleep: return "Detective sleeps"
        }
    }

    var role: MafiaRole? {
        switch self {
        case .mafiaWake, .mafiaSleep:         return .mafia
        case .doctorWake, .doctorSleep:       return .doctor
        case .detectiveWake, .detectiveSleep: return .detective
        case .sleep:                          return nil
        }
    }

    var needsPick: Bool {
        self == .mafiaWake || self == .doctorWake || self == .detectiveWake
    }

    var symbol: String {
        switch self {
        case .sleep:                                  return "moon.zzz.fill"
        case .mafiaWake, .doctorWake, .detectiveWake: return "eye.fill"
        default:                                      return "eye.slash.fill"
        }
    }
}

enum MafiaLines {
    static let sleep = "Night falls on the town. Everyone, close your eyes."
    static let mafiaWake = "Mafia, open your eyes. Silently agree on one person to eliminate, and point to them."
    static let mafiaSleep = "Mafia, close your eyes."
    static let doctorWake = "Doctor, open your eyes. Point to one person you want to save tonight."
    static let doctorSleep = "Doctor, close your eyes."
    static let detectiveWake = "Detective, open your eyes. Point to someone you suspect."
    static let detectiveSleep = "Detective, close your eyes."
    static let day = "Talk it over. Who do you think the Mafia are? When you are ready, vote."
    static let noElimination = "The town could not agree. Nobody is eliminated today."
    static let townWins = "All the Mafia are gone. The town wins!"
    static let mafiaWins = "The Mafia have taken over the town. The Mafia win!"
    static let saved = "Everyone, open your eyes. The Mafia struck last night, but the doctor got there first. Nobody was eliminated."

    static func victim(_ name: String) -> String {
        "Everyone, open your eyes. Sadly, last night \(name) was eliminated by the Mafia."
    }

    static func eliminated(_ name: String) -> String {
        "The town has spoken. \(name) is eliminated."
    }

    static let fixed: [String] = [
        sleep, mafiaWake, mafiaSleep, doctorWake, doctorSleep, detectiveWake, detectiveSleep,
        day, noElimination, townWins, mafiaWins, saved,
    ]
}

@MainActor
final class MafiaViewModel: ObservableObject {

    enum Stage { case setup, reveal, handoff, night, morning, day, gameOver }

    @Published var names: [String] {
        didSet { PhonePlayRoster.save(names) }
    }
    @Published var narrationOn: Bool = true

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var players: [MafiaPlayer] = []
    @Published private(set) var revealIndex: Int = 0
    @Published private(set) var stepIndex: Int = 0
    @Published private(set) var round: Int = 0
    @Published private(set) var mafiaTarget: Int? = nil
    @Published private(set) var doctorSave: Int? = nil
    @Published private(set) var detectiveCheck: Int? = nil
    /// Who died in the night; nil when the doctor saved them.
    @Published private(set) var nightVictim: Int? = nil
    @Published private(set) var dayVoteDone: Bool = false
    @Published private(set) var dayEliminated: Int? = nil
    @Published private(set) var winner: MafiaWinner? = nil

    let playerRange: ClosedRange<Int> = 5...15

    private let speech: TravelSpeech
    private var prepareTask: Task<Void, Never>? = nil
    private var narrationToken: Int = 0
    private var isActive: Bool = true
    private var lastLine: String = ""

    init(speech: TravelSpeech) {
        self.speech = speech
        names = Array(PhonePlayRoster.load().prefix(15))
    }

    // MARK: - Derived

    var canStart: Bool { playerRange.contains(names.count) }

    static func mafiaCount(for players: Int) -> Int {
        if players <= 6 { return 1 }
        if players <= 9 { return 2 }
        if players <= 12 { return 3 }
        return 4
    }

    var roleSummary: String {
        let n = names.count
        guard n >= playerRange.lowerBound else { return "Needs at least \(playerRange.lowerBound) players" }
        let mafia = Self.mafiaCount(for: n)
        let villagers = max(0, n - mafia - 2)
        let mafiaText = mafia == 1 ? "1 Mafia" : "\(mafia) Mafia"
        let villagerText = villagers == 1 ? "1 Villager" : "\(villagers) Villagers"
        return "\(mafiaText), 1 Doctor, 1 Detective, \(villagerText)"
    }

    var alivePlayers: [MafiaPlayer] { players.filter { $0.alive } }
    var mafiaAlive: Int { players.filter { $0.alive && $0.role.isMafia }.count }
    var townAlive: Int { players.filter { $0.alive && !$0.role.isMafia }.count }

    var currentStep: MafiaNightStep {
        let steps = MafiaNightStep.order
        return steps.indices.contains(stepIndex) ? steps[stepIndex] : .sleep
    }

    /// The role this step wakes is still in the game.
    var stepRoleAlive: Bool {
        guard let role = currentStep.role else { return true }
        return players.contains { $0.alive && $0.role == role }
    }

    /// Who the narrator may tap for the current step.
    var pickChoices: [MafiaPlayer] {
        switch currentStep {
        case .mafiaWake:     return players.filter { $0.alive && !$0.role.isMafia }
        case .doctorWake:    return alivePlayers
        case .detectiveWake: return players.filter { $0.alive && $0.role != .detective }
        default:             return []
        }
    }

    var currentPick: Int? {
        switch currentStep {
        case .mafiaWake:     return mafiaTarget
        case .doctorWake:    return doctorSave
        case .detectiveWake: return detectiveCheck
        default:             return nil
        }
    }

    var canAdvance: Bool {
        guard stage == .night else { return false }
        if currentStep.needsPick && stepRoleAlive { return currentPick != nil }
        return true
    }

    var isLastStep: Bool { stepIndex >= MafiaNightStep.order.count - 1 }

    func name(_ id: Int?) -> String {
        guard let pid = id, players.indices.contains(pid) else { return "" }
        return players[pid].name
    }

    // MARK: - Setup and roles

    func start() {
        guard canStart else { return }
        let n = names.count
        let mafia = Self.mafiaCount(for: n)
        var roles: [MafiaRole] = Array(repeating: .mafia, count: mafia)
        roles.append(.doctor)
        roles.append(.detective)
        while roles.count < n { roles.append(.villager) }
        roles.shuffle()
        players = names.enumerated().map { pair in
            MafiaPlayer(id: pair.offset, name: pair.element, role: roles[pair.offset], alive: true)
        }
        revealIndex = 0
        round = 0
        winner = nil
        stage = .reveal
        prepareVoice()
    }

    func nextReveal() {
        guard stage == .reveal else { return }
        if revealIndex + 1 < players.count {
            revealIndex += 1
        } else {
            PhonePlayHaptics.success()
            stage = .handoff
        }
    }

    func editPlayers() {
        speech.stop()
        narrationToken += 1
        stage = .setup
    }

    func newGame() {
        stage = .setup
        start()
    }

    func shutdown() {
        isActive = false
        narrationToken += 1
        prepareTask?.cancel()
        speech.stop()
    }

    // MARK: - Night

    func startNight() {
        guard stage == .handoff || stage == .day else { return }
        round += 1
        mafiaTarget = nil
        doctorSave = nil
        detectiveCheck = nil
        nightVictim = nil
        dayVoteDone = false
        dayEliminated = nil
        stepIndex = 0
        stage = .night
        PhonePlayHaptics.thump()
        narrate(currentStep.line)
    }

    func choose(_ playerID: Int) {
        guard stage == .night, currentStep.needsPick, stepRoleAlive,
              pickChoices.contains(where: { $0.id == playerID }) else { return }
        PhonePlayHaptics.tap()
        switch currentStep {
        case .mafiaWake:     mafiaTarget = playerID
        case .doctorWake:    doctorSave = playerID
        case .detectiveWake: detectiveCheck = playerID
        default:             break
        }
    }

    func advance() {
        guard canAdvance else { return }
        if isLastStep {
            resolveNight()
            return
        }
        stepIndex += 1
        PhonePlayHaptics.tap()
        narrate(currentStep.line)
    }

    func repeatLine() {
        guard !lastLine.isEmpty else { return }
        narrate(lastLine)
    }

    private func resolveNight() {
        if let target = mafiaTarget, target != doctorSave, players.indices.contains(target) {
            players[target].alive = false
            nightVictim = target
            PhonePlayHaptics.error()
            narrate(MafiaLines.victim(players[target].name))
        } else {
            nightVictim = nil
            PhonePlayHaptics.success()
            narrate(MafiaLines.saved)
        }
        stage = .morning
        checkWinner()
    }

    // MARK: - Day

    func startDay() {
        guard stage == .morning else { return }
        if let result = winner {
            finish(result)
            return
        }
        dayVoteDone = false
        dayEliminated = nil
        stage = .day
        narrate(MafiaLines.day)
    }

    func eliminate(_ playerID: Int?) {
        guard stage == .day, !dayVoteDone else { return }
        if let pid = playerID, players.indices.contains(pid), players[pid].alive {
            players[pid].alive = false
            dayEliminated = pid
            PhonePlayHaptics.thump()
            narrate(MafiaLines.eliminated(players[pid].name))
        } else {
            dayEliminated = nil
            PhonePlayHaptics.tap()
            narrate(MafiaLines.noElimination)
        }
        dayVoteDone = true
        checkWinner()
    }

    /// After the vote: on to the end screen, or another night.
    func continueAfterVote() {
        guard stage == .day, dayVoteDone else { return }
        if let result = winner {
            finish(result)
        } else {
            startNight()
        }
    }

    private func checkWinner() {
        if mafiaAlive == 0 {
            winner = .town
        } else if mafiaAlive >= townAlive {
            winner = .mafia
        } else {
            winner = nil
        }
    }

    private func finish(_ result: MafiaWinner) {
        winner = result
        stage = .gameOver
        PhonePlayHaptics.success()
        narrate(result == .town ? MafiaLines.townWins : MafiaLines.mafiaWins)
    }

    // MARK: - Voice

    /// Decide the voice once, early (while roles are being dealt), so the
    /// whole game is narrated in one consistent voice.
    private func prepareVoice() {
        guard prepareTask == nil else { return }
        let speech = self.speech
        speech.configureSession(withMic: false)
        prepareTask = Task { @MainActor in
            await speech.prepare(firstLine: MafiaLines.sleep, timeout: 4)
            for line in MafiaLines.fixed {
                speech.prefetch(line)
            }
        }
    }

    private func narrate(_ line: String) {
        lastLine = line
        guard narrationOn, isActive else { return }
        narrationToken += 1
        let token = narrationToken
        let waitFor = prepareTask
        Task { [weak self] in
            _ = await waitFor?.value
            guard let self, self.isActive, token == self.narrationToken else { return }
            self.speech.speak(line)
        }
    }

    func setNarration(_ on: Bool) {
        narrationOn = on
        if !on {
            narrationToken += 1
            speech.stop()
        }
    }
}
