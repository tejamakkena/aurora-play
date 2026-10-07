import SwiftUI
import UIKit

/// Trivia game show on the phone: category doors, the power picker, answer
/// buttons (with any powers that hit you applied), and clear lock-in and
/// points feedback.
///
/// private_state (games/native_hub/engines/trivia_show.py): phase,
/// secondsLeft, phaseSeconds, round, totalRounds, questionNumber,
/// totalQuestions, score, rank, playerCount, custom, quizName, categories,
/// myVote, chosenCategory, powers, rivals, myPower, hitBy, shieldBlocked,
/// questionID, questionText, choices, category, showChoices, myAnswer,
/// locked, rung, towerHeight, finaleNumber, finaleTotal, winnerID,
/// winnerName, youWon, placement, and during a reveal correctIndex,
/// wasCorrect, pointsEarned, rungMove.
struct TriviaControllerView: View {
    let privateData: [String: Any]
    let onAction: (String, [String: Any]) -> Void

    /// Optimistic locks so a double tap never sends twice; each is keyed to
    /// the decision it belongs to, so a new question or vote clears it.
    @State private var pendingAnswer: Int? = nil
    @State private var pendingAnswerID: String = ""
    @State private var pendingVote: Int? = nil
    @State private var pendingVoteKey: String = ""
    @State private var chosenPower: String? = nil
    @State private var sentPowerKey: String = ""
    @State private var powerKey: String = ""

    private var phase: String { privateData.str("phase") }
    private var seconds: Int { privateData.int("secondsLeft") }
    private var questionID: String { privateData.str("questionID") }
    private var questionNumber: Int { privateData.int("questionNumber") }
    private var choices: [String] { privateData.strings("choices") }
    private var score: Int { privateData.int("score") }

    /// Identifies one category vote (one per round).
    private var voteKey: String { "vote-\(privateData.int("round"))" }
    /// Identifies one power pick (it comes before question n + 1).
    private var currentPowerKey: String { "power-\(questionNumber)" }

    private var myAnswer: Int? {
        if let server = privateData["myAnswer"] as? Int { return server }
        return pendingAnswerID == questionID && !questionID.isEmpty ? pendingAnswer : nil
    }

    private var myVote: Int? {
        if let server = privateData["myVote"] as? Int { return server }
        return pendingVoteKey == voteKey ? pendingVote : nil
    }

    private var myPower: [String: Any]? {
        privateData["myPower"] as? [String: Any]
    }

    private var hasPicked: Bool { myPower != nil || sentPowerKey == currentPowerKey }

    var body: some View {
        ZStack {
            QuizPadBackground()
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == "power_pick" && powerKey != currentPowerKey {
                powerKey = currentPowerKey
                chosenPower = nil
            }
        }
        .onAppear {
            if phase == "power_pick" && powerKey != currentPowerKey {
                powerKey = currentPowerKey
                chosenPower = nil
            }
        }
    }

    // MARK: Header

    private var subtitle: String {
        switch phase {
        case "finale_intro", "finale_question", "finale_reveal":
            return "Final Climb - rung \(privateData.int("rung")) of \(privateData.int("towerHeight", 7))"
        case "summary":
            return "Show's over"
        case "intro":
            return "Get ready"
        default:
            let total: Int = max(privateData.int("totalQuestions"), 1)
            return "Question \(max(questionNumber, 1)) of \(total)"
        }
    }

