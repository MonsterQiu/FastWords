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
        case "txt":
            return try importTXT(String(decoding: data, as: UTF8.self))
        case "csv":
            return try importCSV(String(decoding: data, as: UTF8.self))
        case "json":
            return try importJSON(data)
        default:
            throw WordBookImportError.unsupportedFileType
        }
    }

    public static func importTXT(_ text: String) throws -> [WordEntry] {
        let entries = text
            .components(separatedBy: .newlines)
            .compactMap { line -> WordEntry? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

                let parts = splitPlainTextLine(trimmed)
                guard let word = parts.first?.trimmedNonEmpty else { return nil }

                return WordEntry(
                    word: word,
                    phonetic: parts[safe: 1]?.trimmedNonEmpty ?? "",
                    meaning: parts[safe: 2]?.trimmedNonEmpty ?? parts[safe: 1]?.trimmedNonEmpty ?? "",
                    example: parts[safe: 3]?.trimmedNonEmpty ?? ""
                )
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
        let hasHeader = header.contains("word") || header.contains("单词")

        let wordIndex = hasHeader ? firstIndex(in: header, matching: ["word", "单词"]) : 0
        let phoneticIndex = hasHeader ? firstIndex(in: header, matching: ["phonetic", "音标"]) : 1
        let meaningIndex = hasHeader ? firstIndex(in: header, matching: ["meaning", "definition", "释义", "中文"]) : 2
        let exampleIndex = hasHeader ? firstIndex(in: header, matching: ["example", "sentence", "例句"]) : 3
        let noteIndex = hasHeader ? firstIndex(in: header, matching: ["note", "notes", "备注"]) : nil

        if hasHeader {
            rows.removeFirst()
        }

        let entries = rows.compactMap { row -> WordEntry? in
            guard let word = value(in: row, at: wordIndex)?.trimmedNonEmpty else { return nil }

            return WordEntry(
                word: word,
                phonetic: value(in: row, at: phoneticIndex)?.trimmedNonEmpty ?? "",
                meaning: value(in: row, at: meaningIndex)?.trimmedNonEmpty ?? "",
                example: value(in: row, at: exampleIndex)?.trimmedNonEmpty ?? "",
                note: value(in: row, at: noteIndex)?.trimmedNonEmpty ?? ""
            )
        }

        guard !entries.isEmpty else { throw WordBookImportError.emptyWordBook }
        return entries
    }

    public static func importJSON(_ data: Data) throws -> [WordEntry] {
        do {
            let words = try JSONDecoder().decode([JSONWord].self, from: data)
            let entries = words.compactMap { item -> WordEntry? in
                guard let word = item.word.trimmedNonEmpty else { return nil }
                return WordEntry(
                    word: word,
                    phonetic: item.phonetic?.trimmedNonEmpty ?? "",
                    meaning: item.meaning?.trimmedNonEmpty ?? "",
                    example: item.example?.trimmedNonEmpty ?? "",
                    note: item.note?.trimmedNonEmpty ?? ""
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

    private static func normalizedHeader(_ row: [String]) -> [String] {
        row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    private static func firstIndex(in header: [String], matching names: [String]) -> Int? {
        header.firstIndex { names.contains($0) }
    }

    private static func value(in row: [String], at index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        return row[index]
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
