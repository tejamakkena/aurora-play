import SwiftUI

/// Controller for Never Have I Ever: two big buttons, I have or Never. Nothing
/// on screen says what anyone else chose; the answer stays private until the TV
/// reveals it. Server side: games/native_hub/engines/never_have_i_ever.py.
struct NeverHaveIEverControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "answer") }
    private var statement: String { privateData.str("statement") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var isHost: Bool { privateData.bool("isHost") }
    private var myChoice: String { privateData.str("myChoice") }
    private var packs: [[String: Any]] { privateData.dicts("packChoices") }

    private var subtitle: String {
        switch phase {
        case "pack": return isHost ? "Pick a pack" : "The host is picking a pack"
        case "answer": return "Answer honestly. Nobody sees until the reveal."
        default: return "The reveal"
        }
    }

    var body: some View {
        ControllerShell(title: "Never Have I Ever", subtitle: subtitle,
                        secondsLeft: phase == "reveal" ? nil : seconds) {
            switch phase {
            case "pack":
                packPicker
            case "answer":
                answerPad
            default:
                WaitingState(systemIcon: "tv", text: "Look at the TV",
                             detail: myChoice == "have" ? "You owned up to that one"
                                                        : "You kept it to yourself")
            }
        }
    }

    @ViewBuilder
    private var packPicker: some View {
        if isHost {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(packs.enumerated()), id: \.offset) { _, pack in
                        packRow(pack)
                    }
                }
                .padding(20)
            }
        } else {
            WaitingState(systemIcon: "shuffle", text: "The host is choosing a pack",
                         detail: "Get ready to be honest")
        }
    }

    private func packRow(_ pack: [String: Any]) -> some View {
        let adult = pack["adult"] as? Bool ?? false
        return Button {
            PhonePlayHaptics.tap()
            onAction("choose_pack", ["pack": pack["id"] as? String ?? ""])
        } label: {
            HStack(spacing: 14) {
                Image(systemName: pack["symbol"] as? String ?? "questionmark")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(adult ? PhonePlayDesign.orange : PhonePlayDesign.cyan)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(pack["name"] as? String ?? "")
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        if adult {
                            Text("18+")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(PhonePlayDesign.orange))
                        }
                    }
                    Text(pack["blurb"] as? String ?? "")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface))
        }
        .buttonStyle(PhonePlayPressStyle())
    }

    @ViewBuilder
    private var answerPad: some View {
        VStack(spacing: 18) {
            Text("Never have I ever...")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.orange)
                .padding(.top, 20)
            Text(statement)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 24)
            Spacer(minLength: 0)
            if myChoice.isEmpty {
                VStack(spacing: 14) {
                    answerButton("I have", symbol: "hand.raised.fill", tint: PhonePlayDesign.orange, choice: "have")
                    answerButton("Never", symbol: "hand.thumbsdown.fill", tint: PhonePlayDesign.cyan, choice: "never")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            } else {
                WaitingState(systemIcon: "checkmark.circle.fill",
                             text: myChoice == "have" ? "You have" : "Never",
                             detail: "Locked in. Waiting for the others...")
            }
        }
    }

    private func answerButton(_ title: String, symbol: String, tint: Color, choice: String) -> some View {
        Button {
            PhonePlayHaptics.tap()
            onAction("answer", ["choice": choice])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(title).font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous).fill(tint))
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}
