import Foundation
import SwiftUI

// MARK: - TravelModeViewModel
//
// The road-trip quizmaster. Pick Riddles, Quiz or Mix once; after that the
// phone runs itself:
//
//   ASK (spoken) -> LISTEN (mic, ~9 s) -> react:
//     right answer        -> cheer + fun fact -> next question
//     wrong / silence     -> joke + hint -> listen again
//     still wrong         -> "one more guess" -> listen again
//     out of guesses      -> reveal + fun fact -> next question
//
// The car can also SAY "hint", "repeat", "skip" or "I give up". Nobody
// has to touch the phone; the on-screen buttons are optional shortcuts.
// Without mic permission the same loop runs on a thinking-time countdown.
//
// Every async callback carries the `flow` token it was started under.
// Any interruption (skip, pause, hint button...) bumps it, so a late
// callback from an older step can never speak or move the game on.

@MainActor
final class TravelModeViewModel: ObservableObject {

    enum Stage { case pick, starting, playing }

    enum Phase {
        case asking     // the quizmaster is talking
        case listening  // mic open for answers
        case thinking   // no mic: countdown before the hint / reveal
        case reacting   // talking back after a guess
        case revealed   // answer is out; the next one follows by itself
        case paused
    }

    @Published private(set) var stage: Stage = .pick
    @Published private(set) var style: TravelPlayStyle = .mix
    @Published private(set) var phase: Phase = .asking
    @Published private(set) var item: TravelItem?
    @Published private(set) var hintShown = false
    /// nil while the question is open; true = the car got it.
    @Published private(set) var gotIt: Bool?
    /// What the mic heard last ("Heard: ...").
    @Published private(set) var heard = ""
    @Published private(set) var asked = 0
    @Published private(set) var correct = 0
    @Published private(set) var micReady = false
    @Published private(set) var countdown = 0

    let speech = TravelSpeech()
    private let ear = TravelVoiceListener()

    private(set) var isActive = true
    private var flow = 0
    private var tries = 0

    private struct Lines { let ask, hint, correct, reveal: String }
    private var lines: Lines?
    private var upcoming: (item: TravelItem, lines: Lines)?

    private var riddleQueue: [TravelItem] = []
    private var quizQueue: [TravelItem] = []
    private var liveRiddles: [TravelItem] = []
    private var liveQuiz: [TravelItem] = []
    private var nextKind: TravelItem.Kind = .riddle
    private var fetching: Set<TravelItem.Kind> = []
    private var liveFailures: [TravelItem.Kind: Int] = [:]
    private var topicIndex = Int.random(in: 0..<travelQuizTopics.count)

    init() {
        // The hosted server sleeps when idle and needs 30-60 s to wake.
        // Warm it while the car is still picking Riddles / Quiz / Mix.
        speech.warmUpServer()
    }

    // MARK: - Start / stop

    func start(_ style: TravelPlayStyle) {
        guard stage == .pick, isActive else { return }
        self.style = style
        stage = .starting
        flow += 1
        let f = flow
        asked = 0
        correct = 0
        item = nil
        buildQueues()
        fetchLiveIfNeeded()
        Task { [weak self] in
            guard let self else { return }
            // Permission is settled up front, never mid-question. Denied?
            // The game still runs on thinking-time countdowns.
            let mic = await self.ear.requestAuthorization()
            guard f == self.flow, self.isActive else { return }
            self.micReady = mic
            self.speech.configureSession(withMic: mic)
            let intro = mic ? Self.introWithMic : Self.introNoMic
            await self.speech.prepare(firstLine: intro)
            guard f == self.flow, self.isActive else { return }
            for line in Self.wrongLines + Self.silenceLines + [Self.oneMoreGuess] {
                self.speech.prefetch(line)
            }
            let first = self.prepared(self.dequeue())
            self.upcoming = first
            self.speech.prefetch(first.lines.ask)
            self.stage = .playing
            self.phase = .asking
            self.speech.speak(intro) { [weak self] in
                guard let self, f == self.flow else { return }
                self.nextQuestion()
            }
        }
    }

    /// Back to the Riddles / Quiz / Mix picker. Also re-checks the voice
    /// on the next start, so a server that woke up late gets its AI voice
    /// at a natural break instead of mid-game.
    func changeGame() {
        flow += 1
        ear.stop()
        speech.reset()
        item = nil
        lines = nil
        upcoming = nil
        gotIt = nil
        hintShown = false
        heard = ""
        phase = .asking
        stage = .pick
    }

    func shutdown() {
        isActive = false
        flow += 1
        ear.stop()
        speech.reset()
        speech.deactivateSession()
    }

