import SwiftUI

/// Never Have I Ever on the phone.
///
/// Two big buttons, and nothing on screen says what anyone else chose -- the
/// answer stays private until the TV reveals it.
struct NeverHaveIEverControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "answer") }
    private var statement: String { privateData.str("statement") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var isHost: Bool { privateData.bool("isHost") }
    private var myChoice: String? { privateData["myChoice"] as? String }
    private var packs: [[String: Any]] { privateData.dicts("packChoices") }

    var body: some View {
        ControllerShell(title: "🙋 Never Have I Ever",
                        subtitle: subtitle,
                        secondsLeft: seconds) {
            switch phase {
            case "pack":
                packPicker
            case "answer":
                answerPad
            default:
                WaitingState(icon: "👀", text: "Look at the TV",
                             detail: myChoice == "have" ? "You owned up to that one"
                                                        : "You kept it to yourself")
            }
        }
    }

    private var subtitle: String {
        switch phase {
        case "pack":   return isHost ? "Pick a pack" : "The host is picking a pack"
        case "answer": return "Answer honestly. Nobody sees until the reveal."
        default:       return "The reveal"
        }
    }

    // MARK: Pack picker (host only)

    @ViewBuilder
    private var packPicker: some View {
        if isHost {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(packs.enumerated()), id: \.offset) { _, pack in
                        PackRow(pack: pack) {
                            onAction("choose_pack", ["pack": pack["id"] as? String ?? ""])
                        }
                    }
                }
                .padding(20)
            }
        } else {
            WaitingState(icon: "🎲", text: "The host is choosing a pack",
                         detail: "Get ready to be honest")
        }
    }

    // MARK: Answer pad

    @ViewBuilder
    private var answerPad: some View {
        VStack(spacing: 22) {
            Text("Never have I ever...")
                .font(.headline).foregroundColor(.orange)
                .padding(.top, 24)
            Text(statement)
                .font(.title2.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            if let choice = myChoice {
                WaitingState(icon: choice == "have" ? "🙋" : "🙅",
                             text: choice == "have" ? "You have" : "Never",
                             detail: "Locked in. Waiting for the others...")
            } else {
                VStack(spacing: 14) {
                    NHIEAnswerButton(emoji: "🙋", title: "I have", tint: .orange) {
                        onAction("answer", ["choice": "have"])
                    }
                    NHIEAnswerButton(emoji: "🙅", title: "Never", tint: .cyan) {
                        onAction("answer", ["choice": "never"])
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

private struct NHIEAnswerButton: View {
    let emoji: String
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 44))
                Text(title).font(.title.bold())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(RoundedRectangle(cornerRadius: 22).fill(tint))
        }
        .buttonStyle(.plain)
    }
}

private struct PackRow: View {
    let pack: [String: Any]
    let action: () -> Void

    private var adult: Bool { pack["adult"] as? Bool ?? false }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(pack["emoji"] as? String ?? "🎲").font(.system(size: 36))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(pack["name"] as? String ?? "")
                            .font(.headline).foregroundColor(.white)
                        if adult {
                            Text("18+")
                                .font(.caption.bold()).foregroundColor(.black)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                    }
                    Text(pack["blurb"] as? String ?? "")
                        .font(.caption).foregroundColor(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}
