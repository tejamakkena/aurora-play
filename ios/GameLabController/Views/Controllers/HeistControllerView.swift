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
            roleBadge

            Spacer()

            if phase == .guardSets {
                guardSetPhase
            } else {
                watchingPhase
            }

            Spacer()
        }
        .background(Color(hex: "140000").ignoresSafeArea())
        // Reset per round so Guard picks cameras fresh each round
        .onChange(of: currentRound) { newRound in
            guard newRound != trackedRound else { return }
            trackedRound = newRound
            hasSubmitted = false
            activeCameras = []
        }
        .onAppear { trackedRound = currentRound }
    }

    // MARK: - Phases

    private var guardSetPhase: some View {
        VStack(spacing: 28) {
            Text("Choose cameras to activate")
                .font(.headline).foregroundColor(.white.opacity(0.6))
            Text("Max 2 cameras per round")
                .font(.caption).foregroundColor(.white.opacity(0.3))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(cameraSlots) { slot in
                    CameraToggleTile(
                        slot: slot,
                        isActive: activeCameras.contains(slot.id),
                        canActivate: activeCameras.count < 2 || activeCameras.contains(slot.id)
                    ) { toggleCamera(slot.id) }
                }
            }
            .padding(.horizontal, 24)

            Button(action: submitCameras) {
                HStack(spacing: 8) {
                    Image(systemName: hasSubmitted ? "checkmark.shield.fill" : "shield.fill")
                    Text(hasSubmitted ? "Cameras Locked" : "Lock Cameras")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(hasSubmitted ? Color.green.opacity(0.3) : Color.red.opacity(0.8)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain).disabled(hasSubmitted).padding(.horizontal, 24)
        }
    }

    private var watchingPhase: some View {
        VStack(spacing: 16) {
            Text("Cameras Active")
                .font(.title3.bold()).foregroundColor(.red)
            Text("Watching for thieves…")
                .foregroundColor(.white.opacity(0.5))

            VStack(spacing: 10) {
                ForEach(cameraSlots.filter { activeCameras.contains($0.id) }) { slot in
                    HStack {
                        Text(slot.direction).font(.title2)
                        Text(slot.label).foregroundColor(.white)
                        Spacer()
                        Text("ACTIVE").font(.caption.bold()).foregroundColor(.red)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.15)))
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    // MARK: - Subviews & helpers

    private var roleBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.fill").font(.system(size: 28)).foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("You are the Guard").font(.headline).foregroundColor(.red)
                Text("Only YOU can see camera positions").font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Text("Round \(currentRound)").font(.caption.bold()).foregroundColor(.white.opacity(0.4))
        }
        .padding(20).background(Color.red.opacity(0.1))
    }

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
            roleBadge

            Spacer()

            if isCaught {
                caughtView
            } else {
                VStack(spacing: 28) {
                    positionIndicator
                    dpad
                    statusLabel
                }
            }

            Spacer()

            cameraWarning
        }
        .background(Color(hex: "000d14").ignoresSafeArea())
        .onChange(of: currentRound) { newRound in
            guard newRound != trackedRound else { return }
            trackedRound = newRound
            hasMoved = false
        }
        .onAppear { trackedRound = currentRound }
    }

    private var positionIndicator: some View {
        HStack(spacing: 12) {
            Text("Position").foregroundColor(.white.opacity(0.5)).font(.subheadline)
            Spacer()
            Text("Col \(myPosition.col)  Row \(myPosition.row)")
                .font(.system(.body, design: .monospaced)).foregroundColor(.cyan)
            if hasReachedVault {
                Text("VAULT REACHED").font(.caption.bold()).foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 24)
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
                Label("Move sent — waiting for round end", systemImage: "hourglass")
                    .font(.subheadline).foregroundColor(.cyan.opacity(0.7))
            } else if !isMovingPhase {
                Label("Guard is setting cameras…", systemImage: "eye")
                    .font(.subheadline).foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private var caughtView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 56)).foregroundColor(.red)
            Text("You were caught!").font(.title2.bold()).foregroundColor(.red)
            Text("Watch the TV to see how it ends.").foregroundColor(.white.opacity(0.5))
        }
    }

    private var cameraWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text("Avoid red-lit tiles on the TV!")
                .font(.caption).foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 24).padding(.bottom, 32)
    }

    private var roleBadge: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill").font(.system(size: 28)).foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("You are a Thief").font(.headline).foregroundColor(.cyan)
                Text("Reach the vault, then escape").font(.caption).foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Text("Round \(currentRound)").font(.caption.bold()).foregroundColor(.white.opacity(0.4))
        }
        .padding(20).background(Color.cyan.opacity(0.08))
    }

    private func move(_ direction: String) {
        guard isMovingPhase, !hasMoved, !isCaught else { return }
        hasMoved = true
        onAction("move", ["direction": direction])
    }
}

// MARK: - Shared subviews

private struct CameraToggleTile: View {
    let slot: CameraSlot
    let isActive: Bool
    let canActivate: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 10) {
                Text(slot.direction).font(.system(size: 36))
                Text(slot.label).font(.caption).foregroundColor(isActive ? .white : .white.opacity(0.5))
                    .multilineTextAlignment(.center)
                Text(isActive ? "ACTIVE" : "OFF").font(.caption2.bold())
                    .foregroundColor(isActive ? .red : .white.opacity(0.3))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActive ? Color.red.opacity(0.25) : Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(isActive ? Color.red.opacity(0.6) : Color.white.opacity(0.08),
                                      lineWidth: isActive ? 2 : 1))
            )
        }
        .buttonStyle(.plain)
        .opacity(canActivate ? 1 : 0.4).disabled(!canActivate && !isActive)
        .scaleEffect(isActive ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

private struct DirectionButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 28, weight: .semibold))
                Text(label).font(.caption2)
            }
            .foregroundColor(.white).frame(width: 80, height: 80)
            .background(Circle().fill(Color.white.opacity(0.1))
                .overlay(Circle().strokeBorder(Color.cyan.opacity(0.3), lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}

private struct CameraSlot: Identifiable {
    let id: String
    let label: String
    let direction: String
}
