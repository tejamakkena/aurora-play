import AVFoundation
import Foundation

/// A quiet spoken guide for the Zen steps of the Mind Gym (the breathing
/// pacer and the sensory reset). Those steps used to be silent: a timer and a
/// leaf, no words, no sound. This reads the instruction aloud and calls each
/// breath, in the phone's own voice, so the step works with eyes closed.
///
/// It plays through the `.playback` category, so it is heard with the ring
/// switch on silent too (someone doing a calm-down exercise has asked to be
/// guided), and mixes with whatever else is playing. A speaker button on the
/// step turns it off; the choice is remembered.
@MainActor
final class NeuroGuideVoice {

    static let shared = NeuroGuideVoice()

    private let synthesizer = AVSpeechSynthesizer()
    private static let defaultsKey = "neuro_guide_voice_on"

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            if !newValue { stop() }
        }
    }

    func speak(_ text: String) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !line.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? session.setActive(true)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: line)
        // Slower and a touch lower than normal speech: this is a calming voice.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        utterance.pitchMultiplier = 0.95
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
