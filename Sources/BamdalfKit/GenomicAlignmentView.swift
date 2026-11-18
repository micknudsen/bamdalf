import AppKit

@MainActor
final class GenomicAlignmentView: NSView {
    static let rowHeight: CGFloat = 18
    var presentation = ViewerPresentation() {
        didSet {
            prepareDifferences(previous: oldValue)
            needsDisplay = true
        }
    }
    private var differences: [UInt64: [Int64: [BaseDifference]]] = [:]
    var canNavigate: (() -> Bool)?
    var beginDrag: (() -> Void)?
    var previewDrag: ((Double) -> Void)?
    var endDrag: (() -> Void)?
    var zoomAt: ((ZoomDirection, Double) -> Void)?
    private var dragStart: CGFloat?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityLabel("Alignment stack")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func mouseDown(with event: NSEvent) {
        guard canNavigate?() == true, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        if event.modifierFlags.contains(.option) {
            zoomAt?(.out, Double(x / bounds.width))
            return
        }
        if event.clickCount == 2 {
            zoomAt?(.in, Double(x / bounds.width))
            return
        }
        dragStart = x
        beginDrag?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard canNavigate?() == true, let start = dragStart, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        previewDrag?(Double((x - start) / bounds.width))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        dragStart = nil
        endDrag?()
    }

    /// Retain comparison cells only for the selected, vertically visible rows of one loaded region.
    /// A fractional drag, scroll, or field edit can reuse cells by their BAM record identity.
    private func prepareDifferences(previous: ViewerPresentation) {
        guard let target = presentation.target, target.referenceScale(in: bounds.width) != nil,
              let region = presentation.referenceBases, region.interval.hasSameReference(as: target) else {
            differences.removeAll()
            return
        }
        let reusable = previous.sessionID == presentation.sessionID && previous.referenceBases == region
        let top = presentation.verticalOffset
        let bottom = top + (enclosingScrollView?.contentSize.height ?? bounds.height)
        var visible: [UInt64: [Int64: [BaseDifference]]] = [:]
        for alignment in presentation.alignments {
            let y = CGFloat(alignment.row) * Self.rowHeight + 3
            guard y + 12 >= top, y <= bottom else { continue }
            visible[alignment.id] = (reusable ? differences[alignment.id] : nil) ?? alignment.differences(in: region)
        }
        differences = visible
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        guard let target = presentation.target else { return }
        let scale = bounds.width / CGFloat(target.end - target.start + 1)
        for alignment in presentation.alignments {
            let y = CGFloat(alignment.row) * Self.rowHeight + 3
            guard y + 12 >= dirtyRect.minY, y <= dirtyRect.maxY else { continue }
            let isBlock: (AlignmentSegment) -> Bool = { $0.kind == .aligned || $0.kind == .softClip }
            let point = alignment.isReverse ? alignment.segments.firstIndex(where: isBlock) : alignment.segments.lastIndex(where: isBlock)
            for (index, segment) in alignment.segments.enumerated() {
                let x = CGFloat(Double(segment.start - target.start) - presentation.previewOffsetInBases) * scale
                let width = CGFloat(segment.end - segment.start) * scale
                switch segment.kind {
                case .aligned:
                    let rect = NSRect(x: x, y: y, width: width, height: 12)
                    if segment.sequence == nil && presentation.referenceURL != nil {
                        Self.drawOutline(in: rect, pointed: index == point, reverse: alignment.isReverse)
                        continue
                    }
                    NSColor.labelColor.setFill()
                    let body = Self.bodyPath(in: rect, pointed: index == point, reverse: alignment.isReverse)
                    body.fill()
                    if scale >= 1, let cells = differences[alignment.id]?[segment.start] {
                        NSGraphicsContext.saveGraphicsState()
                        body.addClip()
                        for cell in cells {
                            let offset = CGFloat(cell.position - segment.start) * scale
                            let cellRect = NSRect(x: x + offset, y: y, width: scale, height: 12)
                            if cellRect.intersects(dirtyRect) {
                                NucleotideCell.draw(cell.base, in: cellRect, indeterminate: cell.isIndeterminate)
                            }
                        }
                        NSGraphicsContext.restoreGraphicsState()
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
                    NSBezierPath(rect: NSRect(x: CGFloat(Double(alignment.drawnStart - target.start) - presentation.previewOffsetInBases) * scale,
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
                        NSGraphicsContext.saveGraphicsState()
                        if index == point {
                            Self.bodyPath(in: NSRect(x: x, y: y, width: width, height: 12),
                                          pointed: true, reverse: alignment.isReverse).addClip()
                        }
                        let bases = Array(sequence.utf8)
                        let first = max(0, min(bases.count, Int(floor((dirtyRect.minX - x) / scale))))
                        let last = max(first, min(bases.count, Int(ceil((dirtyRect.maxX - x) / scale))))
                        for baseIndex in first..<last {
                            let rect = NSRect(x: x + CGFloat(baseIndex) * scale, y: y, width: scale, height: 12)
                            NucleotideCell.draw(bases[baseIndex], in: rect)
                        }
                        NSGraphicsContext.restoreGraphicsState()
                    } else {
                        Self.drawOutline(in: NSRect(x: x, y: y, width: width, height: 12),
                                         pointed: index == point, reverse: alignment.isReverse)
                    }
                }
            }
        }
    }

    private static func drawOutline(in rect: NSRect, pointed: Bool, reverse: Bool) {
        NSColor.labelColor.setStroke()
        let outline = bodyPath(in: rect.insetBy(dx: 0, dy: 0.5), pointed: pointed, reverse: reverse)
        outline.lineWidth = 1
        outline.stroke()
    }

    private static func bodyPath(in rect: NSRect, pointed: Bool, reverse: Bool) -> NSBezierPath {
        guard pointed else { return NSBezierPath(rect: rect) }
        let tip = min(4, rect.width / 2)
        let path = NSBezierPath()
        if reverse {
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
        return path
    }

}
