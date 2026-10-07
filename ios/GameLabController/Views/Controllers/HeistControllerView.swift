import SwiftUI

/// Heist phone controller — completely different UI for Guard vs Thief.
struct HeistControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var role: HeistRole {
        (privateData["role"] as? String) == "guard" ? .guard : .thief
    }

    var body: some View {
        switch role {
        case .guard:
            GuardControllerView(privateData: privateData, onAction: onAction)
        case .thief:
            ThiefControllerView(privateData: privateData, onAction: onAction)
        }
    }
}

// MARK: - Guard Controller

private struct GuardControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    // User interaction state — must persist across re-renders
    @State private var activeCameras: Set<String> = []
    @State private var hasSubmitted = false
    @State private var trackedRound = 0

    // Derived from privateData — automatically reflects server updates
    private var phase: HeistPhase {
        HeistPhase(rawValue: privateData["phase"] as? String ?? "") ?? .guardSets
    }
    private var currentRound: Int { privateData["round"] as? Int ?? 0 }

    private var cameraSlots: [CameraSlot] {
        let raw = privateData["cameraSlots"] as? [[String: Any]] ?? defaultSlots
        return raw.compactMap { d -> CameraSlot? in
            guard let id  = d["id"]  as? String,
                  let lbl = d["label"] as? String,
                  let dir = d["direction"] as? String else { return nil }
            return CameraSlot(id: id, label: lbl, direction: dir)
        }
    }

    private var defaultSlots: [[String: Any]] {[
        ["id": "cam_tl", "label": "Top Left",     "direction": "↘"],
        ["id": "cam_tr", "label": "Top Right",    "direction": "↙"],
        ["id": "cam_bl", "label": "Bottom Left",  "direction": "↗"],
        ["id": "cam_br", "label": "Bottom Right", "direction": "↖"],
    ]}

    var body: some View {
        VStack(spacing: 0) {
            HeistHeader(symbol: "shield.fill",
                        title: "You are the Guard",
                        detail: "Only YOU can see camera positions",
                        tint: PhonePlayDesign.red,
                        round: currentRound)

            Spacer()

            if phase == .guardSets {
                guardSetPhase
                    .transition(.opacity)
            } else {
                watchingPhase
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            Spacer()
        }
        .background(HeistBackdrop(tint: PhonePlayDesign.red))
        .animation(PhonePlayDesign.pop, value: phase)
        .animation(PhonePlayDesign.pop, value: hasSubmitted)
        // Reset per round so Guard picks cameras fresh each round
        .onChange(of: currentRound) { _, newRound in
            guard newRound != trackedRound else { return }
            trackedRound = newRound
            hasSubmitted = false
            activeCameras = []
        }
        .onAppear { trackedRound = currentRound }
    }

    // MARK: - Phases

    private var guardSetPhase: some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text("Choose cameras to activate")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("Max 2 cameras per round · \(activeCameras.count)/2")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                      spacing: 14) {
                ForEach(cameraSlots) { slot in
                    CameraToggleTile(
                        slot: slot,
                        isActive: activeCameras.contains(slot.id),
                        canActivate: activeCameras.count < 2 || activeCameras.contains(slot.id)
                    ) { toggleCamera(slot.id) }
                }
            }
            .padding(.horizontal, 20)

            if hasSubmitted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("Cameras Locked")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                }
                .foregroundColor(PhonePlayDesign.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.green.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .strokeBorder(PhonePlayDesign.green.opacity(0.5), lineWidth: 1.5)
                )
                .padding(.horizontal, 20)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                BigButton(title: "Lock Cameras", systemImage: "shield.fill", tint: PhonePlayDesign.red) {
                    submitCameras()
                }
                .transition(.opacity)
            }
        }
    }

    private var watchingPhase: some View {
        let active: [CameraSlot] = cameraSlots.filter { activeCameras.contains($0.id) }
        return VStack(spacing: 16) {
            HeistHero(systemImage: "video.fill", tint: PhonePlayDesign.red)
            Text("Cameras Active")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.red)
            Text("Watching for thieves…")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)

            VStack(spacing: 10) {
                if active.isEmpty {
                    Text("No cameras switched on this round")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                }
                ForEach(active) { slot in
                    HStack(spacing: 12) {
                        Text(slot.direction)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(slot.label)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(PhonePlayDesign.red)
                                .frame(width: 8, height: 8)
                            Text("ACTIVE")
                        }
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(PhonePlayDesign.red)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(PhonePlayDesign.red.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .strokeBorder(PhonePlayDesign.red.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func toggleCamera(_ id: String) {
        if activeCameras.contains(id) { activeCameras.remove(id) }
        else if activeCameras.count < 2 { activeCameras.insert(id) }
    }

    private func submitCameras() {
        guard !hasSubmitted else { return }
        hasSubmitted = true
        onAction("set_cameras", ["cameras": Array(activeCameras)])
    }
}

// MARK: - Thief Controller

private struct ThiefControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    @State private var hasMoved = false
    @State private var trackedRound = 0

    private var phase: HeistPhase {
        HeistPhase(rawValue: privateData["phase"] as? String ?? "") ?? .guardSets
    }
    private var myPosition: GridPos {
        GridPos(
            col: privateData["col"] as? Int ?? 1,
            row: privateData["row"] as? Int ?? 1
        )
    }
    private var currentRound: Int { privateData["round"] as? Int ?? 0 }
    private var isMovingPhase: Bool { phase == .thievesMove }
    private var hasReachedVault: Bool { privateData["hasReachedVault"] as? Bool ?? false }
    private var isCaught: Bool { privateData["isCaught"] as? Bool ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HeistHeader(symbol: "person.fill",
                        title: "You are a Thief",
                        detail: "Reach the vault, then escape",
                        tint: PhonePlayDesign.cyan,
                        round: currentRound)

            Spacer()

            if isCaught {
                caughtView
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            } else {
                VStack(spacing: 24) {
                    positionIndicator
                    dpad
                    statusLabel
                }
                .transition(.opacity)
            }

            Spacer()

            cameraWarning
        }
        .background(HeistBackdrop(tint: PhonePlayDesign.cyan))
        .animation(PhonePlayDesign.pop, value: isCaught)
        .animation(PhonePlayDesign.pop, value: hasMoved)
        .animation(PhonePlayDesign.pop, value: isMovingPhase)
        .animation(PhonePlayDesign.pop, value: hasReachedVault)
        .onChange(of: currentRound) { _, newRound in
            guard newRound != trackedRound else { return }
            trackedRound = newRound
            hasMoved = false
        }
        .onAppear { trackedRound = currentRound }
    }

    private var positionIndicator: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.cyan)
                Text("Position")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                Spacer()
                Text("Col \(myPosition.col)  Row \(myPosition.row)")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundColor(PhonePlayDesign.cyan)
                    .contentTransition(.numericText())
            }
            if hasReachedVault {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                    Text("VAULT REACHED")
                        .tracking(1)
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(PhonePlayDesign.yellow))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
        .padding(.horizontal, 20)
    }

    private var dpad: some View {
        VStack(spacing: 14) {
            DirectionButton(symbol: "arrow.up",    label: "Up")    { move("up") }
            HStack(spacing: 48) {
                DirectionButton(symbol: "arrow.left",  label: "Left")  { move("left") }
                DirectionButton(symbol: "arrow.right", label: "Right") { move("right") }
            }
            DirectionButton(symbol: "arrow.down",  label: "Down")  { move("down") }
        }
        .opacity(isMovingPhase && !hasMoved ? 1 : 0.3)
        .disabled(!isMovingPhase || hasMoved)
    }

    private var statusLabel: some View {
        Group {
            if hasMoved {
                HeistPill(text: "Move sent — waiting for round end", systemImage: "hourglass",
                          tint: PhonePlayDesign.cyan)
            } else if !isMovingPhase {
                HeistPill(text: "Guard is setting cameras…", systemImage: "eye")
            }
        }
    }

    private var caughtView: some View {
        VStack(spacing: 16) {
            HeistHero(systemImage: "exclamationmark.triangle.fill", tint: PhonePlayDesign.red)
            Text("You were caught!")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundColor(PhonePlayDesign.red)
            Text("Watch the TV to see how it ends.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
    }

    private var cameraWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.yellow)
            Text("Avoid red-lit tiles on the TV!")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Capsule().fill(PhonePlayDesign.yellow.opacity(0.1)))
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func move(_ direction: String) {
        guard isMovingPhase, !hasMoved, !isCaught else { return }
        hasMoved = true
        onAction("move", ["direction": direction])
    }
}

