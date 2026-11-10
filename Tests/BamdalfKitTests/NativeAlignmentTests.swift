import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeAlignmentTests {
    @Test
    @MainActor
    func tailOnlyViewsDrawStoredBaseColorsAndUnclosedMissingSequenceOutlines() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "alignments")
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)

        session.editInterval("tiny:91-100")
        await session.submitInterval()?.value
        let forward = try #require(session.presentation.alignments.first { $0.name == "forward" })
        let reverse = try #require(session.presentation.alignments.first { $0.name == "reverse" })
        #expect(forward.referenceStart == 101 && reverse.referenceStart == 101)
        workspace.layoutSubtreeIfNeeded()
        let left = try renderAlignmentBitmap(in: stack, window: window)
        // Stored forward tail ACGT begins at 91. Reverse tail TGC begins at
        // 98 and stays in stored CIGAR order rather than being reversed again.
        let a = try tailColor(in: left, x: Int(stack.bounds.width * 0.025), y: forward.row * 18 + 4)
        let c = try tailColor(in: left, x: Int(stack.bounds.width * 0.125), y: forward.row * 18 + 4)
        let g = try tailColor(in: left, x: Int(stack.bounds.width * 0.225), y: forward.row * 18 + 4)
        let t = try tailColor(in: left, x: Int(stack.bounds.width * 0.325), y: forward.row * 18 + 4)
        #expect(a.greenComponent > a.redComponent && a.greenComponent > a.blueComponent)
        #expect(c.blueComponent > c.redComponent && c.blueComponent > c.greenComponent)
        #expect(g.redComponent > 0.8 && g.greenComponent > 0.6 && g.blueComponent < 0.4)
        #expect(t.redComponent > t.greenComponent && t.redComponent > t.blueComponent)
        let reverseT = try tailColor(in: left, x: Int(stack.bounds.width * 0.725), y: reverse.row * 18 + 4)
        #expect(reverseT.redComponent > reverseT.greenComponent && reverseT.redComponent > reverseT.blueComponent)

        session.editInterval("tiny:111-115")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.allSatisfy { $0.referenceEnd == 110 })
        let right = try renderAlignmentBitmap(in: stack, window: window)
        let forwardRight = try #require(session.presentation.alignments.first { $0.name == "forward" })
        let rightT = try tailColor(in: right, x: Int(stack.bounds.width * 0.05), y: forwardRight.row * 18 + 4)
        #expect(rightT.redComponent > rightT.greenComponent && rightT.redComponent > rightT.blueComponent)

        for interval in ["tiny:2997-2999", "tiny:3012-3014"] {
            session.editInterval(interval)
            await session.submitInterval()?.value
            let missing = try #require(session.presentation.alignments.first)
            #expect(missing.name == "missing_sequence")
            #expect(missing.segments.filter { $0.kind == .softClip }.allSatisfy { $0.sequence == nil })
            let outline = try renderAlignmentBitmap(in: stack, window: window)
            let y = missing.row * 18
            for x in [1, Int(stack.bounds.width / 2), Int(stack.bounds.width) - 2] {
                let edge = try tailColor(in: outline, x: x, y: y + 3)
                let interior = try tailColor(in: outline, x: x, y: y + 9)
                #expect(max(edge.redComponent, edge.greenComponent, edge.blueComponent) < 0.2)
                #expect(min(interior.redComponent, interior.greenComponent, interior.blueComponent) > 0.95,
                        "Clipped outline tails stay open at both viewport edges and invent no sequence")
            }
        }
    }

    @Test
    @MainActor
    func nativeStackDrawsRealRecordsAndScrollsThroughTheSession() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "rows")
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let scroll = try #require(content.subviews.compactMap { $0 as? NSScrollView }.first)
        #expect(scroll.hasVerticalScroller)
        #expect(!scroll.hasHorizontalScroller)
        let stack = try #require(scroll.documentView)
        #expect(stack.accessibilityLabel() == "Alignment stack")
        #expect(stack.frame.height > scroll.contentSize.height)
        let image = try #require(stack.bitmapImageRepForCachingDisplay(in: NSRect(x: 0, y: 0, width: stack.bounds.width, height: 100)))
        stack.cacheDisplay(in: NSRect(x: 0, y: 0, width: stack.bounds.width, height: 100), to: image)
        #expect(image.pixelsWide > 600)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(session.presentation.verticalOffset == 200)
        session.editInterval("tiny:0100-0300")
        await session.submitInterval()?.value
        #expect(scroll.contentView.bounds.origin.y == 200)
        #expect(session.presentation.verticalOffset == 200)
        let original = session.presentation.alignments
        session.editInterval("tiny:251-259")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.alignments.allSatisfy { $0.referenceEnd == 250 })
        #expect(scroll.contentView.bounds.origin.y == 200)
        #expect(session.presentation.verticalOffset == 200)
    }
    @Test
    @MainActor
    func loadingUsesOnlySpinnerAndRestorationPrecedesTheNativeErrorSheet() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 2260 {
                await gate.pause(2001)
                throw RegionalLoadError(interval: target, message: "Known index failure")
            }
            return try await file.alignments(in: target)
        })
        let bam = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        session.editInterval("tiny:101-110")
        await session.submitInterval()?.value
        session.editInterval("tiny:2001-2010")
        let pending = session.submitInterval()
        await gate.waitFor(2001)
        let spinner = try #require(window.contentView?.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        #expect(!spinner.isHidden && spinner.style == .spinning)
        #expect(spinner.accessibilityLabel() == "Loading alignments")
        #expect(session.presentation.message.isEmpty)
        await gate.release(2001)
        await pending?.value
        #expect(spinner.isHidden)
        #expect(session.presentation.target?.formatted == "tiny:101-110")
        let sheet = try #require(window.attachedSheet)
        let descendants = descendants(of: try #require(sheet.contentView))
        #expect(descendants.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Could not load tiny:2,001-2,010" })
        #expect(descendants.compactMap { $0 as? NSTextField }.contains { $0.stringValue == "Known index failure" })
        #expect(descendants.compactMap { $0 as? NSButton }.map(\.title) == ["OK"])
        session.editInterval("tiny:3001-3010")
        await session.submitInterval()?.value
        #expect(window.attachedSheet == nil)
        #expect(session.presentation.regionalError == nil)
    }

    @Test
    @MainActor
    func regionalErrorWaitingBehindAnotherSheetIsDiscardedAfterNewNavigation() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 2260 { throw RegionalLoadError(interval: target, message: "Queued old failure") }
            return try await file.alignments(in: target)
        })
        let bam = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        let blocker = NSAlert()
        blocker.messageText = "Another native sheet"
        blocker.addButton(withTitle: "OK")
        blocker.beginSheetModal(for: window) { _ in }
        session.editInterval("tiny:2001-2010")
        await session.submitInterval()?.value
        #expect(session.presentation.regionalError != nil)
        #expect(window.attachedSheet === blocker.window)
        session.editInterval("tiny:3001-3010")
        await session.submitInterval()?.value
        window.endSheet(blocker.window)
        await Task.yield()
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.target?.formatted == "tiny:3,001-3,010")
        #expect(window.attachedSheet == nil)
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func tailColor(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

}
