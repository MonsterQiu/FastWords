import Combine
import Foundation
import FastWordsCore

@MainActor
final class WordStore: ObservableObject {
    struct PersistedState: Codable {
        // Increment when persisted settings/data need a one-time migration.
        var schemaVersion: Int?

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

    /// Pending search result awaiting "加入词书" / "仅本次查看".
    struct PendingSearch: Equatable {
        var entry: WordEntry
        var sourceLabel: String
    }

    /// Why a search could not produce a card — drives the failure panel copy & actions.
    enum SearchMissReason: Equatable {
        /// Dictionary missed; local spelling candidates available (AI not tried yet).
        case spellingSuggestions
        /// Dictionary + AI both unusable or empty; not a real word.
        case notAValidWord
        /// Dictionary missed and AI is turned off.
        case aiDisabled
        /// Dictionary missed and AI base URL / key / model missing.
        case aiNotConfigured
        /// Dictionary missed and AI/network failed.
        case lookupFailed(String)
    }

    /// Final or intermediate "no exact hit" panel for the search funnel.
    struct SearchMiss: Equatable {
        var query: String
        var reason: SearchMissReason
        var suggestions: [String]
        /// When true, user can press "仍用 AI 查询" (spelling step only).
        var canContinueWithAI: Bool
    }

    /// Import file parsed but not yet committed.
    struct ImportPreview: Equatable {
        var entries: [WordEntry]
        var sourceName: String
        var added: Int
        var skipped: Int
    }

    /// Snapshot used to undo the last grade action.
    private struct GradeUndoSnapshot {
        var wordKey: String
        var previousProgress: WordProgress?
        var bookID: UUID
        var previousIndex: Int
        var dayKey: String
        var previousDayCount: Int
    }

    @Published private(set) var books: [WordBook] = []
    @Published private(set) var currentBookID: UUID?
    /// Daily review counts for the stats heatmap (yyyy-MM-dd → count).
    @Published private(set) var reviewLog: [String: Int] = [:]
    /// Global per-word progress (key = lowercased word). The single source of
    /// truth for FSRS state & mastery, shared across every book.
    @Published private(set) var wordProgress: [String: WordProgress] = [:]
    @Published var settings = AppSettings() {
        didSet {
            guard !isLoading else { return }
            KeychainHelper.saveAPIKey(settings.aiAPIKey)
            save()
        }
    }
    @Published private(set) var aiState: AIState = .idle
    @Published private(set) var lookupState: LookupState = .idle
    @Published private(set) var importMessage: String?
    /// Temporary one-shot card from search ("仅本次查看") — not in any book.
    @Published private(set) var temporaryPreview: WordEntry?
    /// Dictionary/AI hit not yet in a book — user chooses add vs peek.
    @Published private(set) var pendingSearch: PendingSearch?
    /// Search funnel miss: spelling suggestions or terminal failure.
    @Published private(set) var searchMiss: SearchMiss?
    /// Drag/import confirmation sheet data.
    @Published private(set) var importPreview: ImportPreview?
    @Published private(set) var canUndoGrade = false

    private var gradeUndo: GradeUndoSnapshot?

    /// Persisted-state schema written by this build.
    private static let currentSchemaVersion = 2

    /// Version where all card content blocks became enabled by default for
    /// existing installs too. Missing version means pre-migration state.
    private static let allContentEnabledSchemaVersion = 2

    /// Suppresses the `settings` didSet auto-save while `load()` is populating
    /// state, so a half-loaded store is never persisted (which previously wiped
    /// legacy word data during migration).
    private var isLoading = false

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    /// Directory where downloaded pronunciation clips are cached.
    var audioDirectory: URL { directory.appendingPathComponent("audio", isDirectory: true) }

    /// The base directory, dynamically resolved so toggling iCloud updates it.
    private var directory: URL { iCloudSyncService.activeDirectory }

    init() {
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
        if let preview = temporaryPreview { return preview }
        guard words.indices.contains(currentIndex) else { return nil }
        return words[currentIndex]
    }

