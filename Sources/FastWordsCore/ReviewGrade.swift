import Foundation

/// How well the learner recalled a word during review.
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
}
