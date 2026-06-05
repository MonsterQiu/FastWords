import Foundation
@testable import FastWordsCore
import XCTest

final class WordBookImporterTests: XCTestCase {
    func testImportsPlainTextWithTabs() throws {
        let entries = try WordBookImporter.importTXT("""
        abandon\t/əˈbændən/\t放弃\tDo not abandon it.
        brisk\t/brɪsk/\t轻快的
        """)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].word, "abandon")
        XCTAssertEqual(entries[0].phonetic, "/əˈbændən/")
        XCTAssertEqual(entries[0].meaning, "放弃")
        XCTAssertEqual(entries[0].example, "Do not abandon it.")
        XCTAssertEqual(entries[1].word, "brisk")
    }

    func testImportsCSVWithHeaderAndQuotedComma() throws {
        let entries = try WordBookImporter.importCSV("""
        word,phonetic,meaning,example
        clarity,/ˈklærəti/,"清晰, 明确","Clarity, thankfully, can be learned."
        """)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].word, "clarity")
        XCTAssertEqual(entries[0].meaning, "清晰, 明确")
        XCTAssertEqual(entries[0].example, "Clarity, thankfully, can be learned.")
    }

    func testRejectsEmptyText() {
        XCTAssertThrowsError(try WordBookImporter.importTXT("\n\n")) { error in
            XCTAssertEqual(error as? WordBookImportError, .emptyWordBook)
        }
    }
}
