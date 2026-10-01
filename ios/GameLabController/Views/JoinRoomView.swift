import SwiftUI

struct JoinRoomView: View {
    let onJoin: (String, String) -> Void
    /// Pre-filled from an auroraplay://join/<CODE> deep link.
    var initialCode: String? = nil

    /// Remembered between games so guests only type their name once.
    @AppStorage("aurora_player_name") private var savedName = ""

    @State private var code = ""
    @State private var name = ""
    @State private var shakeCode = false
    @FocusState private var focusedField: Field?

    // The TV app has always shown a "Server connected" / "Reconnecting…"
    // dot (TVGameSelectionView); this app never has, so there was no way
    // for someone stuck on a join to tell whether their phone's socket
    // was even connected in the first place versus a bad room code or a
    // lost server reply -- all three look identical without this.
    @ObservedObject private var socket = GameSocketManager.shared

    private enum Field { case code, name }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                // Logo
                VStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 64)).foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 64))
                    Text("Aurora Play")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .cyan],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Text("Your phone is the controller")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))

                    HStack(spacing: 6) {
                        Circle()
                            .fill(socket.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(socket.isConnected ? "Server connected" : "Reconnecting…")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 60)

                // Input fields
                VStack(spacing: 16) {
                    // Room code — large, prominent
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room Code")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)

                        TextField("", text: $code)
                            .placeholder(when: code.isEmpty) {
                                Text("ABC123").foregroundColor(.white.opacity(0.2))
                            }
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .code)
                            .onChange(of: code) { code = String($0.prefix(6).uppercased()) }
                            .frame(height: 64)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(
                                                shakeCode ? Color.red : Color.white.opacity(0.1),
                                                lineWidth: 1.5
                                            )
                                    )
                            )
                            .offset(x: shakeCode ? 6 : 0)
                            .animation(shakeCode ? .default.repeatCount(4, autoreverses: true).speed(8) : .default,
                                       value: shakeCode)
                    }

                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Name")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)

                        TextField("", text: $name)
                            .placeholder(when: name.isEmpty) {
                                Text("Enter name").foregroundColor(.white.opacity(0.2))
                            }
                            .font(.title3)
                            .foregroundColor(.white)
                            .focused($focusedField, equals: .name)
                            .onChange(of: name) { name = String($0.prefix(20)) }
                            .frame(height: 54)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1.5)
                                    )
                            )
                    }
                }
                .padding(.horizontal, 32)

                // Join button
                Button(action: attemptJoin) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Join Game")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                canJoin
                                ? LinearGradient(colors: [.purple, .cyan],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.white.opacity(0.1)],
                                                 startPoint: .leading, endPoint: .trailing)
                            )
                    )
                    .foregroundColor(canJoin ? .white : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canJoin)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .onTapGesture { focusedField = nil }
        .onAppear {
            if let initialCode, code.isEmpty { code = initialCode }
            if name.isEmpty { name = savedName }
        }
        .onChange(of: initialCode) { newCode in
            if let newCode { code = newCode }
        }
    }

    private var canJoin: Bool { code.count == 6 && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func attemptJoin() {
        guard canJoin else { triggerShake(); return }
        onJoin(code, name.trimmingCharacters(in: .whitespaces))
    }

    private func triggerShake() {
        shakeCode = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { shakeCode = false }
    }
}

// MARK: - Placeholder helper

extension View {
    func placeholder<C: View>(when show: Bool, @ViewBuilder placeholder: () -> C) -> some View {
        ZStack(alignment: .center) {
            if show { placeholder() }
            self
        }
    }
}
