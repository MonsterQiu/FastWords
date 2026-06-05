@testable import FastWordsCore
import XCTest

final class SRSTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 86_400).rounded())
    }

    func testFirstGoodReviewSchedulesOneDayLater() {
        let updated = SRS.apply(.good, to: SRSState(), now: now)
        XCTAssertEqual(updated.repetitions, 1)
        XCTAssertEqual(updated.intervalDays, 1)
        XCTAssertEqual(daysBetween(now, updated.dueDate), 1)
        XCTAssertEqual(updated.lastReviewedAt, now)
    }

    func testSecondGoodReviewSchedulesSixDaysLater() {
        let first = SRS.apply(.good, to: SRSState(), now: now)
        let second = SRS.apply(.good, to: first, now: now)
        XCTAssertEqual(second.repetitions, 2)
        XCTAssertEqual(second.intervalDays, 6)
    }

    func testIntervalGrowsByEaseFactorAfterSecondReview() {
        var state = SRSState()
        for _ in 0..<3 {
            state = SRS.apply(.good, to: state, now: now)
        }
        // After 3 good reviews: 1 -> 6 -> 6 * ease(>=2.5) ~= 15.
        XCTAssertEqual(state.repetitions, 3)
        XCTAssertGreaterThanOrEqual(state.intervalDays, 15)
    }

    func testAgainResetsStreakAndMakesDueImmediately() {
        var state = SRSState()
        state = SRS.apply(.good, to: state, now: now)
        state = SRS.apply(.good, to: state, now: now)

        let lapsed = SRS.apply(.again, to: state, now: now)
        XCTAssertEqual(lapsed.repetitions, 0)
        XCTAssertEqual(lapsed.intervalDays, 0)
        XCTAssertTrue(lapsed.isDue(asOf: now))
    }

    func testEaseFactorNeverDropsBelowMinimum() {
        var state = SRSState()
        for _ in 0..<10 {
            state = SRS.apply(.again, to: state, now: now)
        }
        XCTAssertGreaterThanOrEqual(state.easeFactor, SRSState.minimumEaseFactor)
    }

    func testHardAdvancesSlowerThanGood() {
        let base = SRS.apply(.good, to: SRSState(), now: now)
        let hardSecond = SRS.apply(.hard, to: base, now: now)
        let goodSecond = SRS.apply(.good, to: base, now: now)
        XCTAssertLessThan(hardSecond.intervalDays, goodSecond.intervalDays)
    }

    func testNewStateIsDueImmediately() {
        XCTAssertTrue(SRSState().isDue(asOf: now))
    }

    func testNewWordIsNotMastered() {
        XCTAssertEqual(SRS.masteryStatus(for: SRSState()), .learning)
    }

    func testBecomesMasteredAfterEnoughGoodReviews() {
        var state = SRSState()
        for _ in 0..<4 {
            state = SRS.apply(.good, to: state, now: now)
        }
        // After 4 good reviews: repetitions=4, interval well past 21 days.
        XCTAssertGreaterThanOrEqual(state.repetitions, SRS.masteryRepetitions)
        XCTAssertGreaterThanOrEqual(state.intervalDays, SRS.masteryIntervalDays)
        XCTAssertEqual(SRS.masteryStatus(for: state), .mastered)
    }

    func testLapseDropsBackToLearning() {
        var state = SRSState()
        for _ in 0..<5 {
            state = SRS.apply(.good, to: state, now: now)
        }
        XCTAssertEqual(SRS.masteryStatus(for: state), .mastered)

        let lapsed = SRS.apply(.again, to: state, now: now)
        XCTAssertEqual(SRS.masteryStatus(for: lapsed), .learning, "forgetting a mastered word drops it back")
    }
}
