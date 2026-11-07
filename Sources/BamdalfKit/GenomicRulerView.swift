import AppKit

@MainActor
final class GenomicRulerView: NSView {
    var presentation = ViewerPresentation() {
        didSet { needsLayout = true; needsDisplay = true }
    }
    private var renderedTarget: GenomicInterval?
    private var renderedWidth: CGFloat = -1
    private var ticks: [RulerTick] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Genomic ruler")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func layout() {
        super.layout()
        guard renderedTarget != presentation.target || renderedWidth != bounds.width else { return }
        renderedTarget = presentation.target
        renderedWidth = bounds.width
        subviews.forEach { $0.removeFromSuperview() }
        ticks = presentation.rulerTicks(availableWidth: Double(bounds.width))
        guard let target = presentation.target else { return }
        let title = NSTextField(labelWithString: target.formatted)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        title.toolTip = target.formatted
        title.frame = NSRect(x: 0, y: 44, width: bounds.width, height: 18)
        addSubview(title)
        var previousRight: CGFloat = -12
        for tick in ticks {
            let label = NSTextField(labelWithString: tick.label)
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.sizeToFit()
            let center = CGFloat(tick.fraction) * bounds.width
            let x = min(max(0, center - label.frame.width / 2), max(0, bounds.width - label.frame.width))
            guard x >= previousRight + 12 else { continue }
            label.setFrameOrigin(NSPoint(x: x, y: 22))
            addSubview(label)
            previousRight = label.frame.maxX
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard presentation.target != nil else { return }
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.lineWidth = 1
        line.move(to: NSPoint(x: 0, y: 14))
        line.line(to: NSPoint(x: bounds.width, y: 14))
        for tick in ticks {
            let x = CGFloat(tick.fraction) * bounds.width
            line.move(to: NSPoint(x: x, y: 14))
            line.line(to: NSPoint(x: x, y: 20))
        }
        line.stroke()
    }
}
