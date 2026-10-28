import SwiftUI

// MARK: - Secret Story (was Story Chain)
//
// Story Chain used to be a timer: everyone told a story out loud and the phone
// only counted down, so it did not need a phone at all. Secret Story does.
//
// The phone picks a story (a news report, a Bollywood blockbuster, a wedding
// speech...) with blanks. It goes round the group: each player, alone, fills
// in one blank ("Where did they meet?") without seeing anyone else's answers.
// When every blank is filled, everyone gathers round and the phone shows the
// finished story and reads it aloud in the Phone Play voice (the one the Mafia
// narrator uses). Nobody knew what the others wrote, which is the joke. Then
// the next story starts with the next player.

@MainActor
final class StoryChainViewModel: ObservableObject {

    enum Stage { case setup, pass, write, gather, reveal }

    @Published var names: [String] {
        didSet { PhonePlayRoster.save(names) }
    }
    @Published var readAloud: Bool {
        didSet { UserDefaults.standard.set(readAloud, forKey: StoryChainViewModel.readKey) }
    }

    @Published private(set) var stage: Stage = .setup
    @Published private(set) var template: SecretStoryTemplate = StoryChainDeck.templates[0]
    @Published private(set) var blank: Int = 0
    @Published private(set) var answers: [String] = []
    /// Who wrote each blank, by name.
    @Published private(set) var writers: [String] = []
    @Published private(set) var storiesTold: Int = 0
    @Published var draft: String = ""

    let playerRange: ClosedRange<Int> = 3...10
    static let maxAnswerLength = 60

    var canStart: Bool { playerRange.contains(names.count) }
    var writerName: String {
        guard !names.isEmpty else { return "" }
        return names[(firstWriter + blank) % names.count]
    }
    var prompt: SecretStoryBlank { template.blanks[min(blank, template.blanks.count - 1)] }
    var story: String { StoryChainDeck.fill(template, answers: answers) }

    private let speech: TravelSpeech
    private var firstWriter: Int = 0
    private var dealer = PhonePlayDealer(deck: "secretstory")
    private var isActive: Bool = true
    private static let readKey = "phoneplay_secretstory_read"

    init(speech: TravelSpeech) {
        self.speech = speech
        names = Array(PhonePlayRoster.load().prefix(10))
        let defaults = UserDefaults.standard
        readAloud = defaults.object(forKey: StoryChainViewModel.readKey) == nil
            ? true : defaults.bool(forKey: StoryChainViewModel.readKey)
    }

    // MARK: - Flow

    func start() {
        guard canStart else { return }
        firstWriter = Int.random(in: 0..<names.count)
        storiesTold = 0
        if readAloud { prepareVoice() }
        newStory()
    }

    /// Next story: a fresh template, starting with the player after the last writer.
    func nextStory() {
        speech.stop()
        firstWriter = (firstWriter + template.blanks.count) % max(1, names.count)
        newStory()
    }

    /// The writer has the phone and is alone: show their prompt.
    func showPrompt() {
        guard stage == .pass else { return }
        draft = ""
        PhonePlayHaptics.tap()
        stage = .write
    }

    func submit() {
        guard stage == .write else { return }
        let answer = String(draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(StoryChainViewModel.maxAnswerLength))
        guard !answer.isEmpty else { return }
        record(answer)
    }

    /// Stuck: use the example answer.
    func surpriseMe() {
        guard stage == .write else { return }
        record(prompt.example)
    }

    func reveal() {
        guard stage == .gather else { return }
        storiesTold += 1
        PhonePlayHaptics.success()
        stage = .reveal
        readStory()
    }

    func readStory() {
        guard readAloud, isActive else { return }
        speech.speak("\(template.title). \(story)")
    }

    func stopReading() { speech.stop() }

    func editPlayers() {
        speech.stop()
        stage = .setup
    }

    func shutdown() {
        isActive = false
        speech.stop()
    }

    private func newStory() {
        let ids = StoryChainDeck.templates.map(\.id)
        let pick = dealer.draw(from: ids)
        template = StoryChainDeck.templates.first { $0.id == pick } ?? StoryChainDeck.templates[0]
        blank = 0
        answers = []
        writers = []
        draft = ""
        PhonePlayHaptics.thump()
        stage = .pass
    }

    private func record(_ answer: String) {
        answers.append(answer)
        writers.append(writerName)
        draft = ""
        PhonePlayHaptics.success()
        if answers.count >= template.blanks.count {
            stage = .gather
        } else {
            blank += 1
            stage = .pass
        }
    }

    private func prepareVoice() {
        speech.configureSession(withMic: false)
        let speech = self.speech
        Task { @MainActor in
            await speech.prepare(firstLine: "Story time.", timeout: 4)
        }
    }
}
