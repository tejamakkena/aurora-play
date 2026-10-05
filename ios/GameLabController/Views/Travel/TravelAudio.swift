import AVFoundation
import SwiftUI

/// The quizmaster's voice: ONE voice for the whole session.
///
/// Two voices used to take turns -- the cloud AI voice and the phone's
/// built-in one -- and could even talk over each other. Three causes,
/// all fixed here:
///  1. A 5 s "cloud didn't start" timer was not tied to the line it was
///     armed for. Firing during a LATER line, it re-spoke the OLD line in
///     the device voice on top of the new one.
///  2. AVPlayer never used the URLCache the prefetch filled, so "cached"
///     lines still streamed, hit that timer, and fell back line by line.
///  3. The device fallback picked the alphabetically-first English voice,
///     which can be one of Apple's novelty voices (Whisper, Bad News,
///     Trinoids...) -- the "ghost" voice.
///
/// Now: `prepare()` decides once, at the start of a session, whether the
/// cloud voice is reachable. Cloud lines are fetched as data (through the
/// disk cache, so prefetch really works) and played with AVAudioPlayer;
/// every callback carries a token so a stale line can never speak or
/// advance the game. If the cloud fails mid-session the session switches
/// to the device voice for good -- one switch at most, never alternating.
/// The device voice is a real (non-novelty) Siri-style English voice.
///
/// CARPLAY: there is no CarPlay UI for games (Apple has no games
/// entitlement). Audio simply routes through the car speakers over
/// CarPlay or Bluetooth like any other audio.
@MainActor
final class TravelSpeech: NSObject, ObservableObject {

    enum Voice { case undecided, cloud, device }

    @Published private(set) var voice: Voice = .undecided
    @Published private(set) var isSpeaking = false

    var usingCloudVoice: Bool { voice == .cloud }

    // MARK: Device voice

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?

    nonisolated private static func isNovelty(_ v: AVSpeechSynthesisVoice) -> Bool {
        if v.voiceTraits.contains(.isNoveltyVoice) { return true }
        // Older novelty / Eloquence voices ("Grandma", "Rocko"...) by id.
        let id = v.identifier.lowercased()
        return id.contains("speech.synthesis.voice") || id.contains("eloquence")
    }

