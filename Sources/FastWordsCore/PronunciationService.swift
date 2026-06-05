import Foundation

/// Which English accent to use for text-to-speech pronunciation.
public enum SpeechAccent: String, Codable, CaseIterable, Identifiable, Sendable {
    case american
    case british

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .american:
            "American (en-US)"
        case .british:
            "British (en-GB)"
        }
    }

    /// BCP-47 voice language code passed to the speech synthesizer.
    public var languageCode: String {
        switch self {
        case .american:
            "en-US"
        case .british:
            "en-GB"
        }
    }
}

/// Speaks vocabulary words aloud. Implemented in the app target with
/// `AVSpeechSynthesizer`; abstracted here so the rest of the logic stays
/// testable and UI-framework-agnostic.
@MainActor
public protocol PronunciationService: AnyObject {
    /// Speak the given text using the configured accent and rate.
    func speak(_ text: String, accent: SpeechAccent, rate: Double)
    /// Stop any in-progress speech.
    func stop()
}
