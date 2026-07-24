import XCTest
@testable import FastWordsCore

final class AIClientLookupTests: XCTestCase {
    func testParseLookupResponse_standardTemplate() {
        let text = """
        音标：/ˈskedʒuːl/
        中文：n. 时间表；vt. 安排
        英英：a plan of activities or events
        例句：I have a busy schedule this week.
        """
        let result = AIClient.parseLookupResponse(text)
        XCTAssertEqual(result.phonetic, "/ˈskedʒuːl/")
        XCTAssertEqual(result.meaning, "n. 时间表；vt. 安排")
        XCTAssertEqual(result.englishDefinition, "a plan of activities or events")
        XCTAssertEqual(result.example, "I have a busy schedule this week.")
    }

    func testParseLookupResponse_englishPrefixes() {
        let text = """
        Phonetic: /test/
        Meaning: n. 测试
        English: a procedure for evaluation
        Example: This is a test.
        """
        let result = AIClient.parseLookupResponse(text)
        XCTAssertEqual(result.phonetic, "/test/")
        XCTAssertEqual(result.meaning, "n. 测试")
        XCTAssertEqual(result.englishDefinition, "a procedure for evaluation")
        XCTAssertEqual(result.example, "This is a test.")
    }

    func testParseLookupResponse_fallbackWholeText() {
        let text = "just a free-form definition without labels"
        let result = AIClient.parseLookupResponse(text)
        XCTAssertEqual(result.meaning, text)
        XCTAssertTrue(result.englishDefinition.isEmpty)
    }
}
