import SwiftUI

/// Phone controllers for the two SPOKEN games, Atlas and Antakshari.
///
/// Nobody types. The player talks or sings out loud to the room; the phone
/// only ever makes one quick tap: Next (I said it), Valid / Out!, Sang it /
/// Missed, or a letter on the 26-letter grid. Every button is sized for a
/// thumb at arm's length. The only text field is Atlas's optional spelling
/// box, which appears only when the host turns on spelling mode for kids.
///
/// Server side: games/native_hub/engines/spoken.py. `privateData["role"]`
/// says which screen to show.

// MARK: - Shared pieces

enum SpokenPhoneStyle {
    static let valid: Color = PhonePlayDesign.green
    static let out: Color = PhonePlayDesign.red
    static let alphabet: [String] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }

    /// Team colour names come from games/teams.py ("red", "blue", ...).
    static func teamColor(_ name: String, index: Int) -> Color {
        switch name.lowercased() {
        case "red": return PhonePlayDesign.red
        case "blue": return PhonePlayDesign.blue
        case "green": return PhonePlayDesign.green
        case "yellow", "gold": return PhonePlayDesign.yellow
        default: return index == 1 ? PhonePlayDesign.pink : PhonePlayDesign.cyan
        }
    }
}

/// Small all-caps label above a heading.
private struct SpokenPhoneEyebrow: View {
    let text: String
    var tint: Color = PhonePlayDesign.text3

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// The required letter, big, in a glowing disc.
struct SpokenPhoneLetterBadge: View {
    let letter: String
    let tint: Color
    var size: CGFloat = 140

    var body: some View {
        Text(letter.isEmpty ? "?" : letter)
            .font(.system(size: size * 0.56, weight: .black, design: .rounded))
            .foregroundStyle(PhonePlayDesign.gradient([Color.white, tint]))
            .frame(width: size, height: size)
            .background(
                Circle().fill(PhonePlayDesign.gradient([tint.opacity(0.3),
                                                        PhonePlayDesign.indigo.opacity(0.18)]))
            )
            .overlay(Circle().strokeBorder(tint.opacity(0.55), lineWidth: 2))
            .shadow(color: tint.opacity(0.35), radius: 18)
            .id(letter)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .phonePlayIdle(dy: 3, scale: 0.03, duration: 1.6)
    }
}

/// A full-width, extra-tall tap target: the whole point of the phone here.
struct SpokenPhoneGiantButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var height: CGFloat = 120
    var isSelected: Bool = false
    var isDimmed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            PhonePlayHaptics.thump()
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .heavy))
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient([tint, tint.opacity(0.65)]))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: 4)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .shadow(color: tint.opacity(isDimmed ? 0 : 0.4), radius: 16, y: 8)
            .opacity(isDimmed ? 0.4 : 1)
            .scaleEffect(isSelected ? 1.02 : 1)
            .animation(PhonePlayDesign.pop, value: isSelected)
        }
        .buttonStyle(PhonePlayPressStyle())
        .padding(.horizontal, 20)
    }
}

/// The 26-letter grid: one tap sets the next letter. Q, X and Z carry a
/// "skip" tag because the server swaps them for a fresh letter.
struct SpokenPhoneLetterGrid: View {
    let tint: Color
    var suggested: Set<String> = []
    var hard: Set<String> = []
    var highlighted: String = ""
    let onPick: (String) -> Void

