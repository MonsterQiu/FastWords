import Foundation

struct AppActions {
    var showPrevious: () -> Void
    var showNext: () -> Void
    var toggleMastered: () -> Void
    var importWordBook: () -> Void
    var restoreSamples: () -> Void
    var generateAIInsight: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}