    private var showsTimer: Bool {
        switch phase {
        case "category_vote", "power_pick", "question", "finale_question": return seconds > 0
        default: return false
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TRIVIA SHOWDOWN")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(QuizPadStyle.gold)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText(value: Double(score)))
                    .animation(.easeOut(duration: 0.6), value: score)
                Text("POINTS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(PhonePlayDesign.text3)
            }
            if showsTimer {
                ControllerTimerChip(secondsLeft: seconds)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
                .padding(.horizontal, 10)
        )
        .padding(.top, 6)
        .animation(PhonePlayDesign.pop, value: showsTimer)
    }

    // MARK: Phases

    @ViewBuilder
    private var content: some View {
        switch phase {
        case "intro":
            QuizPadMessage(symbol: "sparkles",
                           title: "Welcome to the show!",
                           detail: privateData.bool("custom")
                               ? "Tonight's quiz: \(privateData.str("quizName", "Your quiz"))"
                               : "Three rounds, sneaky powers and a Final Climb.")
        case "category_vote":
            categoryVote
        case "category_reveal":
            QuizPadMessage(symbol: "door.left.hand.open",
                           title: privateData.str("chosenCategory", "Mystery"),
                           detail: "That's the category. Eyes on the TV!")
        case "power_pick":
            powerPick
        case "power_reveal":
            powerReveal
        case "question", "finale_question":
            question
        case "reveal", "finale_reveal":
            QuizPadRevealCard(isFinale: phase == "finale_reveal",
                              answered: privateData["myAnswer"] is Int,
                              wasCorrect: privateData.bool("wasCorrect"),
                              points: privateData.int("pointsEarned"),
                              rungMove: privateData.int("rungMove"),
                              correctText: correctText,
                              correctIndex: privateData["correctIndex"] as? Int ?? 0)
                .id("reveal-\(questionID)")
        case "standings":
            QuizPadMessage(symbol: "chart.bar.fill",
                           title: "You're \(ordinal(privateData.int("rank")))",
                           detail: "\(score) points. Watch the standings shuffle on the TV!")
        case "finale_intro":
            QuizPadMessage(symbol: "flag.checkered",
                           title: "The Final Climb!",
                           detail: "You start on rung \(privateData.int("rung")) of \(privateData.int("towerHeight", 7)). Right answers climb, wrong ones slip. First to the top wins!")
        case "summary":
            QuizPadSummary(isWinner: privateData.bool("youWon"),
                           winnerName: privateData.str("winnerName"),
                           rank: privateData.int("placement"),
                           score: score)
        default:
            QuizPadMessage(symbol: "tv", title: "Watch the TV", detail: nil)
        }
    }

    private var correctText: String {
        guard let index = privateData["correctIndex"] as? Int,
              index >= 0, index < choices.count else { return "" }
        return choices[index]
    }

    // MARK: Category vote

    private var categoryVote: some View {
        let categories: [String] = privateData.strings("categories")
        let voted: Int? = myVote
        return ScrollView {
            VStack(spacing: 16) {
                Text(voted == nil ? "Pick a door!" : "Vote locked in!")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(voted == nil ? "The most votes opens. Ties are a coin flip." : "Waiting for everyone else...")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
                ForEach(Array(categories.enumerated()), id: \.offset) { index, name in
                    QuizPadDoorButton(index: index,
                                      name: name,
                                      isPicked: voted == index,
                                      isDimmed: voted != nil && voted != index) {
                        vote(index)
                    }
                }
            }
            .padding(20)
        }
    }

    private func vote(_ index: Int) {
        guard myVote == nil else { return }
        pendingVote = index
        pendingVoteKey = voteKey
        QuizPadHaptics.tap(.heavy)
        onAction("vote_category", ["index": index])
    }

    // MARK: Powers

    @ViewBuilder
    private var powerPick: some View {
        if hasPicked {
            powerLockedView
        } else if let power = chosenPower {
            QuizPadTargetPicker(power: power,
                                rivals: privateData.dicts("rivals"),
                                onPick: { target in send(power: power, target: target) },
                                onBack: { withAnimation(PhonePlayDesign.pop) { chosenPower = nil } })
        } else {
            QuizPadPowerGrid(hasRivals: !privateData.dicts("rivals").isEmpty) { power in
                if power == "shield" {
                    send(power: power, target: nil)
                } else {
                    QuizPadHaptics.tap(.light)
                    withAnimation(PhonePlayDesign.pop) { chosenPower = power }
                }
            }
        }
    }

    private var powerLockedView: some View {
        let power: String = myPower?["power"] as? String ?? chosenPower ?? "shield"
        let targetID: String = myPower?["targetID"] as? String ?? ""
        let match: [String: Any]? = privateData.dicts("rivals")
            .first(where: { ($0["id"] as? String) == targetID })
        let targetName: String = match?["name"] as? String ?? "your rival"
        let line: String = power == "shield"
            ? "Shield up! The first power thrown at you bounces off."
            : "\(QuizPadStyle.powerName(power)) is heading for \(targetName)!"
        return QuizPadMessage(symbol: QuizPadStyle.powerSymbol(power),
                              title: "Power locked in",
                              detail: line,
                              tint: QuizPadStyle.powerColor(power))
    }

    private func send(power: String, target: String?) {
        guard !hasPicked else { return }
        sentPowerKey = currentPowerKey
        chosenPower = power
        QuizPadHaptics.notify(.success)
        var payload: [String: Any] = ["power": power]
        if let target { payload["targetID"] = target }
        onAction("pick_power", payload)
    }

    @ViewBuilder
    private var powerReveal: some View {
        let hits: [[String: Any]] = privateData.dicts("hitBy")
        let blocked: [String] = privateData.strings("shieldBlocked")
        if let first = hits.first {
            let power: String = first["power"] as? String ?? ""
            let from: String = first["fromName"] as? String ?? "Someone"
            QuizPadMessage(symbol: QuizPadStyle.powerSymbol(power),
                           title: "Uh oh!",
                           detail: hits.count > 1
                               ? "You got hit by \(hits.count) powers! Get ready..."
                               : "\(from) \(QuizPadStyle.powerVerb(power)) you! Get ready...",
                           tint: QuizPadStyle.powerColor(power))
                .onAppear { QuizPadHaptics.notify(.warning) }
        } else if let attacker = blocked.first {
            QuizPadMessage(symbol: "shield.fill",
                           title: "Blocked!",
                           detail: "Your shield stopped \(attacker).",
                           tint: QuizPadStyle.powerColor("shield"))
                .onAppear { QuizPadHaptics.notify(.success) }
        } else {
            QuizPadMessage(symbol: "bolt.fill",
                           title: "Powers flying!",
                           detail: "You're safe this time. Watch the TV.")
        }
    }

    // MARK: Question

    private var activePowers: [String] {
        guard phase == "question" else { return [] }
        return privateData.dicts("hitBy").compactMap { $0["power"] as? String }
    }

    private var question: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                let category: String = privateData.str("category")
                if !category.isEmpty {
                    Text(category.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(2)
                        .foregroundColor(QuizPadStyle.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(QuizPadStyle.gold))
                }
                Text(privateData.str("questionText"))
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            if let lockedIndex = myAnswer {
                QuizPadLockedCard(index: lockedIndex,
                                  text: lockedIndex >= 0 && lockedIndex < choices.count
                                      ? choices[lockedIndex] : "")
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            } else if privateData.bool("showChoices") && !choices.isEmpty {
                QuizPadAnswerPanel(choices: choices,
                                   powers: activePowers,
                                   onAnswer: { index in submitAnswer(index) })
                    .id(questionID)
            } else {
                QuizPadMessage(symbol: "eye.fill",
                               title: "Read the question...",
                               detail: activePowers.isEmpty
                                   ? "Answers are coming!"
                                   : "Watch out, you've been hit by a power!")
            }
        }
    }

