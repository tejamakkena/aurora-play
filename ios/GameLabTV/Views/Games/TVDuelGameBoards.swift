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
    case "red": return UIColor(TVTheme.red)
    case "blue": return UIColor(TVTheme.blue)
    case "yellow": return UIColor(TVTheme.yellow)
    case "white": return .white
    // Matches `DefuseControllerView.wireColor(_:)` on the phone, black wire
    // and grey fallback included.
    case "black": return UIColor(Color(hex: "121218"))
    default: return UIColor(TVTheme.text3)
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
                                .foregroundColor(i < vm.state.strikes ? TVTheme.red : .white.opacity(0.2))
                        }
                    }
                    Text(String(format: "%d:%02d", vm.state.secondsLeft / 60, vm.state.secondsLeft % 60))
                        .font(.system(size: 62, weight: .heavy, design: .monospaced))
                        .foregroundColor(vm.state.secondsLeft < 30 ? TVTheme.red : TVTheme.green)
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
                        Image(systemName: vm.state.won ? "heart.fill" : "burst.fill").font(.system(size: 120)).foregroundColor(vm.state.won ? TVTheme.green : TVTheme.red)
                        Text(vm.state.won ? "DEFUSED" : "BOOM")
                            .font(.system(size: 64, weight: .heavy)).tracking(6)
                            .foregroundColor(vm.state.won ? TVTheme.green : TVTheme.red)
                            .shadow(color: .black.opacity(0.7), radius: 10)
                    }
                }

                Spacer()
                HStack(spacing: 16) {
                    ForEach(vm.state.log, id: \.self) { entry in
                        Text(entry).font(.callout)
                            .foregroundColor(entry.hasPrefix("Strike") ? TVTheme.red : TVTheme.green)
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
                triggerFlash(color: TVTheme.green, peak: 0.5, fadeDuration: 1.4)
            } else {
                triggerFlash(color: TVTheme.red, peak: 0.75, fadeDuration: 1.2)
                triggerShake(magnitude: 22)
            }
        }
    }

    // MARK: - SwiftUI-level feedback (guaranteed legible regardless of how
    // the 3D scene's own lighting/material flash happens to render)

    private func triggerStrikeFeedback() {
        triggerFlash(color: TVTheme.red, peak: 0.4, fadeDuration: 0.5)
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

    private var currentName: String? {
        guard let id = vm.state.currentPlayerID else { return nil }
        return vm.state.players.first { $0.id == id }?.name
    }

    private var winnerName: String? {
        guard let winner = vm.state.winner else { return nil }
        return vm.state.players.first { $0.id == winner }?.name
    }

    private var phaseLabel: String {
        if vm.state.winner != nil { return "game over" }
        if let currentName { return "\(currentName) fires" }
        return "fire!"
    }

    private var cellSize: CGFloat {
        let n = CGFloat(max(vm.state.size, 1))
        return min(58, 500 / n)
    }

    var body: some View {
        ZStack {
            TVAnimatedBackground(palette: TVTheme.ocean)

            VStack(spacing: 0) {
                TVRoundHeader(symbol: "sailboat.fill", title: "Battleship",
                              round: 0, totalRounds: 0, secondsLeft: 0,
                              phaseLabel: phaseLabel)
                Spacer()
                HStack(alignment: .top, spacing: 70) {
                    ForEach(Array(vm.state.boards.enumerated()), id: \.offset) { index, board in
                        BattleshipFleetCard(ownerName: board.ownerName, shots: board.shots,
                                            sunk: board.sunk, size: vm.state.size, cellSize: cellSize,
                                            isTarget: isTarget(board.ownerName))
                            .tvStaggeredAppear(index: index, step: 0.15)
                    }
                }
                Spacer()
                TVScoreStrip(players: vm.state.players)
            }

            if let winnerName {
                TVWinnerBanner(title: "Admiral of the fleet", headline: winnerName,
                               symbol: "flag.checkered", accent: TVTheme.ocean.accent)
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    /// The board under fire is the one that isn't the shooter's own.
    private func isTarget(_ ownerName: String) -> Bool {
        guard vm.state.winner == nil, let currentName else { return false }
        return ownerName != currentName
    }
}

private struct BattleshipFleetCard: View {
    let ownerName: String
    let shots: [Int: String]
    let sunk: Int
    let size: Int
    let cellSize: CGFloat
    let isTarget: Bool

    var body: some View {
        TVGlassCard(cornerRadius: 30, tint: TVTheme.ocean.accent,
                    glow: isTarget ? TVTheme.ocean.accent2 : nil, padding: 28) {
            VStack(spacing: 18) {
                header
                grid
                    .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0),
                                      anchor: .center, perspective: 0.55)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isTarget)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isTarget ? "UNDER FIRE" : "FLEET").font(.caption.bold()).tracking(3)
                    .foregroundColor(isTarget ? TVTheme.ocean.accent2 : TVTheme.textSecondary)
                Text(ownerName).font(.title2.bold()).foregroundColor(.white)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            TVPopNumber(value: sunk, size: 40, color: TVTheme.ocean.accent)
            Text(sunk == 1 ? "ship sunk" : "ships sunk").font(.callout)
                .foregroundColor(TVTheme.textSecondary)
        }
    }

    private var grid: some View {
        // Only hits and misses -- fleet positions stay on the phones.
        let spacing: CGFloat = 6
        let columns: [GridItem] = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing),
                                        count: max(size, 1))
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(0..<(size * size), id: \.self) { cell in
                BattleshipCell(result: shots[cell], size: cellSize)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "0c4a6e"), Color(hex: "082f49")],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(OceanSheen().clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .shadow(color: Color.black.opacity(0.5), radius: 24, x: 0, y: 18)
    }
}

