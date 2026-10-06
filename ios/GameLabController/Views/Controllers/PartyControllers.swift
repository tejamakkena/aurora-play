import SwiftUI

/// Phone controllers for the big-party games.
///
/// Each reads `privateData` through computed properties rather than mirroring it
/// into `@State`, so a fresh `private_state` from the server is reflected at
/// once. Only genuinely local interaction state (a half-typed answer) is stored.
///
/// Styled with the Phone Play look (PhonePlayDesign): surface cards, rounded
/// heavy type, gradient buttons that squash under the finger, and haptics.

// MARK: - Shared pieces

/// One accent per party game, all drawn from the Phone Play palette.
private enum PartyPadTint {
    static let bluff: Color = PhonePlayDesign.pink
    static let lastTap: Color = PhonePlayDesign.green
    static let herd: Color = PhonePlayDesign.cyan
    static let emoji: Color = PhonePlayDesign.yellow
    static let npat: Color = PhonePlayDesign.cyan
    static let teamA: Color = PhonePlayDesign.cyan
    static let teamB: Color = PhonePlayDesign.pink
    static let mostLikely: Color = PhonePlayDesign.purple
}

/// The question or prompt for the round, on a surface card.
private struct PartyPadPromptCard: View {
    let text: String
    var label: String? = nil
    var accent: Color = PhonePlayDesign.cyan
    var textColor: Color = .white

