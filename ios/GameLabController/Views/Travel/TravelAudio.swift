import AVFoundation
import SwiftUI

/// Spoken prompts for Travel Mode: the passenger taps "Read Aloud" and the
/// question/prompt plays through the car's speakers.
///
/// CARPLAY LIMITATION — there is no CarPlay screen UI for games, by Apple's
/// design, not ours: CarPlay app categories are limited (audio, messaging,
/// navigation, parking, charging, food ordering) and there is no games
/// entitlement, so a game cannot render CarPlay templates at all. "CarPlay
/// support" in Travel Mode therefore means audio routing only: a normal
/// AVAudioSession `.playback` category routes the speech through the car
/// speakers automatically whenever the iPhone is connected via CarPlay or
/// car Bluetooth, exactly like music or podcast audio. Do not attempt
/// CarPlay scenes, templates, or entitlements here.
@MainActor
final class TravelSpeech: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    @Published private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    /// `.playback` (not `.playAndRecord`) because Travel Mode only ever
    /// plays audio out — no microphone input — and `.playback` is the
    /// category that keeps routing to CarPlay / car Bluetooth speakers
    /// even with the screen locked or the silent switch on.
    func configureAudioSession() {
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

    /// Speak one prompt. Anything already playing is cut off first — in a
    /// moving car, the newest prompt always wins over a stale one.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: trimmed)
        // Deliberate and clear at highway noise levels; the default rate
        // (0.5) is too fast over road noise for younger/older players.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.preUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}

extension TravelSpeech: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
