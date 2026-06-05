import Combine
import Foundation
import FastWordsCore

@MainActor
final class WordStore: ObservableObject {
    struct PersistedState: Codable {
        // New multi-book shape.
        var books: [WordBook]?
        var currentBookID: UUID?
        var settings: AppSettings

        // Legacy single-book fields (pre-multi-book). Decoded for migration.
        var words: [WordEntry]?
        var currentIndex: Int?
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

    @Published private(set) var books: [WordBook] = []
    @Published private(set) var currentBookID: UUID?
    @Published var settings = AppSettings() {
        didSet { if !isLoading { save() } }
    }
    @Published private(set) var aiState: AIState = .idle
    @Published private(set) var lookupState: LookupState = .idle
    @Published private(set) var importMessage: String?

    /// Suppresses the `settings` didSet auto-save while `load()` is populating
    /// state, so a half-loaded store is never persisted (which previously wiped
    /// legacy word data during migration).
    private var isLoading = false

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

    // MARK: - Current book access

    private var currentBookIndex: Int? {
        guard let id = currentBookID else { return nil }
        return books.firstIndex { $0.id == id }
    }

    var currentBook: WordBook? {
        guard let index = currentBookIndex else { return nil }
        return books[index]
    }

    /// Words of the current book. Reads/writes proxy into the book array so the
    /// existing word-mutation methods continue to work unchanged.
    private(set) var words: [WordEntry] {
        get { currentBook?.words ?? [] }
        set {
            guard let index = currentBookIndex else { return }
            books[index].words = newValue
        }
    }

    private(set) var currentIndex: Int {
        get { currentBook?.currentIndex ?? 0 }
        set {
            guard let index = currentBookIndex else { return }
            books[index].currentIndex = newValue
        }
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

    // MARK: - Book management

    /// Switch the active word book, preserving each book's own progress.
    func selectBook(_ id: UUID) {
        guard books.contains(where: { $0.id == id }) else { return }
        currentBookID = id
        aiState = .idle
        lookupState = .idle
        importMessage = nil
        save()
    }

    /// Delete a word book. Keeps at least one book by restoring samples if the
    /// last one is removed; reselects another book when the current is deleted.
    func deleteBook(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = (id == currentBookID)
        books.remove(at: index)

        if books.isEmpty {
            restoreSamples()
            return
        }
        if wasCurrent {
            currentBookID = books.first?.id
        }
        aiState = .idle
        lookupState = .idle
        save()
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoded = try JSONDecoder.fastWords.decode(PersistedState.self, from: data)
            settings = decoded.settings

            var migrated = false
            if let savedBooks = decoded.books, !savedBooks.isEmpty {
                books = savedBooks
                currentBookID = decoded.currentBookID ?? savedBooks.first?.id
            } else if let legacyWords = decoded.words, !legacyWords.isEmpty {
                // Migrate the old single-book shape into one default book.
                let book = WordBook(
                    name: "我的词书",
                    source: .imported("state.json"),
                    words: legacyWords,
                    currentIndex: max(0, min(decoded.currentIndex ?? 0, legacyWords.count - 1))
                )
                books = [book]
                currentBookID = book.id
                migrated = true
            } else {
                restoreSamples()
                return
            }

            clampCurrentIndex()
            if currentBookID == nil { currentBookID = books.first?.id }
            if books.isEmpty {
                restoreSamples()
            } else if migrated {
                // Persist the migrated multi-book shape so it survives next launch.
                save()
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

            let state = PersistedState(
                books: books,
                currentBookID: currentBookID,
                settings: settings,
                words: nil,
                currentIndex: nil
            )
            let data = try JSONEncoder.fastWords.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            importMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func clampCurrentIndex() {
        guard let index = currentBookIndex else { return }
        let count = books[index].words.count
        books[index].currentIndex = max(0, min(books[index].currentIndex, max(count - 1, 0)))
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

    /// Record how well the current word was recalled, update its SRS schedule
    /// and mastery status, then advance to the next word.
    func grade(_ grade: ReviewGrade) {
        guard words.indices.contains(currentIndex) else { return }
        let now = Date()
        words[currentIndex].srs = SRS.apply(grade, to: words[currentIndex].srs, now: now)
        // Mastery is a consequence of the SRS schedule, not a separate manual
        // flag: a long-enough streak/interval marks the word mastered; a lapse
        // (which resets the streak) drops it back to learning.
        words[currentIndex].status = SRS.masteryStatus(for: words[currentIndex].srs)
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

    /// Import a file's entries: merge into the current book if one exists
    /// (dedup by word, preserving existing SRS progress), otherwise create a
    /// new book. Switches to and surfaces the affected book.
    func importEntries(_ entries: [WordEntry], sourceName: String) {
        guard !entries.isEmpty else {
            importMessage = "没有可导入的单词。"
            return
        }

        if let index = currentBookIndex {
            let result = books[index].merge(entries)
            currentBookID = books[index].id
            importMessage = "已合并到《\(books[index].name)》：新增 \(result.added)，跳过 \(result.skipped) 个重复。"
        } else {
            let book = WordBook(name: sourceName, source: .imported(sourceName), words: entries)
            books.append(book)
            currentBookID = book.id
            importMessage = "已导入《\(sourceName)》：\(entries.count) 个单词。"
        }
        aiState = .idle
        lookupState = .idle
        save()
    }

    /// Load a built-in exam word book (考研/托福/雅思/…). If a book for this
    /// category already exists, switch to it (preserving progress) instead of
    /// recreating it.
    func loadExamBook(_ category: ExamCategory) {
        if let existing = books.first(where: { $0.source == .exam(category) }) {
            selectBook(existing.id)
            importMessage = "已切换到《\(category.title)》。"
            return
        }

        let entries = OfflineDictionary.shared.words(for: category)
        guard !entries.isEmpty else {
            importMessage = "未找到 \(category.title) 词库。"
            return
        }
        let book = WordBook(name: category.title, source: .exam(category), words: entries)
        books.append(book)
        currentBookID = book.id
        aiState = .idle
        lookupState = .idle
        importMessage = "已加载《\(category.title)》：\(entries.count) 个单词。"
        save()
    }

    func showImportError(_ message: String) {
        importMessage = message
    }

    func restoreSamples() {
        let sampleWords = [
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
        let book = WordBook(name: "示例词书", source: .samples, words: sampleWords)
        books = [book]
        currentBookID = book.id
        importMessage = "已恢复示例词书。"
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
                ? "词典已查询：该词信息已完整。"
                : "词典已查询：已补充真人发音。"
        } else {
            let labels = filled.map { field -> String in
                switch field {
                case "phonetic": return "音标"
                case "meaning": return "释义"
                case "example": return "例句"
                default: return field
                }
            }
            importMessage = "词典已补充：\(labels.joined(separator: "、"))。"
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
