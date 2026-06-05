import Foundation

/// Built-in exam vocabulary categories, matching ECDICT `tag` codes.
public enum ExamCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case zk
    case gk
    case cet4
    case cet6
    case ky
    case toefl
    case ielts
    case gre

    public var id: String { rawValue }

    /// Human-facing name (Chinese, since the audience is Chinese learners).
    public var title: String {
        switch self {
        case .zk:
            "中考"
        case .gk:
            "高考"
        case .cet4:
            "四级 CET-4"
        case .cet6:
            "六级 CET-6"
        case .ky:
            "考研"
        case .toefl:
            "托福 TOEFL"
        case .ielts:
            "雅思 IELTS"
        case .gre:
            "GRE"
        }
    }
}

/// A single entry parsed from the bundled ECDICT exam dictionary.
public struct OfflineDictionaryEntry: Equatable, Sendable {
    public var word: String
    public var phonetic: String
    public var translation: String
    /// English (English-to-English) definition, when available.
    public var englishDefinition: String
    public var tags: Set<ExamCategory>
}

/// Offline English→Chinese dictionary backed by the bundled ECDICT subset
/// (~15k exam-tagged words, MIT-licensed data). Loads lazily on first use.
///
/// Provides both single-word lookup (for filling in Chinese meanings) and
/// tag-based filtering (for building exam word books).
public final class OfflineDictionary: DictionaryService, @unchecked Sendable {
    public static let shared = OfflineDictionary()

    private let lock = NSLock()
    private var loaded = false
    private var byWord: [String: OfflineDictionaryEntry] = [:]
    private var allEntries: [OfflineDictionaryEntry] = []
    private let bundle: Bundle
    private let resourceName: String

    public init() {
        self.bundle = .module
        self.resourceName = "ecdict_exam"
    }

    /// Test/seam initializer with an explicit bundle and resource name.
    init(bundle: Bundle, resourceName: String) {
        self.bundle = bundle
        self.resourceName = resourceName
    }

    // MARK: - DictionaryService

    public func lookup(_ word: String) async throws -> DictionaryResult {
        let key = OfflineDictionary.normalize(word)
        guard !key.isEmpty else { throw DictionaryError.notFound }
        ensureLoaded()

        guard let entry = withLock({ byWord[key] }) else { throw DictionaryError.notFound }
        return DictionaryResult(
            phonetic: entry.phonetic,
            meaning: entry.translation,
            englishDefinition: entry.englishDefinition,
            example: "",
            audioURL: nil
        )
    }

    /// Synchronous entry lookup (case-insensitive). Returns nil if not found.
    public func entry(for word: String) -> OfflineDictionaryEntry? {
        let key = OfflineDictionary.normalize(word)
        guard !key.isEmpty else { return nil }
        ensureLoaded()
        return withLock { byWord[key] }
    }

    // MARK: - Exam word books

    /// All words tagged with the given exam category, as ready-to-review entries.
    public func words(for category: ExamCategory) -> [WordEntry] {
        ensureLoaded()
        let matches = withLock { allEntries.filter { $0.tags.contains(category) } }
        return matches.map { entry in
            WordEntry(
                word: entry.word,
                phonetic: entry.phonetic,
                phoneticUK: entry.phonetic, // ECDICT phonetics are UK-based
                meaning: entry.translation,
                englishDefinition: entry.englishDefinition
            )
        }
    }

    /// Number of words available for each exam category (for settings UI).
    public func counts() -> [ExamCategory: Int] {
        ensureLoaded()
        return withLock {
            var result: [ExamCategory: Int] = [:]
            for entry in allEntries {
                for tag in entry.tags {
                    result[tag, default: 0] += 1
                }
            }
            return result
        }
    }

    // MARK: - Loading & parsing

    static func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func ensureLoaded() {
        if withLock({ loaded }) { return }

        let entries = Self.loadEntries(bundle: bundle, resourceName: resourceName)
        var index: [String: OfflineDictionaryEntry] = [:]
        index.reserveCapacity(entries.count)
        for entry in entries {
            index[Self.normalize(entry.word)] = entry
        }

        withLock {
            if !loaded {
                allEntries = entries
                byWord = index
                loaded = true
            }
        }
    }

    /// Load and parse the bundled TSV. Each line: word \t phonetic \t translation \t tag.
    static func loadEntries(bundle: Bundle, resourceName: String) -> [OfflineDictionaryEntry] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        return parse(text)
    }

    /// Pure TSV parser, unit-testable without a bundle.
    static func parse(_ text: String) -> [OfflineDictionaryEntry] {
        var result: [OfflineDictionaryEntry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Fields: word \t phonetic \t 中文 \t 英英 \t tag
            let fields = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
            guard fields.count == 5 else { continue }
            let word = String(fields[0])
            guard !word.isEmpty else { continue }
            let tags = Set(fields[4].split(separator: " ").compactMap { ExamCategory(rawValue: String($0)) })
            result.append(
                OfflineDictionaryEntry(
                    word: word,
                    phonetic: String(fields[1]),
                    translation: String(fields[2]),
                    englishDefinition: String(fields[3]),
                    tags: tags
                )
            )
        }
        return result
    }
}
