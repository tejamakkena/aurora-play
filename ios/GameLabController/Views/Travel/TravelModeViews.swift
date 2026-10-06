import SwiftUI

// MARK: - Travel Mode views
//
// Three screens: pick (Riddles / Quiz / Mix), a short "waking up" beat,
// and the play screen. The play screen is readable at arm's length and
// every button is optional -- the quizmaster runs the game by voice.

enum TravelDesign {
    static let bg        = Color(hex: "0B0B12")
    static let surface   = Color(hex: "15151F")
    static let surface2  = Color(hex: "1E1E2B")
    static let primary   = Color(hex: "2FE07A")
    static let info      = Color(hex: "38D6F5")
    static let warning   = Color(hex: "FFC531")
    static let riddle    = Color(hex: "B07CFF")
    static let text2     = Color(hex: "A7A7B8")
    static let text3     = Color(hex: "6B6B7E")

    static let cardRadius: CGFloat = 20
}

// MARK: - Root

struct TravelModeRootView: View {
    @EnvironmentObject var vm: ControllerRootViewModel
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        ZStack {
            TravelDesign.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Group {
                    switch travel.stage {
                    case .pick:     TravelPickView(travel: travel)
                    case .starting: TravelStartingView()
                    case .playing:  TravelPlayView(travel: travel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TravelSafetyFooter()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Label("Travel Mode", systemImage: "car.fill")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            if travel.stage == .playing {
                TravelVoiceBadge(speech: travel.speech)
            }
            Button("End") { vm.endTravel() }
                .font(.subheadline.bold())
                .foregroundColor(.red.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red.opacity(0.5), lineWidth: 1.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }
}

/// Which voice this session settled on. It never flips back and forth.
private struct TravelVoiceBadge: View {
    @ObservedObject var speech: TravelSpeech

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: speech.usingCloudVoice ? "sparkles" : "speaker.wave.2.fill")
            Text(speech.usingCloudVoice ? "AI voice" : "Phone voice")
        }
        .font(.caption2.bold())
        .foregroundColor(speech.usingCloudVoice ? TravelDesign.primary : .white.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

struct TravelSafetyFooter: View {
    var body: some View {
        Text(TravelCopy.safetyLine)
            .font(.callout.bold())
            .foregroundColor(TravelDesign.warning.opacity(0.95))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(TravelDesign.warning.opacity(0.08))
    }
}

// MARK: - Pick

struct TravelPickView: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "mic.and.signal.meter.fill")
                        .font(.system(size: 44))
                        .foregroundColor(TravelDesign.primary)
                    Text("Road Trip Quizmaster")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("I ask out loud, everyone shouts the answer.\nNo setup, no tapping.")
                        .font(.body)
                        .foregroundColor(TravelDesign.text2)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)
                .padding(.bottom, 8)

                ForEach(TravelPlayStyle.allCases) { style in
                    Button { travel.start(style) } label: {
                        TravelStyleCard(style: style)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}

private struct TravelStyleCard: View {
    let style: TravelPlayStyle

    private var tint: Color {
        switch style {
        case .riddles: return TravelDesign.riddle
        case .quiz:    return TravelDesign.info
        case .brain:   return TravelDesign.warning
        case .mix:     return TravelDesign.primary
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: style.sfSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 4) {
                Text(style.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(style.blurb)
                    .font(.subheadline)
                    .foregroundColor(TravelDesign.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.title3)
                .foregroundColor(tint)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: TravelDesign.cardRadius)
                .fill(TravelDesign.surface)
                .overlay(RoundedRectangle(cornerRadius: TravelDesign.cardRadius)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
        )
    }
}

// MARK: - Starting

struct TravelStartingView: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ProgressView()
                .scaleEffect(2)
                .tint(TravelDesign.info)
            Text("Waking up your quizmaster...")
                .font(.title3.bold())
                .foregroundColor(.white)
            Spacer()
        }
    }
}

// MARK: - Play

struct TravelPlayView: View {
    @ObservedObject var travel: TravelModeViewModel

    var body: some View {
        VStack(spacing: 16) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 14)

            ScrollView {
                card
                    .padding(.horizontal, 20)
            }

            TravelStatusLine(travel: travel)

            controls
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
    }

    private func chipText(_ kind: TravelItem.Kind) -> String {
        switch kind {
        case .riddle: return "RIDDLE"
        case .quiz:   return "QUIZ"
        case .brain:  return "BRAIN \u{00B7} LEVEL \(travel.brainLevel)"
        }
    }

