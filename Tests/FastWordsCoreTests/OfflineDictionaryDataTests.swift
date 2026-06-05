@testable import FastWordsCore
import XCTest

/// Verifies the real bundled ECDICT subset loads and resolves Chinese meanings.
final class OfflineDictionaryDataTests: XCTestCase {
    func testBundledDictionaryResolvesCommonWord() async throws {
        let dict = OfflineDictionary()
        let result = try await dict.lookup("abandon")
        XCTAssertFalse(result.meaning.isEmpty, "abandon should have a Chinese meaning")
        // Chinese characters present
        XCTAssertTrue(result.meaning.unicodeScalars.contains { $0.value > 0x4E00 && $0.value < 0x9FFF },
                      "meaning should contain Chinese characters: \(result.meaning)")
    }

    func testBundledDictionaryHasEnglishDefinition() async throws {
        let dict = OfflineDictionary()
        let result = try await dict.lookup("abandon")
        XCTAssertFalse(result.englishDefinition.isEmpty, "abandon should have an English definition")
    }

    func testExamBooksAreNonEmpty() {
        let dict = OfflineDictionary()
        for exam in ExamCategory.allCases {
            let words = dict.words(for: exam)
            XCTAssertFalse(words.isEmpty, "\(exam.title) word book should not be empty")
        }
    }

    func testCetWordBookSizesAreReasonable() {
        let dict = OfflineDictionary()
        // From the data analysis: gre ~7504, cet4 ~3849.
        XCTAssertGreaterThan(dict.words(for: .gre).count, 5000)
        XCTAssertGreaterThan(dict.words(for: .cet4).count, 3000)
    }
}