    private func submitAnswer(_ index: Int) {
        guard myAnswer == nil, !questionID.isEmpty else { return }
        pendingAnswer = index
        pendingAnswerID = questionID
        QuizPadHaptics.tap(.medium)
        onAction("answer", ["choiceIndex": index, "questionID": questionID])
    }

    private func ordinal(_ n: Int) -> String {
        guard n > 0 else { return "in the game" }
        let tens: Int = n % 100
        let suffix: String
        if tens >= 11 && tens <= 13 {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Style

/// Phone Play tokens throughout; the answer and door colours keep the same
/// hue order as the TV's tiles (red, blue, amber, green) so players can
/// match them across the room.
enum QuizPadStyle {
    /// Not Phone Play tokens on purpose: a player tapping tile B has to be
    /// tapping the same colour the TV is showing for B, so the tiles, the
    /// doors and the show's gold are the TV's values verbatim -- see
    /// `TShowPalette` in TVTriviaBoardView.swift. Everything else on this
    /// screen comes from PhonePlayDesign.
    static let gold: Color = Color(hex: "FACC15")
    /// Dark ink for text and icons sitting on the gold.
    static let ink: Color = PhonePlayDesign.bg
    static let tileColors: [Color] = [
        Color(hex: "FF3D7F"), Color(hex: "3D8BFF"), Color(hex: "FFB020"), Color(hex: "22C77A"),
    ]
    static let tileShapes: [String] = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    static let doorColors: [Color] = [
        Color(hex: "FF4D8D"), Color(hex: "3DA5FF"), Color(hex: "FFB020"),
    ]
    /// The TV's avatar palette exactly, so a player is one colour on both
    /// screens.
    static let avatarColors: [Color] = [
        Color(hex: "F43F5E"), Color(hex: "F97316"), Color(hex: "EAB308"), Color(hex: "22C55E"),
        Color(hex: "14B8A6"), Color(hex: "06B6D4"), Color(hex: "3B82F6"), Color(hex: "6366F1"),
        Color(hex: "A855F7"), Color(hex: "EC4899"),
    ]

    static func tile(_ index: Int) -> Color {
        tileColors[((index % tileColors.count) + tileColors.count) % tileColors.count]
    }

    static func shape(_ index: Int) -> String {
        tileShapes[((index % tileShapes.count) + tileShapes.count) % tileShapes.count]
    }

    /// Same FNV-1a hash as the TV's avatar tokens, so a player's colour
    /// matches on both screens.
    static func avatarColor(for id: String) -> Color {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return avatarColors[Int(hash % UInt32(avatarColors.count))]
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
        var out: String = ""
        for word in words.prefix(2) {
            if let first = word.first { out.append(first) }
        }
        return out.isEmpty ? "?" : out.uppercased()
    }

    static func powerSymbol(_ power: String) -> String {
        switch power {
        case "freeze": return "snowflake"
        case "scramble": return "shuffle"
        case "fog": return "cloud.fog.fill"
        case "shield": return "shield.fill"
        default: return "bolt.fill"
        }
    }

    static func powerColor(_ power: String) -> Color {
        switch power {
        case "freeze": return PhonePlayDesign.cyan
        case "scramble": return PhonePlayDesign.pink
        case "fog": return PhonePlayDesign.purple
        case "shield": return PhonePlayDesign.yellow
        default: return PhonePlayDesign.cyan
        }
    }

    static func powerName(_ power: String) -> String {
        switch power {
        case "freeze": return "Freeze"
        case "scramble": return "Scramble"
        case "fog": return "Fog"
        case "shield": return "Shield"
        default: return "Power"
        }
    }

    static func powerVerb(_ power: String) -> String {
        switch power {
        case "freeze": return "froze"
        case "scramble": return "scrambled"
        case "fog": return "fogged"
        default: return "zapped"
        }
    }

    static func powerDetail(_ power: String) -> String {
        switch power {
        case "freeze": return "They tap 5 times to break the ice"
        case "scramble": return "Their answers keep jumping"
        case "fog": return "Their answers start blurry"
        case "shield": return "Block one power aimed at you"
        default: return ""
        }
    }
}

/// Routes Trivia's haptics through PhonePlayHaptics, so they feel the same
/// as every other phone screen.
enum QuizPadHaptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        switch style {
        case .heavy: PhonePlayHaptics.thump()
        case .rigid: PhonePlayHaptics.rigid()
        default: PhonePlayHaptics.tap()
        }
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        switch type {
        case .success: PhonePlayHaptics.success()
        case .warning: PhonePlayHaptics.warning()
        case .error: PhonePlayHaptics.error()
        @unknown default: PhonePlayHaptics.tap()
        }
    }
}

// MARK: - Pieces

/// The Phone Play backdrop with a soft game-show glow at the top.
private struct QuizPadBackground: View {
    var body: some View {
        PhonePlayDesign.bg
            .overlay(
                RadialGradient(colors: [PhonePlayDesign.purple.opacity(0.28), Color.clear],
                               center: .top, startRadius: 0, endRadius: 420)
            )
            .ignoresSafeArea()
    }
}

private struct QuizPadMessage: View {
    let symbol: String
    let title: String
    let detail: String?
    var tint: Color = QuizPadStyle.gold

