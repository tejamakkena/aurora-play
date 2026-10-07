import SwiftUI

/// "Play on TV": the join form, shown as a sheet over the Phone Play home
/// (RootControllerView). Room code, name, the QR hint and the LAN server
/// setting, in the Phone Play look.
struct JoinRoomView: View {
    let onJoin: (String, String) -> Void
    /// Dismisses the sheet.
    let onClose: () -> Void
    /// Pre-filled from an auroraplay://join/<CODE> deep link (or the last
    /// attempt, after an error).
    var initialCode: String? = nil

    /// Remembered between games so guests only type their name once.
    @AppStorage("aurora_player_name") private var savedName = ""

    // Advanced: point the app at a server on the party Wi-Fi.
    @State private var showServer = false
    @State private var serverText = ""
    @State private var serverError = false

    @State private var code = ""
    @State private var name = ""
    @State private var shakeCode = false
    @State private var appeared = false
    @FocusState private var focusedField: Field?

    // The TV app has always shown a "Server connected" / "Reconnecting"
    // dot (TVGameSelectionView); without one here there is no way for
    // someone stuck on a join to tell whether their phone's socket was
    // even connected in the first place versus a bad room code or a lost
    // server reply -- all three look identical without this.
    @ObservedObject private var socket = GameSocketManager.shared

    private enum Field { case code, name }

