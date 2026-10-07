import SwiftUI

// MARK: - Wheel geometry

/// The physical facts of a European single-zero wheel, kept in one place so
/// the face, the ball and the result badge can't disagree with each other.
enum RouletteWheel {

    /// Real pocket order on a European wheel — deliberately not sorted, so
    /// the ball landing next to 26 really does mean it nearly hit 0.
    static let order: [Int] = [
        0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23,
        10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
    ]

    static let redNumbers: Set<Int> = [
        1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36,
    ]

    static var pocketCount: Int { order.count }                  // 37
    static var pocketArc: Double { 360 / Double(pocketCount) }   // ~9.73°

    static func index(of number: Int) -> Int {
        order.firstIndex(of: number) ?? 0
    }

    /// Centre of a pocket in wheel-local degrees, 0° at twelve o'clock,
    /// increasing clockwise (matching SwiftUI's `rotationEffect`).
    static func angle(of number: Int) -> Double {
        Double(index(of: number)) * pocketArc + pocketArc / 2
    }

    static func isRed(_ n: Int) -> Bool { redNumbers.contains(n) }

    static func fill(for n: Int) -> Color {
        if n == 0 { return Color(hex: "0b7a3b") }
        return isRed(n) ? Color(hex: "c0202a") : Color(hex: "15161a")
    }

    static func name(for n: Int) -> String {
        if n == 0 { return "GREEN" }
        return isRed(n) ? "RED" : "BLACK"
    }
}

// MARK: - Spin timing

/// One spin, as everything the board needs to animate it without asking the
/// server again: the server picks the winning pocket up front (see
/// RouletteEngine.pending_result) precisely so the ball can be flown into the
/// pocket it will actually land in, instead of teleporting there at the end.
private struct RouletteSpin {
    let start: Date
    let duration: Double
    let result: Int
    /// Full turns the wheel adds over the spin, on top of its idle drift.
    let wheelTurns: Double = 5
    /// Full turns the ball travels, in the opposite direction.
    let ballTurns: Double = 9

    var end: Date { start.addingTimeInterval(duration) }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }
}

// MARK: - Animation model

/// Owns the wheel's motion. Deliberately a set of *pure functions of time* so
/// the renderer (a TimelineView, redrawing every frame) and the audio ticker
/// (a much slower timer) can both ask "where is the ball right now?" and get
/// the same answer without duplicating the maths or drifting apart.
@MainActor
final class RouletteWheelModel: ObservableObject {

    /// Idle drift, degrees per second — a real wheel is never quite still.
    private let idleRate: Double = 4

    private var reference = Date()
    private var spin: RouletteSpin?
    private var resting: Int?

    /// Recent results, newest first, for the history strip.
    @Published private(set) var history: [Int] = []
    @Published private(set) var isSpinning = false
    /// The pocket the ball is sitting in once it has stopped; nil while it
    /// is still moving. Drives the gold outline on the wheel.
    @Published private(set) var landedNumber: Int?

    /// Ball-at-rest distance from the centre (fraction of the wheel radius):
    /// the inner pocket band, directly below its number (RouletteWheelFace).
    static let pocketRestFraction = 0.6

    private var lastClickPocket: Int?
    private var lastClickAt: Date = .distantPast
    private var announcedLanding = false

    // MARK: Server-driven transitions

    func beginSpin(result: Int, duration: Double) {
        guard spin == nil else { return }
        spin = RouletteSpin(start: Date(),
                            duration: max(1.5, duration),
                            result: result)
        isSpinning = true
        landedNumber = nil
        announcedLanding = false
        SoundPlayer.shared.startLoop(.rouletteSpin, volume: 0.45)
    }

    /// The server has settled. If a spin is still animating we let it finish
    /// (it is already flying at the right pocket); otherwise we drop the ball
    /// straight into place, which is what a board joining mid-round does.
    func settle(result: Int) {
        resting = result
        if history.first != result {
            history.insert(result, at: 0)
            history = Array(history.prefix(12))
        }
        if spin == nil {
            isSpinning = false
            landedNumber = result
        }
    }

    func reset() {
        spin = nil
        resting = nil
        isSpinning = false
        landedNumber = nil
        SoundPlayer.shared.fadeOutLoop(.rouletteSpin, over: 0.3)
    }

    // MARK: Pure geometry

