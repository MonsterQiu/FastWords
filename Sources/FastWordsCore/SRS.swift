import Foundation

/// How well the learner recalled a word during review.
///
/// Maps onto the SM-2 quality grades:
/// - `again` → forgot (quality < 3): reset the learning streak.
/// - `hard`  → recalled with serious difficulty.
/// - `good`  → recalled correctly.
public enum ReviewGrade: String, Codable, CaseIterable, Identifiable, Sendable {
    case again
    case hard
    case good

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .again:
            "不认识"
        case .hard:
            "模糊"
        case .good:
            "认识"
        }
    }

    /// SM-2 quality value (0...5). We use three representative points.
    var quality: Int {
        switch self {
        case .again:
            2
        case .hard:
            3
        case .good:
            5
        }
    }
}

/// Per-word spaced-repetition state, following the SM-2 algorithm.
///
/// A freshly initialized state models a brand-new card that is due immediately
/// (`dueDate == .distantPast`, `repetitions == 0`).
public struct SRSState: Codable, Equatable, Sendable {
    /// Ease factor; SM-2 keeps this at or above ``SRSState/minimumEaseFactor``.
    public var easeFactor: Double
    /// Current inter-repetition interval, in days.
    public var intervalDays: Int
    /// Number of consecutive successful reviews.
    public var repetitions: Int
    /// When the word next becomes due for review.
    public var dueDate: Date
    /// When the word was last reviewed, if ever.
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

    /// Whether this word is due for review at the given moment.
    public func isDue(asOf now: Date) -> Bool {
        dueDate <= now
    }
}

/// Pure SM-2 spaced-repetition functions. No I/O, fully unit-testable.
public enum SRS {
    /// Apply a review grade to a word's SRS state, returning the updated state.
    ///
    /// - Parameters:
    ///   - state: The word's current SRS state.
    ///   - grade: How well the learner recalled it.
    ///   - now: The review timestamp (injected for testability).
    public static func apply(_ grade: ReviewGrade, to state: SRSState, now: Date) -> SRSState {
        var result = state
        result.lastReviewedAt = now

        // Update ease factor per SM-2: EF' = EF + (0.1 - (5-q)*(0.08 + (5-q)*0.02))
        let q = Double(grade.quality)
        let updatedEase = state.easeFactor + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
        result.easeFactor = max(SRSState.minimumEaseFactor, updatedEase)

        if grade == .again {
            // Lapse: restart the learning streak, review again very soon.
            result.repetitions = 0
            result.intervalDays = 0
            result.dueDate = now
            return result
        }

        result.repetitions = state.repetitions + 1

        let interval: Int
        switch result.repetitions {
        case 1:
            interval = 1
        case 2:
            interval = grade == .hard ? 3 : 6
        default:
            // Hard reviews advance more slowly than good ones.
            let factor = grade == .hard ? max(SRSState.minimumEaseFactor, result.easeFactor - 0.15) : result.easeFactor
            interval = Int((Double(state.intervalDays) * factor).rounded())
        }

        result.intervalDays = max(1, interval)
        result.dueDate = nextDueDate(from: now, addingDays: result.intervalDays)
        return result
    }

    private static func nextDueDate(from now: Date, addingDays days: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(Double(days) * 86_400)
    }
}