    @State private var popped: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 110, height: 110)
                .background(Circle().fill(tint.opacity(0.85)))
                .shadow(color: tint.opacity(0.6), radius: 18)
                .scaleEffect(popped ? 1 : 0.4)
                .phonePlayIdle(dy: 4, scale: 0.03, duration: 1.6)
            Text(title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { popped = true }
        }
    }
}

private struct QuizPadDoorButton: View {
    let index: Int
    let name: String
    let isPicked: Bool
    let isDimmed: Bool
    let action: () -> Void

    private var color: Color { QuizPadStyle.doorColors[index % QuizPadStyle.doorColors.count] }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Text("\(index + 1)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Color.white))
                Text(name)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "door.left.hand.closed")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(color.opacity(0.55))
                        .offset(y: 6)
                    RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                        .fill(LinearGradient(colors: [color, color.opacity(0.8)],
                                             startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: isPicked ? 4 : 0)
            )
        }
        .buttonStyle(PhonePlayPressStyle())
        .disabled(isPicked || isDimmed)
        .opacity(isDimmed ? 0.35 : 1)
        .scaleEffect(isPicked ? 1.03 : 1)
        .animation(PhonePlayDesign.pop, value: isPicked)
    }
}

private struct QuizPadPowerGrid: View {
    let hasRivals: Bool
    let onPick: (String) -> Void

