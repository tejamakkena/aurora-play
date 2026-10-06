import SwiftUI

/// Displayed on TV while players join via their phones.
///
/// Layout: a glass "join" card on the left (the room code as floating 3D
/// letter tiles, the QR code and the join link), and the room on the right
/// (the game, everyone who has joined as hopping avatar tokens, open seats as
/// breathing ghost tokens, lobby options and a prominent Start button).
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

    private var joinLinkText: String {
        let url = AppConstants.serverURL
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(url.host ?? "")\(port)/join/\(room.code)"
    }

    private var canAddBot: Bool {
        (room.botsAllowed ?? false) && room.players.count < room.gameID.maxPlayers
    }

    /// A solo room has one synthetic player and no phones to wait for.
    private var canStart: Bool {
        isSolo || room.players.count >= room.gameID.minPlayers
    }

    private var style: TVCategoryStyle { room.gameID.category.tvStyle }

    var body: some View {
        // Small outer padding: tvOS adds its own overscan safe area.
        HStack(alignment: .center, spacing: 48) {
            joinPanel
                .frame(width: 700)

            roomPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 40)
        .focusScope(lobbyFocus)
    }

    // MARK: Left -- join card

    private var joinPanel: some View {
        ShellGlassCard(cornerRadius: 44, tint: ShellTheme.cyan, padding: 44) {
            VStack(spacing: 30) {
                Text("JOIN ON YOUR PHONE")
                    .font(ShellTheme.eyebrow(24))
                    .tracking(6)
                    .foregroundColor(ShellTheme.textSecondary)

                RoomCodeTiles(code: room.code)

                Text("Open Aurora Play and enter the code")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textSecondary)

                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 2)

                HStack(alignment: .center, spacing: 34) {
                    LobbyQRCode(code: room.code)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("or scan to join")
                            .font(ShellTheme.display(30, weight: .bold))
                            .foregroundColor(.white)
                        Text("Point your phone camera at the code")
                            .font(.system(size: 21, weight: .regular, design: .rounded))
                            .foregroundColor(ShellTheme.textTertiary)
                        // The same link the QR encodes, for anyone who'd
                        // rather type it into a browser (or when hosting on a
                        // LAN address).
                        Text(joinLinkText)
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundColor(ShellTheme.cyan.opacity(0.85))
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Right -- the room

    private var roomPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 24) {
                ShellIconOrb(symbol: room.gameID.sfSymbol,
                             top: style.top,
                             bottom: style.bottom,
                             accent: style.accent,
                             size: 96,
                             isLit: true)
                    .phaseAnimator([false, true]) { content, phase in
                        content
                            .rotation3DEffect(.degrees(phase ? 12 : -12),
                                              axis: (x: 0, y: 1, z: 0),
                                              perspective: 0.5)
                    } animation: { _ in
                        Animation.easeInOut(duration: 2.4)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(room.gameID.category.rawValue.uppercased())
                        .font(ShellTheme.eyebrow(20))
                        .tracking(4)
                        .foregroundColor(style.accent)
                    Text(room.gameID.displayName)
                        .font(ShellTheme.display(52))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }

            // A solo room now genuinely sits here with zero players
            // until Start is pressed (see TVRootViewModel's own comment
            // on why) -- "0 / 4 players" read as broken rather than
            // optional, so solo gets its own, clearer line instead.
            if isSolo && room.players.isEmpty {
                Text("Playing solo — invite friends with the code, or just press Start")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundColor(ShellTheme.textSecondary)
            } else {
                HStack(spacing: 14) {
                    Text("\(room.players.count) / \(room.gameID.maxPlayers) players")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    if !canStart {
                        WaitingPulse(text: "Waiting for players")
                    }
                }
            }

            ShellGlassCard(cornerRadius: 36, tint: style.accent, padding: 28) {
                LobbyRoster(players: room.players, maxPlayers: room.gameID.maxPlayers)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            lobbyOptions

            Spacer(minLength: 0)

            Button(action: onStart) {
                Label(canStart ? "Start Game" : "Waiting for \(room.gameID.minPlayers - room.players.count) more…",
                      systemImage: canStart ? "play.fill" : "hourglass")
            }
            .buttonStyle(ShellPrimaryButtonStyle(tint: ShellTheme.cyan))
            .disabled(!canStart)
            .prefersDefaultFocus(true, in: lobbyFocus)
        }
    }

    /// Question language (Trivia/KBC) and bot seat-fillers. Focusable with
    /// the Siri Remote, so the host can set these up without a phone.
    @ViewBuilder
    private var lobbyOptions: some View {
        if (room.usesContentPack ?? false) || (room.botsAllowed ?? false) {
            HStack(spacing: 16) {
                if room.usesContentPack ?? false {
                    // One button that cycles English -> Telugu -> Hindi: three
                    // side by side do not fit this column at tvOS sizes.
                    let current = ContentPack(rawValue: room.contentPack ?? "en") ?? .en
                    Button {
                        vm.setContentPack(current.next)
                    } label: {
                        Label("Questions: \(current.label)", systemImage: "character.bubble.fill")
                    }
                    .buttonStyle(ShellGlassButtonStyle(tint: ShellTheme.cyan, fontSize: 24))
                }
                if room.botsAllowed ?? false {
                    Button {
                        vm.addBot()
                    } label: {
                        Label("Add Bot", systemImage: "cpu")
                    }
                    .buttonStyle(ShellGlassButtonStyle(tint: ShellTheme.orange, fontSize: 24))
                    .disabled(!canAddBot)
                    if let bot = room.players.last(where: { $0.isBot }) {
                        Button {
                            vm.removeBot(bot.id)
                        } label: {
                            Label("Remove Bot", systemImage: "minus.circle")
                        }
                        .buttonStyle(ShellGlassButtonStyle(tint: ShellTheme.pink, fontSize: 24))
                    }
                }
            }
        }
    }
}

