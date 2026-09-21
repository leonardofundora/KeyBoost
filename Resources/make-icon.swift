import AppKit

// ─── helpers ───────────────────────────────────────────────────────────────────

func rr(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

func grad(_ c: [NSColor]) -> NSGradient { NSGradient(colors: c)! }

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
    NSRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
           width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
}

func lerp(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let x = a.usingColorSpace(.sRGB)!, y = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: lerp(x.redComponent, y.redComponent, t),
                   green: lerp(x.greenComponent, y.greenComponent, t),
                   blue: lerp(x.blueComponent, y.blueComponent, t), alpha: 1)
}

func shadow(_ alpha: CGFloat, _ blur: CGFloat, _ dy: CGFloat) {
    let s = NSShadow()
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.set()
}

/// The bolt, filled with a gradient rather than flat colour.
func bolt(size: CGFloat, gradient: NSGradient) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .heavy)
    guard let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return nil }
    let out = NSImage(size: symbol.size)
    let rect = NSRect(origin: .zero, size: symbol.size)
    out.lockFocus()
    gradient.draw(in: rect, angle: -90)
    symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
    out.unlockFocus()
    return out
}

// ─── the icon ──────────────────────────────────────────────────────────────────

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let detailed = px >= 64                 // por debajo, el keycap solo ensucia

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    defer { NSGraphicsContext.restoreGraphicsState() }

    let side = s * 0.804
    let box = NSRect(x: (s - side) / 2, y: (s - side) / 2, width: side, height: side)
    let squircle = rr(box, side * 0.2245)

    // The icon's own drop shadow.
    NSGraphicsContext.saveGraphicsState()
    shadow(0.30, side * 0.055, -side * 0.022)
    NSColor.black.setFill(); squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()

    // Background: violet at the top, electric blue at the bottom.
    grad([rgb(92, 82, 238), rgb(24, 96, 240)]).draw(in: box, angle: -90)
    // Highlight towards the upper left.
    grad([rgb(158, 196, 255, 0.50), rgb(158, 196, 255, 0)])
        .draw(fromCenter: NSPoint(x: box.minX + box.width * 0.24, y: box.maxY - box.height * 0.18),
              radius: 0,
              toCenter: NSPoint(x: box.minX + box.width * 0.24, y: box.maxY - box.height * 0.18),
              radius: box.width * 0.78, options: [])
    // Vignette along the bottom.
    grad([rgb(6, 14, 64, 0), rgb(6, 14, 64, 0.34)])
        .draw(in: NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.58), angle: -90)

    if detailed {
        // Keycap geometry: the base is wider than the top face, which gives the tapered wall.
        let baseW = box.width * 0.600
        let baseH = baseW * 0.930
        let rise  = baseH * 0.235                      // altura de la extrusión
        let taper: CGFloat = 0.150                     // cuánto se estrecha al subir
        let cx = box.midX
        let baseY = box.midY - baseH * 0.60

        let base = NSRect(x: cx - baseW/2, y: baseY, width: baseW, height: baseH)
        let face = NSRect(x: cx - baseW*(1-taper)/2, y: baseY + rise,
                          width: baseW*(1-taper), height: baseH*(1-taper))
        let rBase = baseW * 0.190, rFace = face.width * 0.190

        // Glow behind the key.
        grad([rgb(190, 220, 255, 0.45), rgb(190, 220, 255, 0)])
            .draw(fromCenter: NSPoint(x: cx, y: box.midY), radius: 0,
                  toCenter: NSPoint(x: cx, y: box.midY), radius: box.width * 0.44, options: [])

        // Contact shadow under the key.
        NSGraphicsContext.saveGraphicsState()
        shadow(0.42, baseW * 0.16, -baseW * 0.075)
        rgb(20, 30, 90).setFill()
        rr(base, rBase).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Side wall: interpolated from base to face in fine steps. This is what turns two
        // stacked rectangles into something that reads as an actual key.
        let steps = max(24, px / 12)
        let wallLow = rgb(64, 76, 142), wallHigh = rgb(176, 188, 228)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let r = lerp(base, face, t)
            lerp(wallLow, wallHigh, pow(t, 0.75)).setFill()
            rr(r, lerp(rBase, rFace, t)).fill()
        }

        // Top face.
        let facePath = rr(face, rFace)
        grad([rgb(252, 253, 255), rgb(209, 219, 242)]).draw(in: facePath, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        facePath.addClip()
        // Light catching the top edge.
        grad([rgb(255, 255, 255, 1), rgb(255, 255, 255, 0)])
            .draw(in: NSRect(x: face.minX, y: face.maxY - face.height * 0.26,
                             width: face.width, height: face.height * 0.26), angle: -90)
        // Concavity: a soft shadow along the bottom edge, like a sculpted keycap.
        grad([rgb(108, 122, 176, 0.38), rgb(108, 122, 176, 0)])
            .draw(in: NSRect(x: face.minX, y: face.minY,
                             width: face.width, height: face.height * 0.30), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Bright rim around the top face.
        rgb(255, 255, 255, 0.85).setStroke()
        facePath.lineWidth = max(1, side * 0.006)
        facePath.stroke()

        // The bolt.
        if let b = bolt(size: face.height * 0.60, gradient: grad([rgb(104, 92, 244), rgb(26, 102, 242)])) {
            let origin = NSPoint(x: face.midX - b.size.width/2, y: face.midY - b.size.height/2)
            NSGraphicsContext.saveGraphicsState()
            shadow(0.22, face.height * 0.04, -face.height * 0.014)
            b.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    } else {
        // Small sizes: just the bolt, large and high contrast.
        if let b = bolt(size: side * 0.72, gradient: grad([rgb(255, 255, 255), rgb(224, 234, 255)])) {
            let origin = NSPoint(x: box.midX - b.size.width/2, y: box.midY - b.size.height/2)
            NSGraphicsContext.saveGraphicsState()
            shadow(0.32, side * 0.05, -side * 0.02)
            b.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // A discreet light rim around the icon's edge.
    let rim = rr(box.insetBy(dx: side * 0.005, dy: side * 0.005), side * 0.2245)
    rim.lineWidth = max(1, side * 0.009)
    rgb(255, 255, 255, 0.30).setStroke()
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (base, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! render(base * scale).write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}
print("iconset written")
