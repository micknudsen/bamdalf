import AppKit
import BamdalfKit
import Testing

@MainActor
struct NativePairedSourceTests {
    @Test(.timeLimit(.minutes(1))) func referenceCellsAndBAMGeometryShareCoordinatesAsRealRowsScroll() async throws {
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
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        workspace.layoutSubtreeIfNeeded()
        let fixedRow = row.convert(row.bounds, to: nil)
        let fixedRuler = ruler.convert(ruler.bounds, to: nil)
        let firstAlignment = stack.convert(NSPoint.zero, to: nil)
        #expect(fixedRow.minX == firstAlignment.x && row.bounds.width == stack.bounds.width)
        #expect(fixedRow.maxY <= fixedRuler.minY && fixedRow.minY >= scroll.convert(scroll.bounds, to: nil).maxY)
        try #require(row.bounds.width == 608 && stack.bounds.height > scroll.contentSize.height + 180)
        let before = try renderAlignmentBitmap(in: row, window: window)
        let geometry = try renderAlignmentBitmap(in: stack, window: window)
        // Four points per base. At base 101 the reference changes A to C and the soft clip meets the body.
        #expect(before.colorAt(x: 78, y: 7) != before.colorAt(x: 82, y: 7))
        #expect(geometry.colorAt(x: 78, y: 7) != geometry.colorAt(x: 82, y: 7))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(session.presentation.verticalOffset == 180)
        #expect(abs(stack.convert(NSPoint.zero, to: nil).y - firstAlignment.y) == 180)
        #expect(row.convert(row.bounds, to: nil) == fixedRow && ruler.convert(ruler.bounds, to: nil) == fixedRuler)
        let after = try renderAlignmentBitmap(in: row, window: window)
        #expect(after.colorAt(x: 78, y: 7) == before.colorAt(x: 78, y: 7))
        #expect(after.colorAt(x: 82, y: 7) == before.colorAt(x: 82, y: 7))
    }
}
