import SwiftUI

/// A small shared visual kit for the TV boards: design tokens, an animated
/// backdrop, frosted glass cards, particle bursts, glowing text, a popping
/// score counter, a 3D card flip and the winner banner.
///
/// Everything here is plain SwiftUI available on tvOS 17 (no MeshGradient,
/// no SceneKit), drawn mostly through Canvas so a full-screen backdrop or a
/// burst of a hundred particles costs one layer, not a hundred views.

// MARK: - Tokens

/// One board's colour story: three deep backdrop stops, three slowly
/// drifting glow blobs, and two accents for text and highlights.
///
/// These seven moods are deliberately the TV's own -- a lit room's backdrop
/// has no counterpart on a phone held at arm's length -- so their hexes are
/// not expected to match `PhonePlayDesign`. Everything a board draws *on
/// top* of a mood (text, chips, cards, win/lose colour) comes from the
/// shared tokens in `TVTheme` below.
struct TVPalette {
    let background: [Color]
    let blobs: [Color]
    let accent: Color
    let accent2: Color
}

enum TVTheme {
    static let aurora = TVPalette(
        background: [Color(hex: "070a1f"), Color(hex: "140a33"), Color(hex: "03050d")],
        blobs: [Color(hex: "7c3aed"), Color(hex: "0891b2"), Color(hex: "db2777")],
        accent: Color(hex: "67e8f9"), accent2: Color(hex: "f472b6"))

    static let neon = TVPalette(
        background: [Color(hex: "04020f"), Color(hex: "12052b"), Color(hex: "020617")],
        blobs: [Color(hex: "2563eb"), Color(hex: "c026d3"), Color(hex: "0d9488")],
        accent: Color(hex: "22d3ee"), accent2: Color(hex: "f472b6"))

    static let ice = TVPalette(
        background: [Color(hex: "020b1a"), Color(hex: "06213f"), Color(hex: "01060f")],
        blobs: [Color(hex: "0284c7"), Color(hex: "1d4ed8"), Color(hex: "0e7490")],
        accent: Color(hex: "7dd3fc"), accent2: Color(hex: "fb7185"))

    static let ember = TVPalette(
        background: [Color(hex: "140904"), Color(hex: "2a0f05"), Color(hex: "080302")],
        blobs: [Color(hex: "b45309"), Color(hex: "be123c"), Color(hex: "7c2d12")],
        accent: Color(hex: "fbbf24"), accent2: Color(hex: "fb7185"))

    static let ocean = TVPalette(
        background: [Color(hex: "020617"), Color(hex: "06243d"), Color(hex: "010812")],
        blobs: [Color(hex: "0369a1"), Color(hex: "0f766e"), Color(hex: "1e3a8a")],
        accent: Color(hex: "38bdf8"), accent2: Color(hex: "f97316"))

    static let jungle = TVPalette(
        background: [Color(hex: "03140f"), Color(hex: "062a24"), Color(hex: "020b08")],
        blobs: [Color(hex: "059669"), Color(hex: "0891b2"), Color(hex: "65a30d")],
        accent: Color(hex: "6ee7b7"), accent2: Color(hex: "fde047"))

    static let festival = TVPalette(
        background: [Color(hex: "0b0620"), Color(hex: "1e0b3a"), Color(hex: "05030f")],
        blobs: [Color(hex: "9333ea"), Color(hex: "e11d48"), Color(hex: "2563eb")],
        accent: Color(hex: "f0abfc"), accent2: Color(hex: "fde047"))

    // MARK: Shared palette
    //
    // One palette for the whole product: these all forward to `ShellTheme`,
    // whose hexes are the same ones `PhonePlayDesign` uses on the phone. A
    // board reaches for a name here instead of a raw SwiftUI colour, so
    // "red" means the same red on the TV and in your hand.

    static let bg = ShellTheme.ink
    static let surface = ShellTheme.panel
    static let surface2 = ShellTheme.panel2

