import SceneKit
import UIKit
import simd

// MARK: - Realistic snake
//
// A drop-in replacement for the board's capsule-chain `SnakeNode`, with the
// same public surface (`rootNode`, `pathPoints`, the color initializer and
// `playEat()`), built from pure SceneKit and Swift -- no Metal shader
// sources, so nothing can fail to compile at runtime:
//
// - Body: one custom `SCNGeometry`, an elliptical cross-section (wider than
//   tall, flatter belly) swept along a Catmull-Rom spline that S-curves from
//   the head square to the tail square and rests on the board. 120 rings x
//   16 sides with smooth normals and UVs (u around, v along the length).
// - Motion: an `SCNSkinner` over a 14-bone spine. Each vertex is weighted to
//   its two nearest bones, and the bones are driven only by `SCNAction`
//   loops (a phase-offset travelling wave), so there is no per-frame Swift
//   code and no per-frame mesh rebuild.
// - Skin: physically based materials whose albedo, normal and roughness maps
//   are generated once with Core Graphics and cached per species.
// - Head: separate custom upper-head and jaw meshes (a flat-topped wedge with
//   a rounded snout), glossy eyes with slit pupils, a hinged jaw and a forked
//   tongue that flicks on a randomised action loop.
// - Grounding: a soft contact-shadow ribbon under the whole snake.
//
// Every helper type is prefixed `RealSnake` so this file can sit beside the
// board view's own private snake/ladder types without name clashes.

/// One snake lying on the board, head (path index 0) to tail.
@MainActor
final class RealisticSnakeNode {
    let rootNode = SCNNode()
    /// The body centerline from head (index 0) to tail (last index), at
    /// board-surface height -- the token rides this after being "eaten".
    let pathPoints: [SCNVector3]
    /// The natural species this snake is dressed as.
    let species: RealSnakeSpecies

    private let bones: [SCNNode]
    private let headLungeNode: SCNNode
    private let jawPivotNode: SCNNode
    private let bodyRadius: Float

    /// The board's existing initializer: the (body, band) color pair picks a
    /// natural species palette (red -> coral snake, orange -> corn snake,
    /// yellow -> python, green -> green tree snake, blue -> king snake,
    /// purple -> diamondback rattlesnake).
    convenience init(headSquare: Int, tailSquare: Int, squareToPoint: (Int) -> SCNVector3,
                     color: UIColor, bandColor: UIColor) {
        self.init(headSquare: headSquare, tailSquare: tailSquare, squareToPoint: squareToPoint,
                  species: RealSnakeSpecies.matching(color: color, bandColor: bandColor))
    }

    /// Picks the species by index, cycling through `RealSnakeSpecies.allCases`.
    convenience init(headSquare: Int, tailSquare: Int, squareToPoint: (Int) -> SCNVector3, styleIndex: Int) {
        self.init(headSquare: headSquare, tailSquare: tailSquare, squareToPoint: squareToPoint,
                  species: RealSnakeSpecies.forStyleIndex(styleIndex))
    }

    init(headSquare: Int, tailSquare: Int, squareToPoint: (Int) -> SCNVector3, species: RealSnakeSpecies) {
        let headPoint = squareToPoint(headSquare)
        let tailPoint = squareToPoint(tailSquare)
        let boardY: Float = headPoint.y
        let seed: Int = headSquare &* 131 &+ tailSquare &* 17

        let spline = RealSnakeSpline(head: SIMD3<Float>(headPoint.x, 0, headPoint.z),
                                     tail: SIMD3<Float>(tailPoint.x, 0, tailPoint.z),
                                     seed: seed)
        let radius: Float = min(0.155, max(0.10, 0.085 + 0.011 * spline.straightLength))
        let headShape = RealSnakeHeadShape(radius: radius)
        let profile = RealSnakeBodyProfile(maxRadius: radius, length: spline.length, headLength: headShape.length)
        let skin = RealSnakeAssets.skin(for: species)

        let rig = RealSnakeMesh.buildSkinnedBody(spline: spline, profile: profile, boardY: boardY,
                                                 material: skin.bodyMaterial)

        // The head hangs off the first spine bone, so the slither carries it
        // and the neck and skull never separate.
        let headFrame = spline.frame(at: 0)
        let bone0 = rig.bones[0]
        let headAnchor = SCNNode()
        headAnchor.position = SCNVector3(0, boardY - bone0.position.y, 0)
        headAnchor.eulerAngles = SCNVector3(0, atan2(-headFrame.forward.x, -headFrame.forward.z), 0)
        bone0.addChildNode(headAnchor)
        let headIdle = SCNNode()
        headAnchor.addChildNode(headIdle)
        let headLunge = SCNNode()
        headIdle.addChildNode(headLunge)
        let headParts = RealSnakeHeadBuilder.build(shape: headShape, skin: skin, into: headLunge)

        let shadowNode = RealSnakeMesh.buildContactShadow(spline: spline, profile: profile, head: headShape,
                                                          boardY: boardY, material: skin.contactShadowMaterial)

        let pathCount = max(9, spline.halfWaves * 4 + 1)
        var path: [SCNVector3] = []
        path.reserveCapacity(pathCount)
        for i in 0..<pathCount {
            let d = spline.length * Float(i) / Float(pathCount - 1)
            let p = spline.frame(at: d).position
            path.append(SCNVector3(p.x, boardY + 0.10, p.z))
        }

        self.species = species
        self.pathPoints = path
        self.bones = rig.bones
        self.headLungeNode = headLunge
        self.jawPivotNode = headParts.jawPivot
        self.bodyRadius = radius

        rootNode.name = "realisticSnake"
        rootNode.addChildNode(shadowNode)
        rootNode.addChildNode(rig.bodyNode)
        rootNode.addChildNode(rig.skeletonRoot)

        RealisticSnakeNode.startSlither(bones: rig.bones, laterals: rig.laterals, radius: radius,
                                        length: spline.length, seed: seed)
        RealisticSnakeNode.startHeadIdle(headIdle)
        RealisticSnakeNode.startTongue(headParts.tongueRoot, travel: headParts.tongueTravel, seed: seed)
    }

