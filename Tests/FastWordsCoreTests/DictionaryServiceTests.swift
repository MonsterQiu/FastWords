@testable import FastWordsCore
import XCTest

final class DictionaryServiceTests: XCTestCase {
    private func decode(_ json: String) throws -> DictionaryResult? {
        let entries = try FreeDictionaryService.decode(Data(json.utf8))
        return FreeDictionaryService.firstResult(from: entries)
    }

    func testParsesPhoneticMeaningExampleAndAudio() throws {
        let json = """
        [{
          "word": "abandon",
          "phonetic": "/əˈbændən/",
          "phonetics": [
            {"text": "/əˈbændən/", "audio": ""},
            {"text": "/əˈbændən/", "audio": "https://example.com/abandon.mp3"}
          ],
          "meanings": [
            {"partOfSpeech": "verb",
             "definitions": [{"definition": "To give up control of.", "example": "Do not abandon hope."}]}
          ]
        }]
        """
        let result = try XCTUnwrap(decode(json))
        XCTAssertEqual(result.phonetic, "/əˈbændən/")
        XCTAssertEqual(result.meaning, "To give up control of.")
        XCTAssertEqual(result.example, "Do not abandon hope.")
        XCTAssertEqual(result.audioURL?.absoluteString, "https://example.com/abandon.mp3")
    }

    func testPicksFirstNonEmptyAudio() throws {
        let json = """
        [{
          "word": "brisk",
          "phonetics": [
            {"text": "/brɪsk/", "audio": ""},
            {"text": "/brɪsk/", "audio": "https://example.com/brisk.mp3"}
          ],
          "meanings": [{"definitions": [{"definition": "Quick and energetic."}]}]
        }]
        """
        let result = try XCTUnwrap(decode(json))
        XCTAssertEqual(result.audioURL?.absoluteString, "https://example.com/brisk.mp3")
        XCTAssertEqual(result.example, "")
    }

    func testFallsBackToTopLevelPhoneticWhenNoAudio() throws {
        let json = """
        [{"word": "x", "phonetic": "/ks/", "meanings": [{"definitions": [{"definition": "A letter."}]}]}]
        """
        let result = try XCTUnwrap(decode(json))
        XCTAssertEqual(result.phonetic, "/ks/")
        XCTAssertNil(result.audioURL)
    }

    func testReturnsNilWhenNoUsableContent() throws {
        let json = """
        [{"word": "empty", "meanings": [{"definitions": [{"definition": ""}]}]}]
        """
        XCTAssertNil(try decode(json))
    }

    func test404StyleBodyDecodesToEmpty() {
        // The API returns an object (not an array) for misses; decode maps that to notFound.
        let json = #"{"title": "No Definitions Found"}"#
        XCTAssertThrowsError(try FreeDictionaryService.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? DictionaryError, .notFound)
        }
    }
}