    // MARK: - Optional buttons (everything also works by voice)

    var canUseButtons: Bool { stage == .playing && item != nil && phase != .paused }

    func hint() {
        guard canUseButtons, gotIt == nil, !hintShown else { return }
        flow += 1
        giveHint(flow: flow, lead: nil)
    }

    func revealNow() {
        guard canUseButtons, gotIt == nil else { return }
        flow += 1
        reveal(flow: flow)
    }

    /// "We got it!" -- for when the mic missed it (or there is no mic).
    func markGotIt() {
        guard canUseButtons, gotIt == nil else { return }
        flow += 1
        celebrate(flow: flow)
    }

    func skip() {
        guard stage == .playing, phase != .paused else { return }
        nextQuestion()
    }

    func repeatQuestion() {
        guard canUseButtons, gotIt == nil else { return }
        flow += 1
        ear.stop()
        ask(flow: flow)
    }

    func togglePause() {
        guard stage == .playing else { return }
        flow += 1
        ear.stop()
        speech.stop()
        if phase == .paused {
            if gotIt != nil || item == nil { nextQuestion() } else { ask(flow: flow) }
        } else {
            phase = .paused
        }
    }

    // MARK: - The loop

    private func nextQuestion() {
        flow += 1
        let f = flow
        ear.stop()
        let current = upcoming ?? prepared(dequeue())
        let following = prepared(dequeue())
        upcoming = following
        item = current.item
        lines = current.lines
        hintShown = false
        gotIt = nil
        heard = ""
        tries = 0
        asked += 1
        recordHeard(current.item)
        // Everything this question might say, plus the next question, is
        // fetched while this one plays: no dead air between lines.
        speech.prefetch(current.lines.hint)
        speech.prefetch(current.lines.correct)
        speech.prefetch(current.lines.reveal)
        speech.prefetch(following.lines.ask)
        fetchLiveIfNeeded()
        ask(flow: f)
    }

    private func ask(flow f: Int) {
        guard let lines else { return }
        phase = .asking
        speech.speak(lines.ask) { [weak self] in self?.openFloor(flow: f) }
    }

    private func openFloor(flow f: Int) {
        guard f == flow, isActive, gotIt == nil else { return }
        if micReady { listen(flow: f) } else { think(flow: f) }
    }

    private func listen(flow f: Int) {
        phase = .listening
        heard = ""
        ear.start(
            timeout: 9,
            onPartial: { [weak self] partial in
                guard let self, f == self.flow, self.phase == .listening else { return }
                self.heard = partial
                // Shouted the right answer? Don't wait for the pause.
                if let item = self.item,
                   TravelAnswerMatcher.matches(partial, accepted: item.acceptedAnswers) {
                    self.celebrate(flow: f)
                }
            },
            onFinal: { [weak self] transcript, _ in
                guard let self, f == self.flow, self.phase == .listening else { return }
                self.judge(transcript, flow: f)
            }
        )
    }

    /// No mic: give the car thinking time, then a hint, then the answer.
    private func think(flow f: Int) {
        phase = .thinking
        countdown = hintShown ? 8 : 10
        Task { [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, f == self.flow, self.phase == .thinking else { return }
                self.countdown -= 1
                if self.countdown <= 0 {
                    if self.hintShown { self.reveal(flow: f) } else { self.giveHint(flow: f, lead: nil) }
                    return
                }
            }
        }
    }

    private func judge(_ transcript: String, flow f: Int) {
        guard let item else { return }
        let said = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = said
        if !said.isEmpty, TravelAnswerMatcher.matches(said, accepted: item.acceptedAnswers) {
            celebrate(flow: f)
            return
        }
        if let command = TravelCommand.parse(said) {
            switch command {
            case .hint:
                if hintShown { speakThenListen("That was my only hint! Have a guess.", flow: f) }
                else { giveHint(flow: f, lead: nil) }
            case .giveUp, .skip:
                reveal(flow: f)
            case .repeatQuestion:
                ask(flow: f)
            }
            return
        }
        tries += 1
        if said.isEmpty {
            // Nobody answered.
            if hintShown { reveal(flow: f) }
            else { giveHint(flow: f, lead: Self.silenceLines.randomElement()) }
            return
        }
        // A wrong guess.
        if !hintShown {
            giveHint(flow: f, lead: Self.wrongLines.randomElement())
        } else if tries < 3 {
            speakThenListen(Self.oneMoreGuess, flow: f)
        } else {
            reveal(flow: f, lead: Self.wrongLines.randomElement())
        }
    }

