import SwiftUI

/// Shared chrome for the phone controllers.
///
/// The existing controllers each re-derive their own header, waiting state and
/// button styling; these give the newer games one consistent look and keep each
/// controller focused on its own interaction.

// MARK: - Reading private state

/// Small helpers over the untyped `privateData` dictionary. Every controller
/// reads server state through these rather than storing it, so a new
/// `private_state` is reflected immediately instead of going stale in `@State`.
extension Dictionary where Key == String, Value == Any {
    func str(_ key: String, _ fallback: String = "") -> String {
        self[key] as? String ?? fallback
    }
    func int(_ key: String, _ fallback: Int = 0) -> Int {
        self[key] as? Int ?? fallback
    }
    func bool(_ key: String, _ fallback: Bool = false) -> Bool {
        self[key] as? Bool ?? fallback
    }
    func dbl(_ key: String, _ fallback: Double = 0) -> Double {
        self[key] as? Double ?? fallback
    }
    func strings(_ key: String) -> [String] {
        (self[key] as? [Any] ?? []).compactMap { $0 as? String }
    }
    func dicts(_ key: String) -> [[String: Any]] {
        (self[key] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }
}

// MARK: - Physical game pieces

/// The colours of objects that BOTH screens draw: a playing card's face and
/// ink. These are not Phone Play accents and they deliberately sit outside
/// the palette -- a card is off-white because cards are off-white. Every hex
/// here is the value the matching TV board uses (`TVPokerBoardView.PKTCardFace`),
/// so the same card is the same colour in your hand and on the wall; change
/// one side and change the other.
enum GamePieceColors {
    static let faceWhite = Color.white
    static let faceWhiteEdge = Color(hex: "eef0f4")
    static let cardRedInk = Color(hex: "d61f2c")
    static let cardBlackInk = Color(hex: "121826")
    static let cardBackTop = Color(hex: "1e3a8a")
    static let cardBackBottom = Color(hex: "0b1640")
}

// MARK: - Chrome
//
// Every TV-game controller is built from these pieces, so they carry the
// Phone Play look (PhonePlayDesign): the same dark backdrop, rounded heavy
// type, surface cards, gradient buttons that squash under the finger, and
// haptics. Restyling here restyles every controller at once.

struct ControllerShell<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var secondsLeft: Int? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text2)
                    }
                }
                Spacer()
                if let secondsLeft, secondsLeft > 0 {
                    ControllerTimerChip(secondsLeft: secondsLeft)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
                    .padding(.horizontal, 10)
            )
            .padding(.top, 6)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PhonePlayDesign.bg.ignoresSafeArea())
    }
}

/// The round countdown chip in the controller header: a shrinking ring that
/// turns orange, then red, in the last seconds.
struct ControllerTimerChip: View {
    let secondsLeft: Int

    private var tint: Color {
        secondsLeft <= 5 ? PhonePlayDesign.red
            : (secondsLeft <= 10 ? PhonePlayDesign.orange : PhonePlayDesign.cyan)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(1, CGFloat(secondsLeft) / 30))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(secondsLeft)")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .contentTransition(.numericText())
        }
        .frame(width: 46, height: 46)
        .animation(.easeOut(duration: 0.3), value: secondsLeft)
    }
}

struct WaitingState: View {
    let systemIcon: String
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([PhonePlayDesign.indigo.opacity(0.55),
                                                    PhonePlayDesign.cyan.opacity(0.35)]))
                    .frame(width: 110, height: 110)
                Image(systemName: systemIcon)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
            Text(text)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The primary action button. Disabled styling is deliberately obvious -- on a
/// phone held at arm's length a subtly greyed button reads as broken.
struct BigButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = PhonePlayDesign.cyan
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard enabled else { return }
            PhonePlayHaptics.tap()
            action()
        }) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 19, weight: .bold, design: .rounded))
                }
                Text(title).font(.system(size: 19, weight: .heavy, design: .rounded))
            }
            .foregroundColor(enabled ? .white : .white.opacity(0.35))
            .shadow(color: .black.opacity(enabled ? 0.25 : 0), radius: 2, y: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(enabled ? PhonePlayDesign.gradient([tint, tint.opacity(0.7)])
                                  : PhonePlayDesign.gradient([Color.white.opacity(0.08),
                                                              Color.white.opacity(0.08)]))
            )
            .shadow(color: tint.opacity(enabled ? 0.35 : 0), radius: 14, y: 6)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!enabled)
        .padding(.horizontal, 20)
    }
}

/// A labelled text field sized for thumb typing.
struct AnswerField: View {
    let placeholder: String
    @Binding var text: String
    var autocapitalize: Bool = true

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .textInputAutocapitalization(autocapitalize ? .words : .never)
            .autocorrectionDisabled()
            .padding(.horizontal, 20)
    }
}

/// A choice row used by every pick-one controller.
struct ChoiceRow: View {
    let text: String
    var detail: String? = nil
    var selected: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            PhonePlayHaptics.tap()
            action()
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(disabled ? .white.opacity(0.3) : .white)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(PhonePlayDesign.text3)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(selected ? PhonePlayDesign.green.opacity(0.16) : PhonePlayDesign.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(selected ? PhonePlayDesign.green : Color.white.opacity(0.06),
                                  lineWidth: selected ? 2 : 1)
            )
            .animation(PhonePlayDesign.pop, value: selected)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(disabled)
    }
}
