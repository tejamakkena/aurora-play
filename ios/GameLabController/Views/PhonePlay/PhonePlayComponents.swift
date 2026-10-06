import SwiftUI

// MARK: - Shared Phone Play building blocks

/// Squashes a little under the finger and springs back.
struct PhonePlayPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Back chevron plus a centred title, used on every Phone Play screen.
struct PhonePlayTopBar: View {
    let title: String
    let backTitle: String
    let onBack: () -> Void
    var trailing: AnyView? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                        Text(backTitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PhonePlayPressStyle())
                Spacer()
                if let extra = trailing {
                    extra
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// The big gradient call-to-action.
struct PhonePlayBigButton: View {
    let title: String
    let symbol: String
    let colors: [Color]
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            guard enabled else { return }
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
            }
            .foregroundColor(enabled ? .white : .white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(enabled ? PhonePlayDesign.gradient(colors)
                                  : PhonePlayDesign.gradient([Color.white.opacity(0.08),
                                                              Color.white.opacity(0.08)]))
            )
            .shadow(color: (colors.first ?? .clear).opacity(enabled ? 0.35 : 0), radius: 14, y: 6)
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(!enabled)
    }
}

/// A quieter secondary button.
struct PhonePlayGhostButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

/// Small rounded label used for section headings.
struct PhonePlaySectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundColor(PhonePlayDesign.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card flip

/// Two faces on one card. `angle` 0 shows the front, 180 the back; the
/// faces swap at 90 degrees so neither is ever drawn mirrored.
struct PhonePlayFlip<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showBack: Bool = angle >= 90
        return ZStack {
            front
                .opacity(showBack ? 0 : 1)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

// MARK: - Tap-and-hold to reveal

/// Hold a finger on the card to flip it and see the secret; let go and it
/// flips back. `onRevealed` fires the first time it is held.
struct HoldToRevealCard<Secret: View>: View {
    let accent: Color
    let prompt: String
    let onRevealed: () -> Void
    let secret: Secret

    @State private var holding: Bool = false

    init(accent: Color, prompt: String = "Hold to reveal",
         onRevealed: @escaping () -> Void, @ViewBuilder secret: () -> Secret) {
        self.accent = accent
        self.prompt = prompt
        self.onRevealed = onRevealed
        self.secret = secret()
    }

    var body: some View {
        PhonePlayFlip(angle: holding ? 180 : 0, front: frontFace, back: backFace)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !holding {
                            holding = true
                            PhonePlayHaptics.rigid()
                            onRevealed()
                        }
                    }
                    .onEnded { _ in
                        holding = false
                    }
            )
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: holding)
    }

    private var frontFace: some View {
        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
            .fill(PhonePlayDesign.gradient([accent.opacity(0.9), accent.opacity(0.45)]))
            .overlay(
                VStack(spacing: 16) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundColor(.white)
                        .symbolEffect(.pulse, options: .repeating)
                    Text(prompt)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("Keep it hidden from everyone else")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(24)
            )
            .shadow(color: accent.opacity(0.4), radius: 20, y: 10)
    }

    private var backFace: some View {
        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
            .fill(PhonePlayDesign.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.7), lineWidth: 2)
            )
            .overlay(secret.padding(24))
    }
}

// MARK: - Pass the phone, then reveal

/// "Pass to NAME" -> "I'm NAME" -> hold to reveal -> "Hide and pass on".
/// The caller should give this view `.id(index)` so its state resets for
/// every player.
struct PassAndRevealView<Secret: View>: View {
    let name: String
    let index: Int
    let total: Int
    let accent: Color
    let doneTitle: String
    let onDone: () -> Void
    let secret: Secret

    @State private var confirmed: Bool = false
    @State private var peeked: Bool = false

    init(name: String, index: Int, total: Int, accent: Color,
         doneTitle: String = "Hide it and pass on",
         onDone: @escaping () -> Void, @ViewBuilder secret: () -> Secret) {
        self.name = name
        self.index = index
        self.total = total
        self.accent = accent
        self.doneTitle = doneTitle
        self.onDone = onDone
        self.secret = secret()
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("PLAYER \(index + 1) OF \(total)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)

            if confirmed {
                revealStep
                    .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity),
                                            removal: .opacity))
            } else {
                passStep
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .animation(PhonePlayDesign.pop, value: confirmed)
        .animation(PhonePlayDesign.pop, value: peeked)
    }

    private var passStep: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 10)
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(PhonePlayDesign.gradient([accent, .white]))
                .phaseAnimator([false, true]) { content, phase in
                    content.offset(x: phase ? 10 : -10)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
            VStack(spacing: 6) {
                Text("Pass the phone to")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                Text(name)
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            Spacer(minLength: 10)
            PhonePlayBigButton(title: "I am \(name)", symbol: "hand.raised.fill",
                               colors: [accent, accent.opacity(0.6)]) {
                confirmed = true
            }
        }
    }

    private var revealStep: some View {
        VStack(spacing: 24) {
            Text(name)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HoldToRevealCard(accent: accent, onRevealed: { peeked = true }) {
                secret
            }
            if peeked {
                PhonePlayBigButton(title: doneTitle, symbol: "eye.slash.fill",
                                   colors: [PhonePlayDesign.surface2, PhonePlayDesign.surface2]) {
                    onDone()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Only \(name) should be looking")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
        }
    }
}

// MARK: - Player names editor

/// Add, remove and reorder-free list of names, clamped to `range`.
struct PhonePlayNamesEditor: View {
    @Binding var names: [String]
    let range: ClosedRange<Int>
    let accent: Color

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                PhonePlaySectionLabel(text: "Players")
                Text("\(names.count) / \(range.upperBound)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(names.count >= range.lowerBound ? accent : PhonePlayDesign.text3)
            }

            ForEach(Array(names.enumerated()), id: \.offset) { pair in
                nameRow(index: pair.offset, name: pair.element)
            }

            if names.count < range.upperBound {
                addRow
            }

            if names.count < range.lowerBound {
                Text("Add at least \(range.lowerBound) players")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(PhonePlayDesign.smooth, value: names)
    }

    private func nameRow(index: Int, name: String) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 30, height: 30)
                .background(Circle().fill(accent))
            Text(name)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
            Button {
                PhonePlayHaptics.tap()
                remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(PhonePlayDesign.surface))
        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)))
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("", text: $draft)
                .placeholder(when: draft.isEmpty) {
                    Text("Add a name")
                        .foregroundColor(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { add() }
                .onChange(of: draft) { _, newValue in
                    if newValue.count > 16 { draft = String(newValue.prefix(16)) }
                }
            Button {
                add()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(canAdd ? accent : .white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        let name = trimmedDraft
        guard !name.isEmpty, names.count < range.upperBound else { return false }
        return !names.contains(where: { $0.lowercased() == name.lowercased() })
    }

    private func add() {
        guard canAdd else { return }
        PhonePlayHaptics.tap()
        names.append(trimmedDraft)
        draft = ""
        focused = true
    }

    private func remove(at index: Int) {
        guard names.indices.contains(index) else { return }
        names.remove(at: index)
    }
}

// MARK: - Time formatting

enum PhonePlayTime {
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
