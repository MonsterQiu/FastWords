import AppKit
import Combine
import FastWordsCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WordStore()
    private let speech: PronunciationService = SystemSpeechSynthesizer()
    // Offline Chinese dictionary first, online English (with audio) as fallback.
    private let dictionary: DictionaryService = CompositeDictionaryService([
        OfflineDictionary.shared,
        FreeDictionaryService()
    ])
    private lazy var audioCache = AudioCache(directory: store.audioDirectory)
    /// Fixed width keeps the status item from resizing as words change, so the
    /// popover (anchored to it) never shifts left/right. Long words truncate.
    private static let statusItemWidth: CGFloat = 96
    private let statusItem = NSStatusBar.system.statusItem(withLength: AppDelegate.statusItemWidth)
    private let popover = NSPopover()
    private var settingsWindowController: SettingsWindowController?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        bindStore()
        scheduleTimer()
        updateStatusTitle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Truncate (don't expand) inside the fixed-width button so the item
        // keeps a constant width and the popover anchor never moves.
        button.lineBreakMode = .byTruncatingTail
        button.cell?.truncatesLastVisibleLine = true
        button.imagePosition = .noImage
    }

    private func configurePopover() {
        popover.behavior = .transient
        let contentSize = NSSize(width: 360, height: 540)
        popover.contentSize = contentSize

        let hosting = NSHostingController(
            rootView: MenuBarPopoverView(
                store: store,
                actions: AppActions(
                    showPrevious: { [weak self] in self?.store.showPrevious(); self?.advanced() },
                    showNext: { [weak self] in self?.store.showNext(); self?.advanced() },
                    grade: { [weak self] grade in self?.store.grade(grade); self?.advanced() },
                    toggleMastered: { [weak self] in self?.store.toggleMastered(); self?.updateStatusTitle() },
                    speak: { [weak self] accent in self?.speakCurrentWord(accent: accent) },
                    lookUp: { [weak self] in self?.lookUpCurrentWord() },
                    importWordBook: { [weak self] in self?.importWordBook() },
                    restoreSamples: { [weak self] in self?.store.restoreSamples(); self?.advanced() },
                    generateAIInsight: { [weak self] in self?.generateAIInsight() },
                    openSettings: { [weak self] in self?.openSettings() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        )

        // Pin the size so SwiftUI's intrinsic content size can't drive the
        // hosting controller — otherwise the popover re-anchors (visually
        // "jumps") whenever the word changes the content's natural height.
        hosting.sizingOptions = []
        hosting.preferredContentSize = contentSize
        popover.contentViewController = hosting
    }

    private func bindStore() {
        store.$words
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)

        store.$currentIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)

        store.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTimer()
                self?.updateStatusTitle()
            }
            .store(in: &cancellables)
    }

    @objc
    private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        guard store.settings.refreshInterval > 0 else { return }

        timer = Timer.scheduledTimer(withTimeInterval: store.settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.store.showNext()
                // Ambient timer rotation only updates the menu bar; it never
                // speaks unprompted (the Mac shouldn't talk to itself while the
                // user is away). Auto-speak is reserved for user navigation.
                self?.updateStatusTitle()
            }
        }
    }

    /// Called after the user changes the current word: refresh the menu bar and,
    /// if enabled, speak the new word aloud.
    private func advanced() {
        updateStatusTitle()
        if store.settings.autoSpeak {
            speakCurrentWord(accent: store.settings.speechAccent)
        }
    }

    private func speakCurrentWord(accent: SpeechAccent) {
        guard let word = store.currentWord else { return }
        // Prefer a cached human recording; fall back to system TTS.
        // (Cached clips are accent-agnostic; TTS honors the requested accent.)
        if let fileName = word.audioFileName, audioCache.play(fileName: fileName) {
            return
        }
        speech.speak(word.word, accent: accent, rate: store.settings.speechRate)
    }

    /// Look the current word up in the free dictionary: fill blank fields and
    /// cache a human pronunciation clip when one is available. Network failures
    /// degrade gracefully and never block offline use.
    private func lookUpCurrentWord() {
        guard let word = store.currentWord else { return }
        store.beginLookup()
        let wordID = word.id

        Task {
            do {
                let result = try await dictionary.lookup(word.word)
                await MainActor.run { self.store.applyLookup(result) }

                if let audioURL = result.audioURL {
                    if let name = try? await audioCache.ensureCached(audioURL) {
                        await MainActor.run { self.store.setAudioFileName(name, forWordID: wordID) }
                    }
                }
                await MainActor.run { self.updateStatusTitle() }
            } catch {
                let message = (error as? DictionaryError) == .notFound
                    ? "No dictionary entry found."
                    : error.localizedDescription
                await MainActor.run { self.store.failLookup(message) }
            }
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }
        // Menu bar shows the English word only — calm, glanceable, no clutter.
        // A centered, tail-truncating attributed title keeps the fixed-width
        // button from changing size as words vary in length.
        let text = store.currentWord?.word ?? "FastWords"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .paragraphStyle: paragraph
            ]
        )
    }


    private func importWordBook() {
        let panel = NSOpenPanel()
        panel.title = "Import Word Book"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .plainText,
            .commaSeparatedText,
            .json
        ]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let entries = try WordBookImporter.importEntries(from: url)
            store.replaceWords(entries, sourceName: url.lastPathComponent)
            updateStatusTitle()
        } catch {
            store.showImportError(error.localizedDescription)
        }
    }

    private func generateAIInsight() {
        guard let entry = store.currentWord else { return }
        let settings = store.settings
        store.beginAIInsight()

        Task {
            do {
                let insight = try await AIClient().generateInsight(for: entry, settings: settings)
                await MainActor.run {
                    self.store.finishAIInsight(insight)
                }
            } catch {
                await MainActor.run {
                    self.store.failAIInsight(error.localizedDescription)
                }
            }
        }
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
