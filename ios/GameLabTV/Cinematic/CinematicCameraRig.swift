import SceneKit
import QuartzCore

/// A named camera framing the cinematic rig can transition to. Each board
/// scene defines its own set of phases -- Poker's ("dealing", "betting",
/// "reveal") differ from Mafia's ("day", "night", "vote") -- so this is a
/// plain struct keyed by whatever phase identifier the scene wants, rather
/// than a fixed enum baked into the rig itself.
struct CameraShot {
    var position: SCNVector3
    var lookAt: SCNVector3
    var fieldOfView: CGFloat       // degrees
    var focusDistance: CGFloat     // scene units the depth-of-field focuses on

    static func lerp(_ a: CameraShot, _ b: CameraShot, _ t: CGFloat) -> CameraShot {
        func lerpV(_ x: SCNVector3, _ y: SCNVector3) -> SCNVector3 {
            SCNVector3(x.x + (y.x - x.x) * Float(t),
                       x.y + (y.y - x.y) * Float(t),
                       x.z + (y.z - x.z) * Float(t))
        }
        return CameraShot(
            position: lerpV(a.position, b.position),
            lookAt: lerpV(a.lookAt, b.lookAt),
            fieldOfView: a.fieldOfView + (b.fieldOfView - a.fieldOfView) * t,
            focusDistance: a.focusDistance + (b.focusDistance - a.focusDistance) * t
        )
    }
}

/// Drives a single `SCNCamera` with two independent, cooperating motion
/// systems:
///
/// 1. A continuous, subtle idle "floating orbit" -- a Lissajous figure (two
///    out-of-phase sine waves) around the current shot's position, always
///    running, so the table never looks static even mid-hand.
/// 2. Discrete state transitions between named `CameraShot`s (position,
///    look-at target, field of view, and DoF focus distance all
///    interpolated together) using a custom cubic-bezier ease, driven by
///    `SCNTransaction` rather than the idle loop.
///
/// The two never fight: a transition temporarily disables the orbit's
/// contribution and re-bases it around the new shot once the transition
/// completes, rather than the orbit's offset fighting the transition's own
/// animated position every frame.
@MainActor
final class CinematicCameraRig {
    let cameraNode: SCNNode
    let camera: SCNCamera

    /// The shot the orbit is currently floating around. Updated the instant
    /// a transition finishes; read every display-link tick in between.
    private(set) var currentShot: CameraShot

    // MARK: Idle orbit (Lissajous)

    /// Orbit amplitude in scene units on each axis. Small on purpose -- this
    /// is meant to read as "a living camera operator", not a spinning shot.
    var orbitAmplitude = SCNVector3(0.18, 0.10, 0.12)
    /// Angular frequencies (radians/sec) on each axis. Using different,
    /// non-integer-ratio frequencies is what keeps a Lissajous path from
    /// ever exactly repeating over a short, noticeable period.
    var orbitFrequency = SCNVector3(0.21, 0.29, 0.17)

    private var displayLink: CADisplayLink?
    private var orbitStartTime: CFTimeInterval = 0
    private var isTransitioning = false

    // MARK: Impact shake

    /// Impact-shake state. A short, decaying random offset layered on top
    /// of the idle orbit every frame -- a snake bite gets a quick rumble
    /// rather than a jarring camera cut.
    private var shakeStartTime: CFTimeInterval = 0
    private var shakeIntensity: Float = 0
    private var shakeDuration: CFTimeInterval = 0

