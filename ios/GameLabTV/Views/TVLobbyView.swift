import SwiftUI

/// Displayed on TV while players join via their phones.
struct TVLobbyView: View {
    let room: Room
    /// Whether *this* room was created via the solo path (TVRootViewModel's
    /// own tracked flag -- the server's Room JSON carries no `solo` field at
    /// all, see room_manager.Room.to_json). Needed explicitly now that
    /// "Invite Friends" (TVGameSelectionView.soloChoiceGame) can put a
    /// soloPlayable game into a real, non-solo room with zero players at
    /// first: re-deriving "is this solo" from `room.players.count <= 1`, as
    /// this view used to, was only ever safe because a solo room always
    /// started with exactly one (synthetic) player -- it would have
    /// misread a freshly created, still-empty "Invite Friends" room as solo
    /// and shown Start Game as immediately clickable before anyone joined.
    let isSolo: Bool
    let onStart: () -> Void

    @EnvironmentObject private var vm: TVRootViewModel
    // Start Game keeps the initial focus even though the lobby options
    // above it are focusable too.
    @Namespace private var lobbyFocus

    private var canAddBot: Bool {
        (room.botsAllowed ?? false) && room.players.count < room.gameID.maxPlayers
    }

    var body: some View {
        HStack(spacing: 80) {
            // Left — room code + QR
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Text("Join on your phone")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.6))

                    Text(room.code)
                        .font(.system(size: 96, weight: .black, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                        .kerning(12)

                    Text("Open Aurora Play and enter the code")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.4))

                    Text("or scan to join")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }

                // Scannable QR for zero-typing join, served by /native/qr/<code>.
                ZStack {
                    Circle()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 2)
                        .frame(width: 220, height: 220)
                    Circle()
                        .stroke(Color.cyan.opacity(0.15), lineWidth: 1)
                        .frame(width: 270, height: 270)
                        .scaleEffect(1.05)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: true)

                    AsyncImage(url: AppConstants.serverURL
                        .appendingPathComponent("native/qr/\(room.code)")) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            Image(systemName: "qrcode")
                                .font(.system(size: 80))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .frame(width: 170, height: 170)
                    .background(Color.white)
                    .cornerRadius(16)
                }
            }
            .frame(maxWidth: 520)

            // Right — player list + start
            VStack(alignment: .leading, spacing: 24) {
                Text(room.gameID.displayName)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                // A solo room now genuinely sits here with zero players
                // until Start is pressed (see TVRootViewModel's own comment
                // on why) -- "0 / 4 players" read as broken rather than
                // optional, so solo gets its own, clearer line instead.
                if isSolo && room.players.isEmpty {
                    Text("Playing solo — invite friends with the code, or just press Start")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Text("\(room.players.count) / \(room.gameID.maxPlayers) players")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.5))
                }

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(room.players) { player in
                            PlayerRow(player: player)
                        }
                        // Empty slots. Clamped because a range whose lower bound
                        // exceeds its upper bound traps at runtime, and the player
                        // count is server-supplied.
                        ForEach(0..<max(0, room.gameID.maxPlayers - room.players.count), id: \.self) { _ in
                            EmptySlotRow()
                        }
                    }
                }

                lobbyOptions

                Spacer()

                // A solo room has one synthetic player and no phones to wait for.
                let canStart = isSolo || room.players.count >= room.gameID.minPlayers
                Button(action: onStart) {
                    Label(canStart ? "Start Game" : "Waiting for \(room.gameID.minPlayers - room.players.count) more…",
                          systemImage: canStart ? "play.fill" : "hourglass")
                        .font(.title3.bold())
                        .foregroundColor(canStart ? .black : .white.opacity(0.4))
                        .padding(.horizontal, 40)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(canStart ? Color.cyan : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .prefersDefaultFocus(true, in: lobbyFocus)
            }
            .frame(maxWidth: 520)
        }
        .padding(80)
        .focusScope(lobbyFocus)
    }

    /// Question language (Trivia/KBC) and bot seat-fillers. Focusable with
    /// the Siri Remote, so the host can set these up without a phone.
    @ViewBuilder
    private var lobbyOptions: some View {
        if room.usesContentPack ?? false {
            // One button that cycles English -> Telugu -> Hindi: three side
            // by side do not fit this column at tvOS button sizes.
            let current = ContentPack(rawValue: room.contentPack ?? "en") ?? .en
            Button {
                vm.setContentPack(current.next)
            } label: {
                Label("Questions: \(current.label)", systemImage: "character.bubble.fill")
            }
            .font(.callout.bold())
        }
        if room.botsAllowed ?? false {
            HStack(spacing: 14) {
                Button {
                    vm.addBot()
                } label: {
                    Label("Add Bot", systemImage: "cpu")
                }
                .disabled(!canAddBot)
                if let bot = room.players.last(where: { $0.isBot }) {
                    Button {
                        vm.removeBot(bot.id)
                    } label: {
                        Label("Remove Bot", systemImage: "minus.circle")
                    }
                }
            }
            .font(.callout.bold())
        }
    }
}

private struct PlayerRow: View {
    let player: Player

    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.purple.opacity(0.4))
                .frame(width: 40, height: 40)
                .overlay(Text(String(player.name.prefix(1))).foregroundColor(.white))

            Text(player.name)
                .foregroundColor(.white)
                .font(.body)

            if player.isHost { Text("HOST").font(.caption2).foregroundColor(.cyan) }
            if player.isBot {
                Text("BOT")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.2)))
            }

            Spacer()

            Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                .foregroundColor(player.isReady ? .green : .white.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }
}

private struct EmptySlotRow: View {
    var body: some View {
        HStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1, antialiased: true)
                .frame(width: 40, height: 40)
            Text("Waiting…")
                .foregroundColor(.white.opacity(0.2))
                .font(.body)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
    }
}
