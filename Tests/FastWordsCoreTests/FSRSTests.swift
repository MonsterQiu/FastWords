@testable import FastWordsCore
import XCTest

/// Verifies the FSRS-6 scheduler against numeric anchors from the reference
/// implementations (fsrs-rs tests, default parameters).
final class FSRSTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testHas21DefaultParameters() {
        XCTAssertEqual(FSRS.defaultParameters.count, 21)
        XCTAssertEqual(FSRS.defaultParameters[20], 0.1542, accuracy: 1e-6) // FSRS-6 decay marker
    }

    func testForgettingCurveAnchors() {
        // (Δt, S) → R, from fsrs-rs power_forgetting_curve tests.
        let cases: [(Double, Double, Double)] = [
            (0, 1, 1.0), (1, 2, 0.9403443), (2, 3, 0.9253786),
            (3, 4, 0.9185229), (4, 4, 0.9), (5, 2, 0.8261359)
        ]
        for (t, s, expected) in cases {
            XCTAssertEqual(FSRS.retrievability(elapsedDays: t, stability: s), expected, accuracy: 1e-4,
                           "R(t=\(t), S=\(s))")
        }
    }

    func testInitialStabilityIsFirstWeights() {
        XCTAssertEqual(FSRS.initialStability(.again), FSRS.defaultParameters[0], accuracy: 1e-6)
        XCTAssertEqual(FSRS.initialStability(.hard), FSRS.defaultParameters[1], accuracy: 1e-6)
        XCTAssertEqual(FSRS.initialStability(.good), FSRS.defaultParameters[2], accuracy: 1e-6)
    }

    func testFirstReviewSetsStateAndFutureDue() {
        let state = FSRS.review(FSRSState(), grade: .good, now: now, calendar: cal)
        XCTAssertEqual(state.reps, 1)
        XCTAssertEqual(state.stability, FSRS.initialStability(.good), accuracy: 1e-6)
        XCTAssertGreaterThan(state.dueDate, now)
    }

    func testGoodReviewsGrowStability() {
        var state = FSRS.review(FSRSState(), grade: .good, now: now, calendar: cal)
        let firstStability = state.stability
        // Review again a few days later.
        let later = cal.date(byAdding: .day, value: FSRS.interval(stability: firstStability), to: now)!
        state = FSRS.review(state, grade: .good, now: later, calendar: cal)
        XCTAssertGreaterThan(state.stability, firstStability, "a successful recall should increase stability")
        XCTAssertEqual(state.reps, 2)
    }

    func testAgainAddsLapseAndKeepsStabilityLow() {
        var state = FSRS.review(FSRSState(), grade: .good, now: now, calendar: cal)
        let later = cal.date(byAdding: .day, value: 10, to: now)!
        state = FSRS.review(state, grade: .again, now: later, calendar: cal)
        XCTAssertEqual(state.lapses, 1)
        XCTAssertLessThan(state.stability, 21, "a lapse should not leave the card mastered-stable")
    }

    func testMasteryFromStability() {
        var notMastered = FSRSState()
        XCTAssertEqual(FSRS.masteryStatus(for: notMastered), .learning)
        notMastered.reps = 3
        notMastered.stability = 30
        XCTAssertEqual(FSRS.masteryStatus(for: notMastered), .mastered)
        notMastered.stability = 5
        XCTAssertEqual(FSRS.masteryStatus(for: notMastered), .learning)
    }

    func testMigrationFromSM2SeedsStability() {
        var sm2 = SRSState()
        sm2.repetitions = 4
        sm2.intervalDays = 30
        sm2.dueDate = now
        let fsrs = FSRSState.migrated(fromSM2: sm2)
        XCTAssertEqual(fsrs.reps, 4)
        XCTAssertEqual(fsrs.stability, 30, accuracy: 1e-6)
        XCTAssertEqual(fsrs.dueDate, now)
    }

    func testMigrationOfNeverReviewedStaysNew() {
        let fsrs = FSRSState.migrated(fromSM2: SRSState())
        XCTAssertEqual(fsrs.reps, 0)
        XCTAssertTrue(fsrs.isDue(asOf: now))
    }
}
