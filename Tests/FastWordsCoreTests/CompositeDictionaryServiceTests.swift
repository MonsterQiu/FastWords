@testable import FastWordsCore
import XCTest

final class CompositeDictionaryServiceTests: XCTestCase {
    private struct StubService: DictionaryService {
        var result: DictionaryResult?
        var error: Error?
        func lookup(_ word: String) async throws -> DictionaryResult {
            if let error { throw error }
            return result ?? DictionaryResult()
        }
    }

    func testMergesResultsKeepingEarlierFields() async throws {
        let offline = StubService(result: DictionaryResult(phonetic: "/old/", meaning: "放弃"))
        let online = StubService(result: DictionaryResult(
            phonetic: "/new/",
            meaning: "should not overwrite Chinese",
            englishDefinition: "To give up completely.",
            example: "Do not abandon hope.",
            audioURL: URL(string: "https://e/abandon.mp3")
        ))
        let composite = CompositeDictionaryService([offline, online])
        let result = try await composite.lookup("abandon")
        XCTAssertEqual(result.phonetic, "/old/")
        XCTAssertEqual(result.meaning, "放弃")
        XCTAssertEqual(result.englishDefinition, "To give up completely.")
        XCTAssertEqual(result.example, "Do not abandon hope.")
        XCTAssertEqual(result.audioURL?.absoluteString, "https://e/abandon.mp3")
    }

    func testFallsThroughWhenFirstHasNoContent() async throws {
        let offline = StubService(result: DictionaryResult()) // empty → miss
        let online = StubService(result: DictionaryResult(phonetic: "/x/", audioURL: URL(string: "https://e/x.mp3")))
        let composite = CompositeDictionaryService([offline, online])
        let result = try await composite.lookup("rareword")
        XCTAssertEqual(result.audioURL?.absoluteString, "https://e/x.mp3")
    }

    func testFallsThroughWhenFirstThrows() async throws {
        let offline = StubService(error: DictionaryError.notFound)
        let online = StubService(result: DictionaryResult(meaning: "online meaning"))
        let composite = CompositeDictionaryService([offline, online])
        let result = try await composite.lookup("x")
        XCTAssertEqual(result.meaning, "online meaning")
    }

    func testThrowsWhenAllFail() async {
        let composite = CompositeDictionaryService([
            StubService(error: DictionaryError.notFound),
            StubService(error: DictionaryError.network("offline"))
        ])
        do {
            _ = try await composite.lookup("x")
            XCTFail("expected throw")
        } catch {
            // last error propagates
            XCTAssertNotNil(error)
        }
    }
}