// MARK: - Shared subviews

/// The role card at the top of both screens, in the ControllerShell style.
private struct HeistHeader: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let round: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(PhonePlayDesign.gradient([tint.opacity(0.75), tint.opacity(0.3)]))
                    .frame(width: 48, height: 48)
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .phonePlayIdle(dy: 2, scale: 0.03, duration: 1.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text("Round \(round)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(tint.opacity(0.15)))
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
                .padding(.horizontal, 10)
        )
        .padding(.top, 6)
    }
}

/// The Phone Play backdrop with a faint wash of the role colour.
private struct HeistBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            PhonePlayDesign.bg
            LinearGradient(colors: [tint.opacity(0.14), Color.clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

/// The big gently-bobbing icon for "watching" and "caught".
private struct HeistHero: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(PhonePlayDesign.gradient([tint.opacity(0.6), tint.opacity(0.25)]))
                .frame(width: 110, height: 110)
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .shadow(color: tint.opacity(0.35), radius: 18, y: 8)
        .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
    }
}

/// A rounded status capsule.
private struct HeistPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = PhonePlayDesign.text2

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(tint.opacity(0.14)))
        .padding(.horizontal, 20)
    }
}

private struct CameraToggleTile: View {
    let slot: CameraSlot
    let isActive: Bool
    let canActivate: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            onToggle()
        }) {
            VStack(spacing: 10) {
                Text(slot.direction)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(isActive ? .white : .white.opacity(0.6))
                Text(slot.label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(isActive ? .white : PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                Text(isActive ? "ACTIVE" : "OFF")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundColor(isActive ? .white : PhonePlayDesign.text3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(isActive ? PhonePlayDesign.red : Color.white.opacity(0.05)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(isActive
                          ? PhonePlayDesign.gradient([PhonePlayDesign.red.opacity(0.38), PhonePlayDesign.red.opacity(0.14)])
                          : PhonePlayDesign.gradient([PhonePlayDesign.surface, PhonePlayDesign.surface]))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .strokeBorder(isActive ? PhonePlayDesign.red.opacity(0.7) : Color.white.opacity(0.06),
                                  lineWidth: isActive ? 2 : 1)
            )
            .shadow(color: PhonePlayDesign.red.opacity(isActive ? 0.3 : 0), radius: 12, y: 5)
        }
        .buttonStyle(PhonePlayPressStyle())
        .opacity(canActivate ? 1 : 0.4).disabled(!canActivate && !isActive)
        .scaleEffect(isActive ? 1.04 : 1.0)
        .animation(PhonePlayDesign.pop, value: isActive)
    }
}

private struct DirectionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(label)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            .foregroundColor(.white)
            .frame(width: 84, height: 84)
            .background(
                Circle().fill(PhonePlayDesign.gradient([PhonePlayDesign.surface2, PhonePlayDesign.surface]))
                    .overlay(Circle().strokeBorder(PhonePlayDesign.cyan.opacity(0.35), lineWidth: 1.5))
            )
            .shadow(color: PhonePlayDesign.cyan.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

private struct CameraSlot: Identifiable {
    let id: String
    let label: String
    let direction: String
}
