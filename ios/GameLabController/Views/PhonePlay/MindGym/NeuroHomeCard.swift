import SwiftUI

// MARK: - The Mind Gym card on the home screen
//
// One card, above the party games: today's workout, about five minutes, a
// streak ring, and Start, Resume or Done depending on what the cache says
// (NeuroHomeState). Nothing here waits on the network.

struct NeuroHomeCard: View {
    let state: NeuroHomeState
    let appeared: Bool
    let onPlay: () -> Void
    let onProgress: () -> Void
    /// Opens the Daily Brain "Quick 5": five fast puzzles, the same for
    /// everyone that day. `quickDone` is true once today's are finished.
    var quickDone: Bool = false
    var onQuick: (() -> Void)? = nil

    private static let colors: [Color] = [PhonePlayDesign.indigo,
                                          PhonePlayDesign.blue,
                                          PhonePlayDesign.cyan]

    private var isDone: Bool {
        if case .done = state.mode { return true }
        return false
    }

    private var actionTitle: String {
        switch state.mode {
        case .start:                return "Start"
        case .resume(let step):     return "Resume at step \(step)"
        case .done(let pulse):      return "Pulse \(pulse)"
        }
    }

    private var actionSymbol: String {
        switch state.mode {
        case .start:  return "play.fill"
        case .resume: return "arrow.uturn.backward"
        case .done:   return "checkmark.circle.fill"
        }
    }

    private var subtitle: String {
        switch state.mode {
        case .start:
            return "Ten steps across logic, numbers, memory, patterns and calm. About \(NeuroHomeState.minutes) minutes."
        case .resume(let step):
            return "You are part way through: step \(step) of \(NeuroScoring.stepCount) is waiting."
        case .done:
            return "Done for today. Come back tomorrow to keep the streak."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            VStack(alignment: .leading, spacing: 4) {
                Text("Today's workout")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionRow
            if let onQuick {
                quickRow(onQuick)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius + 4, style: .continuous)
                .fill(PhonePlayDesign.gradient(NeuroHomeCard.colors))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius + 4, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: PhonePlayDesign.indigo.opacity(0.35), radius: 16, y: 9)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(PhonePlayDesign.pop, value: appeared)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 58, height: 58)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .phonePlayIdle(dy: 3, degrees: 3, duration: 1.6)
            VStack(alignment: .leading, spacing: 2) {
                Text("NEUROPULSE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.8))
                Text(isDone ? "Done today" : "\(NeuroScoring.stepCount) steps")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            Spacer(minLength: 4)
            NeuroStreakRing(streak: state.streak)
        }
    }

    private func quickRow(_ action: @escaping () -> Void) -> some View {
        Button {
            PhonePlayHaptics.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: quickDone ? "checkmark.circle.fill" : "bolt.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(quickDone ? "Quick 5 done today" : "Quick 5: five fast puzzles, same for everyone")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(PhonePlayPressStyle())
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                PhonePlayHaptics.thump()
                onPlay()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: actionSymbol)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(PhonePlayDesign.indigo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PhonePlayPressStyle())
            .accessibilityLabel(isDone ? "Today's workout is done" : actionTitle)

            Button {
                PhonePlayHaptics.tap()
                onProgress()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Progress")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(PhonePlayPressStyle())
            .accessibilityLabel("Mind Score")
        }
    }
}

// MARK: - Streak ring

/// A week's worth of days around the streak count: full circle at seven.
private struct NeuroStreakRing: View {
    let streak: Int

    private var fraction: Double {
        guard streak > 0 else { return 0 }
        let within = streak % 7
        return within == 0 ? 1 : Double(within) / 7.0
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
            VStack(spacing: -2) {
                Text("\(streak)")
                    .font(.system(size: 20, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text(streak == 1 ? "day" : "days")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .frame(width: 62, height: 62)
        .animation(PhonePlayDesign.smooth, value: streak)
        .accessibilityLabel("\(streak) day streak")
    }
}
