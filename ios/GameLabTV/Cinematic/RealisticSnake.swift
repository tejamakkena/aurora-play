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
    /// natural species palette. The board's `SnakeStyle` body colors map to
    /// fixed species (see `RealSnakeSpecies.matching`); any other color goes
    /// by hue (red -> coral snake, orange -> corn snake, yellow -> python,
    /// green -> green tree snake, blue -> king snake, purple -> diamondback).
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
        if let species = byKnownColor(color) { return species }
        if let species = byHue(color) { return species }
        if let species = byHue(bandColor) { return species }
        return .kingSnake
    }

    /// The board's own `SnakeStyle` body colors, each pinned to the closest
    /// natural species so a style keeps its character (rattlesnakes stay
    /// diamondbacks, the black krait becomes a banded king snake).
    private static let knownColors: [(red: CGFloat, green: CGFloat, blue: CGFloat, species: RealSnakeSpecies)] = [
        (0.27, 0.50, 0.16, .greenTreeSnake),   // green python
        (0.70, 0.56, 0.36, .diamondback),      // tan rattlesnake
        (0.07, 0.07, 0.07, .kingSnake),        // black-and-yellow krait
        (0.78, 0.13, 0.08, .coralSnake),       // red coral style
        (0.45, 0.46, 0.21, .cornSnake),        // olive viper
        (0.56, 0.40, 0.22, .burmesePython),    // brown python
        (0.08, 0.48, 0.26, .greenTreeSnake),   // emerald tree snake
        (0.56, 0.52, 0.45, .diamondback),      // grey-brown rattlesnake
    ]

    private static func byKnownColor(_ color: UIColor) -> RealSnakeSpecies? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        for entry in knownColors {
            let dr = red - entry.red
            let dg = green - entry.green
            let db = blue - entry.blue
            if abs(dr) < 0.03 && abs(dg) < 0.03 && abs(db) < 0.03 {
                return entry.species
            }
        }
        return nil
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

    /// Closes the back of the skull to a point, but with a full, rounded
    /// dome (square root of a quarter sine) so the skull still overhangs
    /// the neck instead of tapering away from it.
    func backClosure(_ s: Float) -> Float {
        sqrt(sin(min(s / 0.16, 1) * Float.pi / 2))
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

// MARK: - Head

/// Builds the head into `parent` (head-local space, see
/// `RealSnakeHeadShape`): a lofted upper head and a separately hinged lower
/// jaw, each split into a scaly outer surface and a pink mouth surface,
/// plus eyes, fangs and the forked tongue.
@MainActor
enum RealSnakeHeadBuilder {
    struct Parts {
        let jawPivot: SCNNode
        let tongueRoot: SCNNode
        /// How far the tongue slides forward when it flicks out.
        let tongueTravel: Float
    }

    static func build(shape: RealSnakeHeadShape, skin: RealSnakeSkin, into parent: SCNNode) -> Parts {
        let sides = 20
        let ringCount = 26
        let hingeZ = shape.z(0.13)

        var upperRings: [[SIMD3<Float>]] = []
        var jawRings: [[SIMD3<Float>]] = []
        var ringV: [Float] = []
        upperRings.reserveCapacity(ringCount)
        jawRings.reserveCapacity(ringCount)
        ringV.reserveCapacity(ringCount)
        for i in 0..<ringCount {
            let s = Float(i) / Float(ringCount - 1)
            let z = shape.z(s)
            let halfWidth = shape.halfWidth(s)
            let top = shape.top(s)
            let palate = shape.palate(s)
            let jawHalf = shape.jawHalfWidth(s)
            let jawDepth = shape.jawDepth(s)
            let jawTop = shape.jawTop(s)
            var upper: [SIMD3<Float>] = []
            var jaw: [SIMD3<Float>] = []
            upper.reserveCapacity(sides)
            jaw.reserveCapacity(sides)
            for j in 0..<sides {
                // Same angular convention as the body: 0 underneath, pi/2 at
                // the +x lip line, pi on top.
                let phi = 2 * Float.pi * Float(j) / Float(sides)
                let sn = sin(phi)
                let cs = cos(phi)
                let sx = RealSnakeMath.signedPow(sn, 2.0 / 3.0)
                let upperY: Float
                let jawY: Float
                if cs <= 0 {
                    // Superellipse (n = 3): a flat crown with firm sides.
                    upperY = shape.mouthY + top * pow(-cs, 2.0 / 3.0)
                    jawY = jawTop * pow(-cs, 1.0 / 3.0)
                } else {
                    upperY = shape.mouthY - palate * pow(cs, 1.0 / 3.0)
                    jawY = -jawDepth * pow(cs, 0.8)
                }
                upper.append(SIMD3<Float>(halfWidth * sx, upperY, z))
                // The jaw is built relative to its hinge so it can rotate.
                jaw.append(SIMD3<Float>(jawHalf * sx, jawY, z - hingeZ))
            }
            upperRings.append(upper)
            jawRings.append(jaw)
            // v = 0 at the snout, so scales overlap toward the neck.
            ringV.append(1 - s)
        }

        let upperLoft = RealSnakeLoft(rings: upperRings, ringV: ringV, sides: sides)
        let jawLoft = RealSnakeLoft(rings: jawRings, ringV: ringV, sides: sides)
        let quarter = sides / 4
        let threeQuarters = 3 * sides / 4
        let isTopColumn: (Int) -> Bool = { column in column >= quarter && column < threeQuarters }
        let isBottomColumn: (Int) -> Bool = { column in !(column >= quarter && column < threeQuarters) }

        // Upper head: crown is skin, underside is the palate.
        let upperGeometry = RealSnakeMesh.makeGeometry(loft: upperLoft, elements: [
            upperLoft.indices(includeColumn: isTopColumn),
            upperLoft.indices(includeColumn: isBottomColumn),
        ])
        upperGeometry.materials = [skin.headMaterial, skin.mouthMaterial]
        let upperNode = SCNNode(geometry: upperGeometry)
        upperNode.name = "realSnakeHead"
        parent.addChildNode(upperNode)

        // Lower jaw: chin and throat are skin, the top is the mouth floor.
        let jawGeometry = RealSnakeMesh.makeGeometry(loft: jawLoft, elements: [
            jawLoft.indices(includeColumn: isBottomColumn),
            jawLoft.indices(includeColumn: isTopColumn),
        ])
        jawGeometry.materials = [skin.headMaterial, skin.mouthMaterial]
        let jawPivot = SCNNode()
        jawPivot.name = "realSnakeJaw"
        jawPivot.position = SCNVector3(0, shape.mouthY, hingeZ)
        jawPivot.addChildNode(SCNNode(geometry: jawGeometry))
        parent.addChildNode(jawPivot)

        addEyes(shape: shape, skin: skin, to: parent)
        addFangs(shape: shape, skin: skin, to: parent)
        let tongue = makeTongue(shape: shape, skin: skin)
        parent.addChildNode(tongue.root)

        return Parts(jawPivot: jawPivot, tongueRoot: tongue.root, tongueTravel: tongue.travel)
    }

    /// Glossy dark eyeballs set into the sides of the head, each with a
    /// vertical slit pupil (a flattened ellipsoid on the outward face) and a
    /// small always-lit catchlight.
    private static func addEyes(shape: RealSnakeHeadShape, skin: RealSnakeSkin, to parent: SCNNode) {
        let eyeS: Float = 0.64
        let eyeHalf = shape.halfWidth(eyeS)
        let eyeTop = shape.top(eyeS)
        let eyeRadius: Float = 0.20 * shape.radius

        let eyeGeometry = SCNSphere(radius: CGFloat(eyeRadius))
        eyeGeometry.segmentCount = 18
        eyeGeometry.materials = [skin.eyeMaterial]
        let pupilGeometry = SCNSphere(radius: CGFloat(eyeRadius * 0.42))
        pupilGeometry.segmentCount = 12
        pupilGeometry.materials = [skin.pupilMaterial]
        let glintGeometry = SCNSphere(radius: CGFloat(eyeRadius * 0.14))
        glintGeometry.segmentCount = 8
        glintGeometry.materials = [skin.catchlightMaterial]

        for side: Float in [-1, 1] {
            let eye = SCNNode(geometry: eyeGeometry)
            eye.position = SCNVector3(side * 0.80 * eyeHalf, shape.mouthY + 0.60 * eyeTop, shape.z(eyeS))
            parent.addChildNode(eye)

            let lookDirection = RealSnakeMath.normalized(SIMD3<Float>(side, 0.15, 0.35),
                                                         fallback: SIMD3<Float>(side, 0, 0))
            let pupilOffset: SIMD3<Float> = lookDirection * (eyeRadius * 0.88)
            let pupil = SCNNode(geometry: pupilGeometry)
            pupil.position = SCNVector3(pupilOffset.x, pupilOffset.y, pupilOffset.z)
            // Local z (the thin axis) faces outward; local y stays vertical.
            pupil.eulerAngles = SCNVector3(0, atan2(lookDirection.x, lookDirection.z), 0)
            pupil.scale = SCNVector3(0.30, 1.0, 0.19)
            eye.addChildNode(pupil)

            let glintDirection = RealSnakeMath.normalized(SIMD3<Float>(side * 0.55, 0.70, 0.45),
                                                          fallback: SIMD3<Float>(0, 1, 0))
            let glintOffset: SIMD3<Float> = glintDirection * (eyeRadius * 0.93)
            let glint = SCNNode(geometry: glintGeometry)
            glint.position = SCNVector3(glintOffset.x, glintOffset.y, glintOffset.z)
            glint.castsShadow = false
            eye.addChildNode(glint)
        }
    }

    /// Two small fangs under the front of the upper jaw: hidden inside the
    /// closed mouth, revealed when the jaw drops in `playEat()`.
    private static func addFangs(shape: RealSnakeHeadShape, skin: RealSnakeSkin, to parent: SCNNode) {
        let fangS: Float = 0.86
        let fangLength: Float = 0.14 * shape.radius
        let fang = SCNCone(topRadius: 0, bottomRadius: CGFloat(0.022 * shape.radius), height: CGFloat(fangLength))
        fang.radialSegmentCount = 6
        fang.materials = [skin.fangMaterial]
        let halfWidth = shape.halfWidth(fangS)
        let rootY = shape.mouthY - shape.palate(fangS)
        for side: Float in [-1, 1] {
            let node = SCNNode(geometry: fang)
            // Flipped so the cone's point (its +y end) hangs downward.
            node.eulerAngles = SCNVector3(Float.pi, 0, 0)
            node.position = SCNVector3(side * 0.45 * halfWidth, rootY - fangLength * 0.45, shape.z(fangS))
            node.castsShadow = false
            parent.addChildNode(node)
        }
    }

    /// A thin forked tongue: a short cylinder ending in two splayed,
    /// tapered cones. It rests fully inside the closed mouth (and hidden);
    /// `RealisticSnakeNode.startTongue` slides it out along +z.
    private static func makeTongue(shape: RealSnakeHeadShape, skin: RealSnakeSkin) -> (root: SCNNode, travel: Float) {
        let r = shape.radius
        let stemLength: Float = 0.55 * r
        let forkLength: Float = 0.34 * r
        let root = SCNNode()
        root.name = "realSnakeTongue"

        let stem = SCNCylinder(radius: CGFloat(0.04 * r), height: CGFloat(stemLength))
        stem.radialSegmentCount = 8
        stem.materials = [skin.tongueMaterial]
        let stemNode = SCNNode(geometry: stem)
        // Cylinder axis is +y; a quarter turn about x lays it along +z.
        stemNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        stemNode.position = SCNVector3(0, 0, stemLength / 2)
        stemNode.castsShadow = false
        root.addChildNode(stemNode)

        let tine = SCNCone(topRadius: 0, bottomRadius: CGFloat(0.034 * r), height: CGFloat(forkLength))
        tine.radialSegmentCount = 6
        tine.materials = [skin.tongueMaterial]
        for side: Float in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 0, stemLength * 0.96)
            pivot.eulerAngles = SCNVector3(0, side * 0.30, 0)
            let tineNode = SCNNode(geometry: tine)
            tineNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            tineNode.position = SCNVector3(0, 0, forkLength / 2)
            tineNode.castsShadow = false
            pivot.addChildNode(tineNode)
            root.addChildNode(pivot)
        }

        let tongueLength = stemLength + forkLength
        root.position = SCNVector3(0, shape.mouthY - 0.01 * r, shape.z(1) - tongueLength - 0.08 * r)
        root.isHidden = true
        return (root, tongueLength * 0.95)
    }
}

