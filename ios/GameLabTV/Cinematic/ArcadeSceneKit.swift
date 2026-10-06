import SceneKit
import UIKit

/// Shared building blocks for the real-time arcade scenes (Pong, Air Hockey,
/// Carrom): PBR material helpers, a glowing particle sprite, one-shot spark
/// bursts and moving-object trails built on `SCNParticleSystem`, emission
/// flashes, and the camera/scene tuning that makes the Cinematic rig suit a
/// fast game rather than a slow card table (crisp focus, fixed exposure,
/// bloom so emissive materials glow).
@MainActor
enum ArcadeFX {

    // MARK: Materials

    static func pbr(_ color: UIColor, metalness: CGFloat = 0, roughness: CGFloat = 0.5,
                    clearCoat: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = NSNumber(value: Double(metalness))
        m.roughness.contents = NSNumber(value: Double(roughness))
        if clearCoat > 0 {
            m.clearCoat.contents = NSNumber(value: Double(clearCoat))
            m.clearCoatRoughness.contents = NSNumber(value: 0.05)
        }
        return m
    }

    /// A glossy body that also emits its own colour, so it glows through the
    /// camera's bloom pass (paddles, mallets, neon rails).
    static func neon(_ color: UIColor, intensity: CGFloat = 1.4, roughness: CGFloat = 0.25) -> SCNMaterial {
        let m = pbr(color, metalness: 0.2, roughness: roughness)
        m.emission.contents = color
        m.emission.intensity = intensity
        return m
    }

