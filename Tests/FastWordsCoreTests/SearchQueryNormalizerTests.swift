import XCTest
@testable import FastWordsCore

final class SearchQueryNormalizerTests: XCTestCase {
    func testPureWordUnchanged() {
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "diversity"), "diversity")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "  Abandon  "), "Abandon")
    }

    func testChineseWhatDoesItMean() {
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "diversity 什么意思"), "diversity")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "diversity什么意思"), "diversity")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "diversity是什么意思"), "diversity")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "abandon 的意思"), "abandon")
    }

    func testEnglishWhatDoesItMean() {
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "what does diversity mean"), "diversity")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "define abandon"), "abandon")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "meaning of clarity"), "clarity")
    }

    func testMultiWordEnglish() {
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "look up"), "look up")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "look up 什么意思"), "look up")
    }

    func testHyphenAndApostrophe() {
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "well-known 什么意思"), "well-known")
        XCTAssertEqual(SearchQueryNormalizer.headword(from: "don't 什么意思"), "don't")
    }
}
