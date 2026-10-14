// Input-source badges as vector PDFs (16×16 pt): rounded square with the glyph
// cut out as a real hole (path subtraction), so the system can tint it like
// Apple's own badges.   swift design/make_badges.swift <outdir>
import AppKit
import CoreText

func badge(_ glyph: String, size: CGFloat, baseline: CGFloat, to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 16, height: 16)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    let square = CGPath(roundedRect: CGRect(x: 0.5, y: 1, width: 15, height: 14),
                        cornerWidth: 3.2, cornerHeight: 3.2, transform: nil)
    let letter = CGMutablePath()

    // Noto Sans (SIL OFL 1.1): a neutral sans like the system badges, with polytonic Greek
    let base = NSFont(name: "NotoSansSC-Regular", size: size) ?? NSFont(name: "Noto Sans SC", size: size)!
    let wght = 0x77676874  // 'wght' axis of the variable font: semibold, like the system badges
    let desc = base.fontDescriptor.addingAttributes([.variation: [wght: 620]])
    let font = (NSFont(descriptor: desc, size: size) ?? base) as CTFont
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: [.font: font]))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    let origin = CGPoint(x: 8 - width / 2, y: 1 + baseline)
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        for i in 0..<n {
            if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                letter.addPath(g, transform: CGAffineTransform(translationX: origin.x + pos[i].x, y: origin.y + pos[i].y))
            }
        }
    }
    // boolean subtraction: overlapping glyph components (a + macron) don't punch extra holes
    ctx.addPath(square.subtracting(letter.normalized()))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.endPDFPage()
    ctx.closePDF()
}

let out = CommandLine.arguments[1]
badge("ā", size: 12.5, baseline: 2.6, to: URL(fileURLWithPath: "\(out)/la-badge.pdf"))
badge("ἀ", size: 12.0, baseline: 1.6, to: URL(fileURLWithPath: "\(out)/grc-badge.pdf"))
print("ok")
