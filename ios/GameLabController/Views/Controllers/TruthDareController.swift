import SwiftUI

/// Controller for the TV game Truth or Dare.
///
/// The host phone runs the whole table: it types everyone's name (guests do
/// not need the app), picks a level, starts, then judges every card. Any other
/// phone is a read-only view, except that the player whose turn it is may pick
/// truth or dare and switch for themselves.
///
/// Server side: games/native_hub/engines/truth_dare.py.
struct TruthDareControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var draft = ""
    @State private var confirmEnd = false

    private let tint = PhonePlayDesign.pink

    private var phase: String { privateData.str("phase", "setup") }
    private var isHost: Bool { privateData.bool("isHost") }
    private var isMyTurn: Bool { privateData.bool("isMyTurn") }
    private var level: String { privateData.str("level", "family") }
    private var kind: String { privateData.str("kind") }
    private var prompt: String { privateData.str("prompt") }
    private var who: String { privateData.str("currentName") }
    private var currentID: String { privateData.str("currentID") }
    private var minPlayers: Int { max(1, privateData.int("minPlayers", 2)) }
    private var canSwitch: Bool { privateData.bool("canSwitch") && (isHost || isMyTurn) }
    private var people: [(id: String, name: String, score: Int)] {
        privateData.dicts("participants").compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return (id, name, $0["score"] as? Int ?? 0)
        }
    }

    private var levelTitle: String {
        switch level {
        case "teens":  return "Teens"
        case "adults": return "Adults"
        default:       return "Family"
        }
    }

    private var kindColor: Color {
        switch kind {
        case "truth": return PhonePlayDesign.cyan
        case "dare":  return PhonePlayDesign.orange
        default:      return PhonePlayDesign.red
        }
    }

    private var kindLabel: String {
        switch kind {
        case "truth": return "TRUTH"
        case "dare":  return "DARE"
        default:      return "PUNISHMENT"
        }
    }

    var body: some View {
        ControllerShell(title: "Truth or Dare",
                        subtitle: phase == "setup" ? "Add the players" : "\(levelTitle) level") {
            VStack(spacing: 12) {
                switch phase {
                case "setup":   setup
                case "choose":  choose
                case "prompt", "punish": card
                default:
                    WaitingState(systemIcon: "party.popper.fill", text: "Game over",
                                 detail: "Final scores are on the TV")
                }
                if phase == "choose" || phase == "prompt" || phase == "punish" {
                    scores
                    if isHost { endButton }
                }
            }
        }
        .confirmationDialog("End the game and show the scores?", isPresented: $confirmEnd,
                            titleVisibility: .visible) {
            Button("End game", role: .destructive) { onAction("end", [:]) }
            Button("Keep playing", role: .cancel) {}
        }
    }

    // MARK: Setup (host)

    @ViewBuilder
    private var setup: some View {
        if !isHost {
            WaitingState(systemIcon: "person.3.fill", text: "The host is adding players",
                         detail: "Look at the TV")
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    Text("Type a name and add it. Several names separated by commas work too.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                    HStack(spacing: 10) {
                        AnswerField(placeholder: "Player name", text: $draft)
                            .onSubmit(addDraft)
                        Button(action: addDraft) {
                            Text("Add")
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 18).padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius,
                                                             style: .continuous)
                                    .fill(draft.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? Color.white.opacity(0.1) : tint))
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.trailing, 20)
                    }

                    VStack(spacing: 8) {
                        ForEach(people, id: \.id) { person in
                            HStack {
                                Text(person.name)
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Spacer()
                                Button("Remove") {
                                    PhonePlayHaptics.tap()
                                    onAction("remove_name", ["id": person.id])
                                }
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(PhonePlayDesign.text2)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius,
                                                         style: .continuous)
                                .fill(PhonePlayDesign.surface))
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("LEVEL")
                        .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2)
                        .foregroundColor(PhonePlayDesign.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                    HStack(spacing: 8) {
                        ForEach([("family", "Family", "All ages"),
                                 ("teens", "Teens", "Cheeky"),
                                 ("adults", "Adults", "Party")], id: \.0) { item in
                            Button {
                                PhonePlayHaptics.tap()
                                onAction("set_level", ["level": item.0])
                            } label: {
                                VStack(spacing: 2) {
                                    Text(item.1).font(.system(size: 16, weight: .heavy, design: .rounded))
                                    Text(item.2).font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(PhonePlayDesign.text2)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius,
                                                             style: .continuous)
                                    .fill(level == item.0 ? tint.opacity(0.3) : PhonePlayDesign.surface))
                                .overlay(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius,
                                                          style: .continuous)
                                    .strokeBorder(level == item.0 ? tint : Color.clear, lineWidth: 1.5))
                            }
                            .buttonStyle(PhonePlayPressStyle())
                        }
                    }
                    .padding(.horizontal, 20)

                    BigButton(title: people.count >= minPlayers ? "Start game"
                                                                : "Add at least \(minPlayers) players",
                              systemImage: "play.fill", tint: tint,
                              enabled: people.count >= minPlayers) {
                        onAction("start_play", [:])
                    }
                    BigButton(title: "End game", systemImage: "xmark.circle.fill",
                              tint: PhonePlayDesign.surface2) { confirmEnd = true }
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private func addDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        onAction("add_names", ["names": text])
    }

    // MARK: Choose

    private var choose: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(who)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(isHost || isMyTurn ? "Truth or dare?" : "is choosing: truth or dare?")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
            if isHost || isMyTurn {
                BigButton(title: "Truth", systemImage: "bubble.left.and.bubble.right.fill",
                          tint: PhonePlayDesign.cyan) { onAction("choose", ["kind": "truth"]) }
                BigButton(title: "Dare", systemImage: "flame.fill",
                          tint: PhonePlayDesign.orange) { onAction("choose", ["kind": "dare"]) }
            }
            Spacer()
        }
    }

    // MARK: Card

    private var card: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(who)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 8)
                VStack(spacing: 8) {
                    Text(kindLabel)
                        .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                        .foregroundColor(kindColor)
                    Text(prompt)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface))
                .overlay(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(kindColor.opacity(0.5), lineWidth: 1))
                .padding(.horizontal, 20)

                if isHost {
                    if phase == "punish" {
                        BigButton(title: "Did the punishment", systemImage: "checkmark.circle.fill",
                                  tint: PhonePlayDesign.green) { onAction("done", [:]) }
                        BigButton(title: "Refused (-2)", systemImage: "xmark.circle.fill",
                                  tint: PhonePlayDesign.red) { onAction("skip", [:]) }
                    } else {
                        BigButton(title: kind == "truth" ? "Told the truth (+1)" : "Did the dare (+2)",
                                  systemImage: "checkmark.circle.fill",
                                  tint: PhonePlayDesign.green) { onAction("done", [:]) }
                        if kind == "truth" {
                            BigButton(title: "Caught lying", systemImage: "exclamationmark.triangle.fill",
                                      tint: PhonePlayDesign.red) { onAction("caught", [:]) }
                        }
                        BigButton(title: "Skip (-1)", systemImage: "forward.fill",
                                  tint: PhonePlayDesign.surface2) { onAction("skip", [:]) }
                    }
                } else {
                    Text("The host judges this one")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }
                if canSwitch {
                    BigButton(title: kind == "truth" ? "Switch to a dare" : "Switch to a truth",
                              systemImage: "arrow.left.arrow.right",
                              tint: PhonePlayDesign.purple) { onAction("switch", [:]) }
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: Scores and end

    private var scores: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(people, id: \.id) { person in
                    HStack(spacing: 6) {
                        Text(person.name).font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("\(person.score)").font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(tint)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(person.id == currentID ? tint.opacity(0.3)
                                                                       : PhonePlayDesign.surface))
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 40)
    }

    private var endButton: some View {
        Button { confirmEnd = true } label: {
            Label("End game", systemImage: "xmark.circle.fill")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .buttonStyle(PhonePlayPressStyle())
        .padding(.bottom, 12)
    }
}
