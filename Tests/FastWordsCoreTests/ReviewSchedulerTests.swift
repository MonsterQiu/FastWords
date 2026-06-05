@testable import FastWordsCore
import XCTest

final class ReviewSchedulerTests: XCTestCase {
    func testSequentialWraps() {
        XCTAssertEqual(
            ReviewScheduler.nextIndex(currentIndex: 2, wordCount: 3, mode: .sequential),
            0
        )
    }

    func testPreviousWraps() {
        XCTAssertEqual(
            ReviewScheduler.previousIndex(currentIndex: 0, wordCount: 3),
            2
        )
    }

    func testRandomDoesNotRepeatWhenPossible() {
        for _ in 0..<20 {
            XCTAssertNotEqual(
                ReviewScheduler.nextIndex(currentIndex: 0, wordCount: 3, mode: .random),
                0
            )
        }
    }
}