    private func chipColor(_ kind: TravelItem.Kind) -> Color {
        switch kind {
        case .riddle: return TravelDesign.riddle
        case .quiz:   return TravelDesign.info
        case .brain:  return TravelDesign.warning
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if let item = travel.item {
                Text(chipText(item.kind))
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(chipColor(item.kind)))
            }
            Spacer()
            if travel.micReady && travel.asked > 0 {
                Text("\(travel.correct) of \(travel.asked) right")
                    .font(.headline)
                    .foregroundColor(TravelDesign.text2)
            } else if travel.asked > 0 {
                Text("Question \(travel.asked)")
                    .font(.headline)
                    .foregroundColor(TravelDesign.text2)
            }
        }
    }

    // MARK: Card

    @ViewBuilder
    private var card: some View {
        VStack(spacing: 18) {
            if let item = travel.item {
                Text(item.prompt)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let options = item.options, travel.gotIt == nil {
                    Text(options.joined(separator: "  /  "))
                        .font(.headline)
                        .foregroundColor(TravelDesign.text2)
                        .multilineTextAlignment(.center)
                }

                if travel.hintShown && travel.gotIt == nil {
                    Label(item.hint, systemImage: "lightbulb.fill")
                        .font(.title3.bold())
                        .foregroundColor(TravelDesign.warning)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(TravelDesign.warning.opacity(0.1)))
                }

                if let gotIt = travel.gotIt {
                    answerBox(item: item, gotIt: gotIt)
                }
            } else {
                Text("Get ready...")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: TravelDesign.cardRadius)
            .fill(TravelDesign.surface))
        .animation(.easeInOut(duration: 0.25), value: travel.gotIt)
        .animation(.easeInOut(duration: 0.25), value: travel.hintShown)
    }

    private func answerBox(item: TravelItem, gotIt: Bool) -> some View {
        let tint = gotIt ? TravelDesign.primary : TravelDesign.info
        return VStack(spacing: 8) {
            Text(gotIt ? "YOU GOT IT!" : "THE ANSWER")
                .font(.caption.bold())
                .tracking(2)
                .foregroundColor(tint)
            Text(String(item.answer.prefix(1)).uppercased() + String(item.answer.dropFirst()))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let fact = item.fact {
                Text(fact)
                    .font(.body)
                    .foregroundColor(TravelDesign.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.12)))
    }

    // MARK: Controls (all optional)

    private var controls: some View {
        let open = travel.gotIt == nil && travel.item != nil
        let paused = travel.phase == .paused
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                TravelControl(title: "Hint", systemImage: "lightbulb.fill",
                              tint: TravelDesign.warning,
                              enabled: open && !paused && !travel.hintShown) { travel.hint() }
                TravelControl(title: "Answer", systemImage: "eye.fill",
                              tint: TravelDesign.info,
                              enabled: open && !paused) { travel.revealNow() }
                TravelControl(title: "Next", systemImage: "forward.fill",
                              tint: TravelDesign.riddle,
                              enabled: !paused) { travel.skip() }
            }
            HStack(spacing: 12) {
                if paused {
                    TravelControl(title: "Change game", systemImage: "square.grid.2x2.fill",
                                  tint: TravelDesign.text2, enabled: true) { travel.changeGame() }
                } else {
                    TravelControl(title: "We got it!", systemImage: "checkmark.circle.fill",
                                  tint: TravelDesign.primary, enabled: open) { travel.markGotIt() }
                }
                TravelControl(title: paused ? "Resume" : "Pause",
                              systemImage: paused ? "play.fill" : "pause.fill",
                              tint: .white, enabled: true) { travel.togglePause() }
            }
        }
    }
}

private struct TravelControl: View {
    let title: String
    let systemImage: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.subheadline.bold())
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 16).fill(TravelDesign.surface2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

// MARK: - Status line

/// What the quizmaster is doing right now, with the live "Heard: ..."
/// caption so the car can see the mic is working.
struct TravelStatusLine: View {
    @ObservedObject var travel: TravelModeViewModel
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(color)
                    .scaleEffect(travel.phase == .listening && pulse ? 1.18 : 1)
                    .animation(travel.phase == .listening
                               ? Animation.easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                               : Animation.default, value: pulse)
                Text(text)
                    .font(.headline)
                    .foregroundColor(color)
            }
            if !travel.heard.isEmpty,
               travel.phase == .listening || travel.phase == .reacting {
                Text("Heard: \(travel.heard)")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 28)
            }
        }
        .frame(minHeight: 56)
        .onAppear { pulse = true }
    }

    private var icon: String {
        switch travel.phase {
        case .asking:    return "speaker.wave.2.fill"
        case .listening: return "mic.fill"
        case .thinking:  return "hourglass"
        case .reacting:  return "bubble.left.fill"
        case .revealed:  return "sparkles"
        case .paused:    return "pause.circle.fill"
        }
    }

    private var color: Color {
        switch travel.phase {
        case .listening: return TravelDesign.primary
        case .asking:    return TravelDesign.info
        case .thinking:  return TravelDesign.warning
        default:         return TravelDesign.text2
        }
    }

    private var text: String {
        switch travel.phase {
        case .asking:    return "Listen up..."
        case .listening: return "Listening -- shout your answer!"
        case .thinking:  return "Thinking time: \(travel.countdown)"
        case .reacting:  return "Quizmaster's talking..."
        case .revealed:  return "Next one coming up..."
        case .paused:    return "Paused"
        }
    }
}
