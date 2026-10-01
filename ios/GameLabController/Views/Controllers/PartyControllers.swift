import SwiftUI

/// Phone controllers for the big-party games.
///
/// Each reads `privateData` through computed properties rather than mirroring it
/// into `@State`, so a fresh `private_state` from the server is reflected at
/// once. Only genuinely local interaction state (a half-typed answer) is stored.

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
                Text(prompt)
                    .font(.title3.bold()).foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.top, 20)

                switch phase {
                case "write":
                    if hasSubmitted {
                        WaitingState(systemIcon: "pencil", text: "Lie submitted",
                                     detail: "Waiting for everyone else…")
                    } else {
                        Spacer()
                        AnswerField(placeholder: "Your fake answer", text: $lie)
                        BigButton(title: "Submit Lie", systemImage: "paperplane.fill",
                                  enabled: !lie.trimmingCharacters(in: .whitespaces).isEmpty) {
                            onAction("submit_lie", ["text": lie])
                            lie = ""
                        }
                        Spacer()
                    }
                case "pick":
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(options, id: \.index) { opt in
                                ChoiceRow(text: opt.text,
                                          detail: opt.isMine ? "your lie — can't pick it" : nil,
                                          selected: myPick == opt.index,
                                          disabled: opt.isMine || myPick != nil) {
                                    onAction("pick", ["index": opt.index])
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                default:
                    WaitingState(systemIcon: "party.popper.fill", text: "Scores are on the TV")
                }
                Spacer(minLength: 0)
            }
            // Clear the draft when a new round starts so the old lie is not resubmitted.
            .onChange(of: privateData.int("round")) { newRound in
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

    @State private var pulse = false

    var body: some View {
        ControllerShell(title: "Last Tap Standing",
                        subtitle: isAlive ? "Round \(privateData.int("round"))" : "Eliminated") {
            if !isAlive {
                WaitingState(systemIcon: "skull", text: "You're out",
                             detail: "Watch the rest fight it out on the TV")
            } else if let ms = myMs {
                WaitingState(systemIcon: falseStart ? "nosign" : "stopwatch.fill",
                             text: falseStart ? "Too early!" : "\(ms) ms",
                             detail: falseStart ? "You tapped before GO"
                                                : "Waiting for the others…")
            } else {
                Button(action: { if canTap { onAction("tap", [:]) } }) {
                    ZStack {
                        Circle()
                            .fill(phase == "go" ? Color.green : Color.white.opacity(0.08))
                            .scaleEffect(phase == "go" && pulse ? 1.04 : 1.0)
                        Text(phase == "go" ? "TAP!" : "WAIT")
                            .font(.system(size: 52, weight: .heavy)).tracking(3)
                            .foregroundColor(phase == "go" ? .black : .white.opacity(0.35))
                    }
                    .padding(30)
                }
                .buttonStyle(.plain)
                .onChange(of: phase) { _ in
                    withAnimation(.easeInOut(duration: 0.25).repeatForever()) { pulse.toggle() }
                }
            }
        }
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
                Text(prompt).font(.title2.bold()).foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.top, 24)

                if phase != "answer" {
                    WaitingState(systemIcon: "chart.bar.fill", text: "Results are on the TV",
                                 detail: myAnswer.map { "You said “\($0)”" })
                } else if hasSubmitted {
                    WaitingState(systemIcon: "checkmark.circle.fill", text: "Answer locked in",
                                 detail: myAnswer.map { "“\($0)”" })
                } else {
                    Spacer()
                    AnswerField(placeholder: "Your answer", text: $answer)
                    BigButton(title: "Submit", systemImage: "paperplane.fill",
                              enabled: !answer.trimmingCharacters(in: .whitespaces).isEmpty) {
                        onAction("answer", ["text": answer])
                        answer = ""
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .onChange(of: privateData.int("round")) { newRound in
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
            if phase == "compose" {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("YOUR SECRET TITLE").font(.caption.bold()).tracking(3)
                            .foregroundColor(.white.opacity(0.4))
                        Text(myTitle ?? "…").font(.title2.bold()).foregroundColor(.yellow)
                    }
                    .padding(.top, 20)

                    if myEmoji != nil {
                        WaitingState(systemIcon: "checkmark.circle.fill", text: "Submitted",
                                     detail: myEmoji)
                    } else {
                        Text(composed.isEmpty ? "tap emoji below" : composed)
                            .font(.system(size: 40))
                            .frame(height: 60)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6),
                                  spacing: 10) {
                            ForEach(palette, id: \.self) { e in
                                Button(action: { if composed.count < 12 { composed += e } }) {
                                    Text(e).font(.system(size: 30))
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(.white.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)

                        HStack(spacing: 12) {
                            Button(action: { composed = String(composed.dropLast()) }) {
                                Image(systemName: "delete.left").font(.title2)
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.vertical, 14).padding(.horizontal, 22)
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)

                            BigButton(title: "Submit", enabled: !composed.isEmpty) {
                                onAction("submit_emoji", ["emoji": composed])
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    Spacer(minLength: 0)
                }
            } else if phase == "guess" {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(entries, id: \.index) { entry in
                            VStack(spacing: 8) {
                                Text(entry.emoji).font(.system(size: 40))
                                if entry.isMine {
                                    Text("your clue").font(.caption)
                                        .foregroundColor(.white.opacity(0.4))
                                } else {
                                    TextField("Guess the title", text: Binding(
                                        get: { guesses[entry.index] ?? "" },
                                        set: { guesses[entry.index] = $0 }))
                                        .textFieldStyle(.plain).font(.body)
                                        .foregroundColor(.white).padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10)
                                            .fill(.white.opacity(0.08)))
                                        .onSubmit {
                                            onAction("guess", ["index": entry.index,
                                                               "text": guesses[entry.index] ?? ""])
                                        }
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(.white.opacity(0.05)))
                        }
                    }
                    .padding(20)
                }
            } else {
                WaitingState(systemIcon: "party.popper.fill", text: "Reveal is on the TV")
            }
        }
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
            if phase != "fill" {
                WaitingState(systemIcon: "clipboard.fill", text: "Scoring on the TV")
            } else if hasSubmitted {
                WaitingState(systemIcon: "checkmark.circle.fill", text: "Submitted",
                             detail: "Waiting for the round to end…")
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        Text(letter)
                            .font(.system(size: 72, weight: .heavy, design: .rounded))
                            .foregroundColor(.cyan).padding(.top, 10)

                        ForEach(fields, id: \.0) { key, label, icon in
                            HStack(spacing: 12) {
                                Image(systemName: icon).foregroundColor(.cyan)
                                    .frame(width: 26)
                                TextField(label, text: Binding(
                                    get: { values[key] ?? "" },
                                    set: { values[key] = $0 }))
                                    .textFieldStyle(.plain).font(.body)
                                    .foregroundColor(.white)
                                    .autocorrectionDisabled()
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.07)))
                        }

                        BigButton(title: "Submit All", systemImage: "checkmark.circle.fill",
                                  enabled: values.values.contains { !$0.isEmpty }) {
                            onAction("submit", values)
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
                .onChange(of: privateData.int("round")) { newRound in
                    if newRound != trackedRound { trackedRound = newRound; values = [:] }
                }
            }
        }
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

    var body: some View {
        ControllerShell(title: "Antakshari",
                        subtitle: "Team \(myTeam == 0 ? "A" : "B")",
                        secondsLeft: seconds) {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("SING A SONG STARTING WITH").font(.caption.bold()).tracking(2)
                        .foregroundColor(.white.opacity(0.4))
                    Text(letter)
                        .font(.system(size: 80, weight: .heavy, design: .rounded))
                        .foregroundColor(myTeam == 0 ? .cyan : .pink)
                }
                .padding(.top, 20)

                if phase != "sing" {
                    WaitingState(systemIcon: "mic.fill", text: "Round over",
                                 detail: mySong.map { "You sang “\($0)”" })
                } else {
                    AnswerField(placeholder: "Song name", text: $song)
                    if !song.isEmpty && !valid {
                        Text("Must start with \(letter)")
                            .font(.caption).foregroundColor(.orange)
                    }
                    BigButton(title: "Sing It!", systemImage: "music.note",
                              tint: myTeam == 0 ? .cyan : .pink, enabled: valid) {
                        onAction("submit_song", ["song": song])
                        song = ""
                    }
                }
                Spacer(minLength: 0)
            }
            .onChange(of: privateData.int("round")) { newRound in
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
            VStack(spacing: 20) {
                Text(prompt)
                    .font(.title3.bold()).foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if phase == "vote" {
                    if hasVoted {
                        Label("Vote counted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(players, id: \.id) { player in
                                Button {
                                    onAction("vote", ["targetID": player.id])
                                } label: {
                                    Text(player.name)
                                        .font(.headline).foregroundColor(.white)
                                        .frame(maxWidth: .infinity, minHeight: 56)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text("Votes are in — check the TV for the reveal")
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
