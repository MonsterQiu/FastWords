import XCTest
@testable import FastWordsCore

final class SpellingSuggesterTests: XCTestCase {
    private let pool = [
        "diversity", "diverse", "diversion", "divert",
        "abandon", "ability", "schedule", "school", "scholar"
    ]

    func testSuggestsNearMiss() {
        let hits = SpellingSuggester.suggestions(for: "diversety", among: pool, limit: 5)
        XCTAssertTrue(hits.map { $0.lowercased() }.contains("diversity"))
    }

    func testEmptyForExactMatchOnlyPoolMember() {
        // Exact match is filtered out; other near words may still appear.
        let hits = SpellingSuggester.suggestions(for: "diversity", among: pool, limit: 5)
        XCTAssertFalse(hits.map { $0.lowercased() }.contains("diversity"))
    }

    func testLevenshteinKnownValues() {
        XCTAssertEqual(SpellingSuggester.levenshtein("kitten", "sitting", maxDistance: 3), 3)
        XCTAssertEqual(SpellingSuggester.levenshtein("abc", "abc", maxDistance: 2), 0)
        XCTAssertEqual(SpellingSuggester.levenshtein("abc", "xyz", maxDistance: 1), 2) // exceeds → max+1
    }

    func testShortQueryIsStricter() {
        // maxDistance 1 for length <= 3
        XCTAssertEqual(SpellingSuggester.maxDistance(for: "cat"), 1)
        XCTAssertEqual(SpellingSuggester.maxDistance(for: "diversity"), 2)
    }

    func testTooShortQueryReturnsEmpty() {
        XCTAssertTrue(SpellingSuggester.suggestions(for: "a", among: pool).isEmpty)
    }
}