    /// True when the card is a transient search peek (not part of a book).
    var isShowingTemporaryPreview: Bool { temporaryPreview != nil }

    var masteredCount: Int {
        words.filter { $0.status == .mastered }.count
    }

    /// Learning words in the current book whose FSRS due date is today or earlier.
    var dueTodayCount: Int {
        let now = Date()
        return words.reduce(0) { count, entry in
            guard entry.status != .mastered else { return count }
            return entry.fsrs.isDue(asOf: now) ? count + 1 : count
        }
    }

    var progressText: String {
        guard !words.isEmpty else { return "No words" }
        let due = dueTodayCount
        if due > 0 {
            return "\(currentIndex + 1)/\(words.count) · 今日\(due) · \(masteredCount) mastered"
        }
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
        clearEphemeralCardState()
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

    /// Remove **one** word from the current book (not the whole book).
    /// - Temporary search peeks are dismissed without writing.
    /// - Shared `wordProgress` is kept if the same word still exists in another book;
    ///   otherwise the progress entry is removed too.
    @discardableResult
    func deleteCurrentWord() -> Bool {
        // Peek-only card: just dismiss.
        if temporaryPreview != nil {
            let name = temporaryPreview?.word ?? ""
            temporaryPreview = nil
            importMessage = name.isEmpty ? "已关闭预览" : "已关闭「\(name)」的预览（未写入词书）"
            return true
        }

        guard let bookIndex = currentBookIndex else { return false }
        let idx = books[bookIndex].currentIndex
        guard books[bookIndex].words.indices.contains(idx) else { return false }

        let removed = books[bookIndex].words.remove(at: idx)
        let key = progressKey(removed.word)
        let bookName = books[bookIndex].name

        // Keep the card position stable: land on the next word, or the previous if we
        // deleted the last one.
        let count = books[bookIndex].words.count
        books[bookIndex].currentIndex = count == 0 ? 0 : min(idx, count - 1)

        // Drop global progress only when no loaded book still contains this word.
        let stillInSomeBook = books.contains { book in
            book.words.contains { progressKey($0.word) == key }
        }
        if !stillInSomeBook {
            wordProgress.removeValue(forKey: key)
        }

        // Undo snapshot may point at the deleted card — invalidate.
        gradeUndo = nil
        canUndoGrade = false
        clearEphemeralCardState()
        aiState = .idle
        lookupState = .idle
        importMessage = "已从《\(bookName)》删除 \(removed.word)"
        save()
        return true
    }

    func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: stateURL)
            let decoded = try JSONDecoder.fastWords.decode(PersistedState.self, from: data)
            settings = decoded.settings
            migrateSettingsIfNeeded(from: decoded.schemaVersion)
            migrateAPIKeyToKeychain()
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


    /// One-time settings migrations for existing users. In schema v2 we made
    /// FastWords show all card content out of the box, including users who had
    /// a pre-v2 state file where newly-added toggles decoded to older defaults.
    private func migrateSettingsIfNeeded(from schemaVersion: Int?) {
        let version = schemaVersion ?? 0
        guard version < Self.allContentEnabledSchemaVersion else { return }

        settings.showChinese = true
        settings.showEnglish = true
        settings.showPhonetic = true
        settings.showExample = true
        settings.showAIHint = true
        settings.showShortcutHint = true
    }

