import AppKit
import FastWordsCore

/// Global hotkey (⌥⌘W) that captures the system text selection and hands it to
/// the app for lookup / add-to-book. Requires Accessibility permission.
@MainActor
final class GlobalWordCapture {
    /// Called on the main actor with the raw selected string (not yet normalized).
    var onCapture: ((String) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var enabled = false

    /// Default chord: Option + Command + W (“Word”).
    private let requiredFlags: NSEvent.ModifierFlags = [.option, .command]
    private let keyCharacter = "w"

    deinit {
        // Monitors must be removed; deinit is nonisolated — tear down sync via MainActor if needed.
        // In practice the capture lives for the app lifetime.
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        rebuildMonitors()
    }

    func rebuildMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        guard enabled else { return }

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.matchesHotkey(event) else { return }
            // Defer so we don't re-enter the event stream mid-dispatch.
            DispatchQueue.main.async {
                self.fire()
            }
        }

        // Other apps (needs Accessibility for the monitor itself on recent macOS).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
        }
        // When FastWords is key (e.g. settings open).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matchesHotkey(event) {
                handler(event)
                return nil // swallow so it doesn't type "w" into a field
            }
            return event
        }
    }

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require ⌥⌘; reject if Shift/Control also held (keeps the chord exclusive).
        guard flags.contains(.option), flags.contains(.command) else { return false }
        guard !flags.contains(.shift), !flags.contains(.control) else { return false }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        return chars == keyCharacter
    }

    private func fire() {
        // Prompt once if not trusted, then try to read selection.
        if !SelectionReader.isTrusted(prompt: false) {
            _ = SelectionReader.isTrusted(prompt: true)
        }

        if let text = SelectionReader.selectedText() {
            onCapture?(text)
            return
        }

        // Fallback: general pasteboard (user may have just copied).
        if let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty,
           clip.count <= 80 {
            onCapture?(clip)
            return
        }

        onCapture?("") // empty → caller shows “请先选中单词”
    }
}
