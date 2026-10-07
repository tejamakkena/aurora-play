import SwiftUI

// MARK: - Mafia screens

private enum MafiaStyle {
    static let night: [Color] = [Color(hex: "120B2E"), Color(hex: "2A1250")]
    static let morning: [Color] = [Color(hex: "FF9A5A"), Color(hex: "FF5E7E")]
    static let accent: Color = PhonePlayDesign.red
    static let colors: [Color] = [PhonePlayDesign.red, PhonePlayDesign.purple]
}

struct MafiaRootView: View {
    @ObservedObject var game: MafiaViewModel
    let onExit: () -> Void

    @State private var confirmEnd: Bool = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                PhonePlayTopBar(title: "Mafia",
                                backTitle: game.stage == .setup ? "Games" : "End",
                                onBack: back,
                                trailing: AnyView(voiceToggle))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
        .confirmationDialog("End this game?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End game", role: .destructive) { game.editPlayers() }
            Button("Keep playing", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var background: some View {
        switch game.stage {
        case .night, .handoff:
            PhonePlayDesign.gradient(MafiaStyle.night)
        case .morning:
            PhonePlayDesign.gradient([Color(hex: "2B1530"), Color(hex: "5A2338")])
        default:
            PhonePlayDesign.bg
        }
    }

    @ViewBuilder
    private var content: some View {
        switch game.stage {
        case .setup:
            MafiaSetupView(game: game)
                .transition(.opacity)
        case .reveal:
            MafiaRevealView(game: game)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        case .handoff:
            MafiaHandoffView(game: game)
                .transition(.opacity)
        case .night:
            MafiaNightView(game: game)
                .transition(.opacity)
        case .morning:
            MafiaMorningView(game: game)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        case .day:
            MafiaDayView(game: game)
                .transition(.opacity)
        case .gameOver:
            MafiaGameOverView(game: game)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var voiceToggle: some View {
        Button {
            PhonePlayHaptics.tap()
            game.setNarration(!game.narrationOn)
        } label: {
            Image(systemName: game.narrationOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(PhonePlayPressStyle())
    }

    private func back() {
        if game.stage == .setup {
            onExit()
        } else {
            confirmEnd = true
        }
    }
}

// MARK: - Setup

private struct MafiaSetupView: View {
    @ObservedObject var game: MafiaViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "theatermasks.fill")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(PhonePlayDesign.gradient(MafiaStyle.colors))
                        .phonePlayIdle(degrees: 8, duration: 1.2)
                    Text("Mafia")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("One person narrates and does not play. The phone deals secret roles, then talks the town through each night.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 6)

                PhonePlayNamesEditor(names: $game.names, range: game.playerRange,
                                     accent: MafiaStyle.accent)

                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(MafiaStyle.accent)
                    Text(game.roleSummary)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .fill(MafiaStyle.accent.opacity(0.12)))

                PhonePlayBigButton(title: "Deal the roles", symbol: "rectangle.stack.fill",
                                   colors: MafiaStyle.colors, enabled: game.canStart) {
                    game.start()
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Role reveal

private struct MafiaRevealView: View {
    @ObservedObject var game: MafiaViewModel

    var body: some View {
        VStack(spacing: 0) {
            if game.players.indices.contains(game.revealIndex) {
                let player: MafiaPlayer = game.players[game.revealIndex]
                PassAndRevealView(name: player.name,
                                  index: game.revealIndex,
                                  total: game.players.count,
                                  accent: MafiaStyle.accent,
                                  onDone: game.nextReveal) {
                    MafiaRoleCard(role: player.role, partners: partners(for: player))
                }
                .id(game.revealIndex)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            Spacer(minLength: 16)
        }
        .animation(PhonePlayDesign.smooth, value: game.revealIndex)
    }

    private func partners(for player: MafiaPlayer) -> [String] {
        guard player.role.isMafia else { return [] }
        return game.players
            .filter { $0.role.isMafia && $0.id != player.id }
            .map { $0.name }
    }
}

private struct MafiaRoleCard: View {
    let role: MafiaRole
    let partners: [String]

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: role.symbol)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundColor(role.color)
            Text("You are")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
            Text(role.title.uppercased())
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundColor(role.color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(role.blurb)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
            if !partners.isEmpty {
                Text("Your partners: \(partners.joined(separator: ", "))")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Hand-off to the narrator

private struct MafiaHandoffView: View {
    @ObservedObject var game: MafiaViewModel

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow, .white]))
                .shadow(color: PhonePlayDesign.yellow.opacity(0.4), radius: 22)
                .phonePlayIdle(scale: 0.05, duration: 1.6)
            VStack(spacing: 8) {
                Text("Roles are dealt")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Give the phone to the narrator. Everyone else, get ready to close your eyes.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            PhonePlayBigButton(title: "Start the night", symbol: "moon.fill",
                               colors: [PhonePlayDesign.indigo, PhonePlayDesign.purple]) {
                game.startNight()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

// MARK: - Night (narrator taps through)

private struct MafiaNightView: View {
    @ObservedObject var game: MafiaViewModel

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    stepDots
                        .padding(.top, 4)

                    Text("NIGHT \(game.round)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.5))

                    Image(systemName: game.currentStep.symbol)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(stepColor)
                        .symbolEffect(.bounce, value: game.stepIndex)
                        .frame(height: 70)

                    Text(game.currentStep.title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .id(game.stepIndex)
                        .transition(.push(from: .trailing))

                    scriptCard

                    pickSection
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }
            controls
        }
        .animation(PhonePlayDesign.smooth, value: game.stepIndex)
        .animation(PhonePlayDesign.pop, value: game.currentPick)
    }

    private var stepColor: Color {
        game.currentStep.role?.color ?? PhonePlayDesign.yellow
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<MafiaNightStep.order.count, id: \.self) { i in
                Capsule()
                    .fill(i <= game.stepIndex ? Color.white : Color.white.opacity(0.18))
                    .frame(width: i == game.stepIndex ? 22 : 8, height: 8)
            }
        }
    }

    private var scriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read aloud", systemImage: "quote.opening")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
            Text(game.currentStep.line)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
            .fill(Color.white.opacity(0.07)))
    }

    @ViewBuilder
    private var pickSection: some View {
        if game.currentStep.needsPick {
            if game.stepRoleAlive {
                VStack(spacing: 12) {
                    PhonePlaySectionLabel(text: pickPrompt)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(game.pickChoices) { player in
                            MafiaPickChip(name: player.name,
                                          selected: game.currentPick == player.id,
                                          tint: stepColor) {
                                game.choose(player.id)
                            }
                        }
                    }
                    if game.currentStep == .detectiveWake, let checked = game.detectiveCheck,
                       game.players.indices.contains(checked) {
                        detectiveAnswer(game.players[checked])
                    }
                }
            } else {
                Text("The \(game.currentStep.role?.title ?? "player") is out of the game. Pause for a few seconds so nobody can tell, then continue.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(Color.white.opacity(0.05)))
            }
        }
    }

    private var pickPrompt: String {
        switch game.currentStep {
        case .mafiaWake:     return "Tap who the Mafia pointed at"
        case .doctorWake:    return "Tap who the Doctor saves"
        case .detectiveWake: return "Tap who the Detective suspects"
        default:             return ""
        }
    }

    private func detectiveAnswer(_ player: MafiaPlayer) -> some View {
        let guilty: Bool = player.role.isMafia
        return HStack(spacing: 12) {
            Image(systemName: guilty ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 2) {
                Text(guilty ? "\(player.name) IS Mafia" : "\(player.name) is not Mafia")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                Text(guilty ? "Give the Detective a silent thumbs up" : "Give the Detective a silent thumbs down")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
            .fill(guilty ? PhonePlayDesign.red.opacity(0.85) : PhonePlayDesign.green.opacity(0.7)))
        .transition(.scale.combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                PhonePlayHaptics.tap()
                game.repeatLine()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(PhonePlayPressStyle())
            PhonePlayBigButton(title: game.isLastStep ? "Morning" : "Next",
                               symbol: game.isLastStep ? "sunrise.fill" : "arrow.right",
                               colors: [PhonePlayDesign.indigo, PhonePlayDesign.purple],
                               enabled: game.canAdvance) {
                game.advance()
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }
}

private struct MafiaPickChip: View {
    let name: String
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(selected ? .black : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(selected ? tint : Color.white.opacity(0.08))
                )
                .scaleEffect(selected ? 1.05 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

// MARK: - Morning

private struct MafiaMorningView: View {
    @ObservedObject var game: MafiaViewModel

    @State private var risen: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sunrise.fill")
                .font(.system(size: 84, weight: .bold, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient(MafiaStyle.morning))
                .offset(y: risen ? 0 : 60)
                .opacity(risen ? 1 : 0)
            if let victim = game.nightVictim {
                VStack(spacing: 8) {
                    Text("Last night")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                    Text(game.name(victim))
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("was eliminated")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.red)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Nobody was eliminated")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("The Doctor saved the day")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.green)
                }
            }
            Spacer()
            PhonePlayBigButton(title: game.winner == nil ? "Start the day" : "See who won",
                               symbol: game.winner == nil ? "sun.max.fill" : "flag.checkered",
                               colors: MafiaStyle.morning) {
                game.startDay()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.75)) {
                risen = true
            }
        }
    }
}

// MARK: - Day

private struct MafiaDayView: View {
    @ObservedObject var game: MafiaViewModel

    @State private var selected: Int? = nil

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("DAY \(game.round)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(PhonePlayDesign.text3)
                    Text(game.dayVoteDone ? "The town has voted" : "Who is in the Mafia?")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("\(game.alivePlayers.count) players left")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }
                .padding(.top, 6)

                if game.dayVoteDone {
                    voteResult
                } else {
                    voteSection
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .animation(PhonePlayDesign.pop, value: selected)
        .animation(PhonePlayDesign.smooth, value: game.dayVoteDone)
    }

    private var voteSection: some View {
        VStack(spacing: 14) {
            PhonePlaySectionLabel(text: "Tap the player the town votes out")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(game.alivePlayers) { player in
                    MafiaPickChip(name: player.name, selected: selected == player.id,
                                  tint: PhonePlayDesign.orange) {
                        PhonePlayHaptics.tap()
                        selected = player.id
                    }
                }
            }
            PhonePlayBigButton(title: selected == nil ? "Pick a player" : "Eliminate \(game.name(selected))",
                               symbol: "hand.raised.fill",
                               colors: [PhonePlayDesign.orange, PhonePlayDesign.red],
                               enabled: selected != nil) {
                game.eliminate(selected)
            }
            PhonePlayGhostButton(title: "No elimination today", symbol: "hand.wave.fill") {
                game.eliminate(nil)
            }
        }
    }

    private var voteResult: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                if let out = game.dayEliminated {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.orange)
                    Text("\(game.name(out)) is out")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Their role stays secret until the end.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                } else {
                    Image(systemName: "hand.raised.slash.fill")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                    Text("Nobody was voted out")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface))
            .transition(.scale(scale: 0.9).combined(with: .opacity))

            PhonePlayBigButton(title: game.winner == nil ? "Night falls" : "See who won",
                               symbol: game.winner == nil ? "moon.fill" : "flag.checkered",
                               colors: [PhonePlayDesign.indigo, PhonePlayDesign.purple]) {
                selected = nil
                game.continueAfterVote()
            }
        }
    }
}

// MARK: - Game over

private struct MafiaGameOverView: View {
    @ObservedObject var game: MafiaViewModel

