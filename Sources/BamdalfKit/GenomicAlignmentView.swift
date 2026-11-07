import AppKit

@MainActor
final class GenomicAlignmentView: NSView {
    static let rowHeight: CGFloat = 18
    var presentation = ViewerPresentation() { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Alignment stack")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard let target = presentation.target else { return }
        let scale = bounds.width / CGFloat(target.end - target.start + 1)
        for alignment in presentation.alignments {
            let y = CGFloat(alignment.row) * Self.rowHeight + 3
            guard y + 12 >= dirtyRect.minY, y <= dirtyRect.maxY else { continue }
            let blocks = alignment.segments.filter { $0.kind == .aligned }
            let point = alignment.isReverse ? blocks.first : blocks.last
            for segment in alignment.segments {
                let x = CGFloat(segment.start - target.start) * scale
                let width = CGFloat(segment.end - segment.start) * scale
                switch segment.kind {
                case .aligned:
                    let rect = NSRect(x: x, y: y, width: width, height: 12)
                    NSColor.labelColor.setFill()
                    if segment == point {
                        let tip = min(4, width / 2)
                        let path = NSBezierPath()
                        if alignment.isReverse {
                            path.move(to: NSPoint(x: rect.minX, y: rect.midY))
                            path.line(to: NSPoint(x: rect.minX + tip, y: rect.minY))
                            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
                            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                            path.line(to: NSPoint(x: rect.minX + tip, y: rect.maxY))
                        } else {
                            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
                            path.line(to: NSPoint(x: rect.maxX - tip, y: rect.minY))
                            path.line(to: NSPoint(x: rect.maxX, y: rect.midY))
                            path.line(to: NSPoint(x: rect.maxX - tip, y: rect.maxY))
                            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
                        }
                        path.close()
                        path.fill()
                    } else {
                        rect.fill()
                    }
                case .deletion, .skip:
                    (segment.kind == .deletion ? NSColor.labelColor : NSColor(calibratedRed: 0.40, green: 0.50, blue: 0.62, alpha: 1)).setStroke()
                    let path = NSBezierPath()
                    path.lineWidth = 1
                    path.move(to: NSPoint(x: x, y: y + 6))
                    path.line(to: NSPoint(x: x + width, y: y + 6))
                    path.stroke()
                case .insertion:
                    // Clip decoration to this record's full drawn extent. It
                    // cannot widen the genomic axis or force retained rows apart.
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(rect: NSRect(x: CGFloat(alignment.drawnStart - target.start) * scale,
                                              y: y - 1, width: CGFloat(alignment.drawnEnd - alignment.drawnStart + 1) * scale,
                                              height: 14)).addClip()
                    NSColor.systemPurple.setStroke()
                    let path = NSBezierPath()
                    path.lineWidth = 1.5
                    path.move(to: NSPoint(x: x, y: y))
                    path.line(to: NSPoint(x: x, y: y + 12))
                    for edge in [y, y + 12] {
                        path.move(to: NSPoint(x: x - 2, y: edge))
                        path.line(to: NSPoint(x: x + 2, y: edge))
                    }
                    path.stroke()
                    NSGraphicsContext.restoreGraphicsState()
                case .softClip:
                    if let sequence = segment.sequence {
                        let bases = Array(sequence.utf8)
                        let first = max(0, min(bases.count, Int(floor((dirtyRect.minX - x) / scale))))
                        let last = max(first, min(bases.count, Int(ceil((dirtyRect.maxX - x) / scale))))
                        for index in first..<last {
                            let rect = NSRect(x: x + CGFloat(index) * scale, y: y, width: scale, height: 12)
                            let (background, foreground) = Self.palette(bases[index])
                            background.setFill()
                            rect.fill()
                            if scale >= 8 {
                                let text = String(UnicodeScalar(bases[index])) as NSString
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                                    .foregroundColor: foreground,
                                ]
                                let size = text.size(withAttributes: attributes)
                                text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
                            }
                        }
                    } else {
                        NSColor.labelColor.setStroke()
                        let outline = NSBezierPath(rect: NSRect(x: x, y: y + 0.5, width: width, height: 11))
                        outline.lineWidth = 1
                        outline.stroke()
                    }
                }
            }
        }
    }

    private static func palette(_ base: UInt8) -> (NSColor, NSColor) {
        switch base {
        case 65: (NSColor(calibratedRed: 0.26, green: 0.65, blue: 0.38, alpha: 1), .black)
        case 67: (NSColor(calibratedRed: 0.20, green: 0.43, blue: 0.85, alpha: 1), .white)
        case 71: (NSColor(calibratedRed: 0.95, green: 0.79, blue: 0.21, alpha: 1), .black)
        case 84: (NSColor(calibratedRed: 0.84, green: 0.25, blue: 0.28, alpha: 1), .white)
        default: (NSColor(calibratedWhite: 0.60, alpha: 1), .black)
        }
    }
}
