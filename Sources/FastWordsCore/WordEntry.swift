import Foundation

public enum WordStatus: String, Codable, Equatable, Sendable {
    case learning
    case mastered
}

public struct WordEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var word: String
    public var phonetic: String
    /// US/UK phonetics when a source distinguishes them; otherwise empty and the
    /// single ``phonetic`` is used as a fallback for display.
    public var phoneticUS: String
    public var phoneticUK: String
    public var meaning: String
    public var example: String
    public var note: String
    public var status: WordStatus
    public var createdAt: Date
    public var updatedAt: Date

    /// Spaced-repetition state (SM-2). Defaults model a brand-new, immediately-due card.
    public var srs: SRSState

    /// Local path (relative to the audio cache directory) of a cached pronunciation clip, if any.
    public var audioFileName: String?

    public init(
        id: UUID = UUID(),
        word: String,
        phonetic: String = "",
        phoneticUS: String = "",
        phoneticUK: String = "",
        meaning: String = "",
        example: String = "",
        note: String = "",
        status: WordStatus = .learning,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        srs: SRSState = SRSState(),
        audioFileName: String? = nil
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.phoneticUS = phoneticUS
        self.phoneticUK = phoneticUK
        self.meaning = meaning
        self.example = example
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.srs = srs
        self.audioFileName = audioFileName
    }

    // Backward-compatible decoding: word books saved before SRS/audio existed
    // simply get default SRS state and no cached audio.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        phoneticUS = try container.decodeIfPresent(String.self, forKey: .phoneticUS) ?? ""
        phoneticUK = try container.decodeIfPresent(String.self, forKey: .phoneticUK) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        status = try container.decodeIfPresent(WordStatus.self, forKey: .status) ?? .learning
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        srs = try container.decodeIfPresent(SRSState.self, forKey: .srs) ?? SRSState()
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
    }
}