private struct BattleshipCell: View {
    let result: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(waterFill)
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            if result == "hit" {
                hitMarker.transition(.scale(scale: 0.2).combined(with: .opacity))
            } else if result == "miss" {
                missMarker.transition(.scale(scale: 1.8).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: result)
    }

    private var waterFill: LinearGradient {
        if result == "hit" {
            return LinearGradient(colors: [Color(hex: "7f1d1d"), Color(hex: "450a0a")],
                                  startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color(hex: "0e7490").opacity(0.75), Color(hex: "0c4a6e").opacity(0.6)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var hitMarker: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "fde047"), Color(hex: "f97316"), Color(hex: "dc2626")],
                                     center: .center, startRadius: 0, endRadius: size * 0.4))
                .frame(width: size * 0.72, height: size * 0.72)
                .shadow(color: Color(hex: "f97316").opacity(0.9), radius: size * 0.3)
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private var missMarker: some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 2)
                .frame(width: size * 0.6, height: size * 0.6)
            Circle().fill(Color.white.opacity(0.75))
                .frame(width: size * 0.18, height: size * 0.18)
        }
    }
}

/// A slow diagonal glint sweeping across the water.
private struct OceanSheen: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { geo in
                let t: Double = timeline.date.timeIntervalSinceReferenceDate
                let phase: CGFloat = CGFloat((t * 0.12).truncatingRemainder(dividingBy: 1))
                let travel: CGFloat = geo.size.width * 2
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.12), Color.white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.5, height: geo.size.height * 1.6)
                    .rotationEffect(.degrees(20))
                    .offset(x: -geo.size.width * 0.5 + travel * phase, y: -geo.size.height * 0.3)
            }
        }
        .allowsHitTesting(false)
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

    private static let colors: [Color] = [TVTheme.cyan, Color(hex: "fb5c8c")]

    private var leaderName: String {
        let sorted = vm.state.paddles.sorted { $0.score > $1.score }
        guard let top = sorted.first else { return "Game over" }
        if sorted.count > 1 && sorted[1].score == top.score { return "Draw" }
        return top.name
    }

    var body: some View {
        ZStack {
            // A real lit 3D table (AirHockeySceneView), driven by the same
            // AirHockeyState: puck and mallets glide between server updates,
            // strikes spark, goals flash the goal mouth and shake the camera.
            AirHockeySceneView(state: vm.state)
                .ignoresSafeArea()

            VStack {
                LinearGradient(colors: [Color.black.opacity(0.55), Color.clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 230)
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                scoreRow
                    .padding(.horizontal, 70)
                    .padding(.top, 40)
                Spacer()
            }
            .allowsHitTesting(false)

            if vm.state.finished {
                TVWinnerBanner(title: "Game over", headline: leaderName,
                               detail: "first to \(vm.state.winScore)",
                               symbol: "trophy.fill", accent: TVTheme.gold)
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private var scoreRow: some View {
        HStack(alignment: .top) {
            ForEach(Array(vm.state.paddles.enumerated()), id: \.offset) { i, p in
                AirHockeyScorePanel(name: p.name, score: p.score,
                                    color: TVAirHockeyBoardView.colors[i % 2],
                                    alignTrailing: i == 1)
                if i == 0 {
                    Spacer()
                    VStack(spacing: 4) {
                        TVGlowText(text: "AIR HOCKEY", size: 40, color: Color(hex: "7dd3fc"))
                        Text("FIRST TO \(vm.state.winScore)").font(.caption.bold()).tracking(4)
                            .foregroundColor(TVTheme.textSecondary)
                    }
                    .padding(.top, 10)
                    Spacer()
                }
            }
        }
    }
}

private struct AirHockeyScorePanel: View {
    let name: String
    let score: Int
    let color: Color
    let alignTrailing: Bool

    var body: some View {
        TVGlassCard(cornerRadius: 26, tint: color, glow: color, padding: 0) {
            HStack(spacing: 22) {
                if alignTrailing { TVPopNumber(value: score, size: 64, color: color) }
                VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 4) {
                    Text(alignTrailing ? "RIGHT GOAL" : "LEFT GOAL").font(.caption.bold()).tracking(3)
                        .foregroundColor(color.opacity(0.9))
                    Text(name).font(.title2.bold()).foregroundColor(.white)
                        .lineLimit(1).truncationMode(.tail)
                }
                if !alignTrailing { TVPopNumber(value: score, size: 64, color: color) }
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: 520, alignment: alignTrailing ? .trailing : .leading)
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
                    Image(systemName: vm.state.won ? "party.popper.fill" : "exclamationmark.triangle.fill").font(.system(size: 120)).foregroundColor(vm.state.won ? TVTheme.yellow : TVTheme.red)
                    Text(vm.state.won ? "ESCAPED" : "CAUGHT")
                        .font(.system(size: 60, weight: .heavy)).tracking(5)
                        .foregroundColor(vm.state.won ? TVTheme.green : TVTheme.red)
                }
            } else {
                // The maze itself is never drawn — only where the team has been.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(90), spacing: 8),
                                         count: vm.state.size), spacing: 8) {
                    ForEach(0..<(vm.state.size * vm.state.size), id: \.self) { cell in
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(cell == vm.state.exitCell ? TVTheme.green.opacity(0.35)
                                      : vm.state.trail.contains(cell) ? TVTheme.cyan.opacity(0.2)
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

/// Board geometry for a classic 15x15 Ludo cross board, in cell units.
/// Seat order matches the engine: 0 red (top-left), 1 green (top-right),
/// 2 yellow (bottom-right), 3 blue (bottom-left).
private enum LudoGeometry {
    /// The 52 shared track cells in path order, starting at red's start.
    /// Each entry is a (col, row) cell on the 15x15 grid.
    static let track: [(col: Int, row: Int)] = [
        (1,6),(2,6),(3,6),(4,6),(5,6),
        (6,5),(6,4),(6,3),(6,2),(6,1),(6,0),
        (7,0),(8,0),
        (8,1),(8,2),(8,3),(8,4),(8,5),
        (9,6),(10,6),(11,6),(12,6),(13,6),(14,6),
        (14,7),(14,8),
        (13,8),(12,8),(11,8),(10,8),(9,8),
        (8,9),(8,10),(8,11),(8,12),(8,13),(8,14),
        (7,14),(6,14),
        (6,13),(6,12),(6,11),(6,10),(6,9),
        (5,8),(4,8),(3,8),(2,8),(1,8),(0,8),
        (0,7),(0,6),
    ]
    /// Per-seat five-cell home stretch columns (token values 100-104).
    static let homeRun: [[(col: Int, row: Int)]] = [
        [(1,7),(2,7),(3,7),(4,7),(5,7)],
        [(7,1),(7,2),(7,3),(7,4),(7,5)],
        [(13,7),(12,7),(11,7),(10,7),(9,7)],
        [(7,13),(7,12),(7,11),(7,10),(7,9)],
    ]
    /// Top-left cell of each 6x6 home quadrant.
    static let quadrant: [(col: Int, row: Int)] = [(0,0),(9,0),(9,9),(0,9)]
    /// Token spots inside a quadrant, in quadrant-relative cell units.
    static let yardSpots: [(x: Double, y: Double)] = [(2,2),(4,2),(2,4),(4,4)]
    /// Absolute track indices of each seat's start cell.
    static let startAbs = [0, 13, 26, 39]
    /// Absolute track indices of the star (safe) cells; starts are safe too.
    static let starAbs: Set<Int> = [8, 21, 34, 47]
}

/// A drawable token position: yard spot, shared track cell, colour home
/// column cell, or the finished centre.
private enum LudoPos: Hashable {
    case yard(seat: Int, token: Int)
    case track(abs: Int)
    case homeRun(seat: Int, step: Int)
    case center
}

/// Maps an engine token value onto a drawable position.
/// Engine value space: -1 yard, 0-51 own track, 100-104 home column, 105 home.
private func ludoPos(seat: Int, token: Int, raw: Int) -> LudoPos {
    if raw < 0 { return .yard(seat: seat, token: token) }
    if raw >= 105 { return .center }
    if raw >= 100 { return .homeRun(seat: seat, step: raw - 100) }
    return .track(abs: (seat * 13 + raw) % 52)
}

/// Centre of a drawable position, in cell units on the 15x15 grid.
private func ludoPoint(_ pos: LudoPos) -> CGPoint {
    switch pos {
    case .yard(let seat, let token):
        let q = LudoGeometry.quadrant[seat % 4]
        let s = LudoGeometry.yardSpots[token % 4]
        return CGPoint(x: Double(q.col) + s.x, y: Double(q.row) + s.y)
    case .track(let abs):
        let c = LudoGeometry.track[abs % 52]
        return CGPoint(x: Double(c.col) + 0.5, y: Double(c.row) + 0.5)
    case .homeRun(let seat, let step):
        let c = LudoGeometry.homeRun[seat % 4][step % 5]
        return CGPoint(x: Double(c.col) + 0.5, y: Double(c.row) + 0.5)
    case .center:
        return CGPoint(x: 7.5, y: 7.5)
    }
}

/// Raw token values stepped through to animate one move hop-by-hop,
/// in the engine's own value space.
private func ludoHops(from: Int, to: Int) -> [Int] {
    if from == to { return [] }
    if to < 0 { return [to] }                  // captured: hop straight home
    var path: [Int] = []
    var cur = from
    if cur < 0 { cur = 0; path.append(0) }     // leaving the yard lands on start
    var safety = 0
    while cur != to && safety < 70 {
        safety += 1
        if cur >= 100 { cur += 1 }
        else { cur += 1; if cur >= 52 { cur = 100 } }
        path.append(cur)
    }
    return path
}

/// Steps tokens through intermediate tiles instead of teleporting them.
/// The server only broadcasts snapshots, so this keeps the last displayed
/// raw value per token and expands each change into its hop path.
@MainActor
private final class LudoAnimator: ObservableObject {
    @Published var shownRaw: [Int: Int] = [:]   // key seat*4+token -> raw value
    private var pending: [Int: [Int]] = [:]
    private var stepping = false

    func ingest(seats: [(seat: Int, tokens: [Int])]) {
        for s in seats {
            for (i, raw) in s.tokens.enumerated() {
                let k = s.seat * 4 + i
                guard let cur = shownRaw[k] else {
                    shownRaw[k] = raw      // first sight: place instantly
                    continue
                }
                let start = pending[k]?.last ?? cur
                if start != raw {
                    pending[k] = ludoHops(from: start, to: raw)
                }
            }
        }
        pump()
    }

    private func pump() {
        guard !stepping else { return }
        guard pending.values.contains(where: { !$0.isEmpty }) else { return }
        stepping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.step()
        }
    }

    private func step() {
        for k in pending.keys {
            if let next = pending[k]?.first {
                shownRaw[k] = next
                pending[k]?.removeFirst()
            }
        }
        stepping = false
        pump()
    }
}

struct LudoState {
    var die = 0
    var rolled = false
    var secondsLeft = 0
    var currentPlayerID: String? = nil
    var seats: [(id: String, name: String, seat: Int, tokens: [Int])] = []
    /// The current player's legal moves with destinations, from the server.
    /// `destAbs` is the shared 0-51 track cell; nil means a home-run column.
    var legal: [(token: Int, dest: Int, destAbs: Int?)] = []
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        if let v = d["die"]?.value as? Int { die = v }
        if let v = d["rolled"]?.value as? Bool { rolled = v }
        if let v = d["secondsLeft"]?.value as? Int { secondsLeft = v }
        currentPlayerID = d["currentPlayerID"]?.value as? String
        winner = d["winner"]?.value as? String
        players = BoardPlayer.list(from: d["players"]?.value)
        seats = (d["seats"]?.value as? [Any] ?? []).compactMap {
            guard let s = $0 as? [String: Any] else { return nil }
            return (s["playerID"] as? String ?? "",
                    s["name"] as? String ?? "",
                    s["seat"] as? Int ?? 0,
                    (s["tokens"] as? [Any] ?? []).compactMap { $0 as? Int })
        }
        legal = (d["legal"]?.value as? [Any] ?? []).compactMap {
            guard let m = $0 as? [String: Any],
                  let t = m["token"] as? Int,
                  let dv = m["dest"] as? Int else { return nil }
            return (t, dv, m["destAbs"] as? Int)
        }
    }
}

struct TVLudoBoardView: View {
    let room: Room
    @StateObject private var vm = TVBoardModel(initial: LudoState()) { $0.update(from: $1) }
    @StateObject private var animator = LudoAnimator()

    private let seatColors: [Color] = [TVTheme.red, TVTheme.green, TVTheme.yellow, TVTheme.blue]

    /// Changes only when a raw token value changes; drives the hop animation.
    private var tokenSignature: String {
        vm.state.seats
            .sorted { $0.seat < $1.seat }
            .map { seat in "\(seat.seat):\(seat.tokens.map(String.init).joined(separator: ","))" }
            .joined(separator: "|")
    }

    private var currentSeat: Int? {
        vm.state.seats.first { $0.id == vm.state.currentPlayerID }?.seat
    }

    private var currentName: String {
        vm.state.seats.first { $0.id == vm.state.currentPlayerID }?.name ?? ""
    }

    private var winnerName: String? {
        guard let w = vm.state.winner, !w.isEmpty else { return nil }
        return vm.state.seats.first { $0.id == w }?.name
    }

    private var phaseText: String {
        guard !currentName.isEmpty else { return "waiting to start" }
        if vm.state.winner != nil { return "game over" }
        return vm.state.rolled ? "\(currentName)'s turn - pick a token"
                               : "\(currentName)'s turn - roll the dice"
    }

    /// Animator keys (seat*4+token) the current player may move right now.
    private var movableKeys: Set<Int> {
        guard let cs = currentSeat else { return [] }
        return Set(vm.state.legal.map { cs * 4 + $0.token })
    }

    private func startColor(abs: Int) -> Color? {
        guard let seat = LudoGeometry.startAbs.firstIndex(of: abs) else { return nil }
        return seatColors[seat % 4]
    }

    var body: some View {
        VStack(spacing: 0) {
            TVRoundHeader(symbol: "dice.fill", title: "Ludo", round: 0, totalRounds: 0,
                          secondsLeft: vm.state.secondsLeft, phaseLabel: phaseText)
            Spacer()
            HStack(spacing: 48) {
                GeometryReader { geo in
                    let cell = min(geo.size.width, geo.size.height) / 15
                    ZStack {
                        LudoBoardBase(cell: cell, colors: seatColors)
                        ForEach(0..<52, id: \.self) { abs in
                            LudoTrackCell(abs: abs, cell: cell, startColor: startColor(abs: abs))
                        }
                        ForEach(0..<4, id: \.self) { seat in
                            ForEach(0..<5, id: \.self) { step in
                                LudoHomeRunCell(seat: seat, step: step, cell: cell,
                                                color: seatColors[seat % 4])
                            }
                        }
                        if let cs = currentSeat {
                            ForEach(Array(vm.state.legal.enumerated()), id: \.offset) { _, move in
                                LudoDestinationRing(
                                    pos: ludoPos(seat: cs, token: move.token, raw: move.dest),
                                    cell: cell)
                            }
                        }
                        LudoTokensLayer(shownRaw: animator.shownRaw,
                                        movable: movableKeys,
                                        colors: seatColors, cell: cell)
                    }
                    .frame(width: cell * 15, height: cell * 15)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .aspectRatio(1, contentMode: .fit)
                LudoSidePanel(state: vm.state, colors: seatColors, currentSeat: currentSeat)
                    .frame(width: 380)
            }
            .padding(.horizontal, 60)
            Spacer()
            TVScoreStrip(players: vm.state.players)
        }
        .onAppear { vm.bind(roomCode: room.code) }
        .onChange(of: tokenSignature) { _ in
            animator.ingest(seats: vm.state.seats.map { ($0.seat, $0.tokens) })
        }
        .overlay {
            if let winnerName {
                LudoWinnerBanner(name: winnerName)
            }
        }
    }
}

/// Board backdrop: dark pitch, four coloured home quadrants with white yard
/// boxes, and the centre home triangle.
private struct LudoBoardBase: View {
    let cell: CGFloat
    let colors: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.6)
                .fill(Color(hex: "0e1830"))
                .frame(width: cell * 15, height: cell * 15)
            ForEach(0..<4, id: \.self) { seat in
                LudoQuadrant(seat: seat, cell: cell, color: colors[seat % 4])
            }
            LudoCenter(cell: cell, colors: colors)
        }
    }
}

/// One 6x6 coloured home quadrant with its white yard box and four spots.
private struct LudoQuadrant: View {
    let seat: Int
    let cell: CGFloat
    let color: Color

    var body: some View {
        let q = LudoGeometry.quadrant[seat % 4]
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.5)
                .fill(color.opacity(0.88))
                .frame(width: cell * 6, height: cell * 6)
            RoundedRectangle(cornerRadius: cell * 0.35)
                .fill(.white)
                .frame(width: cell * 4.4, height: cell * 4.4)
            ForEach(0..<4, id: \.self) { i in
                let s = LudoGeometry.yardSpots[i]
                Circle()
                    .fill(color.opacity(0.25))
                    .frame(width: cell * 0.9, height: cell * 0.9)
                    .offset(x: CGFloat(s.x - 3) * cell, y: CGFloat(s.y - 3) * cell)
            }
        }
        .position(x: (CGFloat(q.col) + 3) * cell, y: (CGFloat(q.row) + 3) * cell)
    }
}

