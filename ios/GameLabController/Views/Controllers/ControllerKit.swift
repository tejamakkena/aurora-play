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

// MARK: - Chrome

struct ControllerShell<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var secondsLeft: Int? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle).font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                if let secondsLeft, secondsLeft > 0 {
                    Text("\(secondsLeft)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(secondsLeft <= 5 ? .red : .cyan)
                        .contentTransition(.numericText())
                        .animation(.default, value: secondsLeft)
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.04))

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: "00040d").ignoresSafeArea())
    }
}

struct WaitingState: View {
    let systemIcon: String
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemIcon).font(.system(size: 56)).foregroundColor(.white.opacity(0.75))
            Text(text).font(.title3.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.subheadline)
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The primary action button. Disabled styling is deliberately obvious — on a
/// phone held at arm's length a subtly greyed button reads as broken.
struct BigButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .cyan
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if enabled { action() } }) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(.headline.bold())
            }
            .foregroundColor(enabled ? .black : .white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(enabled ? tint : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
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
            .font(.title3)
            .foregroundColor(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.15), lineWidth: 1))
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
        Button(action: { if !disabled { action() } }) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(text).font(.headline)
                        .foregroundColor(disabled ? .white.opacity(0.3) : .white)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail).font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundColor(.cyan) }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.cyan : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
