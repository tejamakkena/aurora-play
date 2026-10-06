import SwiftUI

/// Phone controllers for the mid-group games.
///
/// These carry the app's most sensitive private state — a spymaster's colour
/// key, a spy's ignorance, a hidden dial target. Each is rendered only from what
/// the server sent to this specific phone.
///
/// Styled with the Phone Play look (PhonePlayDesign): surface cards, rounded
/// heavy type, gradient buttons that squash under the finger, and haptics.

// MARK: - Shared pieces

private extension View {
    /// A Phone Play surface card, optionally edged in an accent colour.
    func midPadCard(_ accent: Color? = nil,
                    radius: CGFloat = PhonePlayDesign.cardRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(accent?.opacity(0.4) ?? Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

/// The small tracked caps label over a card's content.
private struct MidPadLabel: View {
    let text: String
    var color: Color = PhonePlayDesign.text3

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundColor(color)
    }
}

/// A short status line in a tinted capsule.
private struct MidPadPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = PhonePlayDesign.cyan

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
            }
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

private extension AnyTransition {
    static var midPadPop: AnyTransition {
        .scale(scale: 0.92).combined(with: .opacity)
    }
}

// MARK: - Cipher Grid

struct CipherGridControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var team: String { privateData.str("team", "red") }
    private var isSpymaster: Bool { privateData.bool("isSpymaster") }
    private var canGuess: Bool { privateData.bool("canGuess") }
    private var canClue: Bool { privateData.bool("canClue") }
    private var words: [String] { privateData.strings("words") }
    private var revealed: [Bool] { (privateData["revealed"] as? [Any] ?? []).compactMap { $0 as? Bool } }
    /// Empty for everyone except the two spymasters.
    private var key: [String] { privateData.strings("key") }
    private var clueWord: String {
        (privateData["clue"] as? [String: Any])?["word"] as? String ?? ""
    }
    private var guessesLeft: Int { privateData.int("guessesLeft") }

    @State private var clue = ""
    @State private var count = 1

    private var teamColor: Color { team == "red" ? PhonePlayDesign.red : PhonePlayDesign.blue }

    private func isRevealed(_ index: Int) -> Bool {
        index < revealed.count && revealed[index]
    }

    private func tint(_ index: Int) -> Color {
        if isRevealed(index) { return .white.opacity(0.04) }
        guard isSpymaster, index < key.count else { return PhonePlayDesign.surface2 }
        switch key[index] {
        case "red":      return PhonePlayDesign.red.opacity(0.8)
        case "blue":     return PhonePlayDesign.blue.opacity(0.8)
        case "assassin": return .black
        default:         return Color(hex: "8d7f6d").opacity(0.6)
        }
    }

    /// The assassin is black on a near-black screen, so the spymaster's
    /// copy gets an outline to make it findable.
    private func isAssassinForSpymaster(_ index: Int) -> Bool {
        isSpymaster && !isRevealed(index) && index < key.count && key[index] == "assassin"
    }

    var body: some View {
        ControllerShell(title: "Cipher Grid",
                        subtitle: isSpymaster ? "\(team.capitalized) spymaster — keep it secret"
                                              : "\(team.capitalized) team") {
            VStack(spacing: 12) {
                if canClue {
                    clueComposer
                        .padding(.top, 12)
                        .transition(.midPadPop)
                } else if !clueWord.isEmpty {
                    MidPadPill(text: "“\(clueWord)” · \(guessesLeft) left",
                               systemImage: "key.fill", tint: PhonePlayDesign.yellow)
                        .padding(.top, 12)
                        .transition(.midPadPop)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                          spacing: 6) {
                    ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                        Button(action: {
                            if canGuess {
                                PhonePlayHaptics.tap()
                                onAction("guess", ["index": idx])
                            }
                        }) {
                            Text(word)
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .minimumScaleFactor(0.6).lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(isRevealed(idx) ? .white.opacity(0.3) : .white)
                                .strikethrough(isRevealed(idx), color: .white.opacity(0.3))
                                .padding(.horizontal, 3)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(tint(idx))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(isAssassinForSpymaster(idx) ? Color.white.opacity(0.45)
                                                                                  : Color.white.opacity(0.05),
                                                      lineWidth: isAssassinForSpymaster(idx) ? 1.5 : 1)
                                )
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .disabled(!canGuess || isRevealed(idx))
                    }
                }
                .padding(.horizontal, 14)

                if isSpymaster {
                    MidPadPill(text: "Don't let anyone see this screen",
                               systemImage: "eye.slash.fill", tint: PhonePlayDesign.orange)
                } else if !canGuess {
                    Text("Waiting for the other team…")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: canClue)
            .animation(PhonePlayDesign.pop, value: clueWord)
        }
    }

