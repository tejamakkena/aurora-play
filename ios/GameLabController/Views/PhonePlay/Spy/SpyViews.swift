import SwiftUI

// MARK: - Spy screens

private enum SpyStyle {
    static let accent: Color = PhonePlayDesign.indigo
    static let accent2: Color = PhonePlayDesign.cyan
    static var colors: [Color] { [accent, accent2] }
}

struct SpyRootView: View {
    @ObservedObject var game: SpyViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                SpySetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .reveal:
                SpyRevealView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .discuss:
                SpyDiscussView(game: game)
                    .transition(.opacity)
            case .vote:
                SpyVoteView(game: game)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .result:
                SpyResultView(game: game)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct SpySetupView: View {
    @ObservedObject var game: SpyViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Spy", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "binoculars.fill")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(SpyStyle.colors))
                            .symbolEffect(.pulse)
                        Text("Who is the Spy?")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Everyone sees the same place except one player, the spy. Ask each other questions to find them. The spy wins by blending in or guessing the place.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    PhonePlayNamesEditor(names: $game.names, range: game.playerRange,
                                         accent: SpyStyle.accent2)

                    PhonePlayHowToCard(steps: [
                        "Pass the phone round. Each player taps to see their card, then hides it before handing it on.",
                        "Everyone sees the same place, except the Spy, who is only told they are the Spy.",
                        "Take turns asking one other player a question about the place, like \"Would I need a ticket here?\" or \"Is it noisy?\". Answer truthfully, but do not give the place away.",
                        "The Spy listens for clues and answers vaguely to blend in.",
                        "The Spy can stop the game at any time: tap \"I'm the Spy\" and name the place. Right wins for the Spy, wrong wins for the town.",
                        "When the timer ends, everyone points at a suspect. A caught Spy still gets one last guess at the place.",
                    ], accent: SpyStyle.accent2)

                    VStack(spacing: 10) {
                        PhonePlaySectionLabel(text: "Discussion time")
                        HStack(spacing: 10) {
                            ForEach(game.minuteChoices, id: \.self) { minutes in
                                SpyChoiceChip(title: "\(minutes) min",
                                              selected: game.discussMinutes == minutes) {
                                    game.discussMinutes = minutes
                                }
                            }
                        }
                    }

                    PhonePlayBigButton(title: "Deal the cards", symbol: "rectangle.stack.fill",
                                       colors: SpyStyle.colors, enabled: game.canStart) {
                        game.start()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct SpyChoiceChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(selected ? .white : PhonePlayDesign.text2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(selected ? PhonePlayDesign.gradient(SpyStyle.colors)
                                       : PhonePlayDesign.gradient([PhonePlayDesign.surface,
                                                                   PhonePlayDesign.surface]))
                )
        }
        .buttonStyle(PhonePlayPressStyle())
        .animation(PhonePlayDesign.pop, value: selected)
    }
}

// MARK: - Reveal

private struct SpyRevealView: View {
    @ObservedObject var game: SpyViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Spy", backTitle: "Setup", onBack: game.editPlayers)
            if game.names.indices.contains(game.revealIndex) {
                PassAndRevealView(name: game.names[game.revealIndex],
                                  index: game.revealIndex,
                                  total: game.names.count,
                                  accent: SpyStyle.accent,
                                  onDone: game.nextReveal) {
                    SpySecretCard(isSpy: game.revealIndex == game.spyIndex,
                                  location: game.location)
                }
                .id(game.revealIndex)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            Spacer(minLength: 16)
        }
        .animation(PhonePlayDesign.smooth, value: game.revealIndex)
    }
}

private struct SpySecretCard: View {
    let isSpy: Bool
    let location: String

    var body: some View {
        VStack(spacing: 14) {
            if isSpy {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.red)
                Text("You are the")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                Text("SPY")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(PhonePlayDesign.red)
                Text("Blend in and work out the location")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundColor(SpyStyle.accent2)
                Text("LOCATION")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(PhonePlayDesign.text3)
                Text(location)
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text("Find the spy without giving the place away")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Discuss

private struct SpyDiscussView: View {
    @ObservedObject var game: SpyViewModel

    @State private var showLocations: Bool = false
    @State private var showGuess: Bool = false
    @State private var pendingGuess: String? = nil

    private var fraction: Double {
        let total = Double(max(1, game.discussMinutes * 60))
        return Double(game.secondsLeft) / total
    }

    private var ringColor: Color {
        game.secondsLeft <= 30 ? PhonePlayDesign.red : SpyStyle.accent2
    }

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Spy", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 24) {
                    Text("Ask questions")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 6)

                    if game.names.indices.contains(game.firstAsker) {
                        Text("\(game.names[game.firstAsker]) asks first")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(SpyStyle.accent2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(SpyStyle.accent2.opacity(0.14)))
                    }

                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 18)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: game.secondsLeft)
                        VStack(spacing: 4) {
                            Text(PhonePlayTime.clock(game.secondsLeft))
                                .font(.system(size: 60, weight: .black, design: .rounded).monospacedDigit())
                                .foregroundColor(.white)
                                .contentTransition(.numericText(countsDown: true))
                                .animation(.easeOut(duration: 0.25), value: game.secondsLeft)
                            Text(game.paused ? "Paused" : "left to talk")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text2)
                        }
                    }
                    .frame(width: 240, height: 240)

                    HStack(spacing: 12) {
                        PhonePlayGhostButton(title: game.paused ? "Resume" : "Pause",
                                             symbol: game.paused ? "play.fill" : "pause.fill") {
                            game.togglePause()
                        }
                        PhonePlayGhostButton(title: "Locations", symbol: "list.bullet") {
                            showLocations = true
                        }
                    }

                    PhonePlayGhostButton(title: "I'm the Spy: guess the place", symbol: "binoculars.fill") {
                        showGuess = true
                    }

                    PhonePlayBigButton(title: "Vote now", symbol: "hand.point.up.left.fill",
                                       colors: [PhonePlayDesign.red, PhonePlayDesign.orange]) {
                        game.goToVote()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showLocations) {
            SpyLocationsSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showGuess) {
            SpyLocationsSheet(title: "Spy: where are we?", onPick: { place in
                showGuess = false
                pendingGuess = place
            })
            .presentationDetents([.large])
        }
        .confirmationDialog(pendingGuess.map { "Guess \($0)?" } ?? "",
                            isPresented: Binding(get: { pendingGuess != nil },
                                                 set: { if !$0 { pendingGuess = nil } }),
                            titleVisibility: .visible) {
            Button("Yes, that's the place") {
                if let place = pendingGuess { game.spyGuesses(place) }
                pendingGuess = nil
            }
            Button("Cancel", role: .cancel) { pendingGuess = nil }
        } message: {
            Text("Only the Spy should do this. If it is wrong, the town wins.")
        }
    }
}

