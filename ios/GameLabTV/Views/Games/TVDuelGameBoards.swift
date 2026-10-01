import SwiftUI
import SceneKit
import UIKit

/// Boards for the duel and co-op games.

// MARK: - Defuse

/// Shared colour vocabulary for every colour-named part of a Defuse module
/// (wire insulation, the button body) -- both the flat SwiftUI mapping
/// (`TVDefuseBoardView.wireColor(_:)`) and the 3D casing materials in
/// `DefuseBombSceneView` read from this single table so the colour a wire
/// reads as on the phone's manual always matches the colour it renders as
/// on the TV, in whichever form the TV happens to draw it.
fileprivate func defuseModuleUIColor(_ name: String) -> UIColor {
    switch name {
    case "red": return .red
    case "blue": return .blue
    case "yellow": return .yellow
    case "white": return .white
    default: return .gray
    }
}

struct DefuseState {
    var secondsLeft = 0
    var strikes = 0
    var maxStrikes = 3
    var moduleIndex = 0
    var moduleCount = 0
    var moduleType = ""
    var wires: [String] = []
    var buttonColour = ""
    var buttonLabel = ""
    var symbols: [String] = []
    var won = false
    var finished = false
    var defuserName = ""
    var log: [String] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["strikes"]?.value as? Int { strikes = v }
        if let v = d["maxStrikes"]?.value as? Int { maxStrikes = v }
        if let v = d["moduleIndex"]?.value as? Int { moduleIndex = v }
        if let v = d["moduleCount"]?.value as? Int { moduleCount = v }
        if let v = d["won"]?.value as? Bool { won = v }
        if let v = d["finished"]?.value as? Bool { finished = v }
        if let v = d["defuserName"]?.value as? String { defuserName = v }
        log = (d["log"]?.value as? [Any] ?? []).compactMap { $0 as? String }
        // The module is public but carries neither the answer nor the manual.
        if let m = d["module"]?.value as? [String: Any] {
            moduleType = m["type"] as? String ?? ""
            wires = (m["wires"] as? [Any] ?? []).compactMap { $0 as? String }
            buttonColour = m["colour"] as? String ?? ""
            buttonLabel = m["label"] as? String ?? ""
            symbols = (m["symbols"] as? [Any] ?? []).compactMap { $0 as? String }
        }
    }
}

/// A real 3D bomb casing rendered with SceneKit, built on exactly the same
/// `CinematicCameraRig` / `CinematicLighting` primitives
/// `PokerCinematicBoardSceneView` uses -- a floating orbit camera, a single
/// dramatic key spotlight + a dim ambient fill, and cubic-bezier shot
/// transitions -- rather than any bespoke camera or lighting code.
///
/// The casing itself is a chamfered metal box; whichever module is
/// currently active (wires / button / symbols) is built as real geometry
/// standing off the casing's front "bay" panel, rebuilt only when the
/// module's actual content changes (`rebuildModuleIfNeeded`), not on every
/// state push (the timer alone pushes a new `DefuseState` every second).
///
/// This view owns only the *look* of the bomb -- every number the player
/// actually needs (timer, strikes, module index, defuser name) is rendered
/// as legible SwiftUI text by `TVDefuseBoardView` on top of this scene, the
/// same "3D is atmosphere, SwiftUI is the source of truth" split Poker uses.
private struct DefuseBombSceneView: UIViewRepresentable {
    var state: DefuseState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraRig.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.isPlaying = true
        view.rendersContinuously = true
        context.coordinator.apply(state, animated: false)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.apply(state, animated: true)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let cameraRig: CinematicCameraRig
        let lighting: CinematicLighting

        // Everything but the camera and the lights hangs off this single
        // node, so a "shake" or "pop open" beat can move the whole bomb at
        // once with one `SCNAction` instead of coordinating several nodes.
        private let contentRootNode = SCNNode()
        private let moduleRootNode = SCNNode()
        private let hatchPivot = SCNNode()

        private let casingMaterial = SCNMaterial()
        private var ledMaterials: [SCNMaterial] = []

        private let flashLightNode = SCNNode()
        private let flashLight = SCNLight()

        private let casingWidth: CGFloat = 1.7
        private let casingHeight: CGFloat = 1.0
        private let casingDepth: CGFloat = 0.6
        private let casingRadius: Float = 1.3

        private var lastModuleType = ""
        private var lastWires: [String] = []
        private var lastButtonColour = ""
        private var lastButtonLabel = ""
        private var lastSymbols: [String] = []
        private var lastStrikes = 0
        private var lastFinished = false

        init() {
            // `casingRadius` already has its default value at this point --
            // reading it bare (as a plain argument, not from inside a
            // closure) is exactly the pattern `PokerCinematicBoardSceneView`
            // uses to build its own initial shot before `cameraRig` exists.
            let initialShot = Coordinator.armedShot(radius: casingRadius)
            cameraRig = CinematicCameraRig(initialShot: initialShot)
            lighting = CinematicLighting(tableRadius: casingRadius)

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)
            scene.rootNode.addChildNode(contentRootNode)
            contentRootNode.addChildNode(moduleRootNode)

            flashLight.type = .omni
            flashLight.intensity = 0
            flashLight.color = UIColor.white
            flashLightNode.light = flashLight
            flashLightNode.position = SCNVector3(0, 0.5, Float(casingDepth) / 2 + 1.1)
            scene.rootNode.addChildNode(flashLightNode)

