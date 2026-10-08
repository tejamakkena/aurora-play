import SwiftUI

// MARK: - Mind Score
//
// The long view: one bar per discipline (rating, level 1-10 and best), a
// 30-day sparkline of the pulse score drawn in a Canvas, and today's
// friends leaderboard. The cached profile is shown at once and the fetch
// quietly replaces it.

struct NeuroMindScoreView: View {
    @ObservedObject var game: NeuroPulseViewModel

    private var profile: NeuroProfile { game.profile }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                topLine
                disciplineCard
                NeuroArcadeShelf(onOpen: { game.arcadeRequest = $0 })
                sparklineCard
                leaderboardCard
                if profile.isEmpty {
                    Text("Finish today's workout to start your Mind Score.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(PhonePlayDesign.text3)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onAppear {
            game.loadProgress()
        }
    }

    // MARK: Streak and calm minutes

    private var topLine: some View {
        HStack(spacing: 10) {
            NeuroStreakBadge(streak: max(game.streak, profile.streak))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "wind")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.cyan)
                Text("\(profile.zenMinutes) min calm")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(PhonePlayDesign.cyan.opacity(0.12)))
        }
    }

    // MARK: One bar per discipline

    private var disciplineCard: some View {
        VStack(spacing: 14) {
            HStack {
                PhonePlaySectionLabel(text: "Your five minds")
                if game.loadingProgress {
                    ProgressView()
                        .tint(PhonePlayDesign.cyan)
                        .controlSize(.small)
                }
            }
            ForEach(NeuroDiscipline.all, id: \.self) { key in
                NeuroDisciplineRow(name: profile.displayName(key),
                                   symbol: NeuroDiscipline.symbol(key),
                                   tint: NeuroStyle.tint(key),
                                   rating: profile.rating(key),
                                   best: profile.bestRating(key),
                                   level: profile.level(key))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    // MARK: 30 days of pulse scores

    private var sparklineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PhonePlaySectionLabel(text: "Last 30 days")
                Spacer(minLength: 0)
                if let last = profile.history.last {
                    Text("\(last.pulse)")
                        .font(.system(size: 17, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundColor(PhonePlayDesign.cyan)
                }
            }
            NeuroSparkline(values: profile.history.map { $0.pulse })
                .frame(height: 96)
            if profile.history.count < 2 {
                Text("Two days in a row and this fills in.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
            } else {
                HStack {
                    Text(profile.history.first?.date ?? "")
                    Spacer()
                    Text(profile.history.last?.date ?? "")
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    // MARK: Today's friends

    private var leaderboardCard: some View {
        VStack(spacing: 12) {
            PhonePlaySectionLabel(text: friendRows.isEmpty ? "Today" : "Friends today")
            if friendRows.isEmpty {
                Text("No one you know has played today yet.")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(PhonePlayDesign.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(shownRows) { row in
                NeuroLeaderRowView(row: row)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PhonePlayDesign.cardRadius, style: .continuous)
                .fill(PhonePlayDesign.surface)
        )
    }

    private var friendRows: [NeuroLeaderRow] { game.friends }

    private var shownRows: [NeuroLeaderRow] {
        friendRows.isEmpty ? Array(game.everyone.prefix(5)) : friendRows
    }
}

// MARK: - One discipline

private struct NeuroDisciplineRow: View {
    let name: String
    let symbol: String
    let tint: Color
    let rating: Int
    let best: Int
    let level: Int

    /// Where this rating sits in the range a rating may wander in.
    private var fraction: Double {
        let span = Double(NeuroScoring.maxRating - NeuroScoring.minRating)
        guard span > 0 else { return 0 }
        let value = Double(rating - NeuroScoring.minRating) / span
        return min(1, max(0.02, value))
    }

    private var bestFraction: Double {
        let span = Double(NeuroScoring.maxRating - NeuroScoring.minRating)
        guard span > 0 else { return 0 }
        let value = Double(best - NeuroScoring.minRating) / span
        return min(1, max(0.02, value))
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                Text(name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(rating)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.white)
                Text("Level \(level)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tint))
            }
            GeometryReader { geometry in
                let width: CGFloat = max(1, geometry.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(PhonePlayDesign.gradient([tint, tint.opacity(0.55)]))
                        .frame(width: width * CGFloat(fraction))
                    Capsule()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 2)
                        .offset(x: min(width - 2, width * CGFloat(bestFraction)))
                }
            }
            .frame(height: 10)
            Text("Best \(best)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(PhonePlayDesign.text3)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - The sparkline

/// The pulse score over the days there are, drawn in a Canvas: a filled
/// area under a line, with the latest day marked.
private struct NeuroSparkline: View {
    let values: [Int]

    var body: some View {
        Canvas { context, size in
            guard size.width > 2, size.height > 2 else { return }
            let points = NeuroSparkline.points(values: values, size: size)
            guard points.count >= 2 else {
                if let only = points.first {
                    let dot = Path(ellipseIn: CGRect(x: only.x - 4, y: only.y - 4,
                                                     width: 8, height: 8))
                    context.fill(dot, with: .color(PhonePlayDesign.cyan))
                }
                return
            }

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() { line.addLine(to: point) }

            var area = line
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
            area.addLine(to: CGPoint(x: points[0].x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [PhonePlayDesign.cyan.opacity(0.35), Color.clear]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)))

            context.stroke(line, with: .color(PhonePlayDesign.cyan),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                let dot = Path(ellipseIn: CGRect(x: last.x - 4.5, y: last.y - 4.5,
                                                 width: 9, height: 9))
                context.fill(dot, with: .color(.white))
                let inner = Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5,
                                                   width: 5, height: 5))
                context.fill(inner, with: .color(PhonePlayDesign.cyan))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }

    /// Scales the values into the box, leaving a little room top and bottom.
    static func points(values: [Int], size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let top: CGFloat = 8
        let bottom: CGFloat = 8
        let usable: CGFloat = max(1, size.height - top - bottom)
        let highest: Int = values.max() ?? 1
        let lowest: Int = values.min() ?? 0
        let span: CGFloat = CGFloat(max(1, highest - lowest))
        if values.count == 1 {
            return [CGPoint(x: size.width / 2, y: top + usable / 2)]
        }
        let gap: CGFloat = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { pair in
            let fraction: CGFloat = CGFloat(pair.element - lowest) / span
            return CGPoint(x: CGFloat(pair.offset) * gap,
                           y: top + usable * (1 - fraction))
        }
    }
}

// MARK: - One leaderboard row

private struct NeuroLeaderRowView: View {
    let row: NeuroLeaderRow

    var body: some View {
        HStack(spacing: 12) {
            Text("\(max(1, row.rank))")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundColor(row.rank == 1 ? .black : .white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(row.rank == 1 ? PhonePlayDesign.yellow
                                                        : PhonePlayDesign.surface2))
            Text(row.isMe ? "\(row.name) (you)" : row.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(row.isMe ? PhonePlayDesign.cyan : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if row.streak > 1 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text("\(row.streak)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundColor(PhonePlayDesign.orange)
            }
            Text("\(row.pulse)")
                .font(.system(size: 16, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundColor(PhonePlayDesign.cyan)
        }
    }
}
