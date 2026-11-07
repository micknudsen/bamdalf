import AppKit
import Testing

/// Draw the first two alignment rows through the actual native renderer.
@MainActor
func renderAlignmentBitmap(in view: NSView, window: NSWindow) throws -> NSBitmapImageRep {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: 40,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    let cg = context.cgContext
    cg.translateBy(x: 0, y: 40)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
        view.draw(NSRect(x: 0, y: 0, width: view.bounds.width, height: 40))
    }
    cg.flush()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