    /// Spikes a material's emission and lets it settle back -- a goal flash,
    /// a pocket glow.
    static func flash(_ material: SCNMaterial, peak: CGFloat, rest: CGFloat, hold: TimeInterval = 0.12) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.08
        material.emission.intensity = peak
        SCNTransaction.completionBlock = {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.9 + hold
            material.emission.intensity = rest
            SCNTransaction.commit()
        }
        SCNTransaction.commit()
    }

    // MARK: Particles

    /// A soft round sprite; without an image SceneKit draws hard squares.
    static let glowImage: UIImage = {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors: [CGColor] = [UIColor.white.cgColor,
                                     UIColor(white: 1, alpha: 0.55).cgColor,
                                     UIColor(white: 1, alpha: 0).cgColor]
            let locations: [CGFloat] = [0, 0.35, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray,
                                            locations: locations) else { return }
            let centre = CGPoint(x: 32, y: 32)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                                             endCenter: centre, endRadius: 32, options: [])
        }
    }()

    private static func fadeOutController() -> SCNParticlePropertyController {
        let fade = CAKeyframeAnimation()
        fade.values = [NSNumber(value: 1.0), NSNumber(value: 0.85), NSNumber(value: 0.0)]
        fade.keyTimes = [NSNumber(value: 0.0), NSNumber(value: 0.5), NSNumber(value: 1.0)]
        fade.duration = 1
        return SCNParticlePropertyController(animation: fade)
    }

    /// A continuous emitter left in world space, so a moving node draws a
    /// glowing comet tail behind itself.
    static func trail(color: UIColor, size: CGFloat, life: CGFloat = 0.28) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = glowImage
        ps.birthRate = 160
        ps.loops = true
        ps.emissionDuration = 1
        ps.particleLifeSpan = life
        ps.particleLifeSpanVariation = life * 0.2
        ps.particleVelocity = 0
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.15
        ps.particleColor = color
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.isLocal = false
        ps.propertyControllers = [.opacity: fadeOutController()]
        return ps
    }

    static func burst(color: UIColor, count: CGFloat, speed: CGFloat, size: CGFloat) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.particleImage = glowImage
        ps.loops = false
        ps.emissionDuration = 0.06
        ps.birthRate = max(1, count / 0.06)
        ps.particleLifeSpan = 0.6
        ps.particleLifeSpanVariation = 0.3
        ps.particleVelocity = speed
        ps.particleVelocityVariation = speed * 0.6
        ps.spreadingAngle = 180
        ps.emitterShape = SCNSphere(radius: 0.05)
        ps.birthLocation = .surface
        ps.birthDirection = .surfaceNormal
        ps.acceleration = SCNVector3(0, -7, 0)
        ps.dampingFactor = 1.2
        ps.particleSize = size
        ps.particleSizeVariation = size * 0.5
        ps.particleColor = color
        ps.particleColorVariation = SCNVector4(0.04, 0.1, 0.15, 0)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.propertyControllers = [.opacity: fadeOutController()]
        return ps
    }

    /// Fires a one-shot spark burst at `position` under `root`, plus a quick
    /// point-light flash so the burst actually lights the surface around it.
    static func emitBurst(in root: SCNNode, at position: SCNVector3, color: UIColor,
                          count: CGFloat = 60, speed: CGFloat = 4, size: CGFloat = 0.09,
                          lightIntensity: CGFloat = 900) {
        let holder = SCNNode()
        holder.position = position
        holder.addParticleSystem(burst(color: color, count: count, speed: speed, size: size))

        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = lightIntensity
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = 4
        holder.light = light
        root.addChildNode(holder)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        light.intensity = 0
        SCNTransaction.commit()

        holder.runAction(SCNAction.sequence([SCNAction.wait(duration: 1.6),
                                             SCNAction.removeFromParentNode()]))
    }

    // MARK: Scene + camera

    /// A vertical gradient used as both the skybox and the PBR lighting
    /// environment, so glossy surfaces pick up coloured reflections.
    static func backdropImage(top: UIColor, horizon: UIColor, bottom: UIColor) -> UIImage {
        let size = CGSize(width: 16, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors: [CGColor] = [top.cgColor, horizon.cgColor, bottom.cgColor]
            let locations: [CGFloat] = [0, 0.5, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray,
                                            locations: locations) else { return }
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0),
                                             end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    static func dressScene(_ scene: SCNScene, top: UIColor, horizon: UIColor, bottom: UIColor,
                           environmentIntensity: CGFloat = 1.2) {
        let sky = backdropImage(top: top, horizon: horizon, bottom: bottom)
        scene.background.contents = sky
        scene.lightingEnvironment.contents = sky
        scene.lightingEnvironment.intensity = environmentIntensity
        scene.fogColor = bottom
        scene.fogStartDistance = 24
        scene.fogEndDistance = 60
    }

    /// A dark, slightly reflective studio floor the table stands on.
    static func floorNode(color: UIColor, y: Float) -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0.18
        floor.reflectionFalloffEnd = 6
        floor.materials = [pbr(color, metalness: 0.1, roughness: 0.6)]
        let node = SCNNode(geometry: floor)
        node.position = SCNVector3(0, y, 0)
        return node
    }

    /// Tunes the shared Cinematic camera for a fast arcade game: everything
    /// in focus, a fixed exposure (auto-exposure pumps on bright flashes),
    /// a lighter vignette, and bloom so emissive materials glow.
    static func tuneForArcade(_ rig: CinematicCameraRig, orbit: Float) {
        let camera = rig.camera
        camera.wantsDepthOfField = false
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.vignettingIntensity = 0.25
        camera.saturation = 1.1
        camera.bloomIntensity = 1.1
        camera.bloomThreshold = 0.75
        camera.bloomBlurRadius = 14
        camera.zFar = 200
        rig.orbitAmplitude = SCNVector3(orbit, orbit * 0.5, orbit * 0.6)
        rig.orbitFrequency = SCNVector3(0.13, 0.19, 0.11)
    }

    static func makeView(scene: SCNScene, pointOfView: SCNNode) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.isPlaying = true
        view.rendersContinuously = true
        return view
    }

    /// Moves a node toward a live, server-driven target. Replacing the
    /// action each update means it always eases from where it is drawn now,
    /// so a late or early packet never makes it jump backwards.
    static func glide(_ node: SCNNode, to target: SCNVector3, duration: TimeInterval,
                      easeOut: Bool = false) {
        node.removeAction(forKey: "glide")
        let move = SCNAction.move(to: target, duration: duration)
        move.timingMode = easeOut ? .easeOut : .linear
        node.runAction(move, forKey: "glide")
    }
}