    // MARK: Eat

    /// A one-shot strike when a token lands on the head: the head lunges
    /// forward and up with the jaw gaping, snaps shut, settles back, and a
    /// gulp bulge rolls down the first few spine bones. Every step targets
    /// absolute values, so calling this again mid-strike cannot accumulate
    /// drift.
    func playEat() {
        let r = bodyRadius

        let strikeMove = SCNAction.move(to: SCNVector3(0, 0.35 * r, 0.95 * r), duration: 0.13)
        strikeMove.timingMode = .easeOut
        let strikeTilt = SCNAction.rotateTo(x: -0.30, y: 0, z: 0, duration: 0.13)
        strikeTilt.timingMode = .easeOut
        let settleMove = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 0.34)
        settleMove.timingMode = .easeInEaseOut
        let settleTilt = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.34)
        settleTilt.timingMode = .easeInEaseOut
        let lunge = SCNAction.sequence([
            .group([strikeMove, strikeTilt]),
            .wait(duration: 0.14),
            .group([settleMove, settleTilt]),
        ])
        headLungeNode.removeAction(forKey: "realSnakeEat")
        headLungeNode.runAction(lunge, forKey: "realSnakeEat")

        let gape = SCNAction.rotateTo(x: 0.85, y: 0, z: 0, duration: 0.10)
        gape.timingMode = .easeOut
        let snap = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.08)
        snap.timingMode = .easeIn
        let chewOpen = SCNAction.rotateTo(x: 0.22, y: 0, z: 0, duration: 0.09)
        chewOpen.timingMode = .easeInEaseOut
        let chewClose = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.11)
        chewClose.timingMode = .easeInEaseOut
        let jaw = SCNAction.sequence([gape, .wait(duration: 0.16), snap, .wait(duration: 0.10), chewOpen, chewClose])
        jawPivotNode.removeAction(forKey: "realSnakeJaw")
        jawPivotNode.runAction(jaw, forKey: "realSnakeJaw")

        // Bone 0 carries the head, so the gulp starts one bone behind it.
        let gulpCount = min(5, bones.count - 1)
        guard gulpCount >= 1 else { return }
        for k in 1...gulpCount {
            let factor: CGFloat = 1.24 - 0.03 * CGFloat(k)
            let swell = SCNAction.scale(to: factor, duration: 0.12)
            swell.timingMode = .easeOut
            let relax = SCNAction.scale(to: 1.0, duration: 0.20)
            relax.timingMode = .easeInEaseOut
            let delay: TimeInterval = 0.38 + 0.09 * TimeInterval(k)
            bones[k].removeAction(forKey: "realSnakeGulp")
            bones[k].runAction(.sequence([.wait(duration: delay), swell, relax]), forKey: "realSnakeGulp")
        }
    }

    // MARK: Idle animation (actions only, no per-frame code)

    /// A slow travelling wave down the spine: each bone sways sideways and
    /// turns a little, a fixed delay behind the bone in front of it, so the
    /// ripple runs from head to tail. Amplitudes are a fraction of the body
    /// radius so the snake stays on its path.
    private static func startSlither(bones: [SCNNode], laterals: [SIMD3<Float>], radius: Float,
                                     length: Float, seed: Int) {
        guard bones.count > 1, laterals.count == bones.count else { return }
        let period: TimeInterval = 3.6
        let cycles: Float = min(2.0, max(0.75, length / 2.2))
        let wavelength: Float = max(0.5, length / cycles)
        let kappa: Float = 2 * Float.pi / wavelength
        let baseAmplitude: Float = 0.22 * radius
        let lastIndex = bones.count - 1
        let phaseStep: TimeInterval = TimeInterval(cycles) * period / TimeInterval(lastIndex)
        let startOffset: TimeInterval = TimeInterval(RealSnakeMath.hash(seed, 41)) * period
        for k in 0...lastIndex {
            let along = Float(k) / Float(lastIndex)
            let amplitude: Float = baseAmplitude * (0.3 + 0.7 * along)
            let angle: Float = min(0.07, amplitude * kappa)
            let lateral = laterals[k]
            let delay: TimeInterval = startOffset + phaseStep * TimeInterval(k)
            let sway = swayLoop(dx: lateral.x * amplitude, dz: lateral.z * amplitude, period: period)
            bones[k].runAction(.sequence([.wait(duration: delay), sway]), forKey: "realSnakeSway")
            // The body's slope lags its sideways offset by a quarter period.
            let turn = turnLoop(angle: angle, period: period)
            bones[k].runAction(.sequence([.wait(duration: delay + period / 4), turn]), forKey: "realSnakeTurn")
        }
    }

    private static func swayLoop(dx: Float, dz: Float, period: TimeInterval) -> SCNAction {
        let x = CGFloat(dx)
        let z = CGFloat(dz)
        let first = SCNAction.moveBy(x: x, y: 0, z: z, duration: period / 4)
        first.timingMode = .easeOut
        let back = SCNAction.moveBy(x: -2 * x, y: 0, z: -2 * z, duration: period / 2)
        back.timingMode = .easeInEaseOut
        let out = SCNAction.moveBy(x: 2 * x, y: 0, z: 2 * z, duration: period / 2)
        out.timingMode = .easeInEaseOut
        return SCNAction.sequence([first, .repeatForever(.sequence([back, out]))])
    }

    private static func turnLoop(angle: Float, period: TimeInterval) -> SCNAction {
        let a = CGFloat(angle)
        let first = SCNAction.rotateBy(x: 0, y: a, z: 0, duration: period / 4)
        first.timingMode = .easeOut
        let back = SCNAction.rotateBy(x: 0, y: -2 * a, z: 0, duration: period / 2)
        back.timingMode = .easeInEaseOut
        let out = SCNAction.rotateBy(x: 0, y: 2 * a, z: 0, duration: period / 2)
        out.timingMode = .easeInEaseOut
        return SCNAction.sequence([first, .repeatForever(.sequence([back, out]))])
    }

    /// A barely-there head sway on its own node, so it never fights the
    /// strike in `playEat()` (which drives the node below it).
    private static func startHeadIdle(_ node: SCNNode) {
        let left = SCNAction.rotateBy(x: 0, y: 0.05, z: 0, duration: 2.3)
        left.timingMode = .easeInEaseOut
        let right = SCNAction.rotateBy(x: 0, y: -0.10, z: 0, duration: 4.6)
        right.timingMode = .easeInEaseOut
        let centre = SCNAction.rotateBy(x: 0, y: 0.05, z: 0, duration: 2.3)
        centre.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([left, right, centre])), forKey: "realSnakeHeadIdle")
    }

    /// Every few seconds (randomised by `wait(duration:withRange:)`) the
    /// tongue slides out of the mouth, flutters up and down twice, and
    /// slides back in, hidden while retracted.
    private static func startTongue(_ tongue: SCNNode, travel: Float, seed: Int) {
        let reach = CGFloat(travel)
        let extend = SCNAction.moveBy(x: 0, y: 0, z: reach, duration: 0.09)
        extend.timingMode = .easeOut
        let retract = SCNAction.moveBy(x: 0, y: 0, z: -reach, duration: 0.11)
        retract.timingMode = .easeIn
        let up = SCNAction.rotateBy(x: -0.28, y: 0, z: 0, duration: 0.05)
        let down = SCNAction.rotateBy(x: 0.56, y: 0, z: 0, duration: 0.08)
        let level = SCNAction.rotateBy(x: -0.28, y: 0, z: 0, duration: 0.05)
        let flutter = SCNAction.sequence([up, down, level])
        let flick = SCNAction.sequence([.unhide(), extend, flutter, flutter, retract, .hide()])
        let loop = SCNAction.repeatForever(.sequence([.wait(duration: 4.5, withRange: 4.0), flick]))
        let initialDelay: TimeInterval = 0.8 + 3.0 * TimeInterval(RealSnakeMath.hash(seed, 77))
        tongue.runAction(.sequence([.wait(duration: initialDelay), loop]), forKey: "realSnakeTongue")
    }
}

