import Foundation

/// Pure formatting helpers for displaying dictionary meanings.
public enum MeaningFormatter {
    /// Split a leading part-of-speech token (e.g. "adv." / "vt.") off the meaning
    /// so it can be shown as a chip, matching the ECDICT translation format.
    ///
    /// Returns `(nil, original)` when the meaning has no recognizable POS prefix.
    public static func splitPartOfSpeech(_ meaning: String) -> (pos: String?, body: String) {
        let trimmed = meaning.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: ".") else { return (nil, trimmed) }
        let head = String(trimmed[trimmed.startIndex..<dot])
        // POS tokens are short and alphabetic (n, v, adj, adv, vt, vi, prep, conj…).
        guard !head.isEmpty, head.count <= 4, head.allSatisfy({ $0.isLetter }) else {
            return (nil, trimmed)
        }
        let rest = trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        return (head, rest)
    }

    /// Wrap a phonetic transcription in slashes for display, e.g. `ˈklaɪmət`
    /// or `/ˈklaɪmət/` → `/ˈklaɪmət/`. Returns "" for empty/whitespace input so
    /// callers can skip rendering.
    public static func formattedPhonetic(_ phonetic: String) -> String {
        var s = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip any existing wrapping slashes or brackets so we don't double them.
        while let first = s.first, first == "/" || first == "[" {
            s.removeFirst()
        }
        while let last = s.last, last == "/" || last == "]" {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }
        return "/\(s)/"
    }
}
