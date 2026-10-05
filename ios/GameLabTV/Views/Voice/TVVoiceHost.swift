import AVFoundation
import SwiftUI

/// The TV side of the cross-device voice loop (quizmaster spec §13).
///
/// Roles are split by platform constraint: tvOS gives third-party apps no
/// microphone access, so the TV is the mouth (it speaks questions and
/// verdicts through the TV speakers) and exactly one phone is the ear.
/// The server only relays and validates; the loop is driven here and on
/// the mic phone.
///
/// Wiring (see TVTriviaBoardView for the reference integration):
///   1. `attach(roomCode:)` on appear -- registers micReassigned /
///      voiceState / voiceTranscript / voiceVerdict handlers.
///   2. Set `onFinalTranscript` -- the board grades it (it owns the
///      question + correct answer) and calls `speakVerdict(_:correct:)`.
///   3. Add `TVVoiceOverlay(host:)` to the board so the room sees mic
///      state, live captions, and verdicts.
///   4. Drive the loop: `drive(state:)` emits voice_state; the mic phone
///      arms/disarms its recognizer from it.
@MainActor
final class TVVoiceHost: NSObject, ObservableObject {
    /// Who holds the mic right now (from mic_reassigned).
    @Published var micPlayerName: String?
    @Published var micPlayerID: String?
    /// ask | listen | lock | grade | idle
    @Published var voiceState: String = "idle"
    /// Live caption from the mic phone.
    @Published var liveTranscript = ""
    /// Last verdict text, for the overlay.
    @Published var lastVerdict: String?
    @Published var lastVerdictCorrect: Bool?

    /// The board sets this: grading needs the question + correct answer,
    /// which live in the board's view model, not here.
    var onFinalTranscript: ((String) -> Void)?

    private let socket = GameSocketManager.shared
    private var roomCode: String?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    /// Fired when the current utterance finishes (cloud or device).
    private var pendingSpeechCompletion: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()

