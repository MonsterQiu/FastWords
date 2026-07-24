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
    var importWordBook: () -> Void
    var restoreSamples: () -> Void
    var generateAIInsight: () -> Void
    /// Search a word: jump if already in a book, else dictionary, else AI.
    var searchWord: (String) -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}
