import SwiftUI
import SceneKit
import UIKit

/// Pong as a lit 3D neon arena: a glossy dark table on a reflective studio
/// floor, emissive paddles and rails that bloom, a ball that carries its own
/// light and a comet trail, spark bursts on every paddle hit, and a goal
/// flash plus camera shake on every point. Built on the Cinematic kit
/// (`CinematicCameraRig` for the tilted, gently drifting camera and
/// `CinematicLighting` for the soft-shadow key light).
///
/// Server coordinates are normalised (0...1 on both axes, see PongEngine in
/// games/native_hub/engines/legacy_boards.py): x runs left -> right, y top
/// -> bottom, and a paddle covers +-PADDLE_HALF (0.12) of the height around
/// its centre. The arena maps those onto a 16 x 9 table in the x/z plane.
struct PongArenaSceneView: UIViewRepresentable {
    var state: PongState

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

        static let tableWidth: Float = 16
        static let tableDepth: Float = 9
        static let paddleHalf: Float = 0.12
        /// Distance of each paddle's centre from its end of the table, as a
        /// fraction of the width (the engine bounces the ball at 0.06).
        static let paddleInset: Float = 0.04

        static let leftColor = UIColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1)
        static let rightColor = UIColor(red: 0.96, green: 0.36, blue: 0.71, alpha: 1)

        private let effectsRoot = SCNNode()
        private let ballNode = SCNNode()
        private let leftPaddle = SCNNode()
        private let rightPaddle = SCNNode()
        private let leftGoalMaterial: SCNMaterial
        private let rightGoalMaterial: SCNMaterial

        private var lastBall: SIMD2<Float>?
        private var lastVelocity = SIMD2<Float>(0, 0)
        private var lastScoreLeft: Int?
        private var lastScoreRight: Int?

        init() {
            let width: Float = Coordinator.tableWidth
            let shot = CameraShot(position: SCNVector3(0, 12.8, 9.6),
                                  lookAt: SCNVector3(0, -0.4, 0.5),
                                  fieldOfView: 44,
                                  focusDistance: 16)
            cameraRig = CinematicCameraRig(initialShot: shot)
            lighting = CinematicLighting(tableRadius: width * 0.42)
            leftGoalMaterial = ArcadeFX.neon(Coordinator.leftColor, intensity: 0.6)
            rightGoalMaterial = ArcadeFX.neon(Coordinator.rightColor, intensity: 0.6)
            ArcadeFX.tuneForArcade(cameraRig, orbit: 0.32)
            lighting.keyNode.light?.intensity = 1500
            lighting.fillNode.light?.intensity = 260

            ArcadeFX.dressScene(scene,
                                top: UIColor(red: 0.02, green: 0.01, blue: 0.08, alpha: 1),
                                horizon: UIColor(red: 0.18, green: 0.05, blue: 0.32, alpha: 1),
                                bottom: UIColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1))

            scene.rootNode.addChildNode(cameraRig.cameraNode)
            lighting.addToScene(scene)
            scene.rootNode.addChildNode(effectsRoot)

            buildArena()
            buildActors()
        }

        // MARK: Geometry (built once)

        private func buildArena() {
            let w: Float = Coordinator.tableWidth
            let d: Float = Coordinator.tableDepth
            let root = scene.rootNode

            root.addChildNode(ArcadeFX.floorNode(color: UIColor(red: 0.03, green: 0.02, blue: 0.07, alpha: 1),
                                                 y: -0.62))

            // Table body: a deep glossy slab with a lacquered top.
            let slab = SCNNode(geometry: SCNBox(width: CGFloat(w + 1.2), height: 0.6,
                                                length: CGFloat(d + 1.2), chamferRadius: 0.18))
            slab.geometry?.materials = [ArcadeFX.pbr(UIColor(red: 0.05, green: 0.05, blue: 0.11, alpha: 1),
                                                     metalness: 0.5, roughness: 0.35)]
            slab.position = SCNVector3(0, -0.32, 0)
            root.addChildNode(slab)

            let surface = SCNNode(geometry: SCNBox(width: CGFloat(w), height: 0.04,
                                                   length: CGFloat(d), chamferRadius: 0.02))
            surface.geometry?.materials = [ArcadeFX.pbr(UIColor(red: 0.04, green: 0.07, blue: 0.16, alpha: 1),
                                                        metalness: 0.15, roughness: 0.18, clearCoat: 0.8)]
            surface.position = SCNVector3(0, -0.02, 0)
            root.addChildNode(surface)

            // Neon rails along the top and bottom walls.
            let railMaterial = ArcadeFX.neon(UIColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 1), intensity: 1.2)
            for side: Float in [-1, 1] {
                let rail = SCNNode(geometry: SCNBox(width: CGFloat(w + 0.4), height: 0.22,
                                                    length: 0.16, chamferRadius: 0.06))
                rail.geometry?.materials = [railMaterial]
                rail.position = SCNVector3(0, 0.1, side * (d / 2 + 0.12))
                root.addChildNode(rail)
            }

            // Goal strips at each end; these flash when a point is scored.
            let goals: [(Float, SCNMaterial)] = [(-1, leftGoalMaterial), (1, rightGoalMaterial)]
            for (side, material) in goals {
                let strip = SCNNode(geometry: SCNBox(width: 0.12, height: 0.08,
                                                     length: CGFloat(d), chamferRadius: 0.03))
                strip.geometry?.materials = [material]
                strip.position = SCNVector3(side * (w / 2 + 0.1), 0.02, 0)
                root.addChildNode(strip)
            }

            // Dashed centre line and centre ring, faintly emissive.
            let lineMaterial = ArcadeFX.neon(UIColor(white: 0.85, alpha: 1), intensity: 0.45)
            let dashCount = 11
            let dashLength: Float = d / Float(dashCount) * 0.55
            for i in 0..<dashCount {
                let dash = SCNNode(geometry: SCNBox(width: 0.08, height: 0.012,
                                                    length: CGFloat(dashLength), chamferRadius: 0.004))
                dash.geometry?.materials = [lineMaterial]
                let z: Float = (Float(i) + 0.5) / Float(dashCount) * d - d / 2
                dash.position = SCNVector3(0, 0.006, z)
                root.addChildNode(dash)
            }
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 1.3, pipeRadius: 0.025))
            ring.geometry?.materials = [lineMaterial]
            ring.position = SCNVector3(0, 0.01, 0)
            root.addChildNode(ring)
        }

        private func buildActors() {
            let d: Float = Coordinator.tableDepth
            let paddleLength: CGFloat = CGFloat(Coordinator.paddleHalf * 2 * d)
            let pairs: [(SCNNode, UIColor)] = [(leftPaddle, Coordinator.leftColor),
                                               (rightPaddle, Coordinator.rightColor)]
            for (node, color) in pairs {
                node.geometry = SCNBox(width: 0.32, height: 0.42, length: paddleLength, chamferRadius: 0.15)
                node.geometry?.materials = [ArcadeFX.neon(color, intensity: 1.6, roughness: 0.15)]
                node.castsShadow = true
                // A coloured glow pool on the table under each paddle.
                let glow = SCNLight()
                glow.type = .omni
                glow.color = color
                glow.intensity = 260
                glow.attenuationStartDistance = 0
                glow.attenuationEndDistance = 3
                let glowNode = SCNNode()
                glowNode.light = glow
                glowNode.position = SCNVector3(0, 0.6, 0)
                node.addChildNode(glowNode)
                scene.rootNode.addChildNode(node)
            }
            leftPaddle.position = paddlePosition(left: true, normalized: 0.5)
            rightPaddle.position = paddlePosition(left: false, normalized: 0.5)

            let sphere = SCNSphere(radius: 0.24)
            sphere.segmentCount = 32
            let ballMaterial = ArcadeFX.neon(UIColor(red: 0.85, green: 0.97, blue: 1.0, alpha: 1), intensity: 2.2,
                                             roughness: 0.1)
            sphere.materials = [ballMaterial]
            ballNode.geometry = sphere
            ballNode.castsShadow = true
            let ballLight = SCNLight()
            ballLight.type = .omni
            ballLight.color = UIColor(red: 0.6, green: 0.9, blue: 1.0, alpha: 1)
            ballLight.intensity = 420
            ballLight.attenuationStartDistance = 0
            ballLight.attenuationEndDistance = 3.5
            ballNode.light = ballLight
            ballNode.addParticleSystem(ArcadeFX.trail(color: UIColor(red: 0.45, green: 0.9, blue: 1.0, alpha: 1),
                                                      size: 0.34))
            ballNode.position = ballPosition(x: 0.5, y: 0.5)
            scene.rootNode.addChildNode(ballNode)
        }

        // MARK: Mapping

        private func ballPosition(x: Double, y: Double) -> SCNVector3 {
            let w: Float = Coordinator.tableWidth
            let d: Float = Coordinator.tableDepth
            return SCNVector3((Float(x) - 0.5) * w, 0.26, (Float(y) - 0.5) * d)
        }

        private func paddlePosition(left: Bool, normalized: Double) -> SCNVector3 {
            let w: Float = Coordinator.tableWidth
            let d: Float = Coordinator.tableDepth
            let inset: Float = Coordinator.paddleInset * w
            let x: Float = left ? (-w / 2 + inset) : (w / 2 - inset)
            let clamped: Float = min(1, max(0, Float(normalized)))
            return SCNVector3(x, 0.22, (clamped - 0.5) * d)
        }

        // MARK: Live state

        func apply(_ state: PongState, animated: Bool) {
            let paddleTime: TimeInterval = animated ? 0.09 : 0
            ArcadeFX.glide(leftPaddle, to: paddlePosition(left: true, normalized: state.leftPaddlePos),
                           duration: paddleTime)
            ArcadeFX.glide(rightPaddle, to: paddlePosition(left: false, normalized: state.rightPaddlePos),
                           duration: paddleTime)

            let ball = SIMD2<Float>(Float(state.ballX), Float(state.ballY))
            let target = ballPosition(x: state.ballX, y: state.ballY)
            if let previous = lastBall, animated {
                let delta = ball - previous
                let jump: Float = abs(delta.x) + abs(delta.y)
                if jump > 0.3 {
                    // A serve after a point teleports the ball to the centre.
                    ballNode.removeAction(forKey: "glide")
                    ballNode.position = target
                } else {
                    ArcadeFX.glide(ballNode, to: target, duration: 1.0 / 30.0)
                    detectBounces(ball: ball, delta: delta)
                }
                if delta.x != 0 || delta.y != 0 { lastVelocity = delta }
            } else {
                ballNode.position = target
            }
            lastBall = ball

            if let previousLeft = lastScoreLeft, state.scoreLeft > previousLeft {
                celebrateGoal(intoLeftGoal: false)
            }
            if let previousRight = lastScoreRight, state.scoreRight > previousRight {
                celebrateGoal(intoLeftGoal: true)
            }
            lastScoreLeft = state.scoreLeft
            lastScoreRight = state.scoreRight
        }

        /// The wire has no "hit" event; a reversal of the ball's horizontal
        /// direction near a paddle is one, a vertical reversal near a wall is
        /// a cushion bounce.
        private func detectBounces(ball: SIMD2<Float>, delta: SIMD2<Float>) {
            let at = ballPosition(x: Double(ball.x), y: Double(ball.y))
            if lastVelocity.x < 0 && delta.x > 0 && ball.x < 0.3 {
                ArcadeFX.emitBurst(in: effectsRoot, at: at, color: Coordinator.leftColor,
                                   count: 70, speed: 4.5, size: 0.11)
                pulse(leftPaddle)
            } else if lastVelocity.x > 0 && delta.x < 0 && ball.x > 0.7 {
                ArcadeFX.emitBurst(in: effectsRoot, at: at, color: Coordinator.rightColor,
                                   count: 70, speed: 4.5, size: 0.11)
                pulse(rightPaddle)
            }
            let wallFlip: Bool = (lastVelocity.y < 0 && delta.y > 0) || (lastVelocity.y > 0 && delta.y < 0)
            if wallFlip && (ball.y < 0.08 || ball.y > 0.92) {
                ArcadeFX.emitBurst(in: effectsRoot, at: at,
                                   color: UIColor(red: 0.7, green: 0.6, blue: 1.0, alpha: 1),
                                   count: 26, speed: 2.5, size: 0.07, lightIntensity: 400)
            }
        }

        private func pulse(_ paddle: SCNNode) {
            paddle.removeAction(forKey: "pulse")
            let up = SCNAction.scale(to: 1.25, duration: 0.07)
            let down = SCNAction.scale(to: 1.0, duration: 0.25)
            down.timingMode = .easeOut
            paddle.runAction(SCNAction.sequence([up, down]), forKey: "pulse")
        }

        private func celebrateGoal(intoLeftGoal: Bool) {
            let w: Float = Coordinator.tableWidth
            let x: Float = intoLeftGoal ? -w / 2 : w / 2
            let color: UIColor = intoLeftGoal ? Coordinator.rightColor : Coordinator.leftColor
            ArcadeFX.flash(intoLeftGoal ? leftGoalMaterial : rightGoalMaterial, peak: 7, rest: 0.6, hold: 0.3)
            for z: Float in [-2.4, 0, 2.4] {
                ArcadeFX.emitBurst(in: effectsRoot, at: SCNVector3(x, 0.4, z), color: color,
                                   count: 90, speed: 6, size: 0.13, lightIntensity: 1400)
            }
            cameraRig.shake(intensity: 0.22, duration: 0.5)
        }
    }
}