    init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        // TV never records: pure playback, like music.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,
                                                            mode: .spokenAudio,
                                                            options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* built-in speakers still work */ }
    }

    // MARK: - Attach / detach

    func attach(roomCode: String) {
        self.roomCode = roomCode
        socket.on(.micReassigned) { [weak self] (r: MicReassignedResponse) in
            guard r.roomCode == roomCode else { return }
            self?.micPlayerID = r.playerID
            self?.micPlayerName = r.playerName
        }
        socket.on(.voiceState) { [weak self] (r: VoiceStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.voiceState = r.state
            if r.state == "ask" {
                self?.liveTranscript = ""
                self?.lastVerdict = nil
            }
        }
        socket.on(.voiceTranscript) { [weak self] (r: VoiceTranscriptResponse) in
            guard r.roomCode == roomCode else { return }
            self?.liveTranscript = r.text
            if r.isFinal {
                self?.onFinalTranscript?(r.text)
            }
        }
        socket.on(.voiceVerdict) { [weak self] (r: VoiceVerdictResponse) in
            guard r.roomCode == roomCode else { return }
            self?.lastVerdict = r.text
            self?.lastVerdictCorrect = r.correct
            self?.speak(r.text)
        }
    }

    func detach() {
        socket.off(.micReassigned)
        socket.off(.voiceState)
        socket.off(.voiceTranscript)
        socket.off(.voiceVerdict)
        stopSpeaking()
        roomCode = nil
    }

    // MARK: - Driving the loop (TV is the director)

    /// Emit voice_state to the room. The mic phone arms/disarms from this.
    func drive(state: String, questionID: String = "") {
        guard let roomCode else { return }
        socket.emit(.voiceState, payload: VoiceStatePayload(
            roomCode: roomCode, state: state, questionID: questionID))
        voiceState = state
    }

    // MARK: - Speaking (the mouth)

    /// Speak arbitrary text through the TV speakers: cloud TTS first
    /// (same /api/voice/tts as the phone), device voice as the fallback.
    /// - Parameter completion: fired when the utterance finishes or is
    ///   cut off. The quizmaster uses it to open the listen window exactly
    ///   when the question ends.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion?(); return }
        stopSpeaking()
        pendingSpeechCompletion = completion
        var components = URLComponents(
            url: AppConstants.serverURL.appendingPathComponent("api/voice/tts"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "text", value: trimmed)]
        if let url = components?.url {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            let center = NotificationCenter.default
            endObserver = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: item, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.speechDidFinish() }
            }
            failObserver = center.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.speakOnDevice(trimmed) }
                }
            player.play()
            // If the stream can't start (no API key, offline), don't hang.
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await MainActor.run { [weak self] in
                    if self?.player?.timeControlStatus != .playing {
                        self?.speakOnDevice(trimmed)
                    }
                }
            }
            return
        }
        speakOnDevice(trimmed)
    }

    /// Convenience: speak a trivia question in host phrasing, then open
    /// the listen window for the mic phone exactly when it finishes.
    func askQuestion(_ text: String, questionID: String = "") {
        drive(state: "ask", questionID: questionID)
        liveTranscript = ""
        lastVerdict = nil
        speak(text) { [weak self] in
            guard let self, self.voiceState == "ask" else { return }
            self.drive(state: "listen", questionID: questionID)
        }
    }

    /// Speak the grading result and close the loop.
    func speakVerdict(_ text: String, correct: Bool?) {
        guard let roomCode else { return }
        socket.emit(.voiceVerdict, payload: VoiceVerdictPayload(
            roomCode: roomCode, correct: correct, text: text))
        lastVerdict = text
        lastVerdictCorrect = correct
        speak(text)
        drive(state: "idle")
    }

    func stopSpeaking() {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let o = failObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        failObserver = nil
        player?.pause()
        player = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finishSpeechCompletion()
    }

    private func speechDidFinish() {
        player = nil
        finishSpeechCompletion()
    }

    private func finishSpeechCompletion() {
        let completion = pendingSpeechCompletion
        pendingSpeechCompletion = nil
        completion?()
    }

    private func speakOnDevice(_ text: String) {
        // Callers have already torn down any in-flight audio via
        // stopSpeaking()/teardownPlayer(). Do NOT call stopSpeaking() here:
        // it would fire pendingSpeechCompletion before this utterance
        // even starts, arming the mic while we're still talking.
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        synthesizer.speak(utterance)
    }

    // MARK: - Grading (TV owns the question + correct answer)

    /// Grade a final transcript against the board's question. Server-side
    /// via the same /api/voice/grade the phone uses, then speak the
    /// verdict and close the loop.
    func gradeVoiceAnswer(transcript: String, question: String,
                          options: [String], correctIndex: Int) {
        drive(state: "grade")
        struct GradeResponse: Decodable {
            let success: Bool
            let correct: Bool?
        }
        Task {
            var correct: Bool?
            do {
                let url = AppConstants.serverURL
                    .appendingPathComponent("api/voice/grade")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json",
                                 forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 20
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: ["question": question,
                                     "options": options,
                                     "correct_answer": correctIndex,
                                     "transcript": transcript])
                let (data, response) = try await URLSession.shared
                    .data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(
                        GradeResponse.self, from: data)
                    correct = decoded.success ? decoded.correct : nil
                }
            } catch { /* correct stays nil -> the room judges aloud */ }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let letters = ["A", "B", "C", "D"]
                let answerText = options.indices.contains(correctIndex)
                    ? options[correctIndex] : ""
                let letter = letters[correctIndex % letters.count]
                let text: String
                switch correct {
                case true:
                    text = "Correct!"
                case false:
                    text = "Not quite -- it was \(letter). \(answerText)."
                default:
                    text = "I couldn't quite judge that -- the answer was "
                        + "\(letter). \(answerText)."
                }
                self.speakVerdict(text, correct: correct)
            }
        }
    }
}

extension TVVoiceHost: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeechCompletion() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishSpeechCompletion() }
    }
}
