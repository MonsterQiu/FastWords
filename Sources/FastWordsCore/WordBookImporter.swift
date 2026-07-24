import Foundation

public enum WordBookImportError: Error, LocalizedError, Equatable {
    case unsupportedFileType
    case emptyWordBook
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            "Unsupported word book file type."
        case .emptyWordBook:
            "The selected word book does not contain any words."
        case .invalidJSON:
            "The JSON word book could not be decoded."
        }
    }
}

/// Imports word lists from common plain-text / CSV / JSON exports.
///
/// Recognized formats (P1-6):
/// - Plain TXT / TSV (tab, `|`, or comma), including Anki “Notes in Plain Text” tabs
/// - CSV with headers from Anki / 欧路 / 不背单词 / generic English
/// - JSON array of `{ word, phonetic?, meaning?, example?, note? }`
public enum WordBookImporter {
    private struct JSONWord: Decodable {
        var word: String
        var phonetic: String?
        var meaning: String?
        var example: String?
        var note: String?
    }

    public static func importEntries(from url: URL) throws -> [WordEntry] {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "txt", "tsv":
            return try importTXT(String(decoding: data, as: UTF8.self))
        case "csv":
            return try importCSV(String(decoding: data, as: UTF8.self))
        case "json":
            return try importJSON(data)
        default:
            // Some Anki exports use no extension or `.text`.
            if let text = String(data: data, encoding: .utf8),
               text.contains("\t") || text.contains(",") {
                return try importTXT(text)
            }
            throw WordBookImportError.unsupportedFileType
        }
    }

    public static func importTXT(_ text: String) throws -> [WordEntry] {
        let entries = text
            .components(separatedBy: .newlines)
            .compactMap { line -> WordEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                // Skip blanks, comments, and Anki metadata (`#separator:Tab`, `#html:true`).
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

                let parts = splitPlainTextLine(trimmed).map(sanitizeField)
                guard let word = parts.first?.trimmedNonEmpty else { return nil }

                return plainTextEntry(word: word, fields: parts)
            }

        guard !entries.isEmpty else { throw WordBookImportError.emptyWordBook }
        return entries
    }

    public static func importCSV(_ text: String) throws -> [WordEntry] {
        var rows = text
            .components(separatedBy: .newlines)
            .map(parseCSVLine)
            .filter { row in
                row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard !rows.isEmpty else { throw WordBookImportError.emptyWordBook }

        let header = normalizedHeader(rows[0])
        let hasHeader = looksLikeHeader(header)

        let wordIndex: Int? = hasHeader
            ? firstIndex(in: header, matching: Self.wordHeaderNames)
            : 0
        let phoneticIndex: Int? = hasHeader
            ? firstIndex(in: header, matching: Self.phoneticHeaderNames)
            : 1
        // meaningHeaderNames already includes Anki "back" / 背面 / 答案.
        let meaningIndex: Int? = hasHeader
            ? firstIndex(in: header, matching: Self.meaningHeaderNames)
            : 2
        let exampleIndex: Int? = hasHeader
            ? firstIndex(in: header, matching: Self.exampleHeaderNames)
            : 3
        let noteIndex: Int? = hasHeader
            ? firstIndex(in: header, matching: Self.noteHeaderNames)
            : nil

        if hasHeader {
            rows.removeFirst()
        }

        let entries = rows.compactMap { row -> WordEntry? in
            guard let word = value(in: row, at: wordIndex).map(sanitizeField)?.trimmedNonEmpty else {
                return nil
            }

            return WordEntry(
                word: word,
                phonetic: value(in: row, at: phoneticIndex).map(sanitizeField)?.trimmedNonEmpty ?? "",
                meaning: value(in: row, at: meaningIndex).map(sanitizeField)?.trimmedNonEmpty ?? "",
                example: value(in: row, at: exampleIndex).map(sanitizeField)?.trimmedNonEmpty ?? "",
                note: value(in: row, at: noteIndex).map(sanitizeField)?.trimmedNonEmpty ?? ""
            )
        }

        guard !entries.isEmpty else { throw WordBookImportError.emptyWordBook }
        return entries
    }

    public static func importJSON(_ data: Data) throws -> [WordEntry] {
        do {
            let words = try JSONDecoder().decode([JSONWord].self, from: data)
            let entries = words.compactMap { item -> WordEntry? in
                guard let word = sanitizeField(item.word).trimmedNonEmpty else { return nil }
                return WordEntry(
                    word: word,
                    phonetic: item.phonetic.map(sanitizeField)?.trimmedNonEmpty ?? "",
                    meaning: item.meaning.map(sanitizeField)?.trimmedNonEmpty ?? "",
                    example: item.example.map(sanitizeField)?.trimmedNonEmpty ?? "",
                    note: item.note.map(sanitizeField)?.trimmedNonEmpty ?? ""
                )
            }

            guard !entries.isEmpty else { throw WordBookImportError.emptyWordBook }
            return entries
        } catch let error as WordBookImportError {
            throw error
        } catch {
            throw WordBookImportError.invalidJSON
        }
    }

    // MARK: - Header aliases (Anki / 欧路 / 不背单词 / generic)

    /// Headword column names seen in common exports.
    static let wordHeaderNames = [
        "word", "单词", "词语", "vocabulary", "term", "front", "正面",
        "headword", "lemma", "英文", "英语", "en", "english"
    ]

    static let phoneticHeaderNames = [
        "phonetic", "音标", "pronunciation", "ipa", "uk", "us", "发音"
    ]

    static let meaningHeaderNames = [
        "meaning", "definition", "释义", "中文", "翻译", "解释", "译文",
        "translation", "chinese", "cn", "释义中文", "中文释义", "意思",
        "back", "背面", "答案", "definitions"
    ]

    static let exampleHeaderNames = [
        "example", "sentence", "例句", "例子", "example sentence", "样例"
    ]

    static let noteHeaderNames = [
        "note", "notes", "备注", "笔记", "注释", "tags", "tag", "标签"
    ]

    // MARK: - Parsing helpers

    static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if isQuoted, let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        isQuoted = false
                        if next == "," {
                            result.append(current)
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    isQuoted.toggle()
                }
            } else if character == "," && !isQuoted {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        result.append(current)
        return result
    }

    private static func splitPlainTextLine(_ line: String) -> [String] {
        if line.contains("\t") {
            return line.components(separatedBy: "\t")
        }

        if line.contains("|") {
            return line.components(separatedBy: "|")
        }

        if line.contains(",") {
            return parseCSVLine(line)
        }

        return [line]
    }

    private static func plainTextEntry(word: String, fields: [String]) -> WordEntry {
        if fields.count == 2 {
            // Anki / 欧路 two-column: word + meaning
            return WordEntry(
                word: word,
                meaning: fields[safe: 1]?.trimmedNonEmpty ?? ""
            )
        }

        return WordEntry(
            word: word,
            phonetic: fields[safe: 1]?.trimmedNonEmpty ?? "",
            meaning: fields[safe: 2]?.trimmedNonEmpty ?? "",
            example: fields[safe: 3]?.trimmedNonEmpty ?? ""
        )
    }

    private static func looksLikeHeader(_ header: [String]) -> Bool {
        let joined = Set(header)
        let markers = Set(
            wordHeaderNames + phoneticHeaderNames + meaningHeaderNames
                + exampleHeaderNames + noteHeaderNames
        )
        return !joined.isDisjoint(with: markers)
    }

    private static func normalizedHeader(_ row: [String]) -> [String] {
        row.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func firstIndex(in header: [String], matching names: [String]) -> Int? {
        let nameSet = Set(names.map { $0.lowercased() })
        return header.firstIndex { nameSet.contains($0) }
    }

    private static func value(in row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        return row[index]
    }

    /// Strip light HTML (Anki exports) and collapse whitespace.
    static func sanitizeField(_ raw: String) -> String {
        var s = raw
        if let br = try? NSRegularExpression(pattern: #"<br\s*/?>"#, options: .caseInsensitive) {
            s = br.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: " "
            )
        }
        if let tags = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: .caseInsensitive) {
            s = tags.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
        }
        s = s
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