private struct SpyLocationsSheet: View {
    var title: String = "Possible locations"
    /// When set, tapping a place picks it (the spy's guess).
    var onPick: ((String) -> Void)? = nil

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 140), spacing: 10)]

    var body: some View {
        ZStack {
            PhonePlayDesign.surface.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Text(title)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(SpyLocations.all, id: \.self) { place in
                            Button {
                                onPick?(place)
                            } label: {
                                Text(place)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                        .fill(PhonePlayDesign.surface2))
                            }
                            .buttonStyle(.plain)
                            .disabled(onPick == nil)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Vote

private struct SpyVoteView: View {
    @ObservedObject var game: SpyViewModel

    @State private var pending: Int? = nil

    private let columns: [GridItem] = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Spy", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("Who is the spy?")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Agree as a group, then tap your suspect.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                    }
                    .padding(.top, 6)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(game.names.enumerated()), id: \.offset) { pair in
                            SpySuspectButton(name: pair.element, selected: pending == pair.offset) {
                                pending = pair.offset
                            }
                        }
                    }

                    PhonePlayBigButton(title: pendingTitle, symbol: "magnifyingglass",
                                       colors: [PhonePlayDesign.red, PhonePlayDesign.orange],
                                       enabled: pending != nil) {
                        if let choice = pending { game.accuse(choice) }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }

    private var pendingTitle: String {
        guard let choice = pending, game.names.indices.contains(choice) else { return "Pick a suspect" }
        return "Accuse \(game.names[choice])"
    }
}

private struct SpySuspectButton: View {
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(selected ? PhonePlayDesign.red : PhonePlayDesign.surface2))
                Text(name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .strokeBorder(selected ? PhonePlayDesign.red : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .animation(PhonePlayDesign.pop, value: selected)
    }
}

// MARK: - Result

private struct SpyResultView: View {
    @ObservedObject var game: SpyViewModel

    @State private var flipped: Bool = false
    @State private var showPlace: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Spy", backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 22) {
                    Text(headline)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(headlineColor)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    if let guess = game.guess {
                        Text(guessLine(guess))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    } else if !game.spyCaught {
                        Text("You accused \(game.accusedName), who knew the place.")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }

                    PhonePlayFlip(flipped: flipped, front: cardFront, back: cardBack, duration: 0.7)
                        .frame(height: 230)

                    if game.spyCaught && game.guess == nil {
                        Text("Last chance: \(game.spyName), name the location to steal the win.")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                            .multilineTextAlignment(.center)
                    }

                    if showPlace {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(SpyStyle.accent2)
                            Text("The location was \(game.location)")
                                .font(.system(size: 19, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(PhonePlayDesign.surface))
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        PhonePlayGhostButton(title: "Reveal the location", symbol: "eye.fill") {
                            showPlace = true
                        }
                    }

                    PhonePlayBigButton(title: "Play again", symbol: "arrow.clockwise",
                                       colors: SpyStyle.colors) {
                        game.playAgain()
                    }
                    PhonePlayGhostButton(title: "Edit players", symbol: "person.2.fill") {
                        game.editPlayers()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .animation(PhonePlayDesign.pop, value: showPlace)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                flipped = true
                PhonePlayHaptics.thump()
            }
        }
    }

    private var headline: String {
        switch game.guess {
        case .right?: return "The spy found the place!"
        case .wrong?: return "Wrong place! Town wins."
        case nil:     return game.spyCaught ? "Spy caught!" : "The spy got away!"
        }
    }

    private var headlineColor: Color {
        switch game.guess {
        case .right?: return PhonePlayDesign.red
        case .wrong?: return PhonePlayDesign.green
        case nil:     return game.spyCaught ? PhonePlayDesign.green : PhonePlayDesign.red
        }
    }

    private func guessLine(_ guess: SpyViewModel.Guess) -> String {
        switch guess {
        case .right(let place): return "\(game.spyName) said \(place), and that was right. The spy wins."
        case .wrong(let place): return "\(game.spyName) guessed \(place), but it was \(game.location)."
        }
    }

    private var cardFront: some View {
        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
            .fill(PhonePlayDesign.gradient(SpyStyle.colors))
            .overlay(
                Image(systemName: "questionmark")
                    .font(.system(size: 80, weight: .black, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            )
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
            .fill(PhonePlayDesign.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(PhonePlayDesign.red.opacity(0.8), lineWidth: 2)
            )
            .overlay(
                VStack(spacing: 8) {
                    Text("THE SPY WAS")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(PhonePlayDesign.text3)
                    Text(game.spyName)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.red)
                }
                .padding(20)
            )
    }
}