            buildCasing()
        }

        // MARK: - Casing (built once)

        private func buildCasing() {
            let plinthMaterial = SCNMaterial()
            plinthMaterial.lightingModel = .physicallyBased
            plinthMaterial.diffuse.contents = UIColor(white: 0.03, alpha: 1)
            plinthMaterial.roughness.contents = 0.9
            let plinth = SCNNode(geometry: SCNCylinder(radius: CGFloat(casingRadius) * 0.9, height: 0.05))
            plinth.geometry?.materials = [plinthMaterial]
            plinth.position = SCNVector3(0, -Float(casingHeight) / 2 - 0.035, 0)
            contentRootNode.addChildNode(plinth)

            casingMaterial.lightingModel = .physicallyBased
            casingMaterial.diffuse.contents = UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)
            casingMaterial.metalness.contents = 0.85
            casingMaterial.roughness.contents = 0.35
            casingMaterial.emission.contents = UIColor.black

            let casing = SCNNode(geometry: SCNBox(width: casingWidth, height: casingHeight,
                                                   length: casingDepth, chamferRadius: 0.06))
            casing.geometry?.materials = [casingMaterial]
            contentRootNode.addChildNode(casing)

            // The recessed bay every module stands on top of.
            let bayMaterial = SCNMaterial()
            bayMaterial.lightingModel = .physicallyBased
            bayMaterial.diffuse.contents = UIColor(white: 0.02, alpha: 1)
            bayMaterial.roughness.contents = 0.8
            let bay = SCNNode(geometry: SCNBox(width: casingWidth * 0.82, height: casingHeight * 0.72,
                                                length: 0.04, chamferRadius: 0.02))
            bay.geometry?.materials = [bayMaterial]
            bay.position = SCNVector3(0, 0, Float(casingDepth) / 2 + 0.01)
            contentRootNode.addChildNode(bay)

            // Corner bolts -- purely decorative, reads as "assembled metal
            // panel" instead of a smooth, molded box.
            let boltMaterial = SCNMaterial()
            boltMaterial.lightingModel = .physicallyBased
            boltMaterial.diffuse.contents = UIColor(white: 0.55, alpha: 1)
            boltMaterial.metalness.contents = 0.9
            boltMaterial.roughness.contents = 0.25
            let bx = Float(casingWidth) / 2 - 0.09
            let by = Float(casingHeight) / 2 - 0.09
            let bz = Float(casingDepth) / 2 + 0.006
            for signX: Float in [-1, 1] {
                for signY: Float in [-1, 1] {
                    let bolt = SCNNode(geometry: SCNSphere(radius: 0.026))
                    bolt.geometry?.materials = [boltMaterial]
                    bolt.position = SCNVector3(signX * bx, signY * by, bz)
                    contentRootNode.addChildNode(bolt)
                }
            }

            // Status LEDs along the top edge -- emission-only colour swap
            // driven by `updateStatusLights`, no geometry rebuild needed.
            for x: Float in [-0.18, 0, 0.18] {
                let material = SCNMaterial()
                material.lightingModel = .physicallyBased
                material.diffuse.contents = UIColor(white: 0.05, alpha: 1)
                material.emission.contents = UIColor.black
                let led = SCNNode(geometry: SCNSphere(radius: 0.036))
                led.geometry?.materials = [material]
                led.position = SCNVector3(x, Float(casingHeight) / 2 - 0.03, Float(casingDepth) / 2 + 0.02)
                contentRootNode.addChildNode(led)
                ledMaterials.append(material)
            }

            // A hinged access latch that pops open on a successful defuse --
            // `SCNAction.rotate(by:around:duration:)` swinging a pivot node
            // is the exact joint technique `PokerDealerNode`'s limbs use.
            let hatchMaterial = SCNMaterial()
            hatchMaterial.lightingModel = .physicallyBased
            hatchMaterial.diffuse.contents = UIColor(white: 0.12, alpha: 1)
            hatchMaterial.metalness.contents = 0.8
            hatchMaterial.roughness.contents = 0.3
            let hatch = SCNNode(geometry: SCNBox(width: 0.46, height: 0.05, length: 0.28, chamferRadius: 0.02))
            hatch.geometry?.materials = [hatchMaterial]
            hatch.position = SCNVector3(0, 0, 0.14)
            hatchPivot.addChildNode(hatch)
            hatchPivot.position = SCNVector3(0, Float(casingHeight) / 2, -Float(casingDepth) / 4)
            contentRootNode.addChildNode(hatchPivot)
        }

        // MARK: - Live state -> scene

        func apply(_ state: DefuseState, animated: Bool) {
            rebuildModuleIfNeeded(state)
            updateStatusLights(state)

            guard animated else {
                cameraRig.transition(to: Coordinator.armedShot(radius: casingRadius), duration: 0)
                lighting.apply(state.secondsLeft > 0 && state.secondsLeft < 30 ? .tense : .warm, duration: 0)
                lastStrikes = state.strikes
                lastFinished = state.finished
                return
            }

            if state.finished && !lastFinished {
                if state.won {
                    cameraRig.transition(to: Coordinator.climaxShot(radius: casingRadius), duration: 1.1)
                    lighting.apply(.warm, duration: 1.0)
                    flashCasing(color: UIColor(red: 0.15, green: 0.95, blue: 0.35, alpha: 1),
                                peakIntensity: 1400, duration: 1.6)
                    popOpenHatch()
                } else {
                    cameraRig.transition(to: Coordinator.climaxShot(radius: casingRadius), duration: 0.4)
                    lighting.apply(.tense, duration: 0.3)
                    flashCasing(color: UIColor(red: 1.0, green: 0.25, blue: 0.05, alpha: 1),
                                peakIntensity: 2600, duration: 1.4)
                    shakeContent(magnitude: 0.05, duration: 0.5)
                    joltCamera()
                }
            } else if !state.finished {
                let strikesNow = state.strikes - lastStrikes
                if strikesNow > 0 {
                    flashCasing(color: UIColor(red: 1.0, green: 0.2, blue: 0.15, alpha: 1),
                                peakIntensity: 1200, duration: 0.7)
                    shakeContent(magnitude: 0.02, duration: 0.3)
                }
                lighting.apply(state.secondsLeft > 0 && state.secondsLeft < 30 ? .tense : .warm, duration: 1.2)
            }

            lastStrikes = state.strikes
            lastFinished = state.finished
        }

        private func updateStatusLights(_ state: DefuseState) {
            let color: UIColor
            if state.finished {
                color = state.won ? UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1)
                                   : UIColor(red: 1.0, green: 0.15, blue: 0.1, alpha: 1)
            } else if state.secondsLeft < 20 {
                color = UIColor(red: 1.0, green: 0.35, blue: 0.05, alpha: 1)
            } else {
                color = UIColor(red: 1.0, green: 0.65, blue: 0.05, alpha: 1)
            }
            for material in ledMaterials {
                material.emission.contents = color
            }
        }

        // MARK: - Module content (rebuilt only when it actually changes)

        private func rebuildModuleIfNeeded(_ state: DefuseState) {
            let unchanged: Bool
            switch state.moduleType {
            case "wires":
                unchanged = state.moduleType == lastModuleType && state.wires == lastWires
            case "button":
                unchanged = state.moduleType == lastModuleType
                    && state.buttonColour == lastButtonColour && state.buttonLabel == lastButtonLabel
            case "symbols":
                unchanged = state.moduleType == lastModuleType && state.symbols == lastSymbols
            default:
                unchanged = state.moduleType == lastModuleType
            }
            guard !unchanged else { return }

            moduleRootNode.childNodes.forEach { $0.removeFromParentNode() }
            switch state.moduleType {
            case "wires": buildWires(state.wires)
            case "button": buildButton(colour: state.buttonColour, label: state.buttonLabel)
            case "symbols": buildSymbolsScreen(state.symbols)
            default: break
            }

            lastModuleType = state.moduleType
            lastWires = state.wires
            lastButtonColour = state.buttonColour
            lastButtonLabel = state.buttonLabel
            lastSymbols = state.symbols
        }

        /// Each wire is two thin cylinder segments meeting at a sagging
        /// midpoint -- a real bent wire draped across the bay, not a flat
        /// rectangle -- with a small solder-blob sphere at each anchor.
        private func buildWires(_ wires: [String]) {
            guard !wires.isEmpty else { return }
            let halfWidth = Float(casingWidth) * 0.32
            let panelZ = Float(casingDepth) / 2 + 0.03
            let count = wires.count
            let maxSpan = Float(casingHeight) * 0.55
            let spacing: Float = count > 1 ? min(0.16, maxSpan / Float(count - 1)) : 0
            let sag = max(0.03, spacing * 0.35)
            let topOffset = Float(count - 1) / 2 * spacing

            for (i, colourName) in wires.enumerated() {
                let y = topOffset - Float(i) * spacing
                let left = SCNVector3(-halfWidth, y, panelZ)
                let right = SCNVector3(halfWidth, y, panelZ)
                let dip = SCNVector3(0, y - sag, panelZ + 0.05)

                let material = SCNMaterial()
                material.lightingModel = .physicallyBased
                material.diffuse.contents = defuseModuleUIColor(colourName)
                material.roughness.contents = 0.45

                moduleRootNode.addChildNode(Coordinator.cylinderNode(from: left, to: dip, radius: 0.018, material: material))
                moduleRootNode.addChildNode(Coordinator.cylinderNode(from: dip, to: right, radius: 0.018, material: material))

                for anchor in [left, right] {
                    let blob = SCNNode(geometry: SCNSphere(radius: 0.024))
                    blob.geometry?.materials = [material]
                    blob.position = anchor
                    moduleRootNode.addChildNode(blob)
                }
            }
        }

        /// A real pressable button: a raised cylinder body (colour comes
        /// straight from `defuseModuleUIColor`) plus a thin front label
        /// plate whose texture is rendered text -- a flat box face rather
        /// than a cylinder cap so the label's UV mapping is unambiguous.
        private func buildButton(colour: String, label: String) {
            let panelZ = Float(casingDepth) / 2 + 0.03

            let bodyMaterial = SCNMaterial()
            bodyMaterial.lightingModel = .physicallyBased
            bodyMaterial.diffuse.contents = defuseModuleUIColor(colour)
            bodyMaterial.metalness.contents = 0.3
            bodyMaterial.roughness.contents = 0.4

            let bodyHeight: CGFloat = 0.16
            let body = SCNNode(geometry: SCNCylinder(radius: 0.26, height: bodyHeight))
            body.geometry?.materials = [bodyMaterial]
            body.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            body.position = SCNVector3(0, 0, panelZ + Float(bodyHeight) / 2)
            moduleRootNode.addChildNode(body)

            let textColor: UIColor = colour == "white" ? .black : .white
            let capMaterial = SCNMaterial()
            capMaterial.lightingModel = .physicallyBased
            capMaterial.diffuse.contents = Coordinator.buttonLabelTexture(
                label: label, background: defuseModuleUIColor(colour), textColor: textColor)
            capMaterial.roughness.contents = 0.5

            let cap = SCNNode(geometry: SCNBox(width: 0.34, height: 0.20, length: 0.02, chamferRadius: 0.01))
            cap.geometry?.materials = [capMaterial]
            cap.position = SCNVector3(0, 0, panelZ + Float(bodyHeight) + 0.02)
            moduleRootNode.addChildNode(cap)
        }

        /// The symbol grid renders as an image (the same emoji + index
        /// layout the old flat SwiftUI panel used) onto a small embedded
        /// "screen" recessed into the casing, rather than trying to project
        /// live SwiftUI text onto a moving 3D surface.
        private func buildSymbolsScreen(_ symbols: [String]) {
            guard !symbols.isEmpty else { return }
            let panelZ = Float(casingDepth) / 2 + 0.025

            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = Coordinator.symbolsTexture(symbols)
            material.emission.contents = UIColor(white: 0.06, alpha: 1)
            material.roughness.contents = 0.2

            let screen = SCNNode(geometry: SCNBox(width: casingWidth * 0.7, height: casingHeight * 0.42,
                                                   length: 0.02, chamferRadius: 0.01))
            screen.geometry?.materials = [material]
            screen.position = SCNVector3(0, 0, panelZ)
            moduleRootNode.addChildNode(screen)
        }

        // MARK: - Feedback beats

        private func flashCasing(color: UIColor, peakIntensity: CGFloat, duration: TimeInterval) {
            flashLight.color = color

            SCNTransaction.begin()
            SCNTransaction.animationDuration = duration * 0.2
            flashLight.intensity = peakIntensity
            casingMaterial.emission.contents = color
            SCNTransaction.commit()

            let fadeDelay = duration * 0.2
            let fadeDuration = duration * 0.9
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDelay) { [weak self] in
                guard let self else { return }
                SCNTransaction.begin()
                SCNTransaction.animationDuration = fadeDuration
                self.flashLight.intensity = 0
                self.casingMaterial.emission.contents = UIColor.black
                SCNTransaction.commit()
            }
        }

        /// A quick side-to-side jolt of the whole casing -- the BOOM beat.
        private func shakeContent(magnitude: Float, duration: TimeInterval) {
            let stepCount = 6
            var actions: [SCNAction] = []
            for i in 0..<stepCount {
                let sign: Float = (i % 2 == 0) ? 1 : -1
                let falloff = Float(stepCount - i) / Float(stepCount)
                let delta = SCNVector3(magnitude * sign * falloff, 0, 0)
                actions.append(SCNAction.move(by: delta, duration: duration / Double(stepCount)))
            }
            actions.append(SCNAction.move(to: SCNVector3(0, 0, 0), duration: duration / Double(stepCount)))
            contentRootNode.removeAction(forKey: "shake")
            contentRootNode.runAction(SCNAction.sequence(actions), forKey: "shake")
        }

        /// A brief camera-shake feel on BOOM: boost the idle rig's own
        /// floating-orbit amplitude for a moment, then hand it back --
        /// reusing `CinematicCameraRig`'s public orbit knobs rather than
        /// fighting its per-frame position update with a second animation.
        private func joltCamera() {
            let boosted = SCNVector3(0.55, 0.4, 0.45)
            let original = cameraRig.orbitAmplitude
            cameraRig.orbitAmplitude = boosted
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.cameraRig.orbitAmplitude = original
            }
        }

        private func popOpenHatch() {
            let open = SCNAction.rotate(by: -1.3, around: SCNVector3(1, 0, 0), duration: 0.6)
            open.timingMode = .easeOut
            hatchPivot.removeAction(forKey: "hatch")
            hatchPivot.runAction(open, forKey: "hatch")
        }

        // MARK: - Camera shots

        private static func armedShot(radius: Float) -> CameraShot {
            CameraShot(
                position: SCNVector3(radius * 0.9, radius * 0.85, radius * 1.6),
                lookAt: SCNVector3(0, 0, 0),
                fieldOfView: 40,
                focusDistance: CGFloat(radius * 1.6)
            )
        }

        private static func climaxShot(radius: Float) -> CameraShot {
            CameraShot(
                position: SCNVector3(0, radius * 0.5, radius * 1.1),
                lookAt: SCNVector3(0, 0, 0),
                fieldOfView: 32,
                focusDistance: CGFloat(radius * 1.1)
            )
        }

        // MARK: - Geometry helpers

        /// Builds a thin cylinder spanning two points, oriented by rotating
        /// the cylinder's default +Y axis onto the `a -> b` direction (the
        /// standard axis/angle-from-cross-product technique) -- a plain
        /// static function, so it never touches `self` and is safe to call
        /// from anywhere, including during a caller's own `init`.
        private static func cylinderNode(from a: SCNVector3, to b: SCNVector3,
                                          radius: CGFloat, material: SCNMaterial) -> SCNNode {
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let distance = sqrt(dx * dx + dy * dy + dz * dz)

            let cylinder = SCNCylinder(radius: radius, height: CGFloat(distance))
            cylinder.materials = [material]
            let node = SCNNode(geometry: cylinder)
            node.position = SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)

            guard distance > 0.0001 else { return node }
            let dir = SCNVector3(dx / distance, dy / distance, dz / distance)
            let dot = max(-1, min(1, dir.y)) // (0,1,0) . dir == dir.y
            let angle = acos(dot)
            if angle > 0.0001 {
                if angle > Float.pi - 0.0001 {
                    node.rotation = SCNVector4(1, 0, 0, Float.pi)
                } else {
                    // axis = up × dir, with up = (0, 1, 0).
                    let axis = SCNVector3(dz, 0, -dx)
                    let axisLength = sqrt(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
                    node.rotation = SCNVector4(axis.x / axisLength, axis.y / axisLength, axis.z / axisLength, angle)
                }
            }
            return node
        }

        // MARK: - Rendered textures (symbols screen + button label)

        private static func symbolsTexture(_ symbols: [String]) -> UIImage {
            let size = CGSize(width: 640, height: 320)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor(white: 0.05, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                guard !symbols.isEmpty else { return }

                let cellWidth = size.width / CGFloat(symbols.count)
                let symbolFont = UIFont.systemFont(ofSize: 108)
                let indexFont = UIFont.boldSystemFont(ofSize: 26)
                let indexColor = UIColor.white.withAlphaComponent(0.55)

                for (i, symbol) in symbols.enumerated() {
                    let cellRect = CGRect(x: CGFloat(i) * cellWidth, y: 0, width: cellWidth, height: size.height)

                    let symbolAttrs: [NSAttributedString.Key: Any] = [.font: symbolFont]
                    let symbolText = symbol as NSString
                    let symbolSize = symbolText.size(withAttributes: symbolAttrs)
                    symbolText.draw(at: CGPoint(x: cellRect.midX - symbolSize.width / 2,
                                                 y: cellRect.midY - symbolSize.height / 2 - 16),
                                     withAttributes: symbolAttrs)

                    let indexAttrs: [NSAttributedString.Key: Any] = [.font: indexFont, .foregroundColor: indexColor]
                    let indexText = "\(i + 1)" as NSString
                    let indexSize = indexText.size(withAttributes: indexAttrs)
                    indexText.draw(at: CGPoint(x: cellRect.midX - indexSize.width / 2,
                                                y: size.height - indexSize.height - 16),
                                    withAttributes: indexAttrs)
                }
            }
        }

        private static func buttonLabelTexture(label: String, background: UIColor, textColor: UIColor) -> UIImage {
            let size = CGSize(width: 320, height: 200)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                background.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                guard !label.isEmpty else { return }

                let font = UIFont.systemFont(ofSize: 42, weight: .heavy)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let text = label as NSString
                let textSize = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: size.width / 2 - textSize.width / 2,
                                       y: size.height / 2 - textSize.height / 2),
                           withAttributes: attrs)
            }
        }
    }
}

