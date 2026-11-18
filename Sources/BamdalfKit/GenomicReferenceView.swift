import AppKit

@MainActor
enum NucleotideCell {
    static func draw(_ base: UInt8, in rect: NSRect) {
        let (background, foreground) = palette(base)
        background.setFill()
        rect.fill()
        guard rect.width >= 8 else { return }
        let text = String(UnicodeScalar(base)) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: foreground,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }

    private static func palette(_ base: UInt8) -> (NSColor, NSColor) {
        switch base {
        case 65, 97: (NSColor(calibratedRed: 0.26, green: 0.65, blue: 0.38, alpha: 1), .black)
        case 67, 99: (NSColor(calibratedRed: 0.20, green: 0.43, blue: 0.85, alpha: 1), .white)
        case 71, 103: (NSColor(calibratedRed: 0.95, green: 0.79, blue: 0.21, alpha: 1), .black)
        case 84, 116: (NSColor(calibratedRed: 0.84, green: 0.25, blue: 0.28, alpha: 1), .white)
        default: (NSColor(calibratedWhite: 0.60, alpha: 1), .black)
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