/// The 3x3 centre with four coloured home triangles.
private struct LudoCenter: View {
    let cell: CGFloat
    let colors: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.3)
                .fill(Color(hex: "1b2a4d"))
                .frame(width: cell * 3, height: cell * 3)
            ForEach(0..<4, id: \.self) { seat in
                LudoHomeTriangle(seat: seat, cell: cell, color: colors[seat % 4])
            }
            RoundedRectangle(cornerRadius: cell * 0.3)
                .stroke(.white.opacity(0.5), lineWidth: 2)
                .frame(width: cell * 3, height: cell * 3)
        }
        .position(x: 7.5 * cell, y: 7.5 * cell)
    }
}

private struct LudoHomeTriangle: View {
    let seat: Int
    let cell: CGFloat
    let color: Color

    /// Unit space over the 3x3 centre box; the apex is the board centre.
    private var points: [CGPoint] {
        switch seat % 4 {
        case 0: return [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 1.5, y: 1.5)]
        case 1: return [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0), CGPoint(x: 1.5, y: 1.5)]
        case 2: return [CGPoint(x: 3, y: 0), CGPoint(x: 3, y: 3), CGPoint(x: 1.5, y: 1.5)]
        default: return [CGPoint(x: 0, y: 3), CGPoint(x: 3, y: 3), CGPoint(x: 1.5, y: 1.5)]
        }
    }

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: points[0].x * cell, y: points[0].y * cell))
            path.addLine(to: CGPoint(x: points[1].x * cell, y: points[1].y * cell))
            path.addLine(to: CGPoint(x: points[2].x * cell, y: points[2].y * cell))
            path.closeSubpath()
        }
        .fill(color)
        .frame(width: cell * 3, height: cell * 3)
        .position(x: 7.5 * cell, y: 7.5 * cell)
    }
}