    private static let tvColors: [Color] = [PhonePlayDesign.cyan, PhonePlayDesign.indigo]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 22) {
                    header
                    codeCard
                    nameCard

                    PhonePlayBigButton(title: "Join Game", symbol: "arrow.right.circle.fill",
                                       colors: Self.tvColors, enabled: canJoin) {
                        attemptJoin()
                    }
                    .overlay {
                        // A disabled BigButton swallows nothing; this catches
                        // the tap so an incomplete code still shakes.
                        if !canJoin {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { attemptJoin() }
                        }
                    }

                    qrHint

                    serverSettings

                    // Build stamp -- which commit this build came from.
                    Text(BuildStamp.displayString)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(PhonePlayDesign.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onTapGesture { focusedField = nil }
        .onAppear {
            if let initialCode, code.isEmpty { code = initialCode }
            if name.isEmpty { name = savedName }
            withAnimation(PhonePlayDesign.pop) { appeared = true }
            // Code already there (deep link): straight to the name, or
            // ready to tap Join when the name is remembered too.
            if code.count < 6 {
                focusedField = .code
            } else if name.trimmingCharacters(in: .whitespaces).isEmpty {
                focusedField = .name
            }
        }
        .onChange(of: initialCode) { _, newCode in
            if let newCode { code = newCode }
        }
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button {
                PhonePlayHaptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PhonePlayPressStyle())
            .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(socket.isConnected ? PhonePlayDesign.green : PhonePlayDesign.red)
                    .frame(width: 8, height: 8)
                Text(socket.isConnected ? "Server connected" : "Reconnecting...")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.gradient(Self.tvColors))
                    .frame(width: 92, height: 92)
                    .shadow(color: PhonePlayDesign.cyan.opacity(0.4), radius: 18, y: 8)
                Image(systemName: "tv.fill")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .phonePlayIdle(dy: 3, degrees: 3, duration: 1.3)
            }
            Text("Play on TV")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [PhonePlayDesign.cyan, PhonePlayDesign.indigo, PhonePlayDesign.purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("Your phone becomes the controller")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhonePlaySectionLabel(text: "Room code")
            TextField("", text: $code)
                .placeholder(when: code.isEmpty) {
                    Text("ABC123").foregroundColor(.white.opacity(0.18))
                }
                .font(.system(size: 38, weight: .black, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .focused($focusedField, equals: .code)
                .submitLabel(.next)
                .onSubmit { focusedField = .name }
                .onChange(of: code) { _, newValue in
                    let clean = String(newValue.prefix(6).uppercased())
                    if clean != newValue { code = clean }
                    if clean.count == 6, newValue.count == 6 { PhonePlayHaptics.tap() }
                }
                .frame(height: 70)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .strokeBorder(codeBorder, lineWidth: 1.5)
                )
                .offset(x: shakeCode ? 6 : 0)
                .animation(shakeCode ? .default.repeatCount(4, autoreverses: true).speed(8) : .default,
                           value: shakeCode)
            Text("It is on the TV screen, under the QR code")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
        }
        .phonePlaySurfaceCard()
    }

    private var codeBorder: Color {
        if shakeCode { return PhonePlayDesign.red }
        if focusedField == .code { return PhonePlayDesign.cyan.opacity(0.8) }
        return Color.white.opacity(0.1)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhonePlaySectionLabel(text: "Your name")
            TextField("", text: $name)
                .placeholder(when: name.isEmpty) {
                    Text("Enter name")
                        .foregroundColor(.white.opacity(0.25))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .name)
                .submitLabel(.join)
                .onSubmit { attemptJoin() }
                .onChange(of: name) { _, newValue in
                    if newValue.count > 20 { name = String(newValue.prefix(20)) }
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .strokeBorder(focusedField == .name ? PhonePlayDesign.cyan.opacity(0.8)
                                                            : Color.white.opacity(0.1),
                                      lineWidth: 1.5)
                )
        }
        .phonePlaySurfaceCard()
    }

    /// The TV lobby shows a QR code that opens auroraplay://join/<CODE>;
    /// the iPhone Camera app scans it and lands right back in this sheet
    /// with the code filled in.
    private var qrHint: some View {
        HStack(spacing: 14) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient([PhonePlayDesign.purple, PhonePlayDesign.pink]))
                )
                .phonePlayIdle(scale: 0.05, duration: 1.2)
            VStack(alignment: .leading, spacing: 3) {
                Text("Scan the QR instead")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Point your Camera app at the QR code on the TV. The code fills in here by itself.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .phonePlaySurfaceCard()
    }

    /// Collapsed by default; only the host who runs a LAN server needs it.
    private var serverSettings: some View {
        VStack(spacing: 10) {
            Button {
                serverText = UserDefaults.standard.string(forKey: AppConstants.serverOverrideKey) ?? ""
                serverError = false
                withAnimation(PhonePlayDesign.smooth) { showServer.toggle() }
            } label: {
                Label("Server: \(AppConstants.serverURL.host ?? "?")", systemImage: "server.rack")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            }
            .buttonStyle(.plain)

            if showServer {
                VStack(spacing: 12) {
                    TextField("e.g. 192.168.1.20:5000", text: $serverText)
                        .font(.callout.monospaced())
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                .fill(PhonePlayDesign.surface2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.chipRadius, style: .continuous)
                                .strokeBorder(serverError ? PhonePlayDesign.red : Color.white.opacity(0.12),
                                              lineWidth: 1)
                        )
                    HStack(spacing: 12) {
                        PhonePlayChip(title: "Use default", selected: false,
                                      colors: [PhonePlayDesign.surface2, PhonePlayDesign.surface2]) {
                            applyServer(nil)
                        }
                        PhonePlayChip(title: "Connect", selected: true, colors: Self.tvColors) {
                            applyServer(serverText)
                        }
                    }
                }
                .phonePlaySurfaceCard()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func applyServer(_ raw: String?) {
        if let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let url = AppConstants.validServerURL(raw) else {
                serverError = true
                PhonePlayHaptics.error()
                return
            }
            UserDefaults.standard.set(url.absoluteString, forKey: AppConstants.serverOverrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppConstants.serverOverrideKey)
        }
        serverError = false
        withAnimation(PhonePlayDesign.smooth) { showServer = false }
        GameSocketManager.shared.disconnect()
        GameSocketManager.shared.connect(to: AppConstants.serverURL)
    }

    private var canJoin: Bool { code.count == 6 && !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func attemptJoin() {
        guard canJoin else { triggerShake(); return }
        focusedField = nil
        PhonePlayHaptics.success()
        onJoin(code, name.trimmingCharacters(in: .whitespaces))
    }

    private func triggerShake() {
        PhonePlayHaptics.warning()
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
