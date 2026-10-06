import SwiftUI

// The TV app's *shell* design system: the screens around the games (game
// selection, lobby, results). Game boards have their own kit in TVTheme.swift;
// every type here is prefixed `Shell` so the two can never collide.
//
// Everything is plain SwiftUI available on tvOS 17 -- gradients, Canvas,
// TimelineView, KeyframeAnimator, PhaseAnimator -- with no image assets and no
// Metal shader library. (A `.metal` file would need Xcode 26's separately
// downloaded Metal toolchain on CI, so the holographic shine below is a
// gradient band swept across the content instead.)

// MARK: - Tokens

enum ShellTheme {
    static let ink = Color(hex: "07051A")
    static let night = Color(hex: "140A33")
    static let deepBlue = Color(hex: "0A1238")
    static let violet = Color(hex: "7C3AED")
    static let cyan = Color(hex: "22D3EE")
    static let pink = Color(hex: "EC4899")
    static let blue = Color(hex: "2563EB")
    static let gold = Color(hex: "FACC15")
    static let mint = Color(hex: "34D399")
    static let orange = Color(hex: "FB923C")
    static let panel = Color(hex: "120C2C")

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.45)

    static let brandGradient = LinearGradient(
        colors: [Color(hex: "22D3EE"), Color(hex: "7C3AED"), Color(hex: "EC4899")],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Big rounded display type -- the "toy-like" Swift Playgrounds voice.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }

    /// Small all-caps label above a heading. Pair with `.tracking(4...6)`.
    static func eyebrow(_ size: CGFloat = 22) -> Font {
        Font.system(size: size, weight: .bold, design: .rounded)
    }

    static let avatarPalette: [Color] = [
        Color(hex: "F43F5E"), Color(hex: "F97316"), Color(hex: "EAB308"),
        Color(hex: "22C55E"), Color(hex: "14B8A6"), Color(hex: "06B6D4"),
        Color(hex: "3B82F6"), Color(hex: "6366F1"), Color(hex: "A855F7"),
        Color(hex: "EC4899")
    ]

    static let confettiColors: [Color] = [
        Color(hex: "FACC15"), Color(hex: "22D3EE"), Color(hex: "EC4899"),
        Color(hex: "A855F7"), Color(hex: "34D399"), Color(hex: "FB923C"),
        Color.white
    ]

    /// Same player id -> same colour on every launch and every screen.
    /// `String.hashValue` is randomly seeded per process, so this is FNV-1a.
    static func avatarColor(for id: String) -> Color {
        let palette: [Color] = avatarPalette
        guard !palette.isEmpty else { return violet }
        let index: Int = Int(stableHash(id) % UInt32(palette.count))
        return palette[index]
    }

    static func stableHash(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash
    }

    /// "Teja Makkena" -> "TM", "Sam" -> "S", "" -> "?".
    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
        var result: String = ""
        for word in words.prefix(2) {
            if let first = word.first {
                result.append(first)
            }
        }
        if result.isEmpty {
            return "?"
        }
        return result.uppercased()
    }

    /// Deterministic 0..<1 pseudo-random value, for particles that must not
    /// reshuffle every frame.
    static func noise(_ index: Int, _ salt: Int) -> Double {
        let seed: Double = Double(index) * 12.9898 + Double(salt) * 78.233
        let value: Double = sin(seed) * 43_758.5453
        return value - floor(value)
    }
}

// MARK: - Ambient background

