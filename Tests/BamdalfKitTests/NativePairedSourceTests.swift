import AppKit
import BamdalfKit
import Testing

@MainActor
struct NativePairedSourceTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func referenceCellsAndBAMGeometryShareCoordinatesAsRealRowsScroll(legacyScroller: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let reference = try files.reference("assembly.bref", fasta: ">tiny\n" + String(repeating: "A", count: 100)
            + String(repeating: "C", count: 19_900))
        let session = try await files.openedSession(fixture: "rows")
        let (opened, signal) = AsyncStream<Void>.makeStream()
        let controller = ViewerWindowController(session: session) { _, _, choose in choose(reference) }
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        window.setContentSize(NSSize(width: 640, height: 480))
        window.appearance = NSAppearance(named: .aqua)
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        scroll.scrollerStyle = legacyScroller ? .legacy : .overlay
        session.editInterval("tiny:81-232")
        await session.submitInterval()?.value
        let menu = controller.makeFileMenu()
        let open = try #require(menu.item(withTitle: "Open Reference…"))
        try #require(controller.validateMenuItem(open))
        let render = session.onPresentationChange
        session.onPresentationChange = {
            render?()
            if session.presentation.referenceBases != nil { signal.yield() }
        }
        menu.performActionForItem(at: menu.index(of: open))
        var events = opened.makeAsyncIterator()
        _ = await events.next()
        session.onPresentationChange = render
        let bam = try #require(menu.item(withTitle: "Open BAM…"))
        #expect(controller.validateMenuItem(bam))
        try #require(session.presentation.rowCount == 80)
        let ruler = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Genomic ruler" })
        let row = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Reference sequence" })
        let stack = try #require(scroll.documentView)
        workspace.layoutSubtreeIfNeeded()
        let fixedRow = row.convert(row.bounds, to: nil)
        let fixedRuler = ruler.convert(ruler.bounds, to: nil)
        let firstAlignment = stack.convert(NSPoint.zero, to: nil)
        #expect(fixedRow.minX == firstAlignment.x)
        #expect(row.bounds.width == stack.bounds.width)
        #expect(stack.bounds.width == scroll.contentView.bounds.width)
        #expect(fixedRow.maxY <= fixedRuler.minY && fixedRow.minY >= scroll.convert(scroll.bounds, to: nil).maxY)
        try #require(stack.bounds.height > scroll.contentSize.height + 180)
        let before = try renderAlignmentBitmap(in: row, window: window)
        let geometry = try renderAlignmentBitmap(in: stack, window: window)
        let base101 = Int(ceil(20 * row.bounds.width / 152))
        // At base 101 the reference changes A to C and the soft clip meets the body.
        #expect(before.colorAt(x: base101 - 2, y: 7) != before.colorAt(x: base101 + 2, y: 7))
        #expect(geometry.colorAt(x: base101 - 2, y: 7) != geometry.colorAt(x: base101 + 2, y: 7))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(session.presentation.verticalOffset == 180)
        #expect(abs(stack.convert(NSPoint.zero, to: nil).y - firstAlignment.y) == 180)
        #expect(row.convert(row.bounds, to: nil) == fixedRow && ruler.convert(ruler.bounds, to: nil) == fixedRuler)
        let after = try renderAlignmentBitmap(in: row, window: window)
        #expect(after.colorAt(x: base101 - 2, y: 7) == before.colorAt(x: base101 - 2, y: 7))
        #expect(after.colorAt(x: base101 + 2, y: 7) == before.colorAt(x: base101 + 2, y: 7))
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        #expect(spinner.accessibilityLabel() == "Loading genomic interval")
    }
}