    private let powers: [String] = ["freeze", "scramble", "fog", "shield"]
    private let columns: [GridItem] = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Power up!")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("Throw one at a rival, or shield yourself.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(powers, id: \.self) { power in
                        let usable: Bool = power == "shield" || hasRivals
                        Button {
                            onPick(power)
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: QuizPadStyle.powerSymbol(power))
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 74, height: 74)
                                    .background(Circle().fill(QuizPadStyle.powerColor(power)))
                                    .shadow(color: QuizPadStyle.powerColor(power).opacity(0.6), radius: 10)
                                Text(QuizPadStyle.powerName(power))
                                    .font(.system(size: 21, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                Text(QuizPadStyle.powerDetail(power))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(PhonePlayDesign.text2)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 190)
                            .background(
                                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                                    .fill(PhonePlayDesign.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                                    .strokeBorder(QuizPadStyle.powerColor(power).opacity(0.7), lineWidth: 2)
                            )
                        }
                        .buttonStyle(PhonePlayPressStyle())
                        .disabled(!usable)
                        .opacity(usable ? 1 : 0.35)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct QuizPadTargetPicker: View {
    let power: String
    let rivals: [[String: Any]]
    let onPick: (String) -> Void
    let onBack: () -> Void

    private struct Rival: Identifiable {
        let id: String
        let name: String
    }

    private var list: [Rival] {
        rivals.compactMap { d -> Rival? in
            guard let id = d["id"] as? String else { return nil }
            return Rival(id: id, name: d["name"] as? String ?? "Player")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button(action: {
                        PhonePlayHaptics.tap()
                        onBack()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("Back")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(PhonePlayPressStyle())
                    Spacer()
                }
                Image(systemName: QuizPadStyle.powerSymbol(power))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(QuizPadStyle.powerColor(power)))
                Text("Who gets the \(QuizPadStyle.powerName(power))?")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                ForEach(list) { rival in
                    Button {
                        onPick(rival.id)
                    } label: {
                        HStack(spacing: 14) {
                            Text(QuizPadStyle.initials(rival.name))
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(QuizPadStyle.avatarColor(for: rival.id)))
                            Text(rival.name)
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "scope")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(QuizPadStyle.powerColor(power))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .fill(PhonePlayDesign.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                                .strokeBorder(QuizPadStyle.powerColor(power).opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PhonePlayPressStyle())
                }
            }
            .padding(20)
        }
    }
}

/// The four answers, with whatever powers hit this phone applied: Freeze
/// covers them with ice until tapped five times, Scramble reshuffles them
/// every 1.5 seconds, Fog blurs them and clears over 3 seconds. Built fresh
/// for every question (the caller sets `.id(questionID)`).
private struct QuizPadAnswerPanel: View {
    let choices: [String]
    let powers: [String]
    let onAnswer: (Int) -> Void

    static let iceTapsNeeded: Int = 5

    @State private var order: [Int] = []
    @State private var iceTaps: Int = 0
    @State private var iceGone: Bool = false
    @State private var fogBlur: CGFloat = 0

    private var frozen: Bool { powers.contains("freeze") && !iceGone }
    private var scrambled: Bool { powers.contains("scramble") }
    private var fogged: Bool { powers.contains("fog") }

    private var displayOrder: [Int] {
        order.count == choices.count ? order : Array(choices.indices)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ForEach(displayOrder, id: \.self) { index in
                    QuizPadAnswerButton(index: index, text: choices[index]) {
                        onAnswer(index)
                    }
                }
            }
            .blur(radius: fogBlur)
            .allowsHitTesting(!frozen)
            if fogged && fogBlur > 0.5 {
                Image(systemName: "cloud.fog.fill")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .allowsHitTesting(false)
            }
            if powers.contains("freeze") && !iceGone {
                QuizPadIce(taps: iceTaps, needed: QuizPadAnswerPanel.iceTapsNeeded) {
                    crackIce()
                }
                .transition(.scale(scale: 1.3).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            order = Array(choices.indices)
            if fogged {
                fogBlur = 16
                withAnimation(.linear(duration: 3.0)) { fogBlur = 0 }
            }
        }
        .task {
            guard scrambled, choices.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                var next: [Int] = displayOrder
                let before: [Int] = next
                while next == before {
                    next.shuffle()
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { order = next }
            }
        }
    }

    private func crackIce() {
        guard !iceGone else { return }
        iceTaps += 1
        if iceTaps >= QuizPadAnswerPanel.iceTapsNeeded {
            QuizPadHaptics.notify(.success)
            withAnimation(.easeOut(duration: 0.35)) { iceGone = true }
        } else {
            QuizPadHaptics.tap(.rigid)
        }
    }
}

private struct QuizPadIce: View {
    let taps: Int
    let needed: Int
    let onTap: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "E0F7FF"), Color(hex: "93D8F7"), Color(hex: "5BB8E8")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.96)
            QuizPadCracks(count: taps)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            VStack(spacing: 10) {
                Image(systemName: "snowflake")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color(hex: "0369A1").opacity(0.6), radius: 4)
                Text("FROZEN!")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "0C4A6E"))
                Text("Tap \(max(needed - taps, 0)) more times to break the ice")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "075985"))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
        }
        .scaleEffect(1 + CGFloat(taps) * 0.012)
        .rotationEffect(.degrees(taps % 2 == 0 ? 0 : 1.2))
        .animation(.spring(response: 0.15, dampingFraction: 0.3), value: taps)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

