import Foundation

/// FSRS-6 (Free Spaced Repetition Scheduler) — pure-Swift scheduler with the
/// official default parameters. Open-spaced-repetition algorithm, ported from
/// the py-fsrs / fsrs-rs reference implementations (formulas cross-verified).
///
/// Only the scheduler is implemented (no per-user optimizer): cards schedule
/// from day one using the built-in default weights, which already outperform
/// SM-2. Per-user weight training can be added later if desired.
public enum FSRS {
    /// FSRS-6 default parameters w0…w20 (from fsrs-rs `DEFAULT_PARAMETERS`).
    public static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542
    ]

    public static let stabilityMin = 0.001
    public static let stabilityMax = 36500.0
    public static let difficultyMin = 1.0
    public static let difficultyMax = 10.0
    public static let maximumInterval = 36500

    /// Desired retention (probability of recall the scheduler targets). 0.9 is
    /// the recommended default; higher = more frequent reviews.
    public static let defaultDesiredRetention = 0.9

    // MARK: - Forgetting curve

    private static func decay(_ w: [Double]) -> Double { -w[20] }

    private static func factor(_ w: [Double]) -> Double {
        pow(0.9, 1.0 / decay(w)) - 1.0
    }

    /// Probability of recall after `elapsedDays` given `stability`.
    public static func retrievability(elapsedDays: Double, stability: Double, parameters w: [Double] = defaultParameters) -> Double {
        let t = max(0, elapsedDays)
        return pow(1.0 + factor(w) * t / stability, decay(w))
    }

    /// Interval (days) to reach `desiredRetention` from the given stability.
    public static func interval(stability: Double, desiredRetention: Double = defaultDesiredRetention, parameters w: [Double] = defaultParameters) -> Int {
        let raw = (stability / factor(w)) * (pow(desiredRetention, 1.0 / decay(w)) - 1.0)
        return min(max(1, Int(raw.rounded())), maximumInterval)
    }

    // MARK: - Initial state (first review of a new card)

    public static func initialStability(_ grade: ReviewGrade, parameters w: [Double] = defaultParameters) -> Double {
        clampStability(w[grade.fsrsRating - 1])
    }

    public static func initialDifficulty(_ grade: ReviewGrade, parameters w: [Double] = defaultParameters) -> Double {
        clampDifficulty(initialDifficultyUnclamped(grade.fsrsRating, w))
    }

    private static func initialDifficultyUnclamped(_ rating: Int, _ w: [Double]) -> Double {
        w[4] - exp(w[5] * Double(rating - 1)) + 1.0
    }

    // MARK: - Updates

    /// Difficulty update: linear damping + mean reversion toward the Easy baseline.
    public static func nextDifficulty(_ difficulty: Double, grade: ReviewGrade, parameters w: [Double] = defaultParameters) -> Double {
        let g = Double(grade.fsrsRating)
        let deltaD = -w[6] * (g - 3.0)
        let damped = difficulty + deltaD * (10.0 - difficulty) / 9.0
        let target = initialDifficultyUnclamped(4, w) // Easy initial difficulty, unclamped
        let reverted = w[7] * target + (1.0 - w[7]) * damped
        return clampDifficulty(reverted)
    }

    /// Stability after a successful recall (Hard/Good). This app has no "Easy"
    /// grade, so the easy bonus (w16) never applies.
    private static func stabilityAfterSuccess(stability s: Double, difficulty d: Double, retrievability r: Double, grade: ReviewGrade, _ w: [Double]) -> Double {
        let hardPenalty = grade == .hard ? w[15] : 1.0
        let value = s * (1.0 + exp(w[8]) * (11.0 - d) * pow(s, -w[9]) * (exp(w[10] * (1.0 - r)) - 1.0) * hardPenalty)
        return clampStability(value)
    }

    /// Stability after a lapse (Again).
    private static func stabilityAfterFailure(stability s: Double, difficulty d: Double, retrievability r: Double, _ w: [Double]) -> Double {
        let long = w[11] * pow(d, -w[12]) * (pow(s + 1.0, w[13]) - 1.0) * exp(w[14] * (1.0 - r))
        let shortCap = s / exp(w[17] * w[18])
        return clampStability(min(long, shortCap))
    }

    /// Same-day (elapsed < 1 day) short-term stability.
    private static func stabilityShortTerm(stability s: Double, grade: ReviewGrade, _ w: [Double]) -> Double {
        let g = Double(grade.fsrsRating)
        var inc = exp(w[17] * (g - 3.0 + w[18])) * pow(s, -w[19])
        if grade == .good { inc = max(inc, 1.0) } // py-fsrs: floor for Good/Easy only
        return clampStability(s * inc)
    }

    // MARK: - Public review step

    /// Apply a review to an FSRS memory state, returning the new state with its
    /// next due date. Handles brand-new cards and same-day reviews.
    public static func review(
        _ state: FSRSState,
        grade: ReviewGrade,
        now: Date,
        desiredRetention: Double = defaultDesiredRetention,
        parameters w: [Double] = defaultParameters,
        calendar: Calendar = .current
    ) -> FSRSState {
        var newStability: Double
        var newDifficulty: Double

        if state.reps == 0 {
            // First review of a new card.
            newStability = initialStability(grade, parameters: w)
            newDifficulty = initialDifficulty(grade, parameters: w)
        } else {
            let elapsed = state.lastReview.map {
                Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: now)).day ?? 0)
            } ?? 0
            let r = retrievability(elapsedDays: elapsed, stability: state.stability, parameters: w)
            newDifficulty = nextDifficulty(state.difficulty, grade: grade, parameters: w)

            if elapsed < 1 {
                newStability = stabilityShortTerm(stability: state.stability, grade: grade, w)
            } else if grade == .again {
                newStability = stabilityAfterFailure(stability: state.stability, difficulty: state.difficulty, retrievability: r, w)
            } else {
                newStability = stabilityAfterSuccess(stability: state.stability, difficulty: state.difficulty, retrievability: r, grade: grade, w)
            }
        }

        let days = interval(stability: newStability, desiredRetention: desiredRetention, parameters: w)
        let due = calendar.date(byAdding: .day, value: days, to: now) ?? now.addingTimeInterval(Double(days) * 86_400)

        return FSRSState(
            stability: newStability,
            difficulty: newDifficulty,
            reps: state.reps + 1,
            lapses: state.lapses + (grade == .again ? 1 : 0),
            lastReview: now,
            dueDate: due
        )
    }

    // MARK: - Clamps

    private static func clampStability(_ s: Double) -> Double {
        min(max(s, stabilityMin), stabilityMax)
    }

    private static func clampDifficulty(_ d: Double) -> Double {
        min(max(d, difficultyMin), difficultyMax)
    }

    // MARK: - Mastery

    /// Stability (days) at or above which a word counts as "mastered". 21 days
    /// of memory stability is a comfortable long-term-retention threshold.
    public static let masteryStabilityDays = 21.0

    /// A word is mastered once it has been reviewed and its memory is stable
    /// enough to be retained for weeks. A lapse lowers stability and naturally
    /// drops it back to learning.
    public static func masteryStatus(for state: FSRSState) -> WordStatus {
        (state.reps > 0 && state.stability >= masteryStabilityDays) ? .mastered : .learning
    }
}

private extension ReviewGrade {
    /// Map the app's three grades onto FSRS's 1…4 rating scale.
    /// Again→1, Hard(模糊)→2, Good(认识)→3. (No "Easy" button in this app.)
    var fsrsRating: Int {
        switch self {
        case .again: return 1
        case .hard: return 2
        case .good: return 3
        }
    }
}
