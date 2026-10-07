import SwiftUI

// MARK: - Word of the Day screens

private enum WordDayStyle {
    static let colors: [Color] = [PhonePlayDesign.purple, PhonePlayDesign.blue]
    static let accent: Color = PhonePlayDesign.purple
}

struct WordDayRootView: View {
    @ObservedObject var game: WordDayViewModel
    let onExit: () -> Void

    @State private var appeared: Bool = false
    @State private var showYesterday: Bool = false

    var body: some View {
        ZStack {
            PhonePlayDesign.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PhonePlayTopBar(title: "Word of the Day", backTitle: "Games", onBack: onExit)
                ScrollView {
                    VStack(spacing: 16) {
                        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(2)
                            .foregroundColor(PhonePlayDesign.text3)
                            .padding(.top, 4)

                        WordDayHeroCard(game: game)
                            .modifier(WordDayEntrance(appeared: appeared, order: 0))

                        WordDayInfoCard(label: "In a sentence", symbol: "text.quote",
                                        tint: PhonePlayDesign.cyan) {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\"\(game.today.example)\"")
                                    .font(.system(size: 18, weight: .semibold, design: .serif))
                                    .italic()
                                    .foregroundColor(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                WordDaySpeakerButton(symbol: "speaker.wave.2.fill", tint: PhonePlayDesign.cyan,
                                                     spoken: game.spoken) {
                                    game.sayExample()
                                }
                            }
                        }
                        .modifier(WordDayEntrance(appeared: appeared, order: 1))

                        WordDayInfoCard(label: "Where it comes from", symbol: "scroll.fill",
                                        tint: PhonePlayDesign.yellow) {
                            Text(game.today.origin)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .modifier(WordDayEntrance(appeared: appeared, order: 2))

                        WordDayChallengeCard(game: game)
                            .modifier(WordDayEntrance(appeared: appeared, order: 3))

                        WordDayYesterdayCard(game: game, expanded: $showYesterday)
                            .modifier(WordDayEntrance(appeared: appeared, order: 4))

                        WordDayNextWord()
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            withAnimation(PhonePlayDesign.pop) {
                appeared = true
            }
        }
    }
}

/// Cards rise in one after another.
private struct WordDayEntrance: ViewModifier {
    let appeared: Bool
    let order: Int

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .animation(PhonePlayDesign.smooth.delay(0.08 * Double(order)), value: appeared)
    }
}

// MARK: - Hero

private struct WordDayHeroCard: View {
    @ObservedObject var game: WordDayViewModel

    var body: some View {
        VStack(spacing: 14) {
            Text(game.today.word)
                .font(.system(size: 46, weight: .black, design: .serif))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.4)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

            Text(game.today.partOfSpeech)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.black.opacity(0.2)))

            Text(game.today.meaning)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                WordDayPillButton(title: "Hear it", symbol: "speaker.wave.2.fill", spoken: game.spoken) {
                    game.sayWord()
                }
                WordDayPillButton(title: "Slowly", symbol: "tortoise.fill", spoken: game.spoken) {
                    game.sayWord(slowly: true)
                }
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient(WordDayStyle.colors))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: WordDayStyle.accent.opacity(0.35), radius: 18, y: 8)
    }
}

private struct WordDayPillButton: View {
    let title: String
    let symbol: String
    let spoken: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .symbolEffect(.bounce, value: spoken)
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.92)))
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

private struct WordDaySpeakerButton: View {
    let symbol: String
    let tint: Color
    let spoken: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint.opacity(0.14)))
                .symbolEffect(.bounce, value: spoken)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

// MARK: - Info cards

private struct WordDayInfoCard<Content: View>: View {
    let label: String
    let symbol: String
    let tint: Color
    let content: Content

    init(label: String, symbol: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.label = label
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.text3)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }
}

// MARK: - Use it today

private struct WordDayChallengeCard: View {
    @ObservedObject var game: WordDayViewModel

    @State private var celebrate: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.green)
                Text("USE IT TODAY")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.text3)
                Spacer()
                if game.totalUsed > 0 {
                    Text(game.totalUsed == 1 ? "1 word used" : "\(game.totalUsed) words used")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.green)
                        .contentTransition(.numericText())
                }
            }

            Text(game.challenge)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            if game.usedToday {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.green)
                        .symbolEffect(.bounce, value: celebrate)
                    Text("Done! You used it today.")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.green)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                PhonePlayBigButton(title: "I used it!", symbol: "checkmark.circle.fill",
                                   colors: [PhonePlayDesign.green, PhonePlayDesign.cyan]) {
                    game.markUsed()
                    celebrate += 1
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .strokeBorder(PhonePlayDesign.green.opacity(game.usedToday ? 0.6 : 0.2), lineWidth: 1.5)
                )
        )
        .animation(PhonePlayDesign.pop, value: game.usedToday)
    }
}

// MARK: - Yesterday

private struct WordDayYesterdayCard: View {
    @ObservedObject var game: WordDayViewModel
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                PhonePlayHaptics.tap()
                expanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YESTERDAY'S WORD")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(2)
                            .foregroundColor(PhonePlayDesign.text3)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(game.yesterday.word)
                                .font(.system(size: 24, weight: .black, design: .serif))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            Text(game.yesterday.partOfSpeech)
                                .font(.system(size: 14, weight: .semibold, design: .serif))
                                .italic()
                                .foregroundColor(PhonePlayDesign.text2)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(game.yesterday.meaning)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.yesterday.origin)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        game.sayYesterday()
                    } label: {
                        Label("Hear it", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.purple)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(PhonePlayDesign.purple.opacity(0.15)))
                    }
                    .buttonStyle(PhonePlayPressStyle())
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
        .clipped()
        .animation(PhonePlayDesign.smooth, value: expanded)
    }
}

// MARK: - Countdown

private struct WordDayNextWord: View {
    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            Text("Next word in \(Self.untilTomorrow(from: context.date))")
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(PhonePlayDesign.text3)
        }
    }

    nonisolated private static func untilTomorrow(from now: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        let total = max(0, Int(tomorrow.timeIntervalSince(now)))
        return String(format: "%dh %02dm %02ds", total / 3600, (total % 3600) / 60, total % 60)
    }
}