// MARK: - Scale lattice (species independent)

/// The scale layout of the skin texture: 16 columns of staggered,
/// overlapping dorsal scales around (u, image x) by 88 rows along (v,
/// image y), with wide ventral scutes across the belly at both x edges.
/// Built once and shared by every species: it yields the height field
/// (normal map), the per-pixel edge factor (roughness), and for each pixel
/// the scale it belongs to (so colour patterns follow scale boundaries).
/// The image tiles seamlessly in both directions.
struct RealSnakeLattice {
    static let width = 256
    static let height = 1024
    static let columns = 16
    static let rows = 88
    /// The head texture uses the first 256 pixel rows, exactly 22 lattice
    /// rows (an even count, so the stagger lines up with the body maps).
    static let headPixelRows = 256

    /// 0 in the crevices, up to 1 at a scale's raised free edge.
    let heightField: [Float]
    /// 0 at a scale's centre, 1 at its rim.
    let edge: [Float]
    /// Stable 0...1 random value per scale.
    let scaleHash: [Float]
    /// Pixel-space centre of the scale each pixel belongs to (unwrapped, so
    /// it can sit slightly outside the image near the borders).
    let centreX: [Float]
    let centreY: [Float]

    init() {
        let w = RealSnakeLattice.width
        let h = RealSnakeLattice.height
        let columns = RealSnakeLattice.columns
        let rows = RealSnakeLattice.rows
        let count = w * h
        let su = Float(w) / Float(columns)
        let sv = Float(h) / Float(rows)
        let lengthRadius: Float = 1.25 * sv
        let widthRadius: Float = 0.62 * su
        let halfW = Float(w) * 0.5

        var heights = [Float](repeating: 0, count: count)
        var edges = [Float](repeating: 1, count: count)
        var hashes = [Float](repeating: 0, count: count)
        var centresX = [Float](repeating: 0, count: count)
        var centresY = [Float](repeating: 0, count: count)

        for y in 0..<h {
            let fy = Float(y) + 0.5
            let r0 = Int(floor(fy / sv))
            for x in 0..<w {
                let fx = Float(x) + 0.5
                let idx = y * w + x
                var pixelHeight: Float = 0
                var pixelEdge: Float = 1
                var pixelHash = RealSnakeMath.hash(RealSnakeMath.mod(r0, rows), RealSnakeMath.mod(Int(fx / su), columns))
                var pixelCentreX = fx
                var pixelCentreY = fy

                // Rows toward the head (smaller y) overlap the next row, so
                // the first row that covers this pixel is the visible scale.
                for r in (r0 - 1)...(r0 + 1) {
                    let cy = Float(r) * sv
                    let dy = fy - cy
                    if abs(dy) >= lengthRadius { continue }
                    let offset: Float = RealSnakeMath.mod(r, 2) == 1 ? 0.5 : 0
                    let nearest = Int((fx / su - 0.5 - offset).rounded())
                    // Narrower toward the free (tail-side) edge: a rounded
                    // lozenge rather than a plain ellipse.
                    let along = RealSnakeMath.clamp01(dy / lengthRadius)
                    let halfWidth: Float = widthRadius * (1 - 0.35 * along)
                    let qy: Float = dy / lengthRadius
                    var bestQ: Float = 1
                    var bestColumn = nearest
                    for c in (nearest - 1)...(nearest + 1) {
                        let cx = (Float(c) + 0.5 + offset) * su
                        let qx: Float = (fx - cx) / halfWidth
                        let q: Float = qx * qx + qy * qy
                        if q < bestQ {
                            bestQ = q
                            bestColumn = c
                        }
                    }
                    if bestQ < 1 {
                        // Domed, and rising toward the free edge so the
                        // overlap reads as a step in the normal map.
                        let ramp: Float = (qy + 1) * 0.5
                        pixelHeight = sqrt(1 - bestQ) * (0.45 + 0.55 * ramp)
                        pixelEdge = bestQ
                        pixelHash = RealSnakeMath.hash(RealSnakeMath.mod(r, rows), RealSnakeMath.mod(bestColumn, columns))
                        pixelCentreX = (Float(bestColumn) + 0.5 + offset) * su
                        pixelCentreY = cy
                        break
                    }
                }

                // Ventral scutes: one wide plate per row across the belly.
                let lateral = abs(fx - halfW) / halfW
                let bellyWeight = RealSnakeMath.smoothstep(0.78, 0.88, lateral)
                if bellyWeight > 0 {
                    let rowPosition = fy / sv
                    let row = Int(floor(rowPosition))
                    let fraction = rowPosition - Float(row)
                    let scuteHeight: Float
                    if fraction < 0.9 {
                        scuteHeight = 0.15 + 0.75 * pow(fraction / 0.9, 1.5)
                    } else {
                        scuteHeight = 0.9 - 0.75 * RealSnakeMath.smoothstep(0.9, 1.0, fraction)
                    }
                    let scuteEdge = RealSnakeMath.smoothstep(0.80, 1.0, fraction)
                    pixelHeight += (scuteHeight - pixelHeight) * bellyWeight
                    pixelEdge += (scuteEdge - pixelEdge) * bellyWeight
                    if bellyWeight > 0.5 {
                        pixelHash = RealSnakeMath.hash(RealSnakeMath.mod(row, rows), 997)
                        pixelCentreX = fx
                        pixelCentreY = (Float(row) + 0.5) * sv
                    }
                }

                heights[idx] = pixelHeight
                edges[idx] = pixelEdge
                hashes[idx] = pixelHash
                centresX[idx] = pixelCentreX
                centresY[idx] = pixelCentreY
            }
        }

        self.heightField = heights
        self.edge = edges
        self.scaleHash = hashes
        self.centreX = centresX
        self.centreY = centresY
    }
}