    static let green = ShellTheme.green
    static let cyan = ShellTheme.cyan
    static let yellow = ShellTheme.yellow
    static let purple = ShellTheme.purple
    static let orange = ShellTheme.orange
    static let red = ShellTheme.red
    static let pink = ShellTheme.pink
    static let blue = ShellTheme.blue
    static let indigo = ShellTheme.indigo
    static let violet = ShellTheme.violet

    static let gold = ShellTheme.gold
    static let danger = ShellTheme.red
    static let success = ShellTheme.green
    static let textSecondary = ShellTheme.textSecondary
    static let textTertiary = ShellTheme.textTertiary
    static let text2 = ShellTheme.text2
    static let text3 = ShellTheme.text3

    static let cardRadius: CGFloat = ShellTheme.cardRadius
    static let buttonRadius: CGFloat = ShellTheme.buttonRadius

    static let confetti: [Color] = ShellTheme.confettiColors

    /// Phone Play's diagonal wash, spelled the same way here.
    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Rounded display face used for every big number and title.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Animated background

/// A deep gradient with soft glow blobs drifting slowly behind a board. The
/// blobs are radial gradients (no blur pass), painted in a single Canvas at
/// 30 fps, so this is cheap enough to sit behind a 60 fps game.
struct TVAnimatedBackground: View {
    var palette: TVPalette = TVTheme.aurora
    var intensity: Double = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                TVAnimatedBackground.paint(&ctx, size: size,
                                           time: timeline.date.timeIntervalSinceReferenceDate,
                                           palette: palette, intensity: intensity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    static func paint(_ ctx: inout GraphicsContext, size: CGSize, time: Double,
                      palette: TVPalette, intensity: Double) {
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .linearGradient(
            Gradient(colors: palette.background),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: size.height)))

        let base: CGFloat = max(size.width, size.height)
        for (i, color) in palette.blobs.enumerated() {
            let phase: Double = Double(i) * 2.1
            let speed: Double = 0.05 + Double(i) * 0.017
            let cx: CGFloat = size.width * CGFloat(0.5 + 0.38 * sin(time * speed + phase))
            let cy: CGFloat = size.height * CGFloat(0.5 + 0.34 * cos(time * speed * 1.3 + phase * 0.7))
            let radius: CGFloat = base * CGFloat(0.42 + 0.06 * sin(time * 0.11 + phase))
            let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
            let strength: Double = 0.42 * intensity
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [color.opacity(strength), color.opacity(strength * 0.35), color.opacity(0)]),
                center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: radius))
        }

        // A faint vignette keeps the edges dark so content reads centre-out.
        ctx.fill(Path(full), with: .radialGradient(
            Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.55)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: base * 0.3, endRadius: base * 0.75))
    }
}

// MARK: - Glass card