// MARK: - Species

/// The natural palettes a snake can wear. Textures and materials are built
/// once per species and shared by every snake of that species.
enum RealSnakeSpecies: Int, CaseIterable {
    case coralSnake
    case cornSnake
    case burmesePython
    case greenTreeSnake
    case kingSnake
    case diamondback

    static func forStyleIndex(_ index: Int) -> RealSnakeSpecies {
        let all = RealSnakeSpecies.allCases
        return all[RealSnakeMath.mod(index, all.count)]
    }

    /// Maps the board's per-snake color pair onto a species by hue, so each
    /// of the board's six pairs lands on a different species.
    static func matching(color: UIColor, bandColor: UIColor) -> RealSnakeSpecies {
        if let species = byHue(color) { return species }
        if let species = byHue(bandColor) { return species }
        return .kingSnake
    }

    private static func byHue(_ color: UIColor) -> RealSnakeSpecies? {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha),
              saturation > 0.15 else { return nil }
        let h = Double(hue)
        if h < 0.03 || h >= 0.90 { return .coralSnake }
        if h < 0.09 { return .cornSnake }
        if h < 0.20 { return .burmesePython }
        if h < 0.50 { return .greenTreeSnake }
        if h < 0.68 { return .kingSnake }
        return .diamondback
    }

    /// Flat body color used if texture generation ever fails.
    var fallbackColor: UIColor {
        switch self {
        case .coralSnake: return UIColor(red: 0.78, green: 0.13, blue: 0.08, alpha: 1)
        case .cornSnake: return UIColor(red: 0.86, green: 0.49, blue: 0.26, alpha: 1)
        case .burmesePython: return UIColor(red: 0.62, green: 0.50, blue: 0.32, alpha: 1)
        case .greenTreeSnake: return UIColor(red: 0.20, green: 0.56, blue: 0.16, alpha: 1)
        case .kingSnake: return UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1)
        case .diamondback: return UIColor(red: 0.50, green: 0.42, blue: 0.32, alpha: 1)
        }
    }

    /// Dark, glossy iris tint.
    var irisColor: UIColor {
        switch self {
        case .coralSnake: return UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1)
        case .cornSnake: return UIColor(red: 0.38, green: 0.20, blue: 0.08, alpha: 1)
        case .burmesePython: return UIColor(red: 0.30, green: 0.22, blue: 0.10, alpha: 1)
        case .greenTreeSnake: return UIColor(red: 0.44, green: 0.38, blue: 0.10, alpha: 1)
        case .kingSnake: return UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1)
        case .diamondback: return UIColor(red: 0.34, green: 0.25, blue: 0.12, alpha: 1)
        }
    }

    var tongueColor: UIColor {
        switch self {
        case .coralSnake, .kingSnake, .diamondback:
            return UIColor(red: 0.08, green: 0.06, blue: 0.07, alpha: 1)
        case .cornSnake, .burmesePython:
            return UIColor(red: 0.50, green: 0.07, blue: 0.10, alpha: 1)
        case .greenTreeSnake:
            return UIColor(red: 0.20, green: 0.28, blue: 0.50, alpha: 1)
        }
    }
}

