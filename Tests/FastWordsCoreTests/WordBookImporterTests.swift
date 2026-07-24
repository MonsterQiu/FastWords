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

    func testImportsTwoColumnPlainTextAsWordAndMeaning() throws {
        let entries = try WordBookImporter.importTXT("""
        abandon\t放弃
        brisk\t轻快的
        """)

        XCTAssertEqual(entries[0].word, "abandon")
        XCTAssertEqual(entries[0].phonetic, "")
        XCTAssertEqual(entries[0].meaning, "放弃")
        XCTAssertEqual(entries[1].meaning, "轻快的")
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

    func testImportsAnkiMetadataAndHTML() throws {
        let entries = try WordBookImporter.importTXT("""
        #separator:Tab
        #html:true
        abandon\t<b>放弃</b><br>抛弃
        diversity\t多样性
        """)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].word, "abandon")
        XCTAssertEqual(entries[0].meaning, "放弃 抛弃")
        XCTAssertEqual(entries[1].word, "diversity")
    }

    func testImportsEudicStyleCSVHeaders() throws {
        let entries = try WordBookImporter.importCSV("""
        单词,音标,翻译,例句
        schedule,/ˈskedʒuːl/,时间表,I have a busy schedule.
        """)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].word, "schedule")
        XCTAssertEqual(entries[0].phonetic, "/ˈskedʒuːl/")
        XCTAssertEqual(entries[0].meaning, "时间表")
        XCTAssertEqual(entries[0].example, "I have a busy schedule.")
    }

    func testImportsAnkiFrontBackCSV() throws {
        let entries = try WordBookImporter.importCSV("""
        Front,Back
        abandon,放弃；抛弃
        brisk,轻快的
        """)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].word, "abandon")
        XCTAssertEqual(entries[0].meaning, "放弃；抛弃")
        XCTAssertEqual(entries[1].word, "brisk")
    }

    func testSanitizeFieldStripsHTML() {
        let cleaned = WordBookImporter.sanitizeField("<div>hello<br/>world</div>")
        XCTAssertEqual(cleaned, "hello world")
    }
}