/// A frosted card with a soft gradient border; pass `glow` to make it the
/// highlighted one (current player, winning answer...).
struct TVGlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let tint: Color
    private let glow: Color?
    private let padding: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = ShellTheme.cardRadius, tint: Color = .white, glow: Color? = nil,
         padding: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.glow = glow
        self.padding = padding
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content
            .padding(padding)
            .background(cardFill)
            .overlay(cardBorder)
            .shadow(color: shadowColor, radius: glow == nil ? 18 : 30, x: 0, y: glow == nil ? 12 : 0)
    }

    private var shadowColor: Color {
        if let glow { return glow.opacity(0.55) }
        return Color.black.opacity(0.4)
    }

    private var cardFill: some View {
        ZStack {
            // Forced dark so a light-mode Apple TV never turns the frosted
            // layer white under white text.
            shape.fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            shape.fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var cardBorder: some View {
        let edge: Color = glow ?? Color.white
        return shape.strokeBorder(
            LinearGradient(colors: [Color.white.opacity(0.5), edge.opacity(glow == nil ? 0.08 : 0.9)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: glow == nil ? 1.5 : 3)
    }
}

// MARK: - Glow text

struct TVGlowText: View {
    let text: String
    var size: CGFloat = 64
    var weight: Font.Weight = .heavy
    var color: Color = TVTheme.aurora.accent

    var body: some View {
        Text(text)
            .font(TVTheme.display(size, weight))
            .foregroundStyle(LinearGradient(colors: [Color.white, color],
                                            startPoint: .top, endPoint: .bottom))
            .shadow(color: color.opacity(0.85), radius: size * 0.08)
            .shadow(color: color.opacity(0.45), radius: size * 0.3)
    }
}

// MARK: - Popping number

/// An integer that rolls to its new value and pops when it changes -- for
/// scores, pots and submission counts.
struct TVPopNumber: View {
    let value: Int
    var size: CGFloat = 48
    var color: Color = .white
    var glow: Bool = true

    @State private var pop: CGFloat = 1

    var body: some View {
        Text("\(value)")
            .font(TVTheme.display(size))
            .monospacedDigit()
            .foregroundColor(color)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: value)
            .scaleEffect(pop)
            .shadow(color: color.opacity(glow ? 0.6 : 0), radius: size * 0.22)
            .onChange(of: value) { oldValue, newValue in
                guard oldValue != newValue else { return }
                withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { pop = 1.32 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { pop = 1 }
                }
            }
    }
}

// MARK: - Staggered entrance

/// Rises, un-tilts and fades a view in, `index * step` seconds after it
/// first appears. Re-keying the view (`.id`) replays it.
struct TVStaggeredAppear: ViewModifier {
    let index: Int
    var step: Double = 0.08

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 46)
            .scaleEffect(shown ? 1 : 0.88)
            .rotation3DEffect(.degrees(shown ? 0 : 38), axis: (x: 1, y: 0, z: 0),
                              anchor: .bottom, perspective: 0.6)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.72)
                    .delay(Double(index) * step)) {
                    shown = true
                }
            }
    }
}

extension View {
    func tvStaggeredAppear(index: Int, step: Double = 0.08) -> some View {
        modifier(TVStaggeredAppear(index: index, step: step))
    }
}

// MARK: - 3D card flip

/// Shows `front` or `back` of a card with a real Y-axis flip. The face
/// switch happens per animation frame (at 90 degrees), not at the end of the
/// animation, so neither face is ever seen mirrored.
struct TVFlipCard<Front: View, Back: View>: View {
    let isFaceUp: Bool
    private let front: Front
    private let back: Back

    init(isFaceUp: Bool, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.isFaceUp = isFaceUp
        self.front = front()
        self.back = back()
    }

    var body: some View {
        let angle: Double = isFaceUp ? 0 : 180
        ZStack {
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .modifier(TVFlipFaceVisibility(angle: angle, isFront: false))
            front
                .modifier(TVFlipFaceVisibility(angle: angle, isFront: true))
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

private struct TVFlipFaceVisibility: ViewModifier, Animatable {
    var angle: Double
    let isFront: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let frontShowing: Bool = angle < 90
        return content.opacity(frontShowing == isFront ? 1 : 0)
    }
}

// MARK: - Hero letter

/// A big glowing letter on a glass tile that sways gently in 3D and spins in
/// when the letter changes. Used by NPAT and Atlas.
struct TVHeroLetter: View {
    let letter: String
    var palette: TVPalette = TVTheme.aurora
    var tileSize: CGFloat = 260

    @State private var spin: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t: Double = timeline.date.timeIntervalSinceReferenceDate
            tile
                .rotation3DEffect(.degrees(9 * sin(t * 0.9)), axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.5)
                .rotation3DEffect(.degrees(5 * cos(t * 0.7)), axis: (x: 1, y: 0, z: 0),
                                  perspective: 0.5)
        }
        // The spin lives outside the per-frame sway so its spring animation
        // is never overwritten by the timeline's own redraws.
        .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .frame(width: tileSize * 1.2, height: tileSize * 1.2)
        .onChange(of: letter) { _, _ in
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { spin += 360 }
        }
    }

    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: tileSize * 0.2, style: .continuous)
        let top: Color = palette.blobs.first ?? palette.accent
        let bottom: Color = palette.background.last ?? Color.black
        return ZStack {
            shape.fill(LinearGradient(colors: [top.opacity(0.6), bottom.opacity(0.92)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                      startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), palette.accent.opacity(0.4)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: 4)
            TVGlowText(text: letter.isEmpty ? "?" : letter, size: tileSize * 0.66, color: palette.accent)
        }
        .frame(width: tileSize, height: tileSize)
        .shadow(color: palette.accent.opacity(0.45), radius: 40)
    }
}