// MARK: - Room code

/// The room code as one floating 3D tile per character, bobbing in a slow
/// wave. Read by VoiceOver as a single "Room code ABCD" element.
private struct RoomCodeTiles: View {
    let code: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            RoomCodeTileRow(code: code, time: context.date.timeIntervalSinceReferenceDate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Room code \(code)")
    }
}

private struct RoomCodeTileRow: View {
    let code: String
    let time: Double

    private var characters: [String] { code.map { String($0) } }

    /// Six tiles fit the card at full size; longer codes shrink to fit.
    private var tileWidth: CGFloat { characters.count > 6 ? 74 : 88 }

    private static let accents: [Color] = [
        ShellTheme.cyan, ShellTheme.violet, ShellTheme.pink,
        ShellTheme.blue, ShellTheme.mint, ShellTheme.gold
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                RoomCodeTile(character: character,
                             accent: accent(at: index),
                             width: tileWidth)
                    .offset(y: CGFloat(sin(phase(at: index))) * 7)
                    .rotation3DEffect(.degrees(sin(phase(at: index)) * 10),
                                      axis: (x: 1, y: 0, z: 0),
                                      perspective: 0.5)
            }
        }
    }

    private func phase(at index: Int) -> Double {
        time.truncatingRemainder(dividingBy: 10_000) * 2.0 + Double(index) * 0.7
    }

    private func accent(at index: Int) -> Color {
        let palette: [Color] = Self.accents
        return palette[index % palette.count]
    }
}

private struct RoomCodeTile: View {
    let character: String
    let accent: Color
    let width: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: width * 0.22, style: .continuous)
    }

    var body: some View {
        ZStack {
            // Thickness.
            shape
                .fill(accent)
                .overlay { shape.fill(Color.black.opacity(0.55)) }
                .offset(y: 8)
            shape.fill(Color(hex: "1B1440"))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.04)],
                                      startPoint: .top,
                                      endPoint: .bottom))
            shape.strokeBorder(LinearGradient(colors: [accent, accent.opacity(0.2)],
                                              startPoint: .top,
                                              endPoint: .bottom),
                               lineWidth: 2.5)
            Text(character)
                .font(ShellTheme.mono(width * 0.78, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [Color.white, accent],
                                                startPoint: .top,
                                                endPoint: .bottom))
                .shadow(color: accent.opacity(0.75), radius: 10)
        }
        .frame(width: width, height: width * 1.27)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 12)
    }
}

// MARK: - QR