    func wheelAngle(at now: Date) -> Double {
        let idle = idleRate * now.timeIntervalSince(reference)
        guard let spin else { return idle }
        return idle + spin.wheelTurns * 360 * easeOutCubic(spin.progress(at: now))
    }

    /// Where the ball sits, in screen degrees (0° up, clockwise).
    func ballAngle(at now: Date) -> Double {
        guard let spin else {
            guard let resting else { return -wheelAngle(at: now) * 0.35 }
            // Settled: the ball rides around in its pocket with the wheel.
            return wheelAngle(at: now) + RouletteWheel.angle(of: resting)
        }
        // Where the pocket will be when the wheel stops.
        let idleAtEnd = idleRate * spin.end.timeIntervalSince(reference)
        let target = idleAtEnd + spin.wheelTurns * 360 + RouletteWheel.angle(of: spin.result)
        let from = target + 360 * spin.ballTurns      // travels backwards into place
        return from + (target - from) * easeOutQuint(spin.progress(at: now))
    }

    /// Ball distance from the centre, as a fraction of the wheel's radius.
    func ballRadiusFraction(at now: Date) -> Double {
        let track = 0.935          // the rim it circles while fast
        let pocket = Self.pocketRestFraction   // where it comes to rest
        guard let spin else { return resting == nil ? track : pocket }
        let p = spin.progress(at: now)

        // Stays out on the track, then falls in over the last ~45%.
        let fall = pow(max(0, (p - 0.55) / 0.45), 2.1)
        var r = track - (track - pocket) * fall

        // Rattling over the frets on the way down.
        if p > 0.62, p < 0.98 {
            let decay = (0.98 - p) / 0.36
            r += sin(p * 130) * 0.02 * decay
        }
        return r
    }

    // MARK: Audio (driven by its own slow timer, never from a view body)

    func advanceAudio(at now: Date) {
        guard let spin else { return }
        let p = spin.progress(at: now)

        if p >= 1 {
            if !announcedLanding {
                announcedLanding = true
                SoundPlayer.shared.fadeOutLoop(.rouletteSpin, over: 0.35)
                SoundPlayer.shared.play(.winFanfare, volume: 0.85)
            }
            // Hand the ball over to the resting position and end the spin.
            resting = spin.result
            landedNumber = spin.result
            self.spin = nil
            isSpinning = false
            return
        }

        // One click per fret crossed, thinned out so the fast early phase
        // reads as a rattle rather than a buzzsaw.
        let pocketIndex = Int(floor(ballAngle(at: now) / RouletteWheel.pocketArc))
        if pocketIndex != lastClickPocket,
           now.timeIntervalSince(lastClickAt) > 0.055 {
            lastClickPocket = pocketIndex
            lastClickAt = now
            SoundPlayer.shared.playClick(volume: Float(0.25 + 0.4 * (1 - p)))
        }
    }

    // MARK: Easing

    private func easeOutCubic(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
    private func easeOutQuint(_ p: Double) -> Double { 1 - pow(1 - p, 5) }
}

// MARK: - The wheel face

/// Drawn once and simply rotated as a whole by the caller, so the 37 wedges,
/// frets and numerals are laid out once per state change rather than on
/// every animation frame.
///
/// Layout follows a real European wheel, as fractions of the wheel radius:
/// pocket ring 0.46-0.82, numbers in the outer band (0.70-0.82, centred at
/// 0.76), ball pockets in the inner band where the ball comes to rest
/// (`RouletteWheelModel.pocketRestFraction`), so the number printed right
/// above the ball is always the result.
///
/// The numerals used to be placed at `radius * 0.355` -- well inside the
/// metal cone (radius 0.46), which is drawn on top of them -- so none were
/// visible. They were also `.position`ed and then rotated as a full-size
/// frame, which turned each one a second time (to twice its angle).
///
/// Deliberately NOT wrapped in `.drawingGroup()`: an earlier version was, to
/// flatten those 37+37 shapes and numerals into one composited layer, and
/// the wheel's numbers came back completely invisible on a real Apple TV --
/// reported directly -- while rendering fine in the Simulator the whole
/// pipeline had actually been verified against. Rotated/positioned `Text`
/// silently failing inside a `.drawingGroup()`'s offscreen Metal render pass
/// is a real, independently-reported SwiftUI/Metal interaction, and the
/// Simulator's software renderer doesn't reproduce it -- which is also why
/// neither `build-check` nor `GameLabTVUITests` (neither of which renders a
/// gameplay screen at all) had any chance of catching this before it shipped.
private struct RouletteWheelFace: View {
    /// The pocket the ball has come to rest in, outlined in gold.
    var highlight: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2

