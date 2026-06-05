import Foundation

/// Per-word FSRS-6 memory state. A fresh card (`reps == 0`) is due immediately.
public struct FSRSState: Codable, Equatable, Sendable {
    /// Memory stability in days (interval at which recall drops to ~90%).
    public var stability: Double
    /// Difficulty, 1…10.
    public var difficulty: Double
    /// Number of reviews so far.
    public var reps: Int
    /// Number of lapses (Again) so far.
    public var lapses: Int
    /// When the card was last reviewed, if ever.
    public var lastReview: Date?
    /// When the card next becomes due.
    public var dueDate: Date

    public init(
        stability: Double = 0,
        difficulty: Double = 0,
        reps: Int = 0,
        lapses: Int = 0,
        lastReview: Date? = nil,
        dueDate: Date = .distantPast
    ) {
        self.stability = stability
        self.difficulty = difficulty
        self.reps = reps
        self.lapses = lapses
        self.lastReview = lastReview
        self.dueDate = dueDate
    }

    public func isDue(asOf now: Date) -> Bool {
        dueDate <= now
    }
}
