import Foundation

/// Turns casual search queries into a dictionary headword.
///
/// Examples:
/// - `"diversity 什么意思"` → `"diversity"`
/// - `"diversity是什么意思"` → `"diversity"`
/// - `"what does abandon mean"` → `"abandon"`
/// - `"look up"` → `"look up"` (multi-word English kept)
/// - `"look up 什么意思"` → `"look up"`
/// - `"abandon"` → `"abandon"`
public enum SearchQueryNormalizer {
    /// Chinese wrappers often typed/pasted after (or before) the word.
    /// Longest first so "是什么意思" wins over "什么意思".
    private static let trailingWrappers: [String] = [
        "是什么意思", "什么意思啊", "什么意思呢", "什么意思呀", "什么意思",
        "的意思是什么", "的意思", "怎么读", "如何发音", "怎么拼",
        "释义", "翻译", "中文", "英文"
    ].sorted { $0.count > $1.count }

    private static let leadingWrappers: [String] = [
        "什么是", "请问", "查一下", "查询", "搜索", "搜一下"
    ].sorted { $0.count > $1.count }

    /// English phrasal wrappers: capture group 1 is the headword.
    private static let englishPatterns: [NSRegularExpression] = {
        let patterns = [
            #"(?i)^what\s+does\s+(.+?)\s+mean\??$"#,
            #"(?i)^what'?s\s+the\s+meaning\s+of\s+(.+?)\??$"#,
            #"(?i)^meaning\s+of\s+(.+?)\??$"#,
            #"(?i)^define\s+(.+?)\??$"#,
            // Only treat "look up X" as a wrapper when X is present; bare "look up" is a phrase.
            #"(?i)^look\s+up\s+(.+)$"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Returns the best headword to look up / store.
    public static func headword(from query: String) -> String {
        let original = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return original }

        var s = original
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`「」『』《》【】()（）"))

        // 1) Strip Chinese wrappers first so "look up 什么意思" → "look up"
        //    and is not misread by the English "look up X" pattern.
        s = stripChineseWrappers(s)

        // 2) English "what does X mean" / "define X" / "look up X" (X must be English).
        s = applyEnglishPatterns(s)

        // 3) Strip wrappers again in case a pattern left residue.
        s = stripChineseWrappers(s)

        if isCleanEnglishPhrase(s) {
            return s
        }

        // 4) Extract Latin tokens from whatever remains (or from the original).
        let tokens = latinTokens(in: s.isEmpty ? original : s)
        if tokens.isEmpty {
            // No English at all — fall back to cleaned string or original.
            return s.isEmpty ? original : s
        }

        if let phrase = leadingEnglishPhrase(tokens: tokens, in: s.isEmpty ? original : s),
           phrase.contains(" ") {
            return phrase
        }
        return tokens.max(by: { $0.count < $1.count }) ?? tokens[0]
    }

    // MARK: - Steps

    private static func stripChineseWrappers(_ input: String) -> String {
        var s = input
        for w in trailingWrappers {
            if s.hasSuffix(w) {
                s = String(s.dropLast(w.count))
            }
        }
        for w in leadingWrappers {
            if s.hasPrefix(w) {
                s = String(s.dropFirst(w.count))
            }
        }
        return s.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "？?！!。.~—，,"))
        )
    }

    private static func applyEnglishPatterns(_ input: String) -> String {
        let full = NSRange(input.startIndex..., in: input)
        for re in englishPatterns {
            guard let match = re.firstMatch(in: input, range: full),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: input)
            else { continue }
            let captured = String(input[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Ignore captures that aren't English (e.g. residual CJK).
            if isCleanEnglishPhrase(captured) || !latinTokens(in: captured).isEmpty {
                return captured
            }
        }
        return input
    }

    // MARK: - Helpers

    /// Letters + spaces + hyphen + apostrophe only, and must contain an ASCII letter.
    private static func isCleanEnglishPhrase(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        let allowed = CharacterSet.letters
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-'"))
        guard s.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return s.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }
    }

    private static func latinTokens(in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z'\-]*"#) else {
            return []
        }
        let full = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, range: full).compactMap { match in
            guard let range = Range(match.range, in: s) else { return nil }
            return String(s[range])
        }
    }

    /// If `s` starts with consecutive English tokens from `tokens`, join them.
    private static func leadingEnglishPhrase(tokens: [String], in s: String) -> String? {
        guard let first = tokens.first else { return nil }
        let lower = s.lowercased()
        guard let start = lower.range(of: first.lowercased())?.lowerBound,
              start == lower.startIndex || s[s.startIndex..<start].allSatisfy(\.isWhitespace)
        else { return nil }

        var collected: [String] = []
        var cursor = start
        for token in tokens {
            let rest = s[cursor...]
            let trimmedStart = rest.drop(while: \.isWhitespace)
            guard trimmedStart.lowercased().hasPrefix(token.lowercased()) else { break }
            collected.append(token)
            let advance = rest.distance(from: rest.startIndex, to: trimmedStart.startIndex) + token.count
            cursor = s.index(cursor, offsetBy: advance)
        }
        guard !collected.isEmpty else { return nil }
        return collected.joined(separator: " ")
    }
}
