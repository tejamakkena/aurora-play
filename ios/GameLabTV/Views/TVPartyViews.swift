import SwiftUI

// Game Night dressed as a party (server: games/night_party.py; the settings ride
// along in room_updated as Room.night.party).
//
// The TV holds the welcome screen ("Welcome to Venkat's Birthday Party") until the
// host begins, then speaks the welcome and the lineup in the app's one voice, then
// hands over to the normal lobby for the first game. At the very end it speaks the
// finale. The server fixes the wording, so every device agrees.

struct TVPartyWelcomeView: View {
    let room: Room
    let party: NightParty

    @EnvironmentObject private var vm: TVRootViewModel
    @StateObject private var voice = TVVoiceHost()
    @State private var started = false
    @State private var appeared = false

    private var slots: [TVNightSlot] {
        TVNightSlot.slots(from: room.night?.playlist ?? [])
    }

    /// The line being spoken now, shown under the title.
    @State private var caption = ""

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)

            Image(systemName: "party.popper.fill")
                .font(.system(size: 110, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [ShellTheme.pink, ShellTheme.gold],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(appeared ? 1.0 : 0.4)

            VStack(spacing: 8) {
                Text("WELCOME TO")
                    .font(ShellTheme.eyebrow(28))
                    .tracking(10)
                    .foregroundColor(ShellTheme.textSecondary)
                Text(party.title)
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [ShellTheme.pink, ShellTheme.orange, ShellTheme.cyan],
                                                    startPoint: .leading, endPoint: .trailing))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 90)
                if !party.cheer.isEmpty {
                    Text(party.cheer)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }

            if party.welcomed {
                if !slots.isEmpty {
                    TVNightPlaylistStrip(slots: slots, currentIndex: nil, tileSize: 84)
                }
                Text(caption)
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 160)
                    .frame(minHeight: 90)
            } else {
                waitingBlock
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) { appeared = true }
            // Opened mid-party (the TV app restarted): nothing to announce.
            if party.welcomed { vm.partyWelcomeDone = true }
        }
        .onChange(of: party.welcomed) { _, welcomed in
            if welcomed { announce() }
        }
        .onDisappear { voice.stopSpeaking() }
    }

    /// Before the host begins: the room code, who is here, and a fallback button.
    private var waitingBlock: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("JOIN WITH CODE")
                    .font(ShellTheme.eyebrow(20))
                    .tracking(6)
                    .foregroundColor(ShellTheme.textTertiary)
                Text(room.code)
                    .font(.system(size: 64, weight: .heavy, design: .monospaced))
                    .kerning(10)
                    .foregroundColor(ShellTheme.cyan)
            }
            if !room.players.isEmpty {
                Text(room.players.map(\.name).joined(separator: "   "))
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, 120)
            }
            Text("Waiting for the host to begin the party")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.textTertiary)
            // The host's phone normally does this; the remote can too.
            Button {
                vm.beginParty()
            } label: {
                Label("Begin the party", systemImage: "party.popper.fill")
            }
            .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.pink))
        }
    }

    private func announce() {
        guard !started else { return }
        started = true
        let lines = party.welcomeLines + party.lineupLines
        speak(lines, index: 0)
    }

    /// One line after another, so the caption follows the voice.
    private func speak(_ lines: [String], index: Int) {
        guard index < lines.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { vm.partyWelcomeDone = true }
            return
        }
        caption = lines[index]
        voice.speak(lines[index]) {
            speak(lines, index: index + 1)
        }
    }
}

/// Speaks the finale (the champion and the cheer) once, when the night's results
/// screen opens. Draws nothing.
struct TVPartyFinaleSpeaker: View {
    let lines: [String]

    @StateObject private var voice = TVVoiceHost()
    @State private var spoken = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                guard !spoken, !lines.isEmpty else { return }
                spoken = true
                // Let the champion reveal land before the voice starts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { speak(0) }
            }
    }

    private func speak(_ index: Int) {
        guard index < lines.count else { return }
        voice.speak(lines[index]) { speak(index + 1) }
    }
}
