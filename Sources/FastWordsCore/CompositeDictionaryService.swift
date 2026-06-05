import Foundation

/// Tries each dictionary in order, returning the first successful result.
///
/// Used to prefer the offline Chinese dictionary (ECDICT) and fall back to the
/// online English dictionary (which can also supply a human audio clip).
public struct CompositeDictionaryService: DictionaryService {
    private let services: [any DictionaryService]

    public init(_ services: [any DictionaryService]) {
        self.services = services
    }

    public func lookup(_ word: String) async throws -> DictionaryResult {
        var lastError: Error = DictionaryError.notFound
        for service in services {
            do {
                let result = try await service.lookup(word)
                // Treat a result with no usable content as a miss so we fall through.
                if !result.meaning.isEmpty || !result.phonetic.isEmpty || result.audioURL != nil {
                    return result
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
