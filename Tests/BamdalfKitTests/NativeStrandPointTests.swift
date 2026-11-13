import AppKit
import Testing
@testable import BamdalfKit

@Suite(.serialized)
struct NativeStrandPointTests {
    @Test(arguments: [false, true], [false, true])
    @MainActor
    func strandPointFollowsFullReadEnd(isReverse: Bool, missingSequence: Bool) throws {
        _ = NSApplication.shared
        let view = GenomicAlignmentView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: .aqua)
        defer { window.close() }
        view.presentation.target = GenomicInterval(reference: "tiny", start: 1, end: 24)
        view.presentation.alignments = [Alignment(
            id: 1, name: "clipped", readGroup: nil, cigar: "4S8M4S", isReverse: isReverse,
            referenceStart: 9, referenceEnd: 16,
            segments: [
                AlignmentSegment(kind: .softClip, start: 5, end: 9, sequence: missingSequence ? nil : "AAAA"),
                AlignmentSegment(kind: .aligned, start: 9, end: 17, sequence: nil),
                AlignmentSegment(kind: .softClip, start: 17, end: 21, sequence: missingSequence ? nil : "AAAA"),
            ]
        )]
        let bitmap = try renderAlignmentBitmap(in: view, window: window)
        func color(_ x: Int, _ y: Int) throws -> NSColor {
            try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        }
        // The corner is cut away only at the full read end, 40 pixels beyond
        // the mapped body. Sampling away from letters also checks base color.
        let corner = try color(isReverse ? 40 : 199, 3)
        #expect(min(corner.redComponent, corner.greenComponent, corner.blueComponent) > 0.95,
                "The strand point must reach the outer soft-clipped end")
        let mappedCorner = try color(isReverse ? 80 : 159, 3)
        #expect(max(mappedCorner.redComponent, mappedCorner.greenComponent, mappedCorner.blueComponent) < 0.2,
                "The mapped/soft-clip boundary must remain square")
        if !missingSequence {
            let tip = try color(isReverse ? 41 : 198, 9)
            #expect(tip.greenComponent > tip.redComponent && tip.greenComponent > tip.blueComponent,
                    "The pointed soft clip must retain its nucleotide color")
        }
    }
}
