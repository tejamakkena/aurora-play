import SwiftUI

// MARK: - Shared look and socket helpers for the phone's one-stop features
//
// Profiles, Game Night and make-your-own quiz all live in this folder.
// Server side: games/profiles.py, games/game_night.py, games/ai_decks.py
// and the set_custom_questions / start_night / next_game / end_night
// handlers in games/native_hub/socket_events.py.

enum OneStopTheme {
    static let background = Color(hex: "0a0a14")
    static let nightGradient = [Color.purple, Color.pink, Color.orange]
    static let quizGradient = [Color.cyan, Color.blue, Color.purple]
}

/// Rounded, softly tinted card used by every one-stop panel.
struct OneStopCard: ViewModifier {
    var tint: Color
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.20), Color.white.opacity(0.04)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
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
    var tint: Color = .cyan
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(selected ? .black : .white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(selected ? tint : Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

/// Big gradient call-to-action button.
struct OneStopPrimaryButton: View {
    let title: String
    let systemImage: String
    var colors: [Color] = [.purple, .cyan]
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: enabled ? colors : [Color.white.opacity(0.12), Color.white.opacity(0.08)],
                                             startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: (colors.first ?? .purple).opacity(enabled ? 0.35 : 0), radius: 10, y: 4)
        }
        .buttonStyle(OneStopPressStyle())
        .disabled(!enabled)
    }
}

/// Quiet outlined secondary button.
struct OneStopSecondaryButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                )
        }
        .buttonStyle(OneStopPressStyle())
    }
}

/// Subtle squash on press.
struct OneStopPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