// MARK: - Species colour patterns

/// Colour as a function of skin position. `a` is lateral (-1 and +1 at the
/// belly midline, 0 on the spine, about +-0.5 at the widest point of the
/// flank) and `t` runs along the texture. Body patterns repeat a whole
/// number of times per tile so the texture wraps without a seam. `n` is the
/// owning scale's random value, for per-scale speckles.
enum RealSnakePattern {
    typealias RGB = SIMD3<Float>

    private static func periodic(_ t: Float, count: Int) -> (index: Int, f: Float) {
        let ft = t * Float(count)
        let whole = floor(ft)
        return (RealSnakeMath.mod(Int(whole), count), ft - whole)
    }

    static func body(_ species: RealSnakeSpecies, a rawA: Float, t: Float, n: Float) -> RGB {
        let a = RealSnakeMath.wrapLateral(rawA)
        let aa = abs(a)
        let belly = RealSnakeMath.smoothstep(0.58, 0.82, aa)
        switch species {
        case .burmesePython: return python(aa: aa, t: t, belly: belly)
        case .diamondback: return diamondback(aa: aa, t: t, n: n, belly: belly)
        case .coralSnake: return coral(a: a, t: t, n: n, belly: belly)
        case .cornSnake: return corn(a: a, aa: aa, t: t, belly: belly)
        case .greenTreeSnake: return greenTree(aa: aa, n: n, belly: belly)
        case .kingSnake: return king(a: a, aa: aa, t: t, belly: belly)
        }
    }