struct TVDefuseBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: DefuseState()) { $0.update(from: $1) }

    @State private var previousStrikes = 0
    @State private var flashColor: Color = .clear
    @State private var flashOpacity: Double = 0
    @State private var shakeOffset: CGFloat = 0

    private func wireColor(_ name: String) -> Color {
        Color(defuseModuleUIColor(name))
    }

    var body: some View {
        ZStack {
            // The real 3D bomb: a chamfered metal casing, one dramatic key
            // spotlight, and whichever module is active standing off its
            // front bay. Every number the players actually need is drawn
            // as SwiftUI text on top of it below -- the scene is atmosphere
            // for the defuser to describe, never the source of truth.
            DefuseBombSceneView(state: vm.state)
                .ignoresSafeArea()

            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Rectangle()
                .fill(flashColor)
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Defuse").font(.system(size: 38, weight: .bold))
                            .foregroundColor(.white)
                        Text("\(vm.state.defuserName) holds the bomb — everyone else has the manual")
                            .font(.headline).foregroundColor(.white.opacity(0.55))
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(0..<vm.state.maxStrikes, id: \.self) { i in
                            Image(systemName: "xmark").font(.title.bold()).foregroundColor(.white.opacity(0.7))
                                .foregroundColor(i < vm.state.strikes ? .red : .white.opacity(0.2))
                        }
                    }
                    Text(String(format: "%d:%02d", vm.state.secondsLeft / 60, vm.state.secondsLeft % 60))
                        .font(.system(size: 62, weight: .heavy, design: .monospaced))
                        .foregroundColor(vm.state.secondsLeft < 30 ? .red : .green)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                }
                .padding(.horizontal, 70).padding(.top, 44)

                if !vm.state.finished {
                    Text("MODULE \(vm.state.moduleIndex + 1) OF \(vm.state.moduleCount)")
                        .font(.caption.bold()).tracking(4).foregroundColor(.white.opacity(0.65))
                        .padding(.top, 18)
                }

                Spacer()

                if vm.state.finished {
                    VStack(spacing: 16) {
                        Image(systemName: vm.state.won ? "heart.fill" : "burst.fill").font(.system(size: 120)).foregroundColor(vm.state.won ? .green : .red)
                        Text(vm.state.won ? "DEFUSED" : "BOOM")
                            .font(.system(size: 64, weight: .heavy)).tracking(6)
                            .foregroundColor(vm.state.won ? .green : .red)
                            .shadow(color: .black.opacity(0.7), radius: 10)
                    }
                }

                Spacer()
                HStack(spacing: 16) {
                    ForEach(vm.state.log, id: \.self) { entry in
                        Text(entry).font(.callout)
                            .foregroundColor(entry.hasPrefix("Strike") ? .red : .green)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .offset(x: shakeOffset)
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: vm.state.strikes) { newValue in
            if newValue > previousStrikes && !vm.state.finished {
                triggerStrikeFeedback()
            }
            previousStrikes = newValue
        }
        .onChange(of: vm.state.finished) { finished in
            guard finished else { return }
            if vm.state.won {
                triggerFlash(color: .green, peak: 0.5, fadeDuration: 1.4)
            } else {
                triggerFlash(color: .red, peak: 0.75, fadeDuration: 1.2)
                triggerShake(magnitude: 22)
            }
        }
    }

    // MARK: - SwiftUI-level feedback (guaranteed legible regardless of how
    // the 3D scene's own lighting/material flash happens to render)

    private func triggerStrikeFeedback() {
        triggerFlash(color: .red, peak: 0.4, fadeDuration: 0.5)
        triggerShake(magnitude: 10)
    }

    private func triggerFlash(color: Color, peak: Double, fadeDuration: Double) {
        flashColor = color
        withAnimation(.easeOut(duration: 0.08)) { flashOpacity = peak }
        withAnimation(.easeIn(duration: fadeDuration).delay(0.08)) { flashOpacity = 0 }
    }

    private func triggerShake(magnitude: CGFloat) {
        let steps: [CGFloat] = [1, -0.8, 0.6, -0.4, 0.2, -0.1, 0]
        var delay = 0.0
        for step in steps {
            let offset = magnitude * step
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.045)) { shakeOffset = offset }
            }
            delay += 0.045
        }
    }
}