    @State private var shown: Int = 0

    private var townWon: Bool { game.winner == .town }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: townWon ? "house.fill" : "theatermasks.fill")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(townWon ? PhonePlayDesign.yellow : PhonePlayDesign.red)
                        .symbolEffect(.bounce, value: shown)
                    Text(townWon ? "The town wins!" : "The Mafia win!")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("Here is who everyone really was")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }
                .padding(.top, 6)

                VStack(spacing: 8) {
                    ForEach(game.players) { player in
                        MafiaRoleRow(player: player)
                            .opacity(player.id < shown ? 1 : 0)
                            .offset(x: player.id < shown ? 0 : 40)
                    }
                }

                PhonePlayBigButton(title: "New game", symbol: "arrow.clockwise",
                                   colors: MafiaStyle.colors) {
                    game.newGame()
                }
                PhonePlayGhostButton(title: "Edit players", symbol: "person.2.fill") {
                    game.editPlayers()
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
        .onAppear(perform: revealRows)
    }

    private func revealRows() {
        let count: Int = game.players.count
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            for i in 0..<count {
                withAnimation(PhonePlayDesign.pop) {
                    shown = i + 1
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }
}

private struct MafiaRoleRow: View {
    let player: MafiaPlayer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: player.role.symbol)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 36, height: 36)
                .background(Circle().fill(player.role.color))
            Text(player.name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(player.alive ? .white : PhonePlayDesign.text3)
                .strikethrough(!player.alive, color: PhonePlayDesign.text3)
            Spacer()
            Text(player.role.title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(player.role.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
            .fill(PhonePlayDesign.surface))
    }
}
