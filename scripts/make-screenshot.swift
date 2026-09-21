// Renders the settings window into a framed screenshot for the README.
//
// Compiled together with the app sources into a minimal .app bundle, so that
// NSLocalizedString resolves and the language can be forced with -AppleLanguages.
// ImageRenderer is used instead of a screen capture, which keeps this free of any
// Screen Recording permission. It cannot draw Form, List, GroupBox or ScrollView,
// which is why SettingsView exposes `previewBody`.
import AppKit
import SwiftUI

let contentSize = NSSize(width: 560, height: 628)
let pad: CGFloat = 60
let padBottom: CGFloat = 76   // el desenfoque de la sombra cae hacia abajo
let titleBar: CGFloat = 28
let radius: CGFloat = 11
let scale: CGFloat = 2

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

/// Soft radial wash, the kind macOS wallpapers are made of.
func glow(_ color: NSColor, at point: NSPoint, radius r: CGFloat) {
    NSGradient(colors: [color, color.withAlphaComponent(0)])!
        .draw(fromCenter: point, radius: 0, toCenter: point, radius: r, options: [])
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let model = Model()

DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
    // 1. The window contents.
    let renderer = ImageRenderer(content:
        SettingsView(model: model).previewBody
            .frame(width: contentSize.width, height: contentSize.height))
    renderer.scale = scale
    guard let content = renderer.nsImage else { print("render failed"); exit(1) }

    // 2. The canvas.
    let winW = contentSize.width, winH = contentSize.height + titleBar
    let canvas = NSSize(width: winW + pad * 2, height: winH + pad + padBottom)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(canvas.width * scale),
                               pixelsHigh: Int(canvas.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // 3. Desktop background: violet to blue, with warm and cool washes over it.
    let full = NSRect(origin: .zero, size: canvas)
    NSGradient(colors: [rgb(96, 68, 214), rgb(22, 104, 220)])!.draw(in: full, angle: -60)
    glow(rgb(255, 138, 190, 0.34), at: NSPoint(x: canvas.width * 0.86, y: canvas.height * 0.92),
         radius: canvas.width * 0.60)
    glow(rgb(70, 220, 235, 0.26), at: NSPoint(x: canvas.width * 0.06, y: canvas.height * 0.06),
         radius: canvas.width * 0.55)
    glow(rgb(12, 16, 64, 0.30), at: NSPoint(x: canvas.width * 0.5, y: -canvas.height * 0.25),
         radius: canvas.width * 0.95)

    // 4. Window, with the shadow it would cast on a real desktop.
    let win = NSRect(x: pad, y: padBottom, width: winW, height: winH)
    let winPath = NSBezierPath(roundedRect: win, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.42)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()
    NSColor.white.setFill()
    winPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    winPath.addClip()

    // Contents sit below the title bar.
    content.draw(in: NSRect(x: win.minX, y: win.minY, width: winW, height: contentSize.height))

    // Title bar.
    let bar = NSRect(x: win.minX, y: win.maxY - titleBar, width: winW, height: titleBar)
    NSGradient(colors: [rgb(252, 252, 252), rgb(238, 238, 238)])!.draw(in: bar, angle: -90)
    rgb(214, 214, 214).setFill()
    NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 1).fill()

    // Traffic lights.
    let lights: [NSColor] = [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)]
    for (i, color) in lights.enumerated() {
        let d: CGFloat = 12
        let r = NSRect(x: bar.minX + 16 + CGFloat(i) * 20, y: bar.midY - d/2, width: d, height: d)
        color.setFill(); NSBezierPath(ovalIn: r).fill()
        NSColor(white: 0, alpha: 0.10).setStroke()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)); ring.lineWidth = 1; ring.stroke()
    }

    // Window title.
    let title = "KeyBoost" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: rgb(72, 72, 74),
    ]
    let size = title.size(withAttributes: attrs)
    title.draw(at: NSPoint(x: bar.midX - size.width/2, y: bar.midY - size.height/2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()

    // Hairline around the whole window.
    NSColor(white: 1, alpha: 0.22).setStroke()
    winPath.lineWidth = 1
    winPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    let out = CommandLine.arguments.contains("--out")
        ? CommandLine.arguments[CommandLine.arguments.firstIndex(of: "--out")! + 1]
        : "docs/screenshot.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}
RunLoop.main.run()
