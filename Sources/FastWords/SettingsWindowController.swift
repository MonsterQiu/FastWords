import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: WordStore) {
        let hostingController = NSHostingController(rootView: SettingsView(store: store))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "FastWords 设置"
        window.setContentSize(NSSize(width: 600, height: 460))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
