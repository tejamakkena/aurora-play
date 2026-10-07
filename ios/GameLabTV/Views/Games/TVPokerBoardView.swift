import SwiftUI

// MARK: - Poker Board
//
// A broadcast-style Texas Hold'em table drawn entirely in SwiftUI: a lit
// emerald felt oval inside a black leather rail, every player on a seat pod
// around it (avatar token in their colour, name, counting chip stack, the
// dealer/blind buttons and a countdown ring on whoever is acting), bets as
// chip piles that slide in from the seat and sweep into the pot, community
// cards dealt from the dealer spot and flipped in 3D (flop in sequence, then
// turn, then river), and a showdown that flips the hole cards, lifts the
// winning five, names the hand and sweeps the pot to the winner, followed by
// a short standings card before the next deal.
//
// Everything is laid out on a fixed 1920x1080 stage (scaled to fit) so every
// chip flight, card and seat pod lands at an exact, known point -- the
// reason this replaced the SceneKit table, whose moving camera could never
// line a HUD up with the felt. `PokerCinematicBoardSceneView` is no longer
// used by this board but still compiles against `PokerBoardState`.
//
// Data: `PokerEngine.public_state()` in games/native_hub/engines/legacy_cards.py.

struct TVPokerBoardView: View {
    let room: Room
    @StateObject private var vm = PokerBoardViewModel()

    var body: some View {
        GeometryReader { geo in
            let scale: CGFloat = min(geo.size.width / PKTStage.width, geo.size.height / PKTStage.height)
            PKTStageView(vm: vm)
                .frame(width: PKTStage.width, height: PKTStage.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(hex: "040507"))
        .ignoresSafeArea()
        .onAppear { vm.bind(roomCode: room.code) }
    }
}

// MARK: - State

struct PokerSeat: Identifiable, Equatable {
    let id: String
    let name: String
    let chips: Int
    let currentBet: Int
    let status: String  // "active", "folded", "all-in"
    let isCurrentTurn: Bool
}

struct PokerShowdownHand: Equatable {
    let playerID: String
    let name: String
    let cards: [String]
    let handName: String
    let bestCards: [String]
    let isWinner: Bool
}

struct PokerLastAction: Equatable {
    let seq: Int
    let playerID: String
    let name: String
    /// "fold", "check", "call", "bet", "raise" or "allIn".
    let action: String
    /// Call: chips paid. Bet/raise/all-in: the player's total for the street.
    let amount: Int
}

struct PokerHandResult: Equatable {
    let handNumber: Int
    let winnerIDs: [String]
    let winnerNames: [String]
    let amount: Int
    let handName: String
    let winningCards: [String]
}

struct PokerBoardState {
    var communityCards: [String] = []
    var pot = 0
    var phase = "preflop"
    var playerSeats: [PokerSeat] = []
    /// `base_public()`'s "winner": the single winner of the hand just
    /// finished (nil on a split pot or while a hand is in progress).
    var winnerID: String?
    var handNumber = 0
    var maxHands = 0
    var lastHand: PokerHandResult?
    var showdown: [PokerShowdownHand] = []
    var dealerID: String?
    var smallBlindID: String?
    var bigBlindID: String?
    var currentBet = 0
    var bigBlind = 20
    var lastAction: PokerLastAction?
    var secondsLeft = 0
    var turnSeconds = 45

    var isShowdown: Bool { phase == "showdown" }

    mutating func update(from data: [String: AnyCodable]) {
        if let v = Self.int(data["handNumber"]?.value) { handNumber = v }
        if let v = Self.int(data["maxHands"]?.value) { maxHands = v }
        if let v = Self.int(data["pot"]?.value) { pot = v }
        if let v = data["phase"]?.value as? String { phase = v }
        if let v = data["communityCards"]?.value as? [Any] {
            communityCards = v.compactMap { $0 as? String }
        }
        if let field = data["winner"] { winnerID = field.value as? String }
        if let v = Self.int(data["currentBet"]?.value) { currentBet = v }
        if let v = Self.int(data["bigBlind"]?.value), v > 0 { bigBlind = v }
        if let v = Self.int(data["secondsLeft"]?.value) { secondsLeft = v }
        if let v = Self.int(data["turnSeconds"]?.value), v > 0 { turnSeconds = v }
        if let field = data["dealerID"] { dealerID = field.value as? String }
        if let field = data["smallBlindID"] { smallBlindID = field.value as? String }
        if let field = data["bigBlindID"] { bigBlindID = field.value as? String }
        if let field = data["lastAction"] { lastAction = Self.parseAction(field.value) }
        if let field = data["lastHand"] { lastHand = Self.parseResult(field.value) }
        if let v = data["showdown"]?.value as? [Any] { showdown = Self.parseShowdown(v) }
        if let v = data["players"]?.value as? [Any] { playerSeats = Self.parseSeats(v) }
    }

    private static func int(_ any: Any?) -> Int? {
        if let v = any as? Int { return v }
        if let v = any as? Double { return Int(v) }
        return nil
    }

    private static func strings(_ any: Any?) -> [String] {
        guard let list = any as? [Any] else { return [] }
        return list.compactMap { $0 as? String }
    }

    private static func parseSeats(_ raw: [Any]) -> [PokerSeat] {
        var seats: [PokerSeat] = []
        for entry in raw {
            guard let d = entry as? [String: Any],
                  let id = d["id"] as? String else { continue }
            seats.append(PokerSeat(id: id,
                                   name: d["name"] as? String ?? "Player",
                                   chips: int(d["chips"]) ?? 0,
                                   currentBet: int(d["currentBet"]) ?? 0,
                                   status: d["status"] as? String ?? "active",
                                   isCurrentTurn: d["isCurrentTurn"] as? Bool ?? false))
        }
        return seats
    }

    private static func parseShowdown(_ raw: [Any]) -> [PokerShowdownHand] {
        var hands: [PokerShowdownHand] = []
        for entry in raw {
            guard let d = entry as? [String: Any],
                  let id = d["playerID"] as? String else { continue }
            hands.append(PokerShowdownHand(playerID: id,
                                           name: d["name"] as? String ?? "",
                                           cards: strings(d["cards"]),
                                           handName: d["handName"] as? String ?? "",
                                           bestCards: strings(d["bestCards"]),
                                           isWinner: d["isWinner"] as? Bool ?? false))
        }
        return hands
    }

    private static func parseAction(_ raw: Any) -> PokerLastAction? {
        guard let d = raw as? [String: Any],
              let seq = int(d["seq"]),
              let id = d["playerID"] as? String else { return nil }
        return PokerLastAction(seq: seq, playerID: id,
                               name: d["name"] as? String ?? "",
                               action: d["action"] as? String ?? "",
                               amount: int(d["amount"]) ?? 0)
    }

    private static func parseResult(_ raw: Any) -> PokerHandResult? {
        guard let d = raw as? [String: Any] else { return nil }
        return PokerHandResult(handNumber: int(d["handNumber"]) ?? 0,
                               winnerIDs: strings(d["winnerIDs"]),
                               winnerNames: strings(d["winnerNames"]),
                               amount: int(d["amount"]) ?? 0,
                               handName: d["handName"] as? String ?? "",
                               winningCards: strings(d["winningCards"]))
    }
}

/// How far into the end-of-hand sequence the table is. The server holds a
/// finished hand on screen for six seconds; the view model walks these
/// stages inside that window.
enum PokerShowdownStage: Int, Comparable {
    case none = 0
    case reveal
    case highlight
    case sweep
    case scoreboard