// MARK: - Math

enum RealSnakeMath {
    static func mod(_ a: Int, _ m: Int) -> Int {
        let r = a % m
        return r < 0 ? r + m : r
    }

    static func clamp01(_ x: Float) -> Float {
        min(max(x, 0), 1)
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    static func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        let delta: SIMD3<Float> = b - a
        return a + delta * t
    }

    static func signedPow(_ value: Float, _ exponent: Float) -> Float {
        value < 0 ? -pow(-value, exponent) : pow(value, exponent)
    }

    static func normalized(_ v: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(v)
        guard length > 0.000_000_1 else { return fallback }
        return v / length
    }

    /// Deterministic 0...1 hash of two integers (no global random state, so
    /// textures and per-snake variation are identical on every launch).
    static func hash(_ a: Int, _ b: Int) -> Float {
        let mixed = a &* 374_761_393 &+ b &* 668_265_263
        var h = UInt32(truncatingIfNeeded: mixed)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h = h ^ (h >> 16)
        return Float(h & 0xFFFF) / 65535
    }

    /// 0...1 to a byte; NaN and out-of-range values are clamped rather than
    /// trapping in the `UInt8` conversion.
    static func byte(_ value: Float) -> UInt8 {
        if !(value > 0) { return 0 }
        if value >= 1 { return 255 }
        return UInt8(value * 255 + 0.5)
    }

    /// Lateral texture coordinate (-1 belly, 0 spine, +1 belly) folded back
    /// into range when a scale centre sits just across the belly seam.
    static func wrapLateral(_ a: Float) -> Float {
        if a > 1 { return a - 2 }
        if a < -1 { return a + 2 }
        return a
    }

    /// Uniform Catmull-Rom between p1 and p2.
    static func catmullRom(_ p0: SIMD3<Float>, _ p1: SIMD3<Float>, _ p2: SIMD3<Float>, _ p3: SIMD3<Float>,
                           _ t: Float) -> SIMD3<Float> {
        let t2: Float = t * t
        let t3: Float = t2 * t
        let termA: SIMD3<Float> = p1 * 2
        let termB: SIMD3<Float> = (p2 - p0) * t
        var termC: SIMD3<Float> = p0 * 2
        termC -= p1 * 5
        termC += p2 * 4
        termC -= p3
        termC *= t2
        var termD: SIMD3<Float> = p1 * 3
        termD -= p0
        termD -= p2 * 3
        termD += p3
        termD *= t3
        var sum: SIMD3<Float> = termA + termB
        sum += termC
        sum += termD
        return sum * 0.5
    }
}

// MARK: - Spine path

/// The snake's centreline on the board (y = 0 here; callers add the board
/// height): a Catmull-Rom spline through control points that S-curve between
/// the head and tail squares, resampled by arc length.
struct RealSnakeSpline {
    let samples: [SIMD3<Float>]
    let cumulative: [Float]
    let length: Float
    let straightLength: Float
    /// Number of half sine waves in the S-curve (2...4).
    let halfWaves: Int
    let fallbackForward: SIMD3<Float>

