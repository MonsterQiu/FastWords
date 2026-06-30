import Foundation

/// Tries dictionaries in order and merges their non-empty fields.
///
/// This keeps the best part of each source: the bundled offline ECDICT usually
/// provides Chinese meanings, while the online Free Dictionary source can add
/// English definitions, examples and human audio. Earlier services win when two
/// sources provide the same field, so an English-only API will not overwrite a
/// Chinese translation from the offline dictionary.
public struct CompositeDictionaryService: DictionaryService {
    private let services: [any DictionaryService]

    public init(_ services: [any DictionaryService]) {
        self.services = services
    }

    public func lookup(_ word: String) async throws -> DictionaryResult {
        var merged = DictionaryResult()
        var foundAnyContent = false
        var lastError: Error = DictionaryError.notFound

        for service in services {
            do {
                let result = try await service.lookup(word)
                guard result.hasUsableContent else { continue }

                foundAnyContent = true
                merged.fillMissingFields(from: result)
            } catch {
                lastError = error
            }
        }

        if foundAnyContent {
            return merged
        }
        throw lastError
    }
}

private extension DictionaryResult {
    var hasUsableContent: Bool {
        !phonetic.isEmpty
            || !meaning.isEmpty
            || !englishDefinition.isEmpty
            || !example.isEmpty
            || audioURL != nil
    }

    mutating func fillMissingFields(from other: DictionaryResult) {
        if phonetic.isEmpty, !other.phonetic.isEmpty {
            phonetic = other.phonetic
        }
        if meaning.isEmpty, !other.meaning.isEmpty {
            meaning = other.meaning
        }
        if englishDefinition.isEmpty, !other.englishDefinition.isEmpty {
            englishDefinition = other.englishDefinition
        }
        if example.isEmpty, !other.example.isEmpty {
            example = other.example
        }
        if audioURL == nil, other.audioURL != nil {
            audioURL = other.audioURL
        }
    }
}
