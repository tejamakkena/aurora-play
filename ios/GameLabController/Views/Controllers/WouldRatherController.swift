import SwiftUI

/// Controller for the TV game Would You Rather: tap A or B.
/// Server side: games/native_hub/engines/would_rather.py.
struct WouldRatherControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase", "vote") }
    private var a: String { privateData.str("a") }
    private var b: String { privateData.str("b") }
    private var myVote: String { privateData.str("myVote") }
    private var seconds: Int { privateData.int("secondsLeft") }

    var body: some View {
        ControllerShell(title: "Would You Rather",
                        subtitle: phase == "vote" ? "Pick a side" : "The room has split",
                        secondsLeft: seconds) {
            if phase == "vote" {
                VStack(spacing: 14) {
                    Text("Would you rather...")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                        .padding(.top, 14)
                    side(key: "a", text: a, colors: [PhonePlayDesign.blue, PhonePlayDesign.indigo])
                    Text("or")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                    side(key: "b", text: b, colors: [PhonePlayDesign.orange, PhonePlayDesign.red])
                    if !myVote.isEmpty {
                        Text("Locked in. Waiting for everyone...")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            } else {
                WaitingState(systemIcon: "tv", text: "Look at the TV",
                             detail: "Defend your side")
            }
        }
    }

    private func side(key: String, text: String, colors: [Color]) -> some View {
        let picked = myVote == key
        let locked = !myVote.isEmpty
        return Button {
            PhonePlayHaptics.tap()
            onAction("vote", ["side": key])
        } label: {
            VStack(spacing: 6) {
                Text(key.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(3)
                    .opacity(0.8)
                Text(text)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(picked ? PhonePlayDesign.gradient(colors)
                             : PhonePlayDesign.gradient([PhonePlayDesign.surface, PhonePlayDesign.surface])))
            .overlay(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .strokeBorder(picked ? Color.white : colors[0].opacity(0.5), lineWidth: picked ? 3 : 1.5))
            .opacity(locked && !picked ? 0.45 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(locked)
    }
}
