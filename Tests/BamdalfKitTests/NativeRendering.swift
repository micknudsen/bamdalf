import AppKit
import Testing

/// Draw the first two alignment rows through the actual native renderer.
@MainActor
func renderAlignmentBitmap(in view: NSView, window: NSWindow) throws -> NSBitmapImageRep {
    try renderTrackBitmap(in: view, window: window, height: 40)
}

@MainActor
func renderTrackBitmap(in view: NSView, window: NSWindow, height: Int) throws -> NSBitmapImageRep {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: height,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    let cg = context.cgContext
    if view.isFlipped {
        cg.translateBy(x: 0, y: CGFloat(height))
        cg.scaleBy(x: 1, y: -1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: view.isFlipped)
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
        view.draw(NSRect(x: 0, y: 0, width: view.bounds.width, height: CGFloat(height)))
    }
    cg.flush()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
