import Foundation
import SwiftUI

/// The phone side of the cross-device voice loop (quizmaster spec §13).
///
/// Exactly one phone per room is the ear. This controller:
///  1. claims the mic (`claim_mic` -> server broadcasts `mic_reassigned`),
///  2. arms the on-device recognizer when the TV drives `voice_state`
///     to "listen", and disarms on "lock"/"grade"/"idle",
///  3. streams partial transcripts and the final transcript back over
///     `voice_transcript` (the TV shows captions and grades).
///
/// The TV grades: it owns the question + correct answer. This phone only
/// transcribes -- which is also why no API key ever touches the client.
@MainActor
final class TVMicController: ObservableObject {
    @Published var micPlayerID: String?
    @Published var micPlayerName: String?
    @Published var voiceState: String = "idle"
    @Published var isListening = false
    @Published var liveTranscript = ""

    var isMicHolder: Bool { micPlayerID == playerID }

    let roomCode: String
    let playerID: String

    private let socket = GameSocketManager.shared
    private let voice = TravelVoiceListener()
    private var attached = false

    init(roomCode: String, playerID: String) {
        self.roomCode = roomCode
        self.playerID = playerID
    }

    func attach() {
        guard !attached else { return }
        attached = true
        Task { _ = await voice.requestAuthorization() }
        socket.on(.micReassigned) { [weak self] (r: MicReassignedResponse) in
            guard let self, r.roomCode == self.roomCode else { return }
            self.micPlayerID = r.playerID
            self.micPlayerName = r.playerName
        }
        socket.on(.voiceState) { [weak self] (r: VoiceStateResponse) in
            guard let self, r.roomCode == self.roomCode else { return }
            self.voiceState = r.state
            if r.state == "listen", self.isMicHolder {
                self.startListening()
            } else {
                self.stopListening()
            }
            if r.state == "ask" || r.state == "idle" {
                self.liveTranscript = ""
            }
        }
    }

    func detach() {
        stopListening()
        socket.off(.micReassigned)
        socket.off(.voiceState)
        attached = false
    }

    func claimMic() {
        socket.emit(.claimMic, payload: ClaimMicPayload(
            roomCode: roomCode, playerID: playerID))
    }

    func holdBegan() {
        guard isMicHolder, voiceState == "listen" else { return }
        startListening()
    }

    func holdEnded() {
        voice.finishEarly()
    }

    // MARK: - Private

    private func startListening() {
        liveTranscript = ""
        isListening = true
        voice.start(
            timeout: 10,
            onPartial: { [weak self] partial in
                guard let self else { return }
                self.liveTranscript = partial
                self.emitTranscript(partial, isFinal: false)
            },
            onFinal: { [weak self] transcript, confidence in
                guard let self else { return }
                self.isListening = false
                self.emitTranscript(transcript, isFinal: true,
                                    confidence: confidence)
            }
        )
    }

    private func stopListening() {
        voice.stop()
        isListening = false
    }

    private func emitTranscript(_ text: String, isFinal: Bool,
                                confidence: Float = 0) {
        socket.emit(.voiceTranscript, payload: VoiceTranscriptPayload(
            roomCode: roomCode, playerID: playerID, text: text,
            isFinal: isFinal, confidence: Double(confidence)))
    }
}

/// Compact bottom bar for the controller's game screen: claim the mic,
/// see who holds it, and hold-to-talk while the TV listens.
struct MicClaimBar: View {
    @StateObject private var mic: TVMicController

    init(roomCode: String, playerID: String) {
        _mic = StateObject(wrappedValue: TVMicController(
            roomCode: roomCode, playerID: playerID))
    }

    var body: some View {
        HStack(spacing: 12) {
            if mic.isMicHolder {
                // Hold-to-talk while the TV listens.
                Button(action: {}) {
                    Image(systemName: mic.isListening ? "mic.fill" : "mic")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(
                            mic.isListening ? Color.green : Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in mic.holdBegan() }
                        .onEnded { _ in mic.holdEnded() }
                )
                .disabled(mic.voiceState != "listen")
                VStack(alignment: .leading, spacing: 2) {
                    Text(mic.isListening ? "Listening -- you're the mic"
                                         : "You're the mic")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    if !mic.liveTranscript.isEmpty {
                        Text(mic.liveTranscript)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    } else {
                        Text(mic.voiceState == "listen"
                             ? "Hold the button and answer"
                             : "Wait for the question")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            } else {
                Button { mic.claimMic() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                        Text(mic.micPlayerName ?? "Take the mic")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear { mic.attach() }
        .onDisappear { mic.detach() }
        .accessibilityLabel(mic.isMicHolder ? "Microphone held by you"
                                            : "Take the microphone")
    }
}