    static func < (lhs: PokerShowdownStage, rhs: PokerShowdownStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum PokerChipAnchor: Equatable {
    case seat(String)
    case bet(String)
    case pot
}

struct PokerChipFlight: Identifiable, Equatable {
    let id: Int
    let from: PokerChipAnchor
    let to: PokerChipAnchor
    let chips: Int
    let delay: Double
    let tier: Int
}

struct PokerCallout: Equatable {
    let id: Int
    let playerID: String
    let text: String
    let isAllIn: Bool
    let amount: Int
    let name: String
}

/// Community-card reveal timing, shared by the cards themselves and the
/// showdown sequencer so "highlight the winning five" waits for the board.
enum PokerReveal {
    /// Seconds after the batch arrives at which card `index` starts dealing,
    /// when cards `from..<count` arrived together: flop cards 0.22s apart,
    /// then a longer beat before the turn and again before the river.
    static func delay(index: Int, from: Int) -> Double {
        var t: Double = 0.25
        var j: Int = from
        while j < index {
            t += j < 2 ? 0.22 : 0.85
            j += 1
        }
        return t
    }

    /// Seconds until the last card of the batch is face up.
    static func finishTime(from: Int, count: Int) -> Double {
        guard count > from else { return 0 }
        return delay(index: count - 1, from: from) + 0.35 + 0.55
    }
}

@MainActor final class PokerBoardViewModel: ObservableObject {
    @Published private(set) var state = PokerBoardState()
    @Published private(set) var stage: PokerShowdownStage = .none
    /// Community cards below this index were already on the table before
    /// the latest push, so they render face up without a deal animation.
    @Published private(set) var revealFrom = 0
    @Published private(set) var flights: [PokerChipFlight] = []
    @Published private(set) var callout: PokerCallout?
    @Published private(set) var allInFlash: PokerCallout?
    /// Each player's latest action on the current street, for their pod.
    @Published private(set) var seatActions: [String: PokerLastAction] = [:]
    /// Pre-award stacks for the winners, shown until the pot sweeps over.
    @Published private(set) var heldChips: [String: Int] = [:]
    @Published private(set) var heldPot: Int?
    /// Stacks at the start of the hand (empty when the TV joined mid-hand).
    @Published private(set) var handStartChips: [String: Int] = [:]
    @Published private(set) var turnDeadline: Date?
    @Published private(set) var sweepCount = 0

    private let socket = GameSocketManager.shared
    private var hasState = false
    private var flightCounter = 0
    private var sequenceToken = 0
    private var calloutToken = 0

    func bind(roomCode: String) {
        socket.on(.gameState) { [weak self] (r: GameStateResponse) in
            guard let self, r.roomCode == roomCode else { return }
            self.ingest(r.boardState)
        }
    }

    /// The pot figure to show: held at its pre-award value through the
    /// showdown reveal, then zero once it has swept to the winner.
    var displayPot: Int {
        if state.isShowdown {
            if stage >= .sweep { return 0 }
            return heldPot ?? 0
        }
        return state.pot
    }

    func displayChips(for seat: PokerSeat) -> Int {
        heldChips[seat.id] ?? seat.chips
    }

    // MARK: Diffing pushes into events

    private func ingest(_ data: [String: AnyCodable]) {
        let old: PokerBoardState = state
        var next: PokerBoardState = old
        next.update(from: data)
        let first: Bool = !hasState
        hasState = true

        if first {
            revealFrom = next.communityCards.count
            if next.isShowdown {
                stage = .highlight
            } else if next.phase == "preflop" {
                handStartChips = Self.stacksIncludingBets(next.playerSeats)
            }
        } else if next.handNumber != old.handNumber {
            startNewHand(next)
        } else {
            diffWithinHand(old: old, next: next)
        }

        updateTurnClock(old: old, next: next, first: first)
        state = next
    }

    private func startNewHand(_ next: PokerBoardState) {
        sequenceToken += 1
        stage = .none
        heldChips = [:]
        heldPot = nil
        seatActions = [:]
        revealFrom = 0
        handStartChips = Self.stacksIncludingBets(next.playerSeats)
        // The blinds slide out once the hole cards have been dealt.
        for seat in next.playerSeats where seat.currentBet > 0 {
            addFlight(from: .seat(seat.id), to: .bet(seat.id), chips: 2, delay: 0.9,
                      tier: Self.tier(for: seat.currentBet, bigBlind: next.bigBlind))
        }
    }

    private func diffWithinHand(old: PokerBoardState, next: PokerBoardState) {
        let newCount: Int = next.communityCards.count
        let oldCount: Int = old.communityCards.count
        if newCount > oldCount {
            revealFrom = oldCount
        } else if newCount < oldCount {
            revealFrom = 0
        }

        let action: PokerLastAction? = next.lastAction
        let isNewAction: Bool = action != nil && action?.seq != old.lastAction?.seq
        let streetChanged: Bool = next.phase != old.phase && !old.isShowdown

        if streetChanged {
            // Everything in front of the players slides into the middle.
            for seat in old.playerSeats where seat.currentBet > 0 {
                addFlight(from: .bet(seat.id), to: .pot, chips: 3, delay: 0.1,
                          tier: Self.tier(for: seat.currentBet, bigBlind: next.bigBlind))
            }
            // The action that closed the street went straight in.
            if let action, isNewAction, action.amount > 0, action.action != "fold" {
                addFlight(from: .seat(action.playerID), to: .pot, chips: 2, delay: 0.1,
                          tier: Self.tier(for: action.amount, bigBlind: next.bigBlind))
            }
            seatActions = [:]
        } else if next.phase == old.phase {
            for seat in next.playerSeats {
                let before: Int = old.playerSeats.first(where: { $0.id == seat.id })?.currentBet ?? 0
                if seat.currentBet > before {
                    addFlight(from: .seat(seat.id), to: .bet(seat.id), chips: 3, delay: 0,
                              tier: Self.tier(for: seat.currentBet, bigBlind: next.bigBlind))
                }
            }
        }

        if let action, isNewAction {
            announce(action, recordOnSeat: !streetChanged)
        }

        if next.isShowdown && !old.isShowdown {
            beginShowdown(next)
        }
    }

    private func updateTurnClock(old: PokerBoardState, next: PokerBoardState, first: Bool) {
        let currentID: String? = next.playerSeats.first(where: { $0.isCurrentTurn })?.id
        let oldID: String? = old.playerSeats.first(where: { $0.isCurrentTurn })?.id
        guard !next.isShowdown, currentID != nil, next.secondsLeft > 0 else {
            turnDeadline = nil
            return
        }
        let expected: Date = Date().addingTimeInterval(Double(next.secondsLeft))
        if first || currentID != oldID || next.handNumber != old.handNumber {
            turnDeadline = expected
        } else if let deadline = turnDeadline {
            if abs(deadline.timeIntervalSince(expected)) > 1.5 { turnDeadline = expected }
        } else {
            turnDeadline = expected
        }
    }

    // MARK: Callouts

    private func announce(_ action: PokerLastAction, recordOnSeat: Bool) {
        if recordOnSeat { seatActions[action.playerID] = action }
        calloutToken += 1
        let token: Int = calloutToken
        let name: String = action.name.isEmpty ? "Player" : action.name
        let text: String
        switch action.action {
        case "fold": text = "\(name) folds"
        case "check": text = "\(name) checks"
        case "call": text = "\(name) calls \(PKTFormat.chips(action.amount))"
        case "bet": text = "\(name) bets \(PKTFormat.chips(action.amount))"
        case "raise": text = "\(name) raises to \(PKTFormat.chips(action.amount))"
        case "allIn": text = "\(name) is all in"
        default: text = name
        }
        let isAllIn: Bool = action.action == "allIn"
        let item = PokerCallout(id: action.seq, playerID: action.playerID, text: text,
                                isAllIn: isAllIn, amount: action.amount, name: name)
        callout = item
        if isAllIn { allInFlash = item }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.calloutToken == token else { return }
            self.callout = nil
        }
        if isAllIn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let self, self.allInFlash?.id == item.id else { return }
                self.allInFlash = nil
            }
        }
    }

    // MARK: Showdown sequence

