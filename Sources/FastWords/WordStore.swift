import Combine
import Foundation
import FastWordsCore

@MainActor
final class WordStore: ObservableObject {
    struct PersistedState: Codable {
        var words: [WordEntry]
        var currentIndex: Int
        var settings: AppSettings
    }

    enum AIState: Equatable {
        case idle
        case loading
        case failed(String)
    }

    @Published private(set) var words: [WordEntry] = []
    @Published private(set) var currentIndex: Int = 0
    @Published var settings = AppSettings() {
        didSet { save() }
    }
    @Published private(set) var aiState: AIState = .idle
    @Published private(set) var importMessage: String?

    private let stateURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("FastWords", isDirectory: true)
        stateURL = directory.appendingPathComponent("state.json")

        load()
    }

    var currentWord: WordEntry? {
        guard words.indices.contains(currentIndex) else { return nil }
        return words[currentIndex]
    }

    var masteredCount: Int {
        words.filter { $0.status == .mastered }.count
    }

    var progressText: String {
        guard !words.isEmpty else { return "No words" }
        return "\(currentIndex + 1)/\(words.count) · \(masteredCount) mastered"
    }

    var progressValue: Double {
        guard !words.isEmpty else { return 0 }
        return Double(masteredCount) / Double(words.count)
    }

    func load() {
        do {
            let data = try Data(contentsOf: stateURL)
            let decoded = try JSONDecoder.fastWords.decode(PersistedState.self, from: data)
            words = decoded.words
            currentIndex = min(max(decoded.currentIndex, 0), max(decoded.words.count - 1, 0))
            settings = decoded.settings
            if words.isEmpty {
                restoreSamples()
            }
        } catch {
            restoreSamples()
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let state = PersistedState(words: words, currentIndex: currentIndex, settings: settings)
            let data = try JSONEncoder.fastWords.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            importMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func showNext() {
        currentIndex = ReviewScheduler.nextIndex(
            currentIndex: currentIndex,
            wordCount: words.count,
            mode: settings.reviewMode
        )
        aiState = .idle
        save()
    }

    func showPrevious() {
        currentIndex = ReviewScheduler.previousIndex(currentIndex: currentIndex, wordCount: words.count)
        aiState = .idle
        save()
    }

    func toggleMastered() {
        guard words.indices.contains(currentIndex) else { return }
        let nextStatus: WordStatus = words[currentIndex].status == .mastered ? .learning : .mastered
        words[currentIndex].status = nextStatus
        words[currentIndex].updatedAt = Date()
        save()
    }

    func replaceWords(_ entries: [WordEntry], sourceName: String) {
        words = entries
        currentIndex = 0
        aiState = .idle
        importMessage = "Imported \(entries.count) words from \(sourceName)."
        save()
    }

    func restoreSamples() {
        words = [
            WordEntry(
                word: "abandon",
                phonetic: "/əˈbændən/",
                meaning: "放弃；抛弃",
                example: "Do not abandon the tiny habit after one hard day."
            ),
            WordEntry(
                word: "brisk",
                phonetic: "/brɪsk/",
                meaning: "轻快的；生气勃勃的",
                example: "A brisk walk can wake up a sleepy brain."
            ),
            WordEntry(
                word: "clarity",
                phonetic: "/ˈklærəti/",
                meaning: "清晰；明确",
                example: "Clarity arrives when the sentence stops showing off."
            )
        ]
        currentIndex = 0
        importMessage = "Sample word book restored."
        save()
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
    }

    func beginAIInsight() {
        aiState = .loading
    }

    func finishAIInsight(_ text: String) {
        guard words.indices.contains(currentIndex) else { return }
        words[currentIndex].note = text
        words[currentIndex].updatedAt = Date()
        aiState = .idle
        save()
    }

    func failAIInsight(_ message: String) {
        aiState = .failed(message)
    }
}

private extension JSONEncoder {
    static var fastWords: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var fastWords: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
