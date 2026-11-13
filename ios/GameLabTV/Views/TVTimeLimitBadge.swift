import Combine
import SwiftUI

/// The host's time limit, counting down in the corner of a timed game. The
/// server sends the moment it ends (Room.timeEndsAt), so every screen agrees.
/// The host calls out the last minute, the last ten seconds and the end; the
/// lines are fixed, so the voice pack has them.
struct TVTimeLimitBadge: View {
    let endsAt: Double?

    @StateObject private var voice = TVVoiceHost()
    /// Which calls have been made for this deadline (60, 10, 0).
    @State private var called: Set<Int> = []
    @State private var calledFor: Double? = nil

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Seconds left -> what the host says when the clock reaches it.
    static let calls: [(at: Int, line: String)] = [
        (60, "One minute to go!"),
        (10, "Ten seconds left!"),
        (0, "Time is up, everybody!"),
    ]

    var body: some View {
        if let endsAt {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let left = max(0, Int(endsAt - context.date.timeIntervalSince1970))
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .monospacedDigit()
                }
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(left <= 30 ? ShellTheme.pink : Color.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                .scaleEffect(left <= 10 && left > 0 ? 1.12 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: left <= 10)
                .accessibilityLabel("Time left, \(left / 60) minutes \(left % 60) seconds")
            }
            .onAppear { voice.isInterlude = true }
            .onReceive(tick) { now in
                callOut(endsAt: endsAt, now: now)
            }
        }
    }

    /// Say each call once, when the clock first reaches it. A call already
    /// passed when the badge appears (a TV that joined late) is skipped,
    /// except the last one.
    private func callOut(endsAt: Double, now: Date) {
        if calledFor != endsAt {
            calledFor = endsAt
            let left = Int(endsAt - now.timeIntervalSince1970)
            called = Set(Self.calls.map(\.at).filter { $0 > left && $0 != 0 })
        }
        let left = max(0, Int(endsAt - now.timeIntervalSince1970))
        guard let call = Self.calls.first(where: { left <= $0.at && !called.contains($0.at) }) else { return }
        called.formUnion(Self.calls.map(\.at).filter { $0 >= call.at })
        voice.speak(call.line, style: call.at == 0 ? "hype" : "playful")
    }
}