/// Slowly drifting colour blobs over a deep gradient, with a faint perspective
/// floor grid for depth. tvOS 17 has no MeshGradient, so this is one Canvas
/// redrawn by a TimelineView -- a handful of radial-gradient fills per frame,
/// no blur. `isAnimated: false` freezes it on one frame (used behind game
/// boards, which draw their own backgrounds).
struct ShellAmbientBackground: View {
    var isAnimated: Bool = true
    var showsFloor: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimated)) { context in
            ShellAmbientCanvas(time: context.date.timeIntervalSinceReferenceDate,
                               showsFloor: showsFloor)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ShellAmbientCanvas: View {
    let time: Double
    let showsFloor: Bool

    var body: some View {
        Canvas { context, size in
            ShellAmbientPainter.paint(&context, size: size, time: time, showsFloor: showsFloor)
        }
    }
}

enum ShellAmbientPainter {
    struct Blob {
        let color: Color
        let x: CGFloat
        let y: CGFloat
        let radius: CGFloat
        let driftX: CGFloat
        let driftY: CGFloat
        let speed: CGFloat
        let phase: CGFloat
    }

    static let blobs: [Blob] = [
        Blob(color: Color(hex: "7C3AED"), x: 0.18, y: 0.22, radius: 0.42, driftX: 0.10, driftY: 0.08, speed: 0.11, phase: 0.0),
        Blob(color: Color(hex: "06B6D4"), x: 0.82, y: 0.20, radius: 0.36, driftX: 0.08, driftY: 0.10, speed: 0.09, phase: 1.7),
        Blob(color: Color(hex: "EC4899"), x: 0.70, y: 0.78, radius: 0.38, driftX: 0.12, driftY: 0.06, speed: 0.07, phase: 3.1),
        Blob(color: Color(hex: "2563EB"), x: 0.28, y: 0.80, radius: 0.34, driftX: 0.09, driftY: 0.07, speed: 0.13, phase: 4.4),
        Blob(color: Color(hex: "A855F7"), x: 0.52, y: 0.45, radius: 0.26, driftX: 0.14, driftY: 0.09, speed: 0.06, phase: 5.2)
    ]

    static func paint(_ context: inout GraphicsContext, size: CGSize, time: Double, showsFloor: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        let base = Gradient(colors: [ShellTheme.ink, ShellTheme.night, ShellTheme.deepBlue])
        context.fill(Path(rect),
                     with: .linearGradient(base,
                                           startPoint: CGPoint(x: 0, y: 0),
                                           endPoint: CGPoint(x: size.width, y: size.height)))

        // Keep the argument to sin/cos small so precision never degrades.
        let t: CGFloat = CGFloat(time.truncatingRemainder(dividingBy: 20_000))
        let unit: CGFloat = max(size.width, size.height)
        for blob in blobs {
            paintBlob(&context, blob: blob, size: size, unit: unit, t: t)
        }

        if showsFloor {
            paintFloor(&context, size: size, t: t)
        }

        let vignette = Gradient(colors: [Color.clear, Color.black.opacity(0.55)])
        context.fill(Path(rect),
                     with: .radialGradient(vignette,
                                           center: CGPoint(x: size.width / 2, y: size.height / 2),
                                           startRadius: size.height * 0.45,
                                           endRadius: size.width * 0.78))
    }

    private static func paintBlob(_ context: inout GraphicsContext, blob: Blob,
                                  size: CGSize, unit: CGFloat, t: CGFloat) {
        let wobbleX: CGFloat = blob.driftX * sin(t * blob.speed + blob.phase)
        let wobbleY: CGFloat = blob.driftY * cos(t * blob.speed * 0.8 + blob.phase)
        let cx: CGFloat = (blob.x + wobbleX) * size.width
        let cy: CGFloat = (blob.y + wobbleY) * size.height
        let breathe: CGFloat = 1 + 0.08 * sin(t * blob.speed * 1.3 + blob.phase)
        let radius: CGFloat = blob.radius * unit * breathe
        let circle = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        let gradient = Gradient(colors: [blob.color.opacity(0.5),
                                         blob.color.opacity(0.16),
                                         blob.color.opacity(0)])
        context.fill(Path(ellipseIn: circle),
                     with: .radialGradient(gradient,
                                           center: CGPoint(x: cx, y: cy),
                                           startRadius: 0,
                                           endRadius: radius))
    }

    /// A Tron-style floor receding to a horizon: converging rails plus
    /// cross lines that slowly scroll toward the viewer.
    private static func paintFloor(_ context: inout GraphicsContext, size: CGSize, t: CGFloat) {
        let horizon: CGFloat = size.height * 0.64
        let depth: CGFloat = size.height - horizon
        let centerX: CGFloat = size.width / 2
        var path = Path()

        let rails: Int = 14
        for i in -rails...rails {
            let spread: CGFloat = CGFloat(i)
            path.move(to: CGPoint(x: centerX + spread * size.width * 0.012, y: horizon))
            path.addLine(to: CGPoint(x: centerX + spread * size.width * 0.11, y: size.height))
        }

        let crossCount: Int = 12
        let scroll: CGFloat = (t * 0.12).truncatingRemainder(dividingBy: 1)
        for i in 0..<crossCount {
            let f: CGFloat = (CGFloat(i) + scroll) / CGFloat(crossCount)
            let y: CGFloat = horizon + depth * f * f
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        let fade = Gradient(colors: [ShellTheme.cyan.opacity(0), ShellTheme.cyan.opacity(0.16)])
        context.stroke(path,
                       with: .linearGradient(fade,
                                             startPoint: CGPoint(x: 0, y: horizon),
                                             endPoint: CGPoint(x: 0, y: size.height)),
                       lineWidth: 1.5)
    }
}

// MARK: - Glass

/// The frosted-panel look without a system Material: a Material follows the
/// user's light/dark appearance (white on a light-mode Apple TV) and re-blurs
/// the animated background every frame. This is a tinted translucent fill,
/// a top-left sheen and a light-catching rim, plus layered shadows for lift.
struct ShellGlassSurface: View {
    var cornerRadius: CGFloat = 36
    var tint: Color = ShellTheme.cyan

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(ShellTheme.panel.opacity(0.62))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.02)],
                                      startPoint: .topLeading,
                                      endPoint: .bottomTrailing))
            shape.fill(RadialGradient(colors: [tint.opacity(0.22), Color.clear],
                                      center: .topLeading,
                                      startRadius: 0,
                                      endRadius: 560))
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45),
                                                       Color.white.opacity(0.06),
                                                       tint.opacity(0.35)],
                                              startPoint: .topLeading,
                                              endPoint: .bottomTrailing),
                               lineWidth: 1.5)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.45), radius: 36, x: 0, y: 24)
        .shadow(color: tint.opacity(0.14), radius: 30, x: 0, y: 0)
    }
}

