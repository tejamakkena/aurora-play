import SwiftUI

// MARK: - 2048 screen (Pocket Arcade)

/// The tile ramp, in Phone Play colours: cool blues for the small tiles,
/// warming through green, yellow and orange to hot pinks and purples.
private enum Arcade2048Palette {
    static func colors(for value: Int) -> [Color] {
        switch value {
        case 2:    return [PhonePlayDesign.blue.opacity(0.55), PhonePlayDesign.indigo.opacity(0.55)]
        case 4:    return [PhonePlayDesign.blue, PhonePlayDesign.indigo]
        case 8:    return [PhonePlayDesign.cyan, PhonePlayDesign.blue]
        case 16:   return [PhonePlayDesign.green, PhonePlayDesign.cyan]
        case 32:   return [PhonePlayDesign.yellow, PhonePlayDesign.green]
        case 64:   return [PhonePlayDesign.orange, PhonePlayDesign.yellow]
        case 128:  return [PhonePlayDesign.red, PhonePlayDesign.orange]
        case 256:  return [PhonePlayDesign.pink, PhonePlayDesign.red]
        case 512:  return [PhonePlayDesign.purple, PhonePlayDesign.pink]
        case 1024: return [PhonePlayDesign.indigo, PhonePlayDesign.purple]
        case 2048: return [PhonePlayDesign.yellow, PhonePlayDesign.orange, PhonePlayDesign.pink]
        default:   return [PhonePlayDesign.pink, PhonePlayDesign.purple, PhonePlayDesign.indigo]
        }
    }

    /// Dark digits on the bright middle of the ramp, white elsewhere.
    static func text(for value: Int) -> Color {
        switch value {
        case 16, 32, 64: return Color.black.opacity(0.8)
        default:         return .white
        }
    }

    /// Big tiles glow.
    static func glow(for value: Int) -> Color {
        value >= 128 ? (colors(for: value).first ?? .clear).opacity(0.55) : .clear
    }
}

struct Arcade2048PlayView: View {
    @ObservedObject var board: Arcade2048Model
    let onClose: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            header
            Spacer(minLength: 0)
            Arcade2048BoardView(model: board, onFinish: onFinish)
            controls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private var header: some View {
        HStack {
            Button {
                PhonePlayHaptics.tap()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the arcade")
            Spacer()
            Arcade2048Stat(label: "SCORE", value: board.score, tint: .white)
                .overlay(alignment: .top) {
                    if let gain = board.gain {
                        Arcade2048GainLabel(points: gain.points)
                            .id(gain.id)
                    }
                }
            Spacer()
            Arcade2048Stat(label: "BEST", value: board.shownBest, tint: PhonePlayDesign.yellow)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 10)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                guard board.canUndo else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    board.undo()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(board.undoUsed ? "Undo used" : "Undo last move")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white.opacity(board.canUndo ? 0.9 : 0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .overlay(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .strokeBorder(Color.white.opacity(board.canUndo ? 0.14 : 0.05), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PhonePlayPressStyle())
            .disabled(!board.canUndo)

            Text("Swipe to slide the tiles. Two the same merge into one.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .multilineTextAlignment(.center)
        }
        .animation(PhonePlayDesign.smooth, value: board.canUndo)
    }
}

private struct Arcade2048Stat: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundColor(PhonePlayDesign.text3)
            Text("\(value)")
                .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
                .animation(PhonePlayDesign.smooth, value: value)
        }
        .frame(minWidth: 96)
    }
}

/// "+16" that floats up from the score and fades.
private struct Arcade2048GainLabel: View {
    let points: Int

    @State private var risen: Bool = false

    var body: some View {
        Text("+\(points)")
            .font(.system(size: 18, weight: .black, design: .rounded).monospacedDigit())
            .foregroundColor(PhonePlayDesign.green)
            .offset(y: risen ? -30 : 4)
            .opacity(risen ? 0 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.75)) {
                    risen = true
                }
            }
    }
}

// MARK: - Board

private struct Arcade2048BoardView: View {
    @ObservedObject var model: Arcade2048Model
    let onFinish: () -> Void

    private let gap: CGFloat = 10

    /// New tiles pop in once the slide has landed; eaten tiles fade fast.
    private static var tileTransition: AnyTransition {
        AnyTransition.asymmetric(
            insertion: AnyTransition.scale(scale: 0.1).combined(with: .opacity)
                .animation(Animation.spring(response: 0.3, dampingFraction: 0.55).delay(0.1)),
            removal: AnyTransition.scale(scale: 0.6).combined(with: .opacity)
                .animation(Animation.easeOut(duration: 0.1))
        )
    }

