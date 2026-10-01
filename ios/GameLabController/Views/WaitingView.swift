import SwiftUI

struct WaitingView: View {
    let room: Room
    let onReady: () -> Void
    let onLeave: () -> Void

    @State private var isReady = false
    @EnvironmentObject private var vm: ControllerRootViewModel

    var body: some View {
        VStack(spacing: 36) {
            // Once you've joined a room there was no way back to the join
            // screen at all -- reported directly. A wrong code/game or a
            // change of mind had nowhere to go.
            HStack {
                Button(action: onLeave) {
                    Label("Leave", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Game badge
            VStack(spacing: 12) {
                Image(systemName: room.gameID.sfSymbol)
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.85))
                Text(room.gameID.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }

            // Room code (small reference)
            HStack(spacing: 8) {
                Text("Room")
                    .foregroundColor(.white.opacity(0.4))
                Text(room.code)
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundColor(.cyan)
            }

            // Player list
            VStack(spacing: 10) {
                ForEach(room.players) { player in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(player.isReady ? Color.green.opacity(0.3) : Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                            .overlay(Text(String(player.name.prefix(1))).foregroundColor(.white).font(.caption.bold()))

                        Text(player.name)
                            .foregroundColor(.white)

                        if player.isHost { Text("HOST").font(.caption2).foregroundColor(.cyan) }
                        if player.isBot { Text("BOT").font(.caption2).foregroundColor(.orange) }

                        Spacer()

                        if player.isBot && vm.isHost {
                            Button { vm.removeBot(player.id) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }

                        Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(player.isReady ? .green : .white.opacity(0.2))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
                }
            }
            .padding(.horizontal, 24)

            if vm.isHost {
                HostLobbyControls(room: room)
                    .padding(.horizontal, 24)
            }

            // Private info note
            if room.gameID.hasPrivateInfo {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                    Text("Your private info will appear here when the game starts")
                        .font(.caption)
                }
                .foregroundColor(.cyan.opacity(0.7))
                .padding(.horizontal, 32)
            }

            Spacer()

            // Ready button
            Button(action: {
                isReady = true
                onReady()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "hand.thumbsup.fill")
                    Text(isReady ? "Ready!" : "I'm Ready")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isReady ? Color.green.opacity(0.3) : Color.cyan)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(isReady)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

/// Bot seat-fillers and question language -- shown to the host only.
private struct HostLobbyControls: View {
    let room: Room
    @EnvironmentObject private var vm: ControllerRootViewModel

    private var canAddBot: Bool {
        (room.botsAllowed ?? false) && room.players.count < room.gameID.maxPlayers
    }

    var body: some View {
        VStack(spacing: 12) {
            if room.usesContentPack ?? false {
                HStack(spacing: 8) {
                    Image(systemName: "character.bubble.fill")
                        .foregroundColor(.white.opacity(0.5))
                    ForEach(ContentPack.allCases) { pack in
                        let selected = (room.contentPack ?? "en") == pack.rawValue
                        Button { vm.setContentPack(pack) } label: {
                            Text(pack.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(selected ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(selected ? Color.cyan : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if room.botsAllowed ?? false {
                Button { vm.addBot() } label: {
                    Label("Add a bot player", systemImage: "cpu")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(canAddBot ? .orange : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(canAddBot ? 0.6 : 0.2), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(!canAddBot)
            }
        }
    }
}