    private func beginShowdown(_ next: PokerBoardState) {
        sequenceToken += 1
        let token: Int = sequenceToken
        stage = .none

        let result: PokerHandResult? = next.lastHand
        let winners: [String] = result?.winnerIDs ?? []
        let share: Int = result?.amount ?? 0
        heldPot = max(state.pot, share * max(winners.count, 1))
        var held: [String: Int] = [:]
        for id in winners {
            if let seat = next.playerSeats.first(where: { $0.id == id }) {
                held[id] = max(0, seat.chips - share)
            }
        }
        heldChips = held

        let hasReveal: Bool = !next.showdown.isEmpty
        let boardDone: Double = PokerReveal.finishTime(from: revealFrom, count: next.communityCards.count)
        let highlightAt: Double = hasReveal ? max(1.7, boardDone + 0.4) : 0.7
        let sweepAt: Double = highlightAt + (hasReveal ? 1.0 : 0.2)
        let scoreboardAt: Double = sweepAt + 1.1

        schedule(.reveal, at: hasReveal ? 0.3 : 0.1, token: token)
        schedule(.highlight, at: highlightAt, token: token)
        schedule(.sweep, at: sweepAt, token: token)
        schedule(.scoreboard, at: scoreboardAt, token: token)
    }

    private func schedule(_ target: PokerShowdownStage, at seconds: Double, token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.sequenceToken == token else { return }
            self.advance(to: target, token: token)
        }
    }

    private func advance(to target: PokerShowdownStage, token: Int) {
        stage = target
        guard target == .sweep else { return }
        sweepCount += 1
        let winners: [String] = state.lastHand?.winnerIDs ?? []
        let pot: Int = heldPot ?? 0
        for (i, id) in winners.enumerated() {
            addFlight(from: .pot, to: .seat(id), chips: 7, delay: Double(i) * 0.15,
                      tier: Self.tier(for: pot, bigBlind: state.bigBlind))
        }
        // The winners' stacks count up as the chips land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.sequenceToken == token else { return }
            self.heldChips = [:]
        }
    }

    // MARK: Helpers

    private func addFlight(from: PokerChipAnchor, to: PokerChipAnchor, chips: Int, delay: Double, tier: Int) {
        flightCounter += 1
        let flight = PokerChipFlight(id: flightCounter, from: from, to: to, chips: chips,
                                     delay: delay, tier: tier)
        flights.append(flight)
        let lifetime: Double = delay + Double(chips) * 0.05 + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime) { [weak self] in
            self?.flights.removeAll { $0.id == flight.id }
        }
    }

    private static func stacksIncludingBets(_ seats: [PokerSeat]) -> [String: Int] {
        var stacks: [String: Int] = [:]
        for seat in seats { stacks[seat.id] = seat.chips + seat.currentBet }
        return stacks
    }

    /// Chip colour tier for an amount, relative to the big blind.
    nonisolated static func tier(for amount: Int, bigBlind: Int) -> Int {
        let bb: Int = max(bigBlind, 1)
        if amount >= bb * 25 { return 3 }
        if amount >= bb * 8 { return 2 }
        if amount >= bb * 2 { return 1 }
        return 0
    }
}

// MARK: - Stage layout

private enum PKTStage {
    static let width: CGFloat = 1920
    static let height: CGFloat = 1080
    static let center = CGPoint(x: 960, y: 580)
    /// Half-axes of the outer edge of the leather rail.
    static let rx: CGFloat = 740
    static let ry: CGFloat = 318
    static let rail: CGFloat = 46
    static let potPoint = CGPoint(x: 960, y: 408)
    static let boardPoint = CGPoint(x: 960, y: 594)
    static let dealerPoint = CGPoint(x: 960, y: 300)
    static let boardCardWidth: CGFloat = 112
    static let boardCardHeight: CGFloat = 156
    static let boardCardSpacing: CGFloat = 14
    static let holeCardWidth: CGFloat = 64
    static let holeCardHeight: CGFloat = 90

    static var tableRect: CGRect {
        CGRect(x: center.x - rx, y: center.y - ry, width: rx * 2, height: ry * 2)
    }

    static func boardCardPoint(_ index: Int) -> CGPoint {
        let step: CGFloat = boardCardWidth + boardCardSpacing
        return CGPoint(x: boardPoint.x + CGFloat(index - 2) * step, y: boardPoint.y)
    }
}

/// Where each seat sits. Seats are spread evenly round the oval, clockwise,
/// leaving the top centre (the dealer's spot, under the pot) free.
private struct PKTSeatLayout {
    let count: Int

    private func angle(_ index: Int) -> Double {
        let n: Double = Double(max(count, 1))
        let degrees: Double = 270 + 180 / n + Double(index) * 360 / n
        return degrees * Double.pi / 180
    }

    private func point(_ index: Int, rx: CGFloat, ry: CGFloat) -> CGPoint {
        let t: Double = angle(index)
        return CGPoint(x: PKTStage.center.x + PKTStage.rx * rx * CGFloat(cos(t)),
                       y: PKTStage.center.y + PKTStage.ry * ry * CGFloat(sin(t)))
    }

    /// The avatar's centre, sitting on the rail.
    func seat(_ index: Int) -> CGPoint { point(index, rx: 1.0, ry: 1.0) }
    /// The hole cards, on the felt in front of the player.
    func hole(_ index: Int) -> CGPoint { point(index, rx: 0.80, ry: 0.80) }
    /// The current-street bet pile, further in.
    func bet(_ index: Int) -> CGPoint { point(index, rx: 0.62, ry: 0.55) }

    /// Seats on the far side of the table put their name plate above the
    /// avatar (out towards the edge of the screen) rather than below it.
    func isFarSide(_ index: Int) -> Bool { sin(angle(index)) < -0.25 }
}

private enum PKTFormat {
    static func chips(_ value: Int) -> String {
        value.formatted(.number)
    }
}

private enum PKTColors {
    static let gold = Color(hex: "f5c451")
    static let goldDeep = Color(hex: "b8862b")
    static let feltLight = Color(hex: "1f8a63")
    static let feltMid = Color(hex: "11583f")
    static let feltDark = Color(hex: "0a3527")
    static let feltEdge = Color(hex: "051d15")
    static let leatherTop = Color(hex: "3b2b21")
    static let leatherBottom = Color(hex: "120d0a")
    static let ink = Color(hex: "0b0f17")
    static let red = Color(hex: "ef4444")
    static let mint = TVTheme.green
}

// MARK: - The stage

private struct PKTStageView: View {
    @ObservedObject var vm: PokerBoardViewModel

    private var state: PokerBoardState { vm.state }
    private var layout: PKTSeatLayout { PKTSeatLayout(count: state.playerSeats.count) }

    private var winnerIDs: Set<String> {
        guard vm.stage >= .highlight, let result = state.lastHand else { return [] }
        return Set(result.winnerIDs)
    }

    private var winningCards: Set<String> {
        guard state.isShowdown, vm.stage >= .highlight, !state.showdown.isEmpty,
              let result = state.lastHand else { return [] }
        return Set(result.winningCards)
    }

    var body: some View {
        ZStack {
            PKTRoomBackdrop()
            PKTTableSurface()
            PKTFeltPrint()
                .position(x: PKTStage.center.x, y: 336)
            communityRow
            PKTPotView(amount: vm.displayPot)
                .position(PKTStage.potPoint)
            betPiles
            holeCards
            seatPods
            flightsLayer
            winnerBurst
            winnerBanner
            allInFlash
            topBar
            scoreboard
        }
        .frame(width: PKTStage.width, height: PKTStage.height)
        .clipped()
    }

    // MARK: Community cards

    private var communityRow: some View {
        let cards: [String] = state.communityCards
        let winning: Set<String> = winningCards
        return ZStack {
            ForEach(0..<5, id: \.self) { i in
                let point: CGPoint = PKTStage.boardCardPoint(i)
                ZStack {
                    PKTEmptySlot(width: PKTStage.boardCardWidth, height: PKTStage.boardCardHeight)
                    if i < cards.count {
                        PKTBoardCard(card: cards[i],
                                     startsFaceUp: i < vm.revealFrom,
                                     delay: PokerReveal.delay(index: i, from: vm.revealFrom),
                                     dealFrom: CGSize(width: PKTStage.dealerPoint.x - point.x,
                                                      height: PKTStage.dealerPoint.y - point.y),
                                     emphasis: PKTEmphasis.of(card: cards[i], winning: winning))
                            .id("\(state.handNumber)-\(i)-\(cards[i])")
                    }
                }
                .position(point)
            }
        }
    }

