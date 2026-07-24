import AppKit
import Carbon
import Carbon.HIToolbox
import FastWordsCore

/// Global hotkey (⌥⌘W) that captures the system text selection and hands it to
/// the app for lookup / add-to-book.
///
/// Uses Carbon `RegisterEventHotKey` (more reliable than `NSEvent` global
/// monitors, which silently fail without Accessibility on some macOS versions).
@MainActor
final class GlobalWordCapture {
    /// Called with the raw selected/copied string (may be empty on failure).
    var onCapture: ((String) -> Void)?
    /// Called when the hotkey fired but monitors could not be installed / AX denied.
    var onNeedsPermission: (() -> Void)?

    private var enabled = false
    // Carbon refs are not Sendable; kept for app-lifetime capture only.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?
    private var isCapturing = false

    /// Carbon hotkey id (unique per app).
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4657_5244), id: 1) // 'FWRD'

    func setEnabled(_ on: Bool) {
        enabled = on
        if on {
            installHotKey()
        } else {
            removeHotKey()
        }
    }

    // MARK: - Carbon hotkey

    private func installHotKey() {
        removeHotKey()

        // Install handler first.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let capture = Unmanaged<GlobalWordCapture>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    await capture.fire()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        if status != noErr {
            NSLog("FastWords: InstallEventHandler failed: \(status)")
        }

        // ⌥⌘W — keyCode is layout-stable (unlike charactersIgnoringModifiers with Option).
        var ref: EventHotKeyRef?
        let reg = RegisterEventHotKey(
            UInt32(kVK_ANSI_W),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if reg != noErr {
            NSLog("FastWords: RegisterEventHotKey failed: \(reg)")
            onNeedsPermission?()
            return
        }
        hotKeyRef = ref
    }

    private func removeHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    // MARK: - Capture

    func fire() async {
        guard enabled, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        if !SelectionReader.isTrusted(prompt: false) {
            // Show system prompt once; user must also toggle the app in Settings
            // after each rebuild of an ad-hoc-signed binary.
            _ = SelectionReader.isTrusted(prompt: true)
            if !SelectionReader.isTrusted(prompt: false) {
                onNeedsPermission?()
            }
        }

        if let text = await SelectionReader.captureSelection() {
            onCapture?(text)
            return
        }

        // Last resort: whatever is already on the pasteboard (short only).
        if let clip = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty,
           clip.count <= 80,
           clip.contains(where: \.isLetter) {
            onCapture?(clip)
            return
        }

        onCapture?("")
    }
}
