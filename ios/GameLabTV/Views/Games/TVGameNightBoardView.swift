import SwiftUI

/// The TV side of Game Night.
///
/// Between games this view *is* the screen: a welcome that waits for the host to
/// start, the voiced welcome, the lineup, each game's intro, the tally and the
/// finale. While a hosted game is on, it steps aside and shows that game's own
/// board unchanged -- see `GameNightEngine` on the server for why the night's
/// data travels on its own `night_state` channel instead of `game_state`.
///
/// Speech: each `announce` the server publishes is read aloud once (keyed by its
/// id), and when the voice finishes the TV tells the server so the show moves on.

// MARK: - Model

@MainActor
final class NightTVModel: ObservableObject {
    @Published private(set) var state = NightState()

    private let socket = GameSocketManager.shared
    private var roomCode = ""

    func bind(roomCode: String) {
        self.roomCode = roomCode
        socket.on(.nightState) { [weak self] (r: NightStateResponse) in
            guard let self, r.roomCode == self.roomCode else { return }
            let next = NightState(dict: r.night.mapValues(\.value))
            // Arrives every second; only republish when something changed.
            if next != self.state { self.state = next }
        }
    }

    func unbind() {
        socket.off(.nightState)
    }

    /// Sends a night verb on the TV's own behalf (it has no seat in the room, so
    /// the server treats it as the TV fallback host).
    func send(_ action: String, _ data: [String: Any] = [:]) {
        guard !roomCode.isEmpty else { return }
        socket.emit(.gameAction, payload: GameActionPayload(
            roomCode: roomCode,
            playerID: AppConstants.deviceID,
            action: action,
            data: data.mapValues { AnyCodable($0) }
        ))
    }
}

// MARK: - Board

struct TVGameNightBoardView: View {
    let room: Room

    @StateObject private var model = NightTVModel()
    /// The newest announcement already handed to the voice.
    @State private var spokenID = 0

    private var state: NightState { model.state }

    private var hostedGame: GameID? {
        guard state.phase == "playing", let id = state.currentGame?.id else { return nil }
        return GameID(rawValue: id)
    }

