import FastWordsCore
import Foundation

struct AppActions {
    var showPrevious: () -> Void
    var showNext: () -> Void
    var grade: (ReviewGrade) -> Void
    var toggleMastered: () -> Void
    var speak: (SpeechAccent) -> Void
    var lookUp: () -> Void
    var openSystemDictionary: () -> Void
    /// Open macOS Dictionary for an arbitrary headword (search-miss panel).
    var openSystemDictionaryFor: (String) -> Void
    var importWordBook: () -> Void
    /// Drop a TXT/CSV/JSON file onto the popover → import preview.
    var importDroppedFile: (URL) -> Void
    var restoreSamples: () -> Void
    var generateAIInsight: () -> Void
    /// Search a word: jump if already in a book, else dictionary → spelling → AI.
    var searchWord: (String) -> Void
    /// After spelling suggestions: skip them and try AI / terminal failure for the same headword.
    var continueSearchWithAI: (String) -> Void
    var confirmSearchAdd: () -> Void
    var confirmSearchPeek: () -> Void
    var dismissSearchPending: () -> Void
    var dismissSearchMiss: () -> Void
    /// Offer a blank card (pending confirm) for a headword with no dictionary hit.
    var addBlankWord: (String) -> Void
    var confirmImport: () -> Void
    var cancelImport: () -> Void
    var undoGrade: () -> Void
    /// Delete the current word from the current book (after UI confirmation).
    var deleteCurrentWord: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}
