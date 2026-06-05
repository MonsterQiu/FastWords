@testable import FastWordsCore
import XCTest

final class OfflineDictionaryTests: XCTestCase {
    // Fields: word \t phonetic \t 中文 \t 英英 \t tag
    private let sample = """
    abandon\tә'bændәn\tvt. 放弃, 抛弃; n. 放任\tv. forsake, leave behind\tcet4 cet6 ky toefl gre
    brisk\tbrisk\ta. 敏锐的, 活泼的\ta. quick and energetic\tcet6 ky toefl
    \t\t空词应被跳过\t\tgre
    bad line without enough fields
    """

    func testParsesAllFiveFields() {
        let entries = OfflineDictionary.parse(sample)
        XCTAssertEqual(entries.count, 2, "Empty-word and malformed lines should be skipped")

        let abandon = entries[0]
        XCTAssertEqual(abandon.word, "abandon")
        XCTAssertEqual(abandon.phonetic, "ә'bændәn")
        XCTAssertEqual(abandon.translation, "vt. 放弃, 抛弃; n. 放任")
        XCTAssertEqual(abandon.englishDefinition, "v. forsake, leave behind")
        XCTAssertEqual(abandon.tags, [.cet4, .cet6, .ky, .toefl, .gre])
    }

    func testTranslationKeepsInternalCommasAndSemicolons() {
        let entries = OfflineDictionary.parse(sample)
        XCTAssertTrue(entries[0].translation.contains(","))
        XCTAssertTrue(entries[0].translation.contains(";"))
    }

    func testUnknownTagIsIgnored() {
        let entries = OfflineDictionary.parse("xyz\t/x/\t释义\tdefinition\tcet4 bogus gre")
        XCTAssertEqual(entries[0].tags, [.cet4, .gre])
    }

    func testNormalizeIsCaseInsensitiveAndTrimmed() {
        XCTAssertEqual(OfflineDictionary.normalize("  Abandon "), "abandon")
    }
}