/// One of the 52 numbered track cells: high-contrast number, star watermark
/// on safe cells, seat-colour fill on start cells.
private struct LudoTrackCell: View {
    let abs: Int
    let cell: CGFloat
    let startColor: Color?

    private var isStar: Bool { LudoGeometry.starAbs.contains(abs) }

    var body: some View {
        let c = LudoGeometry.track[abs]
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.18)
                .fill(startColor ?? Color.white.opacity(0.94))
            if isStar {
                Image(systemName: "star.fill")
                    .font(.system(size: cell * 0.6))
                    .foregroundColor(Color(hex: "b8860b").opacity(0.4))
            }
            Text("\(abs + 1)")
                .font(.system(size: cell * 0.32, weight: .bold))
                .foregroundColor(startColor == nil ? Color(hex: "1a2340") : .white)
        }
        .frame(width: cell * 0.94, height: cell * 0.94)
        .position(x: (CGFloat(c.col) + 0.5) * cell, y: (CGFloat(c.row) + 0.5) * cell)
    }
}

/// One cell of a colour home-stretch column (token values 100-104).
private struct LudoHomeRunCell: View {
    let seat: Int
    let step: Int
    let cell: CGFloat
    let color: Color

    var body: some View {
        let c = LudoGeometry.homeRun[seat % 4][step % 5]
        ZStack {
            RoundedRectangle(cornerRadius: cell * 0.18)
                .fill(color.opacity(0.92))
            Text("\(step + 1)")
                .font(.system(size: cell * 0.3, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: cell * 0.94, height: cell * 0.94)
        .position(x: (CGFloat(c.col) + 0.5) * cell, y: (CGFloat(c.row) + 0.5) * cell)
    }
}

/// Pulsing highlight on a legal destination tile for the current player.
private struct LudoDestinationRing: View {
    let pos: LudoPos
    let cell: CGFloat
    @State private var pulse = false

    var body: some View {
        let p = ludoPoint(pos)
        RoundedRectangle(cornerRadius: cell * 0.22)
            .stroke(Color.white, lineWidth: 5)
            .frame(width: cell * 1.02, height: cell * 1.02)
            .scaleEffect(pulse ? 1.1 : 0.95)
            .opacity(pulse ? 1.0 : 0.6)
            .position(x: p.x * cell, y: p.y * cell)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private struct LudoToken: View {
    let color: Color
    let diameter: CGFloat
    let movable: Bool

    var body: some View {
        ZStack {
            if movable {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: diameter * 1.4, height: diameter * 1.4)
            }
            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
    }
}

/// All tokens at their animated positions, stacked when sharing a cell.
/// Tokens the current player may move get a bright selection halo.
private struct LudoTokensLayer: View {
    let shownRaw: [Int: Int]   // key seat*4+token -> raw engine value
    let movable: Set<Int>
    let colors: [Color]
    let cell: CGFloat

    private struct PlacedToken: Identifiable {
        let id: Int
        let pos: LudoPos
        let color: Color
        let movable: Bool
    }

    private var placed: [PlacedToken] {
        var out: [PlacedToken] = []
        for (key, raw) in shownRaw {
            let seat = key / 4, token = key % 4
            out.append(PlacedToken(id: key,
                                  pos: ludoPos(seat: seat, token: token, raw: raw),
                                  color: colors[seat % 4],
                                  movable: movable.contains(key)))
        }
        return out.sorted { $0.id < $1.id }
    }

    private static func stackOffset(index: Int, count: Int) -> CGPoint {
        guard count > 1 else { return .zero }
        let d: CGFloat = 0.19
        if count == 2 { return CGPoint(x: index == 0 ? -d : d, y: 0) }
        let spots = [CGPoint(x: -d, y: -d), CGPoint(x: d, y: -d),
                     CGPoint(x: -d, y: d), CGPoint(x: d, y: d)]
        return spots[index % 4]
    }

    var body: some View {
        ZStack {
            ForEach(placed) { t in
                let p = ludoPoint(t.pos)
                let siblings = placed.filter { $0.pos == t.pos }
                let idx = siblings.firstIndex { $0.id == t.id } ?? 0
                let off = LudoTokensLayer.stackOffset(index: idx, count: siblings.count)
                LudoToken(color: t.color, diameter: cell * 0.72, movable: t.movable)
                    .position(x: (p.x + off.x) * cell, y: (p.y + off.y) * cell)
                    .animation(.easeInOut(duration: 0.18), value: p)
            }
        }
    }
}

/// Turn card plus per-player home progress on the side of the board.
private struct LudoSidePanel: View {
    let state: LudoState
    let colors: [Color]
    let currentSeat: Int?

    private func finishedCount(_ tokens: [Int]) -> Int {
        tokens.filter { $0 >= 105 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let cs = currentSeat,
               let seat = state.seats.first(where: { $0.seat == cs }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TURN").font(.caption.bold()).tracking(3)
                        .foregroundColor(.white.opacity(0.5))
                    HStack(spacing: 12) {
                        Circle().fill(colors[cs % 4]).frame(width: 26, height: 26)
                        Text(seat.name).font(.title2.bold()).foregroundColor(.white)
                        Spacer()
                        Text(state.rolled ? "\(state.die)" : "-")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text(state.rolled ? "Pick a token - highlighted on the board"
                                      : "Roll the dice on your phone")
                        .font(.callout).foregroundColor(.white.opacity(0.6))
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(colors[cs % 4].opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(colors[cs % 4], lineWidth: 3)))
            }
            ForEach(state.seats.sorted { $0.seat < $1.seat }, id: \.seat) { seat in
                let active = seat.seat == currentSeat
                let done = finishedCount(seat.tokens)
                HStack(spacing: 12) {
                    Circle().fill(colors[seat.seat % 4]).frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(seat.name).font(.headline)
                            .foregroundColor(active ? .white : .white.opacity(0.55))
                        HStack(spacing: 6) {
                            ForEach(0..<4, id: \.self) { i in
                                let v = i < seat.tokens.count ? seat.tokens[i] : -1
                                Circle()
                                    .fill(v >= 105 ? .white
                                          : v >= 0 ? colors[seat.seat % 4] : .white.opacity(0.18))
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                    Spacer()
                    Text("\(done)/4")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(active ? .white : .white.opacity(0.55))
                    Text("HOME").font(.caption.bold()).tracking(2)
                        .foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14)
                    .fill(active ? .white.opacity(0.12) : .white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .stroke(active ? colors[seat.seat % 4] : .clear, lineWidth: 2)))
            }
            Spacer()
        }
    }
}

private struct LudoWinnerBanner: View {
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Text("WINNER").font(.caption.bold()).tracking(4)
                .foregroundColor(.white.opacity(0.7))
            Text(name).font(.system(size: 64, weight: .heavy)).foregroundColor(.white)
        }
        .padding(.horizontal, 70).padding(.vertical, 36)
        .background(RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.78))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(TVTheme.yellow, lineWidth: 3)))
    }
}