    // MARK: Bets

    private var betPiles: some View {
        ZStack {
            if !state.isShowdown {
                ForEach(Array(state.playerSeats.enumerated()), id: \.element.id) { i, seat in
                    if seat.currentBet > 0 {
                        PKTBetPile(amount: seat.currentBet,
                                   tier: PokerBoardViewModel.tier(for: seat.currentBet, bigBlind: state.bigBlind))
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                            .position(layout.bet(i))
                    }
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: state.isShowdown)
    }

    // MARK: Hole cards

    private func showdownHand(for id: String) -> PokerShowdownHand? {
        state.showdown.first { $0.playerID == id }
    }

    private var holeCards: some View {
        let winning: Set<String> = winningCards
        return ZStack {
            ForEach(Array(state.playerSeats.enumerated()), id: \.element.id) { i, seat in
                let hand: PokerShowdownHand? = state.isShowdown ? showdownHand(for: seat.id) : nil
                let inHand: Bool = seat.status != "folded" && state.handNumber > 0
                if inHand {
                    let point: CGPoint = layout.hole(i)
                    PKTHoleCards(faceUpCards: hand?.cards ?? [],
                                 reveal: vm.stage >= .reveal,
                                 revealDelay: Double(i) * 0.12,
                                 dealDelay: Double(i) * 0.08,
                                 dealFrom: CGSize(width: PKTStage.dealerPoint.x - point.x,
                                                  height: PKTStage.dealerPoint.y - point.y),
                                 winning: winning,
                                 handName: vm.stage >= .highlight ? hand?.handName : nil,
                                 isWinner: winnerIDs.contains(seat.id),
                                 labelAbove: !layout.isFarSide(i))
                        .id("hole-\(state.handNumber)-\(seat.id)")
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .offset(x: (PKTStage.center.x - point.x) * 0.45,
                                             y: (PKTStage.center.y - point.y) * 0.45)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.6))))
                        .position(point)
                }
            }
        }
        .animation(.easeIn(duration: 0.4), value: foldedSignature)
    }

    /// Changes whenever anyone folds, to animate their cards to the muck.
    private var foldedSignature: String {
        state.playerSeats.filter { $0.status == "folded" }.map(\.id).joined(separator: ",")
    }

    // MARK: Seats

    private var seatPods: some View {
        ZStack {
            ForEach(Array(state.playerSeats.enumerated()), id: \.element.id) { i, seat in
                PKTSeatPod(seat: seat,
                           displayChips: vm.displayChips(for: seat),
                           isFarSide: layout.isFarSide(i),
                           isDealer: seat.id == state.dealerID,
                           isSmallBlind: seat.id == state.smallBlindID,
                           isBigBlind: seat.id == state.bigBlindID,
                           isActive: seat.isCurrentTurn && !state.isShowdown && seat.status == "active",
                           deadline: vm.turnDeadline,
                           turnSeconds: state.turnSeconds,
                           action: vm.seatActions[seat.id],
                           isWinner: winnerIDs.contains(seat.id))
                    .position(layout.seat(i))
            }
        }
    }

    // MARK: Chip flights

    private func resolve(_ anchor: PokerChipAnchor) -> CGPoint? {
        switch anchor {
        case .pot:
            return PKTStage.potPoint
        case .seat(let id):
            guard let i = state.playerSeats.firstIndex(where: { $0.id == id }) else { return nil }
            return layout.seat(i)
        case .bet(let id):
            guard let i = state.playerSeats.firstIndex(where: { $0.id == id }) else { return nil }
            return layout.bet(i)
        }
    }

    private var flightsLayer: some View {
        ZStack {
            ForEach(vm.flights) { flight in
                if let from = resolve(flight.from), let to = resolve(flight.to) {
                    PKTChipFlightView(flight: flight, from: from, to: to)
                }
            }
        }
        .frame(width: PKTStage.width, height: PKTStage.height)
        .allowsHitTesting(false)
    }

    // MARK: Showdown overlays

    @ViewBuilder private var winnerBurst: some View {
        if let id = state.lastHand?.winnerIDs.first, let point = resolve(.seat(id)) {
            TVParticleBurst(trigger: vm.sweepCount, origin: point, color: PKTColors.gold,
                            count: 26, reach: 190, duration: 0.9)
                .frame(width: PKTStage.width, height: PKTStage.height)
        }
    }

    @ViewBuilder private var winnerBanner: some View {
        ZStack {
            if state.isShowdown, vm.stage >= .highlight, vm.stage < .scoreboard, let result = state.lastHand {
                PKTWinnerBanner(result: result, hasShowdown: !state.showdown.isEmpty)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .position(x: PKTStage.center.x, y: 742)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: vm.stage)
    }

    private var allInFlash: some View {
        ZStack {
            if let flash = vm.allInFlash {
                PKTAllInFlash(name: flash.name, amount: flash.amount)
                    .id(flash.id)
                    .transition(.scale(scale: 1.6).combined(with: .opacity))
                    .position(x: PKTStage.center.x, y: PKTStage.boardPoint.y)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: vm.allInFlash?.id)
        .allowsHitTesting(false)
    }

    private var scoreboard: some View {
        ZStack {
            if state.isShowdown && vm.stage == .scoreboard {
                Color.black.opacity(0.55)
                    .transition(.opacity)
                PKTScoreboard(seats: state.playerSeats,
                              startChips: vm.handStartChips,
                              handNumber: state.handNumber,
                              maxHands: state.maxHands,
                              winnerIDs: Set(state.lastHand?.winnerIDs ?? []))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .position(x: PKTStage.center.x, y: PKTStage.center.y)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: vm.stage)
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack(alignment: .center, spacing: 0) {
                PKTTitleBlock(handNumber: state.handNumber, maxHands: state.maxHands,
                              bigBlind: state.bigBlind)
                Spacer(minLength: 0)
                PKTStreetTracker(phase: state.phase)
            }
            .padding(.horizontal, 84)
            .frame(width: PKTStage.width)
            .position(x: PKTStage.width / 2, y: 92)

            PKTCalloutSlot(callout: vm.callout)
                .position(x: PKTStage.width / 2, y: 92)
        }
    }
}

// MARK: - Backdrop and table

/// Near-black room with one warm spotlight falling on the table.
private struct PKTRoomBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            let full = CGRect(origin: .zero, size: size)
            ctx.fill(Path(full), with: .linearGradient(
                Gradient(colors: [Color(hex: "0b0d14"), Color(hex: "06070b"), Color(hex: "020203")]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)))
            let c = CGPoint(x: size.width / 2, y: size.height * 0.5)
            ctx.fill(Path(full), with: .radialGradient(
                Gradient(colors: [Color(hex: "ffe2b0").opacity(0.13), Color(hex: "ffe2b0").opacity(0.04),
                                  Color.clear]),
                center: c, startRadius: 0, endRadius: size.width * 0.55))
            ctx.fill(Path(full), with: .radialGradient(
                Gradient(colors: [Color.clear, Color.black.opacity(0.65)]),
                center: c, startRadius: size.width * 0.32, endRadius: size.width * 0.72))
        }
        .allowsHitTesting(false)
    }
}

