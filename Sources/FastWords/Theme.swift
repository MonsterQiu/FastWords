import SwiftUI

/// Visual design tokens: text uses system semantic colors so it stays legible
/// on the translucent menu-bar material in both light and dark mode; blue is
/// reserved as the accent for marks, chips, borders, and the primary action.
enum Theme {
    /// Subtle translucent fill for inner cards/sections sitting on the material.
    static let surface = Color.primary.opacity(0.06)
    /// Hairline / border stroke color.
    static let stroke = Color.primary.opacity(0.12)
    /// Primary text.
    static let ink = Color.primary
    /// Muted secondary text.
    static let inkSoft = Color.secondary
    /// Bright azure accent for marks, chips, and interactive glyphs.
    static let accent = Color(light: rgb(0.13, 0.42, 0.86), dark: rgb(0.45, 0.70, 1.0))
    /// Filled accent for the primary action pill.
    static let accentFill = Color(light: rgb(0.15, 0.45, 0.90), dark: rgb(0.30, 0.55, 0.98))

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// Build a color that resolves differently in light vs dark appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}

/// Native frosted-glass background using `NSVisualEffectView`, matching the
/// translucency of a standard menu-bar popover.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

