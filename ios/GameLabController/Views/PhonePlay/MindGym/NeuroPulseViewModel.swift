import SwiftUI

// MARK: - Mind Gym: the daily ten-step workout
//
// One screen drives all ten steps (NeuroRunnerView); this holds the state
// that walks through them. Nothing here waits on the network: the session
// comes from the cache, or is built on the phone (NeuroFallback), before
// the first frame, and a fetch that lands later is adopted only while the
// player has not answered anything, so a session never changes underneath
// them. A finished session is queued the moment it ends and posted when
// the player taps Done, so a kill on the results screen still reaches the
// server on the next launch.

/// One dot on the ten-dot rail.
enum NeuroRailMark: Equatable {
    case right
    case wrong
    case rested        // breathing / sensory: completed, never graded
    case current
    case upcoming
}

@MainActor
final class NeuroPulseViewModel: ObservableObject {

    enum Stage: Equatable {
        case running
        case results
        case progress
    }

    /// Where a step is: showing what has to be remembered, waiting for the
    /// answer, or holding the right/wrong beat.
    enum Phase: Equatable {
        case flash
        case answer
        case feedback(correct: Bool)
    }

    // MARK: Published state

    @Published private(set) var stage: Stage = .running
    @Published private(set) var session: NeuroSession
    @Published private(set) var stepIndex: Int = 0
    @Published private(set) var phase: Phase = .answer
    @Published private(set) var answers: [NeuroAnswer] = []
    @Published private(set) var streak: Int = 0

    /// Per-step input.
    @Published private(set) var typed: String = ""
    @Published private(set) var tapped: [Int] = []
    @Published private(set) var chosen: String? = nil
    @Published private(set) var hintShown: Bool = false

    /// The flash phase: which letter of an n-back run is showing.
    @Published private(set) var flashLetterIndex: Int = 0

    /// The breathing pacer.
    @Published private(set) var breathPhase: Int = 0
    @Published private(set) var breathCycle: Int = 1
    @Published private(set) var breathSecondsLeft: Int = 0

    /// The sensory reset's countdown.
    @Published private(set) var reflectSecondsLeft: Int = 0

    /// When the answer could first be given, for the cosmetic ring.
    @Published private(set) var stepStartedAt: Date = Date()

    @Published private(set) var summary: NeuroSummary? = nil
    /// How long the finished workout took, frozen when it ended.
    @Published private(set) var finishedSeconds: Int = 0
    @Published private(set) var mood: Int = 0
    @Published private(set) var profile: NeuroProfile = NeuroProfile()
    @Published private(set) var friends: [NeuroLeaderRow] = []
    @Published private(set) var everyone: [NeuroLeaderRow] = []
    @Published private(set) var loadingProgress: Bool = false

    // MARK: Private state

    let today: String
    /// True when the Mind Gym was opened straight onto the Mind Score
    /// screen from the home card's Progress link: closing it leaves.
    let progressIsRoot: Bool

    private var sessionStartedAt: Date = Date()
    private var zenSeconds: Int = 0
    private var resultBody: [String: Any] = [:]
    private var phaseToken: Int = 0
    private var isActive: Bool = true
    private var network: Task<Void, Never>? = nil
    private var adopted: Bool = false

    // MARK: Init

    init(date: String = NeuroStore.todayKey(), startOnProgress: Bool = false) {
        today = date
        progressIsRoot = startOnProgress
        let cachedProfile = NeuroStore.profile()
        if let cached = cachedProfile {
            profile = cached
            streak = cached.streak
        }
        if let cached = NeuroStore.session(for: date) {
            session = cached
            streak = max(streak, cached.streak)
        } else {
            let built = NeuroFallback.session(date: date, profile: cachedProfile)
            session = built
            NeuroStore.saveSession(built)
        }
        if startOnProgress { stage = .progress }
        restoreProgress()
        beginStep()
        refresh()
        if startOnProgress { loadProgress() }
    }

