import AppKit
import CoreText

@MainActor
enum NucleotideCell {
    private static let green = NSColor(calibratedRed: 0.26, green: 0.65, blue: 0.38, alpha: 1)
    private static let blue = NSColor(calibratedRed: 0.20, green: 0.43, blue: 0.85, alpha: 1)
    private static let yellow = NSColor(calibratedRed: 0.95, green: 0.79, blue: 0.21, alpha: 1)
    private static let red = NSColor(calibratedRed: 0.84, green: 0.25, blue: 0.28, alpha: 1)
    private static let gray = NSColor(calibratedWhite: 0.60, alpha: 1)

    private struct Glyph {
        let line: CTLine
        let width: CGFloat
        let baseline: CGFloat

        init(_ base: UInt8) {
            let text = NSAttributedString(string: String(UnicodeScalar(base)), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ])
            line = CTLineCreateWithAttributedString(text)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            baseline = (ascent - descent) / 2
        }
    }

    // Layout a stored symbol once, including lowercase and literal '='. Reuse its
    // vector glyph at the actual display scale and subpixel position.
    private static var glyphs: [UInt8: Glyph] = [:]

    static func draw(_ base: UInt8, in rect: NSRect, indeterminate: Bool = false) {
        let (background, foreground) = palette(indeterminate ? nil : CanonicalBase(base))
        background.setFill()
        rect.fill()
        guard rect.width >= 8, let context = NSGraphicsContext.current?.cgContext else { return }
        let glyph: Glyph
        if let cached = glyphs[base] {
            glyph = cached
        } else {
            glyph = Glyph(base)
            glyphs[base] = glyph
        }
        foreground.setFill()
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: rect.midX - glyph.width / 2, y: rect.midY + glyph.baseline)
        CTLineDraw(glyph.line, context)
        context.restoreGState()
    }

    private static func palette(_ base: CanonicalBase?) -> (NSColor, NSColor) {
        switch base {
        case .a: (green, .black)
        case .c: (blue, .white)
        case .g: (yellow, .black)
        case .t: (red, .white)
        case nil: (gray, .black)
        }
    }
}

@MainActor
final class GenomicReferenceView: NSView {
    var presentation = ViewerPresentation() { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Reference sequence")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard let target = presentation.target, let region = presentation.referenceBases,
              region.interval.reference.utf8.elementsEqual(target.reference.utf8) else { return }
        guard let scale = target.referenceScale(in: bounds.width) else { return }
        for (index, base) in region.bases.enumerated() {
            let offset = Double(region.interval.start + Int64(index) - target.start) - presentation.previewOffsetInBases
            let rect = NSRect(x: offset * scale, y: 3, width: scale, height: 12)
            if dirtyRect.intersects(rect) { NucleotideCell.draw(base, in: rect) }
        }
    }
}
