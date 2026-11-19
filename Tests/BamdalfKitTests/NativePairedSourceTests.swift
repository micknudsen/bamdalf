import AppKit
import BamdalfKit
import Testing

@MainActor
struct NativePairedSourceTests {
    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func openingReferenceKeepsNavigationAndReadsVisible(appearance: NSAppearance.Name) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let reference = try files.reference("rows.bref", fasta: ">tiny\n" + String(repeating: "ACGT", count: 5_000))
        let session = try await files.openedSession(fixture: "rows")
        let controller = ViewerWindowController(session: session)
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: appearance)
        controller.showWindow(nil)
        defer { window.close() }
        session.editInterval("tiny:81-232")
        await session.submitInterval()?.value
        let workspace = try #require(window.contentView)
        let button = try #require(workspace.subviews.compactMap { $0 as? NSButton }.first)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let referenceRow = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Reference sequence" })

        func checkWorkspace(showingReference: Bool) throws {
            workspace.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            // Capture siblings together so a track that overpaints the window is visible to the test.
            let bitmap = try #require(workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds))
            workspace.cacheDisplay(in: workspace.bounds, to: bitmap)
            #expect(hasContrast(in: button.frame, image: bitmap), "Navigation button disappeared")
            let canvas = scroll.frame
            let reads = NSRect(x: canvas.minX + 4, y: canvas.maxY - 40, width: canvas.width * 0.75, height: 35)
            #expect(hasContrast(in: reads, image: bitmap), "Alignment rows disappeared")
            if showingReference {
                #expect(hasContrast(in: referenceRow.frame.insetBy(dx: 2, dy: 4), image: bitmap), "Reference bases disappeared")
            }
        }
        try checkWorkspace(showingReference: false)
        await session.openReference(reference)
        try #require(session.presentation.referenceBases != nil)
        try #require(session.presentation.rowCount == 80)
        try checkWorkspace(showingReference: true)
    }

    private func hasContrast(in rect: NSRect, image: NSBitmapImageRep) -> Bool {
        // The workspace is unflipped. Bitmap row zero is at the top of that workspace.
        let scale = CGFloat(image.pixelsWide) / image.size.width
        let columns = Int(rect.minX * scale)..<Int(rect.maxX * scale)
        let rows = Int((image.size.height - rect.maxY) * scale)..<Int((image.size.height - rect.minY) * scale)
        // A solid painted-over area has a single color, including its opacity.
        guard let first = image.colorAt(x: columns.lowerBound, y: rows.lowerBound) else { return false }
        for row in rows {
            for column in columns {
                if let pixel = image.colorAt(x: column, y: row), pixel != first { return true }
            }
        }
        return false
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func referenceCellsAndBAMGeometryShareCoordinatesAsRealRowsScroll(legacyScroller: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let reference = try files.reference("assembly.bref", fasta: ">tiny\n" + String(repeating: "C", count: 100)
            + "A" + String(repeating: "C", count: 19_899))
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
        // At base 101 the reference changes C to A and the A tail meets a matching body.
        #expect(before.colorAt(x: base101 - 2, y: 7) != before.colorAt(x: base101 + 2, y: 7))
        #expect(geometry.colorAt(x: base101 - 2, y: 7) != geometry.colorAt(x: base101 + 2, y: 7))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 180))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(session.presentation.verticalOffset == 180)
        #expect(abs(stack.convert(NSPoint.zero, to: nil).y - firstAlignment.y) == 180)
        #expect(row.convert(row.bounds, to: nil) == fixedRow && ruler.convert(ruler.bounds, to: nil) == fixedRuler)
        // Reused scrolling pixels must agree with a fresh draw at the new offset,
        // including mismatches on the newly exposed rows.
        let visibleRows = NSRect(x: 0, y: 180, width: stack.bounds.width, height: 40)
        let scrolled = try #require(stack.bitmapImageRepForCachingDisplay(in: visibleRows))
        stack.cacheDisplay(in: visibleRows, to: scrolled)
        let pixelScale = CGFloat(scrolled.pixelsWide) / visibleRows.width
        let left = Int(CGFloat(base101 - 2) * pixelScale)
        let right = Int(CGFloat(base101 + 2) * pixelScale)
        #expect(scrolled.colorAt(x: left, y: Int(7 * pixelScale)) != scrolled.colorAt(x: right, y: Int(7 * pixelScale)))
        let after = try renderAlignmentBitmap(in: row, window: window)
        #expect(after.colorAt(x: base101 - 2, y: 7) == before.colorAt(x: base101 - 2, y: 7))
        #expect(after.colorAt(x: base101 + 2, y: 7) == before.colorAt(x: base101 + 2, y: 7))
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        #expect(spinner.accessibilityLabel() == "Loading genomic interval")

        let prior = session.presentation
        session.beginAlignmentDrag()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 240))
        scroll.reflectScrolledClipView(scroll.contentView)
        try #require(session.presentation.verticalOffset == 240)
        let close = try #require(menu.item(withTitle: "Close Reference"))
        menu.performActionForItem(at: menu.index(of: close))
        #expect(row.isHidden && session.presentation.referenceURL == nil)
        #expect(session.presentation.bamURL == prior.bamURL && session.presentation.target == prior.target)
        #expect(session.presentation.alignments == prior.alignments && session.presentation.rowCount == 80)
        #expect(scroll.contentView.bounds.origin.y == 240 && session.presentation.verticalOffset == 240)
    }
}
