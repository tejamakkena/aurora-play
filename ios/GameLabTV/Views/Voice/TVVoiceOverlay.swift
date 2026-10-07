import SwiftUI

/// The room-facing voice status: who holds the mic, what the loop is
/// doing, live captions, and the last verdict. Boards overlay this in a
/// corner -- it never covers the question.
struct TVVoiceOverlay: View {
    @ObservedObject var host: TVVoiceHost

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Mic holder
            HStack(spacing: 8) {
                Image(systemName: host.micPlayerID == nil
                      ? "mic.slash.fill" : "mic.fill")
                    .foregroundColor(host.micPlayerID == nil ? TVTheme.text3 : TVTheme.green)
                Text(host.micPlayerName.map { "\($0)'s phone" }
                     ?? "No mic -- claim it on your phone")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.55)))

            // Loop state
            if host.voiceState != "idle" {
                Text(stateLabel)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }

            // Live caption
            if !host.liveTranscript.isEmpty && host.voiceState == "listen" {
                Text("“\(host.liveTranscript)”")
                    .font(.system(.title3, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.55)))
                    .frame(maxWidth: 560, alignment: .trailing)
            }

            // Verdict
            if let verdict = host.lastVerdict {
                Text(verdict)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(host.lastVerdictCorrect == true
                                     ? TVTheme.green : .white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
        }
        .padding(32)
    }

    private var stateLabel: String {
        switch host.voiceState {
        case "ask":     return "Asking..."
        case "listen":  return "Listening..."
        case "lock":    return "Locked in"
        case "grade":   return "Checking..."
        default:        return host.voiceState
        }
    }

    private var stateColor: Color {
        switch host.voiceState {
        case "listen": return TVTheme.green
        case "ask":    return TVTheme.cyan
        default:      return .white.opacity(0.8)
        }
    }
}
