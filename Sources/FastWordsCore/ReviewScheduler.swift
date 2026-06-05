import Foundation

public enum ReviewScheduler {
    public static func nextIndex(currentIndex: Int, wordCount: Int, mode: ReviewMode) -> Int {
        guard wordCount > 0 else { return 0 }

        switch mode {
        case .sequential:
            return (currentIndex + 1) % wordCount
        case .random, .smart:
            // Smart mode needs word state; callers without it fall back to random.
            guard wordCount > 1 else { return 0 }

            var next = Int.random(in: 0..<wordCount)
            while next == currentIndex {
                next = Int.random(in: 0..<wordCount)
            }
            return next
        }
    }

    public static func previousIndex(currentIndex: Int, wordCount: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        return (currentIndex - 1 + wordCount) % wordCount
    }

    /// Choose the next word to show, honoring the review mode.
    ///
    /// In `.smart` mode the most-overdue word wins; if nothing is due yet, the
    /// word closest to being due is shown so review never stalls. We avoid
    /// repeating the current word when alternatives exist.
    public static func nextIndex(
        currentIndex: Int,
        words: [WordEntry],
        mode: ReviewMode,
        now: Date
    ) -> Int {
        let count = words.count
        guard count > 0 else { return 0 }

        switch mode {
        case .sequential, .random:
            return nextIndex(currentIndex: currentIndex, wordCount: count, mode: mode)
        case .smart:
            guard count > 1 else { return 0 }

            // Prefer learning words over mastered ones; within each group, the
            // most-overdue word wins. Comparing fields explicitly keeps the
            // ordering exact instead of collapsing it into one lossy Double.
            let candidates = words.indices.filter { $0 != currentIndex }
            let best = candidates.min { lhs, rhs in
                isHigherPriority(words[lhs], than: words[rhs])
            }
            return best ?? nextIndex(currentIndex: currentIndex, wordCount: count, mode: .random)
        }
    }

    /// Whether `lhs` should be shown before `rhs` in smart mode: learning words
    /// outrank mastered ones; within the same group, the more-overdue word wins.
    private static func isHigherPriority(_ lhs: WordEntry, than rhs: WordEntry) -> Bool {
        let lhsMastered = lhs.status == .mastered
        let rhsMastered = rhs.status == .mastered
        if lhsMastered != rhsMastered {
            return !lhsMastered // learning word comes first
        }
        return lhs.srs.dueDate < rhs.srs.dueDate // earlier due = more overdue = first
    }
}