    init(cameraNode: SCNNode = SCNNode(), initialShot: CameraShot) {
        self.cameraNode = cameraNode
        let camera = cameraNode.camera ?? SCNCamera()
        cameraNode.camera = camera
        self.camera = camera
        self.currentShot = initialShot

        configureCamera()
        applyImmediately(initialShot)
        startOrbit()
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Post-processing (spec #2)

    /// HDR, screen-space ambient occlusion, depth of field, and vignette.
    /// All of these are `SCNCamera` properties, not `SCNView` ones --
    /// `SCNView.wantsHDR` doesn't exist; HDR is a per-camera render setting.
    private func configureCamera() {
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.exposureAdaptationBrighteningSpeedFactor = 0.6
        camera.exposureAdaptationDarkeningSpeedFactor = 0.3
        camera.exposureOffset = 0

        // Screen-space ambient occlusion -- soft contact shadows in creases
        // (between cards, under chip stacks) that per-pixel lighting alone
        // won't produce.
        camera.screenSpaceAmbientOcclusionIntensity = 0.6
        camera.screenSpaceAmbientOcclusionRadius = 3.5
        camera.screenSpaceAmbientOcclusionBias = 0.03
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.5

        // Depth of field -- the real SceneKit property is `focusDistance`,
        // not `focalDistance`. Aperture kept fairly closed (higher fStop)
        // so only the far background/foreground melt away; the play surface
        // itself should stay legible.
        camera.wantsDepthOfField = true
        camera.fStop = 2.8
        camera.focalLength = 50
        camera.focalBlurSampleCount = 16
        camera.apertureBladeCount = 6

        // Vignette + a touch of film grain and color grading -- SceneKit
        // ships these natively on SCNCamera, so no custom SCNTechnique /
        // fragment shader is needed for what the spec calls a "vignette
        // layer".
        camera.vignettingIntensity = 0.35
        camera.vignettingPower = 1.4
        camera.grainIntensity = 0.015
        camera.contrast = 0.02
        camera.saturation = 0.02

        camera.zNear = 0.05
        camera.zFar = 100
    }

    // MARK: - Idle floating orbit

    private func startOrbit() {
        orbitStartTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard !isTransitioning else { return }
        let t = Float(link.timestamp - orbitStartTime)

        let offset = SCNVector3(
            orbitAmplitude.x * sin(orbitFrequency.x * t),
            orbitAmplitude.y * sin(orbitFrequency.y * t + .pi / 3),
            orbitAmplitude.z * sin(orbitFrequency.z * t + .pi / 5)
        )

        // Impact shake: a decaying random offset layered over the orbit.
        // The linear decay reads as a rumble settling back into the idle
        // float rather than a hard cut.
        let shakeElapsed = link.timestamp - shakeStartTime
        var shakeOffset = SCNVector3(0, 0, 0)
        if shakeDuration > 0, shakeElapsed < shakeDuration {
            let decay = 1 - Float(shakeElapsed / shakeDuration)
            shakeOffset = SCNVector3(
                Float.random(in: -1...1) * shakeIntensity * decay,
                Float.random(in: -1...1) * shakeIntensity * 0.6 * decay,
                Float.random(in: -1...1) * shakeIntensity * decay
            )
        }

        // Only the position moves here -- orientation is left entirely to
        // the SCNLookAtConstraint installed on this node (see
        // `lookAtTarget`), which re-aims the camera at the fixed look-at
        // point every frame as the position drifts. Calling `look(at:)`
        // manually here too would fight that constraint instead of
        // cooperating with it.
        cameraNode.position = SCNVector3(
            currentShot.position.x + offset.x + shakeOffset.x,
            currentShot.position.y + offset.y + shakeOffset.y,
            currentShot.position.z + offset.z + shakeOffset.z
        )
    }

    // MARK: - Impact shake trigger

    /// Fires a short camera shake, e.g. on a snake bite. `intensity` is in
    /// scene units of peak random offset (0.08-0.15 reads as a nudge at
    /// the TV-board scale where the idle orbit itself is 0.18), and
    /// `duration` is how long the rumble takes to decay, in seconds.
    /// Safe to call mid-transition -- the shake only feeds the orbit path
    /// the display link writes each frame, so it never fights a running
    /// `SCNTransaction` transition.
    func shake(intensity: Float = 0.12, duration: TimeInterval = 0.4) {
        shakeIntensity = intensity
        shakeDuration = duration
        shakeStartTime = CACurrentMediaTime()
    }

    // MARK: - State-driven transitions (spec #3)

    /// Smoothly interpolates position, look-at target, field of view, and
    /// DoF focus distance to a new shot over `duration` seconds using a
    /// custom cubic-bezier ease (an "ease-out-back"-flavoured curve by
    /// default -- a small overshoot-and-settle reads as a deliberate camera
    /// move rather than a mechanical linear pan).
    func transition(
        to shot: CameraShot,
        duration: TimeInterval = 1.8,
        controlPoints: (Float, Float, Float, Float) = (0.34, 1.24, 0.64, 1.0),
        completion: (() -> Void)? = nil
    ) {
        isTransitioning = true

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(
            controlPoints: controlPoints.0, controlPoints.1, controlPoints.2, controlPoints.3
        )
        SCNTransaction.completionBlock = { [weak self] in
            guard let self else { return }
            self.currentShot = shot
            self.isTransitioning = false
            self.orbitStartTime = CACurrentMediaTime() // re-base the orbit at the new shot
            completion?()
        }

        cameraNode.position = shot.position
        camera.fieldOfView = shot.fieldOfView
        camera.focusDistance = shot.focusDistance
        // `look(at:)` itself can't be interpolated by SCNTransaction, so
        // orientation rides on the SCNLookAtConstraint's target position
        // instead -- an ordinary node position, which is animatable.
        lookAtTarget.position = shot.lookAt

        SCNTransaction.commit()
    }

    /// Backing node for an `SCNLookAtConstraint`, so the look-at target
    /// itself is an animatable scene-graph position rather than a raw
    /// `look(at:)` call (which SCNTransaction can't interpolate directly).
    lazy var lookAtTarget: SCNNode = {
        let node = SCNNode()
        node.position = currentShot.lookAt
        let constraint = SCNLookAtConstraint(target: node)
        constraint.isGimbalLockEnabled = true
        cameraNode.constraints = [constraint]
        return node
    }()

    /// Snaps directly to a shot with no animation -- only used once, at
    /// setup, before the orbit or any transition has ever run.
    private func applyImmediately(_ shot: CameraShot) {
        cameraNode.position = shot.position
        camera.fieldOfView = shot.fieldOfView
        camera.focusDistance = shot.focusDistance
        lookAtTarget.position = shot.lookAt // first access installs the constraint
    }
}
