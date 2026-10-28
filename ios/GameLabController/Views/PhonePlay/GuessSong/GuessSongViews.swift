import SwiftUI

// MARK: - Guess the Song screens

private enum GuessSongStyle {
    static let colors: [Color] = [PhonePlayDesign.pink, PhonePlayDesign.orange]
    static let teamColors: [[Color]] = [
        [PhonePlayDesign.orange, PhonePlayDesign.yellow],
        [PhonePlayDesign.cyan, PhonePlayDesign.blue],
    ]

    static func colors(team: Int) -> [Color] {
        teamColors[team % teamColors.count]
    }
}

struct GuessSongRootView: View {
    @ObservedObject var game: GuessSongViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            switch game.stage {
            case .setup:
                GuessSongSetupView(game: game, onExit: onExit)
                    .transition(.opacity)
            case .ready:
                GuessSongReadyView(game: game)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .singing:
                GuessSongSingingView(game: game)
                    .transition(.opacity)
            case .turnOver:
                GuessSongTurnOverView(game: game)
                    .transition(.opacity)
            case .final:
                GuessSongFinalView(game: game, onExit: onExit)
                    .transition(.opacity)
            }
        }
        .animation(PhonePlayDesign.smooth, value: game.stage)
    }
}

// MARK: - Setup

