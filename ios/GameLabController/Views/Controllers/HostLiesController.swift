import SwiftUI

/// Controller for The Host Is Lying. The TV does the talking; the phone shows
/// the claim, lets you press the host, and locks in Trust or Liar. A private
/// "tells I noticed" tracker is local to the phone and never sent.
/// Server side: games/native_hub/engines/host_lies.py.
struct HostLiesControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var noted: Set<String> = []

    private static let tellKeys: [String] = ["hedge", "overexplain", "repeat", "stall", "rushed"]

    private static func tellName(_ key: String) -> String {
        switch key {
        case "hedge":       return "Hedging"
        case "overexplain": return "Over-explaining"
        case "repeat":      return "Said it twice"
        case "stall":       return "Stalling"
        default:            return "Talking fast"
        }
    }

    private var phase: String { privateData.str("phase", "claim") }
    private var round: Int { privateData.int("round") }
    private var statement: String { privateData.str("statement") }
    private var defences: [[String: Any]] { privateData.dicts("defences") }
    private var myVote: String { privateData.str("myVote") }
    private var canPress: Bool { privateData.bool("canPress") }
    private var reveal: [String: Any]? { privateData["reveal"] as? [String: Any] }

    private var subtitle: String {
        switch phase {
        case "vote":   return "Trust or Liar?"
        case "grill":  return "Press the host"
        case "reveal": return "The verdict"
        default:       return "Listen closely"
        }
    }

    var body: some View {
        ControllerShell(title: "The Host Is Lying", subtitle: subtitle,
                        secondsLeft: privateData.int("secondsLeft")) {
            ScrollView {
                VStack(spacing: 14) {
                    if !statement.isEmpty && phase != "final" {
                        VStack(spacing: 8) {
                            Text(phase == "reveal" ? "THE HOST SAID" : "THE HOST SAYS")
                                .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(2)
                                .foregroundColor(PhonePlayDesign.orange)
                            Text(statement)
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface))
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }

                    switch phase {
                    case "claim":
                        WaitingState(systemIcon: "ear.fill", text: "Listen to the host",
                                     detail: "Hear how they say it, not just what they say")
                            .frame(height: 220)
                    case "grill":
                        grill
                    case "vote":
                        vote
                    case "reveal":
                        verdict
                    default:
                        WaitingState(systemIcon: "party.popper.fill", text: "Game over",
                                     detail: "Scores are on the TV")
                    }

                    if phase == "claim" || phase == "grill" || phase == "vote" {
                        notes
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .onChange(of: round) { _, _ in noted = [] }
    }

    // MARK: Grill

    private var grill: some View {
        VStack(spacing: 12) {
            if canPress {
                BigButton(title: "Press the host", systemImage: "exclamationmark.triangle.fill",
                          tint: PhonePlayDesign.orange) { onAction("press", [:]) }
            } else {
                Text(privateData.int("pressesLeft") > 0 ? "You pressed. Listen to the answer."
                                                        : "The host has been pressed enough.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            ForEach(Array(defences.enumerated()), id: \.offset) { pair in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pair.element.str("by", "Someone")) pressed")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                    Text("\"\(pair.element.str("text"))\"")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface))
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: Vote

    private var vote: some View {
        VStack(spacing: 12) {
            choice(key: "trust", title: "Trust the host", colors: [PhonePlayDesign.green, PhonePlayDesign.cyan])
            choice(key: "liar", title: "LIAR!", colors: [PhonePlayDesign.red, PhonePlayDesign.orange])
            if !myVote.isEmpty {
                Text("Locked in. Waiting for everyone...")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
        }
        .padding(.horizontal, 20)
    }

    private func choice(key: String, title: String, colors: [Color]) -> some View {
        let picked = myVote == key
        let locked = !myVote.isEmpty
        return Button {
            PhonePlayHaptics.thump()
            onAction("vote", ["side": key])
        } label: {
            Text(title)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 92)
                .background(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(picked ? PhonePlayDesign.gradient(colors)
                                 : PhonePlayDesign.gradient([PhonePlayDesign.surface, PhonePlayDesign.surface])))
                .overlay(RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(picked ? Color.white : colors[0].opacity(0.5), lineWidth: picked ? 3 : 1.5))
                .opacity(locked && !picked ? 0.4 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(locked)
    }

    // MARK: Verdict

    @ViewBuilder
    private var verdict: some View {
        if let rev = reveal {
            let isLie = rev.bool("isLie")
            let delta = rev.int("delta")
            VStack(spacing: 12) {
                Text(isLie ? "The host lied!" : "The host told the truth")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(isLie ? PhonePlayDesign.red : PhonePlayDesign.green)
                if isLie {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THE TRUTH")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                        Text(rev.str("truth"))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface))
                }
                Text(rev.str("why"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                let tells = rev.strings("tells")
                Text("Tells in this round: " + (tells.isEmpty ? "none" : tells.joined(separator: ", ")))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                Text(delta > 0 ? "+\(delta)" : (delta < 0 ? "\(delta)" : "No points"))
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(delta > 0 ? PhonePlayDesign.green
                                               : (delta < 0 ? PhonePlayDesign.red : PhonePlayDesign.text2))
            }
            .padding(.horizontal, 20)
        } else {
            WaitingState(systemIcon: "tv", text: "Look at the TV", detail: "The verdict is coming")
                .frame(height: 220)
        }
    }

    // MARK: Tell tracker

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TELLS YOU SPOT (JUST FOR YOU)")
                .font(.system(size: 12, weight: .heavy, design: .rounded)).tracking(1.5)
                .foregroundColor(PhonePlayDesign.text2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Self.tellKeys, id: \.self) { key in
                    let on = noted.contains(key)
                    Button {
                        PhonePlayHaptics.tap()
                        if on { noted.remove(key) } else { noted.insert(key) }
                    } label: {
                        Text(Self.tellName(key))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(on ? PhonePlayDesign.orange.opacity(0.35)
                                                          : PhonePlayDesign.surface))
                            .overlay(Capsule().strokeBorder(on ? PhonePlayDesign.orange : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(PhonePlayPressStyle())
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