    init(head: SIMD3<Float>, tail: SIMD3<Float>, seed: Int) {
        var delta: SIMD3<Float> = tail - head
        var straight = simd_length(delta)
        let direction: SIMD3<Float> = straight > 0.001 ? delta / straight : SIMD3<Float>(1, 0, 0)
        if straight < 0.3 {
            straight = 0.9
            delta = direction * straight
        }
        let perpendicular = SIMD3<Float>(-direction.z, 0, direction.x)
        let waves = min(4, max(2, Int((straight / 1.8).rounded())))
        let sideSign: Float = (seed & 1) == 0 ? 1 : -1
        let jitter: Float = 0.85 + 0.30 * RealSnakeMath.hash(seed, 7)
        let amplitude: Float = min(0.42, 0.14 + straight * 0.045) * jitter * sideSign

        // Whole half-waves, so the curve leaves the head square and arrives
        // at the tail square exactly.
        let controlSegments = waves * 4
        var control: [SIMD3<Float>] = []
        control.reserveCapacity(controlSegments + 1)
        for k in 0...controlSegments {
            let t = Float(k) / Float(controlSegments)
            let wave: Float = amplitude * sin(Float.pi * Float(waves) * t)
            let base: SIMD3<Float> = head + delta * t
            control.append(base + perpendicular * wave)
        }
        let first: SIMD3<Float> = control[0] * 2 - control[1]
        let last: SIMD3<Float> = control[controlSegments] * 2 - control[controlSegments - 1]
        let padded: [SIMD3<Float>] = [first] + control + [last]

        let steps = 16
        var dense: [SIMD3<Float>] = []
        dense.reserveCapacity(controlSegments * steps + 1)
        for segment in 0..<controlSegments {
            for step in 0..<steps {
                let t = Float(step) / Float(steps)
                dense.append(RealSnakeMath.catmullRom(padded[segment], padded[segment + 1],
                                                      padded[segment + 2], padded[segment + 3], t))
            }
        }
        dense.append(control[controlSegments])

        var running: Float = 0
        var lengths: [Float] = [0]
        lengths.reserveCapacity(dense.count)
        for i in 1..<dense.count {
            running += simd_length(dense[i] - dense[i - 1])
            lengths.append(running)
        }

        samples = dense
        cumulative = lengths
        length = max(running, 0.01)
        straightLength = straight
        halfWaves = waves
        fallbackForward = direction
    }

    /// Position and unit forward direction (toward the tail) at arc length `distance`.
    func frame(at distance: Float) -> (position: SIMD3<Float>, forward: SIMD3<Float>) {
        let d = min(max(distance, 0), length)
        var lo = 0
        var hi = cumulative.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] <= d {
                lo = mid
            } else {
                hi = mid
            }
        }
        let segmentLength = cumulative[hi] - cumulative[lo]
        let t: Float = segmentLength > 0.000_001 ? (d - cumulative[lo]) / segmentLength : 0
        let a = samples[lo]
        let b = samples[hi]
        let position: SIMD3<Float> = a + (b - a) * t
        let i0 = max(lo - 1, 0)
        let i1 = min(hi + 1, samples.count - 1)
        let direction: SIMD3<Float> = samples[i1] - samples[i0]
        return (position, RealSnakeMath.normalized(direction, fallback: fallbackForward))
    }
}

// MARK: - Body profile

/// Radius along the body: a slim neck tucked inside the back of the head,
/// thickest about a quarter of the way down, then a long taper to a point.
struct RealSnakeBodyProfile {
    let maxRadius: Float
    let length: Float
    let headLength: Float

    func radius(at d: Float) -> Float {
        let neck: Float = 0.5 * headLength
        let peak: Float = max(0.25 * length, neck + 0.1 * length)
        if d <= neck {
            // Inside the head: close the front of the tube off.
            let close: Float = sqrt(RealSnakeMath.clamp01(d / (0.2 * headLength)))
            let base: Float = 0.56 + 0.06 * (d / neck)
            return maxRadius * base * max(0.08, close)
        }
        if d <= peak {
            let x = (d - neck) / max(peak - neck, 0.0001)
            return maxRadius * (0.62 + 0.38 * RealSnakeMath.smoothstep(0, 1, x))
        }
        let u = RealSnakeMath.clamp01((d - peak) / max(length - peak, 0.0001))
        let taper: Float = 1 - 0.35 * u - 0.65 * u * u * u
        return maxRadius * max(0, taper)
    }

    /// Height of the centreline above the board so the (flattened) belly
    /// just touches it: belly depth is 0.66 x (0.8 x radius).
    static func centreLift(radius r: Float) -> Float {
        0.528 * r + 0.006
    }
}

// MARK: - Head shape

/// Profiles for the wedge head, as functions of `s` from the back of the
/// skull (0) to the snout tip (1). Local space: +z toward the snout, y = 0 on
/// the board, the mouth line at `mouthY`.
struct RealSnakeHeadShape {
    let radius: Float

    var length: Float { 3.4 * radius }
    var mouthY: Float { 0.40 * radius + 0.006 }

    func z(_ s: Float) -> Float {
        -0.45 * length + s * length
    }

    func backClosure(_ s: Float) -> Float {
        sin(min(s / 0.16, 1) * Float.pi / 2)
    }

    func frontClosure(_ s: Float) -> Float {
        guard s > 0.80 else { return 1 }
        let x = (s - 0.80) / 0.20
        return sqrt(max(0, 1 - x * x))
    }

    /// Widest at the jaw angles (s ~ 0.3), narrowing to a rounded snout.
    func halfWidth(_ s: Float) -> Float {
        let base: Float
        if s < 0.3 {
            base = 0.80 + 0.20 * RealSnakeMath.smoothstep(0, 0.3, s)
        } else {
            base = 1 - 0.52 * pow((s - 0.3) / 0.7, 1.25)
        }
        return 1.30 * radius * base * backClosure(s) * frontClosure(s)
    }