    var body: some View {
        ZStack {
            if let game = hostedGame {
                // The hosted game's own board, exactly as it appears outside a
                // night. The id restarts it cleanly for every new game.
                TVGameBoardView(room: Room(code: room.code, gameID: game,
                                           players: room.players, state: .playing))
                    .id("\(state.gameIndex)-\(game.rawValue)")
            } else {
                stage
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.phase)
        .onAppear { model.bind(roomCode: room.code) }
        .onDisappear {
            model.unbind()
            Announcer.shared.stop()
        }
        .onChange(of: state.announce) { _, announce in
            speak(announce)
        }
    }

    private func speak(_ announce: NightAnnouncement?) {
        guard let announce, announce.id != spokenID else { return }
        spokenID = announce.id
        let style = Announcer.Style(language: announce.language,
                                    rate: announce.rate, pitch: announce.pitch)
        let id = announce.id
        let preview = announce.preview
        let model = self.model
        Announcer.shared.speak(announce.lines, style: style) {
            // A preview from the setup screen is just a taste -- nothing is
            // waiting on it, so don't report back.
            guard !preview else { return }
            Task { @MainActor in
                model.send("night_announce_done", ["id": id])
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch state.phase {
        case "welcome":
            NightWelcomeStage(state: state)
        case "lineup":
            NightLineupStage(state: state)
        case "intro":
            NightIntroStage(state: state, playerCount: room.players.count)
        case "interlude":
            NightInterludeStage(state: state)
        case "finale":
            NightFinaleStage(state: state)
        case "done":
            NightDoneStage()
        default:
            NightSetupStage(state: state, roomCode: room.code, onStart: {
                Task { @MainActor in model.send("night_start") }
            })
        }
    }
}

// MARK: - Stages

/// Shown until the host presses start -- the "Welcome to Venkat's Birthday
/// Party" screen that sits on the TV while guests arrive.
private struct NightSetupStage: View {
    let state: NightState
    /// From the room itself, so the code is on screen before the first
    /// `night_state` has had a chance to arrive.
    let roomCode: String
    let onStart: () -> Void

    @State private var glow = false

    private var waitingLine: String {
        if let host = state.hostName {
            return "Waiting for \(host) to start the night"
        }
        return "Open Aurora Play on your iPad and enter the code to host"
    }

    private var lineupLine: String {
        state.lineup.map { "\($0.emoji) \($0.name)" }.joined(separator: "   ")
    }

    var body: some View {
        ZStack {
            NightBackdrop(accent: Color(hex: "FF3CAC"))
            VStack(spacing: 28) {
                Spacer(minLength: 0)

                Text(state.emoji)
                    .font(.system(size: 120))
                    .scaleEffect(glow ? 1.08 : 1.0)

                VStack(spacing: 6) {
                    Text("WELCOME TO")
                        .font(.system(size: 26, weight: .bold)).tracking(8)
                        .foregroundColor(.white.opacity(0.6))
                    Text(state.title)
                        .font(.system(size: 84, weight: .black, design: .rounded))
                        .foregroundStyle(NightStyle.titleGradient)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 100)
                }

                VStack(spacing: 6) {
                    Text("JOIN WITH CODE")
                        .font(.system(size: 20, weight: .bold)).tracking(5)
                        .foregroundColor(.white.opacity(0.45))
                    Text(roomCode)
                        .font(.system(size: 64, weight: .black, design: .monospaced))
                        .kerning(10)
                        .foregroundColor(.cyan)
                }

                Text(waitingLine)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                if !state.guests.isEmpty {
                    NightGuestChips(guests: state.guests)
                }

                if !state.lineup.isEmpty {
                    Text(lineupLine)
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 120)
                }

                Spacer(minLength: 0)

                // Fallback for a night run without the iPad.
                Button(action: onStart) {
                    Label("Start the Night", systemImage: "play.fill")
                        .font(.title3.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.cyan))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

private struct NightWelcomeStage: View {
    let state: NightState

    @State private var appeared = false

    var body: some View {
        ZStack {
            NightBackdrop(accent: Color(hex: "FF3CAC"))
            NightConfetti(symbols: NightStyle.confetti(for: state.occasion))
            VStack(spacing: 30) {
                Text(state.emoji)
                    .font(.system(size: 160))
                    .scaleEffect(appeared ? 1.0 : 0.3)
                Text("WELCOME TO")
                    .font(.system(size: 32, weight: .bold)).tracking(10)
                    .foregroundColor(.white.opacity(0.7))
                Text(state.title)
                    .font(.system(size: 108, weight: .black, design: .rounded))
                    .foregroundStyle(NightStyle.titleGradient)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 90)
                    .scaleEffect(appeared ? 1.0 : 0.85)
                if !state.cheer.isEmpty {
                    Text(state.cheer)
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 100)
                }
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

private struct NightLineupStage: View {
    let state: NightState

    @State private var shown = false

    private var columns: [GridItem] {
        let count = state.lineup.count > 6 ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 24), count: count)
    }

    var body: some View {
        ZStack {
            NightBackdrop(accent: Color(hex: "22D3EE"))
            VStack(spacing: 36) {
                VStack(spacing: 8) {
                    Text("TONIGHT'S GAMES")
                        .font(.system(size: 28, weight: .bold)).tracking(8)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(state.lineup.count) \(state.lineup.count == 1 ? "game" : "games") lined up")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(Array(state.lineup.enumerated()), id: \.element.id) { index, item in
                        NightLineupRow(number: index + 1, item: item)
                            .opacity(shown ? 1 : 0)
                            .offset(x: shown ? 0 : -60)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8)
                                        .delay(Double(index) * 0.35), value: shown)
                    }
                }
                .padding(.horizontal, 140)
            }
        }
        .onAppear { shown = true }
    }
}

private struct NightIntroStage: View {
    let state: NightState
    let playerCount: Int

    @State private var appeared = false

    var body: some View {
        ZStack {
            NightBackdrop(accent: Color(hex: "A855F7"))
            VStack(spacing: 24) {
                Text("GAME \(state.gameIndex) OF \(state.gameCount)")
                    .font(.system(size: 28, weight: .bold)).tracking(8)
                    .foregroundColor(.white.opacity(0.6))
                Text(state.currentGame?.emoji ?? "🎮")
                    .font(.system(size: 190))
                    .scaleEffect(appeared ? 1.0 : 0.4)
                Text(state.currentGame?.name ?? "")
                    .font(.system(size: 92, weight: .black, design: .rounded))
                    .foregroundStyle(NightStyle.titleGradient)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                Text(state.currentGame?.blurb ?? "")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 160)
                Text("\(playerCount) playing")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.45))
            }
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { appeared = true }
        }
    }
}

/// Between games: how that one went, and where the night stands.
private struct NightInterludeStage: View {
    let state: NightState

    private var upNext: String {
        if let next = state.lineup.first(where: { $0.state == "next" }) {
            return "Up next: \(next.emoji) \(next.name)"
        }
        return "That was the last game!"
    }

