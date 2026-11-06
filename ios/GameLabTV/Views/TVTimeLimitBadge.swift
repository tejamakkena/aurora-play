import SwiftUI

/// The host's time limit, counting down in the corner of a timed game. The
/// server sends the moment it ends (Room.timeEndsAt), so every screen agrees.
struct TVTimeLimitBadge: View {
    let endsAt: Double?

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
                .accessibilityLabel("Time left, \(left / 60) minutes \(left % 60) seconds")
            }
        }
    }
}