    var body: some View {
        GeometryReader { geo in
            let n: Int = Arcade2048Board.size
            let side: CGFloat = max(80, min(geo.size.width, geo.size.height))
            let cell: CGFloat = max(10, (side - gap * CGFloat(n + 1)) / CGFloat(n))
            ZStack {
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .fill(PhonePlayDesign.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
                ForEach(0..<(n * n), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .frame(width: cell, height: cell)
                        .position(center(row: index / n, col: index % n, cell: cell))
                }
                ForEach(model.drawn) { tile in
                    Arcade2048TileView(value: tile.value, cell: cell)
                        .position(center(row: tile.row, col: tile.col, cell: cell))
                        .transition(Arcade2048BoardView.tileTransition)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .gesture(swipe)
        .overlay {
            banner
        }
        .animation(PhonePlayDesign.pop, value: model.stuck)
        .animation(PhonePlayDesign.pop, value: model.showGoal)
    }

    private func center(row: Int, col: Int, cell: CGFloat) -> CGPoint {
        CGPoint(x: gap + cell / 2 + CGFloat(col) * (cell + gap),
                y: gap + cell / 2 + CGFloat(row) * (cell + gap))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let dx: CGFloat = value.translation.width
                let dy: CGFloat = value.translation.height
                guard max(abs(dx), abs(dy)) > 24 else { return }
                let direction: Arcade2048Direction
                if abs(dx) > abs(dy) {
                    direction = dx > 0 ? .right : .left
                } else {
                    direction = dy > 0 ? .down : .up
                }
                withAnimation(.easeOut(duration: 0.13)) {
                    model.swipe(direction)
                }
            }
    }

    @ViewBuilder
    private var banner: some View {
        if model.showGoal {
            Arcade2048Banner(symbol: "trophy.fill",
                             title: "2048!",
                             subtitle: "You made the big one. Keep going for more?",
                             colors: [PhonePlayDesign.yellow, PhonePlayDesign.orange]) {
                PhonePlayBigButton(title: "Keep going", symbol: "arrow.right",
                                   colors: [PhonePlayDesign.yellow, PhonePlayDesign.orange]) {
                    model.keepGoing()
                }
                PhonePlayGhostButton(title: "Finish here", symbol: "flag.checkered") {
                    onFinish()
                }
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        } else if model.stuck {
            Arcade2048Banner(symbol: "square.grid.3x3.fill",
                             title: "No moves left",
                             subtitle: model.canUndo ? "One undo left. Use it?" : "The board is full.",
                             colors: [PhonePlayDesign.orange, PhonePlayDesign.pink]) {
                if model.canUndo {
                    PhonePlayBigButton(title: "Undo last move", symbol: "arrow.uturn.backward",
                                       colors: [PhonePlayDesign.cyan, PhonePlayDesign.blue]) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.undo()
                        }
                    }
                }
                PhonePlayBigButton(title: "See score", symbol: "trophy.fill",
                                   colors: [PhonePlayDesign.orange, PhonePlayDesign.pink]) {
                    onFinish()
                }
            }
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
}

/// The card laid over the board when the game pauses for a decision.
private struct Arcade2048Banner<Buttons: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    let colors: [Color]
    let buttons: Buttons

    init(symbol: String, title: String, subtitle: String, colors: [Color],
         @ViewBuilder buttons: () -> Buttons) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.colors = colors
        self.buttons = buttons()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(PhonePlayDesign.gradient(colors))
                .phonePlayIdle(scale: 0.06, duration: 0.8)
            Text(title)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
                .multilineTextAlignment(.center)
            buttons
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.bg.opacity(0.86))
        )
    }
}

// MARK: - One tile

private struct Arcade2048TileView: View {
    let value: Int
    let cell: CGFloat

    /// Bumped when this tile grows from a merge; drives the pop.
    @State private var merges: Int = 0

    private static let popPhases: [CGFloat] = [1, 1.16]

    private var fontSize: CGFloat {
        switch String(value).count {
        case 0...2: return cell * 0.42
        case 3:     return cell * 0.34
        case 4:     return cell * 0.27
        default:    return cell * 0.22
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(PhonePlayDesign.gradient(Arcade2048Palette.colors(for: value)))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .overlay(
                Text("\(value)")
                    .font(.system(size: fontSize, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundColor(Arcade2048Palette.text(for: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(4)
            )
            .shadow(color: Arcade2048Palette.glow(for: value), radius: 10)
            .frame(width: cell, height: cell)
            .phaseAnimator(Arcade2048TileView.popPhases, trigger: merges) { content, scale in
                content.scaleEffect(scale)
            } animation: { scale in
                if scale > 1 {
                    return Animation.spring(response: 0.14, dampingFraction: 0.5).delay(0.08)
                }
                return Animation.spring(response: 0.24, dampingFraction: 0.6)
            }
            .onChange(of: value) { old, new in
                if new > old {
                    merges += 1
                }
            }
    }
}