    /// Burmese python: big dark-brown saddles rimmed in black on a tan
    /// ground, smaller light-centred blotches low on the flanks.
    private static func python(aa: Float, t: Float, belly: Float) -> RGB {
        let ground = RGB(0.76, 0.63, 0.42)
        let blotch = RGB(0.33, 0.23, 0.13)
        let outline = RGB(0.11, 0.08, 0.06)
        let lightCentre = RGB(0.64, 0.54, 0.36)
        let bellyColour = RGB(0.90, 0.86, 0.74)
        let p = periodic(t, count: 8)
        let h1 = RealSnakeMath.hash(p.index, 11)
        let h2 = RealSnakeMath.hash(p.index, 23)
        let centre: Float = 0.5 + (h1 - 0.5) * 0.12
        let df = abs(p.f - centre)
        let halfLength: Float = 0.30 + 0.08 * h2
        let wobble: Float = 0.03 * sin(p.f * 12.566 + Float(p.index))
        let halfWidth: Float = 0.30 + 0.06 * h1 + wobble
        let m: Float = pow(df / halfLength, 3) + pow(aa / halfWidth, 3)
        var c = ground
        if m < 0.80 {
            c = blotch
        } else if m < 1.25 {
            c = outline
        }
        let gap: Float = min(p.f, 1 - p.f) / 0.18
        let low: Float = (aa - 0.47) / 0.09
        let ml: Float = low * low + gap * gap
        if ml < 0.35 {
            c = lightCentre
        } else if ml < 1.0 {
            c = blotch
        } else if ml < 1.45 {
            c = outline
        }
        return RealSnakeMath.lerp(c, bellyColour, belly)
    }