    func top(_ s: Float) -> Float {
        0.70 * radius * (1 - 0.42 * s) * backClosure(s) * pow(frontClosure(s), 0.6)
    }

    func palate(_ s: Float) -> Float {
        0.05 * radius * backClosure(s) * frontClosure(s)
    }

    func jawHalfWidth(_ s: Float) -> Float {
        0.88 * halfWidth(s)
    }

    func jawDepth(_ s: Float) -> Float {
        0.40 * radius * (1 - 0.5 * s) * backClosure(s) * pow(frontClosure(s), 0.6)
    }

    func jawTop(_ s: Float) -> Float {
        0.03 * radius * backClosure(s) * frontClosure(s)
    }
}

// MARK: - Lofted meshes

/// A tube swept through a list of rings (each `sides` points, ordered so
/// the angle increases from the belly/underside, across the +x flank, over
/// the top). The seam column is duplicated so u runs 0...1 cleanly; normals
/// are the smoothed (area-weighted) average of the surrounding quads,
/// which also handles rings collapsed to a single point at the tips.
struct RealSnakeLoft {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let ringCount: Int
    let sides: Int

    init(rings: [[SIMD3<Float>]], ringV: [Float], sides: Int) {
        let count = rings.count
        var accumulated = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: count * sides)
        if count > 1 {
            for i in 0..<(count - 1) {
                for j in 0..<sides {
                    let j1 = (j + 1) % sides
                    let a = rings[i][j]
                    let b = rings[i][j1]
                    let c = rings[i + 1][j1]
                    let d = rings[i + 1][j]
                    // Cross product of the quad diagonals: outward for this
                    // winding, and still valid when one edge is degenerate.
                    let n: SIMD3<Float> = simd_cross(c - a, d - b)
                    accumulated[i * sides + j] += n
                    accumulated[i * sides + j1] += n
                    accumulated[(i + 1) * sides + j1] += n
                    accumulated[(i + 1) * sides + j] += n
                }
            }
        }

        var outPositions: [SIMD3<Float>] = []
        var outNormals: [SIMD3<Float>] = []
        var outUVs: [SIMD2<Float>] = []
        let vertexCount = count * (sides + 1)
        outPositions.reserveCapacity(vertexCount)
        outNormals.reserveCapacity(vertexCount)
        outUVs.reserveCapacity(vertexCount)
        let up = SIMD3<Float>(0, 1, 0)
        for i in 0..<count {
            for j in 0...sides {
                let column = j % sides
                outPositions.append(rings[i][column])
                outNormals.append(RealSnakeMath.normalized(accumulated[i * sides + column], fallback: up))
                outUVs.append(SIMD2<Float>(Float(j) / Float(sides), ringV[i]))
            }
        }
        self.positions = outPositions
        self.normals = outNormals
        self.uvs = outUVs
        self.ringCount = count
        self.sides = sides
    }

    /// Triangle indices for the quads whose column passes `includeColumn`.
    /// Winding (a, b, c) + (a, c, d) is counter-clockwise seen from outside.
    func indices(includeColumn: (Int) -> Bool) -> [UInt16] {
        var out: [UInt16] = []
        guard ringCount > 1 else { return out }
        let rowStride = sides + 1
        for i in 0..<(ringCount - 1) {
            for j in 0..<sides where includeColumn(j) {
                let a = UInt16(i * rowStride + j)
                let b = UInt16(i * rowStride + j + 1)
                let c = UInt16((i + 1) * rowStride + j + 1)
                let d = UInt16((i + 1) * rowStride + j)
                out.append(contentsOf: [a, b, c, a, c, d])
            }
        }
        return out
    }
}

/// The skinned body plus the spine it is bound to.
struct RealSnakeBodyRig {
    let bodyNode: SCNNode
    let skeletonRoot: SCNNode
    let bones: [SCNNode]
    /// Unit sideways direction at each bone (for the slither sway).
    let laterals: [SIMD3<Float>]
}

@MainActor
enum RealSnakeMesh {
    static let bodySides = 16
    static let bodyRings = 120
    static let boneCount = 14

    // MARK: Geometry sources (tightly packed Float data, explicit strides)

