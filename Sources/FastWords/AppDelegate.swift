import AppKit
import Combine
import FastWordsCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WordStore()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 440)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                store: store,
                actions: AppActions(
                    showPrevious: { [weak self] in self?.store.showPrevious(); self?.updateStatusTitle() },
                    showNext: { [weak self] in self?.store.showNext(); self?.updateStatusTitle() },
                    toggleMastered: { [weak self] in self?.store.toggleMastered(); self?.updateStatusTitle() },
                    importWordBook: { [weak self] in self?.importWordBook() },
                    restoreSamples: { [weak self] in self?.store.restoreSamples(); self?.updateStatusTitle() },
                    generateAIInsight: { [weak self] in self?.generateAIInsight() },
                    openSettings: { [weak self] in self?.openSettings() },
                    quit: { NSApp.terminate(nil) }
                )
            )
        )
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
                self?.updateStatusTitle()
            }
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }

        if let word = store.currentWord {
            button.title = statusTitle(for: word)
        } else {
            button.title = "FastWords"
        }
    }

    private func statusTitle(for entry: WordEntry) -> String {
        switch store.settings.displayMode {
        case .wordOnly:
            return truncate(entry.word, limit: 24)
        case .wordAndMeaning:
            let meaning = entry.meaning.isEmpty ? "No meaning" : entry.meaning
            return truncate("\(entry.word) · \(meaning)", limit: 34)
        case .progress:
            return "FastWords · \(store.progressText)"
        }
    }

    private func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
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
            store.failAIInsight(error.localizedDescription)
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
