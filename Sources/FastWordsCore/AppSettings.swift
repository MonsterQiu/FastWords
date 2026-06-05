import Foundation

public enum DisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case wordOnly
    case wordAndMeaning
    case progress

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wordOnly:
            "Word only"
        case .wordAndMeaning:
            "Word + meaning"
        case .progress:
            "Progress"
        }
    }
}

public enum ReviewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case sequential
    case random

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sequential:
            "Sequential"
        case .random:
            "Random"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var refreshInterval: TimeInterval
    public var displayMode: DisplayMode
    public var reviewMode: ReviewMode
    public var aiEnabled: Bool
    public var aiBaseURL: String
    public var aiAPIKey: String
    public var aiModel: String

    public init(
        refreshInterval: TimeInterval = 60,
        displayMode: DisplayMode = .wordAndMeaning,
        reviewMode: ReviewMode = .sequential,
        aiEnabled: Bool = false,
        aiBaseURL: String = "https://api.openai.com/v1",
        aiAPIKey: String = "",
        aiModel: String = ""
    ) {
        self.refreshInterval = refreshInterval
        self.displayMode = displayMode
        self.reviewMode = reviewMode
        self.aiEnabled = aiEnabled
        self.aiBaseURL = aiBaseURL
        self.aiAPIKey = aiAPIKey
        self.aiModel = aiModel
    }
}