    /// Western diamondback: a chain of dark diamonds with pale borders down
    /// the spine on a dusty grey-brown, finely speckled flanks.
    private static func diamondback(aa: Float, t: Float, n: Float, belly: Float) -> RGB {
        let ground = RGB(0.57, 0.49, 0.37)
        let dark = RGB(0.27, 0.20, 0.14)
        let centre = RGB(0.45, 0.37, 0.27)
        let border = RGB(0.88, 0.84, 0.68)
        let bellyColour = RGB(0.88, 0.84, 0.70)
        let p = periodic(t, count: 8)
        let dm: Float = abs(p.f - 0.5) / 0.5 + aa / 0.42
        var c = ground
        if dm < 0.42 {
            c = centre
        } else if dm < 0.80 {
            c = dark
        } else if dm < 0.97 {
            c = border
        } else if aa > 0.36 && n > 0.72 {
            c = ground * 0.72
        }
        return RealSnakeMath.lerp(c, bellyColour, belly)
    }

    /// Coral snake: red, yellow, black, yellow rings all the way round
    /// ("red touches yellow"), the red scales tipped black here and there.
    private static func coral(a: Float, t: Float, n: Float, belly: Float) -> RGB {
        let red = RGB(0.78, 0.13, 0.08)
        let yellow = RGB(0.97, 0.80, 0.28)
        let black = RGB(0.05, 0.045, 0.045)
        let p = periodic(t, count: 6)
        let f: Float = p.f + 0.012 * sin(a * 9.42)
        var c: RGB
        if f < 0.40 {
            c = n > 0.72 ? RealSnakeMath.lerp(red, black, 0.6) : red
        } else if f < 0.47 {
            c = yellow
        } else if f < 0.93 {
            c = black
        } else {
            c = yellow
        }
        c *= 1 + 0.12 * belly
        return c
    }

    /// Corn snake: black-edged red saddles on orange, a checkerboard belly.
    private static func corn(a: Float, aa: Float, t: Float, belly: Float) -> RGB {
        let ground = RGB(0.86, 0.49, 0.26)
        let saddle = RGB(0.74, 0.20, 0.10)
        let border = RGB(0.10, 0.06, 0.04)
        let white = RGB(0.95, 0.92, 0.84)
        let check = RGB(0.10, 0.09, 0.09)
        let p = periodic(t, count: 9)
        let df = abs(p.f - 0.5)
        let ms: Float = pow(df / 0.27, 4) + pow(aa / 0.30, 4)
        var c = ground
        if ms < 1 {
            c = saddle
        } else if ms < 1.7 {
            c = border
        }
        let gap: Float = min(p.f, 1 - p.f) / 0.14
        let low: Float = (aa - 0.48) / 0.08
        let ml: Float = low * low + gap * gap
        if ml < 1 {
            c = saddle
        } else if ml < 1.5 {
            c = border
        }
        let row = Int(floor(t * Float(RealSnakeLattice.rows)))
        let sideBit = a > 0 ? 1 : 0
        let isCheck = RealSnakeMath.mod(row + sideBit * 2, 4) == 0
        return RealSnakeMath.lerp(c, isCheck ? check : white, belly)
    }

    /// Green tree snake: plain leaf green, brighter flanks, a pale yellow
    /// belly and a few white flecks along the spine.
    private static func greenTree(aa: Float, n: Float, belly: Float) -> RGB {
        let dorsal = RGB(0.17, 0.52, 0.14)
        let flank = RGB(0.34, 0.66, 0.19)
        let bellyColour = RGB(0.80, 0.86, 0.42)
        let fleck = RGB(0.90, 0.94, 0.78)
        var c = RealSnakeMath.lerp(dorsal, flank, RealSnakeMath.smoothstep(0.08, 0.50, aa))
        if aa < 0.12 && n > 0.86 {
            c = fleck
        }
        return RealSnakeMath.lerp(c, bellyColour, belly)
    }

    /// California king snake: glossy black with cream rings that widen
    /// toward the belly.
    private static func king(a: Float, aa: Float, t: Float, belly: Float) -> RGB {
        let dark = RGB(0.07, 0.06, 0.055)
        let cream = RGB(0.92, 0.88, 0.74)
        let p = periodic(t, count: 10)
        let wobble: Float = 0.02 * sin(a * 9 + Float(p.index))
        let width: Float = 0.16 + 0.12 * aa + wobble
        let c = p.f < width ? cream : dark
        let lighter: RGB = c * 1.15 + RGB(0.03, 0.03, 0.03)
        return RealSnakeMath.lerp(c, lighter, belly * 0.5)
    }

