import SwiftUI

// MARK: - Shared look and socket helpers for the phone's one-stop features
//
// Profiles, Game Night and make-your-own quiz all live in this folder.
// Server side: games/profiles.py, games/game_night.py, games/ai_decks.py
// and the set_custom_questions / start_night / next_game / end_night
// handlers in games/native_hub/socket_events.py.

/// The one-stop panels (Game Night, quiz maker, profile, teams) wear the
/// Phone Play look: same dark background, party gradients, card radius,
/// press springs and haptics. These names stay so every panel keeps
/// compiling unchanged.
enum OneStopTheme {
    static let background = PhonePlayDesign.bg
    static let nightGradient = [PhonePlayDesign.purple, PhonePlayDesign.pink, PhonePlayDesign.orange]
    static let quizGradient = [PhonePlayDesign.cyan, PhonePlayDesign.blue, PhonePlayDesign.indigo]
}

/// Rounded, softly tinted card used by every one-stop panel: a Phone Play
/// surface card with a wash of `tint`.
struct OneStopCard: ViewModifier {
    var tint: Color
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .fill(PhonePlayDesign.gradient([tint.opacity(0.22), tint.opacity(0.02)]))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.12), radius: 12, y: 6)
    }
}

extension View {
    func oneStopCard(tint: Color, padding: CGFloat = 16) -> some View {
        modifier(OneStopCard(tint: tint, padding: padding))
    }
}

/// A selectable capsule (count, minutes, language pickers).
struct OneStopChip: View {
    let title: String
    let selected: Bool
    var tint: Color = PhonePlayDesign.cyan
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .foregroundColor(selected ? .black : PhonePlayDesign.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(selected ? PhonePlayDesign.gradient([tint, tint.opacity(0.75)])
                                            : PhonePlayDesign.gradient([PhonePlayDesign.surface2,
                                                                        PhonePlayDesign.surface2]))
                )
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
                .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(PhonePlayPressStyle())
        .animation(PhonePlayDesign.pop, value: selected)
    }
}

/// Big gradient call-to-action button: Phone Play's big button.
struct OneStopPrimaryButton: View {
    let title: String
    let systemImage: String
    var colors: [Color] = [PhonePlayDesign.purple, PhonePlayDesign.cyan]
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        PhonePlayBigButton(title: title, symbol: systemImage, colors: colors,
                           enabled: enabled, action: action)
    }
}

/// Quiet secondary button, Phone Play's ghost button with a tint.
struct OneStopSecondaryButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(tint.opacity(0.9))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

/// Subtle squash on press: the Phone Play spring.
struct OneStopPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Socket events

/// The phone's emits for the one-stop features. Same transport as the rest
/// of the controller (GameSocketManager.shared.emit); the server authorises
/// by socket (host phone or TV), so non-hosts never see these buttons.
enum OneStopEvents {
    static func startNight(_ payload: StartNightPayload) {
        GameSocketManager.shared.emit(.startNight, payload: payload)
    }

    static func nextGame(roomCode: String) {
        GameSocketManager.shared.emit(.nextGame, payload: RoomCodePayload(roomCode: roomCode))
    }

    static func endNight(roomCode: String) {
        GameSocketManager.shared.emit(.endNight, payload: RoomCodePayload(roomCode: roomCode))
    }

    static func setCustomQuestions(roomCode: String, questions: [QuizQuestion]) {
        GameSocketManager.shared.emit(.setCustomQuestions,
                                      payload: CustomQuestionsPayload(roomCode: roomCode, questions: questions))
    }
}