struct ShellGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color
    let padding: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 36,
         tint: Color = ShellTheme.cyan,
         padding: CGFloat = 40,
         @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                ShellGlassSurface(cornerRadius: cornerRadius, tint: tint)
            }
    }
}

/// Small rounded info chip ("2-10 players", "Remote ready").
struct ShellChip: View {
    let systemImage: String
    let text: String
    var tint: Color = ShellTheme.cyan

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
            Text(text)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule().fill(tint.opacity(0.14))
        }
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
    }
}

// MARK: - 3D icon orb

/// A glossy, slightly extruded disc holding an SF Symbol: a darker base
/// offset below the face for thickness, a specular highlight top-left and a
/// light-catching rim.
struct ShellIconOrb: View {
    let symbol: String
    let top: Color
    let bottom: Color
    let accent: Color
    var size: CGFloat = 110
    var isLit: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.38))
                .offset(y: size * 0.07)
            Circle()
                .fill(LinearGradient(colors: [top, bottom],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                                     center: UnitPoint(x: 0.3, y: 0.24),
                                     startRadius: 0,
                                     endRadius: size * 0.56))
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.06)],
                                             startPoint: .top,
                                             endPoint: .bottom),
                              lineWidth: max(1.5, size * 0.02))
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: size * 0.03)
                .shadow(color: accent.opacity(isLit ? 0.9 : 0), radius: size * 0.12)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Avatar token

/// A player as a glossy coloured token with their initials. The colour is
/// derived from the player id, so it is stable across screens and launches.
struct ShellAvatarToken: View {
    let id: String
    let name: String
    var size: CGFloat = 96
    var isHost: Bool = false
    var isBot: Bool = false
    var isReady: Bool = false

    private var color: Color { ShellTheme.avatarColor(for: id) }

    var body: some View {
        ZStack {
            // Thickness: a darker copy of the disc peeking out underneath.
            Circle()
                .fill(color)
                .overlay { Circle().fill(Color.black.opacity(0.45)) }
                .offset(y: size * 0.07)
            Circle()
                .fill(color)
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.6), Color.white.opacity(0)],
                                     center: UnitPoint(x: 0.32, y: 0.24),
                                     startRadius: 0,
                                     endRadius: size * 0.62))
            Circle()
                .fill(LinearGradient(colors: [Color.clear, Color.black.opacity(0.28)],
                                     startPoint: .center,
                                     endPoint: .bottom))
            Circle()
                .strokeBorder(Color.white.opacity(0.45), lineWidth: max(1.5, size * 0.025))
            Text(ShellTheme.initials(for: name))
                .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 2)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) {
            if isHost {
                Image(systemName: "crown.fill")
                    .font(.system(size: size * 0.24, weight: .bold))
                    .foregroundColor(ShellTheme.gold)
                    .shadow(color: ShellTheme.gold.opacity(0.7), radius: 6)
                    .offset(y: -size * 0.24)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isBot {
                ShellTokenBadge(systemImage: "cpu", color: ShellTheme.orange, size: size * 0.32)
            } else if isReady {
                ShellTokenBadge(systemImage: "checkmark", color: ShellTheme.mint, size: size * 0.32)
            }
        }
        .compositingGroup()
        .shadow(color: color.opacity(0.45), radius: size * 0.18, x: 0, y: 0)
        .shadow(color: Color.black.opacity(0.4), radius: size * 0.08, x: 0, y: size * 0.1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

private struct ShellTokenBadge: View {
    let systemImage: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background { Circle().fill(color) }
            .overlay { Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2) }
    }
}