    static func vectorSource(_ vectors: [SIMD3<Float>], semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
        var flat: [Float] = []
        flat.reserveCapacity(vectors.count * 3)
        for v in vectors {
            flat.append(v.x)
            flat.append(v.y)
            flat.append(v.z)
        }
        let data = flat.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data,
                                 semantic: semantic,
                                 vectorCount: vectors.count,
                                 usesFloatComponents: true,
                                 componentsPerVector: 3,
                                 bytesPerComponent: MemoryLayout<Float>.size,
                                 dataOffset: 0,
                                 dataStride: MemoryLayout<Float>.size * 3)
    }

    static func uvSource(_ uvs: [SIMD2<Float>]) -> SCNGeometrySource {
        var flat: [Float] = []
        flat.reserveCapacity(uvs.count * 2)
        for uv in uvs {
            flat.append(uv.x)
            flat.append(uv.y)
        }
        let data = flat.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data,
                                 semantic: .texcoord,
                                 vectorCount: uvs.count,
                                 usesFloatComponents: true,
                                 componentsPerVector: 2,
                                 bytesPerComponent: MemoryLayout<Float>.size,
                                 dataOffset: 0,
                                 dataStride: MemoryLayout<Float>.size * 2)
    }

    /// One geometry element per index list, in order -- materials are
    /// assigned to the geometry in the same order.
    static func makeGeometry(loft: RealSnakeLoft, elements: [[UInt16]]) -> SCNGeometry {
        let sources = [
            vectorSource(loft.positions, semantic: .vertex),
            vectorSource(loft.normals, semantic: .normal),
            uvSource(loft.uvs),
        ]
        let geometryElements: [SCNGeometryElement] = elements.map { list in
            SCNGeometryElement(indices: list, primitiveType: .triangles)
        }
        return SCNGeometry(sources: sources, elements: geometryElements)
    }

    // MARK: Body

    /// One body cross-section: an ellipse 0.8x as tall as it is wide, a
    /// touch wider and much flatter underneath. Point j sits at angle
    /// 2*pi*j/sides measured from the belly, sweeping up the +lateral flank.
    static func bodyRing(centre: SIMD3<Float>, forward: SIMD3<Float>, radius r: Float, sides: Int) -> [SIMD3<Float>] {
        let up = SIMD3<Float>(0, 1, 0)
        // up x forward: with (lateral, up, forward) right-handed, the loft
        // winding faces outward.
        let lateral = SIMD3<Float>(forward.z, 0, -forward.x)
        let halfHeight: Float = r * 0.80
        var ring: [SIMD3<Float>] = []
        ring.reserveCapacity(sides)
        for j in 0..<sides {
            let phi = 2 * Float.pi * Float(j) / Float(sides)
            let sn = sin(phi)
            let cs = cos(phi)
            let width: Float = r * (1 + 0.06 * max(0, cs))
            let side: Float = sn * width
            let lift: Float
            if cs > 0 {
                lift = -halfHeight * 0.66 * pow(cs, 0.8)
            } else {
                lift = -cs * halfHeight
            }
            let sideOffset: SIMD3<Float> = lateral * side
            let liftOffset: SIMD3<Float> = up * lift
            ring.append(centre + sideOffset + liftOffset)
        }
        return ring
    }

    /// Sweeps the body mesh along the spline and binds it to a 14-bone
    /// spine with an `SCNSkinner` (two bone influences per vertex).
    static func buildSkinnedBody(spline: RealSnakeSpline, profile: RealSnakeBodyProfile, boardY: Float,
                                 material: SCNMaterial) -> RealSnakeBodyRig {
        let sides = bodySides
        let ringCount = bodyRings
        // World length of one vertical texture tile, chosen so scales come
        // out roughly square at full girth (256 px around ~ 5.65 r).
        let tileWorld: Float = 22.6 * profile.maxRadius

        var rings: [[SIMD3<Float>]] = []
        var ringV: [Float] = []
        var ringD: [Float] = []
        rings.reserveCapacity(ringCount)
        ringV.reserveCapacity(ringCount)
        ringD.reserveCapacity(ringCount)
        var vAccum: Float = 0
        var previousD: Float = 0
        for i in 0..<ringCount {
            let d = spline.length * Float(i) / Float(ringCount - 1)
            let frame = spline.frame(at: d)
            let r = profile.radius(at: d)
            if i > 0 {
                // Scales shrink with girth, so the pattern tightens toward
                // the tail the way a real snake's does.
                let stretch: Float = profile.maxRadius / max(r, 0.35 * profile.maxRadius)
                vAccum += (d - previousD) * stretch / tileWorld
            }
            previousD = d
            ringD.append(d)
            ringV.append(vAccum)
            let lift = RealSnakeBodyProfile.centreLift(radius: r)
            let centre = SIMD3<Float>(frame.position.x, boardY + lift, frame.position.z)
            rings.append(bodyRing(centre: centre, forward: frame.forward, radius: r, sides: sides))
        }

        let loft = RealSnakeLoft(rings: rings, ringV: ringV, sides: sides)
        let geometry = makeGeometry(loft: loft, elements: [loft.indices(includeColumn: { _ in true })])
        geometry.materials = [material]
        let bodyNode = SCNNode(geometry: geometry)
        bodyNode.name = "realSnakeBody"

        // Spine: bones evenly spaced head to tail, flat children of one
        // skeleton root (no hierarchy, so each bone's sway stays local).
        let skeletonRoot = SCNNode()
        skeletonRoot.name = "realSnakeSkeleton"
        var bones: [SCNNode] = []
        var inverseBinds: [NSValue] = []
        var laterals: [SIMD3<Float>] = []
        let spacing = spline.length / Float(boneCount - 1)
        for k in 0..<boneCount {
            let d = spacing * Float(k)
            let frame = spline.frame(at: d)
            let r = profile.radius(at: d)
            let lift = RealSnakeBodyProfile.centreLift(radius: r)
            let p = SIMD3<Float>(frame.position.x, boardY + lift, frame.position.z)
            let bone = SCNNode()
            bone.name = "realSnakeBone\(k)"
            bone.position = SCNVector3(p.x, p.y, p.z)
            skeletonRoot.addChildNode(bone)
            bones.append(bone)
            // Root, skeleton and body node all sit at identity, so the bind
            // pose is just each bone's translation.
            inverseBinds.append(NSValue(scnMatrix4: SCNMatrix4MakeTranslation(-p.x, -p.y, -p.z)))
            laterals.append(SIMD3<Float>(frame.forward.z, 0, -frame.forward.x))
        }

        // Each ring's vertices share the same two bones (the pair the ring
        // falls between) with linear weights; four components per vertex,
        // the last two unused.
        let vertexCount = loft.positions.count
        var weights: [Float] = []
        var boneIndices: [UInt16] = []
        weights.reserveCapacity(vertexCount * 4)
        boneIndices.reserveCapacity(vertexCount * 4)
        for i in 0..<ringCount {
            let f = ringD[i] / spacing
            let k = min(max(Int(floor(f)), 0), boneCount - 2)
            let w1 = RealSnakeMath.clamp01(f - Float(k))
            let w0 = 1 - w1
            for _ in 0...sides {
                weights.append(w0)
                weights.append(w1)
                weights.append(0)
                weights.append(0)
                boneIndices.append(UInt16(k))
                boneIndices.append(UInt16(k + 1))
                boneIndices.append(0)
                boneIndices.append(0)
            }
        }
        let weightData = weights.withUnsafeBufferPointer { Data(buffer: $0) }
        let indexData = boneIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        let weightSource = SCNGeometrySource(data: weightData,
                                             semantic: .boneWeights,
                                             vectorCount: vertexCount,
                                             usesFloatComponents: true,
                                             componentsPerVector: 4,
                                             bytesPerComponent: MemoryLayout<Float>.size,
                                             dataOffset: 0,
                                             dataStride: MemoryLayout<Float>.size * 4)
        let indexSource = SCNGeometrySource(data: indexData,
                                            semantic: .boneIndices,
                                            vectorCount: vertexCount,
                                            usesFloatComponents: false,
                                            componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<UInt16>.size,
                                            dataOffset: 0,
                                            dataStride: MemoryLayout<UInt16>.size * 4)
        let skinner = SCNSkinner(baseGeometry: geometry,
                                 bones: bones,
                                 boneInverseBindTransforms: inverseBinds,
                                 boneWeights: weightSource,
                                 boneIndices: indexSource)
        skinner.baseGeometryBindTransform = SCNMatrix4Identity
        skinner.skeleton = skeletonRoot
        bodyNode.skinner = skinner

        return RealSnakeBodyRig(bodyNode: bodyNode, skeletonRoot: skeletonRoot, bones: bones, laterals: laterals)
    }

    // MARK: Contact shadow

    /// A flat ribbon just above the board, following the spine from the
    /// snout tip to the tail, about twice as wide as the snake, textured
    /// with a soft dark falloff -- the contact occlusion that makes the
    /// snake sit on the board instead of floating over it.
    static func buildContactShadow(spline: RealSnakeSpline, profile: RealSnakeBodyProfile, head: RealSnakeHeadShape,
                                   boardY: Float, material: SCNMaterial) -> SCNNode {
        let samples = 80
        let start: Float = -head.z(1)          // snout tip, ahead of the head square
        let end: Float = spline.length
        let origin = spline.frame(at: 0)
        let y: Float = boardY + 0.006
        let up = SIMD3<Float>(0, 1, 0)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        positions.reserveCapacity(samples * 2)
        normals.reserveCapacity(samples * 2)
        uvs.reserveCapacity(samples * 2)
        for i in 0..<samples {
            let t = Float(i) / Float(samples - 1)
            let d = start + (end - start) * t
            let centre: SIMD3<Float>
            let forward: SIMD3<Float>
            if d < 0 {
                centre = origin.position + origin.forward * d
                forward = origin.forward
            } else {
                let frame = spline.frame(at: d)
                centre = frame.position
                forward = frame.forward
            }
            let bodyHalf: Float = d >= 0 ? profile.radius(at: d) * 1.05 : 0
            // Head-local z is -d (the head faces back along -forward).
            let headS: Float = (-d - head.z(0)) / head.length
            let headHalf: Float = (headS >= 0 && headS <= 1) ? head.halfWidth(headS) : 0
            let half: Float = max(bodyHalf, headHalf) * 1.9 + 0.01
            let lateral = SIMD3<Float>(forward.z, 0, -forward.x)
            let offset: SIMD3<Float> = lateral * half
            let left: SIMD3<Float> = centre + offset
            let right: SIMD3<Float> = centre - offset
            positions.append(SIMD3<Float>(left.x, y, left.z))
            positions.append(SIMD3<Float>(right.x, y, right.z))
            normals.append(up)
            normals.append(up)
            uvs.append(SIMD2<Float>(0, t))
            uvs.append(SIMD2<Float>(1, t))
        }

        // Per step: A = left(i), B = right(i), D = left(i+1), C = right(i+1);
        // (A, B, D) and (B, C, D) both face +y.
        var indices: [UInt16] = []
        indices.reserveCapacity((samples - 1) * 6)
        for i in 0..<(samples - 1) {
            let a = UInt16(2 * i)
            let b = UInt16(2 * i + 1)
            let d = UInt16(2 * i + 2)
            let c = UInt16(2 * i + 3)
            indices.append(contentsOf: [a, b, d, b, c, d])
        }

        let sources = [
            vectorSource(positions, semantic: .vertex),
            vectorSource(normals, semantic: .normal),
            uvSource(uvs),
        ]
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = "realSnakeContactShadow"
        node.castsShadow = false
        return node
    }
}
