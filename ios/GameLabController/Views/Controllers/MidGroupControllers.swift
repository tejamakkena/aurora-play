import SwiftUI

/// Phone controllers for the mid-group games.
///
/// These carry the app's most sensitive private state — a spymaster's colour
/// key, a spy's ignorance, a hidden dial target. Each is rendered only from what
/// the server sent to this specific phone.

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

    private var teamColor: Color { team == "red" ? .red : .blue }

    private func tint(_ index: Int) -> Color {
        if index < revealed.count, revealed[index] { return .white.opacity(0.05) }
        guard isSpymaster, index < key.count else { return .white.opacity(0.09) }
        switch key[index] {
        case "red":      return .red.opacity(0.75)
        case "blue":     return .blue.opacity(0.75)
        case "assassin": return .black
        default:         return Color(hex: "8d7f6d").opacity(0.6)
        }
    }

    var body: some View {
        ControllerShell(title: "Cipher Grid",
                        subtitle: isSpymaster ? "\(team.capitalized) spymaster — keep it secret"
                                              : "\(team.capitalized) team") {
            VStack(spacing: 12) {
                if canClue {
                    VStack(spacing: 10) {
                        AnswerField(placeholder: "One-word clue", text: $clue,
                                    autocapitalize: false)
                        Stepper("Number: \(count)", value: $count, in: 1...9)
                            .foregroundColor(.white).padding(.horizontal, 20)
                        BigButton(title: "Give Clue", tint: teamColor,
                                  enabled: !clue.trimmingCharacters(in: .whitespaces).isEmpty) {
                            onAction("give_clue", ["word": clue, "count": count])
                            clue = ""
                        }
                    }
                    .padding(.top, 12)
                } else if !clueWord.isEmpty {
                    Text("“\(clueWord)” · \(guessesLeft) left")
                        .font(.headline).foregroundColor(.yellow).padding(.top, 12)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5),
                          spacing: 5) {
                    ForEach(Array(words.enumerated()), id: \.offset) { idx, word in
                        Button(action: { if canGuess { onAction("guess", ["index": idx]) } }) {
                            Text(word)
                                .font(.system(size: 10, weight: .bold))
                                .minimumScaleFactor(0.6).lineLimit(2)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(RoundedRectangle(cornerRadius: 7).fill(tint(idx)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canGuess || (idx < revealed.count && revealed[idx]))
                    }
                }
                .padding(.horizontal, 14)

                if isSpymaster {
                    Text("Don't let anyone see this screen")
                        .font(.caption).foregroundColor(.orange)
                } else if !canGuess {
                    Text("Waiting for the other team…")
                        .font(.caption).foregroundColor(.white.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
        }
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
                    if isSpy {
                        VStack(spacing: 8) {
                            Image(systemName: "eyeglasses").font(.system(size: 56)).foregroundColor(.white.opacity(0.75))
                            Text("YOU ARE THE SPY")
                                .font(.title3.bold()).tracking(2).foregroundColor(.red)
                            Text("You don't know the location. Blend in.")
                                .font(.subheadline).foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 6) {
                            Text("THE LOCATION").font(.caption.bold()).tracking(3)
                                .foregroundColor(.white.opacity(0.4))
                            Text(location ?? "…").font(.title.bold()).foregroundColor(.cyan)
                            Text("Don't say it out loud")
                                .font(.caption).foregroundColor(.orange)
                        }
                        .padding(.top, 20)
                    }

                    if phase == "reveal" {
                        Label("Round over - look at the TV", systemImage: "tv")
                            .font(.headline).foregroundColor(.white.opacity(0.7))
                    } else if phase == "question" {
                        BigButton(title: "Call a Vote", systemImage: "hand.raised.fill",
                                  tint: .orange) {
                            onAction("call_vote", [:])
                        }
                    } else {
                        VStack(spacing: 10) {
                            ForEach(others, id: \.id) { p in
                                ChoiceRow(text: p.name, selected: myVote == p.id,
                                          disabled: !canVote) {
                                    onAction("vote", ["targetID": p.id])
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    if isSpy && phase != "reveal" {
                        Button(action: { showGuess.toggle() }) {
                            Text(showGuess ? "Hide locations" : "Guess the location")
                                .font(.subheadline.bold()).foregroundColor(.yellow)
                        }
                        .buttonStyle(.plain)

                        if showGuess {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                      spacing: 8) {
                                ForEach(allLocations, id: \.self) { loc in
                                    Button(action: {
                                        onAction("spy_guess", ["location": loc])
                                    }) {
                                        Text(loc).font(.caption).foregroundColor(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                                            .background(RoundedRectangle(cornerRadius: 8)
                                                .fill(.white.opacity(0.07)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
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
                    Text(lotName).font(.title2.bold()).foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text("worth \(lotValue * 10) points")
                        .font(.subheadline).foregroundColor(.yellow.opacity(0.8))
                }
                .padding(.horizontal, 24).padding(.top, 24)

                if phase != "bid" {
                    WaitingState(systemIcon: "hammer.fill", text: "Bids revealed on the TV",
                                 detail: myBid.map { "You bid \($0)" })
                } else if let placed = myBid {
                    WaitingState(systemIcon: "lock.fill", text: "Bid sealed",
                                 detail: "You bid \(placed) — nobody can see it yet")
                } else {
                    VStack(spacing: 10) {
                        Text("\(Int(bid))")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan)
                        Slider(value: $bid, in: 0...Double(max(budget, 1)), step: 1)
                            .tint(.cyan).padding(.horizontal, 30)
                        Text("of \(budget) remaining")
                            .font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                    BigButton(title: "Place Sealed Bid", systemImage: "lock.fill") {
                        onAction("bid", ["amount": Int(bid)])
                    }
                }
                Spacer(minLength: 0)
            }
            .onChange(of: privateData.int("round")) { newRound in
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
                HStack {
                    Text(leftLabel).font(.subheadline.bold()).foregroundColor(.blue)
                    Spacer()
                    Text(rightLabel).font(.subheadline.bold()).foregroundColor(.red)
                }
                .padding(.horizontal, 26).padding(.top, 24)

                if isPsychic, let target {
                    VStack(spacing: 8) {
                        Text("YOUR SECRET TARGET").font(.caption.bold()).tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                        ZStack(alignment: .leading) {
                            LinearGradient(colors: [.blue, .purple, .red],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(height: 26).clipShape(Capsule())
                            Capsule().fill(.white)
                                .frame(width: 8, height: 42)
                                .offset(x: CGFloat(target) / 100 * 280 - 4)
                        }
                        .frame(width: 280, height: 42)
                        Text("\(target)").font(.title.bold()).foregroundColor(.white)
                    }
                }

                if canClue {
                    AnswerField(placeholder: "Your clue", text: $clueText, autocapitalize: false)
                    BigButton(title: "Give Clue", enabled: !clueText.isEmpty) {
                        onAction("give_clue", ["clue": clueText])
                        clueText = ""
                    }
                } else if canDial {
                    VStack(spacing: 12) {
                        Text("“\(clue)”").font(.title3.bold()).foregroundColor(.yellow)
                        Slider(value: $dial, in: 0...100, step: 1)
                            .tint(.cyan).padding(.horizontal, 30)
                            .onChange(of: dial) { v in
                                onAction("set_dial", ["value": Int(v)])
                            }
                        Text("\(Int(dial))").font(.title2.bold()).foregroundColor(.cyan)
                    }
                } else {
                    WaitingState(systemIcon: "antenna.radiowaves.left.and.right",
                                 text: clue.isEmpty ? "Waiting for the clue…" : "“\(clue)”",
                                 detail: isPsychic ? "The team is turning the dial"
                                                   : "Watch the TV")
                }
                Spacer(minLength: 0)
            }
        }
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
                    } else {
                        Text(question).font(.headline).foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.top, 16)

                        if canPoll {
                            Text("Audience Poll — help them out")
                                .font(.caption.bold()).foregroundColor(.cyan)
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
                            HStack(spacing: 10) {
                                lifelineButton("50:50", key: "fifty", action: "lifeline_fifty")
                                lifelineButton("Audience", key: "poll", action: "lifeline_poll")
                                lifelineButton("Skip", key: "skip", action: "lifeline_skip")
                            }
                            .padding(.horizontal, 20)

                            Button(action: { onAction("walk_away", [:]) }) {
                                Text("Walk away with ₹\(prize)")
                                    .font(.subheadline).foregroundColor(.orange)
                            }
                            .buttonStyle(.plain).padding(.top, 4)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func lifelineButton(_ title: String, key: String, action: String) -> some View {
        let available = lifelines[key] ?? false
        return Button(action: { if available { onAction(action, [:]) } }) {
            Text(title).font(.caption.bold())
                .foregroundColor(available ? .white : .white.opacity(0.25))
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(available ? Color.purple.opacity(0.6) : .white.opacity(0.05)))
        }
        .buttonStyle(.plain).disabled(!available)
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
                        Image(systemName: "theatermasks.fill").font(.system(size: 64)).foregroundColor(.white.opacity(0.75))
                        Text("ACT THIS OUT").font(.caption.bold()).tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                        Text(title ?? "…").font(.title.bold())
                            .foregroundColor(.yellow).multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Text("No words, no sounds!")
                            .font(.subheadline).foregroundColor(.orange)
                    }
                    .padding(.top, 30)
                } else if gotIt {
                    WaitingState(systemIcon: "checkmark.circle.fill", text: "You got it!",
                                 detail: "Waiting for the round to end")
                } else if canGuess {
                    Spacer()
                    AnswerField(placeholder: "Film name", text: $guess)
                    BigButton(title: "Guess", systemImage: "paperplane.fill",
                              enabled: !guess.trimmingCharacters(in: .whitespaces).isEmpty) {
                        onAction("guess", ["text": guess])
                        guess = ""
                    }
                    Spacer()
                } else {
                    WaitingState(systemIcon: "clapperboard.fill", text: "Reveal is on the TV")
                }
                Spacer(minLength: 0)
            }
        }
    }
}
