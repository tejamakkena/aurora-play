import AVFoundation
import SwiftUI

/// Spoken prompts for Travel Mode, now cloud-first.
///
/// The quizmaster speaks through a natural neural voice served by the
/// backend (`GET /api/voice/tts`, OpenAI TTS behind it -- the API key
/// stays server-side). Audio streams via AVPlayer and is cached on disk
/// by URLCache, so repeated lines ("Correct!") cost nothing and replay
/// instantly. When the network is unavailable, the on-device
/// AVSpeechSynthesizer enhanced voice is the fallback -- robotic beats
/// silent in a tunnel.
///
/// CARPLAY LIMITATION -- there is no CarPlay screen UI for games, by Apple's
/// design, not ours: CarPlay app categories are limited (audio, messaging,
/// navigation, parking, charging, food ordering) and there is no games
/// entitlement, so a game cannot render CarPlay templates at all. "CarPlay
/// support" in Travel Mode therefore means audio routing only: speech
/// routes through the car speakers automatically whenever the iPhone is
/// connected via CarPlay or car Bluetooth, exactly like music or podcast
/// audio. Do not attempt CarPlay scenes, templates, or entitlements here.
@MainActor
final class TravelSpeech: NSObject, ObservableObject {
    /// On-device fallback: the most natural English voice on this device.
    private let synthesizer = AVSpeechSynthesizer()
    private let fallbackVoice: AVSpeechSynthesisVoice? = {
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en")
        }
        let pool = english.filter { $0.language == "en-US" }
        let candidates = pool.isEmpty ? english : pool
        return candidates.sorted {
            let lq = $0.quality == .enhanced ? 0 : 1
            let rq = $1.quality == .enhanced ? 0 : 1
            return (lq, $0.name) < (rq, $1.name)
        }.first
    }()

    /// Cloud TTS player. One at a time: in a moving car, the newest prompt
    /// always wins over a stale one.
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var pendingCompletion: (() -> Void)?
    /// Guards the exactly-once fallback when a cloud stream fails.
    private var didFallback = false

    /// Disk cache for TTS audio: 20 MB memory / 200 MB disk. The endpoint
    /// serves immutable Cache-Control, so repeats never re-hit the network.
    private static let ttsCache: URLCache = {
        let dir = FileManager.default.urls(for: .cachesDirectory,
                                           in: .userDomainMask).first?
            .appendingPathComponent("tts_audio")
        return URLCache(memoryCapacity: 20 * 1024 * 1024,
                        diskCapacity: 200 * 1024 * 1024,
                        directory: dir)
    }()
    private lazy var ttsSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = Self.ttsCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    @Published private(set) var isSpeaking = false
    /// True once a cloud voice has succeeded at least once this launch.
    /// The UI can show a subtle "AI voice" vs "device voice" note from this.
    @Published private(set) var usingCloudVoice = false

    private var quizmasterAudio = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    // MARK: - Audio session

    /// `.playback` for pure output (Read Aloud on hosted games).
    func configureAudioSession() {
        quizmasterAudio = false
        let session = AVAudioSession.sharedInstance()
        do {
            // `.spokenAudio` mode tunes ducking/frequency response for
            // speech; `.duckOthers` lowers music instead of stopping it.
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Speech still works on the built-in speaker if the category
            // set fails; never block play on audio setup.
        }
    }

    /// `.playAndRecord` + `.voiceChat` for the quizmaster: this is what buys
    /// echo cancellation, so the mic doesn't re-hear the question coming
    /// through the car speakers. `.allowBluetoothA2DP` keeps high-quality
    /// output routing to the car; input stays on the iPhone's built-in mic
    /// (the phone is in the passenger's hand -- the "pass the mic" pattern).
    /// The state machine (TravelModeViewModel) additionally never arms the
    /// mic while TTS is playing -- half-duplex by design.
    func enableQuizmasterAudio() {
        quizmasterAudio = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.duckOthers, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            // Fall through to the .playback session; the quizmaster still
            // works, just without echo cancellation.
        }
    }

    // MARK: - Speaking

    /// Speak one prompt. Anything already playing is cut off first.
    /// - Parameter completion: called on the main actor when the utterance
    ///   finishes (or is cut off). The quizmaster uses this to arm the mic
    ///   exactly when the question ends -- never while we're still talking.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { completion?(); return }
        stop()
        pendingCompletion = completion
        // Cloud first. playCloud's failure observer falls back to the
        // device voice mid-flight if the stream can't play (no API key,
        // tunnel, 502) -- the game never goes silent.
        if !playCloud(trimmed) {
            speakOnDevice(trimmed)
        }
    }

    /// Fire-and-forget: fetch (and cache) the audio for `text` now, so
    /// speaking it later starts instantly. Used to pre-generate the *next*
    /// question while the players answer the current one -- zero dead air.
    func prefetch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = ttsURL(for: trimmed) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        ttsSession.dataTask(with: request).resume()
    }

    /// Wake the hosted server when Travel Mode opens. Render's free tier
    /// sleeps after ~15 min idle and takes 30-60s to wake; without this,
    /// the first question's cloud stream can't start within the 5s
    /// fallback timeout and the game opens on the robotic device voice.
    /// A short real line is used so the bytes are also useful if spoken.
    func warmUpServer() {
        prefetch("Let's play!")
    }

    func stop() {
        finishCompletion()
        teardownPlayer()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    // MARK: - Cloud TTS

    private func ttsURL(for text: String) -> URL? {
        var components = URLComponents(
            url: AppConstants.serverURL.appendingPathComponent("api/voice/tts"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "text", value: text)]
        return components?.url
    }

    /// Streams the backend's TTS audio. Returns true when playback started
    /// (cloud path); false means "use the on-device fallback" now.
    /// A failed stream (e.g. the server 502s with no API key configured)
    /// falls back mid-flight via the failure observer below.
    private func playCloud(_ text: String) -> Bool {
        guard let url = ttsURL(for: text) else { return false }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        isSpeaking = true
        didFallback = false
        let center = NotificationCenter.default
        endObserver = center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cloudDidFinish() }
        }
        failObserver = center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cloudDidFail(text) }
        }
        player.play()
        // If the stream can't even start (server down, 502, tunnel),
        // don't hang: fall back to the device voice after a short wait.
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run { [weak self] in
                self?.cloudStartTimeout(text)
            }
        }
        return true
    }

    private func cloudStartTimeout(_ text: String) {
        // Still not playing and not finished: the stream is stuck.
        guard player?.timeControlStatus != .playing,
              player?.currentItem != nil else { return }
        cloudDidFail(text)
    }

    private func cloudDidFail(_ text: String) {
        guard !didFallback else { return }
        didFallback = true
        teardownPlayer()
        speakOnDevice(text)
    }

    private func cloudDidFinish() {
        teardownPlayer()
        isSpeaking = false
        usingCloudVoice = true
        finishCompletion()
    }

    private func teardownPlayer() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = failObserver {
            NotificationCenter.default.removeObserver(observer)
            failObserver = nil
        }
        player?.pause()
        player = nil
    }

    private func finishCompletion() {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?()
    }

    // MARK: - On-device fallback

    private func speakOnDevice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let fallbackVoice { utterance.voice = fallbackVoice }
        // Deliberate and clear at highway noise levels; the default rate
        // (0.5) is too fast over road noise for younger/older players.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.1
        isSpeaking = true
        synthesizer.speak(utterance)
    }
}

extension TravelSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.finishCompletion()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.finishCompletion()
        }
    }
}