    // MARK: Derived

    var steps: [NeuroStep] { session.steps }

    var step: NeuroStep? {
        session.steps.indices.contains(stepIndex) ? session.steps[stepIndex] : nil
    }

    var totalSteps: Int { max(session.steps.count, 1) }

    var disciplineName: String {
        guard let step else { return "" }
        if let fromServer = session.names[step.discipline], !fromServer.isEmpty {
            return fromServer
        }
        return step.skill.isEmpty
            ? NeuroDiscipline.name(step.discipline, names: session.names)
            : step.skill
    }

    /// How long the workout has been running, including a resumed part.
    var elapsedSeconds: Int {
        max(0, Int(Date().timeIntervalSince(sessionStartedAt).rounded()))
    }

    func mark(at index: Int) -> NeuroRailMark {
        if let answer = answers.first(where: { $0.index == index }) {
            if NeuroScoring.ungradedKinds.contains(answer.kind) { return .rested }
            return answer.correct ? .right : .wrong
        }
        if index == stepIndex { return .current }
        return .upcoming
    }

    /// The ring at the top is cosmetic: running over the target time never
    /// fails a step, it just fills up.
    var targetSeconds: Double {
        guard let step, step.targetResponseMs > 0 else { return 0 }
        return Double(step.targetResponseMs) / 1000.0
    }

    var hintAvailable: Bool {
        guard let step, !step.hint.isEmpty, phase == .answer else { return false }
        return step.isGraded && !hintShown
    }

    var canSubmitNumber: Bool {
        phase == .answer && !typed.isEmpty
    }

    var breathPhaseSeconds: Double {
        guard let step else { return 4 }
        let pattern = step.visual.breathPattern
        let index = max(0, min(pattern.count - 1, breathPhase))
        return Double(pattern[index])
    }

    var breathCycles: Int { max(1, step?.visual.cycles ?? 1) }

    // MARK: Step flow

    private func restoreProgress() {
        guard let saved = NeuroStore.progress(for: today), saved.isStarted else { return }
        guard saved.index < session.steps.count else { return }
        answers = saved.answers
        stepIndex = saved.index
        zenSeconds = saved.zenSeconds
        sessionStartedAt = Date().addingTimeInterval(-Double(max(0, saved.seconds)))
        adopted = true          // a resumed session is never swapped underneath
    }

    private func beginStep() {
        phaseToken += 1
        let token = phaseToken
        typed = ""
        tapped = []
        chosen = nil
        hintShown = false
        flashLetterIndex = 0
        breathPhase = 0
        breathCycle = 1
        breathSecondsLeft = 0
        reflectSecondsLeft = 0
        guard let step else { return }

        switch step.inputStyle {
        case .breathe:
            phase = .answer
            stepStartedAt = Date()
            runBreathing(step: step, token: token)
        case .reflect:
            phase = .answer
            stepStartedAt = Date()
            reflectSecondsLeft = max(10, step.visual.seconds > 0 ? step.visual.seconds : 30)
            runReflect(token: token)
        case .choice, .number, .grid:
            if needsFlash(step) {
                phase = .flash
                runFlash(step: step, token: token)
            } else {
                phase = .answer
                stepStartedAt = Date()
            }
        }
    }

    private func needsFlash(_ step: NeuroStep) -> Bool {
        switch step.kind {
        case "flash": return !step.visual.flashDigits.isEmpty
        case "nback": return !step.visual.flashLetters.isEmpty
        case "grid":  return !step.visual.cells.isEmpty
        default:      return false
        }
    }

