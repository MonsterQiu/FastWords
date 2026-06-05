import Foundation

public enum WordStatus: String, Codable, Equatable, Sendable {
    case learning
    case mastered
}

public struct WordEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var word: String
    public var phonetic: String
    public var meaning: String
    public var example: String
    public var note: String
    public var status: WordStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        word: String,
        phonetic: String = "",
        meaning: String = "",
        example: String = "",
        note: String = "",
        status: WordStatus = .learning,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.meaning = meaning
        self.example = example
        self.note = note
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
