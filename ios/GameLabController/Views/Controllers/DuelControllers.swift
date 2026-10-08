import SwiftUI

/// Phone controllers for the duel, co-op and solo games.

// MARK: - Shared pieces (Phone Play look)

/// A rounded status capsule for hints and turn status.
private struct DuelHint: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = PhonePlayDesign.text2

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Text(text)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(tint.opacity(0.14)))
        .padding(.horizontal, 20)
    }
}

/// One arrow of a D-pad: a surface tile that squashes under the thumb.
private struct DuelArrowButton: View {
    let icon: String
    var width: CGFloat = 92
    var height: CGFloat = 78
    var tint: Color = PhonePlayDesign.cyan
    let action: () -> Void

    var body: some View {
        Button(action: {
            PhonePlayHaptics.tap()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: min(30, height * 0.4), weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(PhonePlayDesign.gradient([PhonePlayDesign.surface2, PhonePlayDesign.surface]))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .strokeBorder(tint.opacity(0.3), lineWidth: 1.5)
                )
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

private extension View {
    /// The standard Phone Play surface card behind a panel.
    func duelCard(_ fill: Color = PhonePlayDesign.surface) -> some View {
        background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(fill)
        )
    }
}

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
                    strikeRow
                        .padding(.top, 14)

                    if finished {
                        WaitingState(systemIcon: won ? "heart.fill" : "burst.fill",
                                     text: won ? "Defused!" : "Boom.")
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else if isDefuser {
                        defuserControls
                    } else {
                        manualPages
                    }
                }
                .padding(.bottom, 24)
                .animation(PhonePlayDesign.pop, value: strikes)
                .animation(PhonePlayDesign.pop, value: finished)
                .animation(PhonePlayDesign.pop, value: moduleType)
            }
        }
    }

    /// Fixed: each mark carried two foreground colours and the first one
    /// always won, so a strike never actually turned red.
    private var strikeRow: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                let hit: Bool = i < strikes
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(hit ? .white : .white.opacity(0.2))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(hit ? PhonePlayDesign.red : PhonePlayDesign.surface))
                    .shadow(color: hit ? PhonePlayDesign.red.opacity(0.5) : .clear, radius: 8)
                    .scaleEffect(hit ? 1.0 : 0.9)
            }
        }
    }

    @ViewBuilder
    private var defuserControls: some View {
        VStack(spacing: 14) {
            DuelHint(text: "Describe what you see — they have the instructions",
                     systemImage: "bubble.left.and.bubble.right.fill",
                     tint: PhonePlayDesign.orange)

            switch moduleType {
            case "wires":
                let wires = (module["wires"] as? [Any] ?? []).compactMap { $0 as? String }
                VStack(spacing: 10) {
                    ForEach(Array(wires.enumerated()), id: \.offset) { i, w in
                        Button(action: {
                            PhonePlayHaptics.rigid()
                            onAction("cut", ["index": i])
                        }) {
                            HStack(spacing: 14) {
                                Text("\(i + 1)")
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .foregroundColor(PhonePlayDesign.text3)
                                    .frame(width: 26)
                                Capsule()
                                    .fill(wireColor(w))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(w == "black" ? 0.45 : 0),
                                                                    lineWidth: 1))
                                    .frame(height: 14)
                                    .shadow(color: wireColor(w).opacity(0.45), radius: 6)
                                HStack(spacing: 4) {
                                    Image(systemName: "scissors")
                                    Text("CUT")
                                }
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(PhonePlayDesign.red.opacity(0.85)))
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                    .fill(PhonePlayDesign.surface)
                            )
                        }
                        .buttonStyle(PhonePlayPressStyle())
                    }
                }
                .padding(.horizontal, 20)

            case "button":
                let colour: String = module["colour"] as? String ?? ""
                VStack(spacing: 20) {
                    Circle()
                        .fill(PhonePlayDesign.gradient([wireColor(colour), wireColor(colour).opacity(0.7)]))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 3))
                        .frame(width: 150, height: 150)
                        .shadow(color: wireColor(colour).opacity(0.45), radius: 20, y: 8)
                        .overlay(Text(module["label"] as? String ?? "")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(colour == "white" ? .black : .white))
                        .phonePlayIdle(scale: 0.03, duration: 1.2)
                    HStack(spacing: 12) {
                        PhonePlayBigButton(title: "TAP", symbol: "hand.tap.fill",
                                           colors: [PhonePlayDesign.green, PhonePlayDesign.green.opacity(0.65)]) {
                            onAction("button", ["press": "tap"])
                        }
                        PhonePlayBigButton(title: "HOLD", symbol: "hand.raised.fill",
                                           colors: [PhonePlayDesign.orange, PhonePlayDesign.orange.opacity(0.65)]) {
                            onAction("button", ["press": "hold"])
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 6)

            case "symbols":
                let symbols = (module["symbols"] as? [Any] ?? []).compactMap { $0 as? String }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { i, s in
                        Button(action: {
                            PhonePlayHaptics.tap()
                            onAction("symbol", ["index": i])
                        }) {
                            Text(s)
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 22)
                                .background(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .fill(PhonePlayDesign.gradient([PhonePlayDesign.surface2, PhonePlayDesign.surface]))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                        .strokeBorder(PhonePlayDesign.purple.opacity(0.3), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(PhonePlayPressStyle())
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
            VStack(spacing: 6) {
                Text("DEFUSAL MANUAL")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundColor(PhonePlayDesign.cyan)
                Text("You can't see the bomb. Read this out loud.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(manual, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .duelCard()
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(PhonePlayDesign.cyan.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    /// Fixed: "black" wires used to fall through to grey, so the defuser
    /// would describe a grey wire the manual never mentions.
    private func wireColor(_ name: String) -> Color {
        switch name {
        case "red": return PhonePlayDesign.red
        case "blue": return PhonePlayDesign.blue
        case "yellow": return PhonePlayDesign.yellow
        case "white": return .white
        case "black": return Color(hex: "121218")
        default: return PhonePlayDesign.text3
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
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    PhonePlayChip(title: "Fire", selected: !showingFleet,
                                  colors: [PhonePlayDesign.red, PhonePlayDesign.orange]) {
                        showingFleet = false
                    }
                    PhonePlayChip(title: "My Fleet", selected: showingFleet,
                                  colors: [PhonePlayDesign.cyan, PhonePlayDesign.blue]) {
                        showingFleet = true
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                         count: max(size, 1)), spacing: 4) {
                    ForEach(0..<(size * size), id: \.self) { cell in
                        let result: String? = showingFleet ? incoming[cell] : myShots[cell]
                        let fill: Color = result == "hit" ? PhonePlayDesign.red
                            : result == "miss" ? Color.white.opacity(0.12)
                            : (showingFleet && shipCells.contains(cell)) ? PhonePlayDesign.cyan.opacity(0.85)
                            : PhonePlayDesign.blue.opacity(0.22)

                        Button(action: {
                            if !showingFleet && isMyTurn && myShots[cell] == nil {
                                PhonePlayHaptics.rigid()
                                onAction("fire", ["cell": cell])
                            }
                        }) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(fill)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if result == "hit" {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                    } else if result == "miss" {
                                        Circle()
                                            .fill(Color.white.opacity(0.55))
                                            .frame(width: 6, height: 6)
                                    }
                                }
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .disabled(showingFleet || !isMyTurn || myShots[cell] != nil)
                    }
                }
                .padding(10)
                .duelCard()
                .padding(.horizontal, 16)

                DuelHint(text: showingFleet ? "Your fleet — keep this hidden"
                                            : isMyTurn ? "Tap a square to fire" : "Waiting…",
                         systemImage: showingFleet ? "eye.slash.fill" : (isMyTurn ? "scope" : "hourglass"),
                         tint: showingFleet ? PhonePlayDesign.orange
                                            : (isMyTurn ? PhonePlayDesign.red : PhonePlayDesign.text2))
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: showingFleet)
            .animation(PhonePlayDesign.pop, value: isMyTurn)
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
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    DuelHint(text: "Only you can see these walls — describe them",
                             systemImage: "eye.fill", tint: PhonePlayDesign.orange)
                        .padding(.top, 12)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3),
                                             count: max(size, 1)), spacing: 3) {
                        ForEach(0..<(size * size), id: \.self) { cell in
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(cell == position ? PhonePlayDesign.cyan.opacity(0.5)
                                          : cell == exitCell ? PhonePlayDesign.green.opacity(0.4)
                                          : PhonePlayDesign.surface2)
                                if cell == position {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                } else if cell == exitCell {
                                    Image(systemName: "door.left.hand.open")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .trailing) {
                                if (cell % size) < size - 1, hasWall(cell, cell + 1) {
                                    Rectangle().fill(PhonePlayDesign.red).frame(width: 3)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if cell + size < size * size, hasWall(cell, cell + size) {
                                    Rectangle().fill(PhonePlayDesign.red).frame(height: 3)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .duelCard()
                    .padding(.horizontal, 16)
                    .animation(PhonePlayDesign.pop, value: position)

                    dpad
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: finished)
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
        DuelArrowButton(icon: icon, width: 70, height: 58) {
            onAction("move", ["direction": direction])
        }
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

    private let seatColors: [Color] = [PhonePlayDesign.red, PhonePlayDesign.green,
                                       PhonePlayDesign.yellow, PhonePlayDesign.blue]

    /// Never indexes out of range, even for an unexpected negative seat.
    private var seatColor: Color { seatColors[((seat % 4) + 4) % 4] }

    /// Absolute track cells that are safe: every seat's start square plus the
    /// star squares. Matches LudoEngine.SAFE_ABS and the TV board markers.
    private let safeAbs: Set<Int> = [0, 13, 26, 39, 8, 21, 34, 47]

    /// Where a token sits right now, numbered exactly like the TV board.
    private func positionLabel(_ value: Int) -> String {
        if value < 0 { return "Yard" }
        if value >= 105 { return "Home" }
        if value >= 100 { return "Home \(value - 100 + 1) of 5" }
        let abs = (seat * 13 + value) % 52
        let safe = safeAbs.contains(abs) ? " · safe" : ""
        return "Tile \(abs + 1)\(safe)"
    }

    /// Where tapping this token would send it -- matches the TV highlight.
    private func destLabel(token: Int) -> String? {
        guard let m = legalDests.first(where: { $0.token == token }) else { return nil }
        if let a = m.destAbs {
            let safe = safeAbs.contains(a) ? " · safe" : ""
            return "moves to tile \(a + 1)\(safe)"
        }
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
                        .transition(.opacity)
                } else {
                    Button(action: {
                        if canRoll {
                            PhonePlayHaptics.thump()
                            onAction("roll", [:])
                        }
                    }) {
                        VStack(spacing: 6) {
                            Text(die > 0 ? "\(die)" : "–")
                                .font(.system(size: 76, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .contentTransition(.numericText())
                            Text(canRoll ? "Tap to roll" : "Rolled")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .frame(width: 180, height: 180)
                        .background(
                            Circle().fill(PhonePlayDesign.gradient([seatColor.opacity(canRoll ? 0.9 : 0.35),
                                                                    seatColor.opacity(canRoll ? 0.5 : 0.15)]))
                        )
                        .overlay(Circle().strokeBorder(Color.white.opacity(canRoll ? 0.3 : 0.1), lineWidth: 2))
                        .shadow(color: seatColor.opacity(canRoll ? 0.45 : 0), radius: 20, y: 8)
                    }
                    .buttonStyle(PhonePlayPressStyle())
                    .disabled(!canRoll)
                    .phonePlayIdle(scale: canRoll ? 0.035 : 0, duration: 1.1)
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))

                        if legalMoves.isEmpty {
                            DuelHint(text: "No legal moves — passing", systemImage: "forward.fill",
                                     tint: PhonePlayDesign.orange)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(PhonePlayDesign.pop, value: isMyTurn)
            .animation(PhonePlayDesign.pop, value: canRoll)
            .animation(PhonePlayDesign.pop, value: die)
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

    /// A gentle fan: the outer cards tilt and drop a little.
    private func fanAngle(_ i: Int, of count: Int) -> Double {
        Double(i) * 7 - Double(max(count - 1, 0)) * 3.5
    }

    var body: some View {
        ControllerShell(title: "Teen Patti",
                        subtitle: "Chips \(chips) · Pot \(pot)") {
            ScrollView {
                VStack(spacing: 18) {
                    if folded {
                        WaitingState(systemIcon: "door.left.hand.open", text: "You folded",
                                     detail: "Waiting for the hand to finish")
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 10) {
                            if blind {
                                ForEach(0..<3, id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(PhonePlayDesign.gradient([PhonePlayDesign.purple, PhonePlayDesign.indigo]))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)
                                        )
                                        .overlay(Text("?")
                                            .font(.system(size: 34, weight: .black, design: .rounded))
                                            .foregroundColor(.white.opacity(0.75)))
                                        .frame(width: 74, height: 106)
                                        .shadow(color: PhonePlayDesign.purple.opacity(0.35), radius: 10, y: 5)
                                        .rotationEffect(.degrees(fanAngle(i, of: 3)))
                                        .offset(y: CGFloat(abs(fanAngle(i, of: 3))))
                                }
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                            } else {
                                ForEach(Array(cards.enumerated()), id: \.offset) { i, c in
                                    VStack(spacing: 2) {
                                        Text(label(c.rank))
                                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                                        Text(c.suit)
                                            .font(.system(size: 24, weight: .regular, design: .rounded))
                                    }
                                    .foregroundColor(c.suit == "♥" || c.suit == "♦"
                                                     ? GamePieceColors.cardRedInk
                                                     : GamePieceColors.cardBlackInk)
                                    .frame(width: 74, height: 106)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(PhonePlayDesign.gradient([GamePieceColors.faceWhite,
                                                                        GamePieceColors.faceWhiteEdge])))
                                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                                    .rotationEffect(.degrees(fanAngle(i, of: cards.count)))
                                    .offset(y: CGFloat(abs(fanAngle(i, of: cards.count))))
                                }
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                            }
                        }
                        .padding(.top, 24)
                        .padding(.bottom, 6)

                        if blind {
                            DuelHint(text: "Playing blind — half price to stay in",
                                     systemImage: "eye.slash.fill", tint: PhonePlayDesign.orange)
                            BigButton(title: "See My Cards", systemImage: "eye.fill", tint: PhonePlayDesign.yellow) {
                                onAction("see", [:])
                            }
                        }

                        VStack(spacing: 10) {
                            BigButton(title: "Call  (\(callCost))", tint: PhonePlayDesign.cyan, enabled: canAct) {
                                onAction("call", [:])
                            }
                            BigButton(title: "Raise  (\(callCost * 2))", tint: PhonePlayDesign.green, enabled: canAct) {
                                onAction("bet", [:])
                            }
                            PhonePlayGhostButton(title: "Fold", symbol: "xmark") {
                                onAction("fold", [:])
                            }
                            .disabled(!canAct)
                            .opacity(canAct ? 1 : 0.4)
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 6)

                        if !canAct {
                            DuelHint(text: "Waiting for your turn…", systemImage: "hourglass")
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(PhonePlayDesign.pop, value: blind)
                .animation(PhonePlayDesign.pop, value: folded)
                .animation(PhonePlayDesign.pop, value: canAct)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Solo games (phone acts as an optional second controller)