    /// Head colouring. Here `t` runs from the snout (0) to the back of the
    /// skull (1); `aa` is 0 on top, ~0.35 at the eyes, 0.5 at the lips and
    /// beyond 0.5 under the jaw.
    static func head(_ species: RealSnakeSpecies, a rawA: Float, t rawT: Float, n: Float) -> RGB {
        let aa = abs(RealSnakeMath.wrapLateral(rawA))
        let t = RealSnakeMath.clamp01(rawT)
        let lip = RealSnakeMath.smoothstep(0.40, 0.52, aa)
        switch species {
        case .burmesePython:
            let ground = RGB(0.76, 0.63, 0.42)
            let blotch = RGB(0.33, 0.23, 0.13)
            let outline = RGB(0.11, 0.08, 0.06)
            let cream = RGB(0.90, 0.86, 0.74)
            var c = ground
            let spear: Float = 0.04 + 0.20 * t
            if t > 0.12 && aa < spear {
                c = blotch
            } else if t > 0.10 && aa < spear + 0.05 {
                c = outline
            }
            if t > 0.18 && abs(aa - 0.35) < 0.04 {
                c = outline
            }
            return RealSnakeMath.lerp(c, cream, lip)
        case .diamondback:
            let ground = RGB(0.57, 0.49, 0.37)
            let band = RGB(0.36, 0.28, 0.20)
            let cream = RGB(0.88, 0.84, 0.68)
            var c = ground
            let stripe: Float = 0.30 + 0.18 * t
            if abs(aa - stripe) < 0.04 {
                c = cream
            } else if aa > stripe && aa < stripe + 0.10 {
                c = band
            }
            return RealSnakeMath.lerp(c, cream, lip)
        case .coralSnake:
            let yellow = RGB(0.97, 0.80, 0.28)
            let black = RGB(0.05, 0.045, 0.045)
            var c = black
            if t > 0.46 && t < 0.80 {
                c = yellow
            }
            c *= 1 + 0.10 * lip
            return c
        case .cornSnake:
            let ground = RGB(0.86, 0.49, 0.26)
            let saddle = RGB(0.74, 0.20, 0.10)
            let border = RGB(0.10, 0.06, 0.04)
            let white = RGB(0.95, 0.92, 0.84)
            var c = ground
            let spear: Float = 0.22 * max(0, t - 0.15) / 0.85
            if aa < spear {
                c = saddle
            } else if t > 0.15 && aa < spear + 0.04 {
                c = border
            }
            if t > 0.25 && abs(aa - (0.33 + 0.12 * t)) < 0.045 {
                c = saddle
            }
            return RealSnakeMath.lerp(c, white, lip)
        case .greenTreeSnake:
            let dorsal = RGB(0.17, 0.52, 0.14)
            let flank = RGB(0.34, 0.66, 0.19)
            let bellyColour = RGB(0.80, 0.86, 0.42)
            let c = RealSnakeMath.lerp(dorsal, flank, RealSnakeMath.smoothstep(0.10, 0.45, aa))
            return RealSnakeMath.lerp(c, bellyColour, lip)
        case .kingSnake:
            let dark = RGB(0.07, 0.06, 0.055)
            let cream = RGB(0.92, 0.88, 0.74)
            var c = dark
            if t < 0.10 && n > 0.55 {
                c = cream * 0.9
            }
            let lipColour: RGB = n > 0.6 ? cream * 0.82 : cream
            return RealSnakeMath.lerp(c, lipColour, lip)
        }
    }
}

// MARK: - Textures (Core Graphics, built once)

@MainActor
enum RealSnakeTextures {
    static var sRGBSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Data maps (normal, roughness) are tagged linear so SceneKit samples
    /// the stored values as-is instead of sRGB-decoding them.
    static var linearSpace: CGColorSpace {
        CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    static func image(width: Int, height: Int, rgba: [UInt8], space: CGColorSpace,
                      alphaInfo: CGImageAlphaInfo) -> UIImage? {
        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        guard let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 32,
                                    bytesPerRow: width * 4,
                                    space: space,
                                    bitmapInfo: CGBitmapInfo(rawValue: alphaInfo.rawValue),
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: true,
                                    intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Tangent-space normal map from the scale height field (Sobel), +y up.
    static func normalMap(from lattice: RealSnakeLattice) -> UIImage? {
        let w = RealSnakeLattice.width
        let h = RealSnakeLattice.height
        let field = lattice.heightField
        let strength: Float = 0.45
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let rowUp = RealSnakeMath.mod(y - 1, h) * w
            let rowMid = y * w
            let rowDown = RealSnakeMath.mod(y + 1, h) * w
            for x in 0..<w {
                let xl = RealSnakeMath.mod(x - 1, w)
                let xr = RealSnakeMath.mod(x + 1, w)
                let tl = field[rowUp + xl]
                let tc = field[rowUp + x]
                let tr = field[rowUp + xr]
                let ml = field[rowMid + xl]
                let mr = field[rowMid + xr]
                let bl = field[rowDown + xl]
                let bc = field[rowDown + x]
                let br = field[rowDown + xr]
                let right: Float = tr + 2 * mr + br
                let left: Float = tl + 2 * ml + bl
                let below: Float = bl + 2 * bc + br
                let above: Float = tl + 2 * tc + tr
                let gx: Float = right - left
                let gy: Float = below - above
                let nx: Float = -gx * strength
                // Image y runs down, tangent-space +y runs up.
                let ny: Float = gy * strength
                let inv: Float = 1 / sqrt(nx * nx + ny * ny + 1)
                let o = (rowMid + x) * 4
                pixels[o] = RealSnakeMath.byte(nx * inv * 0.5 + 0.5)
                pixels[o + 1] = RealSnakeMath.byte(ny * inv * 0.5 + 0.5)
                pixels[o + 2] = RealSnakeMath.byte(inv * 0.5 + 0.5)
                pixels[o + 3] = 255
            }
        }
        return image(width: w, height: h, rgba: pixels, space: linearSpace, alphaInfo: .noneSkipLast)
    }

    /// Scale faces slightly glossy, rims and crevices rougher.
    static func roughnessMap(from lattice: RealSnakeLattice) -> UIImage? {
        let w = RealSnakeLattice.width
        let h = RealSnakeLattice.height
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for idx in 0..<(w * h) {
            let rim = RealSnakeMath.smoothstep(0.55, 1.0, lattice.edge[idx])
            let jitter: Float = 0.10 * (lattice.scaleHash[idx] - 0.5)
            let value = RealSnakeMath.byte(0.30 + 0.30 * rim + jitter)
            let o = idx * 4
            pixels[o] = value
            pixels[o + 1] = value
            pixels[o + 2] = value
            pixels[o + 3] = 255
        }
        return image(width: w, height: h, rgba: pixels, space: linearSpace, alphaInfo: .noneSkipLast)
    }

    /// Species albedo. 80% of each pixel's colour comes from its scale's
    /// centre (so pattern edges follow scale outlines, as on a real snake),
    /// 20% from the pixel itself (soft edges); then per-scale brightness and
    /// warmth variation and a little crevice darkening.
    static func albedo(species: RealSnakeSpecies, lattice: RealSnakeLattice, head: Bool) -> UIImage? {
        let w = RealSnakeLattice.width
        let h = head ? RealSnakeLattice.headPixelRows : RealSnakeLattice.height
        let halfW = Float(w) * 0.5
        let tileHeight = Float(h)
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let fy = Float(y) + 0.5
            for x in 0..<w {
                let idx = y * w + x
                let fx = Float(x) + 0.5
                let pixelA: Float = (fx - halfW) / halfW
                let centreA: Float = (lattice.centreX[idx] - halfW) / halfW
                let pixelT: Float = fy / tileHeight
                let centreT: Float = lattice.centreY[idx] / tileHeight
                let n = lattice.scaleHash[idx]
                let fromCentre: SIMD3<Float>
                let fromPixel: SIMD3<Float>
                if head {
                    fromCentre = RealSnakePattern.head(species, a: centreA, t: centreT, n: n)
                    fromPixel = RealSnakePattern.head(species, a: pixelA, t: pixelT, n: n)
                } else {
                    fromCentre = RealSnakePattern.body(species, a: centreA, t: centreT, n: n)
                    fromPixel = RealSnakePattern.body(species, a: pixelA, t: pixelT, n: n)
                }
                let mixed: SIMD3<Float> = fromCentre * 0.8 + fromPixel * 0.2
                let crevice: Float = 1 - 0.20 * RealSnakeMath.smoothstep(0.7, 1.0, lattice.edge[idx])
                let shade: Float = (0.80 + 0.20 * lattice.heightField[idx]) * crevice
                let variation: Float = 0.92 + 0.16 * n
                let warmth: Float = 0.05 * (RealSnakeMath.hash(Int(n * 65535), 5) - 0.5)
                let tint = SIMD3<Float>(1 + warmth, 1, 1 - warmth)
                let colour: SIMD3<Float> = mixed * tint * (shade * variation)
                let o = idx * 4
                pixels[o] = RealSnakeMath.byte(colour.x)
                pixels[o + 1] = RealSnakeMath.byte(colour.y)
                pixels[o + 2] = RealSnakeMath.byte(colour.z)
                pixels[o + 3] = 255
            }
        }
        return image(width: w, height: h, rgba: pixels, space: sRGBSpace, alphaInfo: .noneSkipLast)
    }

