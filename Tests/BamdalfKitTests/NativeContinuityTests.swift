import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeContinuityTests {
    @Test
    @MainActor
    func nativeScrollExtentAndSpinnerFollowPartialCompleteAndEmptyReuse() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 550 { await gate.pause(300) }
            return records
        })
        try await files.openedSession(fixture: "rows", indexFormat: "bai", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:100-200")
        await session.submitInterval()?.value
        workspace.layoutSubtreeIfNeeded()
        let original = session.presentation.alignments
        let height = stack.frame.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(session.presentation.verticalOffset == 200)

        session.editInterval("tiny:150-300")
        let pending = session.submitInterval()
        await gate.waitFor(300)
        #expect(!spinner.isHidden)
        #expect(session.presentation.alignments == original)
        #expect(stack.frame.height == height)
        #expect(scroll.contentView.bounds.origin.y == 200)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        await gate.release(300)
        await pending?.value
        #expect(spinner.isHidden)
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(stack.frame.height == height)
        #expect(session.presentation.alignments == original)

        session.editInterval("tiny:261-300")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments.isEmpty)
        #expect(spinner.isHidden)
        #expect(!scroll.isHidden)
        #expect(stack.frame.height == height)
        #expect(scroll.contentView.bounds.origin.y == 300)
        #expect(session.presentation.message.isEmpty)

        session.editInterval("tiny:150-200")
        #expect(session.submitInterval() == nil)
        #expect(scroll.contentView.bounds.origin.y == 0)
        #expect(session.presentation.alignments.count == 80)
        #expect(spinner.isHidden)
        let image = try #require(stack.bitmapImageRepForCachingDisplay(in: NSRect(x: 0, y: 0, width: stack.bounds.width, height: 100)))
        stack.cacheDisplay(in: NSRect(x: 0, y: 0, width: stack.bounds.width, height: 100), to: image)
        #expect(image.pixelsWide > 600)
    }
}
