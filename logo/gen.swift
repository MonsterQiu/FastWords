import AppKit
import CoreText
import Foundation

// 注册 Maple 字体
let fontURL = URL(fileURLWithPath: "Sources/FastWords/Fonts/MapleMono-Bold.ttf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
guard NSFont(name: "MapleMono-Bold", size: 100) != nil else {
    print("FONT NOT AVAILABLE"); exit(1)
}

let size: CGFloat = 1024
let iconRect = CGRect(x: 112, y: 112, width: 800, height: 800)   // squircle 区域
let corner: CGFloat = 180

func squirclePath(_ rect: CGRect, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

// 画一张图：bg = 背景填充闭包；letterColor = W 颜色；fontSize；带不带描边
func render(name: String,
            background: (CGContext, CGRect) -> Void,
            letterColor: NSColor,
            fontSize: CGFloat = 560,
            strokeColor: NSColor? = nil,
            strokeWidth: CGFloat = 0) {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // 背景 squircle
    let clip = squirclePath(iconRect, corner)
    ctx.saveGState()
    clip.addClip()
    background(ctx, iconRect)
    ctx.restoreGState()

    // W 字
    let font = NSFont(name: "MapleMono-Bold", size: fontSize)!
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: letterColor]
    if let sc = strokeColor {
        attrs[.strokeColor] = sc
        attrs[.strokeWidth] = -strokeWidth   // 负数 = 描边+填充
    }
    let str = NSAttributedString(string: "W", attributes: attrs)
    let textSize = str.size()
    // 视觉居中（Maple 的 W 有点偏，微调）
    let x = iconRect.midX - textSize.width / 2
    let y = iconRect.midY - textSize.height / 2 + 6
    str.draw(at: NSPoint(x: x, y: y))

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("encode fail \(name)"); return
    }
    try? png.write(to: URL(fileURLWithPath: "logo/\(name).png"))
    print("wrote logo/\(name).png")
}

func linear(_ ctx: CGContext, _ rect: CGRect, _ c0: NSColor, _ c1: NSColor) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: cs, colors: [c0.cgColor, c1.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}

// E：深靛蓝渐变底 + 白色 Maple W
render(name: "logo-E",
       background: { c, r in linear(c, r, rgb(74,140,255), rgb(45,107,224)) },
       letterColor: .white)

// F：浅底 + 深蓝 Maple W（清爽）
render(name: "logo-F",
       background: { c, r in linear(c, r, rgb(242,245,251), rgb(226,233,246)) },
       letterColor: rgb(35,76,158))

// G：很深的靛蓝底 + 亮蓝 W（夜间感）
render(name: "logo-G",
       background: { c, r in linear(c, r, rgb(34,50,92), rgb(22,34,63)) },
       letterColor: rgb(91,157,255))

// H：白底 + 蓝渐变 W（字本身渐变，留白多）
render(name: "logo-H",
       background: { c, r in c.setFillColor(NSColor.white.cgColor); c.fill(r) },
       letterColor: rgb(45,107,224))