    /// Shows what has to be remembered, then opens the answer.
    private func runFlash(step: NeuroStep, token: Int) {
        let ms = max(400, step.visual.flashMs > 0 ? step.visual.flashMs : 2000)
        let letters = step.visual.flashLetters
        if step.kind == "nback", !letters.isEmpty {
            Task { [weak self] in
                for index in letters.indices {
                    guard let me = self, me.isActive, token == me.phaseToken else { return }
                    me.flashLetterIndex = index
                    PhonePlayHaptics.tap()
                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                }
                guard let me = self, me.isActive, token == me.phaseToken else { return }
                me.openAnswer()
            }
            return
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            guard let me = self, me.isActive, token == me.phaseToken else { return }
            me.openAnswer()
        }
    }

    private func openAnswer() {
        phase = .answer
        stepStartedAt = Date()
        PhonePlayHaptics.rigid()
    }

    // MARK: Breathing and reflecting

    private func runBreathing(step: NeuroStep, token: Int) {
        let pattern = step.visual.breathPattern
        let cycles = max(1, step.visual.cycles)
        breathSecondsLeft = pattern.first ?? 4
        Task { [weak self] in
            for cycle in 1...cycles {
                for phaseIndex in pattern.indices {
                    let seconds = pattern[phaseIndex]
                    guard let me = self, me.isActive, token == me.phaseToken else { return }
                    me.breathCycle = cycle
                    me.breathPhase = phaseIndex
                    me.breathSecondsLeft = seconds
                    PhonePlayHaptics.rigid()
                    for _ in 0..<seconds {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        guard let inner = self, inner.isActive,
                              token == inner.phaseToken else { return }
                        inner.breathSecondsLeft = max(0, inner.breathSecondsLeft - 1)
                        inner.zenSeconds += 1
                    }
                }
            }
            guard let me = self, me.isActive, token == me.phaseToken else { return }
            me.completeRest()
        }
    }

