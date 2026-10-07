import SwiftUI

/// Shared pieces for the two talk games on the TV (Hot Takes and
/// 20 Questions, games/native_hub/engines/talk.py): the player row as it
/// arrives in `boardState.players`, the colour story, a stage backdrop,
/// the top bar, a countdown ring and the player pods. Everything is built
/// on the Shell design system (TVShellTheme.swift) and plain tvOS 17
/// SwiftUI.

// MARK: - Players

struct TalkPlayer: Identifiable, Equatable {
    let id: String
    let name: String
    let score: Int
    let isHost: Bool
    let isBot: Bool
    let connected: Bool

    static func list(from value: Any?) -> [TalkPlayer] {
        let raw: [Any] = value as? [Any] ?? []
        return raw.compactMap { item -> TalkPlayer? in
            guard let d = item as? [String: Any], let id = d["id"] as? String else { return nil }
            return TalkPlayer(id: id,
                              name: d["name"] as? String ?? "Player",
                              score: d["score"] as? Int ?? 0,
                              isHost: d["isHost"] as? Bool ?? false,
                              isBot: d["isBot"] as? Bool ?? false,
                              connected: d["connected"] as? Bool ?? true)
        }
    }
}

// MARK: - Palette

enum TalkPalette {
    /// Hot Takes: FOR is warm, AGAINST is cool. Same two pairs as
    /// TalkPad.forColors / againstColors on the phone.
    static let forColor = TVTheme.orange
    static let forColor2 = TVTheme.red
    static let againstColor = TVTheme.cyan
    static let againstColor2 = TVTheme.blue

    /// 20 Questions verdicts, matching TalkPad.verdictColor on the phone.
    static let yes = TVTheme.green
    static let no = TVTheme.red
    static let sometimes = TVTheme.yellow
    static let wrongGuess = TVTheme.purple

    static let gold = TVTheme.gold

    /// A JSON number that may have arrived as an Int or a Double.
    static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    static func verdictColor(_ answer: String) -> Color {
        switch answer {
        case "yes":       return yes
        case "no":        return no
        case "sometimes": return sometimes
        default:          return wrongGuess
        }
    }
}

// MARK: - Stage backdrop

/// The Shell ambient field with two coloured stage lights on top, one from
/// each side. Their strength animates, so a board can swing the light
/// from the FOR side to the AGAINST side.
struct TalkStageBackground: View {
    let leftColor: Color
    let leftStrength: Double
    let rightColor: Color
    let rightStrength: Double

    var body: some View {
        ZStack {
            ShellAmbientBackground(isAnimated: true, showsFloor: true)
            GeometryReader { proxy in
                let w: CGFloat = proxy.size.width
                let h: CGFloat = proxy.size.height
                ZStack {
                    RadialGradient(colors: [leftColor.opacity(0.55), leftColor.opacity(0)],
                                   center: UnitPoint(x: 0.0, y: 0.45),
                                   startRadius: 0,
                                   endRadius: w * 0.6)
                        .opacity(leftStrength)
                    RadialGradient(colors: [rightColor.opacity(0.55), rightColor.opacity(0)],
                                   center: UnitPoint(x: 1.0, y: 0.45),
                                   startRadius: 0,
                                   endRadius: w * 0.6)
                        .opacity(rightStrength)
                }
                .frame(width: w, height: h)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.8), value: leftStrength)
            .animation(.easeInOut(duration: 0.8), value: rightStrength)
        }
    }
}

// MARK: - Top bar

struct TalkTopBar: View {
    let symbol: String
    let title: String
    let round: Int
    let totalRounds: Int
    let phaseLabel: String
    let accent: Color

