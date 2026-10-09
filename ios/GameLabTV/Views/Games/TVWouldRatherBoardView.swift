import SwiftUI

/// TV board for Would You Rather: two huge halves, A and B. Everyone votes on
/// their phone; the reveal fills each half with its share of the room and lists
/// who chose it. The TV reads each dilemma aloud.
///
/// Server side: games/native_hub/engines/would_rather.py.

struct WouldRatherBoardState {
    var base = RoundBoardState()
    var a = ""
    var b = ""
    var votesSoFar = 0
    var aPercent = 0
    var bPercent = 0
    var aNames: [String] = []
    var bNames: [String] = []

    mutating func update(from d: [String: AnyCodable]) {
        base.updateBase(from: d)
        if let v = d["a"]?.value as? String { a = v }
        if let v = d["b"]?.value as? String { b = v }
        if let v = d["votesSoFar"]?.value as? Int { votesSoFar = v }
        if let r = d["reveal"]?.value as? [String: Any] {
            aPercent = r["aPercent"] as? Int ?? 0
            bPercent = r["bPercent"] as? Int ?? 0
            aNames = (r["aNames"] as? [Any] ?? []).compactMap { $0 as? String }
            bNames = (r["bNames"] as? [Any] ?? []).compactMap { $0 as? String }
        } else {
            aPercent = 0
            bPercent = 0
            aNames = []
            bNames = []
        }
    }
}

struct TVWouldRatherBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: WouldRatherBoardState()) { $0.update(from: $1) }
    @StateObject private var voice = TVVoiceHost()

    private var state: WouldRatherBoardState { vm.state }
    private var isReveal: Bool { state.base.phase == "reveal" }
    private var cardKey: String { "\(state.base.round)|\(state.a)|\(state.b)" }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "arrow.left.arrow.right", title: "Would You Rather",
                          round: state.base.round, totalRounds: state.base.totalRounds,
                          secondsLeft: state.base.secondsLeft,
                          phaseLabel: isReveal ? "the room has split" : "pick a side on your phone")
            Spacer(minLength: 12)
            Text("Would you rather...")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
            HStack(spacing: 28) {
                half(label: "A", text: state.a, percent: state.aPercent, names: state.aNames,
                     colors: [TVTheme.blue, ShellTheme.violet])
                Text("or")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                half(label: "B", text: state.b, percent: state.bPercent, names: state.bNames,
                     colors: [TVTheme.orange, TVTheme.red])
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 24)
            if !isReveal {
                Text("\(state.votesSoFar) of \(max(state.base.players.count, state.votesSoFar)) have voted")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer(minLength: 12)
            TVScoreStrip(players: state.base.players)
                .padding(.bottom, 30)
        }
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: cardKey) { _, _ in readCard() }
        .onDisappear { voice.stopSpeaking() }
    }

    private func half(label: String, text: String, percent: Int, names: [String],
                      colors: [Color]) -> some View {
        VStack(spacing: 18) {
            Text(label)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundColor(.white.opacity(0.8))
            Text(text)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .frame(maxHeight: .infinity)
            if isReveal {
                Text("\(percent)%")
                    .font(.system(size: 76, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(names.isEmpty ? "Nobody" : names.joined(separator: ", "))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 420)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(LinearGradient(colors: colors.map { $0.opacity(isReveal ? 0.9 : 0.55) },
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .animation(.easeInOut(duration: 0.4), value: isReveal)
    }

    private func readCard() {
        guard !state.a.isEmpty, !state.b.isEmpty else { return }
        voice.speak("Would you rather \(state.a), or \(state.b)?")
    }
}
