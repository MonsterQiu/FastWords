import FastWordsCore
import SwiftUI

/// Stats page: a GitHub-style daily-review heatmap (blue) plus summary numbers,
/// with month labels on the top axis, weekday labels on the left, and a live
/// hover readout.
struct StatsView: View {
    @ObservedObject var store: WordStore
    @State private var hovered: ReviewStats.Day?

    private let weeks = 22 // fits the settings detail width
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let rowLabelWidth: CGFloat = 30

    var body: some View {
        let counts = store.reviewLog
        let now = Date()
        let days = ReviewStats.days(upTo: now, weeks: weeks, counts: counts)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryRow(counts: counts, now: now)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("学习热力图").font(.headline)
                        Spacer()
                        // Live hover readout (replaces the slow system tooltip).
                        if let h = hovered {
                            Text("\(h.key) · 学习 \(h.count) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    heatmap(days: days)
                    legend
                }
            }
            .padding(2)
        }
    }

    // MARK: - Summary numbers

    private func summaryRow(counts: [String: Int], now: Date) -> some View {
        let today = counts[ReviewStats.dayKey(for: now)] ?? 0
        let total = ReviewStats.total(counts: counts)
        let streak = ReviewStats.currentStreak(counts: counts, asOf: now)
        let mastered = store.totalMasteredCount

        return HStack(spacing: 12) {
            statCard("今日学习", "\(today)", "flame")
            statCard("连续天数", "\(streak)", "calendar")
            statCard("累计学习", "\(total)", "checkmark.circle")
            statCard("已掌握", "\(mastered)", "star")
        }
    }

    private func statCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.blue)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Heatmap

    /// Lay the chronological days into a 7-row (weekday) × N-column (week) grid,
    /// with month labels across the top and weekday labels down the left.
    private func heatmap(days: [ReviewStats.Day]) -> some View {
        let leading = days.first.map { Calendar.current.component(.weekday, from: $0.date) - 1 } ?? 0
        let padded: [ReviewStats.Day?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        let columns = stride(from: 0, to: padded.count, by: 7).map { start -> [ReviewStats.Day?] in
            Array(padded[start..<min(start + 7, padded.count)])
        }

        return VStack(alignment: .leading, spacing: gap) {
            monthLabels(columns: columns)
            HStack(alignment: .top, spacing: gap) {
                weekdayLabels
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                cellView(row < week.count ? week[row] : nil)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Month name above the first column whose month differs from the previous.
    private func monthLabels(columns: [[ReviewStats.Day?]]) -> some View {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        fmt.locale = Locale(identifier: "en_US")

        var lastMonth = -1
        var labels: [Int: String] = [:]
        for (i, week) in columns.enumerated() {
            guard let firstDay = week.compactMap({ $0 }).first else { continue }
            let m = Calendar.current.component(.month, from: firstDay.date)
            if m != lastMonth {
                labels[i] = fmt.string(from: firstDay.date)
                lastMonth = m
            }
        }

        return HStack(spacing: gap) {
            Color.clear.frame(width: rowLabelWidth, height: 11)
            ForEach(0..<columns.count, id: \.self) { i in
                Text(labels[i] ?? "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: cell, alignment: .leading)
                    .fixedSize()
                    .frame(width: cell, alignment: .leading)
            }
        }
    }

    /// Mon / Wed / Fri on rows 1, 3, 5 (like GitHub).
    private var weekdayLabels: some View {
        let names = ["", "Mon", "", "Wed", "", "Fri", ""]
        return VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(names[row])
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: rowLabelWidth, height: cell, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ day: ReviewStats.Day?) -> some View {
        if let day {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color(for: day.count))
                .frame(width: cell, height: cell)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.blue, lineWidth: hovered?.key == day.key ? 1.5 : 0)
                )
                .onHover { inside in
                    if inside {
                        hovered = day
                    } else if hovered?.key == day.key {
                        hovered = nil
                    }
                }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(shade(level))
                    .frame(width: cell, height: cell)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Colors (blue scale)

    private func color(for count: Int) -> Color {
        shade(ReviewStats.intensity(for: count))
    }

    private func shade(_ level: Int) -> Color {
        switch level {
        case 0: return Color.primary.opacity(0.06)
        case 1: return Color.blue.opacity(0.18)
        case 2: return Color.blue.opacity(0.42)
        case 3: return Color.blue.opacity(0.70)
        default: return Color.blue
        }
    }
}
