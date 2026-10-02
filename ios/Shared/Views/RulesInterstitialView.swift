import SwiftUI

/// How-to-play interstitial shown once, right after Start Game is pressed.
///
/// The TV presents the `.tv` layout (full screen, large type); the phone
/// controller presents the same data as a compact `.card`. Both read the
/// same `GameRules` decoded from the server's `game_started` payload -- the
/// backend is the single source of truth and neither app keeps its own
/// copy of the text.
///
/// Tapping the primary button dismisses the interstitial locally on that
/// device only. The room is already PLAYING server-side at this point, so
/// the gate only changes what each client shows, never the room state.
struct RulesInterstitialView: View {
    enum Layout {
        case tv
        case card
    }

    let rules: GameRules
    let layout: Layout
    let primaryTitle: String
    let onPrimary: () -> Void

    @FocusState private var startFocused: Bool

    var body: some View {
        switch layout {
        case .tv:
            tvBody
        case .card:
            cardBody
        }
    }

    // MARK: - TV layout

    private var tvBody: some View {
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("HOW TO PLAY")
                        .font(.title3).bold()
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(4)

                    Text(rules.title)
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(.white)

                    Text(rules.objective)
                        .font(.title2)
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(rules.rules.enumerated()), id: \.offset) { index, rule in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.title2).bold()
                                    .foregroundColor(.cyan)
                                    .frame(width: 44)
                                Text(rule)
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.92))
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.white.opacity(0.6))
                        Text(rules.controls)
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .font(.title.bold())
                            .frame(maxWidth: 420)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(startFocused ? Color.white : Color.cyan)
                            )
                            .foregroundColor(.black)
                            .scaleEffect(startFocused ? 1.06 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .focused($startFocused)
                    .padding(.top, 8)
                }
                .padding(72)
                .frame(maxWidth: 1200, alignment: .leading)
            }
        }
        .onAppear { startFocused = true }
    }

    // MARK: - Phone card layout

    private var cardBody: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("HOW TO PLAY")
                    .font(.caption).bold()
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(2)

                Text(rules.title)
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text(rules.objective)
                    .font(.subheadline)
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rules.rules.enumerated()), id: \.offset) { index, rule in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1).")
                                .font(.subheadline).bold()
                                .foregroundColor(.cyan)
                            Text(rule)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.92))
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(.white.opacity(0.6))
                    Text(rules.controls)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.75))
                }

                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.cyan))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: "14141f")))
            .padding(.horizontal, 24)
        }
    }
}