// MARK: - Battleship

struct BattleshipState {
    var size = 8
    var boards: [(ownerName: String, shots: [Int: String], sunk: Int)] = []
    var currentPlayerID: String? = nil
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["size"]?.value as? Int { size = v }
        currentPlayerID = d["currentPlayerID"]?.value as? String
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
        boards = (d["boards"]?.value as? [Any] ?? []).compactMap {
            guard let b = $0 as? [String: Any] else { return nil }
            var shots: [Int: String] = [:]
            for item in (b["shots"] as? [Any] ?? []) {
                if let s = item as? [String: Any],
                   let cell = s["cell"] as? Int, let r = s["result"] as? String {
                    shots[cell] = r
                }
            }
            return (b["ownerName"] as? String ?? "", shots, b["sunk"] as? Int ?? 0)
        }
    }
}

struct TVBattleshipBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: BattleshipState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "sailboat.fill", title: "Battleship",
                          round: 0, totalRounds: 0, secondsLeft: 0,
                          phaseLabel: vm.state.winner != nil ? "game over" : "fire!")
            Spacer()
            HStack(spacing: 90) {
                ForEach(Array(vm.state.boards.enumerated()), id: \.offset) { _, board in
                    VStack(spacing: 16) {
                        Text(board.ownerName).font(.title2.bold()).foregroundColor(.white)
                        Text("\(board.sunk) ships sunk").font(.callout)
                            .foregroundColor(.cyan)
                        // Only hits and misses — fleet positions stay on the phones.
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 5),
                                                 count: vm.state.size), spacing: 5) {
                            ForEach(0..<(vm.state.size * vm.state.size), id: \.self) { cell in
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(board.shots[cell] == "hit" ? Color.red
                                          : board.shots[cell] == "miss" ? Color.white.opacity(0.22)
                                          : Color.blue.opacity(0.28))
                                    .frame(width: 52, height: 52)
                                    .overlay(
                                        Group {
                                            if board.shots[cell] == "hit" {
                                                Image(systemName: "xmark").font(.title3)
                                            } else if board.shots[cell] == "miss" {
                                                Text("·")
                                            }
                                        }
                                    )
                            }
                        }
                    }
                }
            }
            if let winner = vm.state.winner,
               let name = vm.state.players.first(where: { $0.id == winner })?.name {
                Text("\(name) wins")
                    .font(.system(size: 44, weight: .heavy)).foregroundColor(.yellow)
                    .padding(.top, 26)
            }
            Spacer()
            TVScoreStrip(players: vm.state.players)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Air Hockey

