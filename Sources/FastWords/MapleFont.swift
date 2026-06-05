import CoreText
import SwiftUI

/// Registers and exposes the bundled Maple Mono font (English only — used for
/// the headword and phonetics; Chinese/UI text keeps the system font).
/// Licensed under SIL OFL-1.1; see Fonts/MapleMono-LICENSE.txt.
@MainActor
enum MapleFont {
    static let regular = "MapleMono-Regular"
    static let bold = "MapleMono-Bold"

    private static var registered = false

    /// Register the bundled TTFs with CoreText so SwiftUI can resolve them by
    /// PostScript name. Safe to call more than once.
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        for name in [regular, bold] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Maple Mono at a given size/weight, falling back to a rounded system font
    /// if the bundled font failed to register.
    @MainActor
    static func maple(_ size: CGFloat, bold: Bool = false) -> Font {
        MapleFont.registerIfNeeded()
        let name = bold ? MapleFont.bold : MapleFont.regular
        if NSFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: bold ? .heavy : .regular, design: .rounded)
    }
}