    private func runReflect(token: Int) {
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let me = self, me.isActive, token == me.phaseToken else { return }
                me.zenSeconds += 1
                me.reflectSecondsLeft = max(0, me.reflectSecondsLeft - 1)
                if me.reflectSecondsLeft == 0 {
                    me.completeRest()
                    return
                }
            }
        }
    }

    // MARK: Answering

    func choose(_ option: String) {
        guard phase == .answer, chosen == nil, let step, step.inputStyle == .choice else { return }
        chosen = option
        record(step: step, correct: step.isCorrect(option))
    }

    func tapDigit(_ digit: Int) {
        guard phase == .answer, typed.count < 12 else { return }
        PhonePlayHaptics.tap()
        typed += String(max(0, min(9, digit)))
    }

    func deleteDigit() {
        guard phase == .answer, !typed.isEmpty else { return }
        PhonePlayHaptics.tap()
        typed.removeLast()
    }

    func submitNumber() {
        guard phase == .answer, let step, step.inputStyle == .number, !typed.isEmpty else { return }
        record(step: step, correct: step.isCorrect(typed))
    }

    /// Taps toggle, and the step submits itself once as many cells are lit
    /// as the answer wants.
    func tapCell(_ cell: Int) {
        guard phase == .answer, let step, step.inputStyle == .grid else { return }
        PhonePlayHaptics.tap()
        if let existing = tapped.firstIndex(of: cell) {
            tapped.remove(at: existing)
            return
        }
        tapped.append(cell)
        let wanted = step.gridAnswerCount
        guard wanted > 0, tapped.count >= wanted else { return }
        record(step: step, correct: step.isCorrect(NeuroStep.gridAnswer(Set(tapped))))
    }

    /// Breathing and the sensory reset: never graded, always completed.
    private func completeRest() {
        guard let step else { return }
        record(step: step, correct: false, completed: true)
    }

    /// Skip is always available on the Zen steps.
    func skipRest() {
        guard let step, !step.isGraded else { return }
        phaseToken += 1
        record(step: step, correct: false, completed: true)
    }

    func revealHint() {
        guard hintAvailable else { return }
        PhonePlayHaptics.tap()
        hintShown = true
    }

    /// A taken hint still counts, and `responseMs` is recorded honestly.
    private func record(step: NeuroStep, correct: Bool, completed: Bool = true) {
        let responseMs = max(0, Int(Date().timeIntervalSince(stepStartedAt) * 1000))
        let answer = NeuroAnswer(index: step.index,
                                 discipline: step.discipline,
                                 kind: step.kind,
                                 level: step.level,
                                 eloTarget: step.eloTarget,
                                 targetResponseMs: step.targetResponseMs,
                                 responseMs: responseMs,
                                 correct: step.isGraded ? correct : false,
                                 completed: completed)
        answers.removeAll { $0.index == step.index }
        answers.append(answer)
        saveProgress(index: stepIndex)
        if step.isGraded {
            if correct {
                PhonePlayHaptics.success()
            } else {
                PhonePlayHaptics.error()
            }
        } else {
            PhonePlayHaptics.tap()
        }
        phase = .feedback(correct: correct)
        phaseToken += 1
        let token = phaseToken
        let pause: UInt64 = step.isGraded
            ? (correct ? 1_300_000_000 : 2_300_000_000)
            : 1_200_000_000
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: pause)
            guard let me = self, me.isActive, token == me.phaseToken else { return }
            me.advance()
        }
    }

    /// Straight on from the feedback beat, when the player taps Next.
    func nextNow() {
        guard case .feedback = phase else { return }
        phaseToken += 1
        advance()
    }

    private func advance() {
        guard stage == .running else { return }
        if stepIndex + 1 < session.steps.count {
            stepIndex += 1
            saveProgress(index: stepIndex)
            beginStep()
        } else {
            finish()
        }
    }

    private func saveProgress(index: Int) {
        NeuroStore.saveProgress(NeuroProgress(date: today, index: index, answers: answers,
                                              seconds: elapsedSeconds, zenSeconds: zenSeconds))
    }

    // MARK: Finishing

    private func finish() {
        let seconds = max(1, elapsedSeconds)
        finishedSeconds = seconds
        let ordered = answers.sorted { $0.index < $1.index }
        answers = ordered
        resultBody = [
            "device": AppConstants.deviceID,
            "date": today,
            "name": NeuroStore.playerName,
            "seconds": seconds,
            "zenSeconds": zenSeconds,
            "mood": mood,
            "answers": ordered.map { $0.json },
        ]
        // Queued before anything else: if the app dies on the results
        // screen, the next launch posts this.
        NeuroStore.queue(resultBody)
        NeuroStore.clearProgress()
        let estimate = NeuroScoring.estimate(date: today, answers: ordered,
                                             profile: profile, names: session.names)
        summary = estimate
        streak = estimate.streak
        NeuroStore.saveDone(estimate)
        PhonePlayHaptics.success()
        stage = .results
    }

    /// The mood slider on the results screen; it travels with the result,
    /// which is why the session is posted when Done is tapped and not the
    /// moment it ends (the server keeps the first mood it is told).
    func setMood(_ value: Int) {
        let clamped = max(0, min(5, value))
        guard clamped != mood else { return }
        mood = clamped
        PhonePlayHaptics.tap()
        guard !resultBody.isEmpty else { return }
        resultBody["mood"] = clamped
        NeuroStore.queue(resultBody)
    }

    /// Done on the results screen: send the session, with the mood.
    func deliverResult() {
        guard !resultBody.isEmpty, let payload = NeuroJSON.data(resultBody) else { return }
        let date = today
        // Deliberately not stored in `network`: leaving the Mind Gym calls
        // shutdown(), and this POST must outlive it.
        Task { [weak self] in
            let reply = await NeuroAPI.post(resultData: payload)
            if let reply {
                NeuroStore.saveDone(reply)
                let left = NeuroStore.pending().filter { NeuroJSON.string($0["date"]) != date }
                NeuroStore.savePending(left)
            }
            let fetched = await NeuroAPI.profile()
            if let fetched { NeuroStore.saveProfile(fetched) }
            guard let me = self, me.isActive else { return }
            if let reply {
                me.summary = reply
                me.streak = reply.streak
            }
            if let fetched {
                me.profile = fetched
                me.streak = max(me.streak, fetched.streak)
            }
        }
    }

    // MARK: Mind Score

    func showProgress() {
        guard stage != .progress else { return }
        PhonePlayHaptics.tap()
        stage = .progress
        loadProgress()
    }

    func closeProgress() {
        guard stage == .progress else { return }
        stage = summary == nil ? .running : .results
    }

    func loadProgress() {
        guard !loadingProgress else { return }
        loadingProgress = true
        let date = today
        Task { [weak self] in
            let fetched = await NeuroAPI.profile()
            let board = await NeuroAPI.leaderboard(date: date)
            if let fetched { NeuroStore.saveProfile(fetched) }
            guard let me = self, me.isActive else { return }
            if let fetched {
                me.profile = fetched
                me.streak = max(me.streak, fetched.streak)
            }
            if let board {
                me.everyone = board.everyone
                me.friends = board.friends
            }
            me.loadingProgress = false
        }
    }

    // MARK: Network reconciliation

    /// Posts anything queued from an earlier offline session, then fetches
    /// today's steps and the profile.
    private func refresh() {
        let date = today
        let name = NeuroStore.playerName
        network?.cancel()
        network = Task { [weak self] in
            await NeuroPulseViewModel.flushQueued()
            let fetched = await NeuroAPI.daily(date: date, name: name)
            if let fetched { NeuroStore.saveSession(fetched) }
            let freshProfile = await NeuroAPI.profile()
            if let freshProfile { NeuroStore.saveProfile(freshProfile) }
            guard let me = self, me.isActive, !Task.isCancelled else { return }
            if let fetched { me.adopt(fetched) }
            if let freshProfile {
                me.profile = freshProfile
                me.streak = max(me.streak, freshProfile.streak)
            }
        }
    }

    /// The fetched steps replace the cached or locally built ones only
    /// while nothing has been answered yet.
    private func adopt(_ fetched: NeuroSession) {
        streak = max(streak, fetched.streak)
        guard !adopted, answers.isEmpty, stepIndex == 0, stage == .running,
              !fetched.steps.isEmpty else { return }
        adopted = true
        session = fetched
        sessionStartedAt = Date()
        beginStep()
    }

    nonisolated private static func flushQueued() async {
        let queued = NeuroStore.pending()
        guard !queued.isEmpty else { return }
        let left = await NeuroAPI.flush(queued)
        NeuroStore.savePending(left)
    }

    // MARK: Teardown

    func shutdown() {
        isActive = false
        phaseToken += 1
        network?.cancel()
        network = nil
        if stage == .running, !answers.isEmpty {
            saveProgress(index: stepIndex)
        }
    }
}

// MARK: - What the home card shows

/// Read straight from the cache, so the home screen never waits on a
/// fetch: Start, Resume (part-done) or Done with today's pulse score.
struct NeuroHomeState: Equatable {
    enum Mode: Equatable {
        case start
        case resume(step: Int)
        case done(pulse: Int)
    }

    let mode: Mode
    let streak: Int

    /// About how long the ten steps take.
    static let minutes: Int = 5

    static func load(date: String = NeuroStore.todayKey()) -> NeuroHomeState {
        let profile = NeuroStore.profile()
        let session = NeuroStore.session(for: date)
        let streak = max(profile?.streak ?? 0, session?.streak ?? 0)
        if let done = NeuroStore.done(for: date) {
            return NeuroHomeState(mode: .done(pulse: done.pulse),
                                  streak: max(streak, done.streak))
        }
        if let progress = NeuroStore.progress(for: date), progress.isStarted {
            let reached = min(progress.index + 1, NeuroScoring.stepCount)
            return NeuroHomeState(mode: .resume(step: reached), streak: streak)
        }
        return NeuroHomeState(mode: .start, streak: streak)
    }
}