    /// Soft dark falloff across u (black, premultiplied alpha), for the
    /// contact-shadow ribbon.
    static func contactShadowImage() -> UIImage? {
        let w = 64
        let h = 4
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let u = (Float(x) + 0.5) / Float(w)
                let distance = abs(u - 0.5)
                let alpha: Float = 0.62 * (1 - RealSnakeMath.smoothstep(0.16, 0.5, distance))
                let o = (y * w + x) * 4
                pixels[o] = 0
                pixels[o + 1] = 0
                pixels[o + 2] = 0
                pixels[o + 3] = RealSnakeMath.byte(alpha)
            }
        }
        return image(width: w, height: h, rgba: pixels, space: sRGBSpace, alphaInfo: .premultipliedLast)
    }
}

// MARK: - Materials (shared per species)

/// Every material one snake needs. One instance per species, shared by all
/// snakes of that species; the eye/mouth/tongue/shadow materials that do
/// not vary are shared across species too.
@MainActor
final class RealSnakeSkin {
    let bodyMaterial: SCNMaterial
    let headMaterial: SCNMaterial
    let mouthMaterial: SCNMaterial
    let eyeMaterial: SCNMaterial
    let pupilMaterial: SCNMaterial
    let catchlightMaterial: SCNMaterial
    let tongueMaterial: SCNMaterial
    let fangMaterial: SCNMaterial
    let contactShadowMaterial: SCNMaterial

    init(bodyMaterial: SCNMaterial, headMaterial: SCNMaterial, mouthMaterial: SCNMaterial,
         eyeMaterial: SCNMaterial, pupilMaterial: SCNMaterial, catchlightMaterial: SCNMaterial,
         tongueMaterial: SCNMaterial, fangMaterial: SCNMaterial, contactShadowMaterial: SCNMaterial) {
        self.bodyMaterial = bodyMaterial
        self.headMaterial = headMaterial
        self.mouthMaterial = mouthMaterial
        self.eyeMaterial = eyeMaterial
        self.pupilMaterial = pupilMaterial
        self.catchlightMaterial = catchlightMaterial
        self.tongueMaterial = tongueMaterial
        self.fangMaterial = fangMaterial
        self.contactShadowMaterial = contactShadowMaterial
    }
}

/// Main-actor caches: the scale lattice and the shared normal/roughness
/// maps are built on first use, each species' skin on first request.
@MainActor
enum RealSnakeAssets {
    private static var lattice: RealSnakeLattice?
    private static var sharedMapsBuilt = false
    private static var normalMap: UIImage?
    private static var roughnessMap: UIImage?
    private static var skins: [RealSnakeSpecies: RealSnakeSkin] = [:]
    private static var mouthCache: SCNMaterial?
    private static var pupilCache: SCNMaterial?
    private static var catchlightCache: SCNMaterial?
    private static var fangCache: SCNMaterial?
    private static var shadowCache: SCNMaterial?
    private static var tongueCache: [RealSnakeSpecies: SCNMaterial] = [:]