struct AirHockeyState {
    var width: Double = 100, height: Double = 160
    var puck = (x: 50.0, y: 80.0)
    var paddles: [(name: String, x: Double, score: Int)] = []
    var paddleWidth: Double = 18
    var winScore = 7
    var finished = false

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["width"]?.value as? Double { width = v }
        if let v = d["height"]?.value as? Double { height = v }
        if let p = d["puck"]?.value as? [String: Any],
           let x = p["x"] as? Double, let y = p["y"] as? Double { puck = (x, y) }
        if let v = d["paddleWidth"]?.value as? Double { paddleWidth = v }
        if let v = d["winScore"]?.value as? Int { winScore = v }
        if let v = d["finished"]?.value as? Bool { finished = v }
        paddles = (d["paddles"]?.value as? [Any] ?? []).compactMap {
            guard let p = $0 as? [String: Any] else { return nil }
            return (p["name"] as? String ?? "", p["x"] as? Double ?? 50,
                    p["score"] as? Int ?? 0)
        }
    }
}

struct TVAirHockeyBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: AirHockeyState()) { $0.update(from: $1) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    ForEach(Array(vm.state.paddles.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: 2) {
                            Text(p.name).font(.headline).foregroundColor(.white.opacity(0.6))
                            Text("\(p.score)").font(.system(size: 54, weight: .heavy))
                                .foregroundColor(i == 0 ? .cyan : .pink)
                        }
                        if i == 0 { Spacer() }
                    }
                }
                .padding(.horizontal, 120).padding(.top, 40)
                Spacer()
            }

            // Reported alongside Neon Snake/Brick Breaker: a fixed 6pt scale
            // sized the rink purely off its own default 100x160 unit grid,
            // regardless of how much bigger the actual TV screen is. Deriving
            // the scale from the space actually available here instead lets
            // the rink fill it (preserving its aspect ratio).
            GeometryReader { geo in
                let margin: CGFloat = 40
                let availableWidth = max(geo.size.width - margin * 2, 1)
                let availableHeight = max(geo.size.height - margin * 2, 1)
                let scale = max(1, min(availableWidth / CGFloat(max(vm.state.width, 1)),
                                        availableHeight / CGFloat(max(vm.state.height, 1))))

                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(.white.opacity(0.25), lineWidth: 3)
                        .background(RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.45)))

                    Canvas { ctx, size in
                        // Centre line and circle
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: size.height / 2))
                        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        ctx.stroke(line, with: .color(.white.opacity(0.15)), lineWidth: 2)
                        ctx.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - 60,
                                                          y: size.height / 2 - 60,
                                                          width: 120, height: 120)),
                                   with: .color(.white.opacity(0.15)), lineWidth: 2)

                        // Paddles. state fields decode as Double (server JSON), scale is
                        // CGFloat -- Swift has no automatic Double<->CGFloat conversion,
                        // so each Double sub-expression is wrapped once before scaling.
                        for (i, p) in vm.state.paddles.enumerated() {
                            let y: CGFloat = i == 0 ? 6 * scale : CGFloat(vm.state.height - 6) * scale
                            ctx.fill(
                                Path(roundedRect: CGRect(
                                    x: CGFloat(p.x - vm.state.paddleWidth / 2) * scale, y: y - 8,
                                    width: CGFloat(vm.state.paddleWidth) * scale, height: 16),
                                     cornerRadius: 8),
                                with: .color(i == 0 ? .cyan : .pink))
                        }

                        ctx.fill(
                            Path(ellipseIn: CGRect(x: CGFloat(vm.state.puck.x - 3) * scale,
                                                   y: CGFloat(vm.state.puck.y - 3) * scale,
                                                   width: 6 * scale, height: 6 * scale)),
                            with: .color(.white))
                    }
                    .frame(width: CGFloat(vm.state.width) * scale, height: CGFloat(vm.state.height) * scale)

                    if vm.state.finished {
                        Text("GAME OVER").font(.system(size: 54, weight: .heavy)).tracking(5)
                            .foregroundColor(.yellow)
                            .padding(34)
                            .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.8)))
                    }
                }
                .frame(width: CGFloat(vm.state.width) * scale + 8, height: CGFloat(vm.state.height) * scale + 8)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Heist Escape