/// The table itself, painted in one Canvas: drop shadow, rail thickness,
/// leather rail with stitching, a gold inlay, then the felt with its own
/// vignette, edge shadow, betting line and spotlight hot-spot.
private struct PKTTableSurface: View {
    var body: some View {
        Canvas { ctx, _ in
            let outer: CGRect = PKTStage.tableRect
            let rail: CGFloat = PKTStage.rail
            let feltRect: CGRect = outer.insetBy(dx: rail, dy: rail * 0.9)
            let felt = Path(ellipseIn: feltRect)

            // Long soft drop shadow onto the floor.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 46))
                layer.fill(Path(ellipseIn: outer.offsetBy(dx: 0, dy: 46).insetBy(dx: -20, dy: -10)),
                           with: .color(Color.black.opacity(0.85)))
            }

            // Rail thickness: a darker copy peeking out below.
            ctx.fill(Path(ellipseIn: outer.offsetBy(dx: 0, dy: 18)),
                     with: .linearGradient(Gradient(colors: [Color(hex: "0c0806"), Color(hex: "020101")]),
                                           startPoint: CGPoint(x: outer.midX, y: outer.midY),
                                           endPoint: CGPoint(x: outer.midX, y: outer.maxY + 18)))

            // Leather rail.
            let railPath = Path(ellipseIn: outer)
            ctx.fill(railPath, with: .linearGradient(
                Gradient(colors: [PKTColors.leatherTop, Color(hex: "1d1510"), PKTColors.leatherBottom]),
                startPoint: CGPoint(x: outer.midX, y: outer.minY),
                endPoint: CGPoint(x: outer.midX, y: outer.maxY)))
            ctx.fill(railPath, with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.10), Color.clear]),
                center: CGPoint(x: outer.midX, y: outer.minY + rail * 0.4),
                startRadius: 0, endRadius: outer.width * 0.45))
            ctx.stroke(Path(ellipseIn: outer.insetBy(dx: 3, dy: 3)), with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.02)]),
                startPoint: CGPoint(x: outer.midX, y: outer.minY),
                endPoint: CGPoint(x: outer.midX, y: outer.maxY)), lineWidth: 2.5)

            // Stitching along the middle of the rail.
            ctx.stroke(Path(ellipseIn: outer.insetBy(dx: rail * 0.5, dy: rail * 0.45)),
                       with: .color(Color(hex: "c9a46a").opacity(0.32)),
                       style: StrokeStyle(lineWidth: 1.6, dash: [7, 6]))

            // Felt: lit in the middle, falling off to a dark edge.
            ctx.fill(felt, with: .radialGradient(
                Gradient(stops: [
                    .init(color: PKTColors.feltLight, location: 0),
                    .init(color: PKTColors.feltMid, location: 0.45),
                    .init(color: PKTColors.feltDark, location: 0.8),
                    .init(color: PKTColors.feltEdge, location: 1),
                ]),
                center: CGPoint(x: feltRect.midX, y: feltRect.midY - 30),
                startRadius: 0, endRadius: feltRect.width * 0.52))

            // Edge shadow where the rail overhangs the felt.
            ctx.drawLayer { layer in
                layer.clip(to: felt)
                layer.addFilter(.blur(radius: 18))
                layer.stroke(felt, with: .color(Color.black.opacity(0.75)), lineWidth: 44)
            }

            // Spotlight hot-spot on the felt.
            ctx.drawLayer { layer in
                layer.clip(to: felt)
                layer.fill(felt, with: .radialGradient(
                    Gradient(colors: [Color(hex: "fff4d6").opacity(0.14), Color.clear]),
                    center: CGPoint(x: feltRect.midX, y: feltRect.midY - 20),
                    startRadius: 0, endRadius: feltRect.width * 0.32))
            }

            // Betting line.
            ctx.stroke(Path(ellipseIn: feltRect.insetBy(dx: 74, dy: 56)),
                       with: .color(PKTColors.gold.opacity(0.16)), lineWidth: 2)

            // Gold inlay between rail and felt.
            ctx.stroke(felt, with: .linearGradient(
                Gradient(colors: [PKTColors.gold.opacity(0.85), PKTColors.goldDeep.opacity(0.55)]),
                startPoint: CGPoint(x: feltRect.midX, y: feltRect.minY),
                endPoint: CGPoint(x: feltRect.midX, y: feltRect.maxY)), lineWidth: 3)
        }
        .frame(width: PKTStage.width, height: PKTStage.height)
        .allowsHitTesting(false)
    }
}

/// The table name printed on the felt, laid flat into the table plane --
/// the one element tilted in 3D, which is what sells the perspective.
private struct PKTFeltPrint: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 26, weight: .bold))
            Text("AURORA HOLD'EM")
                .font(.system(size: 30, weight: .heavy, design: .serif))
                .tracking(10)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 26, weight: .bold))
        }
        .foregroundColor(PKTColors.gold.opacity(0.22))
        .rotation3DEffect(.degrees(58), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
        .allowsHitTesting(false)
    }
}

// MARK: - Cards

private enum PKTSuit {
    static func parse(_ card: String) -> (rank: String, suit: String) {
        guard let last = card.last else { return ("", "") }
        return (String(card.dropLast()), String(last))
    }

    static func isRed(_ suit: String) -> Bool {
        suit == "\u{2665}" || suit == "\u{2666}"
    }

    static func symbol(_ suit: String) -> String {
        switch suit {
        case "\u{2665}": return "suit.heart.fill"
        case "\u{2666}": return "suit.diamond.fill"
        case "\u{2663}": return "suit.club.fill"
        default: return "suit.spade.fill"
        }
    }
}

/// A crisp, jumbo-index card face: big rank and suit top-left, a large suit
/// bottom-right, readable from across the room.
private struct PKTCardFace: View {
    let card: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let parts = PKTSuit.parse(card)
        let ink: Color = PKTSuit.isRed(parts.suit) ? Color(hex: "d61f2c") : Color(hex: "121826")
        let shape = RoundedRectangle(cornerRadius: width * 0.11, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [Color.white, Color(hex: "eef0f4")],
                                      startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
            if !parts.rank.isEmpty {
                VStack(spacing: width * 0.01) {
                    Text(parts.rank)
                        .font(.system(size: width * (parts.rank.count > 1 ? 0.36 : 0.42),
                                      weight: .heavy, design: .rounded))
                        .tracking(parts.rank.count > 1 ? -2 : 0)
                    Image(systemName: PKTSuit.symbol(parts.suit))
                        .font(.system(size: width * 0.22, weight: .bold))
                }
                .foregroundColor(ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, width * 0.09)
                .padding(.top, width * 0.06)

                Image(systemName: PKTSuit.symbol(parts.suit))
                    .font(.system(size: width * 0.5, weight: .bold))
                    .foregroundColor(ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(width * 0.1)
            }
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.45), radius: width * 0.06, x: 0, y: width * 0.05)
    }
}

/// Navy back with a gold frame and a fine diamond lattice.
private struct PKTCardBack: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.11, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
        return ZStack {
            shape.fill(Color.white)
            inner
                .fill(LinearGradient(colors: [Color(hex: "1e3a8a"), Color(hex: "0b1640")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Canvas { ctx, size in
                        let step: CGFloat = max(6, size.width / 7)
                        var x: CGFloat = -size.height
                        while x < size.width + size.height {
                            var a = Path()
                            a.move(to: CGPoint(x: x, y: 0))
                            a.addLine(to: CGPoint(x: x + size.height, y: size.height))
                            var b = Path()
                            b.move(to: CGPoint(x: x + size.height, y: 0))
                            b.addLine(to: CGPoint(x: x, y: size.height))
                            ctx.stroke(a, with: .color(PKTColors.gold.opacity(0.18)), lineWidth: 1)
                            ctx.stroke(b, with: .color(PKTColors.gold.opacity(0.18)), lineWidth: 1)
                            x += step
                        }
                    }
                    .clipShape(inner)
                )
                .overlay(inner.strokeBorder(PKTColors.gold.opacity(0.75), lineWidth: max(1, width * 0.025)))
                .padding(width * 0.07)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: width * 0.3, weight: .bold))
                .foregroundColor(PKTColors.gold)
                .shadow(color: Color.black.opacity(0.5), radius: 2)
        }
        .frame(width: width, height: height)
        .shadow(color: Color.black.opacity(0.45), radius: width * 0.06, x: 0, y: width * 0.05)
    }
}

