import AppKit
@testable import BamdalfKit
import Testing

@MainActor
@Suite(.serialized)
struct NativePileupInspectionTests {
    @Test(arguments: ["bai", "csi"])
    func panelUsesCompleteDepthBeforeSampling(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files, index: index)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:81-120")
        try #require(viewer.session.presentation.alignments.count == 20)
        viewer.scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
        let offset = viewer.scroll.contentView.bounds.origin.y
        try #require(offset == 40)
        let original = viewer.scroll.frame
        try viewer.click(100)
        try await viewer.expectPanel("tiny:100", "Base depth 100   A 90 (90%)   C 0 (0%)   G 0 (0%)   T 10 (10%)")
        #expect(viewer.scroll.frame.width == original.width)
        #expect(viewer.scroll.frame.height < original.height)
        let button = try viewer.closeButton()
        #expect(button.convert(button.bounds, to: viewer.workspace).maxY <= viewer.scroll.frame.minY)
        // Closing the panel also cancels a click still awaiting double-click recognition.
        try viewer.click(101)
        button.sendAction(button.action, to: button.target)
        try await viewer.finishGesture()
        #expect(!viewer.visibleViews(in: viewer.workspace).contains { ($0 as? NSButton)?.title == "Close" })
        #expect(viewer.scroll.frame == original)
        #expect(viewer.scroll.contentView.bounds.origin.y == offset)
        #expect(viewer.session.presentation.target?.formatted == "tiny:81-120")
    }

    @Test(arguments: ["bai", "csi"])
    func independentAlignmentsContributeOnlyTheirStoredAlignedBase(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files, index: index)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:195-310")
        try viewer.click(200)
        try await viewer.expectPanel("tiny:200", "Base depth 10   A 8 (80%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Ambiguous 2 (20%)")
        try viewer.click(300)
        try await viewer.expectPanel("tiny:300", "Base depth 5   A 1 (20%)   C 1 (20%)   G 1 (20%)   T 1 (20%)   Unresolved = 1 (20%)")
        let reference = try files.reference("counts.bref", fasta: ">tiny\n" + String(repeating: "c", count: 2_000))
        await viewer.session.openReference(reference)
        // A mismatch, another read body, and the empty pileup area reach the same base.
        for y in [CGFloat(8), 26, 160] {
            try viewer.click(299)
            try await viewer.expectPanel("tiny:299 · Reference c", "Base depth 0   A 0   C 0   G 0   T 0")
            try viewer.click(300, y: y)
            try await viewer.expectPanel("tiny:300 · Reference c", "Base depth 5   A 1 (20%)   C 2 (40%)   G 1 (20%)   T 1 (20%)")
        }
        // At 302 only '=' is aligned. A deletion, reference skip and drawn clip span it.
        try viewer.click(302)
        try await viewer.expectPanel("tiny:302 · Reference c", "Base depth 1   A 0 (0%)   C 1 (100%)   G 0 (0%)   T 0 (0%)")
        // At 303 four stored bases accompany missing SEQ and an insertion.
        try viewer.click(303)
        try await viewer.expectPanel("tiny:303 · Reference c", "Base depth 4   A 1 (25%)   C 1 (25%)   G 1 (25%)   T 1 (25%)")
    }

    @Test
    func selectionRequiresAnUnmodifiedClickAtOnePointPerBaseOnABAMContig() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files)
        defer { viewer.window.close() }
        let reference = try files.reference("extra.bref", fasta: ">tiny\n" + String(repeating: "R", count: 2_000) + "\n>extra\nACGT")
        await viewer.session.openReference(reference)
        let width = Int(viewer.stack.bounds.width)
        await viewer.navigate("tiny:1-\(width)")
        try viewer.click(302)
        let heading = "tiny:302 · Reference R"
        let detail = "Base depth 1   A 0 (0%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Unresolved = 1 (100%)"
        try await viewer.expectPanel(heading, detail)
        await viewer.navigate("tiny:1-\(width + 1)")
        try viewer.click(100)
        try await viewer.finishGesture()
        try await viewer.expectPanel(heading, detail)
        await viewer.navigate("extra:1-4")
        try viewer.click(1)
        try await viewer.finishGesture()
        try await viewer.expectPanel(heading, detail)
        await viewer.navigate("tiny:80-130")
        try viewer.click(100, modifiers: .shift)
        try await viewer.finishGesture()
        try await viewer.expectPanel(heading, detail)
        try viewer.click(100)
        try viewer.click(100, count: 2)
        try await viewer.finishGesture()
        #expect(viewer.session.presentation.target?.formatted != "tiny:80-130")
        try await viewer.expectPanel(heading, detail)
        try viewer.click(100, modifiers: .option)
        try await viewer.finishGesture()
        try await viewer.expectPanel(heading, detail)
        let target = viewer.session.presentation.target
        try viewer.drag(from: 100, to: 106)
        try await viewer.finishGesture()
        #expect(viewer.session.presentation.target != target)
        try await viewer.expectPanel(heading, detail)
        let menu = viewer.controller.makeGoMenu()
        let go = try #require(menu.item(withTitle: "Go to Interval"))
        #expect(go.keyEquivalent == "l")
        menu.performActionForItem(at: menu.index(of: go))
        try await viewer.expectPanel(heading, detail)
    }

    @Test
    func referenceOnlySessionLeavesThePanelClosed() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        let reference = try files.reference("standalone.bref", fasta: ">tiny\nACGT")
        await session.openReference(reference)
        let viewer = try InspectionWindow(session: session)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:1-4")
        try viewer.click(2)
        try await viewer.finishGesture()
        #expect(!viewer.visibleViews(in: viewer.workspace).contains { ($0 as? NSButton)?.title == "Close" })
    }

    @Test
    func pendingAndFailedQueriesDoNotReplaceNewerCountsOrReopenThePanel() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, interval in
            let records = try await file.alignments(in: interval)
            if interval.start != interval.end || [100, 300].contains(interval.start) {
                await gate.pause(interval.start)
            }
            if interval.start == 299 { throw RegionalLoadError(interval: interval, message: "Controlled failure") }
            // Model the same virtual offsets retrieved by overlapping reads.
            return records + records
        })
        let viewer = try await InspectionWindow(files: files, session: session)
        defer { viewer.window.close() }
        session.editInterval("tiny:81-310")
        let viewport = session.submitInterval()
        await gate.waitFor(1)
        try viewer.click(100)
        try await viewer.expectPanel("tiny:100", "Loading…")
        await gate.waitFor(100)
        let older = try #require(session.inspectionTask)
        try viewer.click(200)
        let amb = "Base depth 10   A 8 (80%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Ambiguous 2 (20%)"
        try await viewer.expectPanel("tiny:200", amb)
        await gate.release(100)
        await older.value
        try await viewer.expectPanel("tiny:200", amb)
        try viewer.click(299)
        try await viewer.expectPanel("tiny:299", "Counts unavailable")
        try viewer.click(298)
        try await viewer.expectPanel("tiny:298", "Base depth 0   A 0   C 0   G 0   T 0")
        try viewer.click(300)
        try await viewer.expectPanel("tiny:300", "Loading…")
        await gate.waitFor(300)
        let closing = try #require(session.inspectionTask)
        let close = try viewer.closeButton()
        close.sendAction(close.action, to: close.target)
        await gate.release(300)
        await closing.value
        await gate.release(1)
        await viewport?.value
        #expect(!viewer.visibleViews(in: viewer.workspace).contains { ($0 as? NSButton)?.title == "Close" })
    }

}