/// An open seat: a dashed ring that slowly breathes.
struct ShellGhostToken: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.04))
            Circle()
                .strokeBorder(Color.white.opacity(0.28),
                              style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.18))
        }
        .frame(width: size, height: size)
        .phaseAnimator([false, true]) { content, phase in
            content
                .scaleEffect(phase ? 1.0 : 0.92)
                .opacity(phase ? 0.9 : 0.5)
        } animation: { _ in
            Animation.easeInOut(duration: 1.4)
        }
    }
}

// MARK: - Hop (KeyframeAnimator)

/// Values a hop animates: lift, plus squash/stretch around the base.
struct ShellHopValues {
    var lift: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
}

extension View {
    /// Anticipate (squash), jump (stretch), land (squash), settle (spring).
    /// Plays every time `trigger` changes; starts and ends at identity, so a
    /// view at rest is never transformed.
    func shellHop(trigger: Int, height: CGFloat = 40) -> some View {
        keyframeAnimator(initialValue: ShellHopValues(), trigger: trigger) { content, value in
            content
                .scaleEffect(x: value.scaleX, y: value.scaleY, anchor: .bottom)
                .offset(y: value.lift)
        } keyframes: { _ in
            KeyframeTrack(\ShellHopValues.lift) {
                CubicKeyframe(0, duration: 0.08)
                CubicKeyframe(-height, duration: 0.22)
                CubicKeyframe(0, duration: 0.18)
                SpringKeyframe(-height * 0.2, duration: 0.14, spring: .snappy)
                SpringKeyframe(0, duration: 0.3, spring: .bouncy)
            }
            KeyframeTrack(\ShellHopValues.scaleX) {
                CubicKeyframe(1.14, duration: 0.08)
                CubicKeyframe(0.9, duration: 0.22)
                CubicKeyframe(1.0, duration: 0.14)
                CubicKeyframe(1.18, duration: 0.07)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
            KeyframeTrack(\ShellHopValues.scaleY) {
                CubicKeyframe(0.86, duration: 0.08)
                CubicKeyframe(1.12, duration: 0.22)
                CubicKeyframe(1.0, duration: 0.14)
                CubicKeyframe(0.8, duration: 0.07)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
        }
    }

    /// Pops a view in after `delay` and hops it once -- used for players
    /// arriving in the lobby.
    func shellHopIn(delay: Double = 0, height: CGFloat = 60) -> some View {
        modifier(ShellHopInModifier(delay: delay, height: height))
    }

    /// Sweeps a holographic shine band across the view while `isActive`.
    func shellShine(isActive: Bool, cornerRadius: CGFloat = 24,
                    period: Double = 2.8, intensity: Double = 0.35) -> some View {
        modifier(ShellShine(isActive: isActive, cornerRadius: cornerRadius,
                            period: period, intensity: intensity))
    }
}

struct ShellHopInModifier: ViewModifier {
    let delay: Double
    let height: CGFloat

    @State private var isShown: Bool = false
    @State private var hopCount: Int = 0

    func body(content: Content) -> some View {
        content
            .shellHop(trigger: hopCount, height: height)
            .scaleEffect(isShown ? 1.0 : 0.3, anchor: .bottom)
            .opacity(isShown ? 1.0 : 0.0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                        isShown = true
                    }
                    hopCount += 1
                }
            }
    }
}

// MARK: - Shine

