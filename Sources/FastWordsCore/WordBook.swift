import Foundation

/// Where a word book came from — used for naming, dedup, and exam-book reuse.
public enum WordBookSource: Codable, Equatable, Sendable {
    case samples
    case imported(String)        // file name
    case exam(ExamCategory)
}

/// A named collection of words with its own review position and SRS progress.
/// Switching books preserves each book's progress independently.
public struct WordBook: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var source: WordBookSource
    public var words: [WordEntry]
    public var currentIndex: Int

    public init(
        id: UUID = UUID(),
        name: String,
        source: WordBookSource,
        words: [WordEntry],
        currentIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.words = words
        self.currentIndex = currentIndex
    }

    public var masteredCount: Int {
        words.filter { $0.status == .mastered }.count
    }

    /// Merge incoming entries into this book: append genuinely new words
    /// (matched case-insensitively by `word`) and leave existing words — and
    /// their SRS progress — untouched. Returns how many were added vs skipped.
    @discardableResult
    public mutating func merge(_ incoming: [WordEntry]) -> (added: Int, skipped: Int) {
        var existing = Set(words.map { $0.word.lowercased() })
        var added = 0
        var skipped = 0
        for entry in incoming {
            let key = entry.word.lowercased()
            if existing.contains(key) {
                skipped += 1
            } else {
                words.append(entry)
                existing.insert(key)
                added += 1
            }
        }
        return (added, skipped)
    }
}