    private func speakThenListen(_ line: String, flow f: Int) {
        ear.stop()
        phase = .reacting
        speech.speak(line) { [weak self] in self?.openFloor(flow: f) }
    }

    private func giveHint(flow f: Int, lead: String?) {
        guard let hintLine = lines?.hint else { return }
        ear.stop()
        hintShown = true
        phase = .reacting
        let sayHint: () -> Void = { [weak self] in
            guard let self, f == self.flow else { return }
            self.speech.speak(hintLine) { [weak self] in self?.openFloor(flow: f) }
        }
        if let lead { speech.speak(lead, completion: sayHint) } else { sayHint() }
    }

    private func celebrate(flow f: Int) {
        guard let line = lines?.correct, gotIt == nil else { return }
        ear.stop()
        correct += 1
        gotIt = true
        phase = .revealed
        speech.speak(line) { [weak self] in self?.wrapUp(flow: f) }
    }

    private func reveal(flow f: Int, lead: String? = nil) {
        guard let line = lines?.reveal, gotIt == nil else { return }
        ear.stop()
        gotIt = false
        phase = .revealed
        let sayAnswer: () -> Void = { [weak self] in
            guard let self, f == self.flow else { return }
            self.speech.speak(line) { [weak self] in self?.wrapUp(flow: f) }
        }
        if let lead { speech.speak(lead, completion: sayAnswer) } else { sayAnswer() }
    }

    /// After the answer: a score check every ten questions, a short
    /// breather, then the next question by itself.
    private func wrapUp(flow f: Int) {
        guard f == flow, isActive else { return }
        if micReady, asked % 10 == 0 {
            speech.speak(summaryLine()) { [weak self] in self?.breather(flow: f) }
        } else {
            breather(flow: f)
        }
    }