    private let deviceVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !TravelSpeech.isNovelty($0)
        }
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium:  return 0
            case .enhanced: return 1
            default:        return 2
            }
        }
        let preferred = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        let best = english.sorted {
            let l = (rank($0.quality), $0.language == preferred ? 0 : 1, $0.language == "en-US" ? 0 : 1)
            let r = (rank($1.quality), $1.language == preferred ? 0 : 1, $1.language == "en-US" ? 0 : 1)
            return l < r
        }.first
        // Only take an upgraded voice; otherwise the system default
        // English voice (Samantha et al.) is the safe, normal choice.
        if let best, best.quality != .default { return best }
        return AVSpeechSynthesisVoice(language: "en-US") ?? best
    }()

    // MARK: Cloud voice

    private var audioPlayer: AVAudioPlayer?
    /// Bumped on every speak/stop; callbacks for an older token are ignored.
    private var token = 0
    private var pendingCompletion: (() -> Void)?

    /// Decoded lines kept in memory for this session (they are also on disk).
    private var memory: [String: Data] = [:]
    private var inflight: [String: Task<Data?, Never>] = [:]

    private static let ttsCache: URLCache = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("tts_audio")
        return URLCache(memoryCapacity: 10 * 1024 * 1024,
                        diskCapacity: 200 * 1024 * 1024,
                        directory: dir)
    }()

    private lazy var ttsSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = Self.ttsCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        return URLSession(configuration: config)
    }()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Audio session

    /// Set ONCE per session. Switching categories between lines changes
    /// the route and volume mid-game, which sounds like a different voice.
    /// With the mic, `.defaultToSpeaker` keeps the voice on the loudspeaker
    /// (not the earpiece) when no car audio is connected.
    func configureSession(withMic: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if withMic {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.defaultToSpeaker, .duckOthers,
                                                  .allowBluetoothA2DP])
            } else {
                try session.setCategory(.playback, mode: .spokenAudio,
                                        options: [.duckOthers])
            }
            try session.setActive(true)
        } catch {
            // Never block play on audio setup; the built-in speaker works.
        }
    }

    func deactivateSession() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Choosing the voice

    /// Wake the server early (it sleeps when idle) so `prepare` finds it up.
    func warmUpServer() {
        prefetch("Let's play!")
    }

    /// Decide the session's voice: cloud if a line can be fetched within
    /// `timeout`, else the device voice. Called once per session.
    func prepare(firstLine: String, timeout: TimeInterval = 10) async {
        guard voice == .undecided else { return }
        let fetch = audio(for: firstLine)
        let timer = Task { () -> Data? in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            return nil
        }
        let data = await withTaskGroup(of: Data?.self) { group -> Data? in
            group.addTask { await fetch.value }
            group.addTask { await timer.value }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        timer.cancel()
        voice = (data != nil) ? .cloud : .device
    }

    /// Fetch and keep a line's audio so speaking it later starts instantly.
    func prefetch(_ text: String) {
        guard voice != .device else { return }
        _ = audio(for: text)
    }

    // MARK: - Speaking

    /// Speak one line. Anything already playing is cut off, and its
    /// completion is dropped (a cut-off line never advances the game).
    /// `completion` runs once, on the main actor, when this line finishes.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        guard !line.isEmpty else { completion?(); return }
        let myToken = token
        pendingCompletion = completion
        isSpeaking = true
        if voice != .cloud {
            speakOnDevice(line)
            return
        }
        let fetch = audio(for: line)
        Task { [weak self] in
            let data = await fetch.value
            guard let self, self.token == myToken else { return }
            if let data, let player = try? AVAudioPlayer(data: data) {
                player.delegate = self
                self.audioPlayer = player
                if player.play() { return }
            }
            // The cloud failed: the device voice from here on, so the
            // car never hears the two voices alternate.
            self.audioPlayer = nil
            self.voice = .device
            self.speakOnDevice(line)
        }
    }

    func stop() {
        token += 1
        pendingCompletion = nil
        audioPlayer?.stop()
        audioPlayer = nil
        currentUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    /// End of session: forget the voice choice so the next one re-checks.
    func reset() {
        stop()
        voice = .undecided
        memory.removeAll()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
    }

    private func finished(token finishedToken: Int) {
        guard finishedToken == token else { return }
        audioPlayer = nil
        currentUtterance = nil
        isSpeaking = false
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }

    // MARK: - Cloud audio fetch

    private func audio(for text: String) -> Task<Data?, Never> {
        if let data = memory[text] { return Task<Data?, Never> { data } }
        if let task = inflight[text] { return task }
        guard let url = ttsURL(for: text) else { return Task<Data?, Never> { nil } }
        let session = ttsSession
        let task = Task { [weak self] () -> Data? in
            let result = try? await session.data(from: url)
            let ok = (result?.1 as? HTTPURLResponse)?.statusCode == 200
            let data = ok ? result?.0 : nil
            // Anything tiny is an error body, not audio.
            let audio = (data?.count ?? 0) > 1_000 ? data : nil
            await MainActor.run {
                guard let self else { return }
                self.inflight[text] = nil
                if let audio {
                    if self.memory.count > 150 { self.memory.removeAll() }
                    self.memory[text] = audio
                }
            }
            return audio
        }
        inflight[text] = task
        return task
    }

    private func ttsURL(for text: String) -> URL? {
        var components = URLComponents(
            url: AppConstants.serverURL.appendingPathComponent("api/voice/tts"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }

    // MARK: - Device voice

    private func speakOnDevice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let deviceVoice { utterance.voice = deviceVoice }
        // A touch slower than default: clearer over road noise.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.postUtteranceDelay = 0.1
        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private func deviceFinished(_ utterance: AVSpeechUtterance) {
        // Only the line we're waiting on may advance the game; a cancelled
        // older utterance reports in late and must be ignored.
        guard utterance === currentUtterance else { return }
        finished(token: token)
    }
}

extension TravelSpeech: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.audioPlayer else { return }
            self.finished(token: self.token)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard player === self.audioPlayer else { return }
            self.finished(token: self.token)
        }
    }
}

extension TravelSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deviceFinished(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deviceFinished(utterance) }
    }
}
