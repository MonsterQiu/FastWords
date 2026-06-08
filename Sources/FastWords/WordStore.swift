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
        /// Daily review counts (yyyy-MM-dd → grade taps that day).
        var reviewLog: [String: Int]?
        /// Global per-word learning progress, keyed by lowercased word, shared
        /// across every book (you study a *word*, not a book-specific copy).
        var wordProgress: [String: WordProgress]?

        // Legacy single-book fields (pre-multi-book). Decoded for migration.
        var words: [WordEntry]?
        var currentIndex: Int?
    }

    /// A word's learning state, shared across all books that contain it.
    struct WordProgress: Codable, Equatable {
        var fsrs: FSRSState
        var status: WordStatus
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
    /// Daily review counts for the stats heatmap (yyyy-MM-dd → count).
    @Published private(set) var reviewLog: [String: Int] = [:]
    /// Global per-word progress (key = lowercased word). The single source of
    /// truth for FSRS state & mastery, shared across every book.
    @Published private(set) var wordProgress: [String: WordProgress] = [:]
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

    /// Lowercased lookup key for global per-word progress.
    private func progressKey(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Overlay the shared global progress onto a book entry so the rest of the
    /// app reads each word's *shared* FSRS state & mastery, not the stale copy
    /// stored inside the book.
    private func withProgress(_ entry: WordEntry) -> WordEntry {
        guard let p = wordProgress[progressKey(entry.word)] else { return entry }
        var e = entry
        e.fsrs = p.fsrs
        e.status = p.status
        return e
    }

    private var currentBookIndex: Int? {
        guard let id = currentBookID else { return nil }
        return books.firstIndex { $0.id == id }
    }

    var currentBook: WordBook? {
        guard let index = currentBookIndex else { return nil }
        return books[index]
    }

    /// Words of the current book, each carrying the shared global progress.
    /// Writes to text fields (meaning/phonetic/etc.) still proxy into the book;
    /// progress fields (fsrs/status) are owned by the global table.
    private(set) var words: [WordEntry] {
        get { (currentBook?.words ?? []).map(withProgress) }
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

    /// Number of mastered words in a book, counted against the shared global
    /// progress table (so a word mastered in another book counts here too).
    func masteredCount(in book: WordBook) -> Int {
        book.words.reduce(0) { count, entry in
            wordProgress[progressKey(entry.word)]?.status == .mastered ? count + 1 : count
        }
    }

    /// Total distinct mastered words across the current books (no double-counting
    /// words shared between books). Counts only words still present in some book,
    /// so progress orphaned by a deleted book doesn't inflate the total.
    var totalMasteredCount: Int {
        var keys = Set<String>()
        for book in books {
            for entry in book.words {
                let key = progressKey(entry.word)
                if keys.contains(key) { continue }
                if wordProgress[key]?.status == .mastered { keys.insert(key) }
            }
        }
        return keys.count
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
            reviewLog = decoded.reviewLog ?? [:]
            wordProgress = decoded.wordProgress ?? [:]

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
            } else {
                restoreSamples()
                return
            }

            // Migrate per-book progress into the shared global table when this
            // state predates global progress (no wordProgress key). Keeps the
            // most-reviewed copy if a word appears in several books — so your
            // existing progress is preserved, not reset.
            if decoded.wordProgress == nil {
                migrateBookProgressIntoGlobal()
            }

            clampCurrentIndex()
            if currentBookID == nil { currentBookID = books.first?.id }
            if books.isEmpty {
                restoreSamples()
            } else {
                // Persist once on load so any decode-time migration (legacy
                // single-book → multi-book, or SM-2 → FSRS seeding) is written
                // to disk in the current format.
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
                reviewLog: reviewLog,
                wordProgress: wordProgress,
                words: nil,
                currentIndex: nil
            )
            let data = try JSONEncoder.fastWords.encode(state)
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            importMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Harvest any per-book FSRS/status that's been reviewed into the global
    /// progress table. When a word appears in multiple books, keep the most-
    /// reviewed copy. Used to migrate pre-global-progress saved state.
    private func migrateBookProgressIntoGlobal() {
        for book in books {
            for entry in book.words {
                guard entry.fsrs.reps > 0 || entry.status == .mastered else { continue }
                let key = progressKey(entry.word)
                if let existing = wordProgress[key], existing.fsrs.reps >= entry.fsrs.reps {
                    continue // keep the more-reviewed copy
                }
                wordProgress[key] = WordProgress(fsrs: entry.fsrs, status: entry.status)
            }
        }
    }

    private func clampCurrentIndex() {
        guard let bookIndex = currentBookIndex else { return }
        let count = books[bookIndex].words.count
        books[bookIndex].currentIndex = max(0, min(books[bookIndex].currentIndex, max(count - 1, 0)))
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

    /// Record how well the current word was recalled, update its FSRS schedule
    /// and mastery status (in the shared global table), then advance.
    func grade(_ grade: ReviewGrade) {
        guard let word = currentWord else { return }
        let now = Date()
        let key = progressKey(word.word)
        let current = wordProgress[key]?.fsrs ?? word.fsrs
        let updated = FSRS.review(current, grade: grade, now: now, desiredRetention: settings.desiredRetention)
        // Mastery follows the FSRS schedule; shared across all books with this word.
        wordProgress[key] = WordProgress(fsrs: updated, status: FSRS.masteryStatus(for: updated))
        // Record one review for today's heatmap.
        reviewLog[ReviewStats.dayKey(for: now), default: 0] += 1
        showNext() // showNext() saves
    }

    func toggleMastered() {
        guard let word = currentWord else { return }
        let key = progressKey(word.word)
        let p = wordProgress[key] ?? WordProgress(fsrs: word.fsrs, status: word.status)
        let nextStatus: WordStatus = p.status == .mastered ? .learning : .mastered
        wordProgress[key] = WordProgress(fsrs: p.fsrs, status: nextStatus)
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

    /// Load a built-in exam word book (考研/托福/雅思/…). If the book already
    /// exists, refresh its word list & order from the current dictionary
    /// (e.g. to pick up frequency ordering) — progress is global, so this is
    /// lossless — and switch to it. Otherwise create it.
    func loadExamBook(_ category: ExamCategory) {
        let entries = OfflineDictionary.shared.words(for: category)
        guard !entries.isEmpty else {
            importMessage = "未找到 \(category.title) 词库。"
            return
        }

        if let index = books.firstIndex(where: { $0.source == .exam(category) }) {
            // Re-sync words/order from the latest dictionary; progress lives in
            // the shared global table, so refreshing the list loses nothing.
            books[index].words = entries
            books[index].currentIndex = 0
            currentBookID = books[index].id
            importMessage = "已更新《\(category.title)》词序（进度已保留）。"
        } else {
            let book = WordBook(name: category.title, source: .exam(category), words: entries)
            books.append(book)
            currentBookID = book.id
            importMessage = "已加载《\(category.title)》：\(entries.count) 个单词。"
        }
        aiState = .idle
        lookupState = .idle
        save()
    }

    func showImportError(_ message: String) {
        importMessage = message
    }

    /// Fill in blank fields (English definition, Chinese meaning, phonetic) for
    /// every word in the current book from the bundled offline dictionary.
    /// Useful for books loaded before a field existed (e.g. English definitions).
    @discardableResult
    func enrichCurrentBookFromOffline() -> Int {
        guard let bookIndex = currentBookIndex else { return 0 }
        let dict = OfflineDictionary.shared
        var enriched = 0

        for i in books[bookIndex].words.indices {
            var word = books[bookIndex].words[i]
            let needsSomething = word.englishDefinition.isEmpty || word.meaning.isEmpty || word.phonetic.isEmpty
            guard needsSomething, let entry = dict.entry(for: word.word) else { continue }

            var changed = false
            if word.englishDefinition.isEmpty, !entry.englishDefinition.isEmpty {
                word.englishDefinition = entry.englishDefinition; changed = true
            }
            if word.meaning.isEmpty, !entry.translation.isEmpty {
                word.meaning = entry.translation; changed = true
            }
            if word.phonetic.isEmpty, !entry.phonetic.isEmpty {
                word.phonetic = entry.phonetic
                if word.phoneticUK.isEmpty { word.phoneticUK = entry.phonetic }
                changed = true
            }
            if changed {
                books[bookIndex].words[i] = word
                enriched += 1
            }
        }

        if enriched > 0 {
            importMessage = "已为《\(books[bookIndex].name)》补全 \(enriched) 个单词的释义。"
            save()
        } else {
            importMessage = "本词书无需补全。"
        }
        return enriched
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
        if words[currentIndex].englishDefinition.isEmpty, !result.englishDefinition.isEmpty {
            words[currentIndex].englishDefinition = result.englishDefinition
            filled.append("english")
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
                case "english": return "英英释义"
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
