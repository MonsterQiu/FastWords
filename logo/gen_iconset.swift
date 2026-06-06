import AppKit
import CoreText
import Foundation

CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: "Sources/FastWords/Fonts/MapleMono-Bold.ttf") as CFURL, .process, nil)
guard NSFont(name: "MapleMono-Bold", size: 100) != nil else { print("FONT MISSING"); exit(1) }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

/// Render the app icon at a given pixel size. Transparent canvas, centered
/// squircle with ~10% margin (Apple's macOS icon grid), gradient blue, white W.
func renderIcon(px: CGFloat) -> Data? {
    let dim = Int(px)
    // Draw directly into a pixel-exact bitmap so output is `dim`×`dim` regardless
    // of the screen's backing scale (NSImage.lockFocus would draw at 2x on Retina).
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: dim, pixelsHigh: dim,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: dim, height: dim)

    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))

    // macOS icon: content ~80% of canvas, centered (≈10% margin each side).
    let inset = px * 0.10
    let rect = CGRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let corner = rect.width * 0.225   // squircle-ish corner radius

    // Gradient squircle background.
    let clip = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    ctx.saveGState()
    clip.addClip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [rgb(74,140,255).cgColor, rgb(45,107,224).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()

    // White W, sized relative to the icon, visually centered.
    let font = NSFont(name: "MapleMono-Bold", size: rect.width * 0.62)!
    let str = NSAttributedString(string: "W", attributes: [.font: font, .foregroundColor: NSColor.white])
    let ts = str.size()
    str.draw(at: NSPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2 + px * 0.012))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// macOS .iconset 需要的尺寸（含 @2x）
let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16",      16),  ("icon_16x16@2x",    32),
    ("icon_32x32",      32),  ("icon_32x32@2x",    64),
    ("icon_128x128",   128),  ("icon_128x128@2x", 256),
    ("icon_256x256",   256),  ("icon_256x256@2x", 512),
    ("icon_512x512",   512),  ("icon_512x512@2x",1024),
]

let dir = "logo/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for s in specs {
    if let png = renderIcon(px: s.px) {
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(s.name).png"))
        print("wrote \(s.name).png (\(Int(s.px))px)")
    }
}
// 也存一张 1024 预览
if let png = renderIcon(px: 1024) { try? png.write(to: URL(fileURLWithPath: "logo/AppIcon-preview.png")) }
print("done")