private struct PKTEmptySlot: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.11, style: .continuous)
            .fill(Color.black.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .frame(width: width, height: height)
    }
}

/// How a face-up card is treated at showdown.
private enum PKTEmphasis {
    case normal
    case winning
    case dimmed

    static func of(card: String, winning: Set<String>) -> PKTEmphasis {
        guard !winning.isEmpty else { return .normal }
        return winning.contains(card) ? .winning : .dimmed
    }
}

private struct PKTEmphasisModifier: ViewModifier {
    let emphasis: PKTEmphasis
    let cornerRadius: CGFloat
    let lift: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PKTColors.gold, lineWidth: 4)
                    .opacity(emphasis == .winning ? 1 : 0)
            )
            .shadow(color: PKTColors.gold.opacity(emphasis == .winning ? 0.85 : 0), radius: 18)
            .offset(y: emphasis == .winning ? -lift : 0)
            .opacity(emphasis == .dimmed ? 0.4 : 1)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: emphasis)
    }
}

/// A community card: slides in face down from the dealer spot, then flips.
private struct PKTBoardCard: View {
    let card: String
    let startsFaceUp: Bool
    let delay: Double
    let dealFrom: CGSize
    let emphasis: PKTEmphasis

    @State private var dealt = false
    @State private var faceUp = false

    var body: some View {
        TVFlipCard(isFaceUp: faceUp) {
            PKTCardFace(card: card, width: PKTStage.boardCardWidth, height: PKTStage.boardCardHeight)
        } back: {
            PKTCardBack(width: PKTStage.boardCardWidth, height: PKTStage.boardCardHeight)
        }
        .modifier(PKTEmphasisModifier(emphasis: emphasis,
                                      cornerRadius: PKTStage.boardCardWidth * 0.11, lift: 18))
        .rotationEffect(.degrees(dealt ? 0 : -16))
        .offset(dealt ? .zero : dealFrom)
        .opacity(dealt ? 1 : 0)
        .onAppear {
            if startsFaceUp {
                dealt = true
                faceUp = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(delay)) {
                dealt = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.35) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                    faceUp = true
                }
            }
        }
    }
}

/// A player's two hole cards on the felt in front of them: dealt face down,
/// mucked when they fold, and flipped and enlarged at showdown.
private struct PKTHoleCards: View {
    let faceUpCards: [String]
    let reveal: Bool
    let revealDelay: Double
    let dealDelay: Double
    let dealFrom: CGSize
    let winning: Set<String>
    let handName: String?
    let isWinner: Bool
    let labelAbove: Bool

    @State private var dealt = false

    private var revealed: Bool { reveal && faceUpCards.count >= 2 }

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                card(i)
            }
        }
        .frame(width: PKTStage.holeCardWidth + 40, height: PKTStage.holeCardHeight)
        .scaleEffect(revealed ? 1.32 : 1)
        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(revealDelay), value: revealed)
        .overlay(alignment: labelAbove ? .top : .bottom) {
            if let handName, !handName.isEmpty {
                PKTHandNamePill(text: handName, isWinner: isWinner)
                    .fixedSize()
                    .offset(y: labelAbove ? -50 : 50)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: handName)
        .onAppear {
            DispatchQueue.main.async { dealt = true }
        }
    }

    private func card(_ i: Int) -> some View {
        let value: String = i < faceUpCards.count ? faceUpCards[i] : ""
        let emphasis: PKTEmphasis = revealed ? PKTEmphasis.of(card: value, winning: winning) : .normal
        return TVFlipCard(isFaceUp: revealed) {
            PKTCardFace(card: value, width: PKTStage.holeCardWidth, height: PKTStage.holeCardHeight)
        } back: {
            PKTCardBack(width: PKTStage.holeCardWidth, height: PKTStage.holeCardHeight)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.72).delay(revealDelay + Double(i) * 0.12),
                   value: revealed)
        .modifier(PKTEmphasisModifier(emphasis: emphasis,
                                      cornerRadius: PKTStage.holeCardWidth * 0.11, lift: 8))
        .rotationEffect(.degrees(i == 0 ? -7 : 7), anchor: .bottom)
        .offset(x: i == 0 ? -19 : 19)
        .offset(dealt ? .zero : dealFrom)
        .opacity(dealt ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(dealDelay + Double(i) * 0.3),
                   value: dealt)
    }
}

private struct PKTHandNamePill: View {
    let text: String
    let isWinner: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .heavy, design: .rounded))
            .foregroundColor(isWinner ? Color.black : Color.white)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isWinner
                               ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "fde68a"), PKTColors.gold],
                                                              startPoint: .top, endPoint: .bottom))
                               : AnyShapeStyle(Color.black.opacity(0.72)))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(isWinner ? 0.6 : 0.18), lineWidth: 1.5))
            .shadow(color: isWinner ? PKTColors.gold.opacity(0.7) : Color.clear, radius: 12)
    }
}

// MARK: - Chips

/// Chip colours by tier: red, green, black, purple -- each with an edge
/// colour for the stripes.
private enum PKTChipPalette {
    static func base(_ tier: Int) -> Color {
        switch tier {
        case 0: return Color(hex: "dc2626")
        case 1: return Color(hex: "15803d")
        case 2: return Color(hex: "1f2937")
        default: return Color(hex: "7c3aed")
        }
    }

    static func edge(_ tier: Int) -> Color {
        switch tier {
        case 2: return PKTColors.gold
        default: return Color.white
        }
    }
}

/// A single chip seen at the table's angle: an elliptical top face over a
/// darker edge band, with the classic edge spots.
private struct PKTChip: View {
    let tier: Int
    var diameter: CGFloat = 42

    var body: some View {
        let h: CGFloat = diameter * 0.56
        let thickness: CGFloat = diameter * 0.12
        let base: Color = PKTChipPalette.base(tier)
        let edge: Color = PKTChipPalette.edge(tier)
        return ZStack {
            Ellipse()
                .fill(base)
                .overlay(Ellipse().fill(Color.black.opacity(0.4)))
                .frame(width: diameter, height: h)
                .offset(y: thickness)
            Ellipse()
                .fill(base)
                .frame(width: diameter, height: h)
            Ellipse()
                .strokeBorder(edge.opacity(0.9), style: StrokeStyle(lineWidth: diameter * 0.09,
                                                                    dash: [diameter * 0.14, diameter * 0.16]))
                .frame(width: diameter, height: h)
            Ellipse()
                .strokeBorder(edge.opacity(0.55), lineWidth: 1.2)
                .frame(width: diameter * 0.58, height: h * 0.58)
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.clear],
                                     startPoint: .top, endPoint: .center))
                .frame(width: diameter, height: h)
        }
        .frame(width: diameter, height: h + thickness)
    }
}

/// A short stack of chips.
private struct PKTChipStack: View {
    let count: Int
    let tier: Int
    var diameter: CGFloat = 42

    var body: some View {
        let n: Int = max(1, min(count, 8))
        let step: CGFloat = diameter * 0.13
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                PKTChip(tier: i % 3 == 2 ? max(tier - 1, 0) : tier, diameter: diameter)
                    .offset(y: -CGFloat(i) * step)
            }
        }
        .frame(width: diameter, height: diameter * 0.68 + CGFloat(n - 1) * step, alignment: .bottom)
        .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 3)
    }
}

private struct PKTBetPile: View {
    let amount: Int
    let tier: Int

    var body: some View {
        VStack(spacing: 6) {
            PKTChipStack(count: 2 + tier * 2, tier: tier, diameter: 40)
            PKTCountingText(value: Double(amount), size: 24, color: Color.white)
                .animation(.easeOut(duration: 0.6), value: amount)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
        }
        .fixedSize()
    }
}

