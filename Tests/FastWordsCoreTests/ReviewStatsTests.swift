@testable import FastWordsCore
import XCTest

final class ReviewStatsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testDayKeyFormat() {
        XCTAssertEqual(ReviewStats.dayKey(for: date(2026, 6, 5), calendar: cal), "2026-06-05")
    }

    func testIntensityBuckets() {
        XCTAssertEqual(ReviewStats.intensity(for: 0), 0)
        XCTAssertEqual(ReviewStats.intensity(for: 2), 1)
        XCTAssertEqual(ReviewStats.intensity(for: 5), 2)
        XCTAssertEqual(ReviewStats.intensity(for: 15), 3)
        XCTAssertEqual(ReviewStats.intensity(for: 100), 4)
    }

    func testTotal() {
        XCTAssertEqual(ReviewStats.total(counts: ["a": 3, "b": 4]), 7)
    }

    func testCurrentStreakCountsConsecutiveDays() {
        let today = date(2026, 6, 5)
        let counts = [
            "2026-06-05": 2,
            "2026-06-04": 1,
            "2026-06-03": 5,
            // gap on 06-02
            "2026-06-01": 9
        ]
        XCTAssertEqual(ReviewStats.currentStreak(counts: counts, asOf: today, calendar: cal), 3)
    }

    func testStreakNotBrokenByEmptyToday() {
        let today = date(2026, 6, 5) // no reviews yet today
        let counts = ["2026-06-04": 1, "2026-06-03": 1]
        XCTAssertEqual(ReviewStats.currentStreak(counts: counts, asOf: today, calendar: cal), 2)
    }

    func testDaysBuildsGridAndAppliesCounts() {
        let today = date(2026, 6, 5)
        let counts = ["2026-06-05": 7]
        let days = ReviewStats.days(upTo: today, weeks: 4, counts: counts, calendar: cal)
        XCTAssertFalse(days.isEmpty)
        XCTAssertEqual(days.last?.key, "2026-06-05")
        XCTAssertEqual(days.last?.count, 7)
        // No future days beyond today.
        XCTAssertNil(days.first { $0.date > cal.startOfDay(for: today) })
    }
}
