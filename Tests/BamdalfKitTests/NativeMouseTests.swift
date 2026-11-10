import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeMouseTests {
    @Test
    @MainActor
    func subBaseDragMotionMovesActualGeometryAndRulerBeforeWholeBaseCommit() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "navigation")
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:100-104")
        await session.submitInterval()?.value
        session.editInterval("keep the draft")
        let tick = try #require(session.presentation.rulerTicks(availableWidth: 1000).first { $0.coordinate == 102 })
        let x = Int(stack.bounds.width * 0.25)
        let lead = try #require(session.presentation.alignments.first { $0.name == "lead" })
        let leadY = lead.row * 18 + 9
        let before = try renderedPixel(in: stack, window: window, x: x, y: leadY)
        #expect(before.redComponent < 0.2)
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.5, in: stack, window: window))
        stack.mouseDragged(with: try mouse(.leftMouseDragged, fraction: 0.58, in: stack, window: window))
        #expect(session.presentation.target?.formatted == "tiny:100-104")
        let moved = try #require(session.presentation.rulerTicks(availableWidth: 1000).first { $0.coordinate == 102 })
        #expect(abs(moved.fraction - tick.fraction - 0.08) < 0.000001)
        let preview = try renderedPixel(in: stack, window: window, x: x, y: leadY)
        #expect(preview.redComponent > 0.95, "An 0.4-base displacement moves the actual body before integer rounding changes the target")
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.58, in: stack, window: window))
        #expect(session.presentation.intervalText == "keep the draft")
        #expect(session.presentation.target?.formatted == "tiny:100-104")
        #expect(session.presentation.rulerTicks(availableWidth: 1000).contains(tick))
    }

    @Test(arguments: [false, true], [false, true])
    @MainActor
    func nativeDragHoldsOlderCompletionUntilChangedOrUnchangedRelease(failOlder: Bool, changed: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 409 {
                await gate.pause(159)
                if failOlder { throw RegionalLoadError(interval: target, message: "Older native load failed") }
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let older = session.pan(.right)
        await gate.waitFor(159)
        session.editInterval("tiny:9-2")
        session.submitInterval()
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.75, in: stack, window: window))
        stack.mouseDragged(with: try mouse(.leftMouseDragged, fraction: -0.25, in: stack, window: window))
        let visible = session.presentation.alignments
        await gate.release(159)
        await older?.value
        #expect(session.presentation.target?.formatted == "tiny:160-199")
        #expect(session.presentation.alignments == visible)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(window.attachedSheet == nil)
        let release: CGFloat = changed ? -0.25 : 0.75
        stack.mouseDragged(with: try mouse(.leftMouseDragged, fraction: release, in: stack, window: window))
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: release, in: stack, window: window))
        if changed {
            await session.submitInterval()?.value
            #expect(session.presentation.target?.formatted == "tiny:160-199")
            #expect(session.presentation.intervalText == "tiny:160-199")
            #expect(session.presentation.intervalError == nil)
            #expect(window.attachedSheet == nil)
        } else {
            #expect(session.presentation.target?.formatted == (failOlder ? "tiny:100-139" : "tiny:120-159"))
            #expect(session.presentation.intervalText == "tiny:9-2")
            #expect(session.presentation.intervalError != nil)
            #expect((window.attachedSheet != nil) == failOlder)
        }
        #expect(!session.presentation.isLoading)
        #expect(await gate.count(159) == 1)
    }

    @Test
    @MainActor
    func nativeWheelScrollingDuringDragLoadingSurvivesCompletionAndBoundaryDragsPreserveDrafts() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 499 { await gate.pause(249) }
            return records
        })
        try await files.openedSession(fixture: "rows", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        session.editInterval("tiny:100-199")
        await session.submitInterval()?.value
        let initialRows = session.presentation.alignments
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.75, in: stack, window: window))
        stack.mouseDragged(with: try mouse(.leftMouseDragged, fraction: 0.25, in: stack, window: window))
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.25, in: stack, window: window))
        let pending = session.submitInterval()
        await gate.waitFor(249)
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                        wheel1: -180, wheel2: 0, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: wheel))
        stack.scrollWheel(with: event)
        let offset = session.presentation.verticalOffset
        #expect(offset > 0)
        #expect(Double(scroll.contentView.bounds.origin.y) == offset)
        await gate.release(249)
        await pending?.value
        #expect(session.presentation.verticalOffset == offset)
        #expect(Double(scroll.contentView.bounds.origin.y) == offset)
        #expect(session.presentation.alignments == initialRows)

        session.editInterval("tiny:1-100")
        await session.submitInterval()?.value
        session.editInterval("tiny:9-2")
        session.submitInterval()
        let target = session.presentation.target
        let error = session.presentation.intervalError
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.25, in: stack, window: window))
        stack.mouseDragged(with: try mouse(.leftMouseDragged, fraction: 0.75, in: stack, window: window))
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.75, in: stack, window: window))
        #expect(session.presentation.target == target)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError == error)
    }

    @Test
    @MainActor
    func doubleClickAndOptionLeftClickZoomAtTheHitBaseIncludingTheWideState() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(alignmentVisibilityLimit: 40)
        try await files.openedSession(session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        session.editInterval("tiny:101-140")
        await session.submitInterval()?.value
        session.editInterval("tiny:9-2")
        session.submitInterval()
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.25, in: stack, window: window, clicks: 2))
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.25, in: stack, window: window, clicks: 2))
        #expect(session.presentation.target?.formatted == "tiny:101-120")
        #expect(field.stringValue == "tiny:101-120")
        #expect(session.presentation.intervalError == nil)
        await session.submitInterval()?.value

        session.editInterval("tiny:101-140")
        await session.submitInterval()?.value
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.5, in: stack, window: window, modifiers: .option))
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.5, in: stack, window: window, modifiers: .option))
        #expect(session.presentation.target?.formatted == "tiny:81-160")
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.submitInterval() == nil)
        let point = stack.convert(NSPoint(x: stack.bounds.midX, y: stack.bounds.midY), to: workspace)
        let hit = workspace.hitTest(point)
        #expect(hit === stack, "The ruler-only alignment area remains a native pointer target")
        let messages = workspace.subviews.compactMap { $0 as? NSTextField }
        #expect(messages.contains { $0.stringValue == "Zoom in to see alignments" && !$0.isHidden })
        stack.mouseDown(with: try mouse(.leftMouseDown, fraction: 0.5, in: stack, window: window, clicks: 2))
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.5, in: stack, window: window, clicks: 2))
        #expect(session.presentation.target?.formatted == "tiny:101-140")
        #expect(!session.presentation.isAlignmentSuppressed)
        #expect(session.submitInterval() == nil)

        session.editInterval("preserve the draft")
        let target = session.presentation.target
        stack.rightMouseDown(with: try mouse(.rightMouseDown, fraction: 0.25, in: stack, window: window))
        stack.rightMouseUp(with: try mouse(.rightMouseUp, fraction: 0.25, in: stack, window: window))
        #expect(session.presentation.target == target)
        #expect(field.stringValue == "preserve the draft")
        let editorPoint = NSPoint(x: field.frame.midX, y: field.frame.midY)
        let editorHit = workspace.hitTest(editorPoint)
        #expect(editorHit !== stack && editorHit?.isDescendant(of: scroll) == false)
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("native editing", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        #expect(field.stringValue == "native editing")
        #expect(session.presentation.target == target)
    }

    @Test
    @MainActor
    func pointerDragMovesTheRulerAndLoadedRowsBeforeReleaseCommitsLoading() async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 409 { await gate.pause(159) }
            return records
        })
        try await files.openedSession(fixture: "navigation", session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        let field = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        let ruler = try #require(workspace.subviews.first { $0.accessibilityLabel() == "Genomic ruler" })
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        session.editInterval("tiny:9-2")
        session.submitInterval()
        workspace.layoutSubtreeIfNeeded()
        let sampleX = Int(stack.bounds.width / 8)
        let lead = try #require(original.first { $0.name == "lead" })
        let leadY = lead.row * 18 + 9
        let before = try renderedPixel(in: stack, window: window, x: sampleX, y: leadY)
        #expect(max(before.redComponent, before.greenComponent, before.blueComponent) < 0.2)
        let down = try mouse(.leftMouseDown, fraction: 0.75, in: stack, window: window)
        let dragged = try mouse(.leftMouseDragged, fraction: 0.25, in: stack, window: window)
        stack.mouseDown(with: down)
        stack.mouseDragged(with: dragged)
        #expect(session.presentation.target?.formatted == "tiny:120-159")
        #expect(field.stringValue == "tiny:9-2")
        #expect(session.presentation.intervalError != nil)
        let rulerLabels = ruler.subviews.compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(rulerLabels.contains("tiny:120-159"))
        #expect(session.presentation.alignments == original)
        #expect(await gate.count(159) == 0)
        #expect(!session.presentation.isLoading)
        let preview = try renderedPixel(in: stack, window: window, x: sampleX, y: leadY)
        #expect(min(preview.redComponent, preview.greenComponent, preview.blueComponent) > 0.95,
                "The first alignment moves left with the pointer; it is not just a ruler-label change")
        stack.mouseUp(with: try mouse(.leftMouseUp, fraction: 0.25, in: stack, window: window))
        #expect(field.stringValue == "tiny:120-159")
        #expect(session.presentation.intervalError == nil)
        let pending = session.submitInterval()
        guard session.presentation.target?.formatted == "tiny:120-159" else { return }
        await gate.waitFor(159)
        #expect(session.presentation.isLoading)
        session.scrollVertically(to: 100)
        await gate.release(159)
        await pending?.value
        #expect(Set(session.presentation.alignments.map(\.name)) == ["lead", "anchor", "new_tail"])
        #expect(scroll.contentView.bounds.origin.y == 100)
        for alignment in original {
            #expect(session.presentation.alignments.first { $0.id == alignment.id }?.row == alignment.row)
        }
    }
}

@MainActor
private func renderedPixel(in view: NSView, window: NSWindow, x: Int, y: Int) throws -> NSColor {
    let bitmap = try renderAlignmentBitmap(in: view, window: window)
    return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
}

@MainActor
private func mouse(_ type: NSEvent.EventType, fraction: CGFloat, in view: NSView, window: NSWindow,
                   clicks: Int = 1, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: view.bounds.width * fraction,
                                                                            y: view.bounds.minY + 8), to: nil),
                                   modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 1, clickCount: clicks, pressure: 1))
}