/// A holographic band (cyan -> white -> pink) that sweeps across the content
/// and then rests offscreen for the remainder of `period`. Built only while
/// active, so an idle view carries no extra layer and no timeline.
struct ShellShine: ViewModifier {
    let isActive: Bool
    var cornerRadius: CGFloat = 24
    var period: Double = 2.8
    var intensity: Double = 0.35

    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                ShellShineBand(period: period, intensity: intensity)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct ShellShineBand: View {
    let period: Double
    let intensity: Double

    @State private var startDate: Date = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { context in
                ShellShineStripe(intensity: intensity)
                    .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 1.8)
                    .rotationEffect(.degrees(18))
                    .position(x: ShellShineBand.xPosition(date: context.date,
                                                          start: startDate,
                                                          period: period,
                                                          width: proxy.size.width),
                              y: proxy.size.height / 2)
            }
        }
        .onAppear { startDate = Date() }
    }

    /// Sweeps left-to-right during the first 55% of each period, then waits
    /// offscreen, so the loop restart is never visible.
    static func xPosition(date: Date, start: Date, period: Double, width: CGFloat) -> CGFloat {
        guard period > 0 else { return -width }
        let elapsed: Double = max(0, date.timeIntervalSince(start))
        let progress: Double = elapsed.truncatingRemainder(dividingBy: period) / period
        let sweep: CGFloat = CGFloat(min(1.0, progress / 0.55))
        return -width * 0.5 + sweep * width * 2.0
    }
}

private struct ShellShineStripe: View {
    let intensity: Double

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0), location: 0.0),
                .init(color: ShellTheme.cyan.opacity(intensity * 0.45), location: 0.3),
                .init(color: Color.white.opacity(intensity), location: 0.5),
                .init(color: ShellTheme.pink.opacity(intensity * 0.4), location: 0.7),
                .init(color: Color.white.opacity(0), location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .blendMode(.plusLighter)
    }
}

// MARK: - Confetti

/// One-shot confetti burst: deterministic particles drawn in a single Canvas
/// with simple ballistic motion, spin and a paper "flip". Removes its own
/// timeline once the burst is over.
struct ShellConfetti: View {
    var particleCount: Int = 140
    var duration: Double = 5.0
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.4)
    var seed: Int = 7

    @State private var startDate: Date = Date()
    @State private var isFinished: Bool = false

    var body: some View {
        ZStack {
            if !isFinished {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        ShellConfettiPainter.paint(&context,
                                                   size: size,
                                                   elapsed: timeline.date.timeIntervalSince(startDate),
                                                   count: particleCount,
                                                   duration: duration,
                                                   origin: origin,
                                                   seed: seed)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { startDate = Date() }
        .task {
            let nanos: UInt64 = UInt64(max(0.5, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            isFinished = true
        }
    }
}

enum ShellConfettiPainter {
    static func paint(_ context: inout GraphicsContext, size: CGSize, elapsed: Double,
                      count: Int, duration: Double, origin: UnitPoint, seed: Int) {
        guard elapsed >= 0, elapsed < duration, count > 0 else { return }
        let colors: [Color] = ShellTheme.confettiColors
        guard !colors.isEmpty else { return }

        let originX: Double = Double(size.width * origin.x)
        let originY: Double = Double(size.height * origin.y)
        let gravity: Double = 620
        let fade: Double = min(1.0, max(0.0, (duration - elapsed) / 1.2))

        for i in 0..<count {
            let r1: Double = ShellTheme.noise(i, seed)
            let r2: Double = ShellTheme.noise(i, seed + 1)
            let r3: Double = ShellTheme.noise(i, seed + 2)
            let r4: Double = ShellTheme.noise(i, seed + 3)
            let r5: Double = ShellTheme.noise(i, seed + 4)

            let t: Double = elapsed - r5 * 0.25
            if t <= 0 { continue }

            let angle: Double = -Double.pi / 2 + (r1 - 0.5) * Double.pi * 1.15
            let speed: Double = 700 + r2 * 900
            // Air drag: the burst decelerates quickly, then gravity takes over.
            let travel: Double = (1 - exp(-2.2 * t)) / 2.2
            let sway: Double = sin(t * (3 + r3 * 4) + r4 * 6) * 22
            let x: Double = originX + cos(angle) * speed * travel + sway
            let y: Double = originY + sin(angle) * speed * travel + 0.5 * gravity * t * t
            if y > Double(size.height) + 60 { continue }

            let width: CGFloat = CGFloat(10 + r3 * 12)
            let height: CGFloat = CGFloat(6 + r4 * 8)
            let spin: Double = t * (3 + r2 * 7) + r1 * 6
            let flip: Double = cos(t * (5 + r5 * 6) + r3 * 3)
            let colorIndex: Int = Int(r4 * Double(colors.count)) % colors.count

            var piece = context
            piece.opacity = fade
            piece.translateBy(x: CGFloat(x), y: CGFloat(y))
            piece.rotate(by: Angle(radians: spin))
            piece.scaleBy(x: CGFloat(max(0.15, abs(flip))), y: 1)
            let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            if i % 3 == 0 {
                piece.fill(Path(ellipseIn: rect), with: .color(colors[colorIndex]))
            } else {
                piece.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(colors[colorIndex]))
            }
        }
    }
}

// MARK: - Button styles

/// The one big call to action on a screen (Start Game, Play Again): a solid
/// gradient slab that lifts, glows and shines when focused. Reads focus from
/// the environment, so it draws its own focus state with no system chrome.
struct ShellPrimaryButtonStyle: ButtonStyle {
    var tint: Color = ShellTheme.cyan

    func makeBody(configuration: Configuration) -> some View {
        ShellPrimaryButtonBody(configuration: configuration, tint: tint)
    }
}

private struct ShellPrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color

    @Environment(\.isFocused) private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    var body: some View {
        configuration.label
            .font(ShellTheme.display(32, weight: .bold))
            .foregroundColor(isEnabled ? Color.black : Color.white.opacity(0.55))
            .padding(.horizontal, 52)
            .padding(.vertical, 24)
            .frame(minWidth: 380)
            .background { surface }
            .shellShine(isActive: isFocused && isEnabled, cornerRadius: 24, period: 2.4, intensity: 0.5)
            .compositingGroup()
            .shadow(color: tint.opacity(isEnabled ? (isFocused ? 0.7 : 0.3) : 0),
                    radius: isFocused ? 34 : 14, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.45),
                    radius: isFocused ? 22 : 10, x: 0, y: isFocused ? 18 : 8)
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1.0))
            .offset(y: isFocused ? -4 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isFocused)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private var surface: some View {
        if isEnabled {
            ZStack {
                shape.fill(tint)
                    .overlay { shape.fill(Color.black.opacity(0.4)) }
                    .offset(y: 6)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.95), tint],
                                          startPoint: .top,
                                          endPoint: .bottom))
                    .overlay { shape.fill(tint.opacity(isFocused ? 0.15 : 0.45)) }
                shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
            }
        } else {
            ShellGlassSurface(cornerRadius: 24, tint: tint)
        }
    }
}