struct HeistEscapeState {
    var size = 7
    var position = 0
    var exitCell = 48
    var trail: [Int] = []
    var secondsLeft = 0
    var won = false
    var finished = false
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["size"]?.value as? Int { size = v }
        if let v = d["position"]?.value as? Int { position = v }
        if let v = d["exitCell"]?.value as? Int { exitCell = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        if let v = d["won"]?.value as? Bool { won = v }
        if let v = d["finished"]?.value as? Bool { finished = v }
        trail = (d["trail"]?.value as? [Any] ?? []).compactMap { $0 as? Int }
        players = BoardPlayer.list(from: d["players"]?.value)
    }
}

struct TVHeistEscapeBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: HeistEscapeState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "door.left.hand.open", title: "Heist Escape",
                          round: 0, totalRounds: 0, secondsLeft: vm.state.secondsLeft,
                          phaseLabel: "each phone holds part of the map")
            Spacer()
            if vm.state.finished {
                VStack(spacing: 16) {
                    Image(systemName: vm.state.won ? "party.popper.fill" : "exclamationmark.triangle.fill").font(.system(size: 120)).foregroundColor(vm.state.won ? .yellow : .red)
                    Text(vm.state.won ? "ESCAPED" : "CAUGHT")
                        .font(.system(size: 60, weight: .heavy)).tracking(5)
                        .foregroundColor(vm.state.won ? .green : .red)
                }
            } else {
                // The maze itself is never drawn — only where the team has been.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(90), spacing: 8),
                                         count: vm.state.size), spacing: 8) {
                    ForEach(0..<(vm.state.size * vm.state.size), id: \.self) { cell in
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(cell == vm.state.exitCell ? Color.green.opacity(0.35)
                                      : vm.state.trail.contains(cell) ? Color.cyan.opacity(0.2)
                                      : Color.white.opacity(0.05))
                            if cell == vm.state.position {
                                Image(systemName: "person.fill").font(.system(size: 40)).foregroundColor(.white)
                            } else if cell == vm.state.exitCell {
                                Image(systemName: "door.left.hand.open").font(.system(size: 34)).foregroundColor(.white)
                            }
                        }
                        .frame(width: 90, height: 90)
                    }
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.players)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Ludo

