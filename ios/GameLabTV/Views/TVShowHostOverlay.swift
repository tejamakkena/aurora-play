import SwiftUI

// MARK: - Game Night show host
//
// The server's show host (games/show_host.py) sends a line at the big
// moments of a Game Night: the opener, a teaser before each game, a reaction
// when a quiz question stumps the room, a cheer for each winner, the
// standings, the closer. This is the TV side: a talk-show lower third with
// the headline (which may name a player) and the line, spoken in the app's
// one voice.
//
// The game always comes first. The host's voice is an interlude
// (TVVoiceHost.isInterlude): it waits while a board is talking, and a board
// that starts talking cuts it off. Every spoken line is fixed text, so with
// the voice pack rendered it plays in the natural voice.

struct TVShowHostOverlay: View {
    @ObservedObject var vm: TVRootViewModel

    @StateObject private var voice = TVVoiceHost()
    @State private var current: HostLine?

    /// Longest the host waits for a board to stop talking before showing the
    /// line without saying it.
    private static let maxWait: TimeInterval = 6
    /// Shortest time a card stays up, and the hard limit for one card.
    private static let minShown: TimeInterval = 4
    private static let maxShown: TimeInterval = 14

    var body: some View {
        VStack {
            Spacer()
            if let current {
                TVShowHostCard(line: current)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(current.seq)
            }
        }
        .padding(.bottom, 48)
        .allowsHitTesting(false)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: current?.seq)
        .onAppear {
            voice.isInterlude = true
            showNext()
        }
        .onChange(of: vm.hostLines.count) { _, _ in
            if current == nil { showNext() }
        }
    }

    private func showNext() {
        guard current == nil, let line = vm.takeHostLine() else { return }
        current = line
        let shownAt = Date()
        // Hard limit: a line whose speech never reports back still goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxShown) { finish(line) }
        speakWhenQuiet(line, shownAt: shownAt, waited: 0)
    }

    private func speakWhenQuiet(_ line: HostLine, shownAt: Date, waited: TimeInterval) {
        guard current?.seq == line.seq else { return }
        if TVVoiceHost.boardIsTalking {
            if waited >= Self.maxWait {
                hold(line, shownAt: shownAt)          // the board kept talking: text only
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                speakWhenQuiet(line, shownAt: shownAt, waited: waited + 0.3)
            }
            return
        }
        voice.speak(line.text, style: line.moment) {
            hold(line, shownAt: shownAt)
        }
    }

    /// Leave the card up a moment after the voice ends, at least `minShown` in all.
    private func hold(_ line: HostLine, shownAt: Date) {
        let shown = Date().timeIntervalSince(shownAt)
        let rest = max(1.2, Self.minShown - shown)
        DispatchQueue.main.asyncAfter(deadline: .now() + rest) { finish(line) }
    }

    private func finish(_ line: HostLine) {
        guard current?.seq == line.seq else { return }
        current = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showNext() }
    }
}

/// The lower third: a gold microphone badge, the headline, the line.
private struct TVShowHostCard: View {
    let line: HostLine

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            ZStack {
                Circle()
                    .fill(ShellTheme.gold)
                    .frame(width: 84, height: 84)
                Image(systemName: "mic.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR HOST")
                    .font(ShellTheme.eyebrow(18))
                    .tracking(4)
                    .foregroundColor(ShellTheme.gold)
                if !line.headline.isEmpty {
                    Text(line.headline)
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(line.text)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(ShellTheme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: 1400)
        .background(
            // A plain painted panel (no live blur): it sits over animated
            // boards, and a backdrop blur there would redraw every frame.
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(ShellTheme.panel.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .strokeBorder(ShellTheme.gold.opacity(0.7), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 80)
    }
}