// MARK: - Particle bursts

/// Confetti thrown up from `origin` (a unit point in this view's bounds)
/// every time `trigger` changes, and once on appear when `fireOnAppear`.
struct TVConfettiBurst: View {
    let trigger: Int
    var fireOnAppear: Bool = false
    var origin: UnitPoint = UnitPoint(x: 0.5, y: 0.45)
    var colors: [Color] = TVTheme.confetti
    var count: Int = 110
    var duration: Double = 2.8

    var body: some View {
        TVBurstLayer(trigger: trigger, fireOnAppear: fireOnAppear, duration: duration) { ctx, size, elapsed, seed in
            TVBurstPainter.confetti(&ctx, size: size, elapsed: elapsed, seed: seed,
                                    origin: CGPoint(x: size.width * origin.x, y: size.height * origin.y),
                                    colors: colors, count: count, duration: duration)
        }
    }
}

/// A small spark shower plus a shockwave ring at `origin` (in points, in
/// this view's own coordinate space) every time `trigger` changes.
struct TVParticleBurst: View {
    let trigger: Int
    let origin: CGPoint
    var color: Color = .white
    var count: Int = 18
    var reach: CGFloat = 140
    var duration: Double = 0.75

    var body: some View {
        TVBurstLayer(trigger: trigger, fireOnAppear: false, duration: duration) { ctx, _, elapsed, seed in
            TVBurstPainter.sparks(&ctx, elapsed: elapsed, seed: seed, origin: origin,
                                  color: color, count: count, reach: reach, duration: duration)
        }
    }
}

/// Runs a short-lived TimelineView only while a burst is in flight, so an
/// idle burst layer costs nothing.
private struct TVBurstLayer: View {
    let trigger: Int
    let fireOnAppear: Bool
    let duration: Double
    let paint: (inout GraphicsContext, CGSize, Double, Int) -> Void

    @State private var firedAt: Date = .distantPast
    @State private var running = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !running)) { timeline in
            Canvas { ctx, size in
                let elapsed: Double = timeline.date.timeIntervalSince(firedAt)
                if elapsed >= 0 && elapsed < duration {
                    paint(&ctx, size, elapsed, trigger)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { if fireOnAppear { fire() } }
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        let now = Date()
        firedAt = now
        running = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            if firedAt == now { running = false }
        }
    }
}

enum TVBurstPainter {
    /// Deterministic 0..<1 noise, so a burst needs no stored particles.
    static func noise(_ seed: Int, _ i: Int, _ k: Int) -> Double {
        let v: Double = sin(Double(seed % 997) * 12.9898 + Double(i) * 78.233 + Double(k) * 37.719) * 43758.5453
        return v - v.rounded(.down)
    }

    static func confetti(_ ctx: inout GraphicsContext, size: CGSize, elapsed: Double, seed: Int,
                         origin: CGPoint, colors: [Color], count: Int, duration: Double) {
        guard !colors.isEmpty else { return }
        let t: Double = elapsed
        let drag: Double = 1.6
        let travel: Double = (1 - exp(-drag * t)) / drag
        let fade: Double = max(0, min(1, (duration - t) / (duration * 0.35)))
        for i in 0..<max(count, 0) {
            let angle: Double = -Double.pi / 2 + (noise(seed, i, 1) - 0.5) * 2.6
            let speed: Double = 700 + noise(seed, i, 2) * 1100
            let x: Double = Double(origin.x) + cos(angle) * speed * travel
            let y: Double = Double(origin.y) + sin(angle) * speed * travel + 420 * t * t
            let w: Double = 12 + noise(seed, i, 3) * 12
            let flutter: Double = abs(cos(t * (5 + noise(seed, i, 4) * 7) + noise(seed, i, 5) * 6))
            let h: Double = max(1.5, w * 0.55 * flutter)
            let rot: Double = noise(seed, i, 6) * 6.28 + t * (3 + noise(seed, i, 7) * 6)

            var piece = ctx
            piece.translateBy(x: CGFloat(x), y: CGFloat(y))
            piece.rotate(by: Angle(radians: rot))
            piece.opacity = fade
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            piece.fill(Path(roundedRect: rect, cornerRadius: 2),
                       with: .color(colors[i % colors.count]))
        }
    }

