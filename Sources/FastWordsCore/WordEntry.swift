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
    /// English (English-to-English) definition, when available.
    public var englishDefinition: String
    public var example: String
    public var note: String
    public var status: WordStatus
    public var createdAt: Date
    public var updatedAt: Date

    /// Legacy SM-2 state, kept for backward-compatible decoding and migration.
    public var srs: SRSState
    /// FSRS-6 memory state (the active scheduler).
    public var fsrs: FSRSState

    /// Local path (relative to the audio cache directory) of a cached pronunciation clip, if any.
    public var audioFileName: String?

    public init(
        id: UUID = UUID(),
        word: String,
        phonetic: String = "",
        phoneticUS: String = "",
        phoneticUK: String = "",
        meaning: String = "",
        englishDefinition: String = "",
        example: String = "",
        note: String = "",
        status: WordStatus = .learning,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        srs: SRSState = SRSState(),
        fsrs: FSRSState = FSRSState(),
        audioFileName: String? = nil
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.phoneticUS = phoneticUS
        self.phoneticUK = phoneticUK
        self.meaning = meaning
        self.englishDefinition = englishDefinition
        self.example = example
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.srs = srs
        self.fsrs = fsrs
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
        englishDefinition = try container.decodeIfPresent(String.self, forKey: .englishDefinition) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        status = try container.decodeIfPresent(WordStatus.self, forKey: .status) ?? .learning
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        srs = try container.decodeIfPresent(SRSState.self, forKey: .srs) ?? SRSState()
        if let savedFSRS = try container.decodeIfPresent(FSRSState.self, forKey: .fsrs) {
            fsrs = savedFSRS
        } else {
            // Migrate from legacy SM-2 state: seed FSRS stability from the old
            // interval and carry over reps/due so progress isn't reset.
            fsrs = FSRSState.migrated(fromSM2: srs)
        }
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
    }
}

public extension FSRSState {
    /// Seed an FSRS state from a legacy SM-2 state so existing reviewed cards
    /// keep their progress instead of resetting to brand-new.
    static func migrated(fromSM2 sm2: SRSState) -> FSRSState {
        guard sm2.repetitions > 0 || sm2.intervalDays > 0 else {
            return FSRSState() // never reviewed → brand new
        }
        return FSRSState(
            stability: max(FSRS.stabilityMin, Double(max(sm2.intervalDays, 1))),
            difficulty: 5.0, // neutral starting difficulty
            reps: max(1, sm2.repetitions),
            lapses: 0,
            lastReview: sm2.lastReviewedAt,
            dueDate: sm2.dueDate
        )
    }
}
