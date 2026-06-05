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

    enum LookupState: Equatable {
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
    @Published private(set) var lookupState: LookupState = .idle
    @Published private(set) var importMessage: String?

    private let stateURL: URL
    /// Directory where downloaded pronunciation clips are cached.
    let audioDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("FastWords", isDirectory: true)
        stateURL = directory.appendingPathComponent("state.json")
        audioDirectory = directory.appendingPathComponent("audio", isDirectory: true)

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
            words: words,
            mode: settings.reviewMode,
            now: Date()
        )
        aiState = .idle
        save()
    }

    func showPrevious() {
        currentIndex = ReviewScheduler.previousIndex(currentIndex: currentIndex, wordCount: words.count)
        aiState = .idle
        save()
    }

    /// Record how well the current word was recalled, update its SRS schedule,
    /// then advance to the next word.
    func grade(_ grade: ReviewGrade) {
        guard words.indices.contains(currentIndex) else { return }
        let now = Date()
        words[currentIndex].srs = SRS.apply(grade, to: words[currentIndex].srs, now: now)
        words[currentIndex].updatedAt = now
        showNext()
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

    /// Load a built-in exam word book (考研/托福/雅思/…) from the offline dictionary.
    func loadExamBook(_ category: ExamCategory) {
        let entries = OfflineDictionary.shared.words(for: category)
        guard !entries.isEmpty else {
            importMessage = "No words found for \(category.title)."
            return
        }
        words = entries
        currentIndex = 0
        aiState = .idle
        lookupState = .idle
        importMessage = "Loaded \(entries.count) \(category.title) words."
        save()
    }

    func showImportError(_ message: String) {
        importMessage = message
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

    // MARK: - Dictionary lookup

    func beginLookup() {
        lookupState = .loading
    }

    func failLookup(_ message: String) {
        lookupState = .failed(message)
    }

    /// Fill in any blank fields on the current word from a dictionary result,
    /// without clobbering data the user already has. Reports what changed so the
    /// UI can confirm the lookup did something even when nothing was missing.
    func applyLookup(_ result: DictionaryResult) {
        guard words.indices.contains(currentIndex) else { return }

        var filled: [String] = []
        if words[currentIndex].phonetic.isEmpty, !result.phonetic.isEmpty {
            words[currentIndex].phonetic = result.phonetic
            filled.append("phonetic")
        }
        if words[currentIndex].meaning.isEmpty, !result.meaning.isEmpty {
            words[currentIndex].meaning = result.meaning
            filled.append("meaning")
        }
        if words[currentIndex].example.isEmpty, !result.example.isEmpty {
            words[currentIndex].example = result.example
            filled.append("example")
        }
        words[currentIndex].updatedAt = Date()
        lookupState = .idle

        if filled.isEmpty {
            importMessage = result.audioURL == nil
                ? "Dictionary checked — this word is already complete."
                : "Dictionary checked — added pronunciation audio."
        } else {
            importMessage = "Dictionary added: \(filled.joined(separator: ", "))."
        }
        save()
    }

    /// Record that a word now has a cached pronunciation clip on disk.
    func setAudioFileName(_ name: String, forWordID id: UUID) {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return }
        words[index].audioFileName = name
        save()
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
