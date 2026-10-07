import SwiftUI

struct WaitingView: View {
    let room: Room
    let onReady: () -> Void
    let onLeave: () -> Void

    @State private var isReady = false
    @State private var appeared = false
    @EnvironmentObject private var vm: ControllerRootViewModel

    private static let tvColors: [Color] = [PhonePlayDesign.cyan, PhonePlayDesign.indigo]

    var body: some View {
        VStack(spacing: 0) {
            // Once you've joined a room there was no way back to the join
            // screen at all -- reported directly. A wrong code/game or a
            // change of mind had nowhere to go.
            PhonePlayTopBar(title: "", backTitle: "Leave", onBack: onLeave,
                            trailing: AnyView(ProfileChipButton()))

            // Scrolls so the host's Game Night / quiz cards never push the
            // Ready button off small screens.
            ScrollView {
                VStack(spacing: 20) {
                    gameBadge
                    roomCodeCard

                    // Game Night scoreboard (everyone sees it while one runs)
                    if let night = room.night {
                        GameNightStatusCard(room: room, night: night, isHost: vm.isHost,
                                            myID: vm.playerID)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }

                    // Teams (everyone sees them; tap to switch)
                    if let teams = room.teams {
                        PhoneTeamsCard(room: room, teams: teams, myID: vm.playerID)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }

                    playersList

                    if vm.isHost {
                        PhonePlaySectionLabel(text: "Host controls")
                            .padding(.top, 4)
                        HostLobbyControls(room: room)
                    }

                    // Private info note
                    if room.gameID.hasPrivateInfo {
                        HStack(spacing: 10) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("Your private info will appear here when the game starts")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(PhonePlayDesign.cyan.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(PhonePlayDesign.smooth, value: room.night)
                .animation(PhonePlayDesign.smooth, value: room.teams)
                .animation(PhonePlayDesign.smooth, value: room.players.count)
            }

            readyButton
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 28)
        }
        .background(PhonePlayDesign.bg.ignoresSafeArea())
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { appeared = true }
        }
    }

    // MARK: Pieces

    private var gameBadge: some View {
        VStack(spacing: 12) {
            Image(systemName: room.gameID.sfSymbol)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 96, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient(Self.tvColors))
                )
                .shadow(color: PhonePlayDesign.cyan.opacity(0.4), radius: 18, y: 8)
                .phonePlayIdle(dy: 3, degrees: 3, duration: 1.5)
            Text(room.gameID.displayName)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Waiting for everyone to get ready")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .padding(.top, 6)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
    }

    private var roomCodeCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                PhonePlaySectionLabel(text: "Room")
                Text(room.code)
                    .font(.system(size: 30, weight: .black, design: .monospaced))
                    .foregroundColor(PhonePlayDesign.cyan)
                    .tracking(2)
            }
            Spacer()
            InviteShareButton(room: room)
        }
        .phonePlaySurfaceCard(tint: PhonePlayDesign.cyan)
    }

    private var playersList: some View {
        VStack(spacing: 10) {
            HStack {
                PhonePlaySectionLabel(text: "Players")
                Text("\(room.players.filter(\.isReady).count) / \(room.players.count) ready")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.green)
                    .fixedSize()
            }
            ForEach(room.players) { player in
                playerRow(player)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .scale(scale: 0.8).combined(with: .opacity)))
            }
        }
    }

    private func playerRow(_ player: Player) -> some View {
        let me = player.id == vm.playerID
        return HStack(spacing: 12) {
            Text(String(player.name.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(player.isReady ? .black : .white)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(player.isReady
                                  ? PhonePlayDesign.gradient([PhonePlayDesign.green, PhonePlayDesign.cyan])
                                  : PhonePlayDesign.gradient([PhonePlayDesign.surface2, PhonePlayDesign.surface2]))
                )

            Text(player.name)
                .font(.system(size: 17, weight: me ? .heavy : .bold, design: .rounded))
                .foregroundColor(me ? PhonePlayDesign.cyan : .white)
                .lineLimit(1)

            if player.isHost { roleTag("HOST", PhonePlayDesign.cyan) }
            if player.isBot { roleTag("BOT", PhonePlayDesign.orange) }

            Spacer()

            if player.isBot && vm.isHost {
                Button {
                    PhonePlayHaptics.tap()
                    vm.removeBot(player.id)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundColor(PhonePlayDesign.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(player.name)")
            }

            Image(systemName: player.isReady ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(player.isReady ? PhonePlayDesign.green : .white.opacity(0.2))
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(me ? PhonePlayDesign.cyan.opacity(0.1) : PhonePlayDesign.surface)
        )
    }

    private func roleTag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundColor(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }

    @ViewBuilder
    private var readyButton: some View {
        if isReady {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .symbolEffect(.bounce, value: isReady)
                Text("Ready! Waiting for the TV")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundColor(PhonePlayDesign.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.green.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(PhonePlayDesign.green.opacity(0.45), lineWidth: 1.5)
            )
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            PhonePlayBigButton(title: "I'm Ready", symbol: "hand.thumbsup.fill",
                               colors: [PhonePlayDesign.green, PhonePlayDesign.cyan]) {
                PhonePlayHaptics.success()
                withAnimation(PhonePlayDesign.pop) { isReady = true }
                onReady()
            }
            .transition(.opacity)
        }
    }
}

/// Game Night, make-your-own quiz, bot seat-fillers and question language
/// -- shown to the host only.
private struct HostLobbyControls: View {
    let room: Room
    @EnvironmentObject private var vm: ControllerRootViewModel

    private var canAddBot: Bool {
        (room.botsAllowed ?? false) && room.players.count < room.gameID.maxPlayers
    }

    var body: some View {
        VStack(spacing: 12) {
            // Game Night planner (the running night shows in WaitingView
            // for everyone) and make-your-own quiz: Views/OneStop/.
            if room.night == nil {
                GameNightPlannerCard(room: room)
            }
            QuizMakerCard(room: room)
            HostTeamsControl(room: room)

            if room.usesContentPack ?? false {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Question language", systemImage: "character.bubble.fill")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    HStack(spacing: 8) {
                        ForEach(ContentPack.allCases) { pack in
                            PhonePlayChip(title: pack.label,
                                          selected: (room.contentPack ?? "en") == pack.rawValue,
                                          colors: [PhonePlayDesign.cyan, PhonePlayDesign.blue]) {
                                vm.setContentPack(pack)
                            }
                        }
                    }
                }
                .phonePlaySurfaceCard()
            }
            if room.botsAllowed ?? false {
                Button {
                    PhonePlayHaptics.tap()
                    vm.addBot()
                } label: {
                    Label("Add a bot player", systemImage: "cpu")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(canAddBot ? PhonePlayDesign.orange : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .fill(PhonePlayDesign.orange.opacity(canAddBot ? 0.1 : 0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .strokeBorder(PhonePlayDesign.orange.opacity(canAddBot ? 0.5 : 0.15), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PhonePlayPressStyle())
                .disabled(!canAddBot)
            }
        }
    }
}
