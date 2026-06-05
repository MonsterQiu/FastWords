@testable import FastWordsCore
import XCTest

final class MeaningFormatterTests: XCTestCase {
    func testSplitsLeadingPartOfSpeech() {
        let (pos, body) = MeaningFormatter.splitPartOfSpeech("adv. 最终")
        XCTAssertEqual(pos, "adv")
        XCTAssertEqual(body, "最终")
    }

    func testSplitsVerbTransitive() {
        let (pos, body) = MeaningFormatter.splitPartOfSpeech("vt. 放弃, 抛弃")
        XCTAssertEqual(pos, "vt")
        XCTAssertEqual(body, "放弃, 抛弃")
    }

    func testNoPartOfSpeechWhenLeadingTokenTooLong() {
        let (pos, body) = MeaningFormatter.splitPartOfSpeech("Washington. 华盛顿")
        XCTAssertNil(pos)
        XCTAssertEqual(body, "Washington. 华盛顿")
    }

    func testNoPeriodMeansNoSplit() {
        let (pos, body) = MeaningFormatter.splitPartOfSpeech("纯中文释义")
        XCTAssertNil(pos)
        XCTAssertEqual(body, "纯中文释义")
    }

    func testFormattedPhoneticWrapsBareTranscription() {
        XCTAssertEqual(MeaningFormatter.formattedPhonetic("ˈklaɪmət"), "/ˈklaɪmət/")
        XCTAssertEqual(MeaningFormatter.formattedPhonetic("ә'bændәn"), "/ә'bændәn/")
    }

    func testFormattedPhoneticDoesNotDoubleSlashes() {
        XCTAssertEqual(MeaningFormatter.formattedPhonetic("/ˈklaɪmət/"), "/ˈklaɪmət/")
        XCTAssertEqual(MeaningFormatter.formattedPhonetic(" [ˈklaɪmət] "), "/ˈklaɪmət/")
    }

    func testFormattedPhoneticEmptyStaysEmpty() {
        XCTAssertEqual(MeaningFormatter.formattedPhonetic("   "), "")
        XCTAssertEqual(MeaningFormatter.formattedPhonetic(""), "")
    }
}