// MARK: - Carrom

struct CarromState {
    var board: Double = 100
    var coins: [(id: Int, x: Double, y: Double, kind: String)] = []
    var strikerX: Double = 50
    var currentPlayerID: String? = nil
    var targetScore = 8
    var shotsLeft: Int? = nil
    var winner: String? = nil
    var players: [BoardPlayer] = []

    mutating func update(from d: [String: AnyCodable]) {
        shotsLeft = d["shotsLeft"]?.value as? Int
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

    private var phaseText: String {
        if let left = vm.state.shotsLeft {
            return "first to \(vm.state.targetScore)  -  \(left) shots left"
        }
        return "first to \(vm.state.targetScore)"
    }

    private var winnerName: String? {
        guard let id = vm.state.winner else { return nil }
        return vm.state.players.first { $0.id == id }?.name
    }

    var body: some View {
        ZStack {
            // A real lit 3D board (CarromSceneView): lacquered surface,
            // PBR coins that slide to rest after each shot, pockets that
            // flare and spark when a coin drops. Same CarromState as before.
            CarromSceneView(state: vm.state)
                .ignoresSafeArea()

            HStack {
                LinearGradient(colors: [Color.black.opacity(0.6), Color.clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 520)
                Spacer()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                TVRoundHeader(symbol: "circle.dashed", title: "Carrom", round: 0, totalRounds: 0,
                              secondsLeft: 0, phaseLabel: phaseText)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(vm.state.players.enumerated()), id: \.element.id) { index, player in
                            CarromPlayerRow(player: player,
                                            isCurrent: player.id == vm.state.currentPlayerID,
                                            target: vm.state.targetScore)
                                .tvStaggeredAppear(index: index)
                        }
                    }
                    .frame(width: 400)
                    .padding(.leading, 70)
                    .padding(.top, 30)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(false)

            if let winnerName {
                TVWinnerBanner(title: "Winner", headline: winnerName,
                               detail: "first to \(vm.state.targetScore)")
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

private struct CarromPlayerRow: View {
    let player: BoardPlayer
    let isCurrent: Bool
    let target: Int

    private var progress: CGFloat {
        guard target > 0 else { return 0 }
        return CGFloat(min(1, Double(player.score) / Double(target)))
    }

    var body: some View {
        TVGlassCard(cornerRadius: 22, tint: isCurrent ? TVTheme.gold : Color.white,
                    glow: isCurrent ? TVTheme.gold : nil, padding: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if isCurrent {
                        Image(systemName: "scope").foregroundColor(TVTheme.gold)
                    }
                    Text(player.name).font(.title3.bold()).foregroundColor(.white)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer()
                    TVPopNumber(value: player.score, size: 40,
                                color: isCurrent ? TVTheme.gold : Color(hex: "fde68a"))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient(colors: [Color(hex: "f59e0b"), Color(hex: "fde68a")],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .scaleEffect(isCurrent ? 1.04 : 1, anchor: .leading)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isCurrent)
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
        ["", "High Card", "Pair", "Colour", "Sequence", "Pure Sequence", "Trail"][min(max(r, 0), 6)]
    }

    private var winnerName: String? {
        guard let id = vm.state.winner else { return nil }
        return vm.state.players.first { $0.id == id }?.name
    }

    var body: some View {
        ZStack {
            TVAnimatedBackground(palette: TVTheme.ember)

            VStack(spacing: 0) {
                header
                Spacer()
                if vm.state.showdown.isEmpty {
                    seatsTable
                } else {
                    showdownTable
                }
                Spacer()
                TVScoreStrip(players: vm.state.players)
            }

            if winnerName != nil {
                TVConfettiBurst(trigger: 1, fireOnAppear: true)
                    .ignoresSafeArea()
            }
        }
        .onAppear { vm.bind(roomCode: room.code) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 30) {
            TVGlowText(text: "Teen Patti", size: 52, color: TVTheme.gold)
            Spacer()
            TPChipBadge(label: "STAKE", value: vm.state.currentStake, color: Color(hex: "fda4af"), glows: false)
            TPChipBadge(label: "POT", value: vm.state.pot, color: TVTheme.gold, glows: true)
        }
        .padding(.horizontal, 70).padding(.top, 44)
    }

    /// Cards stay on the phones until showdown; seats show fanned backs.
    private var seatsTable: some View {
        ZStack {
            TPFeltTable()
                .frame(width: 1500, height: 560)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 4), spacing: 24) {
                ForEach(Array(vm.state.seats.enumerated()), id: \.offset) { index, seat in
                    TPSeatCard(name: seat.name, chips: seat.chips, stake: seat.stake,
                               folded: seat.folded, blind: seat.blind,
                               isCurrent: seat.id == vm.state.currentPlayerID)
                        .tvStaggeredAppear(index: index)
                }
            }
            .padding(.horizontal, 110)
        }
    }

    /// Card height for the showdown, shrinking so every hand still fits
    /// between the header and the score strip in a full room.
    private var showdownCardHeight: CGFloat {
        let n = CGFloat(max(vm.state.showdown.count, 1))
        let fit: CGFloat = (700 - 14 * (n - 1)) / n - 28
        return min(130, max(56, fit))
    }

    private var showdownTable: some View {
        VStack(spacing: 14) {
            ForEach(Array(vm.state.showdown.enumerated()), id: \.offset) { index, hand in
                TPShowdownRow(name: hand.name, cards: hand.cards, rankName: rankName(hand.rank),
                              isWinner: hand.name == winnerName, rowIndex: index,
                              cardHeight: showdownCardHeight)
                    .tvStaggeredAppear(index: index, step: 0.12)
            }
        }
        .padding(.horizontal, 160)
    }
}

private struct TPChipBadge: View {
    let label: String
    let value: Int
    let color: Color
    let glows: Bool

    var body: some View {
        TVGlassCard(cornerRadius: 24, tint: color, glow: glows ? color : nil, padding: 0) {
            HStack(spacing: 14) {
                chip
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.caption.bold()).tracking(3).foregroundColor(TVTheme.textSecondary)
                    TVPopNumber(value: value, size: 40, color: color)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
    }

    private var chip: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color, color.opacity(0.45)],
                                         center: .topLeading, startRadius: 2, endRadius: 40))
            Circle().strokeBorder(Color.white.opacity(0.75),
                                  style: StrokeStyle(lineWidth: 4, dash: [6, 5]))
                .padding(5)
        }
        .frame(width: 46, height: 46)
        .shadow(color: color.opacity(0.6), radius: 10)
    }
}