    static func skin(for species: RealSnakeSpecies) -> RealSnakeSkin {
        if let cached = skins[species] { return cached }

        let latticeValue: RealSnakeLattice
        if let existing = lattice {
            latticeValue = existing
        } else {
            let built = RealSnakeLattice()
            lattice = built
            latticeValue = built
        }
        if !sharedMapsBuilt {
            normalMap = RealSnakeTextures.normalMap(from: latticeValue)
            roughnessMap = RealSnakeTextures.roughnessMap(from: latticeValue)
            sharedMapsBuilt = true
        }

        let bodyAlbedo = RealSnakeTextures.albedo(species: species, lattice: latticeValue, head: false)
        let headAlbedo = RealSnakeTextures.albedo(species: species, lattice: latticeValue, head: true)
        let headScale = Float(RealSnakeLattice.headPixelRows) / Float(RealSnakeLattice.height)
        let skin = RealSnakeSkin(
            bodyMaterial: scaledSkinMaterial(albedo: bodyAlbedo, fallback: species.fallbackColor, vScale: 1),
            headMaterial: scaledSkinMaterial(albedo: headAlbedo, fallback: species.fallbackColor, vScale: headScale),
            mouthMaterial: mouthMaterial(),
            eyeMaterial: eyeMaterial(species),
            pupilMaterial: pupilMaterial(),
            catchlightMaterial: catchlightMaterial(),
            tongueMaterial: tongueMaterial(species),
            fangMaterial: fangMaterial(),
            contactShadowMaterial: contactShadowMaterial()
        )
        skins[species] = skin
        // Every species built: the lattice's working arrays can go.
        if skins.count == RealSnakeSpecies.allCases.count {
            lattice = nil
        }
        return skin
    }

    /// The scaly skin: PBR albedo + shared normal and roughness maps and a
    /// thin clear coat. `vScale` maps the head's 0...1 v range onto the
    /// first 256 rows of the shared maps, matching its albedo.
    private static func scaledSkinMaterial(albedo: UIImage?, fallback: UIColor, vScale: Float) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        if let albedo {
            m.diffuse.contents = albedo
        } else {
            m.diffuse.contents = fallback
        }
        if let normals = normalMap {
            m.normal.contents = normals
            m.normal.intensity = 0.85
        }
        if let roughness = roughnessMap {
            m.roughness.contents = roughness
        } else {
            m.roughness.contents = NSNumber(value: 0.45)
        }
        m.metalness.contents = NSNumber(value: 0.0)
        m.clearCoat.contents = NSNumber(value: 0.22)
        m.clearCoatRoughness.contents = NSNumber(value: 0.28)
        for property in [m.diffuse, m.normal, m.roughness] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.minificationFilter = .linear
            property.magnificationFilter = .linear
            property.mipFilter = .linear
        }
        if vScale != 1 {
            let transform = SCNMatrix4MakeScale(1, vScale, 1)
            m.normal.contentsTransform = transform
            m.roughness.contentsTransform = transform
        }
        return m
    }

    private static func plainMaterial(_ color: UIColor, roughness: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: 0.0)
        return m
    }

    private static func mouthMaterial() -> SCNMaterial {
        if let cached = mouthCache { return cached }
        let m = plainMaterial(UIColor(red: 0.80, green: 0.45, blue: 0.48, alpha: 1), roughness: 0.35)
        m.clearCoat.contents = NSNumber(value: 0.3)
        mouthCache = m
        return m
    }

    /// Dark, very glossy eyeball: low roughness plus a full clear coat for
    /// a crisp specular highlight.
    private static func eyeMaterial(_ species: RealSnakeSpecies) -> SCNMaterial {
        let m = plainMaterial(species.irisColor, roughness: 0.08)
        m.clearCoat.contents = NSNumber(value: 1.0)
        m.clearCoatRoughness.contents = NSNumber(value: 0.03)
        return m
    }

    private static func pupilMaterial() -> SCNMaterial {
        if let cached = pupilCache { return cached }
        let m = plainMaterial(UIColor(white: 0.01, alpha: 1), roughness: 0.05)
        pupilCache = m
        return m
    }

    /// A tiny always-lit glint so the eyes read as wet even when the key
    /// light's highlight falls elsewhere.
    private static func catchlightMaterial() -> SCNMaterial {
        if let cached = catchlightCache { return cached }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor(white: 0.92, alpha: 1)
        catchlightCache = m
        return m
    }

    private static func tongueMaterial(_ species: RealSnakeSpecies) -> SCNMaterial {
        if let cached = tongueCache[species] { return cached }
        let m = plainMaterial(species.tongueColor, roughness: 0.3)
        tongueCache[species] = m
        return m
    }

    private static func fangMaterial() -> SCNMaterial {
        if let cached = fangCache { return cached }
        let m = plainMaterial(UIColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1), roughness: 0.25)
        fangCache = m
        return m
    }

    private static func contactShadowMaterial() -> SCNMaterial {
        if let cached = shadowCache { return cached }
        let m = SCNMaterial()
        m.lightingModel = .constant
        if let image = RealSnakeTextures.contactShadowImage() {
            m.diffuse.contents = image
        } else {
            m.diffuse.contents = UIColor(white: 0, alpha: 0.35)
        }
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = false
        shadowCache = m
        return m
    }
}