    private var clueComposer: some View {
        VStack(spacing: 10) {
            AnswerField(placeholder: "One-word clue", text: $clue,
                        autocapitalize: false)
            // Same 1...9 range as the system stepper this replaces.
            HStack(spacing: 14) {
                Text("Number")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                Spacer()
                stepButton("minus", enabled: count > 1) { count = max(1, count - 1) }
                Text("\(count)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .frame(minWidth: 30)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(PhonePlayDesign.pop, value: count)
                stepButton("plus", enabled: count < 9) { count = min(9, count + 1) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .midPadCard(radius: PhonePlayDesign.buttonRadius)
            .padding(.horizontal, 20)
            BigButton(title: "Give Clue", systemImage: "paperplane.fill", tint: teamColor,
                      enabled: !clue.trimmingCharacters(in: .whitespaces).isEmpty) {
                onAction("give_clue", ["word": clue, "count": count])
                clue = ""
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            guard enabled else { return }
            PhonePlayHaptics.tap()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(enabled ? .white : .white.opacity(0.25))
                .frame(width: 44, height: 44)
                .background(Circle().fill(enabled ? teamColor.opacity(0.35) : Color.white.opacity(0.06)))
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!enabled)
    }
}

// MARK: - Odd One Out

struct OddOneOutControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isSpy: Bool { privateData.bool("isSpy") }
    /// Nil for the spy — the server simply never sends it to them.
    private var location: String? { privateData["location"] as? String }
    private var phase: String { privateData.str("phase", "question") }
    private var canVote: Bool { privateData.bool("canVote") }
    private var myVote: String? { privateData["myVote"] as? String }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var others: [(id: String, name: String)] {
        privateData.dicts("players").map {
            ($0["id"] as? String ?? "", $0["name"] as? String ?? "")
        }
    }
    private var allLocations: [String] { privateData.strings("allLocations") }

    @State private var showGuess = false

    var body: some View {
        ControllerShell(title: "Odd One Out",
                        subtitle: phase == "vote" ? "Vote for the spy" : "Ask questions",
                        secondsLeft: seconds) {
            ScrollView {
                VStack(spacing: 18) {
                    roleCard
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    Group {
                        if phase == "reveal" {
                            MidPadPill(text: "Round over - look at the TV", systemImage: "tv",
                                       tint: PhonePlayDesign.text2)
                        } else if phase == "question" {
                            BigButton(title: "Call a Vote", systemImage: "hand.raised.fill",
                                      tint: PhonePlayDesign.orange) {
                                onAction("call_vote", [:])
                            }
                        } else {
                            VStack(spacing: 10) {
                                PhonePlaySectionLabel(text: "Who is the spy?")
                                ForEach(others, id: \.id) { p in
                                    ChoiceRow(text: p.name, selected: myVote == p.id,
                                              disabled: !canVote) {
                                        onAction("vote", ["targetID": p.id])
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .transition(.midPadPop)

                    if isSpy && phase != "reveal" {
                        PhonePlayGhostButton(title: showGuess ? "Hide locations" : "Guess the location",
                                             symbol: showGuess ? "chevron.up" : "mappin.and.ellipse") {
                            showGuess.toggle()
                        }
                        .padding(.horizontal, 20)

                        if showGuess {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                                GridItem(.flexible(), spacing: 8)],
                                      spacing: 8) {
                                ForEach(allLocations, id: \.self) { loc in
                                    Button(action: {
                                        PhonePlayHaptics.thump()
                                        onAction("spy_guess", ["location": loc])
                                    }) {
                                        Text(loc)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.7)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 8)
                                            .frame(maxWidth: .infinity, minHeight: 48)
                                            .midPadCard(PhonePlayDesign.yellow, radius: 14)
                                    }
                                    .buttonStyle(PhonePlayPressStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(PhonePlayDesign.pop, value: phase)
                .animation(PhonePlayDesign.pop, value: showGuess)
            }
        }
    }

    @ViewBuilder
    private var roleCard: some View {
        if isSpy {
            VStack(spacing: 8) {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.red, PhonePlayDesign.pink]))
                    .phonePlayIdle(degrees: 4, duration: 1.2)
                Text("YOU ARE THE SPY")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.red)
                Text("You don't know the location. Blend in.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .midPadCard(PhonePlayDesign.red)
        } else {
            VStack(spacing: 6) {
                MidPadLabel(text: "The location")
                Text(location ?? "…")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(PhonePlayDesign.cyan)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text("Don't say it out loud")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.orange)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .midPadCard(PhonePlayDesign.cyan)
        }
    }
}

// MARK: - Sealed Auction

struct SealedAuctionControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var lotName: String { privateData.str("lotName") }
    private var lotValue: Int { privateData.int("lotValue") }
    private var budget: Int { privateData.int("budget") }
    private var phase: String { privateData.str("phase", "bid") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var myBid: Int? { privateData["myBid"] as? Int }

    @State private var bid: Double = 0
    @State private var trackedRound = -1

    var body: some View {
        ControllerShell(title: "Sealed Auction",
                        subtitle: "Budget \(budget)", secondsLeft: seconds) {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    MidPadLabel(text: "On the block")
                    Text(lotName)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("worth \(lotValue * 10) points")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.yellow)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .midPadCard(PhonePlayDesign.yellow)
                .padding(.horizontal, 20)
                .padding(.top, 14)

                if phase != "bid" {
                    WaitingState(systemIcon: "hammer.fill", text: "Bids revealed on the TV",
                                 detail: myBid.map { "You bid \($0)" })
                        .transition(.midPadPop)
                } else if let placed = myBid {
                    WaitingState(systemIcon: "lock.fill", text: "Bid sealed",
                                 detail: "You bid \(placed) — nobody can see it yet")
                        .transition(.midPadPop)
                } else {
                    VStack(spacing: 18) {
                        VStack(spacing: 10) {
                            Text("\(Int(bid))")
                                .font(.system(size: 64, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.cyan,
                                                                           PhonePlayDesign.indigo]))
                                .contentTransition(.numericText(value: bid))
                                .animation(.snappy(duration: 0.15), value: bid)
                            Slider(value: $bid, in: 0...Double(max(budget, 1)), step: 1)
                                .tint(PhonePlayDesign.cyan)
                            Text("of \(budget) remaining")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text3)
                        }
                        .padding(20)
                        .midPadCard()
                        .padding(.horizontal, 20)

                        BigButton(title: "Place Sealed Bid", systemImage: "lock.fill") {
                            onAction("bid", ["amount": Int(bid)])
                        }
                    }
                    .transition(.midPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: myBid)
            .onChange(of: privateData.int("round")) { _, newRound in
                if newRound != trackedRound { trackedRound = newRound; bid = 0 }
            }
        }
    }
}

// MARK: - Wavelength

struct WavelengthControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isPsychic: Bool { privateData.bool("isPsychic") }
    /// Only ever populated for the psychic.
    private var target: Int? { privateData["target"] as? Int }
    private var leftLabel: String { privateData.str("leftLabel") }
    private var rightLabel: String { privateData.str("rightLabel") }
    private var clue: String { privateData.str("clue") }
    private var canClue: Bool { privateData.bool("canClue") }
    private var canDial: Bool { privateData.bool("canDial") }
    private var seconds: Int { privateData.int("secondsLeft") }

    @State private var clueText = ""
    @State private var dial: Double = 50

    var body: some View {
        ControllerShell(title: "Wavelength",
                        subtitle: isPsychic ? "You're the psychic" : "Read the clue",
                        secondsLeft: seconds) {
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    endLabel(leftLabel, tint: PhonePlayDesign.blue, alignment: .leading)
                    Spacer(minLength: 0)
                    endLabel(rightLabel, tint: PhonePlayDesign.red, alignment: .trailing)
                }
                .padding(.horizontal, 20).padding(.top, 14)

                if isPsychic, let target {
                    VStack(spacing: 10) {
                        MidPadLabel(text: "Your secret target")
                        ZStack(alignment: .leading) {
                            LinearGradient(colors: [PhonePlayDesign.blue, PhonePlayDesign.purple,
                                                    PhonePlayDesign.red],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(height: 26).clipShape(Capsule())
                            Capsule().fill(.white)
                                .frame(width: 8, height: 42)
                                .shadow(color: .black.opacity(0.4), radius: 4)
                                .offset(x: CGFloat(target) / 100 * 280 - 4)
                        }
                        .frame(width: 280, height: 42)
                        Text("\(target)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .midPadCard(PhonePlayDesign.purple)
                    .padding(.horizontal, 20)
                }

                if canClue {
                    VStack(spacing: 14) {
                        AnswerField(placeholder: "Your clue", text: $clueText, autocapitalize: false)
                        BigButton(title: "Give Clue", systemImage: "paperplane.fill",
                                  tint: PhonePlayDesign.purple, enabled: !clueText.isEmpty) {
                            onAction("give_clue", ["clue": clueText])
                            clueText = ""
                        }
                    }
                    .transition(.midPadPop)
                } else if canDial {
                    VStack(spacing: 14) {
                        Text("“\(clue)”")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                            .multilineTextAlignment(.center)
                        Slider(value: $dial, in: 0...100, step: 1)
                            .tint(PhonePlayDesign.cyan)
                            .onChange(of: dial) { _, v in
                                onAction("set_dial", ["value": Int(v)])
                            }
                        Text("\(Int(dial))")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(PhonePlayDesign.cyan)
                            .contentTransition(.numericText(value: dial))
                    }
                    .padding(20)
                    .midPadCard(PhonePlayDesign.cyan)
                    .padding(.horizontal, 20)
                    .transition(.midPadPop)
                } else {
                    WaitingState(systemIcon: "antenna.radiowaves.left.and.right",
                                 text: clue.isEmpty ? "Waiting for the clue…" : "“\(clue)”",
                                 detail: isPsychic ? "The team is turning the dial"
                                                   : "Watch the TV")
                        .transition(.midPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: canClue)
            .animation(PhonePlayDesign.pop, value: canDial)
        }
    }

    private func endLabel(_ text: String, tint: Color, alignment: TextAlignment) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundColor(tint)
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: - KBC Hot Seat

struct KBCControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isHotSeat: Bool { privateData.bool("isHotSeat") }
    private var phase: String { privateData.str("phase", "answer") }
    private var question: String { privateData.str("question") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var prize: Int { privateData.int("prize") }
    private var canAnswer: Bool { privateData.bool("canAnswer") }
    private var canPoll: Bool { privateData.bool("canPoll") }
    private var myPollVote: Int? { privateData["myPollVote"] as? Int }
    private var lifelines: [String: Bool] {
        (privateData["lifelines"] as? [String: Any] ?? [:]).compactMapValues { $0 as? Bool }
    }
    private var choices: [(index: Int, text: String, hidden: Bool)] {
        privateData.dicts("choices").map {
            ($0["index"] as? Int ?? 0, $0["text"] as? String ?? "",
             $0["hidden"] as? Bool ?? false)
        }
    }

    var body: some View {
        ControllerShell(title: "KBC Hot Seat",
                        subtitle: isHotSeat ? "₹\(prize) question" : "Audience",
                        secondsLeft: seconds) {
            ScrollView {
                VStack(spacing: 14) {
                    if !isHotSeat && !canPoll {
                        WaitingState(systemIcon: "eye.fill", text: "Watching from the audience",
                                     detail: "You'll vote if the Audience Poll lifeline is used")
                            .transition(.midPadPop)
                    } else {
                        Text(question)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .midPadCard(PhonePlayDesign.purple)
                            .padding(.horizontal, 20).padding(.top, 14)

                        if canPoll {
                            MidPadPill(text: "Audience Poll — help them out",
                                       systemImage: "person.3.fill", tint: PhonePlayDesign.cyan)
                        }

                        VStack(spacing: 10) {
                            ForEach(choices, id: \.index) { c in
                                ChoiceRow(text: c.hidden ? "—" : c.text,
                                          detail: ["A", "B", "C", "D"][min(c.index, 3)],
                                          selected: myPollVote == c.index,
                                          disabled: c.hidden || (!canAnswer && !canPoll)) {
                                    onAction(canAnswer ? "answer" : "poll_vote",
                                             ["index": c.index])
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        if isHotSeat {
                            VStack(spacing: 8) {
                                PhonePlaySectionLabel(text: "Lifelines")
                                HStack(spacing: 10) {
                                    lifelineButton("50:50", key: "fifty", action: "lifeline_fifty")
                                    lifelineButton("Audience", key: "poll", action: "lifeline_poll")
                                    lifelineButton("Skip", key: "skip", action: "lifeline_skip")
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                            Button(action: {
                                PhonePlayHaptics.warning()
                                onAction("walk_away", [:])
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "figure.walk")
                                        .font(.system(size: 15, weight: .bold))
                                    Text("Walk away with ₹\(prize)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                                .foregroundColor(PhonePlayDesign.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .fill(PhonePlayDesign.orange.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .strokeBorder(PhonePlayDesign.orange.opacity(0.35), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PhonePlayPressStyle())
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(PhonePlayDesign.pop, value: canPoll)
                .animation(PhonePlayDesign.pop, value: isHotSeat)
            }
        }
    }

    private func lifelineButton(_ title: String, key: String, action: String) -> some View {
        let available = lifelines[key] ?? false
        return Button(action: {
            if available {
                PhonePlayHaptics.tap()
                onAction(action, [:])
            }
        }) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(available ? .white : .white.opacity(0.25))
                .strikethrough(!available, color: .white.opacity(0.25))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(available ? PhonePlayDesign.gradient([PhonePlayDesign.purple, PhonePlayDesign.indigo])
                                        : PhonePlayDesign.gradient([Color.white.opacity(0.05),
                                                                    Color.white.opacity(0.05)]))
                )
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!available)
    }
}

// MARK: - Bollywood Charades

struct BollywoodCharadesControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isActor: Bool { privateData.bool("isActor") }
    /// Only the actor is sent the title.
    private var title: String? { privateData["title"] as? String }
    private var gotIt: Bool { privateData.bool("gotIt") }
    private var canGuess: Bool { privateData.bool("canGuess") }
    private var seconds: Int { privateData.int("secondsLeft") }

    @State private var guess = ""

    var body: some View {
        ControllerShell(title: "Bollywood Charades",
                        subtitle: isActor ? "You're acting" : "Guess the film",
                        secondsLeft: seconds) {
            VStack(spacing: 18) {
                if isActor {
                    VStack(spacing: 12) {
                        Image(systemName: "theatermasks.fill")
                            .font(.system(size: 58, weight: .bold))
                            .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.orange,
                                                                       PhonePlayDesign.pink]))
                            .phonePlayIdle(degrees: 5, scale: 0.04, duration: 1.2)
                        MidPadLabel(text: "Act this out")
                        Text(title ?? "…")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundColor(PhonePlayDesign.yellow)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.5)
                        MidPadPill(text: "No words, no sounds!", systemImage: "speaker.slash.fill",
                                   tint: PhonePlayDesign.orange)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .midPadCard(PhonePlayDesign.orange)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .transition(.midPadPop)
                } else if gotIt {
                    WaitingState(systemIcon: "checkmark.circle.fill", text: "You got it!",
                                 detail: "Waiting for the round to end")
                        .transition(.midPadPop)
                } else if canGuess {
                    VStack(spacing: 14) {
                        Spacer()
                        AnswerField(placeholder: "Film name", text: $guess)
                        BigButton(title: "Guess", systemImage: "paperplane.fill",
                                  tint: PhonePlayDesign.orange,
                                  enabled: !guess.trimmingCharacters(in: .whitespaces).isEmpty) {
                            onAction("guess", ["text": guess])
                            guess = ""
                        }
                        Spacer()
                    }
                    .transition(.midPadPop)
                } else {
                    WaitingState(systemIcon: "film.fill", text: "Reveal is on the TV")
                        .transition(.midPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: isActor)
            .animation(PhonePlayDesign.pop, value: gotIt)
            .animation(PhonePlayDesign.pop, value: canGuess)
        }
    }
}
