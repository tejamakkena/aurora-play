import SwiftUI

// MARK: - Settings and the welcome guide on the TV
//
// One place for everything the TV remembers about how it sounds (the voice,
// the host's pace, the bundled voice pack), plus a short guide that opens the
// first time the app runs and can be shown again from here.

struct TVSettingsView: View {
    let onShowGuide: () -> Void
    let onDone: () -> Void

    @ObservedObject private var socket = GameSocketManager.shared
    @State private var studioVoice = VoiceSettings.cloudAllowed
    @State private var paceIndex = VoiceSettings.paceIndex

    /// How many lines the bundled voice pack holds (0: not rendered yet).
    private var packClips: Int {
        Bundle.main.urls(forResourcesWithExtension: "m4a", subdirectory: nil)?.count ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                Text("SETTINGS")
                    .font(ShellTheme.eyebrow(28))
                    .tracking(6)
                    .foregroundColor(.white)

                section("Voice", note: studioVoice
                        ? "The studio voice reads every line live, with names and fresh questions. It uses the server's voice credits."
                        : "Free and works offline: the bundled voice pack, then the Apple TV's own voice for anything the pack does not have.") {
                    Button {
                        studioVoice = false
                        VoiceSettings.cloudAllowed = false
                    } label: {
                        Label("Offline", systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.violet, isSelected: !studioVoice))
                    .accessibilityIdentifier("voiceModeButton")
                    Button {
                        studioVoice = true
                        VoiceSettings.cloudAllowed = true
                        TVVoiceHost.warmServer()
                    } label: {
                        Label("Studio (online)", systemImage: "cloud.fill")
                    }
                    .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.violet, isSelected: studioVoice))
                }

                section("Host pace", note: "How fast the host talks, for the voice pack and the Apple TV voice.") {
                    ForEach(VoiceSettings.paces.indices, id: \.self) { index in
                        Button {
                            paceIndex = index
                            VoiceSettings.paceIndex = index
                        } label: {
                            Text(VoiceSettings.paces[index].name)
                        }
                        .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.cyan, isSelected: paceIndex == index))
                        .accessibilityIdentifier(index == 0 ? "voicePaceButton" : "voicePace\(index)")
                    }
                }

                section("Voice pack", note: packClips > 0
                        ? "\(packClips) lines are built into this app, so they play instantly with no internet."
                        : "No voice pack in this build yet. Render one with the Render voice pack workflow; lines play in the Apple TV voice until then.") {
                    Label(packClips > 0 ? "\(packClips) lines installed" : "Not installed",
                          systemImage: packClips > 0 ? "checkmark.seal.fill" : "exclamationmark.circle")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(packClips > 0 ? ShellTheme.mint : ShellTheme.textSecondary)
                }

                section("Server", note: socket.isConnected
                        ? "Connected. If the server restarts, the TV brings your room back with the same code."
                        : "Reconnecting. A sleeping server can take up to a minute to wake.") {
                    Label(socket.isConnected ? "Connected" : "Reconnecting",
                          systemImage: socket.isConnected ? "wifi" : "wifi.exclamationmark")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(socket.isConnected ? ShellTheme.mint : ShellTheme.pink)
                }

                HStack(spacing: 20) {
                    Button(action: onShowGuide) {
                        Label("Show the welcome guide", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(ShellPillButtonStyle(accent: ShellTheme.gold, isSelected: false))
                    Button(action: onDone) {
                        Label("Done", systemImage: "checkmark")
                    }
                    .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.pink))
                }
            }
            .padding(70)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black.opacity(0.92).ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, note: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(ShellTheme.eyebrow(20))
                .tracking(5)
                .foregroundColor(ShellTheme.textTertiary)
            HStack(spacing: 16) { content() }
            Text(note)
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Opens the first time the app runs: how phones join, what a Game Night is,
/// and what the two voices cost.
struct TVWelcomeGuide: View {
    let onDone: () -> Void

    private static let seenKey = "aurora_tv_guide_seen_v1"

    /// True until the guide has been closed once (never during UI tests).
    static var shouldShow: Bool {
        if CommandLine.arguments.contains("-aurora_fresh_start") { return false }
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    private struct Step: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
    }

    private static let steps: [Step] = [
        Step(id: 1, symbol: "iphone.gen3", title: "Phones are the controllers",
             text: "Pick a game here. The TV shows a code and a QR. Everyone scans it or opens Aurora Play on their phone and types the code. No accounts, no setup."),
        Step(id: 2, symbol: "moon.stars.fill", title: "Make it a Game Night",
             text: "Game Night plays a lineup of games with one scoreboard. Pick the games, rounds and scoring, or make it a party with a birthday name, a cheer and a host who jokes about every game."),
        Step(id: 3, symbol: "speaker.wave.2.fill", title: "Choose the voice",
             text: "Offline is free and works without internet. Studio reads every line live, names included, and uses voice credits. Change it any time in Settings."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text("WELCOME TO AURORA PLAY")
                .font(ShellTheme.eyebrow(30))
                .tracking(6)
                .foregroundColor(.white)
            HStack(alignment: .top, spacing: 30) {
                ForEach(Self.steps) { step in
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundColor(ShellTheme.gold)
                        Text(step.title)
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text(step.text)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(ShellTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06)))
                }
            }
            Button {
                Self.markSeen()
                onDone()
            } label: {
                Label("Let's play", systemImage: "sparkles")
            }
            .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.pink))
            .accessibilityIdentifier("guideDoneButton")
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.94).ignoresSafeArea())
    }
}