            ZStack {
                // Outer wooden bowl
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [Color(hex: "6b3b1d"), Color(hex: "a56435"),
                                     Color(hex: "6b3b1d"), Color(hex: "8a4f28"),
                                     Color(hex: "6b3b1d")],
                            center: .center,
                            // AngularGradient's startAngle/endAngle default to
                            // .zero -- a zero-degree sweep, which renders as a
                            // single solid colour, not a gradient. Every
                            // report of "AngularGradient shows one flat
                            // colour" traces back to this; a real sweep needs
                            // both spelled out.
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.55), lineWidth: size * 0.012))

                // Recessed ball track
                Circle()
                    .fill(Color(hex: "2a1710"))
                    .frame(width: size * 0.90, height: size * 0.90)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: size * 0.006)
                            .frame(width: size * 0.90, height: size * 0.90)
                    )

                // Pocket ring
                ForEach(Array(RouletteWheel.order.enumerated()), id: \.offset) { index, number in
                    PocketWedge(startAngle: Double(index) * RouletteWheel.pocketArc,
                                sweep: RouletteWheel.pocketArc,
                                innerRatio: 0.56)
                        .fill(RouletteWheel.fill(for: number))
                        .frame(width: size * 0.82, height: size * 0.82)
                }

                // Frets between pockets
                ForEach(0..<RouletteWheel.pocketCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Color(hex: "d9d9de"), Color(hex: "7c7c86")],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: size * 0.006, height: size * 0.21)
                        .offset(y: -size * 0.295)
                        .rotationEffect(.degrees(Double(index) * RouletteWheel.pocketArc))
                }

                // Gold ring splitting the number band from the ball pockets
                Circle()
                    .strokeBorder(Color(hex: "d4a531").opacity(0.85), lineWidth: size * 0.004)
                    .frame(width: size * 0.70, height: size * 0.70)

                // Winning pocket, outlined (rotates with the wheel)
                if let highlight {
                    PocketWedge(startAngle: Double(RouletteWheel.index(of: highlight)) * RouletteWheel.pocketArc,
                                sweep: RouletteWheel.pocketArc,
                                innerRatio: 0.56)
                        .stroke(Color(hex: "ffe9a8"), lineWidth: size * 0.008)
                        .frame(width: size * 0.82, height: size * 0.82)
                        .shadow(color: Color(hex: "ffe9a8").opacity(0.9), radius: size * 0.015)
                }

                // Numerals in the outer band, tops pointing outward like a real
                // wheel. Same offset-then-rotate idiom as the frets: the offset
                // moves the label up to the band, and the rotation (about the
                // wheel centre, the label's untranslated frame centre) carries
                // it round to its pocket and turns it to match.
                ForEach(Array(RouletteWheel.order.enumerated()), id: \.offset) { _, number in
                    Text("\(number)")
                        .font(.system(size: size * 0.042, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .fixedSize()
                        .offset(y: -radius * 0.76)
                        .rotationEffect(.degrees(RouletteWheel.angle(of: number)))
                }

                // Metal cone and turret
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: "e8e6df"), Color(hex: "9a978d"),
                                                Color(hex: "5d5b55")],
                                       center: .init(x: 0.38, y: 0.32),
                                       startRadius: 0, endRadius: size * 0.28)
                    )
                    .frame(width: size * 0.46, height: size * 0.46)

                ForEach(0..<4, id: \.self) { arm in
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Color(hex: "f2f0e8"), Color(hex: "8b8880")],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: size * 0.028, height: size * 0.42)
                        .rotationEffect(.degrees(Double(arm) * 45))
                }

                Circle()
                    .fill(
                        RadialGradient(colors: [Color(hex: "ffe9a8"), Color(hex: "b8912f")],
                                       center: .init(x: 0.35, y: 0.3),
                                       startRadius: 0, endRadius: size * 0.09)
                    )
                    .frame(width: size * 0.12, height: size * 0.12)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 2)
                        .frame(width: size * 0.12, height: size * 0.12))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// One pocket: the ring segment between two frets.