@MainActor
private struct InspectionWindow {
    let session: ViewerSession
    let controller: ViewerWindowController
    let window: NSWindow
    let workspace: NSView
    let scroll: NSScrollView
    let stack: NSView

    init(files: FixtureFiles, index: String = "bai", session: ViewerSession? = nil) async throws {
        let opened = try await files.openedSession(fixture: "inspection", indexFormat: index,
                                                  session: session ?? ViewerSession(prefetch: .disabled, samplingGroupBudget: 20))
        try self.init(session: opened)
    }

    init(session: ViewerSession) throws {
        _ = NSApplication.shared
        self.session = session
        controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        window = try #require(controller.window)
        window.setContentSize(NSSize(width: 640, height: 400))
        workspace = try #require(window.contentView)
        scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        scroll.scrollerStyle = .overlay
        workspace.layoutSubtreeIfNeeded()
        stack = try #require(scroll.documentView)
    }

    func navigate(_ interval: String) async {
        session.editInterval(interval)
        await session.submitInterval()?.value
    }

    func click(_ position: Int64, y: CGFloat = 8, count: Int = 1, modifiers: NSEvent.ModifierFlags = []) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try event(type, position: position, y: y, count: count, modifiers: modifiers)
            if type == .leftMouseDown { stack.mouseDown(with: event) } else { stack.mouseUp(with: event) }
        }
    }

    func drag(from start: Int64, to end: Int64) throws {
        let down = try event(.leftMouseDown, position: start)
        let drag = try event(.leftMouseDragged, position: end)
        let up = try event(.leftMouseUp, position: end)
        stack.mouseDown(with: down)
        stack.mouseDragged(with: drag)
        stack.mouseUp(with: up)
    }

    func event(_ type: NSEvent.EventType, position: Int64, y: CGFloat = 8, count: Int = 1,
               modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let target = try #require(session.presentation.target)
        let x = (CGFloat(position - target.start) + 0.5) * stack.bounds.width / CGFloat(target.end - target.start + 1)
        let point = stack.convert(NSPoint(x: x, y: scroll.contentView.bounds.minY + y), to: nil)
        return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: count, pressure: 1))
    }

    func finishGesture() async throws {
        try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
    }

    func closeButton() throws -> NSButton {
        try #require(visibleViews(in: workspace).compactMap { $0 as? NSButton }.first { $0.title == "Close" })
    }

    func visibleViews(in view: NSView) -> [NSView] {
        guard !view.isHidden else { return [] }
        return [view] + view.subviews.flatMap { visibleViews(in: $0) }
    }

    func expectPanel(_ heading: String, _ detail: String) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        var labels: [String] = []
        repeat {
            labels = visibleViews(in: workspace).compactMap { ($0 as? NSTextField)?.stringValue }
            if labels.contains(heading), labels.contains(detail) { return }
            try await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        try #require(labels.contains(heading) && labels.contains(detail), "Expected \(heading), \(detail); visible labels: \(labels)")
    }
}
