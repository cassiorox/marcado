// Gera Resources/AppIcon.icns: folha de papel com "M" e seta para baixo (marca do Markdown).
// Uso: swift make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Fundo arredondado azul da marca, com leve gradiente.
    let bgRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.10, green: 0.36, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.00, green: 0.20, blue: 0.66, alpha: 1))!.draw(in: bg, angle: -90)

    // Folha sépia.
    let sheet = NSRect(x: 262 * s, y: 196 * s, width: 500 * s, height: 632 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 30 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.965, green: 0.937, blue: 0.863, alpha: 1).setFill()
    NSBezierPath(roundedRect: sheet, xRadius: 36 * s, yRadius: 36 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Linhas de texto.
    NSColor(srgbRed: 0.23, green: 0.19, blue: 0.14, alpha: 0.22).setFill()
    for (i, w) in [360, 300, 340].enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 332 * s, y: (300 + CGFloat(i) * 56) * s, width: CGFloat(w) * s, height: 22 * s),
                     xRadius: 11 * s, yRadius: 11 * s).fill()
    }

    // "M" e seta.
    let ink = NSColor(srgbRed: 0.16, green: 0.13, blue: 0.10, alpha: 1)
    let font = NSFont.systemFont(ofSize: 230 * s, weight: .heavy)
    let m = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: ink])
    let mSize = m.size()
    m.draw(at: NSPoint(x: 330 * s, y: 520 * s - mSize.height * 0.18))
    let arrow = NSBezierPath()
    let ax = 628 * s, top = 740 * s, bottom = 560 * s
    arrow.move(to: NSPoint(x: ax - 26 * s, y: top))
    arrow.line(to: NSPoint(x: ax + 26 * s, y: top))
    arrow.line(to: NSPoint(x: ax + 26 * s, y: bottom + 70 * s))
    arrow.line(to: NSPoint(x: ax + 70 * s, y: bottom + 70 * s))
    arrow.line(to: NSPoint(x: ax, y: bottom))
    arrow.line(to: NSPoint(x: ax - 70 * s, y: bottom + 70 * s))
    arrow.line(to: NSPoint(x: ax - 26 * s, y: bottom + 70 * s))
    arrow.close()
    NSColor(srgbRed: 0.00, green: 0.24, blue: 0.78, alpha: 1).setFill()
    arrow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
print(p.terminationStatus == 0 ? "OK: Resources/AppIcon.icns" : "falha no iconutil")
