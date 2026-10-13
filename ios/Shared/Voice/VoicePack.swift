import AVFoundation
import CryptoKit
import Foundation

// MARK: - Offline voice pack
//
// The games speak a lot of fixed text (quiz questions, dilemmas, host banter,
// narration). Rendering that through a cloud voice on every game costs credits
// and needs a connection. Instead those lines are rendered ONCE, offline, by
// tools/render_voice_pack.py and shipped inside the app as small audio files.
//
// A clip is looked up by the text of one SENTENCE, so a line like
//     "Teja chose truth. What is the silliest thing you were scared of?"
// plays the second sentence from the pack and speaks only the first (the one
// with the player's name in it) live. A line with no clip at all is spoken
// exactly as before, so an empty pack changes nothing.
//
// The splitting and hashing rules here MUST match tools/render_voice_pack.py
// (tests/test_voice_pack.py pins the same golden values; `selfCheck()` below
// fails a debug launch if the two ever drift apart).

enum VoicePack {

    /// Sentences of `text`: split after . ? or ! when whitespace (or the end)
    /// follows. Punctuation stays with its sentence. Blank pieces are dropped.
    static func pieces(of text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (index, ch) in chars.enumerated() {
            current.append(ch)
            if ch == "." || ch == "?" || ch == "!" {
                let atEnd: Bool = index + 1 >= chars.count
                if atEnd || chars[index + 1].isWhitespace {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { out.append(trimmed) }
                    current = ""
                }
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    /// Lower-case, runs of whitespace collapsed to one space.
    static func normalized(_ piece: String) -> String {
        piece.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// The clip's file name (without extension): the first 16 hex characters
    /// of the SHA-256 of the normalized sentence.
    static func key(for piece: String) -> String {
        let digest = SHA256.hash(data: Data(normalized(piece).utf8))
        let hex: String = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// The bundled audio for one sentence, or nil.
    static func clipURL(for piece: String) -> URL? {
        Bundle.main.url(forResource: key(for: piece), withExtension: "m4a")
    }

    /// True when at least one sentence of `text` has a bundled clip.
    static func hasAnyClip(for text: String) -> Bool {
        pieces(of: text).contains { clipURL(for: $0) != nil }
    }

    /// Debug-only guard that this file and the Python renderer agree. A
    /// mismatch would silently leave every clip unplayed, so fail loudly.
    static func selfCheck() {
        #if DEBUG
        assert(pieces(of: "Hi there.  Second one? Yes!") == ["Hi there.", "Second one?", "Yes!"],
               "VoicePack.pieces drifted from tools/render_voice_pack.py")
        assert(key(for: "Hello,   World!  ") == "68e656b251e67e83",
               "VoicePack.key drifted from tools/render_voice_pack.py")
        #endif
    }
}

// MARK: - Settings

/// One switch for the paid cloud voice. Off by default: lines come from the
/// bundled pack, then the device voice. Turn it on for the studio-quality
/// voice on every line (it spends cloud credits).
enum VoiceSettings {
    private static let cloudKey = "aurora_studio_voice"

    static var cloudAllowed: Bool {
        get { UserDefaults.standard.bool(forKey: cloudKey) }
        set { UserDefaults.standard.set(newValue, forKey: cloudKey) }
    }
}

// MARK: - Playing a line from the pack

/// Plays one line sentence by sentence: bundled clips where the pack has
/// them, and a `live` closure (the caller's own voice) for the rest.
///
/// `play` returns false, having done nothing, when no sentence has a clip, so
/// the caller keeps its existing path for that line. Starting a new line (or
/// `stop()`) cancels the current one without running its completion.
@MainActor
final class VoiceClipSequencer: NSObject, AVAudioPlayerDelegate {

    /// Speak one piece with the caller's voice and call `done` when it ends.
    typealias LiveSpeaker = @MainActor (_ piece: String, _ done: @escaping () -> Void) -> Void

    private var player: AVAudioPlayer?
    private var token = 0

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(_ text: String,
              rate: Float = 1.0,
              preDelay: TimeInterval = 0,
              live: @escaping LiveSpeaker,
              completion: (@MainActor () -> Void)?) -> Bool {
        let pieces = VoicePack.pieces(of: text)
        guard pieces.contains(where: { VoicePack.clipURL(for: $0) != nil }) else { return false }
        stop()
        token += 1
        let mine = token
        step(pieces[...], mine, rate, preDelay, live, completion)
        return true
    }

    func stop() {
        token += 1
        player?.stop()
        player = nil
    }

    private func step(_ remaining: ArraySlice<String>,
                      _ mine: Int,
                      _ rate: Float,
                      _ preDelay: TimeInterval,
                      _ live: @escaping LiveSpeaker,
                      _ completion: (@MainActor () -> Void)?) {
        guard mine == token else { return }
        guard let piece = remaining.first else {
            completion?()
            return
        }
        let rest = remaining.dropFirst()
        let next: () -> Void = { [weak self] in
            Task { @MainActor in
                self?.step(rest, mine, rate, 0, live, completion)
            }
        }
        if let url = VoicePack.clipURL(for: piece),
           let clip = try? AVAudioPlayer(contentsOf: url) {
            finishOnEnd = next
            clip.delegate = self
            if rate != 1.0 {
                clip.enableRate = true
                clip.rate = max(0.5, min(2.0, rate))
            }
            player = clip
            let started: Bool = preDelay > 0 ? clip.play(atTime: clip.deviceCurrentTime + preDelay)
                                             : clip.play()
            if started { return }
            player = nil
            finishOnEnd = nil
        }
        live(piece, next)
    }

    private var finishOnEnd: (() -> Void)?

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard finished === self.player else { return }
            self.player = nil
            let next = self.finishOnEnd
            self.finishOnEnd = nil
            next?()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ finished: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard finished === self.player else { return }
            self.player = nil
            let next = self.finishOnEnd
            self.finishOnEnd = nil
            next?()
        }
    }
}
