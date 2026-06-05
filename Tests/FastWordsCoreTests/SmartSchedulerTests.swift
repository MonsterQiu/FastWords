@testable import FastWordsCore
import XCTest

final class SmartSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ word: String, dueOffsetDays: Double, status: WordStatus = .learning) -> WordEntry {
        var e = WordEntry(word: word, status: status)
        e.fsrs.dueDate = now.addingTimeInterval(dueOffsetDays * 86_400)
        return e
    }

    func testSmartPicksMostOverdueWord() {
        let words = [
            entry("a", dueOffsetDays: 5),    // index 0, current
            entry("b", dueOffsetDays: -10),  // most overdue
            entry("c", dueOffsetDays: -2)
        ]
        let next = ReviewScheduler.nextIndex(currentIndex: 0, words: words, mode: .smart, now: now)
        XCTAssertEqual(next, 1)
    }

    func testSmartSkipsCurrentWord() {
        let words = [
            entry("a", dueOffsetDays: -100), // current; most overdue but must be skipped
            entry("b", dueOffsetDays: -1)
        ]
        let next = ReviewScheduler.nextIndex(currentIndex: 0, words: words, mode: .smart, now: now)
        XCTAssertEqual(next, 1)
    }

    func testSmartDeprioritizesMasteredWords() {
        let words = [
            entry("a", dueOffsetDays: 0),                       // current
            entry("b", dueOffsetDays: -50, status: .mastered),  // overdue but mastered
            entry("c", dueOffsetDays: 100)                      // not due, but still learning
        ]
        let next = ReviewScheduler.nextIndex(currentIndex: 0, words: words, mode: .smart, now: now)
        XCTAssertEqual(next, 2, "Learning words should beat mastered words even when the mastered one is overdue")
    }

    func testSmartFallsBackWhenSingleWord() {
        let words = [entry("a", dueOffsetDays: -1)]
        XCTAssertEqual(ReviewScheduler.nextIndex(currentIndex: 0, words: words, mode: .smart, now: now), 0)
    }
}
