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
    /// Fired when the current utterance finishes (cloud or device).
    private var pendingSpeechCompletion: (() -> Void)?

    // MARK: One voice per app session
    //
    // The TV used to mix two voices: the cloud AI voice and the Apple TV's
    // built-in one. A 4 s "stream didn't start" timer was not tied to the
    // line it was armed for, so when it fired during a LATER line it
    // re-spoke the OLD line in the device voice; and every slow request (a
    // sleeping server) fell back to the device voice for that one line.
    // Now the first line decides: if the cloud voice answers, the whole
    // session uses it; if not, the whole session uses one fixed device
    // voice. At most one switch (cloud -> device, if the cloud dies
    // mid-session), never alternating. Every async callback carries a
    // token, so a stale line can never speak or fire a completion.
    private enum SessionVoice { case undecided, cloud, device }
    private static var sessionVoice: SessionVoice = .undecided
    private var speechToken = 0
    private var audioPlayer: AVAudioPlayer?
    private var currentUtteranceID: ObjectIdentifier?

    /// Disk-cached session for cloud voice lines (nonisolated: read by the
    /// background fetch below; URLSession is thread-safe).
    nonisolated private static let ttsSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024,
                                   diskCapacity: 100 * 1024 * 1024,
                                   directory: FileManager.default
                                       .urls(for: .cachesDirectory, in: .userDomainMask)
                                       .first?.appendingPathComponent("tv_tts_audio"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    nonisolated private static func isNovelty(_ v: AVSpeechSynthesisVoice) -> Bool {
        if v.voiceTraits.contains(.isNoveltyVoice) { return true }
        let id = v.identifier.lowercased()
        return id.contains("speech.synthesis.voice") || id.contains("eloquence")
    }

    /// One fixed, real (non-novelty) English voice: the best installed
    /// quality, else the standard en-US voice.
    private static let deviceVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !TVVoiceHost.isNovelty($0)
        }
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium:  return 0
            case .enhanced: return 1
            default:        return 2
            }
        }
        let best = english.sorted {
            (rank($0.quality), $0.language == "en-US" ? 0 : 1, $0.identifier)
                < (rank($1.quality), $1.language == "en-US" ? 0 : 1, $1.identifier)
        }.first
        if let best, best.quality != .default { return best }
        return AVSpeechSynthesisVoice(language: "en-US") ?? best
    }()

    /// The cloud voice's audio for `text`, or nil (offline, no API key,
    /// slow). Cached on disk, so repeated lines are instant.
    nonisolated private static func fetchTTS(_ text: String, timeout: TimeInterval) async -> Data? {
        var components = URLComponents(
            url: AppConstants.serverURL.appendingPathComponent("api/voice/tts"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (data, response) = try? await ttsSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count > 512 else { return nil }
        return data
    }

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
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

    /// Speak arbitrary text through the TV speakers in the session's one
    /// voice (see "One voice per app session" above).
    /// - Parameter completion: fired when the utterance finishes or is
    ///   cut off. The quizmaster uses it to open the listen window exactly
    ///   when the question ends.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion?(); return }
        stopSpeaking()
        speechToken += 1
        let token = speechToken
        pendingSpeechCompletion = completion
        if Self.sessionVoice == .device {
            speakOnDevice(trimmed)
            return
        }
        // First line: a short wait decides the session. Once the cloud
        // voice is chosen, allow it longer (a sleeping server) rather than
        // switching voices mid-game.
        let timeout: TimeInterval = Self.sessionVoice == .cloud ? 20 : 8
        Task { [weak self] in
            let data = await Self.fetchTTS(trimmed, timeout: timeout)
            guard let self, token == self.speechToken else { return }
            if let data, let player = try? AVAudioPlayer(data: data) {
                Self.sessionVoice = .cloud
                player.delegate = self
                self.audioPlayer = player
                if player.play() { return }
                self.audioPlayer = nil
            }
            // The cloud voice is unavailable: use the device voice for the
            // rest of the session, never alternating.
            Self.sessionVoice = .device
            self.speakOnDevice(trimmed)
        }
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
        speechToken += 1
        audioPlayer?.stop()
        audioPlayer = nil
        currentUtteranceID = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        finishSpeechCompletion()
    }

    fileprivate func cloudLineFinished(_ id: ObjectIdentifier) {
        guard let current = audioPlayer, ObjectIdentifier(current) == id else { return }
        audioPlayer = nil
        finishSpeechCompletion()
    }

    fileprivate func deviceLineFinished(_ id: ObjectIdentifier) {
        // A cancelled earlier utterance reports late; only the current one
        // may fire the completion (else the mic would open mid-question).
        guard currentUtteranceID == id else { return }
        currentUtteranceID = nil
        finishSpeechCompletion()
    }

    private func finishSpeechCompletion() {
        let completion = pendingSpeechCompletion
        pendingSpeechCompletion = nil
        completion?()
    }

    private func speakOnDevice(_ text: String) {
        // Callers have already torn down any in-flight audio. Do NOT call
        // stopSpeaking() here: it would fire pendingSpeechCompletion before
        // this utterance even starts, arming the mic while we're talking.
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.deviceVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        currentUtteranceID = ObjectIdentifier(utterance)
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
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.deviceLineFinished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.deviceLineFinished(id) }
    }
}

extension TVVoiceHost: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.cloudLineFinished(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.cloudLineFinished(id) }
    }
}