struct LudoState {
    var die = 0
    var rolled = false
    var currentPlayerID: String? = nil
    var seats: [(name: String, seat: Int, tokens: [Int], absolute: [Int?])] = []
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["die"]?.value as? Int { die = v }
        if let v = d["rolled"]?.value as? Bool { rolled = v }
        currentPlayerID = d["currentPlayerID"]?.value as? String
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
        seats = (d["seats"]?.value as? [Any] ?? []).compactMap {
            guard let s = $0 as? [String: Any] else { return nil }
            return (s["name"] as? String ?? "",
                    s["seat"] as? Int ?? 0,
                    (s["tokens"] as? [Any] ?? []).compactMap { $0 as? Int },
                    (s["absolute"] as? [Any] ?? []).map { $0 as? Int })
        }
    }
}

struct TVLudoBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: LudoState()) { $0.update(from: $1) }

    private let seatColors: [Color] = [.red, .green, .yellow, .blue]
    private let track = 52
    private let radius: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "dice.fill", title: "Ludo", round: 0, totalRounds: 0, secondsLeft: 0,
                          phaseLabel: vm.state.rolled ? "pick a token" : "roll the dice")
            Spacer()
            HStack(spacing: 70) {
                // Ring board: 52 squares laid out in a circle keeps every token
                // visible at TV distance without a cramped cross layout.
                ZStack {
                    // Extracted into their own subviews (below) rather than inline
                    // closures here: two nested ForEach loops combining trig,
                    // conditional binding, and several chained modifiers in one
                    // expression tree made the type-checker time out. Each subview
                    // now type-checks independently.
                    ForEach(0..<track, id: \.self) { i in
                        LudoTrackDot(index: i, track: track, radius: radius)
                    }
                    ForEach(Array(vm.state.seats.enumerated()), id: \.offset) { _, seat in
                        ForEach(Array(seat.absolute.enumerated()), id: \.offset) { _, abs in
                            LudoTokenDot(position: abs, track: track, radius: radius,
                                        color: seatColors[seat.seat % 4])
                        }
                    }
                    VStack(spacing: 6) {
                        Image(systemName: "dice.fill").font(.system(size: 56)).foregroundColor(.white.opacity(0.8))
                        Text(vm.state.die > 0 ? "\(vm.state.die)" : "—")
                            .font(.system(size: 70, weight: .heavy)).foregroundColor(.white)
                    }
                }
                .frame(width: radius * 2 + 60, height: radius * 2 + 60)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(vm.state.seats.enumerated()), id: \.offset) { _, seat in
                        let active = vm.state.players.first { $0.id == vm.state.currentPlayerID }?.name == seat.name
                        HStack(spacing: 12) {
                            Circle().fill(seatColors[seat.seat % 4]).frame(width: 22, height: 22)
                            Text(seat.name).font(.title3.bold())
                                .foregroundColor(active ? .white : .white.opacity(0.5))
                            Spacer()
                            Text("\(seat.tokens.filter { $0 >= 100 }.count)/4 home")
                                .font(.callout).foregroundColor(.cyan)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .frame(width: 340)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(active ? .white.opacity(0.12) : .white.opacity(0.04)))
                    }
                }
            }
            Spacer()
            TVScoreStrip(players: vm.state.players)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

/// One background ring position on the Ludo track. Its own `body` gives the
/// type-checker a small, isolated expression instead of one more closure
/// nested inside TVLudoBoardView's already-heavy view tree.
private struct LudoTrackDot: View {
    let index: Int
    let track: Int
    let radius: CGFloat

    var body: some View {
        let angle = Double(index) / Double(track) * 2 * .pi - .pi / 2
        Circle()
            .fill(.white.opacity(0.1))
            .frame(width: 30, height: 30)
            .offset(x: radius * cos(angle), y: radius * sin(angle))
    }
}

/// One player token on the Ludo track, or nothing if that token hasn't left
/// the yard yet (`position == nil`).
private struct LudoTokenDot: View {
    let position: Int?
    let track: Int
    let radius: CGFloat
    let color: Color

    var body: some View {
        if let pos = position {
            let angle = Double(pos) / Double(track) * 2 * .pi - .pi / 2
            Circle()
                .fill(color)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .offset(x: radius * cos(angle), y: radius * sin(angle))
        }
    }
}

// MARK: - Carrom

struct CarromState {
    var board: Double = 100
    var coins: [(id: Int, x: Double, y: Double, kind: String)] = []
    var strikerX: Double = 50
    var currentPlayerID: String? = nil
    var targetScore = 8
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["board"]?.value as? Double { board = v }
        if let v = d["strikerX"]?.value as? Double { strikerX = v }
        if let v = d["targetScore"]?.value as? Int { targetScore = v }
        currentPlayerID = d["currentPlayerID"]?.value as? String
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
        coins = (d["coins"]?.value as? [Any] ?? []).compactMap {
            guard let c = $0 as? [String: Any], let id = c["id"] as? Int else { return nil }
            return (id, c["x"] as? Double ?? 0, c["y"] as? Double ?? 0,
                    c["kind"] as? String ?? "white")
        }
    }
}

