import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the current text selection from the frontmost app.
/// Strategy: Accessibility `AXSelectedText` first, then synthetic ⌘C + pasteboard.
enum SelectionReader {
    /// Whether this process is trusted for Accessibility.
    static func isTrusted(prompt: Bool = false) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings → Privacy → Accessibility.
    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Best-effort selection read. Prefer AX; fall back to ⌘C (restores pasteboard).
    @MainActor
    static func captureSelection() async -> String? {
        if let ax = selectedTextViaAX(), !ax.isEmpty {
            return ax
        }
        return await selectedTextViaCopy()
    }

    // MARK: - AX

    static func selectedTextViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        ) == .success,
            let focusedApp = focusedAppRef
        else { return nil }

        var focusedElementRef: CFTypeRef?
        // Some apps only expose selection on the app element itself.
        let appElement = focusedApp as! AXUIElement
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        ) == .success,
            let focusedElement = focusedElementRef {
            if let text = selectedText(from: focusedElement as! AXUIElement) {
                return text
            }
        }

        return selectedText(from: appElement)
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success else { return nil }

        if let text = selectedRef as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // Some elements return attributed strings boxed oddly.
        if let attr = selectedRef as? NSAttributedString {
            let trimmed = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    // MARK: - Synthetic ⌘C

    /// Posts ⌘C, waits for the pasteboard to change, returns new string, then restores.
    @MainActor
    static func selectedTextViaCopy() async -> String? {
        let pb = NSPasteboard.general
        let previousChange = pb.changeCount
        let previousString = pb.string(forType: .string)

        postCommandC()

        // Poll pasteboard briefly (other apps need a moment to copy).
        let deadline = Date().addingTimeInterval(0.45)
        while Date() < deadline {
            if pb.changeCount != previousChange {
                let text = pb.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Restore prior clipboard so we don't clobber the user permanently.
                restorePasteboard(string: previousString)
                if let text, !text.isEmpty, text.count <= 200 {
                    return text
                }
                return nil
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return nil
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = CGKeyCode(kVK_ANSI_C)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        // hidEventTap can fail without accessibility; try both taps.
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private static func restorePasteboard(string: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let string {
            pb.setString(string, forType: .string)
        }
    }
}
