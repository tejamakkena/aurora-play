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
final class NeuroGuideVoice: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = NeuroGuideVoice()

    private let synthesizer = AVSpeechSynthesizer()
    private let clips = VoiceClipSequencer()
    private var liveDone: (() -> Void)?
    private static let defaultsKey = "neuro_guide_voice_on"

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// A live sentence between bundled clips ended: on to the next one.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let done = self.liveDone else { return }
            self.liveDone = nil
            done()
        }
    }

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
        stop()
        // The step prompts are fixed text: play the bundled recording when
        // there is one, and speak any other sentence in the device voice.
        if clips.play(line,
                      live: { [weak self] piece, done in
                          guard let self else { return }
                          self.liveDone = done
                          self.speakOnDevice(piece)
                      },
                      completion: nil) {
            return
        }
        speakOnDevice(line)
    }

    private func speakOnDevice(_ line: String) {
        let utterance = AVSpeechUtterance(string: line)
        // Slower and a touch lower than normal speech: this is a calming voice.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        utterance.pitchMultiplier = 0.95
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stop() {
        clips.stop()
        liveDone = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}