/// An oval felt table, tilted back in 3D so the seats sit "on" it.
private struct TPFeltTable: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: "a16207"), Color(hex: "78350f"), Color(hex: "451a03")],
                                     startPoint: .top, endPoint: .bottom))
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: "15803d"), Color(hex: "14532d"), Color(hex: "052e16")],
                                     center: .center, startRadius: 40, endRadius: 760))
                .padding(28)
            Ellipse()
                .strokeBorder(TVTheme.gold.opacity(0.45), lineWidth: 3)
                .padding(56)
        }
        .rotation3DEffect(.degrees(42), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.4)
        .shadow(color: Color.black.opacity(0.6), radius: 40, x: 0, y: 30)
        .allowsHitTesting(false)
    }
}

private struct TPSeatCard: View {
    let name: String
    let chips: Int
    let stake: Int
    let folded: Bool
    let blind: Bool
    let isCurrent: Bool

    var body: some View {
        TVGlassCard(cornerRadius: 24, tint: isCurrent ? TVTheme.gold : Color.white,
                    glow: isCurrent ? TVTheme.gold : nil, padding: 0) {
            VStack(spacing: 12) {
                fan
                Text(name).font(.title3.bold())
                    .foregroundColor(folded ? Color.white.opacity(0.35) : Color.white)
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 8) {
                    Image(systemName: "circle.hexagongrid.fill").foregroundColor(TVTheme.gold)
                    TVPopNumber(value: chips, size: 28, color: Color(hex: "fde68a"), glow: false)
                }
                badge
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .scaleEffect(isCurrent ? 1.06 : 1)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isCurrent)
    }