/// An integer that counts up or down to its new value.
private struct PKTCountingText: View, Animatable {
    var value: Double
    let size: CGFloat
    let color: Color

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(PKTFormat.chips(Int(value.rounded())))
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundColor(color)
            .lineLimit(1)
    }
}

private struct PKTPotView: View {
    let amount: Int

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                PKTChipStack(count: 4, tier: 3, diameter: 38).offset(x: -16, y: 4)
                PKTChipStack(count: 6, tier: 2, diameter: 38).offset(x: 16, y: 0)
            }
            .frame(width: 76, height: 70)
            VStack(alignment: .leading, spacing: 0) {
                Text("POT")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(5)
                    .foregroundColor(PKTColors.gold.opacity(0.85))
                PKTCountingText(value: Double(amount), size: 50, color: Color.white)
                    .animation(.easeOut(duration: 0.9), value: amount)
                    .shadow(color: PKTColors.gold.opacity(0.35), radius: 10)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 26)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color.black.opacity(0.42))
        )
        .overlay(Capsule().strokeBorder(PKTColors.gold.opacity(0.35), lineWidth: 1.5))
        .opacity(amount > 0 ? 1 : 0.55)
        .fixedSize()
    }
}

/// Moves its view along a shallow arc from where it was placed to `delta`.
private struct PKTArcEffect: GeometryEffect {
    var progress: CGFloat
    let delta: CGSize
    let lift: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x: CGFloat = delta.width * progress
        let y: CGFloat = delta.height * progress - lift * 4 * progress * (1 - progress)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

private struct PKTFlyingChip: View {
    let tier: Int
    let from: CGPoint
    let to: CGPoint
    let delay: Double

    @State private var progress: CGFloat = 0
    @State private var visible = false
    @State private var landed = false

    var body: some View {
        PKTChip(tier: tier, diameter: 38)
            .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0, y: 4)
            .opacity(visible && !landed ? 1 : 0)
            .modifier(PKTArcEffect(progress: progress,
                                   delta: CGSize(width: to.x - from.x, height: to.y - from.y),
                                   lift: 70))
            .position(from)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    visible = true
                    withAnimation(.easeInOut(duration: 0.55)) { progress = 1 }
                    withAnimation(.easeIn(duration: 0.15).delay(0.55)) { landed = true }
                }
            }
    }
}

private struct PKTChipFlightView: View {
    let flight: PokerChipFlight
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        ZStack {
            ForEach(0..<max(flight.chips, 1), id: \.self) { i in
                PKTFlyingChip(tier: i % 2 == 0 ? flight.tier : max(flight.tier - 1, 0),
                              from: CGPoint(x: from.x + CGFloat((i % 3) - 1) * 10, y: from.y),
                              to: CGPoint(x: to.x + CGFloat((i % 3) - 1) * 8, y: to.y - CGFloat(i) * 3),
                              delay: flight.delay + Double(i) * 0.05)
            }
        }
    }
}

// MARK: - Seats

private struct PKTSeatPod: View {
    let seat: PokerSeat
    let displayChips: Int
    let isFarSide: Bool
    let isDealer: Bool
    let isSmallBlind: Bool
    let isBigBlind: Bool
    let isActive: Bool
    let deadline: Date?
    let turnSeconds: Int
    let action: PokerLastAction?
    let isWinner: Bool

    private var color: Color { ShellTheme.avatarColor(for: seat.id) }
    private var isFolded: Bool { seat.status == "folded" }
    private var isBusted: Bool { isFolded && displayChips == 0 }

    var body: some View {
        avatar
            .overlay(alignment: isFarSide ? .top : .bottom) {
                PKTNamePlate(name: seat.name, chips: displayChips, tag: tag,
                             accent: color, isActive: isActive, isWinner: isWinner)
                    .fixedSize()
                    .offset(y: isFarSide ? -70 : 70)
            }
            .opacity(isFolded ? 0.45 : 1)
            .saturation(isFolded ? 0.15 : 1)
            .scaleEffect(isWinner ? 1.1 : (isActive ? 1.05 : 1))
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: isActive)
            .animation(.spring(response: 0.45, dampingFraction: 0.65), value: isWinner)
            .animation(.easeInOut(duration: 0.4), value: isFolded)
    }

    private var avatar: some View {
        ZStack {
            if isActive {
                PKTActiveRing(color: color)
                if let deadline {
                    PKTCountdownRing(deadline: deadline, total: Double(max(turnSeconds, 1)))
                }
            }
            if isWinner {
                Circle()
                    .strokeBorder(PKTColors.gold, lineWidth: 6)
                    .frame(width: 112, height: 112)
                    .shadow(color: PKTColors.gold.opacity(0.9), radius: 22)
            }
            ShellAvatarToken(id: seat.id, name: seat.name, size: 92)
        }
        .frame(width: 124, height: 124)
        .overlay(alignment: .topTrailing) { badges.offset(x: 18, y: -2) }
        .overlay(alignment: .top) {
            if isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "fff3c4"), PKTColors.gold],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: PKTColors.gold.opacity(0.9), radius: 10)
                    .offset(y: -22)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var badges: some View {
        VStack(spacing: 4) {
            if isDealer {
                PKTButtonBadge(label: "D", fill: Color.white, ink: PKTColors.ink)
            }
            if isSmallBlind {
                PKTButtonBadge(label: "SB", fill: Color(hex: "3b82f6"), ink: Color.white)
            }
            if isBigBlind {
                PKTButtonBadge(label: "BB", fill: PKTColors.gold, ink: PKTColors.ink)
            }
        }
    }

    private var tag: PKTSeatTag? {
        if isBusted { return PKTSeatTag(text: "OUT", color: Color.white.opacity(0.35)) }
        if isFolded { return PKTSeatTag(text: "FOLD", color: Color.white.opacity(0.35)) }
        if seat.status == "all-in" { return PKTSeatTag(text: "ALL IN", color: PKTColors.red) }
        guard let action else { return nil }
        switch action.action {
        case "check": return PKTSeatTag(text: "CHECK", color: Color(hex: "64748b"))
        case "call": return PKTSeatTag(text: "CALL \(PKTFormat.chips(action.amount))", color: Color(hex: "0ea5e9"))
        case "bet": return PKTSeatTag(text: "BET \(PKTFormat.chips(action.amount))", color: Color(hex: "f59e0b"))
        case "raise": return PKTSeatTag(text: "RAISE \(PKTFormat.chips(action.amount))", color: Color(hex: "f97316"))
        case "allIn": return PKTSeatTag(text: "ALL IN", color: PKTColors.red)
        default: return nil
        }
    }
}

private struct PKTSeatTag: Equatable {
    let text: String
    let color: Color
}

private struct PKTNamePlate: View {
    let name: String
    let chips: Int
    let tag: PKTSeatTag?
    let accent: Color
    let isActive: Bool
    let isWinner: Bool

    var body: some View {
        let edge: Color = isWinner ? PKTColors.gold : (isActive ? accent : Color.white.opacity(0.16))
        return VStack(spacing: 2) {
            Text(name)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 230)
            HStack(spacing: 8) {
                Circle()
                    .fill(PKTColors.gold)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.7),
                                                   style: StrokeStyle(lineWidth: 2, dash: [3, 3])))
                PKTCountingText(value: Double(chips), size: 23, color: PKTColors.gold)
                    .animation(.easeOut(duration: 0.8), value: chips)
                if let tag {
                    Text(tag.text)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tag.color))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: tag)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "1a1f2b").opacity(0.94), Color(hex: "0a0d13").opacity(0.94)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(edge, lineWidth: isActive || isWinner ? 2.5 : 1.2)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 6)
    }
}

private struct PKTButtonBadge: View {
    let label: String
    let fill: Color
    let ink: Color

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 14 : 18, weight: .black, design: .rounded))
            .foregroundColor(ink)
            .frame(width: 36, height: 36)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 2).padding(3))
            .shadow(color: Color.black.opacity(0.5), radius: 4, x: 0, y: 3)
    }
}