    /// Move a plaintext API key out of settings into the Keychain (one-time),
    /// then always rehydrate the in-memory key from Keychain.
    private func migrateAPIKeyToKeychain() {
        let fromJSON = settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromJSON.isEmpty {
            KeychainHelper.saveAPIKey(fromJSON)
            settings.aiAPIKey = "" // strip before any subsequent save
        }
        let fromKeychain = KeychainHelper.loadAPIKey()
        if !fromKeychain.isEmpty {
            settings.aiAPIKey = fromKeychain
        }
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Never write the API key into state.json.
            KeychainHelper.saveAPIKey(settings.aiAPIKey)
            let state = PersistedState(
                schemaVersion: Self.currentSchemaVersion,
                books: books,
                currentBookID: currentBookID,
                settings: settings.encodingWithoutAPIKey(),
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
        clearEphemeralCardState(clearPendingSearch: true)
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
        clearEphemeralCardState(clearPendingSearch: true)
        currentIndex = ReviewScheduler.previousIndex(currentIndex: currentIndex, wordCount: words.count)
        aiState = .idle
        save()
    }

    /// Record how well the current word was recalled, update its FSRS schedule
    /// and mastery status (in the shared global table), then advance.
    /// Temporary search previews cannot be graded (not in a book).
    func grade(_ grade: ReviewGrade) {
        guard temporaryPreview == nil else {
            importMessage = "预览词请先加入词书后再评分。"
            return
        }
        guard let word = currentWord, let bookID = currentBookID else { return }
        let now = Date()
        let key = progressKey(word.word)
        let day = ReviewStats.dayKey(for: now)
        let previousDayCount = reviewLog[day] ?? 0
        gradeUndo = GradeUndoSnapshot(
            wordKey: key,
            previousProgress: wordProgress[key],
            bookID: bookID,
            previousIndex: currentIndex,
            dayKey: day,
            previousDayCount: previousDayCount
        )
        canUndoGrade = true

        let current = wordProgress[key]?.fsrs ?? word.fsrs
        let updated = FSRS.review(current, grade: grade, now: now, desiredRetention: settings.desiredRetention)
        // Mastery follows the FSRS schedule; shared across all books with this word.
        wordProgress[key] = WordProgress(fsrs: updated, status: FSRS.masteryStatus(for: updated))
        // Record one review for today's heatmap.
        reviewLog[day, default: 0] += 1
        showNext() // showNext() saves
    }

    /// Undo the last `grade(_:)` — restores FSRS progress, position, and heatmap count.
    @discardableResult
    func undoLastGrade() -> Bool {
        guard let snap = gradeUndo else { return false }
        if let prev = snap.previousProgress {
            wordProgress[snap.wordKey] = prev
        } else {
            wordProgress.removeValue(forKey: snap.wordKey)
        }
        if snap.previousDayCount == 0 {
            reviewLog.removeValue(forKey: snap.dayKey)
        } else {
            reviewLog[snap.dayKey] = snap.previousDayCount
        }
        if books.contains(where: { $0.id == snap.bookID }) {
            currentBookID = snap.bookID
            if let bookIndex = books.firstIndex(where: { $0.id == snap.bookID }) {
                let count = books[bookIndex].words.count
                books[bookIndex].currentIndex = max(0, min(snap.previousIndex, max(count - 1, 0)))
            }
        }
        gradeUndo = nil
        canUndoGrade = false
        clearEphemeralCardState()
        importMessage = "已撤销上一次评分"
        save()
        return true
    }

    func toggleMastered() {
        guard temporaryPreview == nil, let word = currentWord else { return }
        let key = progressKey(word.word)
        let p = wordProgress[key] ?? WordProgress(fsrs: word.fsrs, status: word.status)
        let nextStatus: WordStatus = p.status == .mastered ? .learning : .mastered
        wordProgress[key] = WordProgress(fsrs: p.fsrs, status: nextStatus)
        save()
    }

    /// Compute merge stats without writing — used for the import confirmation UI.
    func previewImport(_ entries: [WordEntry], sourceName: String) {
        guard !entries.isEmpty else {
            importMessage = "没有可导入的单词。"
            importPreview = nil
            return
        }
        if let book = currentBook {
            var existing = Set(book.words.map { $0.word.lowercased() })
            var added = 0
            var skipped = 0
            for entry in entries {
                let key = entry.word.lowercased()
                if existing.contains(key) {
                    skipped += 1
                } else {
                    existing.insert(key)
                    added += 1
                }
            }
            importPreview = ImportPreview(entries: entries, sourceName: sourceName, added: added, skipped: skipped)
        } else {
            importPreview = ImportPreview(entries: entries, sourceName: sourceName, added: entries.count, skipped: 0)
        }
        importMessage = nil
    }

    func confirmImportPreview() {
        guard let preview = importPreview else { return }
        importPreview = nil
        importEntries(preview.entries, sourceName: preview.sourceName)
    }

    func cancelImportPreview() {
        importPreview = nil
        importMessage = "已取消导入"
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
                englishDefinition: "To leave behind or give up completely.",
                example: "Do not abandon the tiny habit after one hard day."
            ),
            WordEntry(
                word: "brisk",
                phonetic: "/brɪsk/",
                meaning: "轻快的；生气勃勃的",
                englishDefinition: "Quick, energetic, and active.",
                example: "A brisk walk can wake up a sleepy brain."
            ),
            WordEntry(
                word: "clarity",
                phonetic: "/ˈklærəti/",
                meaning: "清晰；明确",
                englishDefinition: "The quality of being clear and easy to understand.",
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

    // MARK: - Word search

    /// Prefix suggestions: current book first, then offline dictionary.
    func searchSuggestions(for query: String, limit: Int = 8) -> [String] {
        let key = progressKey(query)
        guard key.count >= 1 else { return [] }

        var seen = Set<String>()
        var results: [String] = []

        for entry in words {
            let w = entry.word
            let nk = progressKey(w)
            guard nk.hasPrefix(key), !seen.contains(nk) else { continue }
            seen.insert(nk)
            results.append(w)
            if results.count >= limit { return results }
        }

        for suggestion in OfflineDictionary.shared.suggestions(matching: key, limit: limit) {
            let nk = progressKey(suggestion)
            guard !seen.contains(nk) else { continue }
            seen.insert(nk)
            results.append(suggestion)
            if results.count >= limit { break }
        }
        return results
    }

    /// Jump to `query` if it already exists in any loaded book (case-insensitive).
    /// Prefers the current book; otherwise switches to the first book that has it.
    /// Never shows the “add to book” prompt — the word is already collected.
    @discardableResult
    func jumpToWord(_ query: String, announce: Bool = false) -> Bool {
        let key = progressKey(query)
        guard !key.isEmpty else { return false }

        // Current book first — keeps the user in their active list.
        if let index = words.firstIndex(where: { progressKey($0.word) == key }) {
            temporaryPreview = nil
            pendingSearch = nil
            searchMiss = nil
            currentIndex = index
            aiState = .idle
            lookupState = .idle
            importMessage = announce ? "已在当前词书中，已跳转到 \(words[index].word)" : nil
            save()
            return true
        }

        // Other books: switch and land on the match.
        for bookIndex in books.indices {
            if books[bookIndex].id == currentBookID { continue }
            if let wordIndex = books[bookIndex].words.firstIndex(where: { progressKey($0.word) == key }) {
                let found = books[bookIndex].words[wordIndex].word
                temporaryPreview = nil
                pendingSearch = nil
                searchMiss = nil
                currentBookID = books[bookIndex].id
                books[bookIndex].currentIndex = wordIndex
                aiState = .idle
                lookupState = .idle
                importMessage = "已在《\(books[bookIndex].name)》中，已跳转到 \(found)"
                save()
                return true
            }
        }
        return false
    }

    /// Build a card entry from a dictionary/AI result and park it as pending
    /// confirmation (join book vs peek once). Does not auto-append to the book.
    /// If the word is already in a book, jumps there instead of asking to add.
    func presentPendingSearch(word: String, result: DictionaryResult, sourceLabel: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchMiss = nil

        // Belt-and-suspenders: never ask to add a word that is already collected.
        if jumpToWord(trimmed, announce: true) {
            return
        }

        let key = progressKey(trimmed)
        var entry = WordEntry(
            word: trimmed,
            phonetic: result.phonetic,
            phoneticUK: result.phonetic,
            meaning: result.meaning,
            englishDefinition: result.englishDefinition,
            example: result.example
        )
        if let p = wordProgress[key] {
            entry.fsrs = p.fsrs
            entry.status = p.status
        }

        temporaryPreview = nil
        pendingSearch = PendingSearch(entry: entry, sourceLabel: sourceLabel)
        lookupState = .idle
        importMessage = "\(sourceLabel)：选择加入词书或仅本次查看"
    }

    /// Commit the pending search result into the current book and jump to it.
    func confirmPendingSearchAdd() {
        guard let pending = pendingSearch else { return }
        pendingSearch = nil
        presentLookupWord(
            pending.entry.word,
            result: DictionaryResult(
                phonetic: pending.entry.phonetic,
                meaning: pending.entry.meaning,
                englishDefinition: pending.entry.englishDefinition,
                example: pending.entry.example
            ),
            sourceNote: "已加入当前词书"
        )
    }

    /// Show the pending search result without adding it to any book.
    func confirmPendingSearchPeek() {
        guard let pending = pendingSearch else { return }
        temporaryPreview = pending.entry
        pendingSearch = nil
        lookupState = .idle
        importMessage = "仅本次查看（翻页后消失，不会写入词书）"
    }

    func dismissPendingSearch() {
        pendingSearch = nil
        if lookupState == .loading { return }
        lookupState = .idle
    }

    func clearTemporaryPreview() {
        temporaryPreview = nil
    }

    private func clearEphemeralCardState(clearPendingSearch: Bool = true) {
        temporaryPreview = nil
        searchMiss = nil
        if clearPendingSearch { pendingSearch = nil }
    }

    // MARK: - Search miss funnel

    func presentSearchMiss(_ miss: SearchMiss) {
        temporaryPreview = nil
        pendingSearch = nil
        searchMiss = miss
        lookupState = .idle
        importMessage = nil
    }

    func dismissSearchMiss() {
        searchMiss = nil
        lookupState = .idle
    }

    /// Local spelling candidates for a headword (current book + ECDICT).
    func spellingSuggestions(for headword: String, limit: Int = 5) -> [String] {
        let extras = words.map(\.word)
        return OfflineDictionary.shared.spellingCorrections(
            for: headword,
            extraWords: extras,
            limit: limit
        )
    }

    /// Offer a blank card for a headword (e.g. proper noun / deliberate typo study).
    /// Does **not** write to the book yet — parks a pending confirmation so the user
    /// can still pick「加入词书 / 仅本次查看 / 取消」, same as a dictionary hit.
    func presentBlankPending(word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Already collected → jump; never create a second blank copy.
        if jumpToWord(trimmed, announce: true) {
            return
        }
        presentPendingSearch(
            word: trimmed,
            result: DictionaryResult(),
            sourceLabel: "空白卡片（暂无释义，确认后才写入词书）"
        )
    }

    /// Insert (or merge) a looked-up word into the current book, fill fields from
    /// `result`, and make it the current card. Used after user confirms add.
    func presentLookupWord(_ word: String, result: DictionaryResult, sourceNote: String? = nil) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        temporaryPreview = nil
        pendingSearch = nil

        // Ensure we have a book to land in.
        if currentBookIndex == nil {
            if books.isEmpty {
                restoreSamples()
            } else {
                currentBookID = books.first?.id
            }
        }
        guard let bookIndex = currentBookIndex else { return }

        let key = progressKey(trimmed)
        if let existing = books[bookIndex].words.firstIndex(where: { progressKey($0.word) == key }) {
            books[bookIndex].currentIndex = existing
            applyLookup(result)
            if let sourceNote {
                importMessage = sourceNote
            }
            return
        }

        var entry = WordEntry(
            word: trimmed,
            phonetic: result.phonetic,
            phoneticUK: result.phonetic,
            meaning: result.meaning,
            englishDefinition: result.englishDefinition,
            example: result.example
        )
        // Overlay shared progress if this word was studied in another book.
        if let p = wordProgress[key] {
            entry.fsrs = p.fsrs
            entry.status = p.status
        }

        books[bookIndex].words.append(entry)
        books[bookIndex].currentIndex = books[bookIndex].words.count - 1
        aiState = .idle
        lookupState = .idle
        importMessage = sourceNote ?? "已加入《\(books[bookIndex].name)》"
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
