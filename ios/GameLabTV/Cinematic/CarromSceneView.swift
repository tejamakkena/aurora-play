import SwiftUI
import SceneKit
import UIKit

/// Carrom as a lit 3D board: a lacquered birch playing surface with painted
/// markings inside a dark polished frame, recessed corner pockets with brass
/// rims, PBR coins with grooves, clear-coat shine and soft contact shadows,
/// and a glowing striker. Coins slide to their new resting places after
/// every shot; a potted coin glides into its pocket and sinks while the
/// pocket rim flares and sparks.
///
/// Board units match CarromEngine (games/native_hub/engines/duel.py): a
/// 100 x 100 board, pockets of radius 8 at the corners, coins of radius 2.5,
/// a striker of radius 3.2 on the baseline at y = 88. One board unit is 0.1
/// world units here, with the board centred on the origin.
struct CarromSceneView: UIViewRepresentable {
    var state: CarromState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = ArcadeFX.makeView(scene: context.coordinator.scene,
                                     pointOfView: context.coordinator.cameraRig.cameraNode)
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

        static let size: Float = 10
        static let strikerLine: Double = 88

        private let effectsRoot = SCNNode()
        private let strikerNode = SCNNode()
        private let strikerTrail: SCNParticleSystem
        private var coinNodes: [Int: SCNNode] = [:]
        private var coinPositions: [Int: SCNVector3] = [:]
        private var pocketRims: [SCNMaterial] = []
        private var pocketCentres: [SCNVector3] = []

        private let whiteMaterial: SCNMaterial
        private let blackMaterial: SCNMaterial
        private let queenMaterial: SCNMaterial
        private let grooveMaterial: SCNMaterial

        private var lastStrikerX: Double?
        private var trailToken = 0

        init() {
            let shot = CameraShot(position: SCNVector3(0, 11.6, 8.6),
                                  lookAt: SCNVector3(0, -0.4, 0.5),
                                  fieldOfView: 46,
                                  focusDistance: 14)
            cameraRig = CinematicCameraRig(initialShot: shot)
            lighting = CinematicLighting(tableRadius: 5)
            strikerTrail = ArcadeFX.trail(color: UIColor(red: 0.4, green: 0.9, blue: 1.0, alpha: 1), size: 0.42)
            whiteMaterial = ArcadeFX.pbr(UIColor(red: 0.96, green: 0.91, blue: 0.80, alpha: 1),
                                         metalness: 0.0, roughness: 0.32, clearCoat: 0.7)
            blackMaterial = ArcadeFX.pbr(UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),
                                         metalness: 0.0, roughness: 0.28, clearCoat: 0.7)
            let queen = ArcadeFX.pbr(UIColor(red: 0.82, green: 0.06, blue: 0.12, alpha: 1),
                                     metalness: 0.0, roughness: 0.25, clearCoat: 0.8)
            queen.emission.contents = UIColor(red: 0.6, green: 0.0, blue: 0.05, alpha: 1)
            queen.emission.intensity = 0.35
            queenMaterial = queen
            grooveMaterial = ArcadeFX.pbr(UIColor(white: 0.0, alpha: 0.35), metalness: 0, roughness: 0.6)

            ArcadeFX.tuneForArcade(cameraRig, orbit: 0.22)
            cameraRig.camera.bloomThreshold = 0.85
            cameraRig.camera.bloomIntensity = 0.8
            lighting.apply(.warm, duration: 0)
            lighting.keyNode.light?.intensity = 1500