private struct PocketWedge: Shape {
    let startAngle: Double
    let sweep: Double
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        // SwiftUI angles start at three o'clock, so shift by 90° to put 0° at
        // the top and keep every angle in this file in the same convention.
        let from = Angle(degrees: startAngle - 90)
        let to = Angle(degrees: startAngle + sweep - 90)

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Board

struct TVRouletteBoardView: View {
    let room: Room

    @StateObject private var vm = RouletteBoardViewModel()
    @StateObject private var wheel = RouletteWheelModel()

    /// Audio only — the visuals redraw from TimelineView, which must stay a
    /// pure function of time with no side effects in its body.
    private let audioTicker = Timer.publish(every: 1.0 / 25.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let wheelSize = min(geo.size.height * 0.86, geo.size.width * 0.46)

            HStack(spacing: 0) {
                wheelPanel(size: wheelSize)
                    .frame(width: geo.size.width * 0.46)

                tablePanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(feltBackground.ignoresSafeArea())
        .onAppear { vm.bind(roomCode: room.code) }
        .onReceive(audioTicker) { now in wheel.advanceAudio(at: now) }
        .onChange(of: vm.state.isSpinning) { spinning in
            if spinning, let pending = vm.state.pendingResult {
                wheel.beginSpin(result: pending,
                                duration: vm.state.spinRemaining > 0
                                    ? vm.state.spinRemaining
                                    : vm.state.spinSeconds)
            }
        }
        // Keyed on the round counter, not on lastResult: the same number
        // coming up twice in a row is a perfectly ordinary outcome, and
        // watching the value itself would silently skip the second one.
        .onChange(of: vm.state.round) { _ in
            if let result = vm.state.lastResult { wheel.settle(result: result) }
        }
    }

    // MARK: Left — the wheel

    private func wheelPanel(size: CGFloat) -> some View {
        TimelineView(.animation) { context in
            let now = context.date
            let wheelAngle = wheel.wheelAngle(at: now)
            let ballAngle = wheel.ballAngle(at: now)
            let ballR = wheel.ballRadiusFraction(at: now)

            ZStack {
                RouletteWheelFace(highlight: wheel.landedNumber)
                    .frame(width: size, height: size)
                    .rotationEffect(.degrees(wheelAngle))
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 12)

                // The ball
                Circle()
                    .fill(
                        RadialGradient(colors: [.white, Color(hex: "d9d9d9"), Color(hex: "8f8f8f")],
                                       center: .init(x: 0.34, y: 0.3),
                                       startRadius: 0, endRadius: size * 0.022)
                    )
                    .frame(width: size * 0.042, height: size * 0.042)
                    .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                    .offset(
                        x: size / 2 * ballR * cos((ballAngle - 90) * .pi / 180),
                        y: size / 2 * ballR * sin((ballAngle - 90) * .pi / 180)
                    )

                // Fixed pointer at the top of the bowl
                RoulettePointer()
                    .fill(
                        LinearGradient(colors: [Color(hex: "ffe9a8"), Color(hex: "b8912f")],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: size * 0.05, height: size * 0.06)
                    .offset(y: -size * 0.52)
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            }
            .frame(width: size, height: size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Right — result, history and the felt

    private var tablePanel: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                Text("Roulette")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: "ffe9a8"), Color(hex: "d4a531")],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Spacer()
                if vm.state.maxRounds > 0 {
                    Text("Round \(min(vm.state.round + 1, vm.state.maxRounds)) / \(vm.state.maxRounds)")
                        .font(.system(.title3, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            resultBadge
            historyStrip
            feltTable
            Spacer(minLength: 0)
            playerStrip
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 48)
    }

    private var resultBadge: some View {
        HStack(spacing: 22) {
            if wheel.isSpinning || vm.state.isSpinning {
                ProgressView()
                    .scaleEffect(1.6)
                    .tint(Color(hex: "ffe9a8"))
                    .frame(width: 104, height: 104)
                Text("No more bets…")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
            } else if let result = vm.state.lastResult {
                ZStack {
                    Circle()
                        .fill(RouletteWheel.fill(for: result))
                        .frame(width: 104, height: 104)
                        .overlay(Circle().strokeBorder(Color(hex: "ffe9a8"), lineWidth: 4))
                        .shadow(color: RouletteWheel.fill(for: result).opacity(0.8), radius: 24)
                    Text("\(result)")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(RouletteWheel.name(for: result))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(Self.subtitle(for: result))
                        .font(.system(.title3, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
            } else {
                Text("Place your bets")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(height: 104)
            }
            Spacer()
        }
    }

    private var historyStrip: some View {
        HStack(spacing: 10) {
            ForEach(Array(wheel.history.prefix(10).enumerated()), id: \.offset) { _, number in
                Text("\(number)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(RouletteWheel.fill(for: number)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            }
            Spacer()
        }
        .frame(height: 46)
    }

    /// The betting layout. Only the outside bets are actually playable (see
    /// ROULETTE_PAYOUTS on the engine), so those are the ones given real
    /// estate; the numbers are here so a win can be pointed at.
    private var feltTable: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                numberCell(0, width: 46, height: 116)
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(0..<12, id: \.self) { column in
                                numberCell(3 - row + column * 3, width: 46, height: 34)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                outsideCell("1st 12", target: "1-12")
                outsideCell("2nd 12", target: "13-24")
                outsideCell("3rd 12", target: "25-36")
            }

            HStack(spacing: 6) {
                outsideCell("1–18", target: "low")
                outsideCell("EVEN", target: "even")
                outsideCell("RED", target: "red", tint: Color(hex: "c0202a"))
                outsideCell("BLACK", target: "black", tint: Color(hex: "15161a"))
                outsideCell("ODD", target: "odd")
                outsideCell("19–36", target: "high")
            }
        }
    }

    private func numberCell(_ n: Int, width: CGFloat, height: CGFloat) -> some View {
        // Only once the ball has actually stopped, so the felt never gives
        // the number away before the wheel does.
        let isWinner = !vm.state.isSpinning && !wheel.isSpinning && vm.state.lastResult == n
        return Text("\(n)")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 5).fill(RouletteWheel.fill(for: n)))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isWinner ? Color(hex: "ffe9a8") : .white.opacity(0.18),
                                  lineWidth: isWinner ? 4 : 1)
            )
            .overlay(alignment: .bottom) { chipStack(for: "\(n)") }
            .scaleEffect(isWinner ? 1.14 : 1)
            .shadow(color: isWinner ? Color(hex: "ffe9a8").opacity(0.9) : .clear, radius: 14)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isWinner)
    }

    private func outsideCell(_ label: String, target: String, tint: Color? = nil) -> some View {
        let isWinner = !vm.state.isSpinning && winningTargets.contains(target)
        return Text(label)
            .font(.system(size: 19, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(tint ?? Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isWinner ? Color(hex: "ffe9a8") : .white.opacity(0.18),
                                  lineWidth: isWinner ? 4 : 1)
            )
            .overlay(alignment: .topTrailing) { chipStack(for: target) }
            .shadow(color: isWinner ? Color(hex: "ffe9a8").opacity(0.8) : .clear, radius: 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isWinner)
    }

    /// A little stack of chips over a cell with money on it, sized loosely by
    /// how much is staked -- reads as "there's real weight here" without
    /// needing an exact chip-counting simulation.
    @ViewBuilder
    private func chipStack(for target: String) -> some View {
        if let amount = vm.state.betsByTarget[target], amount > 0 {
            ZStack {
                ForEach(0..<min(3, 1 + amount / 50), id: \.self) { i in
                    Circle()
                        .fill(chipColor(for: amount))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                        .offset(y: -CGFloat(i) * 4)
                }
                Text("\(amount)")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .offset(y: -CGFloat(min(2, amount / 50)) * 4)
            }
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: amount)
            // Nudged half outside the cell so it reads as a chip resting ON
            // the number rather than a badge clipped to its bounds.
            .offset(y: -6)
        }
    }

    private func chipColor(for amount: Int) -> Color {
        switch amount {
        case ..<25:   return Color(hex: "e5e7eb")   // white/grey — small stake
        case ..<100:  return Color(hex: "3b82f6")   // blue
        case ..<500:  return Color(hex: "16a34a")   // green
        default:      return Color(hex: "1f2937")   // black — big money
        }
    }

    /// Which outside bets the last number paid out — mirrors `_bet_wins` on
    /// the engine so the highlight can never claim a win the server didn't.
    private var winningTargets: Set<String> {
        guard let n = vm.state.lastResult, n != 0 else { return [] }
        var targets: Set<String> = []
        targets.insert(RouletteWheel.isRed(n) ? "red" : "black")
        targets.insert(n % 2 == 0 ? "even" : "odd")
        targets.insert(n <= 18 ? "low" : "high")
        if n <= 12 { targets.insert("1-12") }
        else if n <= 24 { targets.insert("13-24") }
        else { targets.insert("25-36") }
        return targets
    }

    /// Split out of the badge rather than inlined: a nested ternary with
    /// string interpolation inside a view builder is the exact shape that
    /// has previously blown up this project's Swift type-check budget.
    private static func subtitle(for result: Int) -> String {
        guard result != 0 else { return "House number" }
        let parity = result % 2 == 0 ? "Even" : "Odd"
        let half = result <= 18 ? "Low" : "High"
        return "\(parity) · \(half)"
    }

    private var playerStrip: some View {
        HStack(spacing: 18) {
            ForEach(room.players) { player in
                VStack(spacing: 4) {
                    Text(player.name)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("$\(vm.state.chips[player.id] ?? player.score)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "ffe9a8"))
                    let bet = vm.state.playerBets[player.id] ?? 0
                    Text(bet > 0 ? "Bet $\(bet)" : "—")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(bet > 0 ? TVTheme.cyan : .white.opacity(0.3))
                }
                .frame(minWidth: 120)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: ShellTheme.chipRadius).fill(.white.opacity(0.06)))
            }
            Spacer()
        }
    }

