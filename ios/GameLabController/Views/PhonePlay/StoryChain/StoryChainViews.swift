import SwiftUI

// MARK: - Secret Story screens (StoryChainViewModel)

private enum SecretStoryStyle {
    static let colors: [Color] = [PhonePlayDesign.indigo, PhonePlayDesign.pink]
    static let reveal: [Color] = [PhonePlayDesign.purple, PhonePlayDesign.pink]
    static let go: [Color] = [PhonePlayDesign.green, PhonePlayDesign.cyan]
}

struct StoryChainRootView: View {
    @ObservedObject var game: StoryChainViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                SecretStorySetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .pass:
                SecretStoryPassView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .write:
                SecretStoryWriteView(game: game)
                    .transition(.opacity)
            case .gather:
                SecretStoryGatherView(game: game)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            case .reveal:
                SecretStoryRevealView(game: game, onExit: onExit)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct SecretStorySetupView: View {
    @ObservedObject var game: StoryChainViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Secret Story", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed.fill")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(SecretStoryStyle.colors))
                            .phonePlayIdle(degrees: 6, duration: 1.2)
                        Text("Secret Story")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("Everyone secretly writes one piece of a story without seeing the rest. Then the phone reads the whole thing aloud.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    PhonePlayHowToCard(steps: [
                        "Pass the phone. Each player answers one question alone, like \"Where did they meet?\"",
                        "Nobody sees what anyone else wrote.",
                        "When everyone is done, gather round: the phone reveals the story and reads it out.",
                    ], accent: PhonePlayDesign.pink)

                    PhonePlayNamesEditor(names: $game.names, range: game.playerRange,
                                         accent: PhonePlayDesign.pink)

                    Toggle(isOn: $game.readAloud) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read the story aloud")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("The phone narrates the finished story")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                        }
                    }
                    .tint(PhonePlayDesign.pink)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface))

                    Text("\(StoryChainDeck.templates.count) kinds of story: news reports, wedding speeches, Bollywood blockbusters and more")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .multilineTextAlignment(.center)

                    PhonePlayBigButton(title: "Start", symbol: "pencil.and.scribble",
                                       colors: SecretStoryStyle.colors, enabled: game.canStart) {
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

// MARK: - Pass the phone

private struct SecretStoryPassView: View {
    @ObservedObject var game: StoryChainViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: game.template.title, backTitle: "Setup", onBack: game.editPlayers)
            Spacer()
            VStack(spacing: 18) {
                SecretStoryProgress(filled: game.blank, total: game.template.blanks.count)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundStyle(PhonePlayDesign.gradient(SecretStoryStyle.colors))
                    .phonePlayIdle(dy: 3, duration: 1.0)
                Text("Pass the phone to")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                Text(game.writerName)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("No peeking, everyone else.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            .padding(.horizontal, 24)
            Spacer()
            PhonePlayBigButton(title: "I am \(game.writerName)", symbol: "eye.fill",
                               colors: SecretStoryStyle.colors) {
                game.showPrompt()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }
}

// MARK: - Write one blank

private struct SecretStoryWriteView: View {
    @ObservedObject var game: StoryChainViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: game.template.title, backTitle: "Setup", onBack: game.editPlayers)
            ScrollView {
                VStack(spacing: 20) {
                    SecretStoryProgress(filled: game.blank, total: game.template.blanks.count)
                        .padding(.top, 10)
                    Text(game.writerName.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(PhonePlayDesign.pink)
                    Text(game.prompt.prompt)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(game.prompt.example, text: $game.draft, axis: .vertical)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1...3)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { game.submit() }
                        .onChange(of: game.draft) { _, value in
                            if value.count > StoryChainViewModel.maxAnswerLength {
                                game.draft = String(value.prefix(StoryChainViewModel.maxAnswerLength))
                            }
                        }

                    PhonePlayBigButton(title: "Done, hide it", symbol: "checkmark",
                                       colors: SecretStoryStyle.go,
                                       enabled: !game.draft.trimmingCharacters(in: .whitespaces).isEmpty) {
                        game.submit()
                    }
                    PhonePlayGhostButton(title: "Stuck? Surprise me", symbol: "wand.and.stars") {
                        game.surpriseMe()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Gather round

private struct SecretStoryGatherView: View {
    @ObservedObject var game: StoryChainViewModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient(SecretStoryStyle.reveal))
                .phonePlayIdle(dy: 4, scale: 0.05, duration: 1.0)
            Text("Everyone, gather round!")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("The story is written. Nobody knows how it goes. Yet.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
            Spacer()
            PhonePlayBigButton(title: "Reveal the story", symbol: "book.fill",
                               colors: SecretStoryStyle.reveal) {
                game.reveal()
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 22)
    }
}

// MARK: - The story

private struct SecretStoryRevealView: View {
    @ObservedObject var game: StoryChainViewModel
    let onExit: () -> Void
    @State private var showWriters = false

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Story time", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 18) {
                    Label(game.template.title, systemImage: game.template.symbol)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(PhonePlayDesign.gradient(SecretStoryStyle.reveal))
                        .padding(.top, 6)

                    Text(game.story)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface))

                    if showWriters {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(game.answers.enumerated()), id: \.offset) { pair in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.template.blanks[pair.offset].prompt)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(PhonePlayDesign.text3)
                                    Text("\(game.writers[pair.offset]): \(pair.element)")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                            .fill(Color.white.opacity(0.06)))
                        .transition(.opacity)
                    } else {
                        PhonePlayGhostButton(title: "Who wrote what?", symbol: "person.crop.circle.badge.questionmark") {
                            withAnimation(PhonePlayDesign.smooth) { showWriters = true }
                        }
                    }

                    if game.readAloud {
                        PhonePlayGhostButton(title: "Read it again", symbol: "speaker.wave.2.fill") {
                            game.readStory()
                        }
                    }

                    PhonePlayBigButton(title: "Next story", symbol: "arrow.right",
                                       colors: SecretStoryStyle.colors) {
                        showWriters = false
                        game.nextStory()
                    }
                    PhonePlayGhostButton(title: "Change players", symbol: "person.2.fill") {
                        game.editPlayers()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }
}

/// Dots for the blanks: filled ones lit.
private struct SecretStoryProgress: View {
    let filled: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? PhonePlayDesign.pink : Color.white.opacity(0.15))
                    .frame(width: index == filled ? 26 : 12, height: 8)
            }
        }
        .animation(PhonePlayDesign.smooth, value: filled)
    }
}
