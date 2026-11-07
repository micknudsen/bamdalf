import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeZoomTests {
    @Test
    @MainActor
    func nativeZoomKeepsCrowdedInsertionDecorationWithinRetainedRows() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "zoom")
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        let workspace = try #require(window.contentView)
        let minus = try #require(workspace.subviews.compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Zoom out" })
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:1000-1011")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        for _ in 0..<9 {
            minus.performClick(nil)
            await session.submitInterval()?.value
        }
        #expect(session.presentation.target?.formatted == "tiny:1-6,144")
        for retained in original {
            #expect(session.presentation.alignments.first { $0.id == retained.id }?.row == retained.row)
        }
        workspace.layoutSubtreeIfNeeded()
        let width = Int(ceil(stack.bounds.width))
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 40,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        let cg = context.cgContext
        cg.translateBy(x: 0, y: 40)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            stack.draw(NSRect(x: 0, y: 0, width: stack.bounds.width, height: 40))
        }
        cg.flush()
        NSGraphicsContext.restoreGraphicsState()
        // The two adjacent insertion-bearing records span 1001...1010 and
        // share their retained row. Their decoration may not leak sideways.
        let first = Int(floor(1000 * stack.bounds.width / 6144))
        let last = Int(ceil(1010 * stack.bounds.width / 6144))
        var ink = false
        for y in 3..<15 {
            for x in first..<last {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if min(color.redComponent, color.greenComponent, color.blueComponent) < 0.9 { ink = true }
            }
            for x in [first - 2, last + 2] {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                #expect(min(color.redComponent, color.greenComponent, color.blueComponent) > 0.95)
            }
        }
        #expect(ink, "The actual native renderer draws the retained records at the crowded zoom level")
    }

    @Test
    @MainActor
    func nativeZoomCrossesTheCutoffAndHonorsScrollDuringAFreshReturn() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end - target.start + 1 > 100 {
                throw RegionalLoadError(interval: target, message: "Wide zoom must not query")
            }
            let records = try await file.alignments(in: target)
            if target.end == 250 { await gate.pause(250) }
            return records
        }, alignmentVisibilityLimit: 100)
        try await files.openedSession(fixture: "rows", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let buttons = workspace.subviews.compactMap { $0 as? NSButton }
        let plus = try #require(buttons.first { $0.accessibilityLabel() == "Zoom in" })
        let minus = try #require(buttons.first { $0.accessibilityLabel() == "Zoom out" })
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:100-199")
        await session.submitInterval()?.value
        workspace.layoutSubtreeIfNeeded()
        #expect(session.presentation.alignments.count == 80)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        minus.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:50-249")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.isAlignmentSuppressed && spinner.isHidden)
        #expect(session.presentation.alignments.isEmpty)
        let messages = workspace.subviews.compactMap { $0 as? NSTextField }
        #expect(messages.contains { $0.stringValue == "Zoom in to see alignments" && !$0.isHidden })
        plus.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:100-199")
        #expect(session.submitInterval() == nil)
        #expect(!scroll.isHidden && spinner.isHidden)
        #expect(scroll.contentView.bounds.origin.y == 0)
        #expect(session.presentation.alignments.count == 80)
        minus.performClick(nil)
        minus.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:1-400")
        plus.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:101-300")
        #expect(session.presentation.isAlignmentSuppressed && session.presentation.alignments.isEmpty)
        plus.performClick(nil)
        #expect(session.presentation.target?.formatted == "tiny:151-250")
        let returning = session.submitInterval()
        await gate.waitFor(250)
        #expect(!scroll.isHidden && !spinner.isHidden)
        #expect(plus.isEnabled && minus.isEnabled)
        #expect(scroll.contentView.bounds.origin.y == 0)
        let height = stack.frame.height
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        scroll.reflectScrolledClipView(scroll.contentView)
        await gate.release(250)
        await returning?.value
        #expect(spinner.isHidden)
        #expect(scroll.contentView.bounds.origin.y == 200)
        #expect(stack.frame.height == height)
        #expect(session.presentation.alignments.count == 80)

        let alert = NSAlert()
        alert.messageText = "Modal zoom check"
        alert.addButton(withTitle: "OK")
        await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { _ in continuation.resume() }
            plus.performClick(nil)
            minus.performClick(nil)
            #expect(session.presentation.target?.formatted == "tiny:151-250")
            window.endSheet(alert.window)
        }
    }

    @Test
    @MainActor
    func nativeZoomButtonsReachLimitsAndUpdateTheActiveEditorAndRuler() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let buttons = workspace.subviews.compactMap { $0 as? NSButton }
        let plus = try #require(buttons.first { $0.accessibilityLabel() == "Zoom in" })
        let minus = try #require(buttons.first { $0.accessibilityLabel() == "Zoom out" })
        #expect(!plus.isEnabled && !minus.isEnabled)
        try await files.openedSession(session: session)
        #expect(!plus.isEnabled && !minus.isEnabled)
        session.editInterval("tiny:101-102")
        await session.submitInterval()?.value
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("tiny:2-1", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(session.presentation.intervalError != nil)
        plus.performClick(nil)
        #expect(field.stringValue == "tiny:101-101")
        #expect(editor.string == "tiny:101-101")
        #expect(session.presentation.intervalError == nil)
        #expect(!plus.isEnabled && minus.isEnabled)
        session.editInterval("rejected draft")
        session.submitInterval()
        let error = session.presentation.intervalError
        plus.performClick(nil)
        #expect(field.stringValue == "rejected draft")
        #expect(session.presentation.intervalError == error)
        minus.performClick(nil)
        #expect(field.stringValue == "tiny:100-101")
        #expect(session.presentation.intervalError == nil)
        await session.submitInterval()?.value

        session.editInterval("tiny:1996-2000")
        await session.submitInterval()?.value
        minus.performClick(nil)
        #expect(field.stringValue == "tiny:1,991-2,000")
        await session.submitInterval()?.value
        session.editInterval("tiny:1-2000")
        await session.submitInterval()?.value
        #expect(plus.isEnabled && !minus.isEnabled)
        session.editInterval("keep this draft")
        minus.performClick(nil)
        #expect(field.stringValue == "keep this draft")
        plus.performClick(nil)
        #expect(field.stringValue == "tiny:501-1,500")
        await session.submitInterval()?.value
        workspace.layoutSubtreeIfNeeded()
        let ruler = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Genomic ruler" })
        let labels = ruler.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(labels.contains("tiny:501-1,500"))
        window.setContentSize(window.contentMinSize)
        workspace.layoutSubtreeIfNeeded()
        let ordered = buttons.sorted { $0.frame.minX < $1.frame.minX }
        for button in ordered { #expect(workspace.bounds.contains(button.frame)) }
        for (left, right) in zip(ordered, ordered.dropFirst()) { #expect(left.frame.maxX <= right.frame.minX) }
        #expect(ordered.last!.frame.maxX < field.frame.minX)
        #expect(workspace.bounds.contains(field.frame))
    }
}
