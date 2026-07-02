import Foundation

/// Per-word spaced-repetition state, following the legacy SM-2 algorithm.
/// Kept only for backward-compatible decoding and migration to FSRS.
public struct SRSState: Codable, Equatable, Sendable {
    public var easeFactor: Double
    public var intervalDays: Int
    public var repetitions: Int
    public var dueDate: Date
    public var lastReviewedAt: Date?

    public static let minimumEaseFactor = 1.3
    public static let defaultEaseFactor = 2.5

    public init(
        easeFactor: Double = SRSState.defaultEaseFactor,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        dueDate: Date = .distantPast,
        lastReviewedAt: Date? = nil
    ) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
    }
}
