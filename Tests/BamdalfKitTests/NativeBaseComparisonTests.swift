import AppKit
import BamdalfKit
import Testing

@MainActor
@Suite(.serialized)
struct NativeBaseComparisonTests {
    @Test(arguments: [false, true])
    func mixedCIGARComparesStoredBasesAtTheirAlignedCoordinates(dark: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await ComparisonWindow(files: files, dark: dark)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:1-77")
        try #require(viewer.stack.bounds.width == 608)
        let before = viewer.session.presentation
        try #require(Set(before.alignments.map(\.name)) == ["forward", "reverse", "absentForward", "absentReverse"])
        let baseline = try viewer.capture()
        try await viewer.attachReference(files)
        let applied = viewer.session.presentation
        #expect(applied.alignments == before.alignments && applied.rowCount == before.rowCount)
        let bitmap = try viewer.capture()
        for alignment in applied.alignments where alignment.referenceStart == 11 {
            let y = alignment.row * 18 + 7
            func x(_ position: Int) -> Int { Int((Double(position) - 0.5) * 608 / 77) }
            let body = try #require(baseline.colorAt(x: x(11), y: y))
            let background = try #require(baseline.colorAt(x: x(1), y: y))
            // Symbols are pixel expectations in reference order: '.' body, '-' gap,
            // '?' neutral, and a nucleotide the color of the stored aligned base.
            let expected = alignment.isReverse ? "?AG.?CTAT-----??A." : "?C..?C..T-----??A."
            for (offset, ink) in expected.enumerated() {
                let pos = 9 + offset
                let color = try #require(bitmap.colorAt(x: x(pos), y: y))
                let reason = Comment(rawValue: "\(alignment.name) at \(pos), expecting \(ink)")
                if ink == "." { #expect(color == body, reason) }
                else if ink == "-" { #expect(color == background, reason) }
                else { #expect(try hasInk(ink, color), reason) }
            }
        }
        viewer.session.closeReference()
        let closed = try viewer.capture()
        #expect(closed.representation(using: .png, properties: [:]) == baseline.representation(using: .png, properties: [:]))
    }
    @Test(arguments: [false, true])
    func cellsAndLettersFollowTheSharedZoomThresholdsAndFractionalDrag(dark: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await ComparisonWindow(files: files, dark: dark)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:1-609")
        let bamOnly = try viewer.capture()
        try await viewer.attachReference(files)
        let overview = try viewer.capture()
        let row = try #require(viewer.session.presentation.alignments.first { $0.name == "forward" }).row * 18
        #expect(viewer.session.presentation.referenceBases == nil)
        for x in 8..<27 {
            #expect(overview.colorAt(x: x, y: row + 8) == bamOnly.colorAt(x: x, y: row + 8))
        }
        await viewer.navigate("tiny:1-608")
        let unit = try viewer.capture()
        #expect(try hasInk("?", #require(unit.colorAt(x: 23, y: row + 8))))
        #expect(try hasInk("A", #require(unit.colorAt(x: 24, y: row + 8))))
        #expect(unit.colorAt(x: 25, y: row + 8) == unit.colorAt(x: 10, y: row + 8))

        await viewer.navigate("tiny:1-77")
        let cells = try viewer.capture()
        let insideA = 193 // Center of the mismatching A at position 25.
        let fill = try #require(cells.colorAt(x: insideA, y: row + 7))
        #expect(try hasInk("A", fill))
        #expect((3..<15).allSatisfy { cells.colorAt(x: insideA, y: row + $0) == fill })

        await viewer.navigate("tiny:1-76") // Eight points per base, exactly.
        let letters = try viewer.capture()
        func glyph(_ position: Int) -> [NSColor?] {
            (3..<15).flatMap { y in (0..<8).map { letters.colorAt(x: (position - 1) * 8 + $0, y: row + y) } }
        }
        #expect(glyph(9) == glyph(23), "A soft-clipped = and an indeterminate aligned = show the same literal symbol")
        #expect(glyph(23) != glyph(24), "Indeterminate = and G have different glyphs on neutral gray")
        #expect(glyph(25).contains { $0 != fill }, "The mismatching A gains its letter at eight points")

        viewer.session.beginAlignmentDrag()
        await viewer.session.previewAlignmentDrag(horizontalFraction: -0.4 / 76)?.value
        let moved = try viewer.capture()
        #expect(try hasInk("?", #require(letters.colorAt(x: 190, y: row + 14))))
        #expect(try hasInk("A", #require(moved.colorAt(x: 190, y: row + 14))))
        await viewer.session.endAlignmentDrag()?.value
    }

    @Test(arguments: [false, true])
    func missingSequenceKeepsItsStrandPointAndUnfilledCIGARGeometry(dark: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await ComparisonWindow(files: files, dark: dark)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:45-64")
        let filled = try viewer.capture()
        try await viewer.attachReference(files)
        let outline = try viewer.capture()
        for record in viewer.session.presentation.alignments {
            let top = record.row * 18 + 3
            func x(_ position: Int) -> Int { Int((Double(position - 45) + 0.5) * 608 / 20) }
            let background = try #require(outline.colorAt(x: 1, y: top + 6))
            let body = try #require(filled.colorAt(x: x(51), y: top + 6))
            try #require(background != body)
            // 51–52 body, insertion at 53, 53–54 body, 55 deletion, 56–57 skip, 58–59 body.
            for pos in [51, 52, 53, 54, 58, 59] {
                #expect(outline.colorAt(x: x(pos), y: top + 6) == background)
                #expect(outline.colorAt(x: x(pos), y: top) == body)
            }
            for pos in [55, 56, 57] {
                #expect(outline.colorAt(x: x(pos), y: top) == background)
                #expect(outline.colorAt(x: x(pos), y: top + 6) == filled.colorAt(x: x(pos), y: top + 6))
            }
            let pointedCorner = record.isReverse ? 183 : 454
            let squareCorner = record.isReverse ? 454 : 183
            #expect(outline.colorAt(x: pointedCorner, y: top) == background)
            #expect(outline.colorAt(x: squareCorner, y: top) == body)
            let insertion = Int(8.0 * 608 / 20) // Leading edge of base 53.
            #expect(outline.colorAt(x: insertion - 1, y: top + 6) != background)
        }
    }

}

@MainActor
private struct ComparisonWindow {
    let session: ViewerSession
    let controller: ViewerWindowController
    let window: NSWindow
    let stack: NSView

    init(files: FixtureFiles, dark: Bool) async throws {
        _ = NSApplication.shared
        session = try await files.openedSession(fixture: "comparison")
        controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        window = try #require(controller.window)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 640, height: 480))
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        scroll.scrollerStyle = .overlay
        workspace.layoutSubtreeIfNeeded()
        stack = try #require(scroll.documentView)
        await session.setViewportWidth(stack.bounds.width)?.value
    }

    func navigate(_ interval: String) async {
        session.editInterval(interval)
        await session.submitInterval()?.value
    }

    func attachReference(_ files: FixtureFiles) async throws {
        // Positions 11–17 = acAtgta, 18–22 are consumed by D and N,
        // and the final four aligned positions 23–26 = Nrtc.
        let prefix = "AAAAAAAAAAacAtgtagggggNrtc"
        let url = try files.reference("test.bref", fasta: ">tiny\n" + prefix + String(repeating: "a", count: 20_000 - prefix.count))
        await session.openReference(url)
        try #require(session.presentation.referenceURL == url)
    }

    func capture() throws -> NSBitmapImageRep { try renderAlignmentBitmap(in: stack, window: window) }
}

private func hasInk(_ ink: Character, _ color: NSColor) throws -> Bool {
    let rgb = try #require(color.usingColorSpace(.deviceRGB))
    let (r, g, b) = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    switch ink {
    case "A": return g > r + 0.15 && g > b + 0.1
    case "C": return b > r + 0.3 && b > g + 0.2
    case "G": return r > 0.75 && g > 0.55 && b < 0.45
    case "T": return r > g + 0.3 && r > b + 0.3
    case "?": return abs(r - g) < 0.03 && abs(r - b) < 0.03 && (0.4...0.8).contains(r)
    default: return false
    }
}
