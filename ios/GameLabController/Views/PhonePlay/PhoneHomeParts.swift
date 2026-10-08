import SwiftUI

// MARK: - Home screen pieces
//
// The app's home is the Phone Play grid (PhonePlayHomeView); these are the
// bits on top of it: the wordmark bar with the profile chip, the "Play on
// TV" row that opens the join sheet, and the "Back to your TV game"
// banner.

/// Wordmark and server dot on the left, profile chip on the right.
struct PhoneHomeTopBar: View {
    @ObservedObject private var socket = GameSocketManager.shared

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Aurora Play")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [PhonePlayDesign.orange, PhonePlayDesign.pink, PhonePlayDesign.purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                HStack(spacing: 5) {
                    Circle()
                        .fill(socket.isConnected ? PhonePlayDesign.green : PhonePlayDesign.text3)
                        .frame(width: 6, height: 6)
                    Text(socket.isConnected ? "TV server online" : "Phone games work offline")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
            }
            Spacer(minLength: 8)
            ProfileChipButton()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

/// The "Play on TV" entry at the top of the home screen: one quiet row on
/// the same surface every other non-game card uses. It is the way into a
/// TV room, not the point of the app, so nothing here is louder than the
/// games below it -- no gradient, badge, glow or idle animation.
struct PhoneHomeTVEntry: View {
    let appeared: Bool
    let action: () -> Void

    var body: some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                            .fill(PhonePlayDesign.surface2)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Play on TV")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("Join a room with a code or QR")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            .phonePlaySurfaceCard(padding: 14)
        }
        .buttonStyle(PhonePlayPressStyle())
        .accessibilityLabel("Play on TV. Join a TV room.")
        .scaleEffect(appeared ? 1 : 0.96)
        .opacity(appeared ? 1 : 0)
        .animation(PhonePlayDesign.pop, value: appeared)
    }
}

/// "Back to your TV game": offered when the app went away while seated
/// in a TV room. Rejoins the same seat (the server re-attaches this
/// device's player id).
struct PhoneHomeResumeBanner: View {
    let code: String
    let onResume: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .phonePlayIdle(scale: 0.06, duration: 0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Back to your TV game")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Room \(code)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer(minLength: 4)
            Button {
                PhonePlayHaptics.tap()
                onResume()
            } label: {
                Text("Rejoin")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.green)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PhonePlayPressStyle())
            Button {
                PhonePlayHaptics.tap()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.black.opacity(0.2)))
            }
            .buttonStyle(PhonePlayPressStyle())
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                .fill(PhonePlayDesign.gradient([PhonePlayDesign.green.opacity(0.85), PhonePlayDesign.cyan.opacity(0.7)]))
        )
        .shadow(color: PhonePlayDesign.green.opacity(0.3), radius: 12, y: 6)
    }
}