    private var fan: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                TPCardBack(width: 52, height: 74)
                    .rotationEffect(.degrees(Double(i - 1) * (folded ? 4 : 12)), anchor: .bottom)
                    .offset(x: CGFloat(i - 1) * (folded ? 6 : 16), y: folded ? 14 : 0)
            }
        }
        .frame(height: 92)
        .opacity(folded ? 0.35 : 1)
        .saturation(folded ? 0 : 1)
        .rotation3DEffect(.degrees(folded ? 55 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: folded)
    }

    @ViewBuilder private var badge: some View {
        if folded {
            Text("FOLDED").font(.caption.bold()).tracking(2).foregroundColor(TVTheme.textTertiary)
        } else if blind {
            Text("BLIND").font(.caption.bold()).tracking(2).foregroundColor(TVTheme.orange)
        } else if stake > 0 {
            Text("IN FOR \(stake)").font(.caption.bold()).tracking(2).foregroundColor(TVTheme.textSecondary)
        } else {
            Text("SEEN").font(.caption.bold()).tracking(2).foregroundColor(TVTheme.textSecondary)
        }
    }
}

private struct TPCardBack: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .fill(Color.white)
            RoundedRectangle(cornerRadius: width * 0.09, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "9f1239"), Color(hex: "4c0519")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(width * 0.07)
            RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
                .strokeBorder(TVTheme.gold.opacity(0.8), lineWidth: 1.5)
                .padding(width * 0.14)
            Image(systemName: "suit.diamond.fill")
                .font(.system(size: width * 0.34))
                .foregroundColor(TVTheme.gold.opacity(0.85))
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.45), radius: 6, x: 0, y: 4)
    }
}