/// Scannable QR for zero-typing join, served by /native/qr/<code>, on a white
/// card tilted slightly in 3D with a breathing glow behind it.
private struct LobbyQRCode: View {
    let code: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(RadialGradient(colors: [ShellTheme.cyan.opacity(0.55), ShellTheme.cyan.opacity(0)],
                                     center: .center,
                                     startRadius: 40,
                                     endRadius: 170))
                .frame(width: 300, height: 300)
                .phaseAnimator([false, true]) { content, phase in
                    content
                        .scaleEffect(phase ? 1.06 : 0.92)
                        .opacity(phase ? 1.0 : 0.45)
                } animation: { _ in
                    Animation.easeInOut(duration: 1.6)
                }

            AsyncImage(url: AppConstants.serverURL
                .appendingPathComponent("native/qr/\(code)")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().interpolation(.none).scaledToFit()
                default:
                    Image(systemName: "qrcode")
                        .font(.system(size: 80))
                        .foregroundColor(Color.black.opacity(0.35))
                }
            }
            .frame(width: 180, height: 180)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 14)
            .rotation3DEffect(.degrees(-8), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        .frame(width: 260, height: 260)
    }
}

// MARK: - Roster

/// Everyone in the room as avatar tokens, plus ghost tokens for open seats.
/// Up to 10 tokens at full size; bigger rooms (Tambola seats 20) switch to a
/// compact grid so the column never overflows the screen.
private struct LobbyRoster: View {
    let players: [Player]
    let maxPlayers: Int

    private var isCompact: Bool { players.count > 10 }
    private var tokenSize: CGFloat { isCompact ? 60 : 88 }
    private var cellWidth: CGFloat { isCompact ? 108 : 140 }
    private var columnCount: Int { isCompact ? 7 : 5 }

    /// Ghost seats fill the grid up to 10 tokens (or the game's max, if
    /// smaller); the exact count of open seats is in the line above.
    /// Clamped because a range whose lower bound exceeds its upper bound
    /// traps at runtime, and the player count is server-supplied.
    private var ghostCount: Int {
        let open: Int = max(0, maxPlayers - players.count)
        let space: Int = max(0, 10 - players.count)
        return min(open, space)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: 12), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: isCompact ? 10 : 22) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                LobbyPlayerCell(player: player, tokenSize: tokenSize, isCompact: isCompact)
                    .frame(width: cellWidth)
                    .shellHopIn(delay: Double(min(index, 6)) * 0.09, height: isCompact ? 36 : 56)
            }
            ForEach(0..<ghostCount, id: \.self) { _ in
                LobbyGhostCell(tokenSize: tokenSize, isCompact: isCompact)
                    .frame(width: cellWidth)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: players.count)
    }
}

private struct LobbyPlayerCell: View {
    let player: Player
    let tokenSize: CGFloat
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 8) {
            ShellAvatarToken(id: player.id,
                             name: player.name,
                             size: tokenSize,
                             isHost: player.isHost,
                             isBot: player.isBot,
                             isReady: player.isReady)
                .padding(.top, tokenSize * 0.2)

            Text(player.name)
                .font(.system(size: isCompact ? 18 : 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if player.isHost {
                LobbyTag(text: "HOST", color: ShellTheme.cyan)
            } else if player.isBot {
                LobbyTag(text: "BOT", color: ShellTheme.orange)
            }
        }
    }
}

private struct LobbyGhostCell: View {
    let tokenSize: CGFloat
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 8) {
            ShellGhostToken(size: tokenSize)
                .padding(.top, tokenSize * 0.2)
            Text("Open")
                .font(.system(size: isCompact ? 18 : 22, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.25))
        }
    }
}

private struct LobbyTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background { Capsule().fill(color.opacity(0.18)) }
    }
}

/// Three dots pulsing in a wave next to a label.
private struct WaitingPulse: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(ShellTheme.cyan)
                        .frame(width: 11, height: 11)
                        .phaseAnimator([false, true]) { content, phase in
                            content
                                .scaleEffect(phase ? 1.0 : 0.45)
                                .opacity(phase ? 1.0 : 0.3)
                        } animation: { phase in
                            Animation.easeInOut(duration: 0.6).delay(phase ? Double(index) * 0.18 : 0)
                        }
                }
            }
            Text(text)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(ShellTheme.cyan.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background { Capsule().fill(ShellTheme.cyan.opacity(0.1)) }
    }
}