    private var feltBackground: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: "13512f"), Color(hex: "062617"), Color(hex: "03130c")],
                           center: .center, startRadius: 80, endRadius: 1400)
            // Vignette so the wheel reads as lit from above.
            RadialGradient(colors: [.clear, .black.opacity(0.55)],
                           center: .center, startRadius: 500, endRadius: 1500)
        }
    }
}

private struct RoulettePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Server state

struct RouletteBoardState {
    var isSpinning = false
    var lastResult: Int? = nil
    var pendingResult: Int? = nil
    var spinRemaining: Double = 0
    var spinSeconds: Double = 6
    var playerBets: [String: Int] = [:]
    /// Every current bet's total, keyed by target ("red", "17", ...) rather
    /// than by player -- what actually drives the chip stacks drawn on the
    /// felt, since once money is on the table which player placed it isn't
    /// what the board needs to show.
    var betsByTarget: [String: Int] = [:]
    var chips: [String: Int] = [:]
    var round = 0
    var maxRounds = 0

    mutating func update(from data: [String: AnyCodable]) {
        if let v = data["isSpinning"]?.value as? Bool { isSpinning = v }
        if let v = data["lastResult"]?.value as? Int { lastResult = v }
        // pendingResult is deliberately nil while not spinning, so this one
        // is assigned unconditionally rather than only when present.
        pendingResult = data["pendingResult"]?.value as? Int
        if let v = data["spinRemaining"]?.value { spinRemaining = Self.double(v) ?? spinRemaining }
        if let v = data["spinSeconds"]?.value { spinSeconds = Self.double(v) ?? spinSeconds }
        if let v = data["playerBets"]?.value as? [String: Int] { playerBets = v }
        // Cleared to empty when the field goes missing rather than only
        // assigned when present: an empty round (nobody's staked anything
        // yet, or bets were just cleared) must not go on showing the
        // PREVIOUS round's chip stacks.
        betsByTarget = (data["betsByTarget"]?.value as? [String: Int]) ?? [:]
        if let v = data["chips"]?.value as? [String: Int] { chips = v }
        if let v = data["round"]?.value as? Int { round = v }
        if let v = data["maxRounds"]?.value as? Int { maxRounds = v }
    }

    /// JSON numbers arrive as Int when they happen to be whole, so anything
    /// that can be fractional has to accept both or it silently stays at its
    /// default -- a failure mode this project has hit more than once.
    private static func double(_ value: Any) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}

@MainActor final class RouletteBoardViewModel: ObservableObject {
    @Published var state = RouletteBoardState()
    private let socket = GameSocketManager.shared

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard r.roomCode == roomCode else { return }
            self?.state.update(from: r.boardState)
        }
    }
}