    var body: some View {
        ZStack {
            NightBackdrop(accent: Color(hex: "FACC15"))
            VStack(spacing: 34) {
                if let recap = state.lastGame {
                    VStack(spacing: 10) {
                        Text("\(recap.emoji) \(recap.name)")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        if recap.skipped {
                            Text("Skipped")
                                .font(.system(size: 60, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        } else if let winner = recap.winner {
                            Text("🏆 \(winner) wins!")
                                .font(.system(size: 76, weight: .black, design: .rounded))
                                .foregroundStyle(NightStyle.titleGradient)
                        } else {
                            Text("Everyone's a winner")
                                .font(.system(size: 60, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }

                VStack(spacing: 14) {
                    Text("THE NIGHT SO FAR")
                        .font(.system(size: 24, weight: .bold)).tracking(6)
                        .foregroundColor(.white.opacity(0.5))
                    NightStandingsList(standings: Array(state.standings.prefix(6)))
                }

                Text(upNext)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 160)
        }
    }
}

private struct NightFinaleStage: View {
    let state: NightState

    @State private var appeared = false

    private var champion: NightStanding? {
        guard let top = state.standings.first, top.points > 0 else { return nil }
        return top
    }

    var body: some View {
        ZStack {
            NightBackdrop(accent: Color(hex: "FACC15"))
            NightConfetti(symbols: ["🏆", "🎉", "⭐️", "✨", "🥳"])
            VStack(spacing: 26) {
                Text("🏆")
                    .font(.system(size: 130))
                    .scaleEffect(appeared ? 1.0 : 0.3)
                Text(champion == nil ? "WHAT A NIGHT" : "TONIGHT'S CHAMPION")
                    .font(.system(size: 30, weight: .bold)).tracking(8)
                    .foregroundColor(.white.opacity(0.7))
                if let champion {
                    Text(champion.name)
                        .font(.system(size: 110, weight: .black, design: .rounded))
                        .foregroundStyle(NightStyle.titleGradient)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text("\(champion.points) points")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                NightStandingsList(standings: Array(state.standings.prefix(5)))
                    .padding(.top, 10)
                Text(state.title)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 160)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

private struct NightDoneStage: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("🎉").font(.system(size: 100))
            Text("Thanks for playing!")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Pieces

private enum NightStyle {
    static let titleGradient = LinearGradient(
        colors: [Color(hex: "FF3CAC"), Color(hex: "FFB347"), Color(hex: "22D3EE")],
        startPoint: .leading, endPoint: .trailing)

    static func confetti(for occasion: String) -> [String] {
        switch occasion {
        case "birthday":     return ["🎂", "🎈", "🎉", "🎁", "✨", "🥳"]
        case "anniversary":  return ["💞", "🥂", "🌹", "✨", "🎉"]
        case "housewarming": return ["🏡", "🔑", "✨", "🎉", "🪴"]
        case "festival":     return ["🪔", "✨", "🎆", "🎉", "🌼"]
        case "newyear":      return ["🎆", "🥂", "✨", "🎉", "🕛"]
        default:             return ["🎉", "✨", "🎊", "🥳", "⭐️"]
        }
    }
}

private struct NightBackdrop: View {
    let accent: Color

    var body: some View {
        RadialGradient(colors: [accent.opacity(0.35), .clear],
                       center: .center, startRadius: 40, endRadius: 900)
            .ignoresSafeArea()
    }
}

/// Emoji drifting down the screen. Each piece is one repeating animation with
/// its own speed and delay, so the whole effect costs nothing when idle.
private struct NightConfetti: View {
    let symbols: [String]

    @State private var falling = false

    private let count = 26

    private func startX(_ i: Int, _ width: CGFloat) -> CGFloat {
        CGFloat((i * 37) % 100) / 100 * width
    }

    private func size(_ i: Int) -> CGFloat {
        CGFloat(30 + (i * 11) % 30)
    }

    private func duration(_ i: Int) -> Double {
        Double(6 + (i * 3) % 6)
    }

    private func delay(_ i: Int) -> Double {
        Double(i % 7) * 0.7
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<count, id: \.self) { i in
                Text(symbols[i % max(symbols.count, 1)])
                    .font(.system(size: size(i)))
                    .position(x: startX(i, geo.size.width),
                              y: falling ? geo.size.height + 80 : -80)
                    .rotationEffect(.degrees(falling ? Double(i * 50) : 0))
                    .animation(.linear(duration: duration(i))
                                .repeatForever(autoreverses: false)
                                .delay(delay(i)), value: falling)
            }
        }
        .allowsHitTesting(false)
        .onAppear { falling = true }
    }
}

private struct NightGuestChips: View {
    let guests: [NightGuest]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(guests.prefix(10)) { guest in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.purple.opacity(0.5))
                        .frame(width: 34, height: 34)
                        .overlay(Text(String(guest.name.prefix(1)))
                            .font(.headline).foregroundColor(.white))
                    Text(guest.name)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                    if guest.isHost {
                        Text("HOST").font(.caption2.bold()).foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            if guests.count > 10 {
                Text("+\(guests.count - 10)")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

private struct NightLineupRow: View {
    let number: Int
    let item: NightLineupItem

    var body: some View {
        HStack(spacing: 20) {
            Text("\(number)")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.cyan))
            Text(item.emoji).font(.system(size: 50))
            Text(item.name)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.08)))
    }
}

private struct NightStandingsList: View {
    let standings: [NightStanding]

    private func medal(_ index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "\(index + 1)."
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 20) {
                    Text(medal(index))
                        .font(.system(size: 34))
                        .frame(width: 60)
                    Text(row.name)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(row.points)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(index == 0 ? .yellow : .cyan)
                }
                .padding(.horizontal, 28).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 16)
                    .fill(index == 0 ? Color.yellow.opacity(0.12) : Color.white.opacity(0.06)))
            }
        }
    }
}