    private func breather(flow f: Int) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, f == self.flow, self.isActive else { return }
            self.nextQuestion()
        }
    }

    // MARK: - Lines

    private func prepared(_ item: TravelItem) -> (item: TravelItem, lines: Lines) {
        let intro = (item.kind == .riddle ? Self.riddleIntros : Self.quizIntros)
            .randomElement() ?? ""
        var ask = "\(intro) \(item.prompt)"
        if let options = item.options { ask += " Is it \(Self.spokenList(options))?" }
        let answer = Self.capitalizedFirst(item.answer)
        let fact = item.fact.map { " \($0)" } ?? ""
        let lines = Lines(
            ask: ask,
            hint: "Here's a hint. \(item.hint)",
            correct: "\(Self.praise.randomElement() ?? "Yes!") \(answer)!\(fact)",
            reveal: "\(Self.revealIntros.randomElement() ?? "The answer is") \(item.answer)!\(fact)"
        )
        return (item, lines)
    }

    private func summaryLine() -> String {
        let ratio = Double(correct) / Double(max(asked, 1))
        let quip: String
        if ratio >= 0.8 { quip = "You lot are way too smart for one car." }
        else if ratio >= 0.5 { quip = "Not bad at all!" }
        else { quip = "Don't worry, I'm blaming the road noise." }
        return "That's \(asked) questions! You got \(correct) right. \(quip) Keep going!"
    }

    private static func spokenList(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + ", or " + (items.last ?? "")
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + String(text.dropFirst())
    }

    private static let introWithMic =
        "Hi everyone, I'm your road trip quizmaster! I ask, you shout out the answer. Stuck? Just say hint. Let's go!"
    private static let introNoMic =
        "Hi everyone, I'm your road trip quizmaster! I ask, you shout out the answer, and I'll tell you if you got it after a little thinking time. Let's go!"

    private static let riddleIntros = ["Riddle time!", "Here's a riddle.", "Okay, brain teaser."]
    private static let quizIntros = ["Quiz time!", "Quick question.", "Here's one for the smart people in the car."]
    private static let praise = [
        "Yes! Somebody in this car is a genius.",
        "Nailed it!",
        "Correct! Give that person the window seat.",
        "Boom! That's right.",
        "Yes! I'm impressed. A little annoyed, but impressed.",
        "That's it! Extra snacks for the winner.",
    ]
    private static let revealIntros = ["The answer is", "Drumroll please... it's", "And the answer was"]
    private static let wrongLines = [
        "Ha! Nice try, but no.",
        "Nope! I love the confidence though.",
        "Ooh, interesting guess. Wrong, but interesting.",
        "Not quite!",
        "Ha, no! But that was a funny one.",
    ]
    private static let silenceLines = [
        "Hello? Is anybody awake back there?",
        "So quiet... I can hear the engine thinking.",
        "Nobody? Okay, I'll help you out.",
    ]
    private static let oneMoreGuess = "Nope! One more guess."

    // MARK: - Queues
    //
    // "Already asked" is tracked two ways on the phone and sent to the
    // server with every request:
    //  - prompts, to skip bundled items heard on earlier trips;
    //  - ANSWERS, which is what the server dedupes on. A riddle comes back
    //    reworded, but "a piano" is still "a piano", so the server tells
    //    the model every answer this phone has heard is off limits.
    // The phone's copy is the durable one: the hosted server's disk resets
    // on every redeploy.

    private static let promptHistoryKey = "travel_heard_items"
    private static let answerHistoryKey = "travel_heard_answers"
    private static let historyCap = 400

    private var promptHistory: [String] {
        UserDefaults.standard.stringArray(forKey: Self.promptHistoryKey) ?? []
    }

    private var answerHistory: [String] {
        UserDefaults.standard.stringArray(forKey: Self.answerHistoryKey) ?? []
    }

    private func recordHeard(_ item: TravelItem) {
        for (key, value) in [(Self.promptHistoryKey, item.prompt),
                             (Self.answerHistoryKey, item.answer)] {
            var h = UserDefaults.standard.stringArray(forKey: key) ?? []
            h.append(value)
            if h.count > Self.historyCap { h.removeFirst(h.count - Self.historyCap) }
            UserDefaults.standard.set(h, forKey: key)
        }
    }

    /// Only bundled items this phone hasn't heard; once those run out,
    /// fresh server items take over (see dequeue).
    private func buildQueues() {
        let seen = Set(promptHistory)
        riddleQueue = TravelDeck.riddles.filter { !seen.contains($0.prompt) }.shuffled()
        quizQueue = TravelDeck.quiz.filter { !seen.contains($0.prompt) }.shuffled()
        nextKind = Bool.random() ? .riddle : .quiz
    }

    private func dequeue() -> TravelItem {
        let kind: TravelItem.Kind
        switch style {
        case .riddles: kind = .riddle
        case .quiz:    kind = .quiz
        case .mix:
            kind = nextKind
            nextKind = (nextKind == .riddle) ? .quiz : .riddle
        }
        if kind == .riddle {
            return take(live: &liveRiddles, bundled: &riddleQueue, deck: TravelDeck.riddles)
        }
        return take(live: &liveQuiz, bundled: &quizQueue, deck: TravelDeck.quiz)
    }

    /// Fresh server items mixed with unheard bundled ones; a repeat from
    /// the bundled deck only when there is nothing new at all (offline,
    /// and every bundled item already heard).
    private func take(live: inout [TravelItem], bundled: inout [TravelItem],
                      deck: [TravelItem]) -> TravelItem {
        if !live.isEmpty, bundled.isEmpty || Bool.random() {
            return live.removeFirst()
        }
        if bundled.isEmpty { bundled = deck.shuffled() }
        return bundled.removeFirst()
    }

    private func fetchLiveIfNeeded() {
        guard isActive else { return }
        switch style {
        case .riddles: fetchLive(.riddle)
        case .quiz:    fetchLive(.quiz)
        case .mix:     fetchLive(.riddle); fetchLive(.quiz)
        }
    }

    private func fetchLive(_ kind: TravelItem.Kind) {
        let queued = kind == .riddle ? liveRiddles : liveQuiz
        guard !fetching.contains(kind), queued.count < 4,
              liveFailures[kind, default: 0] < 2 else { return }
        fetching.insert(kind)
        // Everything heard, plus everything already waiting in the queue.
        let seenAnswers = answerHistory + (liveRiddles + liveQuiz).map(\.answer)
        let topic = travelQuizTopics[topicIndex % travelQuizTopics.count]
        topicIndex += 1
        let promptsHeard = promptHistory
        Task { [weak self] in
            var items = await fetchTravelItems(kind: kind, seenAnswers: seenAnswers)
            if items.isEmpty, kind == .quiz {
                // No model on the server: Open Trivia DB questions instead.
                items = await fetchLiveQuizQuestions(topic: topic, exclude: promptsHeard)
                    .map(\.asItem)
            }
            guard let self, self.isActive else { return }
            self.fetching.remove(kind)
            let heard = Set(self.promptHistory)
            let waiting = Set((self.liveRiddles + self.liveQuiz).map(\.prompt))
            let fresh = items.filter { !heard.contains($0.prompt) && !waiting.contains($0.prompt) }
            if fresh.isEmpty {
                self.liveFailures[kind, default: 0] += 1   // offline: stop after two tries
            } else {
                self.liveFailures[kind] = 0
                if kind == .riddle { self.liveRiddles += fresh } else { self.liveQuiz += fresh }
            }
        }
    }
}
