import Foundation

/// A definition looked up from a dictionary source.
public struct DictionaryResult: Equatable, Sendable {
    public var phonetic: String
    public var meaning: String
    public var example: String
    /// Remote URL of a human pronunciation clip, if the source provided one.
    public var audioURL: URL?

    public init(phonetic: String = "", meaning: String = "", example: String = "", audioURL: URL? = nil) {
        self.phonetic = phonetic
        self.meaning = meaning
        self.example = example
        self.audioURL = audioURL
    }
}

public enum DictionaryError: Error, Equatable {
    case notFound
    case network(String)
}

/// Looks up a single word's phonetic / meaning / example / audio.
/// Abstracted so the live network client can be swapped for a mock in tests.
public protocol DictionaryService: Sendable {
    func lookup(_ word: String) async throws -> DictionaryResult
}

/// Live client for the free, key-less dictionaryapi.dev service.
public struct FreeDictionaryService: DictionaryService {
    private let session: URLSession
    private let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func lookup(_ word: String) async throws -> DictionaryResult {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictionaryError.notFound }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        let url = baseURL.appendingPathComponent(encoded)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw DictionaryError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw DictionaryError.notFound }
            guard (200..<300).contains(http.statusCode) else {
                throw DictionaryError.network("HTTP \(http.statusCode)")
            }
        }

        let entries = try Self.decode(data)
        guard let result = Self.firstResult(from: entries) else { throw DictionaryError.notFound }
        return result
    }

    // MARK: - Parsing (pure, unit-testable)

    static func decode(_ data: Data) throws -> [APIEntry] {
        do {
            return try JSONDecoder().decode([APIEntry].self, from: data)
        } catch {
            throw DictionaryError.notFound
        }
    }

    /// Build a `DictionaryResult` from the first usable definition, preferring a
    /// phonetic entry that carries a non-empty audio URL.
    static func firstResult(from entries: [APIEntry]) -> DictionaryResult? {
        guard let entry = entries.first else { return nil }

        let audioPhonetic = entry.phonetics?.first { ($0.audio?.isEmpty == false) }
        let textPhonetic = entry.phonetic
            ?? entry.phonetics?.first { ($0.text?.isEmpty == false) }?.text
            ?? audioPhonetic?.text
            ?? ""

        let definition = entry.meanings?.first?.definitions?.first
        let meaning = definition?.definition ?? ""
        let example = definition?.example ?? ""

        let audioURL = audioPhonetic?.audio.flatMap { URL(string: $0) }

        guard !meaning.isEmpty || !textPhonetic.isEmpty || audioURL != nil else { return nil }
        return DictionaryResult(phonetic: textPhonetic, meaning: meaning, example: example, audioURL: audioURL)
    }

    // MARK: - API model

    struct APIEntry: Decodable {
        var word: String?
        var phonetic: String?
        var phonetics: [APIPhonetic]?
        var meanings: [APIMeaning]?
    }

    struct APIPhonetic: Decodable {
        var text: String?
        var audio: String?
    }

    struct APIMeaning: Decodable {
        var partOfSpeech: String?
        var definitions: [APIDefinition]?
    }

    struct APIDefinition: Decodable {
        var definition: String?
        var example: String?
    }
}
