import Foundation

public enum ReviewScheduler {
    public static func nextIndex(currentIndex: Int, wordCount: Int, mode: ReviewMode) -> Int {
        guard wordCount > 0 else { return 0 }

        switch mode {
        case .sequential:
            return (currentIndex + 1) % wordCount
        case .random:
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
}