/// Crack lines that grow with every tap on the ice.
private struct QuizPadCracks: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let starts: [CGPoint] = [
            CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.3, y: 0.35), CGPoint(x: 0.7, y: 0.6),
            CGPoint(x: 0.4, y: 0.7), CGPoint(x: 0.62, y: 0.3),
        ]
        let angles: [Double] = [0.3, 2.2, 4.1, 5.3, 1.2]
        for i in 0..<min(count, starts.count) {
            let origin = CGPoint(x: rect.minX + starts[i].x * rect.width,
                                 y: rect.minY + starts[i].y * rect.height)
            for branch in 0..<3 {
                let angle: Double = angles[i] + Double(branch) * 2.1
                var point = origin
                path.move(to: point)
                for segment in 1...3 {
                    let length: CGFloat = rect.width * 0.07
                    let wobble: Double = angle + (segment % 2 == 0 ? 0.35 : -0.3)
                    point = CGPoint(x: point.x + CGFloat(cos(wobble)) * length,
                                    y: point.y + CGFloat(sin(wobble)) * length)
                    path.addLine(to: point)
                }
            }
        }
        return path
    }
}

private struct QuizPadAnswerButton: View {
    let index: Int
    let text: String
    let action: () -> Void

    private var color: Color { QuizPadStyle.tile(index) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: QuizPadStyle.shape(index))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundColor(color)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.white))
                Text(text)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(color.opacity(0.5))
                        .offset(y: 5)
                    RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                        .fill(LinearGradient(colors: [color, color.opacity(0.82)],
                                             startPoint: .top, endPoint: .bottom))
                }
            )
        }
        .buttonStyle(PhonePlayPressStyle())
    }
}