private struct GuessSongSetupView: View {
    @ObservedObject var game: GuessSongViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Guess the Song", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "music.mic")
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(GuessSongStyle.colors))
                            .phonePlayIdle(degrees: 8, duration: 1.0)
                        Text("Guess the Song")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("A word comes up. Sing any song that fits it: the word in the title, its Hindi meaning, or the word in the scene. Rain? Tip Tip Barsa Paani!")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 10) {
                        PhonePlaySectionLabel(text: "Who plays")
                        HStack(spacing: 10) {
                            PhonePlayChip(title: "Two teams", subtitle: "Take turns",
                                          selected: !game.oneTeam, colors: GuessSongStyle.colors) {
                                game.oneTeam = false
                            }
                            PhonePlayChip(title: "Everyone", subtitle: "One big team",
                                          selected: game.oneTeam, colors: GuessSongStyle.colors) {
                                game.oneTeam = true
                            }
                        }
                        if !game.oneTeam {
                            ForEach(0..<2, id: \.self) { index in
                                TextField("Team \(index + 1)", text: $game.teamNames[index])
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius,
                                                                 style: .continuous)
                                        .fill(PhonePlayDesign.surface))
                                    .submitLabel(.done)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        PhonePlaySectionLabel(text: "Time per turn")
                        HStack(spacing: 10) {
                            ForEach(GuessSongViewModel.turnChoices, id: \.self) { seconds in
                                PhonePlayChip(title: "\(seconds) sec", selected: game.turnSeconds == seconds,
                                              colors: GuessSongStyle.colors) {
                                    game.turnSeconds = seconds
                                }
                            }
                        }
                        PhonePlaySectionLabel(text: game.oneTeam ? "Turns" : "Turns per team")
                        HStack(spacing: 10) {
                            ForEach(GuessSongViewModel.roundChoices, id: \.self) { rounds in
                                PhonePlayChip(title: "\(rounds)", selected: game.roundsEach == rounds,
                                              colors: GuessSongStyle.colors) {
                                    game.roundsEach = rounds
                                }
                            }
                        }
                    }

                    PhonePlayHowToCard(steps: [
                        "The other team holds the phone and shows the word to the singers.",
                        "Sing a song that fits. The judge taps Sung it for 2 points, or Pass.",
                        "Stuck? Hint shows the Hindi word, for 1 point.",
                        "When time runs out, swap. Most points wins.",
                    ], accent: PhonePlayDesign.pink)

                    Toggle(isOn: $game.soundOn) {
                        Text("Countdown sound")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .tint(PhonePlayDesign.pink)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface))

                    Text("\(GuessSongDeck.words.count) words, Bollywood and English songs")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)

                    PhonePlayBigButton(title: "Start", symbol: "music.note", colors: GuessSongStyle.colors) {
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

// MARK: - Ready (hand the phone over)

private struct GuessSongReadyView: View {
    @ObservedObject var game: GuessSongViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Guess the Song", backTitle: "Setup", onBack: game.editSetup)
            ScrollView {
                VStack(spacing: 24) {
                    GuessSongScoreboard(game: game)

                    VStack(spacing: 8) {
                        Text("Up next")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                        Text(game.teamName)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(GuessSongStyle.colors(team: game.team)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(game.oneTeam
                             ? "Turn \(game.turn + 1) of \(game.totalTurns). Whoever holds the phone judges."
                             : "Turn \(game.turn / game.teamCount + 1) of \(game.roundsEach). Hand the phone to the other team: they judge.")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 10)

                    PhonePlayBigButton(title: "Start the clock", symbol: "play.fill",
                                       colors: GuessSongStyle.colors(team: game.team)) {
                        game.beginTurn()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Singing (the clock runs)

private struct GuessSongSingingView: View {
    @ObservedObject var game: GuessSongViewModel

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(game.teamName)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(game.turnPoints) pts")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.yellow)
                Text(PhonePlayTime.clock(game.secondsLeft))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(game.secondsLeft <= 5 ? PhonePlayDesign.red : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Spacer(minLength: 0)

            if let word = game.current {
                VStack(spacing: 14) {
                    Text("SING A SONG WITH")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundColor(PhonePlayDesign.text3)
                    Text(word.word)
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .id(word.word)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    if game.hintShown {
                        Text("Hindi: \(word.hindi)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient(GuessSongStyle.colors(team: game.team)))
                        .opacity(0.9)
                )
                .padding(.horizontal, 20)
                .animation(PhonePlayDesign.pop, value: word.word)
                .animation(PhonePlayDesign.smooth, value: game.hintShown)
            }

            if let last = game.lastOutcome {
                GuessSongLastWord(outcome: last)
                    .id(last.id)
                    .transition(.opacity)
                    .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                PhonePlayBigButton(title: game.hintShown ? "Sung it (+1)" : "Sung it (+2)",
                                   symbol: "checkmark", colors: [PhonePlayDesign.green, PhonePlayDesign.cyan]) {
                    game.sung()
                }
                HStack(spacing: 12) {
                    PhonePlayGhostButton(title: "Hint", symbol: "lightbulb.fill") { game.showHint() }
                        .opacity(game.hintShown ? 0.4 : 1)
                    PhonePlayGhostButton(title: "Pass", symbol: "forward.fill") { game.pass() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

/// The word just played and a few songs that fit it.
private struct GuessSongLastWord: View {
    let outcome: GuessSongViewModel.Outcome

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: outcome.sung ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(outcome.sung ? PhonePlayDesign.green : PhonePlayDesign.red)
                Text("\(outcome.word.word): songs that fit")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            Text(outcome.word.songs.joined(separator: "  /  "))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
            .fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Turn over

private struct GuessSongTurnOverView: View {
    @ObservedObject var game: GuessSongViewModel

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Time!", backTitle: "Setup", onBack: game.editSetup)
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text(game.teamName)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(PhonePlayDesign.gradient(GuessSongStyle.colors(team: game.team)))
                        Text("scored \(game.turnPoints) this turn")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(game.outcomes) { outcome in
                            GuessSongLastWord(outcome: outcome)
                        }
                        if game.outcomes.isEmpty {
                            Text("Not a single song. The microphone is disappointed.")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                        }
                    }

                    GuessSongScoreboard(game: game)

                    PhonePlayBigButton(title: game.isLastTurn ? "Final scores" : "Next turn",
                                       symbol: game.isLastTurn ? "trophy.fill" : "arrow.right",
                                       colors: GuessSongStyle.colors) {
                        game.nextTurn()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Final

private struct GuessSongFinalView: View {
    @ObservedObject var game: GuessSongViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PhonePlayTopBar(title: "Guess the Song", backTitle: "Games", onBack: onExit)
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.yellow, PhonePlayDesign.orange]))
                        .phonePlayIdle(dy: 4, scale: 0.05, duration: 1.2)
                        .padding(.top, 10)
                    Text(game.winnerText)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    GuessSongScoreboard(game: game)
                    PhonePlayBigButton(title: "Play again", symbol: "arrow.clockwise",
                                       colors: GuessSongStyle.colors) {
                        game.playAgain()
                    }
                    PhonePlayGhostButton(title: "Change teams or time", symbol: "slider.horizontal.3") {
                        game.editSetup()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct GuessSongScoreboard: View {
    @ObservedObject var game: GuessSongViewModel

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<game.teamCount, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(game.name(of: index))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(game.scores.indices.contains(index) ? game.scores[index] : 0)")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient(GuessSongStyle.colors(team: index)))
                        .opacity(index == game.team ? 0.95 : 0.45)
                )
            }
        }
    }
}
