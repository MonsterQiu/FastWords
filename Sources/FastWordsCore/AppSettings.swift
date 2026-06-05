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
    case smart

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sequential:
            "Sequential"
        case .random:
            "Random"
        case .smart:
            "Smart (SRS)"
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

    // Pronunciation
    public var speechAccent: SpeechAccent
    /// 0...1 normalized speaking rate; mapped to the synthesizer's range at speak time.
    public var speechRate: Double
    /// Speak the word automatically whenever a new one is shown.
    public var autoSpeak: Bool

    public init(
        refreshInterval: TimeInterval = 60,
        displayMode: DisplayMode = .wordAndMeaning,
        reviewMode: ReviewMode = .sequential,
        aiEnabled: Bool = false,
        aiBaseURL: String = "https://api.openai.com/v1",
        aiAPIKey: String = "",
        aiModel: String = "",
        speechAccent: SpeechAccent = .american,
        speechRate: Double = 0.45,
        autoSpeak: Bool = false
    ) {
        self.refreshInterval = refreshInterval
        self.displayMode = displayMode
        self.reviewMode = reviewMode
        self.aiEnabled = aiEnabled
        self.aiBaseURL = aiBaseURL
        self.aiAPIKey = aiAPIKey
        self.aiModel = aiModel
        self.speechAccent = speechAccent
        self.speechRate = speechRate
        self.autoSpeak = autoSpeak
    }

    // Backward-compatible decoding: settings saved before pronunciation existed
    // fall back to sensible defaults for the new keys.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        refreshInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        reviewMode = try container.decodeIfPresent(ReviewMode.self, forKey: .reviewMode) ?? defaults.reviewMode
        aiEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? defaults.aiEnabled
        aiBaseURL = try container.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? defaults.aiBaseURL
        aiAPIKey = try container.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? defaults.aiAPIKey
        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? defaults.aiModel
        speechAccent = try container.decodeIfPresent(SpeechAccent.self, forKey: .speechAccent) ?? defaults.speechAccent
        speechRate = try container.decodeIfPresent(Double.self, forKey: .speechRate) ?? defaults.speechRate
        autoSpeak = try container.decodeIfPresent(Bool.self, forKey: .autoSpeak) ?? defaults.autoSpeak
    }
}