private struct QuizPadLockedCard: View {
    let index: Int
    let text: String

    @State private var popped: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(QuizPadStyle.ink)
                .frame(width: 84, height: 84)
                .background(Circle().fill(QuizPadStyle.gold))
                .scaleEffect(popped ? 1 : 0.3)
            Text("Locked in!")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
            HStack(spacing: 12) {
                Image(systemName: QuizPadStyle.shape(index))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(QuizPadStyle.tile(index))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white))
                Text(text)
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                    .fill(QuizPadStyle.tile(index).opacity(0.85))
            )
            Text("Fingers crossed. Watch the TV!")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text2)
        }
        .padding(.top, 20)
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { popped = true }
        }
    }
}

private struct QuizPadRevealCard: View {
    let isFinale: Bool
    let answered: Bool
    let wasCorrect: Bool
    let points: Int
    let rungMove: Int
    let correctText: String
    let correctIndex: Int

    @State private var shownPoints: Int = 0
    @State private var popped: Bool = false

    private var tint: Color {
        if wasCorrect { return PhonePlayDesign.green }
        return answered ? PhonePlayDesign.red : PhonePlayDesign.purple
    }

    private var title: String {
        if wasCorrect { return isFinale ? "You climbed!" : "Correct!" }
        if !answered { return "Too slow!" }
        return isFinale && rungMove < 0 ? "You slipped!" : "Not quite!"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: wasCorrect ? (isFinale ? "arrow.up" : "checkmark") : (answered ? "xmark" : "hourglass"))
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 120, height: 120)
                .background(Circle().fill(tint))
                .shadow(color: tint.opacity(0.7), radius: 20)
                .scaleEffect(popped ? 1 : 0.3)
            Text(title)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
            if points > 0 {
                Text("+\(shownPoints)")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundColor(QuizPadStyle.gold)
            }
            if !wasCorrect && !correctText.isEmpty {
                VStack(spacing: 8) {
                    Text("The answer was")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text2)
                    HStack(spacing: 10) {
                        Image(systemName: QuizPadStyle.shape(correctIndex))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundColor(QuizPadStyle.tile(correctIndex))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white))
                        Text(correctText)
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: PhonePlayDesign.buttonRadius, style: .continuous)
                            .fill(QuizPadStyle.tile(correctIndex).opacity(0.8))
                    )
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { popped = true }
            QuizPadHaptics.notify(wasCorrect ? .success : .error)
        }
        .task {
            guard points > 0 else { return }
            let steps: Int = 20
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 35_000_000)
                if Task.isCancelled { return }
                shownPoints = points * step / steps
            }
        }
    }
}

private struct QuizPadSummary: View {
    let isWinner: Bool
    let winnerName: String
    let rank: Int
    let score: Int

    @State private var popped: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isWinner ? "crown.fill" : "star.fill")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(isWinner ? QuizPadStyle.ink : .white)
                .frame(width: 140, height: 140)
                .background(Circle().fill(isWinner ? QuizPadStyle.gold : PhonePlayDesign.purple))
                .shadow(color: QuizPadStyle.gold.opacity(isWinner ? 0.8 : 0.2), radius: 24)
                .scaleEffect(popped ? 1 : 0.3)
                .phonePlayIdle(dy: 4, degrees: isWinner ? 4 : 0, scale: 0.03, duration: 1.4)
            Text(isWinner ? "You win the show!" : (winnerName.isEmpty ? "What a show!" : "\(winnerName) wins!"))
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if rank > 0 {
                Text("You finished #\(rank) with \(score) points")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(PhonePlayDesign.pop) { popped = true }
            QuizPadHaptics.notify(isWinner ? .success : .warning)
        }
    }
}