            ArcadeFX.dressScene(scene,
                                top: UIColor(red: 0.05, green: 0.02, blue: 0.01, alpha: 1),
                                horizon: UIColor(red: 0.32, green: 0.14, blue: 0.05, alpha: 1),
                                bottom: UIColor(red: 0.03, green: 0.01, blue: 0.0, alpha: 1),
                                environmentIntensity: 1.0)

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)
            scene.rootNode.addChildNode(effectsRoot)

            buildBoard()
            buildStriker()
        }

        // MARK: Board (built once)

        private func buildBoard() {
            let s: Float = Coordinator.size
            let root = scene.rootNode

            root.addChildNode(ArcadeFX.floorNode(color: UIColor(red: 0.05, green: 0.03, blue: 0.02, alpha: 1),
                                                 y: -1.2))

            // A pedestal so the board floats above the floor like a table.
            let pedestal = SCNNode(geometry: SCNCylinder(radius: 4.2, height: 1.0))
            pedestal.geometry?.materials = [ArcadeFX.pbr(UIColor(red: 0.12, green: 0.06, blue: 0.03, alpha: 1),
                                                         metalness: 0.1, roughness: 0.4)]
            pedestal.position = SCNVector3(0, -0.7, 0)
            root.addChildNode(pedestal)

            let surface = SCNNode(geometry: SCNBox(width: CGFloat(s), height: 0.2,
                                                   length: CGFloat(s), chamferRadius: 0))
            let surfaceMaterial = ArcadeFX.pbr(UIColor.white, metalness: 0, roughness: 0.34, clearCoat: 0.9)
            surfaceMaterial.diffuse.contents = Coordinator.boardTexture()
            surface.geometry?.materials = [surfaceMaterial]
            surface.position = SCNVector3(0, -0.1, 0)
            root.addChildNode(surface)

            // Polished dark frame: four bars around the surface, raised above it.
            let frameMaterial = ArcadeFX.pbr(UIColor(red: 0.24, green: 0.10, blue: 0.04, alpha: 1),
                                             metalness: 0.05, roughness: 0.22, clearCoat: 1.0)
            let bar: Float = 0.9
            for side: Float in [-1, 1] {
                let horizontal = SCNNode(geometry: SCNBox(width: CGFloat(s + bar * 2), height: 0.5,
                                                          length: CGFloat(bar), chamferRadius: 0.1))
                horizontal.geometry?.materials = [frameMaterial]
                horizontal.position = SCNVector3(0, 0.0, side * (s / 2 + bar / 2))
                horizontal.castsShadow = true
                root.addChildNode(horizontal)

                let vertical = SCNNode(geometry: SCNBox(width: CGFloat(bar), height: 0.5,
                                                        length: CGFloat(s), chamferRadius: 0.1))
                vertical.geometry?.materials = [frameMaterial]
                vertical.position = SCNVector3(side * (s / 2 + bar / 2), 0.0, 0)
                vertical.castsShadow = true
                root.addChildNode(vertical)
            }

            // Pockets: a dark well with a brass rim that flares on a pot.
            let pocketRadius: CGFloat = 0.8
            let well = ArcadeFX.pbr(UIColor(white: 0.01, alpha: 1), metalness: 0, roughness: 0.9)
            for cx: Float in [-1, 1] {
                for cz: Float in [-1, 1] {
                    let centre = SCNVector3(cx * s / 2, 0, cz * s / 2)
                    pocketCentres.append(centre)

                    let hole = SCNNode(geometry: SCNCylinder(radius: pocketRadius, height: 0.02))
                    hole.geometry?.materials = [well]
                    hole.position = SCNVector3(centre.x, 0.006, centre.z)
                    root.addChildNode(hole)

                    let rimMaterial = ArcadeFX.pbr(UIColor(red: 0.85, green: 0.62, blue: 0.25, alpha: 1),
                                                   metalness: 0.95, roughness: 0.2)
                    rimMaterial.emission.contents = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1)
                    rimMaterial.emission.intensity = 0
                    pocketRims.append(rimMaterial)
                    let rim = SCNNode(geometry: SCNTorus(ringRadius: pocketRadius, pipeRadius: 0.06))
                    rim.geometry?.materials = [rimMaterial]
                    rim.position = SCNVector3(centre.x, 0.03, centre.z)
                    root.addChildNode(rim)
                }
            }
        }

        /// Birch with grain, the baselines, centre circles and rosette, and
        /// the corner arrows, painted once into the surface texture.
        private static func boardTexture() -> UIImage {
            let px: CGFloat = 1024
            let unit: CGFloat = px / 100
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: px, height: px))
            return renderer.image { ctx in
                let cg = ctx.cgContext
                let colors: [CGColor] = [UIColor(red: 0.96, green: 0.84, blue: 0.62, alpha: 1).cgColor,
                                         UIColor(red: 0.90, green: 0.74, blue: 0.50, alpha: 1).cgColor]
                let locations: [CGFloat] = [0, 1]
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors as CFArray, locations: locations) {
                    cg.drawRadialGradient(gradient, startCenter: CGPoint(x: px / 2, y: px / 2), startRadius: 0,
                                          endCenter: CGPoint(x: px / 2, y: px / 2), endRadius: px * 0.75,
                                          options: [.drawsAfterEndLocation])
                }

                // Wood grain: gently wavy, low-contrast strokes.
                cg.setLineWidth(1.6)
                for i in 0..<70 {
                    let y0: CGFloat = CGFloat(i) * px / 70
                    let alpha: CGFloat = 0.05 + 0.06 * CGFloat((i * 37) % 7) / 7
                    UIColor(red: 0.55, green: 0.33, blue: 0.14, alpha: alpha).setStroke()
                    let grain = UIBezierPath()
                    grain.move(to: CGPoint(x: 0, y: y0))
                    var x: CGFloat = 0
                    while x <= px {
                        let wave: CGFloat = 4 * sin(x / 90 + CGFloat(i) * 0.7) + 2 * sin(x / 31 + CGFloat(i))
                        grain.addLine(to: CGPoint(x: x, y: y0 + wave))
                        x += 16
                    }
                    grain.lineWidth = 1.6
                    grain.stroke()
                }

                let ink = UIColor(red: 0.18, green: 0.08, blue: 0.04, alpha: 0.9)
                let red = UIColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 0.95)

                // Baselines on all four sides: twin lines the striker sits
                // between, capped by red circles.
                let near: CGFloat = 12 * unit
                let gap: CGFloat = 3.2 * unit
                let from: CGFloat = 15 * unit
                let to: CGFloat = 85 * unit
                for side in 0..<4 {
                    cg.saveGState()
                    cg.translateBy(x: px / 2, y: px / 2)
                    cg.rotate(by: CGFloat(side) * CGFloat.pi / 2)
                    cg.translateBy(x: -px / 2, y: -px / 2)
                    ink.setStroke()
                    cg.setLineWidth(3)
                    let yA: CGFloat = px - near - gap
                    let yB: CGFloat = px - near + gap
                    cg.move(to: CGPoint(x: from, y: yA)); cg.addLine(to: CGPoint(x: to, y: yA))
                    cg.move(to: CGPoint(x: from, y: yB)); cg.addLine(to: CGPoint(x: to, y: yB))
                    cg.strokePath()
                    red.setFill()
                    for end in [from, to] {
                        cg.fillEllipse(in: CGRect(x: end - gap, y: px - near - gap, width: gap * 2, height: gap * 2))
                    }
                    // Corner arrow toward the centre.
                    cg.setLineWidth(3)
                    ink.setStroke()
                    cg.move(to: CGPoint(x: 9 * unit, y: px - 9 * unit))
                    cg.addLine(to: CGPoint(x: 30 * unit, y: px - 30 * unit))
                    cg.strokePath()
                    cg.strokeEllipse(in: CGRect(x: 27 * unit, y: px - 33 * unit, width: 6 * unit, height: 6 * unit))
                    cg.restoreGState()
                }

                // Centre: outer circle, rosette, inner red circle.
                let c = CGPoint(x: px / 2, y: px / 2)
                ink.setStroke()
                cg.setLineWidth(3)
                cg.strokeEllipse(in: CGRect(x: c.x - 17 * unit, y: c.y - 17 * unit, width: 34 * unit, height: 34 * unit))
                let star = UIBezierPath()
                for k in 0..<16 {
                    let r: CGFloat = k % 2 == 0 ? 14 * unit : 6 * unit
                    let a: CGFloat = CGFloat(k) / 16 * 2 * CGFloat.pi
                    let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    if k == 0 { star.move(to: p) } else { star.addLine(to: p) }
                }
                star.close()
                UIColor(red: 0.6, green: 0.12, blue: 0.08, alpha: 0.18).setFill()
                star.fill()
                ink.setStroke()
                star.lineWidth = 2
                star.stroke()
                red.setStroke()
                cg.setLineWidth(5)
                cg.strokeEllipse(in: CGRect(x: c.x - 3.4 * unit, y: c.y - 3.4 * unit, width: 6.8 * unit, height: 6.8 * unit))
            }
        }

        private func buildStriker() {
            let disc = SCNCylinder(radius: 0.32, height: 0.1)
            disc.radialSegmentCount = 48
            disc.materials = [ArcadeFX.pbr(UIColor(red: 0.88, green: 0.97, blue: 1.0, alpha: 1),
                                           metalness: 0.1, roughness: 0.18, clearCoat: 1.0)]
            strikerNode.geometry = disc
            strikerNode.castsShadow = true
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.22, pipeRadius: 0.025))
            ring.geometry?.materials = [ArcadeFX.neon(UIColor(red: 0.2, green: 0.85, blue: 1.0, alpha: 1),
                                                      intensity: 2.0)]
            ring.position = SCNVector3(0, 0.05, 0)
            strikerNode.addChildNode(ring)
            let light = SCNLight()
            light.type = .omni
            light.color = UIColor(red: 0.4, green: 0.85, blue: 1.0, alpha: 1)
            light.intensity = 160
            light.attenuationStartDistance = 0
            light.attenuationEndDistance = 1.6
            strikerNode.light = light
            strikerTrail.birthRate = 0
            strikerNode.addParticleSystem(strikerTrail)
            strikerNode.position = boardPoint(x: 50, y: Coordinator.strikerLine, lift: 0.05)
            scene.rootNode.addChildNode(strikerNode)
        }

        private func makeCoin(kind: String) -> SCNNode {
            let disc = SCNCylinder(radius: 0.25, height: 0.08)
            disc.radialSegmentCount = 40
            switch kind {
            case "queen": disc.materials = [queenMaterial]
            case "black": disc.materials = [blackMaterial]
            default: disc.materials = [whiteMaterial]
            }
            let coin = SCNNode(geometry: disc)
            coin.castsShadow = true
            let groove = SCNNode(geometry: SCNTorus(ringRadius: 0.16, pipeRadius: 0.012))
            groove.geometry?.materials = [grooveMaterial]
            groove.position = SCNVector3(0, 0.04, 0)
            coin.addChildNode(groove)
            return coin
        }

        // MARK: Mapping

        private func boardPoint(x: Double, y: Double, lift: Float) -> SCNVector3 {
            let k: Float = Coordinator.size / 100
            return SCNVector3((Float(x) - 50) * k, lift, (Float(y) - 50) * k)
        }

        // MARK: Live state

        func apply(_ state: CarromState, animated: Bool) {
            let strikerTarget = boardPoint(x: state.strikerX, y: Coordinator.strikerLine, lift: 0.05)
            if let last = lastStrikerX, animated, abs(last - state.strikerX) > 0.05 {
                ArcadeFX.glide(strikerNode, to: strikerTarget, duration: 0.14, easeOut: true)
                showStrikerTrail()
            } else if !animated || lastStrikerX == nil {
                strikerNode.position = strikerTarget
            }
            lastStrikerX = state.strikerX

            var seen = Set<Int>()
            for (index, coin) in state.coins.enumerated() {
                seen.insert(coin.id)
                let target = boardPoint(x: coin.x, y: coin.y, lift: 0.04)
                if let node = coinNodes[coin.id] {
                    let previous = coinPositions[coin.id] ?? target
                    let moved: Float = abs(previous.x - target.x) + abs(previous.z - target.z)
                    if animated && moved > 0.01 {
                        node.removeAction(forKey: "glide")
                        let wait = SCNAction.wait(duration: 0.03 * Double(index % 6))
                        let slide = SCNAction.move(to: target, duration: 0.75)
                        slide.timingMode = .easeOut
                        node.runAction(SCNAction.sequence([wait, slide]), forKey: "glide")
                    } else if !animated {
                        node.position = target
                    }
                } else {
                    let node = makeCoin(kind: coin.kind)
                    node.position = target
                    scene.rootNode.addChildNode(node)
                    coinNodes[coin.id] = node
                    if animated {
                        node.scale = SCNVector3(0.01, 0.01, 0.01)
                        node.runAction(SCNAction.scale(to: 1, duration: 0.35))
                    }
                }
                coinPositions[coin.id] = target
            }

            let gone: [Int] = coinNodes.keys.filter { !seen.contains($0) }
            for id in gone {
                guard let node = coinNodes[id] else { continue }
                coinNodes[id] = nil
                let from = coinPositions[id] ?? node.position
                coinPositions[id] = nil
                if animated {
                    pot(node, from: from)
                } else {
                    node.removeFromParentNode()
                }
            }
        }

        private func showStrikerTrail() {
            strikerTrail.birthRate = 160
            trailToken += 1
            let token = trailToken
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self, self.trailToken == token else { return }
                self.strikerTrail.birthRate = 0
            }
        }

        /// Slides a potted coin into its nearest pocket, sinks it, and makes
        /// that pocket's brass rim flare with a spark burst.
        private func pot(_ node: SCNNode, from: SCNVector3) {
            var bestIndex = 0
            var bestDistance: Float = .greatestFiniteMagnitude
            for (i, centre) in pocketCentres.enumerated() {
                let dx: Float = centre.x - from.x
                let dz: Float = centre.z - from.z
                let distance: Float = dx * dx + dz * dz
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = i
                }
            }
            guard bestIndex < pocketCentres.count else {
                node.removeFromParentNode()
                return
            }
            let pocket = pocketCentres[bestIndex]
            // Stop a little inside the board so the drop reads on screen.
            let lip = SCNVector3(pocket.x * 0.93, 0.04, pocket.z * 0.93)

            node.removeAllActions()
            let slide = SCNAction.move(to: lip, duration: 0.55)
            slide.timingMode = .easeIn
            let sink = SCNAction.group([SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.3),
                                        SCNAction.scale(to: 0.6, duration: 0.3),
                                        SCNAction.fadeOut(duration: 0.3)])
            node.runAction(SCNAction.sequence([slide, sink, SCNAction.removeFromParentNode()]))

            let rim: SCNMaterial? = bestIndex < pocketRims.count ? pocketRims[bestIndex] : nil
            let burstAt = SCNVector3(lip.x, 0.25, lip.z)
            let root = effectsRoot
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 550_000_000)
                if let rim { ArcadeFX.flash(rim, peak: 4, rest: 0, hold: 0.4) }
                ArcadeFX.emitBurst(in: root, at: burstAt, color: UIColor(red: 1.0, green: 0.78, blue: 0.3, alpha: 1),
                                   count: 80, speed: 3.5, size: 0.1, lightIntensity: 1200)
                self?.cameraRig.shake(intensity: 0.05, duration: 0.25)
            }
        }
    }
}
