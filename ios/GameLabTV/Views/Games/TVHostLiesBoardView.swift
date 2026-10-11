import SwiftUI

/// TV board for The Host Is Lying.
///
/// The TV is the host: it speaks each statement through `TVVoiceHost`, with
/// the server's delivery numbers (speaking rate, pause before speaking) so a
/// "rushed" or "stalling" tell is something the room can actually hear. When
/// players press the host it answers in the same voice. Phones lock in Trust
/// or Liar, and the reveal says who was fooled and which tells were used.
///
/// Server side: games/native_hub/engines/host_lies.py. This board only gets
/// `game_state` (the engine sets heavy_state), which is where the delivery
/// numbers live; phones never see them.

struct HostLiesBoardState {
    struct Defence: Identifiable, Equatable {
        let seq: Int
        let by: String
        let text: String
        var id: Int { seq }
    }

    var base = RoundBoardState()
    var statement = ""
    var votesSoFar = 0
    var pressesLeft = 3
    var hostFooled = 0
    var defences: [Defence] = []

    var speechSeq = 0
    var speechText = ""
    var speechRate: Float = 1.0
    var speechPreDelay: Double = 0

    var isLie = false
    var truth = ""
    var why = ""
    var tells: [String] = []
    var liarCount = 0
    var trustCount = 0
    var fooled = 0
    var challenger = ""
    var hasReveal = false

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        statement = d["statement"]?.value as? String ?? ""
        votesSoFar = d["votesSoFar"]?.value as? Int ?? 0
        pressesLeft = d["pressesLeft"]?.value as? Int ?? 3
        hostFooled = d["hostFooled"]?.value as? Int ?? 0
        defences = (d["defences"]?.value as? [Any] ?? []).compactMap { raw in
            guard let r = raw as? [String: Any], let seq = r["seq"] as? Int,
                  let text = r["text"] as? String else { return nil }
            return Defence(seq: seq, by: r["by"] as? String ?? "Someone", text: text)
        }
        if let speech = d["speech"]?.value as? [String: Any] {
            speechSeq = speech["seq"] as? Int ?? 0
            speechText = speech["text"] as? String ?? ""
            speechRate = Float((speech["rate"] as? Double) ?? Double(speech["rate"] as? Int ?? 1))
            speechPreDelay = (speech["preDelay"] as? Double) ?? Double(speech["preDelay"] as? Int ?? 0)
        }
        if let r = d["reveal"]?.value as? [String: Any] {
            hasReveal = true
            isLie = r["isLie"] as? Bool ?? false
            truth = r["truth"] as? String ?? ""
            why = r["why"] as? String ?? ""
            tells = (r["tells"] as? [Any] ?? []).compactMap { $0 as? String }
            liarCount = r["liar"] as? Int ?? 0
            trustCount = r["trust"] as? Int ?? 0
            fooled = r["fooled"] as? Int ?? 0
            challenger = r["challenger"] as? String ?? ""
        } else {
            hasReveal = false
        }
    }
}

struct TVHostLiesBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: HostLiesBoardState()) { $0.update(from: $1) }
    @StateObject private var voice = TVVoiceHost()

    private var state: HostLiesBoardState { vm.state }
    private var phase: String { state.base.phase }
    private let accent = TVTheme.orange

    private var phaseLabel: String {
        switch phase {
        case "claim":  return "listen to the host"
        case "grill":  return "press the host"
        case "vote":   return "trust or liar?"
        case "reveal": return "the verdict"
        default:       return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "mic.fill", title: "The Host Is Lying",
                          round: state.base.round, totalRounds: state.base.totalRounds,
                          secondsLeft: state.base.secondsLeft, phaseLabel: phaseLabel)
            Spacer(minLength: 12)
            stage
            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 30)
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: state.speechSeq) { _, _ in speakLatest() }
        .onDisappear { voice.stopSpeaking() }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        if phase == "final" {
            VStack(spacing: 14) {
                Text("Game over")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("The host fooled \(state.hostFooled) votes in total")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
            }
        } else if phase == "reveal" && state.hasReveal {
            revealStage
        } else {
            VStack(spacing: 30) {
                HostOrb(isTalking: phase == "claim" || phase == "grill")
                TVGlassCard(cornerRadius: ShellTheme.cardRadius, tint: accent, padding: 0) {
                    Text(state.statement)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                }
                if phase == "grill" || !state.defences.isEmpty {
                    defenceList
                }
            }
        }
    }

    private var defenceList: some View {
        VStack(spacing: 12) {
            ForEach(state.defences) { item in
                HStack(spacing: 14) {
                    Text("\(item.by) pressed:")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(accent)
                    Text("\"\(item.text)\"")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08)))
            }
            if phase == "grill" && state.pressesLeft > 0 {
                Text("Press the host on your phone (\(state.pressesLeft) left)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
    }

    private var revealStage: some View {
        VStack(spacing: 22) {
            Text(state.isLie ? "THE HOST LIED" : "THE HOST TOLD THE TRUTH")
                .font(.system(size: 76, weight: .heavy, design: .rounded))
                .foregroundColor(state.isLie ? TVTheme.red : TVTheme.green)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\"\(state.statement)\"")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .strikethrough(state.isLie, color: TVTheme.red)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            if state.isLie {
                Text(state.truth)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
            }
            Text(state.why)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            HStack(spacing: 28) {
                RevealChip(label: "Said Liar", value: "\(state.liarCount)", tint: TVTheme.red)
                RevealChip(label: "Said Trust", value: "\(state.trustCount)", tint: TVTheme.green)
                RevealChip(label: "Fooled", value: "\(state.fooled)", tint: accent)
            }
            Text(state.tells.isEmpty ? "No tells this round"
                                     : "Tells used: " + state.tells.joined(separator: ", "))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            if !state.challenger.isEmpty {
                Text("\(state.challenger) pressed the host first")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 14) {
            if phase == "vote" {
                Text("\(state.votesSoFar) of \(max(state.base.players.count, state.votesSoFar)) locked in")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
            TVScoreStrip(players: state.base.players)
        }
    }

    // MARK: Voice

    private func speakLatest() {
        guard state.speechSeq > 0, !state.speechText.isEmpty else { return }
        voice.speak(state.speechText, rate: state.speechRate, preDelay: state.speechPreDelay)
    }
}

/// The host's face: a microphone orb that pulses while the host is talking.
private struct HostOrb: View {
    let isTalking: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(TVTheme.orange.opacity(0.25))
                .frame(width: 150, height: 150)
                .scaleEffect(isTalking && pulse ? 1.18 : 1.0)
            Circle()
                .fill(LinearGradient(colors: [TVTheme.orange, TVTheme.red],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 110, height: 110)
            Image(systemName: "mic.fill")
                .font(.system(size: 50, weight: .bold))
                .foregroundColor(.white)
        }
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}

private struct RevealChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 36).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.08)))
    }
}
