import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativePrefetchTests {
    @Test(arguments: [false, true])
    @MainActor
    func optionalFailurePreservesNativeReadyStatusAndNeverPresentsAnAlert(sampled: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .init(chunkBases: 250), samplingGroupBudget: 7,
                                    samplingSeed: { 42 }, samplingPriority: { _, _ in 1 },
                                    loadPrefetchRegion: { file, interval, budget in
            if interval.start == 701 {
                await gate.pause(1)
                throw RegionalLoadError(interval: interval, message: "Malformed optional-only alignment")
            }
            await gate.pause(2)
            return try await file.alignments(in: interval, budget: budget)
        })
        try await files.openedSession(fixture: sampled ? "sampling" : "rows", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        let content = try #require(window.contentView)
        let explanation = "Downsampled: some alignments are not shown."
        let warning = try #require(content.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == explanation })
        let spinner = try #require(content.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let scroll = try #require(content.subviews.compactMap { $0 as? NSScrollView }.first)
        let renderer = try #require(scroll.documentView)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        await gate.waitFor(1)
        content.layoutSubtreeIfNeeded()
        if !sampled {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
            scroll.reflectScrolledClipView(scroll.contentView)
            #expect(session.presentation.verticalOffset == 200)
        }
        let original = session.presentation
        let originalHeight = renderer.frame.height
        let originalScroll = scroll.contentView.bounds.origin.y
        #expect(original.isDownsampled == sampled)
        #expect(warning.isHidden == !sampled)
        #expect(spinner.isHidden)
        #expect(window.attachedSheet == nil)
        if sampled {
            #expect(warning.accessibilityLabel() == explanation)
            #expect(warning.accessibilityHelp() == explanation)
        }

        await gate.release(1)
        // Entering another optional query proves that the session handled the
        // failed query. No timing sleep or post-read delivery gate is used.
        await gate.waitFor(2)
        content.layoutSubtreeIfNeeded()
        #expect(session.presentation.target == original.target)
        #expect(session.presentation.alignments == original.alignments)
        #expect(session.presentation.rowCount == original.rowCount)
        #expect(session.presentation.verticalOffset == original.verticalOffset)
        #expect(session.presentation.regionalError == nil)
        #expect(!session.presentation.isLoading)
        #expect(warning.isHidden == !sampled)
        #expect(spinner.isHidden)
        #expect(window.attachedSheet == nil)
        #expect(renderer.frame.height == originalHeight)
        #expect(scroll.contentView.bounds.origin.y == originalScroll)
        let bitmap = try renderAlignmentBitmap(in: renderer, window: window)
        #expect(bitmap.pixelsWide > 600)

        // Retiring optional work before releasing the last gate also exercises
        // native cleanup without leaving a held task in later tests.
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.release(2)
    }
}
