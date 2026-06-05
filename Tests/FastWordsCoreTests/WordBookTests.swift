@testable import FastWordsCore
import XCTest

final class WordBookTests: XCTestCase {
    func testMergeAddsNewWordsAndSkipsDuplicates() {
        var book = WordBook(name: "Test", source: .samples, words: [
            WordEntry(word: "abandon", meaning: "放弃"),
            WordEntry(word: "brisk", meaning: "轻快的")
        ])

        let result = book.merge([
            WordEntry(word: "Abandon", meaning: "different"), // case-insensitive dup
            WordEntry(word: "clarity", meaning: "清晰")
        ])

        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(book.words.count, 3)
        XCTAssertEqual(book.words.map(\.word), ["abandon", "brisk", "clarity"])
    }

    func testMergePreservesExistingProgress() {
        var existing = WordEntry(word: "abandon", meaning: "放弃")
        existing.srs.repetitions = 5
        existing.status = .mastered
        var book = WordBook(name: "Test", source: .samples, words: [existing])

        book.merge([WordEntry(word: "abandon", meaning: "new meaning")])

        XCTAssertEqual(book.words.count, 1)
        XCTAssertEqual(book.words[0].srs.repetitions, 5, "existing SRS progress must be kept")
        XCTAssertEqual(book.words[0].status, .mastered)
        XCTAssertEqual(book.words[0].meaning, "放弃", "existing data must not be overwritten")
    }

    func testMergeIntoEmptyBookAddsAll() {
        var book = WordBook(name: "Empty", source: .samples, words: [])
        let result = book.merge([WordEntry(word: "a"), WordEntry(word: "b")])
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.skipped, 0)
    }

    func testMasteredCount() {
        var mastered = WordEntry(word: "a")
        mastered.status = .mastered
        let book = WordBook(name: "T", source: .samples, words: [mastered, WordEntry(word: "b")])
        XCTAssertEqual(book.masteredCount, 1)
    }

    func testExamSourceEquatableForReuse() {
        XCTAssertEqual(WordBookSource.exam(.gre), WordBookSource.exam(.gre))
        XCTAssertNotEqual(WordBookSource.exam(.gre), WordBookSource.exam(.toefl))
    }
}
