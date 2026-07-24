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
        MapleFont.registerIfNeeded()
        installMainMenu()
        configureStatusItem()
        configurePopover()
        bindStore()
        scheduleTimer()
        updateStatusTitle()
    }

    /// A menu-bar (.accessory) app has no main menu by default, so the standard
    /// editing shortcuts (⌘C/⌘V/⌘X/⌘A) are never dispatched to the focused text
    /// field. Install a minimal Edit menu wired to the responder-chain selectors
    /// so paste works in the settings text fields.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        // App menu (provides ⌘Q quit).
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 FastWords", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Edit menu (provides ⌘X/⌘C/⌘V/⌘A in text fields).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        // Left-click → word card; right-click → status menu (settings / quit).
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Truncate (don't expand) inside the fixed-width button so the item
        // keeps a constant width and the popover anchor never moves.
        button.lineBreakMode = .byTruncatingTail
        button.cell?.truncatesLastVisibleLine = true
        button.imagePosition = .noImage
    }

    @objc
    private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent, let button = statusItem.button else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            // Close the card if open so the menu isn't fighting the popover.
            if popover.isShown { popover.performClose(nil) }
            let menu = buildStatusMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        } else {
            togglePopover()
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "打开单词卡",
            action: #selector(openPopoverFromMenu),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "退出 FastWords",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        return menu
    }

    @objc
    private func openPopoverFromMenu() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc
    private func openSettingsFromMenu() {
        openSettings()
    }

    private func configurePopover() {
        // semitransient keeps the popover open while typing in the search field
        // (transient often dismisses when the text field becomes first responder).
        popover.behavior = .semitransient
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
                    openSystemDictionary: { [weak self] in self?.openSystemDictionary() },
                    openSystemDictionaryFor: { [weak self] word in self?.openSystemDictionary(for: word) },
                    importWordBook: { [weak self] in self?.importWordBook() },
                    importDroppedFile: { [weak self] url in self?.handleDroppedWordBook(url: url) },
                    restoreSamples: { [weak self] in self?.store.restoreSamples(); self?.advanced() },
                    generateAIInsight: { [weak self] in self?.generateAIInsight() },
                    searchWord: { [weak self] query in self?.searchWord(query, skipSpellingGate: false) },
                    continueSearchWithAI: { [weak self] headword in self?.searchWord(headword, skipSpellingGate: true) },
                    confirmSearchAdd: { [weak self] in
                        self?.store.confirmPendingSearchAdd()
                        self?.advanced()
                    },
                    confirmSearchPeek: { [weak self] in
                        self?.store.confirmPendingSearchPeek()
                        self?.updateStatusTitle()
                    },
                    dismissSearchPending: { [weak self] in self?.store.dismissPendingSearch() },
                    dismissSearchMiss: { [weak self] in self?.store.dismissSearchMiss() },
                    addBlankWord: { [weak self] word in
                        // Pending confirm only — does not write until user taps 加入词书.
                        self?.store.presentBlankPending(word: word)
                        self?.updateStatusTitle()
                    },
                    confirmImport: { [weak self] in
                        self?.store.confirmImportPreview()
                        self?.updateStatusTitle()
                    },
                    cancelImport: { [weak self] in self?.store.cancelImportPreview() },
                    undoGrade: { [weak self] in
                        _ = self?.store.undoLastGrade()
                        self?.updateStatusTitle()
                    },
                    deleteCurrentWord: { [weak self] in
                        _ = self?.store.deleteCurrentWord()
                        self?.updateStatusTitle()
                    },
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
        // Any change to the books (current word, index, switching books) or the
        // selected book refreshes the menu bar title.
        store.$books
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)

        store.$currentBookID
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
                guard let self else { return }
                // Don't auto-advance while the popover is open — the user is
                // looking at or interacting with the current word.
                guard !self.popover.isShown else { return }
                self.store.showNext()
                // Ambient timer rotation only updates the menu bar; it never
                // speaks unprompted (the Mac shouldn't talk to itself while the
                // user is away). Auto-speak is reserved for user navigation.
                self.updateStatusTitle()
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

    private func openSystemDictionary() {
        guard let word = store.currentWord?.word else { return }
        openSystemDictionary(for: word)
    }

    private func openSystemDictionary(for word: String) {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        guard let url = URL(string: "dict://\(encoded)") else { return }
        NSWorkspace.shared.open(url)
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
            .tabSeparatedText,
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
            // Preview first: user confirms added/skipped counts before merge.
            store.previewImport(entries, sourceName: url.lastPathComponent)
            updateStatusTitle()
        } catch {
            store.showImportError(error.localizedDescription)
        }
    }

    /// Called when a file is dropped onto the popover (TXT / CSV / JSON).
    func handleDroppedWordBook(url: URL) {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let entries = try WordBookImporter.importEntries(from: url)
            store.previewImport(entries, sourceName: url.lastPathComponent)
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

    /// Search funnel:
    /// 1) normalize headword  2) jump if in book  3) dictionary
    /// 4) local spelling suggestions (unless skipped)  5) AI  6) typed failure panel
    ///
    /// - Parameter skipSpellingGate: when true (user tapped “仍用 AI 查询”), skip the
    ///   intermediate spelling panel and go straight to AI / terminal failure.
    private func searchWord(_ query: String, skipSpellingGate: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // "diversity 什么意思" → headword "diversity". Match books by headword only.
        let headword = SearchQueryNormalizer.headword(from: trimmed)
        guard !headword.isEmpty else { return }

        store.dismissSearchMiss()

        // Already in any loaded book → jump there; never show “加入词书”.
        if store.jumpToWord(headword, announce: true) {
            advanced()
            return
        }

        store.beginLookup()
        let settings = store.settings

        Task {
            // 1) Offline ECDICT + Free Dictionary API.
            do {
                let result = try await dictionary.lookup(headword)
                await MainActor.run {
                    self.store.presentPendingSearch(
                        word: headword,
                        result: result,
                        sourceLabel: "词典查询成功"
                    )
                    self.updateStatusTitle()
                }
                if let audioURL = result.audioURL {
                    _ = try? await audioCache.ensureCached(audioURL)
                }
                return
            } catch {
                // fall through
            }

            // 2) Local spelling suggestions before spending AI (unless user already skipped).
            let suggestions = await MainActor.run {
                self.store.spellingSuggestions(for: headword)
            }
            if !skipSpellingGate, !suggestions.isEmpty {
                await MainActor.run {
                    self.store.presentSearchMiss(
                        WordStore.SearchMiss(
                            query: headword,
                            reason: .spellingSuggestions,
                            suggestions: suggestions,
                            canContinueWithAI: true
                        )
                    )
                    self.updateStatusTitle()
                }
                return
            }

            // 3) AI fallback.
            await self.finishSearchWithAI(headword: headword, settings: settings, suggestions: suggestions)
        }
    }

    private func finishSearchWithAI(
        headword: String,
        settings: AppSettings,
        suggestions: [String]
    ) async {
        do {
            let result = try await AIClient().lookupDefinition(for: headword, settings: settings)
            await MainActor.run {
                self.store.presentPendingSearch(
                    word: headword,
                    result: result,
                    sourceLabel: "AI 补充释义"
                )
                self.updateStatusTitle()
            }
        } catch let error as AIClientError {
            let reason: WordStore.SearchMissReason
            switch error {
            case .disabled:
                reason = .aiDisabled
            case .missingConfiguration:
                reason = .aiNotConfigured
            case .notAWord:
                reason = .notAValidWord
            case .requestFailed(let msg):
                reason = .lookupFailed(msg)
            case .invalidResponse, .invalidBaseURL:
                reason = .lookupFailed(error.localizedDescription)
            }
            await MainActor.run {
                self.store.presentSearchMiss(
                    WordStore.SearchMiss(
                        query: headword,
                        reason: reason,
                        suggestions: suggestions,
                        canContinueWithAI: false
                    )
                )
                self.updateStatusTitle()
            }
        } catch {
            await MainActor.run {
                self.store.presentSearchMiss(
                    WordStore.SearchMiss(
                        query: headword,
                        reason: .lookupFailed(error.localizedDescription),
                        suggestions: suggestions,
                        canContinueWithAI: false
                    )
                )
                self.updateStatusTitle()
            }
        }
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
            // Revert to a menu-bar-only app once the settings window closes.
            if let window = settingsWindowController?.window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(settingsWindowWillClose),
                    name: NSWindow.willCloseNotification,
                    object: window
                )
            }
        }

        // Dismiss the transient popover first; leaving it open can keep the app
        // from giving the settings window keyboard focus (so paste/⌘V fails).
        if popover.isShown { popover.performClose(nil) }

        // An .accessory app won't reliably give a window key/focus. Switch to
        // .regular while settings is open so text fields accept typing & paste.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc
    private func settingsWindowWillClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}
