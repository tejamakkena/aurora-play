import AVFoundation
import Speech
import SwiftUI

/// The quizmaster's ear: on-device speech recognition, armed only inside
/// the LISTEN window.
///
/// Design constraints (see the quizmaster spec):
/// - The recognizer runs ONLY while the state machine says LISTEN. It is
///   created on start and torn down on stop -- there is deliberately no
///   always-listening mode, which is what makes the game immune to the
///   car's side conversations.
/// - `requiresOnDeviceRecognition = true`: free, private, and it works in
///   tunnels. Short quiz answers are exactly what the on-device model is
///   good at.
/// - End-of-utterance comes from SFSpeechRecognizer's own final-result
///   detection; the timeout is the backstop, not the primary mechanism.
@MainActor
final class TravelVoiceListener: NSObject, ObservableObject {
    /// Live partial transcript, for the "hearing: …" caption.
    @Published private(set) var partialTranscript = ""
    @Published private(set) var isListening = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?
    private var didFinish = false

    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String, Float) -> Void)?

    // MARK: - Authorization

    /// Ask for both permissions up front, once, when Travel Mode starts --
    /// never mid-question. Returns true when recognition can run.
    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        let recordGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        return recordGranted && (recognizer?.isAvailable ?? false)
    }

    // MARK: - Listening

    /// Arm the mic. Exactly one of `onFinal` fires per start() call.
    /// - Parameters:
    ///   - timeout: backstop silence timeout (default 8 s).
    ///   - onPartial: live caption updates.
    ///   - onFinal: (transcript, confidence 0...1). Empty transcript means
    ///     "heard nothing" -- the caller re-prompts once, then falls back
    ///     to host tap.
    func start(timeout: TimeInterval = 8,
               onPartial: ((String) -> Void)? = nil,
               onFinal: ((String, Float) -> Void)? = nil) {
        stop()
        guard let recognizer, recognizer.isAvailable else {
            onFinal?("", 0)
            return
        }
        self.onPartial = onPartial
        self.onFinal = onFinal
        didFinish = false
        partialTranscript = ""

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when this phone supports it (free, private, works in
        // tunnels); otherwise Apple's server recognizer rather than none.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        // Task hint improves end-of-utterance detection for short answers.
        if #available(iOS 13, *) {
            request.taskHint = .dictation
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) {
            [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            finish(transcript: "", confidence: 0)
            return
        }

        isListening = true
        recognitionTask = recognizer.recognitionTask(with: request) {
            [weak self] result, error in
            Task { @MainActor in
                self?.handleResult(result: result, error: error)
            }
        }
        timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            await MainActor.run { [weak self] in
                self?.finish(transcript: self?.partialTranscript ?? "",
                             confidence: 0.4)
            }
        }
    }

    /// Release the press-and-hold button early: finalize whatever was heard.
    func finishEarly() {
        recognitionRequest?.endAudio()
    }

    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        isListening = false
        onPartial = nil
        // NOTE: onFinal is intentionally NOT nil'd here -- stop() is also
        // called from finish(), which needs to deliver the result after
        // tearing down the engine.
    }

    // MARK: - Private

    private func handleResult(result: SFSpeechRecognitionResult?,
                              error: Error?) {
        guard !didFinish else { return }
        if let result {
            partialTranscript = result.bestTranscription.formattedString
            onPartial?(partialTranscript)
            if result.isFinal {
                let segments = result.bestTranscription.segments
                let total: Double = segments.reduce(0) { $0 + Double($1.confidence) }
                let avg = total / max(1, Double(segments.count))
                finish(transcript: partialTranscript,
                       confidence: Float(avg))
                return
            }
        }
        if error != nil {
            // Noisy but non-fatal: deliver what we have (possibly empty).
            finish(transcript: partialTranscript, confidence: 0.3)
        }
    }

    private func finish(transcript: String, confidence: Float) {
        guard !didFinish else { return }
        didFinish = true
        let callback = onFinal
        onFinal = nil
        stop()
        callback?(transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                  confidence)
    }
}
