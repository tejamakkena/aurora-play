import AVFoundation
import Foundation

/// The TV's voice.
///
/// Game Night's host voice (and Never Have I Ever reading each statement aloud)
/// goes through the system speech synthesiser, so a guest's name or any game
/// title can be dropped into the script -- there is nothing to record per name.
/// Like `SoundPlayer`, this lives in the TV target because the TV is the only
/// speaker in the room.
///
/// All calls are made from SwiftUI on the main thread; the delegate callbacks
/// hop back to it before touching any state.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = Announcer()

    /// How a line should sound. The server picks one per voice pack.
    struct Style {
        var language: String
        var rate: Float
        var pitch: Float

        static let standard = Style(language: "en-US", rate: 0.5, pitch: 1.0)
    }

    private let synth = AVSpeechSynthesizer()

    /// Bumped by every `speak` / `stop`. A callback from an earlier request
    /// carries an older number and is ignored, so cutting one announcement off
    /// to start the next can never fire the first one's completion.
    private var generation = 0
    private var remaining = 0
    private var completion: (() -> Void)?
    private var generationOf: [ObjectIdentifier: Int] = [:]

    /// The voice of the most recent announcement, so a game that wants to talk
    /// (Never Have I Ever) keeps the host's voice for the whole night.
    private(set) var style = Style.standard

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Reads `lines` one after another, then calls `completion` once, on the
    /// main thread. Starting a new announcement cancels the one in progress
    /// (its completion is never called).
    func speak(_ lines: [String], style: Style, completion: (() -> Void)? = nil) {
        stop()
        self.style = style

        let spoken = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !spoken.isEmpty else {
            completion?()
            return
        }

        generation += 1
        let current = generation
        self.completion = completion
        remaining = spoken.count

        let voice = AVSpeechSynthesisVoice(language: style.language)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        for line in spoken {
            let utterance = AVSpeechUtterance(string: line)
            utterance.voice = voice
            utterance.rate = min(max(style.rate, AVSpeechUtteranceMinimumSpeechRate),
                                 AVSpeechUtteranceMaximumSpeechRate)
            utterance.pitchMultiplier = min(max(style.pitch, 0.5), 2.0)
            utterance.postUtteranceDelay = 0.35
            generationOf[ObjectIdentifier(utterance)] = current
            synth.speak(utterance)
        }
    }

    /// Reads one line in the current voice.
    func say(_ text: String) {
        speak([text], style: style)
    }

    func stop() {
        generation += 1
        completion = nil
        remaining = 0
        generationOf.removeAll()
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            self?.finished(key)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            self?.generationOf.removeValue(forKey: key)
        }
    }

    private func finished(_ key: ObjectIdentifier) {
        guard let tag = generationOf.removeValue(forKey: key), tag == generation else { return }
        remaining -= 1
        if remaining <= 0 {
            let done = completion
            completion = nil
            done?()
        }
    }
}
