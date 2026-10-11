import SwiftUI

/// A staged big-screen reveal for party games.
///
/// The engine broadcasts the whole reveal payload at once, but the fun of a
/// reveal is the drumroll: each player's answer or vote appears one by one,
/// then the winner gets a spotlight. Any game whose reveal is "a list of
/// entries plus a winner" feeds this view from its own board state — the
/// boards in `TVPartyGameBoards.swift` switch to it when their phase flips to
/// `reveal`.
///
/// Pacing adapts to the room: twenty rows still finish well inside the
/// reveal window, so the spotlight always gets its moment.

// MARK: - Model

/// One staged row: a player's answer or vote.
struct TVRevealRow: Identifiable, Equatable {
    let id: String
    let name: String            // player name, cluster text, lie owner...
    let detail: String          // the answer, the vote count, the emoji...
    var sublabel: String? = nil // points, member names, the revealed title...
    var isWinner = false
}

/// The final spotlight card, shown after every row has appeared.
struct TVRevealSpotlight: Equatable {
    let title: String           // small caps, e.g. "MOST VOTED"
    let name: String            // the winner's name, large
    var detail: String? = nil   // e.g. "7 votes"
}

// MARK: - View

struct TVRevealBoardView: View {
    /// Unique per reveal (round + prompt); a change restarts the animation.
    let roundKey: String
    /// Small-caps label above the headline, e.g. "the room has spoken".
    let header: String
    /// The prompt, letter, or lot being revealed.
    let headline: String
    let rows: [TVRevealRow]
    /// Nil for games with no single winner (e.g. Emoji Charades titles).
    let spotlight: TVRevealSpotlight?
    let emptyMessage: String

    @State private var revealedCount = 0
    @State private var spotlightShown = false
    @State private var elapsed = 0.0

    private let tick = 0.12
    /// Fixed-rate ticker; the stagger interval is derived from the row count
    /// so a full room of rows still finishes inside the reveal phase.
    private let ticker = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    /// Seconds between rows, clamped so even a 20-player reveal lands in ~6s.
    private var stagger: Double {
        guard !rows.isEmpty else { return 0.5 }
        return min(0.5, max(tick, 6.0 / Double(rows.count)))
    }

    var body: some View {
        VStack(spacing: 44) {
            VStack(spacing: 10) {
                Text(header.uppercased())
                    .font(.system(.caption, design: .rounded, weight: .bold)).tracking(4)
                    .foregroundColor(TVTheme.cyan.opacity(0.8))
                Text(headline)
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 120)
            }

            if rows.isEmpty && spotlight == nil {
                Text(emptyMessage)
                    .font(.system(.title2, design: .rounded)).foregroundColor(.white.opacity(0.5))
            } else {
                VStack(spacing: 14) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index < revealedCount {
                            revealRow(row)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, 160)
            }

            if spotlightShown, let spotlight {
                spotlightCard(spotlight)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onAppear(perform: reset)
        .onChange(of: roundKey) { _ in reset() }
        .onReceive(ticker) { _ in advance() }
    }

    private func reset() {
        revealedCount = 0
        spotlightShown = false
        elapsed = 0
    }

    private func advance() {
        if revealedCount < rows.count {
            elapsed += tick
            if elapsed >= stagger {
                elapsed = 0
                withAnimation(.easeOut(duration: 0.3)) { revealedCount += 1 }
            }
        } else if !spotlightShown, spotlight != nil {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                spotlightShown = true
            }
        }
    }

    private func revealRow(_ row: TVRevealRow) -> some View {
        HStack(spacing: 20) {
            if row.isWinner {
                Image(systemName: "crown.fill")
                    .font(.system(.title2, design: .rounded)).foregroundColor(TVTheme.yellow)
                    .frame(width: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(row.isWinner ? TVTheme.yellow : .white)
                    .lineLimit(1)
                if let sublabel = row.sublabel {
                    Text(sublabel)
                        .font(.system(.body, design: .rounded)).foregroundColor(.white.opacity(0.55))
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(row.detail)
                .font(.system(.title2, design: .rounded))
                .foregroundColor(row.isWinner ? TVTheme.yellow : .white.opacity(0.9))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.horizontal, 30).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(row.isWinner ? TVTheme.yellow.opacity(0.15)
                                   : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(row.isWinner ? TVTheme.yellow.opacity(0.7) : .clear,
                        lineWidth: 2)
        )
    }

    private func spotlightCard(_ spotlight: TVRevealSpotlight) -> some View {
        VStack(spacing: 12) {
            Text(spotlight.title)
                .font(.system(.caption, design: .rounded, weight: .bold)).tracking(4)
                .foregroundColor(TVTheme.yellow.opacity(0.85))
            HStack(spacing: 18) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 54, weight: .regular, design: .rounded)).foregroundColor(TVTheme.yellow)
                Text(spotlight.name)
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(TVTheme.yellow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let detail = spotlight.detail {
                Text(detail)
                    .font(.system(.title2, design: .rounded, weight: .bold)).foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 60).padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: ShellTheme.cardRadius).fill(TVTheme.yellow.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: ShellTheme.cardRadius).stroke(TVTheme.yellow, lineWidth: 3))
        .shadow(color: TVTheme.yellow.opacity(0.5), radius: 40)
    }
}