    @State private var picked: String = ""

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(SpokenPhoneStyle.alphabet, id: \.self) { letter in
                letterButton(letter)
            }
        }
        .padding(.horizontal, 16)
    }

    private func letterButton(_ letter: String) -> some View {
        let isPicked: Bool = picked == letter
        let isHighlighted: Bool = highlighted == letter
        let isSuggested: Bool = suggested.contains(letter)
        let isHard: Bool = hard.contains(letter)
        let fill: Color = isPicked ? tint
            : (isHighlighted ? tint.opacity(0.45)
               : (isSuggested ? tint.opacity(0.16) : PhonePlayDesign.surface))
        let border: Color = isPicked || isHighlighted ? Color.white.opacity(0.8)
            : (isSuggested ? tint.opacity(0.45) : Color.white.opacity(0.06))
        return Button(action: {
            guard picked.isEmpty else { return }
            PhonePlayHaptics.thump()
            withAnimation(PhonePlayDesign.pop) { picked = letter }
            onPick(letter)
        }) {
            VStack(spacing: 0) {
                Text(letter)
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundColor(isHard && !isPicked ? PhonePlayDesign.text2 : .white)
                if isHard {
                    Text("SKIP")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundColor(PhonePlayDesign.yellow)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .strokeBorder(border, lineWidth: isPicked || isHighlighted ? 2 : 1)
            )
            .scaleEffect(isPicked ? 1.08 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!picked.isEmpty && !isPicked)
    }
}

/// Hearts for Atlas lives.
private struct SpokenPhoneLives: View {
    let lives: Int
    let maxLives: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(maxLives, 0), id: \.self) { index in
                Image(systemName: index < lives ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(index < lives ? PhonePlayDesign.red : Color.white.opacity(0.2))
            }
        }
        .animation(PhonePlayDesign.pop, value: lives)
    }
}

/// A one-line note in a soft capsule.
private struct SpokenPhoneNote: View {
    let text: String
    var systemImage: String = "info.circle.fill"
    var tint: Color = PhonePlayDesign.text2

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(tint.opacity(0.14)))
        .padding(.horizontal, 20)
    }
}

// MARK: - Atlas

