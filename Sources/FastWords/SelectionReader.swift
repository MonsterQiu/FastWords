import AppKit
import ApplicationServices

/// Reads the current text selection from the frontmost app via Accessibility (AX).
enum SelectionReader {
    /// Whether this process is trusted for Accessibility. Pass `prompt: true` to
    /// show the system dialog once when not yet trusted.
    static func isTrusted(prompt: Bool = false) -> Bool {
        // Use the string constant directly — referencing `kAXTrustedCheckOptionPrompt`
        // is not concurrency-safe under Swift 6 strict checking.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings → Privacy → Accessibility so the user can enable FastWords.
    static func openAccessibilitySettings() {
        // macOS 13+ Settings deep link; fall back to legacy preference pane.
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Selected text in the focused UI element of the focused application, if any.
    static func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        ) == .success,
            let focusedApp = focusedAppRef
        else {
            return nil
        }

        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        ) == .success,
            let focusedElement = focusedElementRef
        else {
            return nil
        }

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success,
            let text = selectedRef as? String
        else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