private struct TPCardFace: View {
    let rank: Int
    let suit: String
    let width: CGFloat
    let height: CGFloat

    private var label: String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        default: return "\(rank)"
        }
    }

    /// Hearts (U+2665) and diamonds (U+2666) print red.
    private var ink: Color {
        if suit == "\u{2665}" || suit == "\u{2666}" { return Color(hex: "dc2626") }
        return Color(hex: "111827")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(hex: "f5f0e6")],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            Text(suit).font(.system(size: width * 0.5)).foregroundColor(ink)
            corner
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 6)
    }

    private var corner: some View {
        VStack(spacing: -4) {
            Text(label).font(.system(size: width * 0.27, weight: .heavy, design: .rounded))
            Text(suit).font(.system(size: width * 0.2))
        }
        .foregroundColor(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(width * 0.08)
    }
}

/// One revealed card: arrives face down and flips over in 3D after `delay`.
private struct TPRevealCard: View {
    let rank: Int
    let suit: String
    let delay: Double
    let height: CGFloat

    @State private var faceUp = false

    var body: some View {
        TVFlipCard(isFaceUp: faceUp) {
            TPCardFace(rank: rank, suit: suit, width: height * 0.7, height: height)
        } back: {
            TPCardBack(width: height * 0.7, height: height)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) { faceUp = true }
            }
        }
    }
}

private struct TPShowdownRow: View {
    let name: String
    let cards: [(rank: Int, suit: String)]
    let rankName: String
    let isWinner: Bool
    let rowIndex: Int
    let cardHeight: CGFloat

    var body: some View {
        TVGlassCard(cornerRadius: 26, tint: isWinner ? TVTheme.gold : Color.white,
                    glow: isWinner ? TVTheme.gold : nil, padding: 0) {
            HStack(spacing: 28) {
                nameLabel
                HStack(spacing: 14) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                        TPRevealCard(rank: card.rank, suit: card.suit,
                                     delay: 0.35 + Double(rowIndex) * 0.45 + Double(i) * 0.15,
                                     height: cardHeight)
                    }
                }
                Spacer()
                rankPill
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 14)
        }
    }

    private var nameLabel: some View {
        HStack(spacing: 10) {
            if isWinner {
                Image(systemName: "crown.fill").foregroundColor(TVTheme.gold)
            }
            Text(name).font(.title2.bold()).foregroundColor(.white)
                .lineLimit(1).truncationMode(.tail)
        }
        .frame(width: 280, alignment: .leading)
    }

    private var rankPill: some View {
        Text(rankName.uppercased())
            .font(.headline.weight(.heavy)).tracking(2)
            .foregroundColor(isWinner ? Color.black : TVTheme.gold)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Capsule().fill(isWinner ? TVTheme.gold : TVTheme.gold.opacity(0.14)))
    }
}
