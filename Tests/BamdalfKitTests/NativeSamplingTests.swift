import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeSamplingTests {
    @Test
    @MainActor
    func statusSlotShowsAccessibleWarningOnlyForReadySampledData() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 850 { await gate.pause(451) }
            if target.end == 950 { throw RegionalLoadError(interval: target, message: "Native sampled rollback") }
            return try await file.alignments(in: target)
        }, samplingGroupBudget: 7, samplingSeed: { 42 }, samplingPriority: { _, _ in 1 })
        try await files.openedSession(fixture: "sampling", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        let workspace = try #require(window.contentView)
        let text = "Downsampled: some alignments are not shown."
        let warning = try #require(workspace.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == text })
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        #expect(warning.isHidden && spinner.isHidden)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        #expect(!warning.isHidden && spinner.isHidden)
        #expect(warning.accessibilityLabel() == text)
        #expect(warning.accessibilityHelp() == text)
        #expect(warning.contentTintColor == .systemOrange)
        window.setContentSize(window.contentMinSize)
        workspace.layoutSubtreeIfNeeded()
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        #expect(warning.frame.minX > field.frame.maxX)
        #expect(workspace.bounds.contains(warning.frame))
        window.setContentSize(NSSize(width: 1100, height: 720))
        workspace.layoutSubtreeIfNeeded()
        #expect(window.makeFirstResponder(warning))
        #expect(window.firstResponder === warning)
        func containsExplanation(_ view: NSView) -> Bool {
            if let label = view as? NSTextField, label.stringValue == text { return true }
            return view.subviews.contains(where: containsExplanation)
        }
        #expect(NSApp.windows.compactMap(\.contentView).contains(where: containsExplanation))
        _ = window.makeFirstResponder(nil)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let renderer = try #require(scroll.documentView)
        let bitmap = try #require(renderer.bitmapImageRepForCachingDisplay(in: renderer.bounds))
        renderer.cacheDisplay(in: renderer.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 600)

        session.editInterval("tiny:100-600")
        let pending = session.submitInterval()
        await gate.waitFor(451)
        #expect(warning.isHidden && !spinner.isHidden)
        await gate.release(451)
        await pending?.value
        #expect(!warning.isHidden && spinner.isHidden)
        session.editInterval("tiny:100-700")
        await session.submitInterval()?.value
        #expect(!warning.isHidden && spinner.isHidden)
        #expect(window.attachedSheet != nil)
        #expect(session.presentation.target?.formatted == "tiny:100-600")
        #expect(session.presentation.verticalOffset == 0)
        session.editInterval("tiny:1000-1100")
        await session.submitInterval()?.value
        #expect(warning.isHidden && spinner.isHidden)
        #expect(session.presentation.alignments.isEmpty)
    }
}
