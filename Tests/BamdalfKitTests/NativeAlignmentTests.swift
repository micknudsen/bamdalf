import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeAlignmentTests {
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
    }
    @Test
    @MainActor
    func loadingUsesOnlySpinnerAndRestorationPrecedesTheNativeErrorSheet() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.start == 2001 {
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
            if target.start == 2001 { throw RegionalLoadError(interval: target, message: "Queued old failure") }
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

}