/// Secondary actions: a glass capsule that turns solid white when focused,
/// matching the tvOS convention of a focused control going bright.
struct ShellGlassButtonStyle: ButtonStyle {
    var tint: Color = ShellTheme.cyan
    var fontSize: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        ShellGlassButtonBody(configuration: configuration, tint: tint, fontSize: fontSize)
    }
}

private struct ShellGlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let fontSize: CGFloat

    @Environment(\.isFocused) private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    var body: some View {
        configuration.label
            .font(ShellTheme.display(fontSize, weight: .semibold))
            .foregroundColor(isFocused ? Color.black : Color.white.opacity(isEnabled ? 0.85 : 0.35))
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background {
                ZStack {
                    Capsule().fill(Color.white.opacity(isFocused ? 0.95 : 0.08))
                    Capsule().strokeBorder(Color.white.opacity(isFocused ? 0 : 0.22), lineWidth: 1.2)
                }
            }
            .compositingGroup()
            .shadow(color: tint.opacity(isFocused ? 0.55 : 0), radius: 22, x: 0, y: 0)
            .shadow(color: Color.black.opacity(isFocused ? 0.4 : 0), radius: 14, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.07 : 1.0))
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isFocused)
    }
}

/// Sidebar category pill: filled with its category accent when selected,
/// lifted and bright when focused.
struct ShellPillButtonStyle: ButtonStyle {
    let accent: Color
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ShellPillButtonBody(configuration: configuration, accent: accent, isSelected: isSelected)
    }
}

private struct ShellPillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let accent: Color
    let isSelected: Bool

    @Environment(\.isFocused) private var isFocused: Bool

    private var textColor: Color {
        if isFocused || isSelected { return Color.black }
        return Color.white.opacity(0.75)
    }

    private var fill: Color {
        if isFocused { return Color.white }
        if isSelected { return accent }
        return Color.white.opacity(0.07)
    }

    var body: some View {
        configuration.label
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundColor(textColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background { Capsule().fill(fill) }
            .overlay {
                Capsule().strokeBorder(accent.opacity(isSelected && !isFocused ? 0.9 : 0), lineWidth: 1.5)
            }
            .compositingGroup()
            .shadow(color: accent.opacity(isFocused ? 0.7 : (isSelected ? 0.35 : 0)),
                    radius: isFocused ? 18 : 10, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.08 : 1.0), anchor: .leading)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isFocused)
    }
}
