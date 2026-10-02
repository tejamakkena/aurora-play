import SwiftUI

/// Phone controllers for the duel, co-op and solo games.

// MARK: - Defuse

struct DefuseControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isDefuser: Bool { privateData.bool("isDefuser") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var strikes: Int { privateData.int("strikes") }
    private var moduleType: String { privateData.str("moduleType") }
    /// Empty for the defuser: they hold the bomb, everyone else holds the manual.
    private var manual: [String] { privateData.strings("manual") }
    private var module: [String: Any] { privateData["module"] as? [String: Any] ?? [:] }
    private var finished: Bool { privateData.bool("finished") }
    private var won: Bool { privateData.bool("won") }

    var body: some View {
        ControllerShell(title: "Defuse",
                        subtitle: isDefuser ? "You hold the bomb" : "You have the manual",
                        secondsLeft: seconds) {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "xmark").font(.title3.bold()).foregroundColor(.white.opacity(0.7))
                                .foregroundColor(i < strikes ? .red : .white.opacity(0.15))
                        }
                    }
                    .padding(.top, 14)

                    if finished {
                        WaitingState(systemIcon: won ? "heart.fill" : "burst.fill",
                                     text: won ? "Defused!" : "Boom.")
                    } else if isDefuser {
                        defuserControls
                    } else {
                        manualPages
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var defuserControls: some View {
        VStack(spacing: 12) {
            Text("Describe what you see — they have the instructions")
                .font(.caption).foregroundColor(.orange)
                .multilineTextAlignment(.center).padding(.horizontal, 24)

            switch moduleType {
            case "wires":
                let wires = (module["wires"] as? [Any] ?? []).compactMap { $0 as? String }
                VStack(spacing: 10) {
                    ForEach(Array(wires.enumerated()), id: \.offset) { i, w in
                        Button(action: { onAction("cut", ["index": i]) }) {
                            HStack(spacing: 14) {
                                Text("\(i + 1)").font(.headline)
                                    .foregroundColor(.white.opacity(0.4)).frame(width: 26)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(wireColor(w)).frame(height: 16)
                                Text("CUT").font(.caption.bold()).foregroundColor(.white)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

            case "button":
                VStack(spacing: 16) {
                    Circle().fill(wireColor(module["colour"] as? String ?? ""))
                        .frame(width: 140, height: 140)
                        .overlay(Text(module["label"] as? String ?? "")
                            .font(.headline.bold())
                            .foregroundColor((module["colour"] as? String) == "white"
                                             ? .black : .white))
                    HStack(spacing: 12) {
                        BigButton(title: "TAP", tint: .green) {
                            onAction("button", ["press": "tap"])
                        }
                        BigButton(title: "HOLD", tint: .orange) {
                            onAction("button", ["press": "hold"])
                        }
                    }
                }

            case "symbols":
                let symbols = (module["symbols"] as? [Any] ?? []).compactMap { $0 as? String }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { i, s in
                        Button(action: { onAction("symbol", ["index": i]) }) {
                            Text(s).font(.system(size: 46)).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 22)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

            default:
                ProgressView().tint(.white)
            }
        }
    }

    private var manualPages: some View {
        VStack(spacing: 14) {
            Text("DEFUSAL MANUAL").font(.caption.bold()).tracking(3)
                .foregroundColor(.cyan)
            Text("You can't see the bomb. Read this out loud.")
                .font(.caption).foregroundColor(.white.opacity(0.45))
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(manual, id: \.self) { line in
                    Text(line).font(.callout).foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
            .padding(.horizontal, 20)
        }
    }

    private func wireColor(_ name: String) -> Color {
        switch name {
        case "red": return .red
        case "blue": return .blue
        case "yellow": return .yellow
        case "white": return .white
        default: return .gray
        }
    }
}

// MARK: - Battleship

struct BattleshipControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var size: Int { privateData.int("size", 8) }
    private var isMyTurn: Bool { privateData.bool("isMyTurn") }
    /// Your fleet, and only yours.
    private var myShips: [[Int]] {
        (privateData["myShips"] as? [Any] ?? []).map {
            ($0 as? [Any] ?? []).compactMap { $0 as? Int }
        }
    }
    private var myShots: [Int: String] { shotMap("myShots") }
    private var incoming: [Int: String] { shotMap("incoming") }

    private func shotMap(_ key: String) -> [Int: String] {
        var out: [Int: String] = [:]
        for s in privateData.dicts(key) {
            if let c = s["cell"] as? Int, let r = s["result"] as? String { out[c] = r }
        }
        return out
    }

    private var shipCells: Set<Int> { Set(myShips.flatMap { $0 }) }

    @State private var showingFleet = false

    var body: some View {
        ControllerShell(title: "Battleship",
                        subtitle: isMyTurn ? "Your shot" : "Opponent's turn") {
            VStack(spacing: 12) {
                Picker("", selection: $showingFleet) {
                    Text("Fire").tag(false)
                    Text("My Fleet").tag(true)
                }
                .pickerStyle(.segmented).padding(.horizontal, 20).padding(.top, 12)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                         count: size), spacing: 4) {
                    ForEach(0..<(size * size), id: \.self) { cell in
                        let fill: Color = showingFleet
                            ? (incoming[cell] == "hit" ? .red
                               : incoming[cell] == "miss" ? .white.opacity(0.2)
                               : shipCells.contains(cell) ? .cyan : .blue.opacity(0.25))
                            : (myShots[cell] == "hit" ? .red
                               : myShots[cell] == "miss" ? .white.opacity(0.2)
                               : .blue.opacity(0.25))

                        Button(action: {
                            if !showingFleet && isMyTurn && myShots[cell] == nil {
                                onAction("fire", ["cell": cell])
                            }
                        }) {
                            RoundedRectangle(cornerRadius: 4).fill(fill)
                                .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                        .disabled(showingFleet || !isMyTurn || myShots[cell] != nil)
                    }
                }
                .padding(.horizontal, 20)

                Text(showingFleet ? "Your fleet — keep this hidden"
                                  : isMyTurn ? "Tap a square to fire" : "Waiting…")
                    .font(.caption)
                    .foregroundColor(showingFleet ? .orange : .white.opacity(0.45))
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Air Hockey

struct AirHockeyControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var width: Double { privateData.dbl("width", 100) }
    private var score: Int { privateData.int("score") }

    @State private var x: Double = 50
    /// Reported "super slow": a raw `DragGesture.onChanged` fires far faster
    /// than the server's shared action rate limiter (15/sec sustained --
    /// `ACTION_BURST`/`ACTION_WINDOW_SECONDS` in `socket_events.py`) allows,
    /// so most paddle updates during a drag were being silently dropped and
    /// the paddle only caught up to your finger in occasional jumps. This was
    /// the exact same failure mode already root-caused and fixed for Pong's
    /// gyro input -- the fix here is the same send-rate guard, just gating a
    /// touch drag instead of a gyro sample.
    @State private var lastSendTime: Double = 0

    var body: some View {
        ControllerShell(title: "Air Hockey", subtitle: "Score \(score)") {
            VStack(spacing: 18) {
                Text("Drag to move your paddle")
                    .font(.caption).foregroundColor(.white.opacity(0.45)).padding(.top, 20)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05))
                        RoundedRectangle(cornerRadius: 12).fill(Color.cyan)
                            .frame(width: 90, height: 60)
                            .offset(x: CGFloat(x / width) * (geo.size.width - 90))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            let t = min(max(0, value.location.x / geo.size.width), 1)
                            x = t * width
                            let now = Date().timeIntervalSince1970
                            // Same 0.083s (~12/sec) guard used for Pong's gyro
                            // send rate -- comfortably under the server's
                            // 15/sec sustained cap.
                            guard now - lastSendTime > 0.083 else { return }
                            lastSendTime = now
                            onAction("paddle", ["x": x])
                        }
                    )
                }
                .frame(height: 90).padding(.horizontal, 20)

                Spacer()
            }
        }
    }
}

// MARK: - Heist Escape

struct HeistEscapeControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var size: Int { privateData.int("size", 7) }
    private var position: Int { privateData.int("position") }
    private var exitCell: Int { privateData.int("exitCell") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var finished: Bool { privateData.bool("finished") }
    private var won: Bool { privateData.bool("won") }
    /// Only this player's slice of the wall map.
    private var myWalls: [[Int]] {
        (privateData["myWalls"] as? [Any] ?? []).map {
            ($0 as? [Any] ?? []).compactMap { $0 as? Int }
        }
    }

    private var wallSet: Set<[Int]> { Set(myWalls.map { $0.sorted() }) }

    private func hasWall(_ a: Int, _ b: Int) -> Bool {
        wallSet.contains([min(a, b), max(a, b)])
    }

    var body: some View {
        ControllerShell(title: "Heist Escape",
                        subtitle: "Your piece of the map", secondsLeft: seconds) {
            VStack(spacing: 14) {
                if finished {
                    WaitingState(systemIcon: won ? "party.popper.fill" : "exclamationmark.triangle.fill",
                                 text: won ? "Escaped!" : "Out of time")
                } else {
                    Text("Only you can see these walls — describe them")
                        .font(.caption).foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.top, 12)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3),
                                             count: size), spacing: 3) {
                        ForEach(0..<(size * size), id: \.self) { cell in
                            ZStack {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(cell == position ? Color.cyan.opacity(0.4)
                                          : cell == exitCell ? Color.green.opacity(0.35)
                                          : Color.white.opacity(0.06))
                                if cell == position { Image(systemName: "person.fill").font(.caption).foregroundColor(.white) }
                                else if cell == exitCell { Image(systemName: "door.left.hand.open").font(.caption).foregroundColor(.white) }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .trailing) {
                                if (cell % size) < size - 1, hasWall(cell, cell + 1) {
                                    Rectangle().fill(.red).frame(width: 3)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if cell + size < size * size, hasWall(cell, cell + size) {
                                    Rectangle().fill(.red).frame(height: 3)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    dpad
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var dpad: some View {
        VStack(spacing: 8) {
            arrow("up", "chevron.up")
            HStack(spacing: 8) {
                arrow("left", "chevron.left")
                arrow("down", "chevron.down")
                arrow("right", "chevron.right")
            }
        }
        .padding(.top, 6)
    }

    private func arrow(_ direction: String, _ icon: String) -> some View {
        Button(action: { onAction("move", ["direction": direction]) }) {
            Image(systemName: icon).font(.title2.bold()).foregroundColor(.white)
                .frame(width: 66, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ludo

struct LudoControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var isMyTurn: Bool { privateData.bool("isMyTurn") }
    private var die: Int { privateData.int("die") }
    private var canRoll: Bool { privateData.bool("canRoll") }
    private var tokens: [Int] { (privateData["myTokens"] as? [Any] ?? []).compactMap { $0 as? Int } }
    private var legalMoves: [Int] {
        (privateData["legalMoves"] as? [Any] ?? []).compactMap { $0 as? Int }
    }
    /// Same shape as the TV's "legal": where tapping a token would send it.
    private var legalDests: [(token: Int, dest: Int, destAbs: Int?)] {
        (privateData["legalDests"] as? [Any] ?? []).compactMap {
            guard let m = $0 as? [String: Any],
                  let t = m["token"] as? Int, let d = m["dest"] as? Int else { return nil }
            return (t, d, m["destAbs"] as? Int)
        }
    }
    private var seat: Int { privateData.int("seat") }
    private var currentPlayerName: String { privateData["currentPlayerName"] as? String ?? "" }

    private let seatColors: [Color] = [.red, .green, .yellow, .blue]

    /// Where a token sits right now, numbered exactly like the TV board.
    private func positionLabel(_ value: Int) -> String {
        if value < 0 { return "Yard" }
        if value >= 105 { return "Home" }
        if value >= 100 { return "Home \(value - 100 + 1) of 5" }
        return "Tile \((seat * 13 + value) % 52 + 1)"
    }

    /// Where tapping this token would send it -- matches the TV highlight.
    private func destLabel(token: Int) -> String? {
        guard let m = legalDests.first(where: { $0.token == token }) else { return nil }
        if let a = m.destAbs { return "moves to tile \(a + 1)" }
        if m.dest >= 105 { return "moves home" }
        return "moves to home \(m.dest - 100 + 1) of 5"
    }

    var body: some View {
        ControllerShell(title: "Ludo",
                        subtitle: isMyTurn ? (canRoll ? "Roll the dice" : "Pick a token")
                                           : (currentPlayerName.isEmpty ? "Waiting for your turn"
                                                                        : "\(currentPlayerName)'s turn")) {
            VStack(spacing: 20) {
                if !isMyTurn {
                    WaitingState(systemIcon: "hourglass",
                                 text: currentPlayerName.isEmpty ? "Not your turn yet"
                                                                  : "Waiting for \(currentPlayerName)",
                                 detail: "Watch the board")
                } else {
                    Button(action: { if canRoll { onAction("roll", [:]) } }) {
                        VStack(spacing: 6) {
                            Text(die > 0 ? "\(die)" : "–")
                                .font(.system(size: 76, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                            Text(canRoll ? "Tap to roll" : "Rolled")
                                .font(.caption).foregroundColor(.white.opacity(0.5))
                        }
                        .frame(width: 180, height: 180)
                        .background(Circle().fill(seatColors[seat % 4].opacity(canRoll ? 0.5 : 0.2)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRoll)
                    .padding(.top, 20)

                    if !canRoll {
                        VStack(spacing: 10) {
                            ForEach(Array(tokens.enumerated()), id: \.offset) { i, value in
                                let legal = legalMoves.contains(i)
                                ChoiceRow(text: "Token \(i + 1)",
                                          detail: legal ? (destLabel(token: i) ?? positionLabel(value))
                                                        : positionLabel(value),
                                          disabled: !legal) {
                                    onAction("move", ["token": i])
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        if legalMoves.isEmpty {
                            Text("No legal moves — passing")
                                .font(.caption).foregroundColor(.orange)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Carrom

struct CarromControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var canFlick: Bool { privateData.bool("canFlick") }
    private var strikerX: Double { privateData.dbl("strikerX", 50) }
    private var score: Int { privateData.int("score") }

    @State private var aim: CGSize = .zero
    @State private var position: Double = 50

    /// Drag back from the striker to aim; the pull length becomes the power,
    /// the same gesture people already expect from a real board. The shot
    /// flies opposite the pull (along the drawn aim line). Server convention:
    /// angle 0 = straight up the board, direction (sin a, -cos a).
    private var angle: Double { atan2(Double(-aim.width), Double(aim.height)) }
    private var power: Double { min(1, Double(hypot(aim.width, aim.height)) / 140) }

    var body: some View {
        ControllerShell(title: "Carrom", subtitle: canFlick ? "Your shot" : "Opponent's turn") {
            VStack(spacing: 16) {
                if !canFlick {
                    WaitingState(systemIcon: "hourglass", text: "Waiting for your turn",
                                 detail: "Score \(score)")
                } else {
                    Text("Slide to position, then pull back and release")
                        .font(.caption).foregroundColor(.white.opacity(0.45))
                        .multilineTextAlignment(.center).padding(.top, 16)

                    VStack(spacing: 6) {
                        Slider(value: $position, in: 15...85, step: 1)
                            .tint(.cyan).padding(.horizontal, 26)
                            .onChange(of: position) { v in onAction("position", ["x": v]) }
                        Text("Striker position").font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }

                    ZStack {
                        Circle().fill(Color(hex: "d9b382").opacity(0.25))
                            .frame(width: 220, height: 220)
                        Circle().fill(Color.cyan).frame(width: 54, height: 54)
                            .offset(x: aim.width * 0.35, y: aim.height * 0.35)

                        if power > 0.02 {
                            // Aim line: shows both direction and how hard it'll hit.
                            Path { p in
                                p.move(to: CGPoint(x: 110, y: 110))
                                p.addLine(to: CGPoint(x: 110 - aim.width * 0.7,
                                                      y: 110 - aim.height * 0.7))
                            }
                            .stroke(Color.yellow.opacity(0.8),
                                    style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                            .frame(width: 220, height: 220)
                        }
                    }
                    .frame(width: 220, height: 220)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture()
                            .onChanged { aim = $0.translation }
                            .onEnded { _ in
                                if power > 0.05 {
                                    onAction("flick", ["angle": angle, "power": power])
                                }
                                aim = .zero
                            }
                    )

                    Text("Power \(Int(power * 100))%")
                        .font(.headline).foregroundColor(.yellow)
                }
                Spacer(minLength: 0)
            }
            .onAppear { position = strikerX }
        }
    }
}

// MARK: - Teen Patti

struct TeenPattiControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var blind: Bool { privateData.bool("blind") }
    /// Empty while playing blind — the server withholds them until you look.
    private var cards: [(rank: Int, suit: String)] {
        privateData.dicts("cards").map {
            ($0["rank"] as? Int ?? 0, $0["suit"] as? String ?? "♠")
        }
    }
    private var chips: Int { privateData.int("chips") }
    private var pot: Int { privateData.int("pot") }
    private var callCost: Int { privateData.int("callCost") }
    private var canAct: Bool { privateData.bool("canAct") }
    private var folded: Bool { privateData.bool("folded") }

    private func label(_ rank: Int) -> String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        default: return "\(rank)"
        }
    }

    var body: some View {
        ControllerShell(title: "Teen Patti",
                        subtitle: "Chips \(chips) · Pot \(pot)") {
            VStack(spacing: 18) {
                if folded {
                    WaitingState(systemIcon: "door.left.hand.open", text: "You folded",
                                 detail: "Waiting for the hand to finish")
                } else {
                    HStack(spacing: 12) {
                        if blind {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.6))
                                    .frame(width: 74, height: 106)
                                    .overlay(Text("?").font(.largeTitle.bold())
                                        .foregroundColor(.white.opacity(0.7)))
                            }
                        } else {
                            ForEach(Array(cards.enumerated()), id: \.offset) { _, c in
                                VStack(spacing: 2) {
                                    Text(label(c.rank)).font(.title.bold())
                                    Text(c.suit).font(.title2)
                                }
                                .foregroundColor(c.suit == "♥" || c.suit == "♦" ? .red : .black)
                                .frame(width: 74, height: 106)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                            }
                        }
                    }
                    .padding(.top, 24)

                    if blind {
                        Text("Playing blind — half price to stay in")
                            .font(.caption).foregroundColor(.orange)
                        BigButton(title: "See My Cards", systemImage: "eye.fill", tint: .yellow) {
                            onAction("see", [:])
                        }
                    }

                    VStack(spacing: 10) {
                        BigButton(title: "Call  (\(callCost))", tint: .cyan, enabled: canAct) {
                            onAction("call", [:])
                        }
                        BigButton(title: "Raise  (\(callCost * 2))", tint: .green, enabled: canAct) {
                            onAction("bet", [:])
                        }
                        BigButton(title: "Fold", tint: .red, enabled: canAct) {
                            onAction("fold", [:])
                        }
                    }
                    .padding(.top, 6)

                    if !canAct {
                        Text("Waiting for your turn…")
                            .font(.caption).foregroundColor(.white.opacity(0.4))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Solo games (phone acts as an optional second controller)

/// Directional controller used by Neon Snake when a phone is present. The
/// TV's Siri Remote sends the same actions. (Simon Says used to share this
/// too, but its four directions are really four colors on the TV -- see
/// SimonSaysControllerView below.)
struct DPadControllerView: View {
    let title: String
    let actionName: String
    let payloadKey: String
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    var body: some View {
        ControllerShell(title: title,
                        subtitle: privateData.bool("isOut") ? "You're out"
                                                            : "Score \(privateData.int("score"))") {
            VStack(spacing: 14) {
                Spacer()
                arrow("up", "chevron.up")
                HStack(spacing: 14) {
                    arrow("left", "chevron.left")
                    arrow("down", "chevron.down")
                    arrow("right", "chevron.right")
                }
                Spacer()
                Text("You can also use the Apple TV remote")
                    .font(.caption).foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 20)
            }
        }
    }

    private func arrow(_ direction: String, _ icon: String) -> some View {
        Button(action: { onAction(actionName, [payloadKey: direction]) }) {
            Image(systemName: icon).font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 92, height: 78)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.09)))
        }
        .buttonStyle(.plain)
    }
}

/// Colored-pad controller for Simon Says. Reported directly: reusing
/// DPadControllerView's plain white arrows here meant a phone player had to
/// remember "up = green, right = red, down = yellow, left = blue" instead of
/// just tapping the color they watched flash -- exactly backwards for a game
/// that's supposed to be easier on the phone. Same cross layout and same
/// four colors as TVSimonSaysBoardView's `pad(_:)`/`colors`, so the two
/// screens read as the same game.
///
/// Also (unlike the plain D-pad) gates on turn/phase the way the TV's own
/// `.remoteDPad` handler does, so a phone player sees "Watch the
/// sequence…" / "Your turn" instead of five always-tappable buttons that
/// silently no-op server-side outside the input phase.
struct SimonSaysControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var phase: String { privateData.str("phase") }
    private var isMyTurn: Bool { privateData.bool("isMyTurn") }
    private var isOut: Bool { privateData.bool("isOut") }
    private var round: Int { privateData.int("round") }

    private var canTap: Bool { isMyTurn && phase == "input" && !isOut }

    private let colors: [String: Color] = [
        "up": .green, "right": .red, "down": .yellow, "left": .blue,
    ]

    var body: some View {
        ControllerShell(
            title: "Simon Says",
            subtitle: isOut ? "You're out"
                : phase == "show" ? "Watch the sequence…"
                : isMyTurn ? "Your turn — round \(round)"
                : "Waiting for your turn"
        ) {
            VStack(spacing: 14) {
                Spacer()
                pad("up")
                HStack(spacing: 14) { pad("left"); pad("right") }
                pad("down")
                Spacer()
                Text("You can also use the Apple TV remote")
                    .font(.caption).foregroundColor(.white.opacity(0.35))
                    .padding(.bottom, 20)
            }
        }
    }

    private func pad(_ direction: String) -> some View {
        Button(action: { onAction("pad", ["pad": direction]) }) {
            RoundedRectangle(cornerRadius: 20)
                .fill((colors[direction] ?? .gray).opacity(canTap ? 0.85 : 0.25))
                .frame(width: 100, height: 84)
        }
        .buttonStyle(.plain)
        .disabled(!canTap)
    }
}

/// Swipe controller for 2048.
struct SwipeControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    var body: some View {
        ControllerShell(title: "2048",
                        subtitle: "Score \(privateData.int("score"))") {
            VStack(spacing: 16) {
                Spacer()
                RoundedRectangle(cornerRadius: 24)
                    .fill(.white.opacity(0.06))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "hand.draw").font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.4))
                            Text("Swipe anywhere").font(.headline)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    )
                    .frame(height: 320)
                    .padding(.horizontal, 24)
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                let direction = abs(dx) > abs(dy)
                                    ? (dx > 0 ? "right" : "left")
                                    : (dy > 0 ? "down" : "up")
                                onAction("swipe", ["direction": direction])
                            }
                    )
                Spacer()
            }
        }
    }
}

/// Paddle controller for Brick Breaker.
struct PaddleControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var width: Double { privateData.dbl("width", 100) }

    var body: some View {
        ControllerShell(title: "Brick Breaker",
                        subtitle: "Score \(privateData.int("score")) · \(privateData.int("lives")) lives") {
            VStack(spacing: 16) {
                Spacer()
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.06))
                        .overlay(Text("Slide to move the paddle")
                            .font(.headline).foregroundColor(.white.opacity(0.4)))
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0).onChanged { value in
                                let t = Double(min(max(0, value.location.x / geo.size.width), 1))
                                onAction("paddle", ["x": t * width])
                            }
                        )
                }
                .frame(height: 220).padding(.horizontal, 24)
                Spacer()
            }
        }
    }
}

/// Text controller for Atlas.
struct AtlasControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    private var letter: String { privateData.str("letter") }
    private var isMyTurn: Bool { privateData.bool("isMyTurn") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var error: String { privateData.str("error") }
    private var isOut: Bool { privateData.bool("isOut") }

    @State private var place = ""

    var body: some View {
        ControllerShell(title: "Atlas",
                        subtitle: isOut ? "You're out" : (isMyTurn ? "Your turn" : "Waiting"),
                        secondsLeft: isMyTurn ? seconds : nil) {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("STARTS WITH").font(.caption.bold()).tracking(3)
                        .foregroundColor(.white.opacity(0.4))
                    Text(letter)
                        .font(.system(size: 76, weight: .heavy, design: .rounded))
                        .foregroundColor(.cyan)
                }
                .padding(.top, 24)

                if isOut {
                    WaitingState(systemIcon: "globe", text: "Out of the chain")
                } else if isMyTurn {
                    AnswerField(placeholder: "Place name", text: $place)
                    if !error.isEmpty {
                        Text(error).font(.caption).foregroundColor(.orange)
                    }
                    BigButton(title: "Submit", systemImage: "paperplane.fill",
                              enabled: !place.trimmingCharacters(in: .whitespaces).isEmpty) {
                        onAction("answer", ["place": place])
                        place = ""
                    }
                } else {
                    WaitingState(systemIcon: "hourglass", text: "Someone else's turn")
                }
                Spacer(minLength: 0)
            }
        }
    }
}