struct AtlasControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var role: String { privateData.str("role", "wait") }
    private var phase: String { privateData.str("phase") }
    private var round: Int { privateData.int("round") }
    private var letter: String { privateData.str("letter") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var speakerName: String { privateData.str("speakerName", "Someone") }
    private var myVote: String { privateData.str("myVote") }
    private var lives: Int { privateData.int("lives") }
    private var maxLives: Int { privateData.int("maxLives", 3) }
    private var isPlaying: Bool { privateData.bool("isPlaying") }
    private var isOut: Bool { privateData.bool("isOut") }
    private var spelling: Bool { privateData.bool("spelling") }
    private var isHost: Bool { privateData.bool("isHost") }
    private var finished: Bool { privateData.bool("finished") }
    private var hardLetters: Set<String> { Set(privateData.strings("hardLetters")) }

    @State private var spelled: String = ""

    private let tint: Color = PhonePlayDesign.cyan

    private var subtitle: String {
        if isOut { return "You're out -- still judging" }
        if !isPlaying { return "Judging" }
        return lives == 1 ? "1 life left" : "\(lives) lives left"
    }

    /// The last letter of what the speaker spelled, highlighted on the grid.
    private var spelledLastLetter: String {
        let letters = spelled.uppercased().filter { SpokenPhoneStyle.alphabet.contains(String($0)) }
        guard let last = letters.last else { return "" }
        return String(last)
    }

    var body: some View {
        ControllerShell(title: "Atlas",
                        subtitle: subtitle,
                        secondsLeft: role == "wait" || finished ? nil : seconds) {
            VStack(spacing: 16) {
                if isPlaying && !isOut {
                    SpokenPhoneLives(lives: lives, maxLives: maxLives)
                        .padding(.top, 10)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if isHost && role != "pick" && !finished {
                    spellingToggle
                        .padding(.bottom, 10)
                }
            }
            .animation(PhonePlayDesign.pop, value: role)
            .animation(PhonePlayDesign.pop, value: letter)
            .onChange(of: round) { _, _ in spelled = "" }
        }
    }

    @ViewBuilder
    private var content: some View {
        if finished {
            WaitingState(systemIcon: "flag.checkered", text: "Game over",
                         detail: "The winner is on the TV")
        } else {
            switch role {
            case "speak": speakView
            case "judge": judgeView
            case "pick": pickView
            default: waitView
            }
        }
    }

    private var speakView: some View {
        VStack(spacing: 14) {
            SpokenPhoneEyebrow(text: "Your turn", tint: tint)
            SpokenPhoneLetterBadge(letter: letter, tint: tint, size: 150)
            Text("Say a place starting with \(letter)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Text("Out loud, to the room. They judge it.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
            Spacer(minLength: 8)
            SpokenPhoneGiantButton(title: "Next", systemImage: "checkmark",
                                   tint: SpokenPhoneStyle.valid, height: 130) {
                onAction("said", [:])
            }
            Text("Tap once you've said it")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .padding(.bottom, 8)
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var judgeView: some View {
        VStack(spacing: 14) {
            SpokenPhoneEyebrow(text: "\(speakerName) is speaking")
            HStack(spacing: 16) {
                SpokenPhoneLetterBadge(letter: letter, tint: tint, size: 92)
                Text("Did they say a real place starting with \(letter)?")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 8)
            SpokenPhoneGiantButton(title: "Valid", systemImage: "checkmark",
                                   tint: SpokenPhoneStyle.valid,
                                   isSelected: myVote == "valid",
                                   isDimmed: myVote == "out") {
                onAction("judge", ["verdict": "valid"])
            }
            SpokenPhoneGiantButton(title: "Out!", systemImage: "xmark",
                                   tint: SpokenPhoneStyle.out,
                                   isSelected: myVote == "out",
                                   isDimmed: myVote == "valid") {
                onAction("judge", ["verdict": "out"])
            }
            Text(myVote.isEmpty ? "A majority decides" : "Tap the other one to change your mind")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .padding(.bottom, 8)
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var pickView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                SpokenPhoneEyebrow(text: "Valid!", tint: SpokenPhoneStyle.valid)
                    .padding(.top, 14)
                Text("Your place ended with...")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                if spelling {
                    AnswerField(placeholder: "Spell it (optional)", text: $spelled)
                }
                SpokenPhoneLetterGrid(tint: tint,
                                      hard: hardLetters,
                                      highlighted: spelledLastLetter) { picked in
                    var payload: [String: Any] = ["letter": picked]
                    let place: String = spelled.trimmingCharacters(in: .whitespacesAndNewlines)
                    if spelling && !place.isEmpty {
                        payload["place"] = place
                    }
                    onAction("pick_letter", payload)
                    spelled = ""
                }
                .id(round)
                SpokenPhoneNote(text: "Q, X and Z skip to a new letter",
                                systemImage: "forward.fill")
                    .padding(.bottom, 12)
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var waitView: some View {
        Group {
            if phase == "letter" {
                WaitingState(systemIcon: "hand.tap.fill",
                             text: "\(speakerName) is picking the next letter",
                             detail: "Get ready -- it could be you next")
            } else {
                WaitingState(systemIcon: "hourglass",
                             text: "Next player coming up",
                             detail: "Watch the TV")
            }
        }
        .transition(.opacity)
    }

    private var spellingToggle: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            onAction("toggle_spelling", ["on": !spelling])
        }) {
            HStack(spacing: 8) {
                Image(systemName: spelling ? "textformat.abc" : "textformat")
                    .font(.system(size: 14, weight: .bold))
                Text(spelling ? "Spelling mode: on" : "Spelling mode for kids: off")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundColor(spelling ? PhonePlayDesign.yellow : PhonePlayDesign.text2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(PhonePlayDesign.surface))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

// MARK: - Antakshari

struct AntakshariControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var role: String { privateData.str("role", "wait") }
    private var phase: String { privateData.str("phase") }
    private var round: Int { privateData.int("round") }
    private var letter: String { privateData.str("letter") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var myTeam: Int { privateData.int("myTeam", -1) }
    private var myTeamName: String { privateData.str("myTeamName") }
    private var myTeamColor: String { privateData.str("myTeamColor") }
    private var singingTeamName: String { privateData.str("singingTeamName", "The other team") }
    private var target: Int { privateData.int("target", 8) }
    private var finished: Bool { privateData.bool("finished") }
    private var suggested: Set<String> { Set(privateData.strings("suggestedLetters")) }
    private var hardLetters: Set<String> { Set(privateData.strings("hardLetters")) }
    private var teamScores: [Int] {
        (privateData["teamScores"] as? [Any] ?? []).compactMap { $0 as? Int }
    }

    private var tint: Color { SpokenPhoneStyle.teamColor(myTeamColor, index: myTeam) }

    private var subtitle: String? {
        guard myTeam >= 0, !myTeamName.isEmpty else { return nil }
        let scores: [Int] = teamScores
        guard scores.count == 2 else { return myTeamName }
        let mine: Int = scores[myTeam == 1 ? 1 : 0]
        let theirs: Int = scores[myTeam == 1 ? 0 : 1]
        return "\(myTeamName)  \(mine) - \(theirs)  (first to \(target))"
    }

    var body: some View {
        ControllerShell(title: "Antakshari",
                        subtitle: subtitle,
                        secondsLeft: role == "wait" || finished ? nil : seconds) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(PhonePlayDesign.pop, value: role)
                .animation(PhonePlayDesign.pop, value: letter)
        }
    }

    @ViewBuilder
    private var content: some View {
        if finished {
            WaitingState(systemIcon: "music.note", text: "Game over",
                         detail: "The winners are on the TV")
        } else {
            switch role {
            case "sing": singView
            case "judge": judgeView
            case "pick": pickView
            default: waitView
            }
        }
    }

    private var singView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            SpokenPhoneEyebrow(text: "Your team is singing", tint: tint)
            SpokenPhoneLetterBadge(letter: letter, tint: tint, size: 170)
            Text("Sing a song starting with \(letter)")
                .font(.system(size: 25, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Image(systemName: "music.mic")
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(tint)
                .phonePlayIdle(dy: 0, scale: 0.12, duration: 0.5)
                .padding(.top, 6)
            Text("Out loud, together. The other team judges.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer(minLength: 8)
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var judgeView: some View {
        VStack(spacing: 14) {
            SpokenPhoneEyebrow(text: "\(singingTeamName) is singing")
                .padding(.top, 12)
            HStack(spacing: 16) {
                SpokenPhoneLetterBadge(letter: letter, tint: PhonePlayDesign.yellow, size: 92)
                Text("Did they sing a song starting with \(letter)?")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 8)
            SpokenPhoneGiantButton(title: "Sang it", systemImage: "music.note",
                                   tint: SpokenPhoneStyle.valid) {
                onAction("judge", ["verdict": "sang"])
            }
            SpokenPhoneGiantButton(title: "Missed", systemImage: "xmark",
                                   tint: SpokenPhoneStyle.out) {
                onAction("judge", ["verdict": "missed"])
            }
            Text("Any player on your team can call it")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .padding(.bottom, 8)
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var pickView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                SpokenPhoneEyebrow(text: "Sang it! +1", tint: SpokenPhoneStyle.valid)
                    .padding(.top, 14)
                Text("Your song ended with...")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                SpokenPhoneLetterGrid(tint: tint, suggested: suggested, hard: hardLetters) { picked in
                    onAction("pick_letter", ["letter": picked])
                }
                .id(round)
                SpokenPhoneNote(text: "Highlighted letters have lots of songs. Q, X and Z skip to a new letter.",
                                systemImage: "music.note.list")
                    .padding(.bottom, 12)
            }
        }
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private var waitView: some View {
        Group {
            if phase == "letter" {
                WaitingState(systemIcon: "hand.tap.fill",
                             text: "\(singingTeamName) is picking the next letter",
                             detail: "Start thinking of songs!")
            } else if phase == "beat" {
                WaitingState(systemIcon: "music.quarternote.3",
                             text: "Get ready",
                             detail: "\(singingTeamName) sings next. Letter \(letter).")
            } else {
                WaitingState(systemIcon: "hourglass", text: "Watch the TV")
            }
        }
        .transition(.opacity)
    }
}