    var body: some View {
        VStack(spacing: 8) {
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(accent)
            }
            Text(text)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
}

/// The transition every phase change in this file uses.
private extension AnyTransition {
    static var partyPadPop: AnyTransition {
        .scale(scale: 0.92).combined(with: .opacity)
    }
}

// MARK: - Bluff It

struct BluffItControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "write") }
    private var prompt: String { privateData.str("prompt") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var hasSubmitted: Bool { privateData.bool("hasSubmitted") }
    private var myPick: Int? { privateData["myPick"] as? Int }
    private var options: [(index: Int, text: String, isMine: Bool)] {
        privateData.dicts("options").map {
            ($0["index"] as? Int ?? 0, $0["text"] as? String ?? "",
             $0["isMine"] as? Bool ?? false)
        }
    }

    @State private var lie = ""
    @State private var trackedRound = -1

    var body: some View {
        ControllerShell(title: "Bluff It",
                        subtitle: phase == "write" ? "Invent a convincing lie" : "Find the truth",
                        secondsLeft: seconds) {
            VStack(spacing: 18) {
                if !prompt.isEmpty {
                    PartyPadPromptCard(text: prompt,
                                       label: phase == "pick" ? "Spot the real answer" : "Fake an answer",
                                       accent: PartyPadTint.bluff)
                        .padding(.top, 14)
                }

                switch phase {
                case "write":
                    if hasSubmitted {
                        WaitingState(systemIcon: "pencil", text: "Lie submitted",
                                     detail: "Waiting for everyone else…")
                            .transition(.partyPadPop)
                    } else {
                        VStack(spacing: 14) {
                            Spacer()
                            AnswerField(placeholder: "Your fake answer", text: $lie)
                            BigButton(title: "Submit Lie", systemImage: "paperplane.fill",
                                      tint: PartyPadTint.bluff,
                                      enabled: !lie.trimmingCharacters(in: .whitespaces).isEmpty) {
                                onAction("submit_lie", ["text": lie])
                                lie = ""
                            }
                            Spacer()
                        }
                        .transition(.partyPadPop)
                    }
                case "pick":
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(options, id: \.index) { opt in
                                ChoiceRow(text: opt.text,
                                          detail: opt.isMine ? "Your lie, so you can't pick it" : nil,
                                          selected: myPick == opt.index,
                                          disabled: opt.isMine || myPick != nil) {
                                    onAction("pick", ["index": opt.index])
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .transition(.partyPadPop)
                default:
                    WaitingState(systemIcon: "party.popper.fill", text: "Scores are on the TV")
                        .transition(.partyPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: hasSubmitted)
            // Clear the draft when a new round starts so the old lie is not resubmitted.
            .onChange(of: privateData.int("round")) { _, newRound in
                if newRound != trackedRound { trackedRound = newRound; lie = "" }
            }
        }
    }
}

// MARK: - Last Tap Standing

struct LastTapControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "arming") }
    private var isAlive: Bool { privateData.bool("isAlive", true) }
    private var canTap: Bool { privateData.bool("canTap") }
    private var myMs: Int? { privateData["myMs"] as? Int }
    private var falseStart: Bool { privateData.bool("falseStart") }

    var body: some View {
        ControllerShell(title: "Last Tap Standing",
                        subtitle: isAlive ? "Round \(privateData.int("round"))" : "Eliminated") {
            ZStack {
                if !isAlive {
                    WaitingState(systemIcon: "xmark.octagon.fill", text: "You're out",
                                 detail: "Watch the rest fight it out on the TV")
                        .transition(.partyPadPop)
                } else if let ms = myMs {
                    WaitingState(systemIcon: falseStart ? "nosign" : "stopwatch.fill",
                                 text: falseStart ? "Too early!" : "\(ms) ms",
                                 detail: falseStart ? "You tapped before GO"
                                                    : "Waiting for the others…")
                        .transition(.partyPadPop)
                } else {
                    tapPad
                        .transition(.partyPadPop)
                }
            }
            .animation(PhonePlayDesign.pop, value: isAlive)
            .animation(PhonePlayDesign.pop, value: myMs)
        }
    }

    /// The giant tap target. It stays live while waiting (the server judges
    /// a false start), and turns green and throbs on GO.
    private var tapPad: some View {
        let go: Bool = phase == "go"
        return Button(action: {
            guard canTap else { return }
            if go { PhonePlayHaptics.thump() } else { PhonePlayHaptics.rigid() }
            onAction("tap", [:])
        }) {
            ZStack {
                if go {
                    Circle()
                        .fill(PhonePlayDesign.gradient([PartyPadTint.lastTap, PhonePlayDesign.cyan]))
                        .shadow(color: PartyPadTint.lastTap.opacity(0.55), radius: 30)
                        .phonePlayIdle(scale: 0.03, duration: 0.25)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    Circle()
                        .fill(PhonePlayDesign.gradient([PhonePlayDesign.surface2, PhonePlayDesign.surface]))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 2))
                        .transition(.opacity)
                }
                VStack(spacing: 6) {
                    Text(go ? "TAP!" : "WAIT")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundColor(go ? .black : .white.opacity(0.35))
                    Text(go ? "Hit it!" : "Tap the moment it turns green")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(go ? .black.opacity(0.6) : PhonePlayDesign.text3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(PhonePlayDesign.pop, value: go)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

// MARK: - Herd

struct HerdControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var prompt: String { privateData.str("prompt") }
    private var phase: String { privateData.str("phase", "answer") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var hasSubmitted: Bool { privateData.bool("hasSubmitted") }
    private var myAnswer: String? { privateData["myAnswer"] as? String }

    @State private var answer = ""
    @State private var trackedRound = -1

    var body: some View {
        ControllerShell(title: "Herd",
                        subtitle: "Answer like the crowd would",
                        secondsLeft: seconds) {
            VStack(spacing: 18) {
                if !prompt.isEmpty {
                    PartyPadPromptCard(text: prompt, label: "Think like the herd",
                                       accent: PartyPadTint.herd)
                        .padding(.top, 14)
                }

                if phase != "answer" {
                    WaitingState(systemIcon: "chart.bar.fill", text: "Results are on the TV",
                                 detail: myAnswer.map { "You said “\($0)”" })
                        .transition(.partyPadPop)
                } else if hasSubmitted {
                    WaitingState(systemIcon: "checkmark.circle.fill", text: "Answer locked in",
                                 detail: myAnswer.map { "“\($0)”" })
                        .transition(.partyPadPop)
                } else {
                    VStack(spacing: 14) {
                        Spacer()
                        AnswerField(placeholder: "Your answer", text: $answer)
                        BigButton(title: "Submit", systemImage: "paperplane.fill",
                                  tint: PartyPadTint.herd,
                                  enabled: !answer.trimmingCharacters(in: .whitespaces).isEmpty) {
                            onAction("answer", ["text": answer])
                            answer = ""
                        }
                        Spacer()
                    }
                    .transition(.partyPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: hasSubmitted)
            .onChange(of: privateData.int("round")) { _, newRound in
                if newRound != trackedRound { trackedRound = newRound; answer = "" }
            }
        }
    }
}

// MARK: - Emoji Movie

struct EmojiMovieControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "compose") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var myTitle: String? { privateData["myTitle"] as? String }
    private var myEmoji: String? { privateData["myEmoji"] as? String }
    private var entries: [(index: Int, emoji: String, isMine: Bool)] {
        privateData.dicts("entries").map {
            ($0["index"] as? Int ?? 0, $0["emoji"] as? String ?? "",
             $0["isMine"] as? Bool ?? false)
        }
    }

    @State private var composed = ""
    @State private var guesses: [Int: String] = [:]

    private let palette = ["😀","😍","😱","😭","🤖","👑","🐉","🦁","🚀","🌊","🔥","❤️",
                           "⚔️","🏰","🎬","🎵","💀","👻","🧙","🕵️","🚗","✈️","🌍","⭐️"]

    var body: some View {
        ControllerShell(title: "Emoji Movie",
                        subtitle: phase == "compose" ? "Describe it in emoji" : "Guess the others",
                        secondsLeft: seconds) {
            ZStack {
                if phase == "compose" {
                    composeView
                        .transition(.partyPadPop)
                } else if phase == "guess" {
                    guessView
                        .transition(.partyPadPop)
                } else {
                    WaitingState(systemIcon: "party.popper.fill", text: "Reveal is on the TV")
                        .transition(.partyPadPop)
                }
            }
            .animation(PhonePlayDesign.pop, value: phase)
        }
    }

    private var composeView: some View {
        VStack(spacing: 16) {
            PartyPadPromptCard(text: myTitle ?? "…", label: "Your secret title",
                               accent: PartyPadTint.emoji, textColor: PartyPadTint.emoji)
                .padding(.top, 14)

            if myEmoji != nil {
                WaitingState(systemIcon: "checkmark.circle.fill", text: "Submitted",
                             detail: myEmoji)
                    .transition(.partyPadPop)
            } else {
                VStack(spacing: 14) {
                    // The clue so far; the hint is set in small type so it
                    // is not blown up to emoji size.
                    Text(composed.isEmpty ? "Tap emoji below" : composed)
                        .font(composed.isEmpty
                              ? Font.system(size: 17, weight: .semibold, design: .rounded)
                              : Font.system(size: 40))
                        .foregroundColor(composed.isEmpty ? PhonePlayDesign.text3 : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .fill(PhonePlayDesign.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .animation(PhonePlayDesign.pop, value: composed)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                              spacing: 8) {
                        ForEach(palette, id: \.self) { e in
                            Button(action: {
                                guard composed.count < 12 else {
                                    PhonePlayHaptics.warning()
                                    return
                                }
                                PhonePlayHaptics.tap()
                                composed += e
                            }) {
                                Text(e).font(.system(size: 30))
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(PhonePlayDesign.surface)
                                    )
                            }
                            .buttonStyle(PhonePlayPressStyle())
                        }
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 12) {
                        Button(action: {
                            PhonePlayHaptics.tap()
                            composed = String(composed.dropLast())
                        }) {
                            Image(systemName: "delete.left")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 66, height: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .fill(Color.white.opacity(0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PhonePlayPressStyle())

                        PhonePlayBigButton(title: "Submit", symbol: "paperplane.fill",
                                           colors: [PhonePlayDesign.yellow, PhonePlayDesign.orange],
                                           enabled: !composed.isEmpty) {
                            onAction("submit_emoji", ["emoji": composed])
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .transition(.partyPadPop)
            }
            Spacer(minLength: 0)
        }
        .animation(PhonePlayDesign.pop, value: myEmoji)
    }

    private var guessView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(entries, id: \.index) { entry in
                    VStack(spacing: 10) {
                        Text(entry.emoji)
                            .font(.system(size: 40))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if entry.isMine {
                            Text("YOUR CLUE")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .tracking(2)
                                .foregroundColor(PhonePlayDesign.text3)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(0.07)))
                        } else {
                            TextField("Guess the title", text: Binding(
                                get: { guesses[entry.index] ?? "" },
                                set: { guesses[entry.index] = $0 }))
                                .textFieldStyle(.plain)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .submitLabel(.send)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .fill(PhonePlayDesign.surface2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .onSubmit {
                                    PhonePlayHaptics.tap()
                                    onAction("guess", ["index": entry.index,
                                                       "text": guesses[entry.index] ?? ""])
                                }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface)
                    )
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - Name Place Animal Thing

struct NPATControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var letter: String { privateData.str("letter") }
    private var phase: String { privateData.str("phase", "fill") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var hasSubmitted: Bool { privateData.bool("hasSubmitted") }

    @State private var values: [String: String] = [:]
    @State private var trackedRound = -1

    private let fields = [("name", "Name", "person"),
                          ("place", "Place", "mappin"),
                          ("animal", "Animal", "pawprint"),
                          ("thing", "Thing", "cube")]

    var body: some View {
        ControllerShell(title: "Name Place Animal Thing",
                        subtitle: "Everything starts with \(letter)",
                        secondsLeft: seconds) {
            ZStack {
                if phase != "fill" {
                    WaitingState(systemIcon: "clipboard.fill", text: "Scoring on the TV")
                        .transition(.partyPadPop)
                } else if hasSubmitted {
                    WaitingState(systemIcon: "checkmark.circle.fill", text: "Submitted",
                                 detail: "Waiting for the round to end…")
                        .transition(.partyPadPop)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            Text(letter)
                                .font(.system(size: 80, weight: .black, design: .rounded))
                                .foregroundStyle(PhonePlayDesign.gradient([PhonePlayDesign.cyan,
                                                                           PhonePlayDesign.indigo]))
                                .phonePlayIdle(dy: 3, scale: 0.03, duration: 1.4)
                                .padding(.top, 8)

                            ForEach(fields, id: \.0) { key, label, icon in
                                fieldRow(key: key, label: label, icon: icon)
                            }

                            PhonePlayBigButton(title: "Submit All", symbol: "checkmark.circle.fill",
                                               colors: [PhonePlayDesign.cyan, PhonePlayDesign.indigo],
                                               enabled: values.values.contains { !$0.isEmpty }) {
                                onAction("submit", values)
                            }
                            .padding(.top, 6)
                        }
                        .padding(20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .transition(.partyPadPop)
                }
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: hasSubmitted)
            .onChange(of: privateData.int("round")) { _, newRound in
                if newRound != trackedRound { trackedRound = newRound; values = [:] }
            }
        }
    }

    private func fieldRow(key: String, label: String, icon: String) -> some View {
        let filled: Bool = !(values[key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 12) {
            Image(systemName: filled ? "checkmark.circle.fill" : icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(filled ? PhonePlayDesign.green : PartyPadTint.npat)
                .frame(width: 26)
            TextField(label, text: Binding(
                get: { values[key] ?? "" },
                set: { values[key] = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .autocorrectionDisabled()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .strokeBorder(filled ? PhonePlayDesign.green.opacity(0.5) : Color.white.opacity(0.06),
                              lineWidth: 1)
        )
        .animation(PhonePlayDesign.pop, value: filled)
    }
}

// MARK: - Antakshari

struct AntakshariControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var letter: String { privateData.str("letter") }
    private var phase: String { privateData.str("phase", "sing") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var myTeam: Int { privateData.int("myTeam") }
    private var mySong: String? { privateData["mySong"] as? String }

    @State private var song = ""
    @State private var trackedRound = -1

    /// The server only accepts a song beginning with the required letter, so the
    /// button mirrors that rule rather than letting a doomed submit through.
    private var valid: Bool {
        song.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix(letter)
    }

    private var teamColor: Color { myTeam == 0 ? PartyPadTint.teamA : PartyPadTint.teamB }

    var body: some View {
        ControllerShell(title: "Antakshari",
                        subtitle: "Team \(myTeam == 0 ? "A" : "B")",
                        secondsLeft: seconds) {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("SING A SONG STARTING WITH")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(PhonePlayDesign.text3)
                    Text(letter)
                        .font(.system(size: 84, weight: .black, design: .rounded))
                        .foregroundStyle(PhonePlayDesign.gradient([teamColor, teamColor.opacity(0.6)]))
                        .phonePlayIdle(dy: 3, scale: 0.03, duration: 1.4)
                }
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .strokeBorder(teamColor.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 14)

                if phase != "sing" {
                    WaitingState(systemIcon: "mic.fill", text: "Round over",
                                 detail: mySong.map { "You sang “\($0)”" })
                        .transition(.partyPadPop)
                } else {
                    VStack(spacing: 12) {
                        AnswerField(placeholder: "Song name", text: $song)
                        if !song.isEmpty && !valid {
                            Text("Must start with \(letter)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(PhonePlayDesign.orange)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        BigButton(title: "Sing It!", systemImage: "music.note",
                                  tint: teamColor, enabled: valid) {
                            onAction("submit_song", ["song": song])
                            song = ""
                        }
                    }
                    .animation(PhonePlayDesign.pop, value: valid)
                    .transition(.partyPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .onChange(of: privateData.int("round")) { _, newRound in
                if newRound != trackedRound { trackedRound = newRound; song = "" }
            }
        }
    }
}

// MARK: - Most Likely To

struct MostLikelyToControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "vote") }
    private var prompt: String { privateData.str("prompt") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var hasVoted: Bool { privateData.bool("hasVoted") }
    private var myPlayerID: String { privateData.str("myPlayerID") }
    private var players: [(id: String, name: String)] {
        (privateData["players"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, id != myPlayerID,
                  let name = $0["name"] as? String else { return nil }
            return (id, name)
        }
    }

    var body: some View {
        ControllerShell(title: "Most Likely To",
                        subtitle: phase == "vote" ? "Vote for who fits best" : "See who got the votes",
                        secondsLeft: seconds) {
            VStack(spacing: 18) {
                if !prompt.isEmpty {
                    PartyPadPromptCard(text: prompt, label: "Who is most likely to",
                                       accent: PartyPadTint.mostLikely)
                        .padding(.top, 14)
                }

                if phase == "vote" {
                    if hasVoted {
                        WaitingState(systemIcon: "checkmark.circle.fill", text: "Vote counted",
                                     detail: "Waiting for everyone else…")
                            .transition(.partyPadPop)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                                GridItem(.flexible(), spacing: 12)],
                                      spacing: 12) {
                                ForEach(players, id: \.id) { player in
                                    Button {
                                        PhonePlayHaptics.tap()
                                        onAction("vote", ["targetID": player.id])
                                    } label: {
                                        Text(player.name)
                                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                            .minimumScaleFactor(0.7)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 10)
                                            .frame(maxWidth: .infinity, minHeight: 64)
                                            .background(
                                                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius,
                                                                 style: .continuous)
                                                    .fill(PhonePlayDesign.surface)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius,
                                                                 style: .continuous)
                                                    .strokeBorder(PartyPadTint.mostLikely.opacity(0.35),
                                                                  lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(PhonePlayPressStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .transition(.partyPadPop)
                    }
                } else {
                    WaitingState(systemIcon: "tv", text: "Votes are in",
                                 detail: "Check the TV for the reveal")
                        .transition(.partyPadPop)
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: phase)
            .animation(PhonePlayDesign.pop, value: hasVoted)
        }
    }
}