struct TVCarromBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: CarromState()) { $0.update(from: $1) }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "circle.dashed", title: "Carrom", round: 0, totalRounds: 0, secondsLeft: 0,
                          phaseLabel: "first to \(vm.state.targetScore)")
            // Same fix as Neon Snake/Brick Breaker/Air Hockey: a fixed 8pt
            // scale sized the board purely off its own default 100x100 unit
            // grid, regardless of how much bigger the actual TV screen is.
            // Deriving the scale from the space actually available here
            // instead lets the board (square, so width and height agree)
            // fill it.
            GeometryReader { geo in
                let margin: CGFloat = 40
                let availableWidth = max(geo.size.width - margin * 2, 1)
                let availableHeight = max(geo.size.height - margin * 2, 1)
                let scale = max(1, min(availableWidth / CGFloat(max(vm.state.board, 1)),
                                        availableHeight / CGFloat(max(vm.state.board, 1))))

                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "d9b382"))
                        .frame(width: CGFloat(vm.state.board) * scale, height: CGFloat(vm.state.board) * scale)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "6b4f2a"), lineWidth: 10))

                    Canvas { ctx, size in
                        // Pockets
                        for p in [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                                  CGPoint(x: 0, y: size.height),
                                  CGPoint(x: size.width, y: size.height)] {
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 28, y: p.y - 28,
                                                            width: 56, height: 56)),
                                     with: .color(.black))
                        }
                        ctx.stroke(Path(ellipseIn: CGRect(x: size.width / 2 - 45,
                                                          y: size.height / 2 - 45,
                                                          width: 90, height: 90)),
                                   with: .color(Color(hex: "6b4f2a").opacity(0.5)), lineWidth: 3)

                        // coin.x/y and strikerX decode as Double (server JSON); scale is
                        // CGFloat, so each is wrapped before scaling -- see AirHockey above.
                        for coin in vm.state.coins {
                            let color: Color = coin.kind == "queen" ? .red
                                             : coin.kind == "black" ? .black
                                             : Color(hex: "f5e6c8")
                            ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(coin.x) * scale - 12,
                                                            y: CGFloat(coin.y) * scale - 12,
                                                            width: 24, height: 24)),
                                     with: .color(color))
                        }
                        // Striker
                        ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(vm.state.strikerX) * scale - 16,
                                                        y: 92 * scale - 16,
                                                        width: 32, height: 32)),
                                 with: .color(.cyan))
                    }
                    .frame(width: CGFloat(vm.state.board) * scale, height: CGFloat(vm.state.board) * scale)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            TVScoreStrip(players: vm.state.players)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - Teen Patti

struct TeenPattiState {
    var pot = 0
    var currentStake = 0
    var currentPlayerID: String? = nil
    var seats: [(id: String, name: String, chips: Int, folded: Bool,
                 blind: Bool, stake: Int)] = []
    var showdown: [(name: String, cards: [(rank: Int, suit: String)], rank: Int)] = []
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["pot"]?.value as? Int { pot = v }
        if let v = d["currentStake"]?.value as? Int { currentStake = v }
        currentPlayerID = d["currentPlayerID"]?.value as? String
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
        seats = (d["seats"]?.value as? [Any] ?? []).compactMap {
            guard let s = $0 as? [String: Any] else { return nil }
            return (s["playerID"] as? String ?? "", s["name"] as? String ?? "",
                    s["chips"] as? Int ?? 0, s["folded"] as? Bool ?? false,
                    s["blind"] as? Bool ?? false, s["stake"] as? Int ?? 0)
        }
        showdown = (d["showdown"]?.value as? [Any] ?? []).compactMap {
            guard let s = $0 as? [String: Any] else { return nil }
            let cards = (s["cards"] as? [Any] ?? []).compactMap { c -> (rank: Int, suit: String)? in
                guard let card = c as? [String: Any], let r = card["rank"] as? Int
                else { return nil }
                return (r, card["suit"] as? String ?? "♠")
            }
            return (s["name"] as? String ?? "", cards, s["rank"] as? Int ?? 0)
        }
    }
}

struct TVTeenPattiBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: TeenPattiState()) { $0.update(from: $1) }

    private func rankName(_ r: Int) -> String {
        ["", "High Card", "Pair", "Colour", "Sequence", "Pure Sequence", "Trail"][min(r, 6)]
    }

    private func cardLabel(_ rank: Int) -> String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        default: return "\(rank)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Teen Patti").font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                VStack(spacing: 2) {
                    Text("POT").font(.caption.bold()).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    Text("\(vm.state.pot)").font(.system(size: 46, weight: .heavy))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal, 70).padding(.top, 44)

            Spacer()

            if vm.state.showdown.isEmpty {
                // Cards stay on the phones until showdown.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 20) {
                    ForEach(Array(vm.state.seats.enumerated()), id: \.offset) { _, seat in
                        VStack(spacing: 8) {
                            Text(seat.name).font(.title3.bold())
                                .foregroundColor(seat.folded ? .white.opacity(0.3) : .white)
                            HStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(seat.folded ? Color.white.opacity(0.07)
                                                          : Color.purple.opacity(0.55))
                                        .frame(width: 40, height: 58)
                                }
                            }
                            Text("\(seat.chips)").font(.headline).foregroundColor(.cyan)
                            if seat.blind && !seat.folded {
                                Text("BLIND").font(.caption.bold()).tracking(2)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 18).frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(seat.id == vm.state.currentPlayerID
                                  ? Color.white.opacity(0.14) : Color.white.opacity(0.04)))
                    }
                }
                .padding(.horizontal, 80)
            } else {
                VStack(spacing: 18) {
                    ForEach(Array(vm.state.showdown.enumerated()), id: \.offset) { _, s in
                        HStack(spacing: 18) {
                            Text(s.name).font(.title2.bold()).foregroundColor(.white)
                                .frame(width: 200, alignment: .leading)
                            HStack(spacing: 8) {
                                ForEach(Array(s.cards.enumerated()), id: \.offset) { _, c in
                                    VStack(spacing: 0) {
                                        Text(cardLabel(c.rank)).font(.title3.bold())
                                        Text(c.suit).font(.title3)
                                    }
                                    .foregroundColor(c.suit == "♥" || c.suit == "♦" ? .red : .black)
                                    .frame(width: 54, height: 76)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                                }
                            }
                            Text(rankName(s.rank)).font(.headline).foregroundColor(.yellow)
                        }
                    }
                }
            }

            Spacer()
            TVScoreStrip(players: vm.state.players)
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}