    var body: some View {
        HStack(spacing: 24) {
            ShellIconOrb(symbol: symbol, top: accent, bottom: accent.opacity(0.55),
                         accent: accent, size: 62, isLit: true)
            Text(title.uppercased())
                .font(ShellTheme.display(36, weight: .black))
                .tracking(5)
                .foregroundColor(.white)
            if !phaseLabel.isEmpty {
                ShellChip(systemImage: "sparkles", text: phaseLabel, tint: accent)
                    .id(phaseLabel)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            Spacer()
            if totalRounds > 0 {
                HStack(spacing: 10) {
                    Text("ROUND")
                        .font(ShellTheme.eyebrow(20))
                        .tracking(4)
                        .foregroundColor(ShellTheme.textTertiary)
                    Text("\(round) / \(totalRounds)")
                        .font(ShellTheme.display(30))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.default, value: round)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }
        }
        .padding(.horizontal, 70)
        .padding(.top, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: phaseLabel)
    }
}

// MARK: - Countdown ring

/// A ring that drains linearly between the server's 1 Hz updates, with the
/// number in the middle. Turns red and pulses in the last five seconds.
struct TalkTimerRing: View {
    let secondsLeft: Int
    let total: Int
    let tint: Color
    let label: String
    var size: CGFloat = 200

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(secondsLeft) / CGFloat(total)))
    }

    private var urgent: Bool { secondsLeft > 0 && secondsLeft <= 5 }

    var body: some View {
        let color: Color = urgent ? TalkPalette.no : tint
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: size * 0.07)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.7), radius: size * 0.06)
                .animation(.linear(duration: 1), value: fraction)
            VStack(spacing: 0) {
                Text("\(secondsLeft)")
                    .font(ShellTheme.display(size * 0.36, weight: .black))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: secondsLeft)
                if !label.isEmpty {
                    Text(label)
                        .font(ShellTheme.eyebrow(size * 0.09))
                        .tracking(3)
                        .foregroundColor(color)
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(urgent && secondsLeft % 2 == 0 ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: secondsLeft)
    }
}

// MARK: - Player pods

/// A small label shown above a pod ("FOR", "ANSWERER", "VOTED").
struct TalkPodBadge: Equatable {
    let text: String
    let color: Color
}

struct TalkPodRow: View {
    let players: [TalkPlayer]
    var badges: [String: TalkPodBadge] = [:]
    var checked: Set<String> = []
    var spotlight: Set<String> = []

    var body: some View {
        let big: Bool = players.count <= 6
        let size: CGFloat = big ? 70 : 58
        HStack(alignment: .bottom, spacing: big ? 30 : 18) {
            ForEach(players) { player in
                TalkPod(player: player,
                        size: size,
                        badge: badges[player.id],
                        isChecked: checked.contains(player.id),
                        isSpotlit: spotlight.contains(player.id))
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }
}

struct TalkPod: View {
    let player: TalkPlayer
    let size: CGFloat
    let badge: TalkPodBadge?
    let isChecked: Bool
    let isSpotlit: Bool

    @State private var hop: Int = 0

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let badge {
                    Text(badge.text)
                        .font(ShellTheme.eyebrow(16))
                        .tracking(2)
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(badge.color))
                        .shadow(color: badge.color.opacity(0.6), radius: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 28)
            ShellAvatarToken(id: player.id, name: player.name, size: size,
                             isHost: player.isHost, isBot: player.isBot, isReady: isChecked)
                .shellHop(trigger: hop, height: 30)
                .opacity(player.connected ? 1 : 0.35)
            Text(player.name)
                .font(ShellTheme.display(20, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: size + 50)
            Text("\(player.score)")
                .font(ShellTheme.display(23, weight: .black))
                .foregroundColor(TalkPalette.gold)
                .contentTransition(.numericText(value: Double(player.score)))
                .animation(.easeOut(duration: 0.8), value: player.score)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .fill(isSpotlit ? Color.white.opacity(0.16) : Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShellTheme.cardRadius, style: .continuous)
                .strokeBorder((badge?.color ?? Color.white).opacity(isSpotlit ? 0.8 : 0), lineWidth: 2)
        )
        .scaleEffect(isSpotlit ? 1.06 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isSpotlit)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: badge)
        .onChange(of: isChecked) { _, nowChecked in
            if nowChecked { hop += 1 }
        }
        .onChange(of: player.score) { oldValue, newValue in
            if newValue > oldValue { hop += 1 }
        }
    }
}

// MARK: - Points chip

/// "+750" in a gold capsule.
struct TalkPointsChip: View {
    let points: Int
    var color: Color = TalkPalette.gold

    var body: some View {
        Text(points >= 0 ? "+\(points)" : "\(points)")
            .font(ShellTheme.display(30, weight: .black))
            .foregroundColor(.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Capsule().fill(color))
            .shadow(color: color.opacity(0.6), radius: 12)
    }
}
