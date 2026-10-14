// Scriptorium app icons.  swift design/make_icons.swift <outdir>
// ā (Latin) and ἀ (Greek) in Cardo (David Perry, SIL OFL 1.1 — a typeface made for
// classical scholarship), cream on Tyrian purple, divided by a gold rule.
import AppKit

let cream = NSColor(srgbRed: 0.965, green: 0.918, blue: 0.812, alpha: 1)
let gold = NSColor(srgbRed: 0.851, green: 0.690, blue: 0.396, alpha: 1)
let top = NSColor(srgbRed: 0.435, green: 0.122, blue: 0.282, alpha: 1)      // Tyrian purple
let bottom = NSColor(srgbRed: 0.180, green: 0.043, blue: 0.118, alpha: 1)   // ink

func artwork(in r: NSRect) {
    // background
    NSGradient(starting: top, ending: bottom)!.draw(in: r, angle: -90)
    // soft vignette light from the top
    let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.13), NSColor.white.withAlphaComponent(0)])!
    glow.draw(fromCenter: NSPoint(x: r.midX, y: r.maxY - r.height * 0.18), radius: 0,
              toCenter: NSPoint(x: r.midX, y: r.maxY - r.height * 0.18), radius: r.width * 0.75, options: [])

    let s = r.width
    let font = NSFont(name: "Cardo", size: s * 0.52) ?? NSFont(name: "Cardo-Regular", size: s * 0.52)!
    let baseline = r.minY + s * 0.30                      // optical centre of x-height + marks
    func glyph(_ t: String, centerX: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        shadow.shadowBlurRadius = s * 0.015
        let a = NSAttributedString(string: t, attributes: [.font: font, .foregroundColor: cream, .shadow: shadow])
        let w = a.size().width
        a.draw(at: NSPoint(x: r.minX + centerX - w / 2, y: baseline + font.descender))
    }
    glyph("ā", centerX: s * 0.29)
    glyph("ἀ", centerX: s * 0.71)

    // gold rule between them, with a small rubricated interpunct
    gold.setFill()
    let ruleY = baseline - s * 0.055
    NSBezierPath(rect: NSRect(x: r.minX + s * 0.4975, y: ruleY, width: s * 0.005, height: s * 0.44)).fill()
    // ruled manuscript line just under both letters, with an interpunct where the rules meet
    NSBezierPath(rect: NSRect(x: r.minX + s * 0.13, y: ruleY, width: s * 0.74, height: s * 0.005)).fill()
    let d = s * 0.03
    NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: ruleY + s * 0.0025 - d / 2, width: d, height: d)).fill()
}

func render(_ px: Int, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]

// iOS: full-bleed square, opaque (the system applies the mask)
save(render(1024) { r in artwork(in: r) }, "\(out)/ios-1024.png")

// macOS: Apple's grid — 824 pt rounded square centred on 1024, with a drop shadow
func macIcon(_ px: Int) -> NSBitmapImageRep {
    render(px) { r in
        let k = r.width / 1024
        let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let path = NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.30)
        sh.shadowOffset = NSSize(width: 0, height: -10 * k)
        sh.shadowBlurRadius = 20 * k
        sh.set()
        bottom.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        artwork(in: body)
        NSGraphicsContext.restoreGraphicsState()
        // hairline inner edge
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5 * k, dy: 1.5 * k), xRadius: 184 * k, yRadius: 184 * k)
        edge.lineWidth = 3 * k
        edge.stroke()
    }
}
for px in [16, 32, 64, 128, 256, 512, 1024] { save(macIcon(px), "\(out)/mac-\(px).png") }
print("ok")
