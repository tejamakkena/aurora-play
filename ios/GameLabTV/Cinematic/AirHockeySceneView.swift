import SwiftUI
import SceneKit
import UIKit

/// Air Hockey as a lit 3D table seen from the side: polished ice with
/// clear-coat reflections, chrome rails with LED strips, glossy emissive
/// mallets, a glowing puck with a comet trail, sparks on every strike and a
/// goal-mouth flash, burst and camera shake on every goal.
///
/// The engine's rink is portrait (x across 0...width, y along 0...height,
/// mallet 0 guarding y = 0 and mallet 1 guarding y = height). Here the long
/// axis runs left -> right across the TV: world X follows the engine's y and
/// world Z its x, so player 0 defends the left goal and player 1 the right.
/// Positions are normalised against the live width/height, so the table
/// always matches the engine's own proportions of play.
struct AirHockeySceneView: UIViewRepresentable {
    var state: AirHockeyState

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

        /// World size of the playing surface (long axis, short axis).
        static let length: Float = 16
        static let width: Float = 10

        static let colors: [UIColor] = [
            UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1),
            UIColor(red: 0.98, green: 0.36, blue: 0.55, alpha: 1),
        ]

        private let effectsRoot = SCNNode()
        private let puckNode = SCNNode()
        private var malletNodes: [SCNNode] = []
        private var malletBodies: [SCNNode] = []
        private var goalMaterials: [SCNMaterial] = []

        private var builtPaddleWidth: Double = -1
        private var lastPuck: SIMD2<Float>?
        private var lastVelocity = SIMD2<Float>(0, 0)
        private var lastScores: [Int] = []

        init() {
            let shot = CameraShot(position: SCNVector3(0, 12.6, 11.4),
                                  lookAt: SCNVector3(0, -0.6, 0.4),
                                  fieldOfView: 42,
                                  focusDistance: 17)
            cameraRig = CinematicCameraRig(initialShot: shot)
            lighting = CinematicLighting(tableRadius: 7)
            ArcadeFX.tuneForArcade(cameraRig, orbit: 0.3)
            cameraRig.camera.bloomThreshold = 0.9
            lighting.keyNode.light?.intensity = 1300
            lighting.fillNode.light?.intensity = 300

            ArcadeFX.dressScene(scene,
                                top: UIColor(red: 0.01, green: 0.03, blue: 0.09, alpha: 1),
                                horizon: UIColor(red: 0.04, green: 0.2, blue: 0.36, alpha: 1),
                                bottom: UIColor(red: 0.0, green: 0.02, blue: 0.05, alpha: 1))

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)
            scene.rootNode.addChildNode(effectsRoot)

            buildTable()
            buildActors()
        }

        // MARK: Geometry (built once)

        private func buildTable() {
            let len: Float = Coordinator.length
            let wid: Float = Coordinator.width
            let root = scene.rootNode

            root.addChildNode(ArcadeFX.floorNode(color: UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1),
                                                 y: -1.4))

            // Cabinet.
            let cabinet = SCNNode(geometry: SCNBox(width: CGFloat(len + 1.6), height: 1.3,
                                                   length: CGFloat(wid + 1.6), chamferRadius: 0.2))
            cabinet.geometry?.materials = [ArcadeFX.pbr(UIColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1),
                                                        metalness: 0.6, roughness: 0.3)]
            cabinet.position = SCNVector3(0, -0.72, 0)
            root.addChildNode(cabinet)

            // Ice: pale, very smooth, clear-coated so the lights streak on it.
            let ice = SCNNode(geometry: SCNBox(width: CGFloat(len), height: 0.06,
                                               length: CGFloat(wid), chamferRadius: 0.03))
            let iceMaterial = ArcadeFX.pbr(UIColor(red: 0.80, green: 0.90, blue: 0.98, alpha: 1),
                                           metalness: 0.0, roughness: 0.12, clearCoat: 1.0)
            iceMaterial.diffuse.contents = Coordinator.iceTexture()
            ice.geometry?.materials = [iceMaterial]
            ice.position = SCNVector3(0, -0.03, 0)
            root.addChildNode(ice)

            // Chrome rails with an LED strip along the inside edge.
            let chrome = ArcadeFX.pbr(UIColor(white: 0.78, alpha: 1), metalness: 0.95, roughness: 0.18)
            let led = ArcadeFX.neon(UIColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1), intensity: 1.1)
            for side: Float in [-1, 1] {
                let rail = SCNNode(geometry: SCNBox(width: CGFloat(len + 0.8), height: 0.36,
                                                    length: 0.4, chamferRadius: 0.12))
                rail.geometry?.materials = [chrome]
                rail.position = SCNVector3(0, 0.12, side * (wid / 2 + 0.2))
                root.addChildNode(rail)

                let strip = SCNNode(geometry: SCNBox(width: CGFloat(len), height: 0.05,
                                                     length: 0.05, chamferRadius: 0.02))
                strip.geometry?.materials = [led]
                strip.position = SCNVector3(0, 0.08, side * (wid / 2 - 0.02))
                root.addChildNode(strip)
            }

            // End rails with a glowing goal mouth in the middle of each.
            for (index, side) in [Float(-1), Float(1)].enumerated() {
                let mouth: Float = wid * 0.36
                let segment: Float = (wid - mouth) / 2
                for half: Float in [-1, 1] {
                    let piece = SCNNode(geometry: SCNBox(width: 0.4, height: 0.36,
                                                         length: CGFloat(segment + 0.4), chamferRadius: 0.12))
                    piece.geometry?.materials = [chrome]
                    piece.position = SCNVector3(side * (len / 2 + 0.2), 0.12,
                                                half * (mouth / 2 + segment / 2 + 0.2))
                    root.addChildNode(piece)
                }
                let goalMaterial = ArcadeFX.neon(Coordinator.colors[index], intensity: 0.8)
                goalMaterials.append(goalMaterial)
                let goal = SCNNode(geometry: SCNBox(width: 0.3, height: 0.12,
                                                    length: CGFloat(mouth), chamferRadius: 0.04))
                goal.geometry?.materials = [goalMaterial]
                goal.position = SCNVector3(side * (len / 2 + 0.1), -0.02, 0)
                root.addChildNode(goal)
            }
        }

        /// Rink markings painted into the ice texture: red centre line, blue
        /// lines, centre circle, goal creases and a field of air holes.
        private static func iceTexture() -> UIImage {
            let size = CGSize(width: 1600, height: 1000)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let cg = ctx.cgContext
                UIColor(red: 0.86, green: 0.93, blue: 0.99, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))

                UIColor(red: 0.62, green: 0.74, blue: 0.86, alpha: 0.55).setFill()
                var x: CGFloat = 20
                while x < size.width {
                    var y: CGFloat = 20
                    while y < size.height {
                        cg.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
                        y += 40
                    }
                    x += 40
                }

                cg.setLineWidth(10)
                UIColor(red: 0.86, green: 0.15, blue: 0.22, alpha: 0.9).setStroke()
                cg.stroke(CGRect(x: size.width / 2 - 5, y: 0, width: 10, height: size.height))
                cg.strokeEllipse(in: CGRect(x: size.width / 2 - 150, y: size.height / 2 - 150,
                                            width: 300, height: 300))

                UIColor(red: 0.15, green: 0.4, blue: 0.9, alpha: 0.85).setStroke()
                for lineX: CGFloat in [size.width * 0.3, size.width * 0.7] {
                    cg.stroke(CGRect(x: lineX - 5, y: 0, width: 10, height: size.height))
                }
                for creaseX: CGFloat in [0, size.width] {
                    cg.strokeEllipse(in: CGRect(x: creaseX - 190, y: size.height / 2 - 190,
                                                width: 380, height: 380))
                }
            }
        }

        private func buildActors() {
            for color in Coordinator.colors {
                let mallet = SCNNode()
                let body = SCNNode()
                body.castsShadow = true
                mallet.addChildNode(body)

                let knob = SCNNode(geometry: SCNCylinder(radius: 0.24, height: 0.55))
                knob.geometry?.materials = [ArcadeFX.pbr(UIColor(white: 0.12, alpha: 1),
                                                         metalness: 0.3, roughness: 0.25, clearCoat: 0.8)]
                knob.position = SCNVector3(0, 0.45, 0)
                knob.castsShadow = true
                mallet.addChildNode(knob)
                let cap = SCNNode(geometry: SCNSphere(radius: 0.26))
                cap.geometry?.materials = [ArcadeFX.neon(color, intensity: 1.8, roughness: 0.1)]
                cap.position = SCNVector3(0, 0.75, 0)
                mallet.addChildNode(cap)

                let glow = SCNLight()
                glow.type = .omni
                glow.color = color
                glow.intensity = 300
                glow.attenuationStartDistance = 0
                glow.attenuationEndDistance = 3
                let glowNode = SCNNode()
                glowNode.light = glow
                glowNode.position = SCNVector3(0, 0.9, 0)
                mallet.addChildNode(glowNode)

                scene.rootNode.addChildNode(mallet)
                malletNodes.append(mallet)
                malletBodies.append(body)
            }
            rebuildMalletBodies(paddleWidth: 18, rinkWidth: 100)

            let disc = SCNCylinder(radius: 0.32, height: 0.12)
            disc.radialSegmentCount = 48
            disc.materials = [ArcadeFX.neon(UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1), intensity: 1.6,
                                            roughness: 0.2)]
            puckNode.geometry = disc
            puckNode.castsShadow = true
            let rim = SCNNode(geometry: SCNTorus(ringRadius: 0.32, pipeRadius: 0.035))
            rim.geometry?.materials = [ArcadeFX.neon(UIColor.white, intensity: 2.2, roughness: 0.1)]
            puckNode.addChildNode(rim)
            let puckLight = SCNLight()
            puckLight.type = .omni
            puckLight.color = UIColor(red: 1.0, green: 0.8, blue: 0.35, alpha: 1)
            puckLight.intensity = 380
            puckLight.attenuationStartDistance = 0
            puckLight.attenuationEndDistance = 3
            puckNode.light = puckLight
            puckNode.addParticleSystem(ArcadeFX.trail(color: UIColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1),
                                                      size: 0.5))
            puckNode.position = SCNVector3(0, 0.07, 0)
            scene.rootNode.addChildNode(puckNode)
        }

        /// The engine's mallets are flat bars `paddleWidth` wide, so each is
        /// drawn as a glossy capsule exactly that long under its handle.
        private func rebuildMalletBodies(paddleWidth: Double, rinkWidth: Double) {
            builtPaddleWidth = paddleWidth
            let span: Float = Float(paddleWidth / max(rinkWidth, 1)) * Coordinator.width
            for (i, body) in malletBodies.enumerated() {
                let capsule = SCNCapsule(capRadius: 0.24, height: CGFloat(max(span, 0.5)))
                capsule.materials = [ArcadeFX.neon(Coordinator.colors[i % Coordinator.colors.count],
                                                   intensity: 1.2, roughness: 0.15)]
                body.geometry = capsule
                // Capsules stand along Y; lay this one along the table's Z.
                body.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
                body.position = SCNVector3(0, 0.24, 0)
            }
        }

        // MARK: Mapping

        private func world(x: Double, y: Double, state: AirHockeyState, lift: Float) -> SCNVector3 {
            let nx: Float = Float(x / max(state.width, 1))
            let ny: Float = Float(y / max(state.height, 1))
            return SCNVector3((ny - 0.5) * Coordinator.length, lift, (nx - 0.5) * Coordinator.width)
        }

        // MARK: Live state

        func apply(_ state: AirHockeyState, animated: Bool) {
            if state.paddleWidth != builtPaddleWidth {
                rebuildMalletBodies(paddleWidth: state.paddleWidth, rinkWidth: state.width)
            }

            for (i, mallet) in malletNodes.enumerated() {
                guard i < state.paddles.count else {
                    mallet.isHidden = true
                    continue
                }
                mallet.isHidden = false
                let y: Double = i == 0 ? 6 : state.height - 6
                let target = world(x: state.paddles[i].x, y: y, state: state, lift: 0)
                ArcadeFX.glide(mallet, to: target, duration: animated ? 0.09 : 0)
            }

            let puck = SIMD2<Float>(Float(state.puck.x), Float(state.puck.y))
            let target = world(x: state.puck.x, y: state.puck.y, state: state, lift: 0.07)
            if let previous = lastPuck, animated {
                let delta = puck - previous
                let jump: Float = abs(delta.x) / Float(max(state.width, 1)) + abs(delta.y) / Float(max(state.height, 1))
                if jump > 0.3 {
                    puckNode.removeAction(forKey: "glide")
                    puckNode.position = target
                } else {
                    ArcadeFX.glide(puckNode, to: target, duration: 1.0 / 30.0)
                    detectStrikes(puck: puck, delta: delta, at: target, state: state)
                }
                if delta.x != 0 || delta.y != 0 { lastVelocity = delta }
            } else {
                puckNode.position = target
            }
            lastPuck = puck

            let scores: [Int] = state.paddles.map { $0.score }
            if scores.count == lastScores.count {
                for i in scores.indices where scores[i] > lastScores[i] {
                    celebrateGoal(scorer: i)
                }
            }
            lastScores = scores
        }

        private func detectStrikes(puck: SIMD2<Float>, delta: SIMD2<Float>, at: SCNVector3, state: AirHockeyState) {
            let h: Float = Float(max(state.height, 1))
            let w: Float = Float(max(state.width, 1))
            if lastVelocity.y < 0 && delta.y > 0 && puck.y < h * 0.2 {
                ArcadeFX.emitBurst(in: effectsRoot, at: at, color: Coordinator.colors[0],
                                   count: 70, speed: 4.5, size: 0.12)
                cameraRig.shake(intensity: 0.06, duration: 0.2)
            } else if lastVelocity.y > 0 && delta.y < 0 && puck.y > h * 0.8 {
                ArcadeFX.emitBurst(in: effectsRoot, at: at, color: Coordinator.colors[1],
                                   count: 70, speed: 4.5, size: 0.12)
                cameraRig.shake(intensity: 0.06, duration: 0.2)
            }
            let sideFlip: Bool = (lastVelocity.x < 0 && delta.x > 0) || (lastVelocity.x > 0 && delta.x < 0)
            if sideFlip && (puck.x < w * 0.08 || puck.x > w * 0.92) {
                ArcadeFX.emitBurst(in: effectsRoot, at: at, color: UIColor(red: 0.6, green: 0.85, blue: 1.0, alpha: 1),
                                   count: 24, speed: 2.4, size: 0.08, lightIntensity: 350)
            }
        }

        /// Mallet 0 defends the left goal, so its points land in the right one.
        private func celebrateGoal(scorer: Int) {
            let goalIndex: Int = scorer == 0 ? 1 : 0
            let side: Float = goalIndex == 0 ? -1 : 1
            let x: Float = side * Coordinator.length / 2
            if goalIndex < goalMaterials.count {
                ArcadeFX.flash(goalMaterials[goalIndex], peak: 8, rest: 0.8, hold: 0.3)
            }
            let color: UIColor = Coordinator.colors[scorer % Coordinator.colors.count]
            for z: Float in [-1.5, 0, 1.5] {
                ArcadeFX.emitBurst(in: effectsRoot, at: SCNVector3(x, 0.5, z), color: color,
                                   count: 90, speed: 6, size: 0.14, lightIntensity: 1500)
            }
            cameraRig.shake(intensity: 0.24, duration: 0.55)
        }
    }
}
