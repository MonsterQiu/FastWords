import Foundation

/// Pure helpers for the daily review heatmap (GitHub-contribution style).
/// No I/O — the daily counts are supplied by the caller and persisted elsewhere.
public enum ReviewStats {
    /// Canonical day key `yyyy-MM-dd` in the current calendar/timezone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// One cell of the heatmap.
    public struct Day: Equatable, Sendable {
        public let date: Date
        public let key: String
        public let count: Int
    }

    /// Build the last `weeks` weeks of days, ending on `reference`'s week,
    /// laid out column-by-column (each column a Sun→Sat week). Returns the days
    /// in chronological order; the caller arranges them into a 7-row grid.
    public static func days(
        upTo reference: Date,
        weeks: Int,
        counts: [String: Int],
        calendar: Calendar = .current
    ) -> [Day] {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday-first columns, like GitHub.

        // Start at the Sunday of the earliest week in range.
        let startOfToday = cal.startOfDay(for: reference)
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: startOfToday)?.start,
              let firstColumn = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart)
        else { return [] }

        var result: [Day] = []
        let totalDays = weeks * 7
        for offset in 0..<totalDays {
            guard let date = cal.date(byAdding: .day, value: offset, to: firstColumn) else { continue }
            if date > startOfToday { break } // don't show future days
            let key = dayKey(for: date, calendar: cal)
            result.append(Day(date: date, key: key, count: counts[key] ?? 0))
        }
        return result
    }

    /// Intensity level 0...4 for a count, used to pick a color shade.
    public static func intensity(for count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1...3: return 1
        case 4...9: return 2
        case 10...19: return 3
        default: return 4
        }
    }

    /// Current consecutive-day streak ending today (or yesterday, so a fresh day
    /// before any review doesn't break the streak). Days with count > 0 count.
    public static func currentStreak(counts: [String: Int], asOf reference: Date, calendar: Calendar = .current) -> Int {
        let cal = calendar
        var day = cal.startOfDay(for: reference)
        // If today has no reviews yet, start counting from yesterday.
        if (counts[dayKey(for: day, calendar: cal)] ?? 0) == 0 {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while (counts[dayKey(for: day, calendar: cal)] ?? 0) > 0 {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Total reviews across all recorded days.
    public static func total(counts: [String: Int]) -> Int {
        counts.values.reduce(0, +)
    }
}