/// A soft breathing halo in the player's colour behind the acting seat.
private struct PKTActiveRing: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0)],
                                 center: .center, startRadius: 40, endRadius: 78))
            .frame(width: 156, height: 156)
            .phaseAnimator([false, true]) { content, phase in
                content
                    .scaleEffect(phase ? 1.08 : 0.94)
                    .opacity(phase ? 1 : 0.6)
            } animation: { _ in
                Animation.easeInOut(duration: 0.9)
            }
    }
}

/// The shot clock: an arc round the avatar that drains, green to amber to red.
private struct PKTCountdownRing: View {
    let deadline: Date
    let total: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let remaining: Double = max(0, deadline.timeIntervalSince(context.date))
            let fraction: Double = min(1, remaining / total)
            let tint: Color = fraction > 0.5 ? PKTColors.mint : (fraction > 0.2 ? PKTColors.gold : PKTColors.red)
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.45), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.8), radius: 8)
            }
            .frame(width: 112, height: 112)
        }
    }
}

// MARK: - Banners

private struct PKTTitleBlock: View {
    let handNumber: Int
    let maxHands: Int
    let bigBlind: Int

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(PKTColors.ink)
                .frame(width: 60, height: 60)
                .background(Circle().fill(LinearGradient(colors: [Color(hex: "fde68a"), PKTColors.gold],
                                                         startPoint: .top, endPoint: .bottom)))
                .shadow(color: PKTColors.gold.opacity(0.5), radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("POKER")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = ["Texas Hold'em"]
        if maxHands > 0 && handNumber > 0 {
            parts.append("Hand \(handNumber) of \(maxHands)")
        }
        let small: Int = max(bigBlind / 2, 1)
        parts.append("Blinds \(PKTFormat.chips(small)) / \(PKTFormat.chips(bigBlind))")
        return parts.joined(separator: "   |   ")
    }
}

private struct PKTStreetTracker: View {
    let phase: String

    private static let streets: [(key: String, label: String)] = [
        ("preflop", "PRE-FLOP"), ("flop", "FLOP"), ("turn", "TURN"), ("river", "RIVER"), ("showdown", "SHOWDOWN"),
    ]

    var body: some View {
        let current: Int = Self.streets.firstIndex(where: { $0.key == phase }) ?? 0
        return HStack(spacing: 8) {
            ForEach(Array(Self.streets.enumerated()), id: \.offset) { i, street in
                Text(street.label)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(i == current ? PKTColors.ink : Color.white.opacity(i < current ? 0.7 : 0.3))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(i == current ? PKTColors.gold : Color.white.opacity(i < current ? 0.1 : 0.04))
                    )
            }
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: phase)
    }
}

/// "Ravi raises to 200", sliding down from the top of the screen.
private struct PKTCalloutSlot: View {
    let callout: PokerCallout?

    var body: some View {
        ZStack {
            if let callout {
                PKTCalloutBanner(callout: callout)
                    .id(callout.id)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .opacity))
            }
        }
        .frame(width: 520, height: 80)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: callout?.id)
    }
}

private struct PKTCalloutBanner: View {
    let callout: PokerCallout

    var body: some View {
        let accent: Color = callout.isAllIn ? PKTColors.red : ShellTheme.avatarColor(for: callout.playerID)
        return HStack(spacing: 14) {
            Circle()
                .fill(accent)
                .frame(width: 16, height: 16)
                .shadow(color: accent, radius: 6)
            Text(callout.text)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(Capsule().fill(Color.black.opacity(0.7)))
        .overlay(Capsule().strokeBorder(accent.opacity(0.8), lineWidth: 2))
        .shadow(color: accent.opacity(0.45), radius: 16)
        .frame(maxWidth: 520)
    }
}

private struct PKTAllInFlash: View {
    let name: String
    let amount: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("ALL IN!")
                .font(.system(size: 120, weight: .black, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [Color(hex: "fff1c1"), PKTColors.gold, Color(hex: "f97316")],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: PKTColors.red.opacity(0.9), radius: 26)
                .shadow(color: Color.black.opacity(0.8), radius: 6, x: 0, y: 4)
            Text(amount > 0 ? "\(name)  |  \(PKTFormat.chips(amount))" : name)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .background(Capsule().fill(PKTColors.red.opacity(0.85)))
        }
    }
}

private struct PKTWinnerBanner: View {
    let result: PokerHandResult
    let hasShowdown: Bool

    private var headline: String {
        let names: String = result.winnerNames.joined(separator: " & ")
        let verb: String = result.winnerNames.count > 1 ? "split" : "wins"
        let total: Int = result.amount * max(result.winnerNames.count, 1)
        return "\(names.isEmpty ? "Winner" : names) \(verb) \(PKTFormat.chips(total))"
    }

    private var detail: String {
        if !hasShowdown { return "Everyone else folded" }
        return result.handName.isEmpty ? "Showdown" : result.handName
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(headline)
                .font(.system(size: 40, weight: .black, design: .rounded))
                .foregroundColor(PKTColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail.uppercased())
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(3)
                .foregroundColor(PKTColors.ink.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .frame(maxWidth: 820)
        .background(
            Capsule().fill(LinearGradient(colors: [Color(hex: "fff1c1"), PKTColors.gold, PKTColors.goldDeep],
                                          startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 2))
        .shadow(color: PKTColors.gold.opacity(0.6), radius: 26)
        .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 8)
    }
}

/// Standings between hands: chip counts, biggest first, with each player's
/// change over the hand just played.
private struct PKTScoreboard: View {
    let seats: [PokerSeat]
    let startChips: [String: Int]
    let handNumber: Int
    let maxHands: Int
    let winnerIDs: Set<String>

    private var ranked: [PokerSeat] {
        seats.sorted { lhs, rhs in
            if lhs.chips != rhs.chips { return lhs.chips > rhs.chips }
            return lhs.name < rhs.name
        }
    }

    private var title: String {
        if maxHands > 0 && handNumber >= maxHands { return "FINAL STANDINGS" }
        if maxHands > 0 { return "AFTER HAND \(handNumber) OF \(maxHands)" }
        return "STANDINGS"
    }

    var body: some View {
        let rowHeight: CGFloat = seats.count > 6 ? 54 : 62
        return VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .tracking(6)
                .foregroundColor(PKTColors.gold)
                .padding(.bottom, 6)
            ForEach(Array(ranked.enumerated()), id: \.element.id) { i, seat in
                row(rank: i + 1, seat: seat)
                    .frame(height: rowHeight)
                    .tvStaggeredAppear(index: i, step: 0.05)
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 26)
        .frame(width: 760)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "151a26"), Color(hex: "07090e")],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(PKTColors.gold.opacity(0.45), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.7), radius: 30, x: 0, y: 16)
    }

    private func row(rank: Int, seat: PokerSeat) -> some View {
        let isWinner: Bool = winnerIDs.contains(seat.id)
        let delta: Int? = startChips[seat.id].map { seat.chips - $0 }
        return HStack(spacing: 18) {
            Text("\(rank)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(rank == 1 ? PKTColors.gold : Color.white.opacity(0.45))
                .frame(width: 34)
            ShellAvatarToken(id: seat.id, name: seat.name, size: 44)
            Text(seat.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(seat.chips > 0 ? .white : Color.white.opacity(0.4))
                .lineLimit(1)
            if isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PKTColors.gold)
            }
            Spacer(minLength: 12)
            if let delta, delta != 0 {
                Text(delta > 0 ? "+\(PKTFormat.chips(delta))" : "-\(PKTFormat.chips(-delta))")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(delta > 0 ? PKTColors.mint : Color(hex: "fb7185"))
            }
            Text(seat.chips > 0 ? PKTFormat.chips(seat.chips) : "OUT")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundColor(seat.chips > 0 ? .white : Color.white.opacity(0.4))
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isWinner ? PKTColors.gold.opacity(0.14) : Color.white.opacity(0.04))
        )
    }
}
