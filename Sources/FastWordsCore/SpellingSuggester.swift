import Foundation

/// Local spelling corrections against a word list (ECDICT keys + optional extras).
/// Used when a dictionary lookup misses — cheap, offline, no AI.
public enum SpellingSuggester {
    /// Max edit distance considered. Short queries stay stricter.
    public static func maxDistance(for query: String) -> Int {
        let n = query.count
        if n <= 3 { return 1 }
        if n <= 6 { return 2 }
        return 2
    }

    /// Ranked headword suggestions for `query` (case-insensitive).
    /// - Parameters:
    ///   - query: user headword (already normalized preferred)
    ///   - candidates: dictionary keys or display words (will be lowercased for compare)
    ///   - limit: max results
    public static func suggestions(
        for query: String,
        among candidates: [String],
        limit: Int = 5
    ) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2, limit > 0 else { return [] }

        let maxD = maxDistance(for: q)
        var scored: [(word: String, distance: Int, display: String)] = []
        scored.reserveCapacity(32)

        for raw in candidates {
            let display = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !display.isEmpty else { continue }
            let c = display.lowercased()
            if c == q { continue }

            // Cheap filters before full Levenshtein.
            let lenDiff = abs(c.count - q.count)
            guard lenDiff <= maxD else { continue }
            // Same first letter, or very short query with shared prefix of 1.
            if let q0 = q.first, let c0 = c.first, q0 != c0, !c.hasPrefix(String(q.prefix(2))) {
                // Allow first-letter typos only when distance budget is 1 and lengths close.
                if maxD < 2 || lenDiff > 1 { continue }
            }

            let d = levenshtein(q, c, maxDistance: maxD)
            guard d > 0, d <= maxD else { continue }
            scored.append((c, d, display))
        }

        // Prefer lower distance, then shorter words, then alpha.
        scored.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.word.count != $1.word.count { return $0.word.count < $1.word.count }
            return $0.word < $1.word
        }

        var seen = Set<String>()
        var result: [String] = []
        for item in scored {
            guard !seen.contains(item.word) else { continue }
            seen.insert(item.word)
            result.append(item.display)
            if result.count >= limit { break }
        }
        return result
    }

    /// Bounded Levenshtein — returns `maxDistance + 1` when exceeded (early exit).
    public static func levenshtein(_ a: String, _ b: String, maxDistance: Int) -> Int {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count
        if abs(n - m) > maxDistance { return maxDistance + 1 }
        if n == 0 { return m }
        if m == 0 { return n }

        // Two-row DP.
        var prev = Array(0...m)
        var curr = Array(repeating: 0, count: m + 1)

        for i in 1...n {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
                rowMin = min(rowMin, curr[j])
            }
            if rowMin > maxDistance { return maxDistance + 1 }
            prev = curr
        }
        return prev[m]
    }
}
