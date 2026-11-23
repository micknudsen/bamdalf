import AppKit

/// Position on the shared horizontal axis, including a live drag's fractional offset.
struct InspectedColumn {
    private let leading: CGFloat
    private let trailing: CGFloat

    init?(_ position: GenomicInterval?, in presentation: ViewerPresentation) {
        guard let position, let target = presentation.target, target.hasSameReference(as: position) else { return nil }
        let offset = CGFloat(position.start - target.start) - presentation.previewOffsetInBases
        let span = CGFloat(target.end - target.start + 1)
        guard offset < span, offset + 1 > 0 else { return nil }
        leading = offset / span
        trailing = (offset + 1) / span
    }

    func center(in width: CGFloat) -> CGFloat {
        min(width, max(0, (leading + trailing) * width / 2))
    }

    @MainActor
    func drawOutline(in bounds: NSRect, behindBases: Bool) {
        let left = leading * bounds.width
        let right = trailing * bounds.width
        // At narrow scales, paint under the cells so the neighboring mismatch colors survive.
        guard behindBases == (right - left < 4) else { return }
        NSColor.controlAccentColor.setFill()
        for x in [left, max(left, right - 1)] {
            NSRect(x: x, y: bounds.minY, width: 1, height: bounds.height).fill()
        }
    }
}
