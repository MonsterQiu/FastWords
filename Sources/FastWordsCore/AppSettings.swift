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

public enum AccentColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case green
    case purple
    case red

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blue: "Indigo"
        case .green: "Mint"
        case .purple: "Lilac"
        case .red: "Maple"
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

    /// FSRS desired retention (target recall probability, 0.7…0.97).
    public var desiredRetention: Double

    // Which content blocks to show on the word card.
    public var showChinese: Bool
    public var showEnglish: Bool
    public var showPhonetic: Bool
    public var showExample: Bool
    public var showAIHint: Bool
    /// Show the keyboard-shortcut hint bar on the word card.
    public var showShortcutHint: Bool

    /// User chosen accent color for the UI.
    public var accentColor: AccentColor

    public init(
        refreshInterval: TimeInterval = 60,
        displayMode: DisplayMode = .wordAndMeaning,
        reviewMode: ReviewMode = .smart,
        aiEnabled: Bool = false,
        aiBaseURL: String = "https://api.openai.com/v1",
        aiAPIKey: String = "",
        aiModel: String = "",
        speechAccent: SpeechAccent = .american,
        speechRate: Double = 0.45,
        autoSpeak: Bool = false,
        desiredRetention: Double = 0.9,
        showChinese: Bool = true,
        showEnglish: Bool = true,
        showPhonetic: Bool = true,
        showExample: Bool = true,
        showAIHint: Bool = true,
        showShortcutHint: Bool = true,
        accentColor: AccentColor = .blue
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
        self.desiredRetention = desiredRetention
        self.showChinese = showChinese
        self.showEnglish = showEnglish
        self.showPhonetic = showPhonetic
        self.showExample = showExample
        self.showAIHint = showAIHint
        self.showShortcutHint = showShortcutHint
        self.accentColor = accentColor
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
        desiredRetention = try container.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? defaults.desiredRetention
        showChinese = try container.decodeIfPresent(Bool.self, forKey: .showChinese) ?? defaults.showChinese
        showEnglish = try container.decodeIfPresent(Bool.self, forKey: .showEnglish) ?? defaults.showEnglish
        showPhonetic = try container.decodeIfPresent(Bool.self, forKey: .showPhonetic) ?? defaults.showPhonetic
        showExample = try container.decodeIfPresent(Bool.self, forKey: .showExample) ?? defaults.showExample
        showAIHint = try container.decodeIfPresent(Bool.self, forKey: .showAIHint) ?? defaults.showAIHint
        showShortcutHint = try container.decodeIfPresent(Bool.self, forKey: .showShortcutHint) ?? defaults.showShortcutHint
        accentColor = try container.decodeIfPresent(AccentColor.self, forKey: .accentColor) ?? defaults.accentColor
    }
}