    static func sparks(_ ctx: inout GraphicsContext, elapsed: Double, seed: Int, origin: CGPoint,
                       color: Color, count: Int, reach: CGFloat, duration: Double) {
        let p: Double = max(0, min(1, elapsed / max(duration, 0.01)))
        let ease: Double = 1 - (1 - p) * (1 - p) * (1 - p)
        let fade: Double = 1 - p

        // Shockwave ring.
        let ring: CGFloat = reach * 0.75 * CGFloat(ease)
        ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - ring, y: origin.y - ring,
                                          width: ring * 2, height: ring * 2)),
                   with: .color(color.opacity(0.7 * fade)), lineWidth: CGFloat(2 + 6 * fade))

        // Core flash.
        if p < 0.3 {
            let core: CGFloat = reach * 0.35
            ctx.fill(Path(ellipseIn: CGRect(x: origin.x - core, y: origin.y - core,
                                            width: core * 2, height: core * 2)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * (1 - p / 0.3)),
                                                             color.opacity(0)]),
                                           center: origin, startRadius: 0, endRadius: core))
        }

        // Streaks.
        var layer = ctx
        layer.blendMode = .plusLighter
        for i in 0..<max(count, 0) {
            let angle: Double = Double(i) / Double(max(count, 1)) * 2 * Double.pi + noise(seed, i, 1) * 0.6
            let dist: Double = Double(reach) * (0.55 + 0.6 * noise(seed, i, 2))
            let head: Double = dist * ease
            let tail: Double = dist * max(0, ease - 0.18)
            let dx: Double = cos(angle), dy: Double = sin(angle)
            var streak = Path()
            streak.move(to: CGPoint(x: Double(origin.x) + dx * tail, y: Double(origin.y) + dy * tail))
            streak.addLine(to: CGPoint(x: Double(origin.x) + dx * head, y: Double(origin.y) + dy * head))
            let tint: Color = i % 3 == 0 ? Color.white : color
            layer.stroke(streak, with: .color(tint.opacity(fade)),
                         style: StrokeStyle(lineWidth: CGFloat(1.5 + 3.5 * fade), lineCap: .round))
        }
    }
}

// MARK: - Winner banner

/// The end-of-game card: a 3D swing-in glass panel with a glowing headline
/// and a confetti shower behind it. Sized to its content, so it can sit in
/// an overlay or a ZStack without pushing the board's layout around.
struct TVWinnerBanner: View {
    let title: String
    let headline: String
    var detail: String? = nil
    var symbol: String = "trophy.fill"
    var accent: Color = TVTheme.gold
    var celebrate: Bool = true

    @State private var appeared = false

    var body: some View {
        card
            .scaleEffect(appeared ? 1 : 0.55)
            .rotation3DEffect(.degrees(appeared ? 0 : 75), axis: (x: 1, y: 0, z: 0),
                              anchor: .center, perspective: 0.6)
            .opacity(appeared ? 1 : 0)
            .background(confetti)
            .onAppear {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) { appeared = true }
            }
    }

    @ViewBuilder private var confetti: some View {
        if celebrate {
            TVConfettiBurst(trigger: 1, fireOnAppear: true, origin: UnitPoint(x: 0.5, y: 0.55))
                .frame(width: 1600, height: 1000)
        }
    }

    private var card: some View {
        TVGlassCard(cornerRadius: ShellTheme.cardRadius, tint: accent, glow: accent, padding: 0) {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color.white, accent],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: accent.opacity(0.8), radius: 16)
                Text(title.uppercased())
                    .font(.system(size: 24, weight: .heavy)).tracking(6)
                    .foregroundColor(Color.white.opacity(0.75))
                TVGlowText(text: headline, size: 76, color: accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let detail {
                    Text(detail)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(TVTheme.textSecondary)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 44)
        }
    }
}
