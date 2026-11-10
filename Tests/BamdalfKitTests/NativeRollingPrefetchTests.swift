import AppKit
import Testing
import BamdalfKit

@Suite(.serialized)
struct NativeRollingPrefetchTests {
    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func arrivingTailDataDrawsAtLatestPointerAndReleaseCompletesBAI() async throws {
        try await verifyArrivalAndRelease(indexFormat: "bai", failRelease: false)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func arrivingTailDataDrawsAtLatestPointerAndReleaseCompletesCSI() async throws {
        try await verifyArrivalAndRelease(indexFormat: "csi", failRelease: false)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func failedReleaseRestoresCommittedViewAfterNativePreviewArrivalBAI() async throws {
        try await verifyArrivalAndRelease(indexFormat: "bai", failRelease: true)
    }

    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func failedReleaseRestoresCommittedViewAfterNativePreviewArrivalCSI() async throws {
        try await verifyArrivalAndRelease(indexFormat: "csi", failRelease: true)
    }

    @MainActor
    private func verifyArrivalAndRelease(indexFormat: String, failRelease: Bool) async throws {
        _ = NSApplication.shared
        let files = try FixtureFiles()
        defer { files.remove() }
        let optional = RollingNativeGate()
        defer { Task { await optional.finish() } }
        let session = ViewerSession(prefetch: .init(chunkBases: 100), loadRegion: { file, interval in
            if interval.end >= 2200 {
                await optional.holdRequired()
                if failRelease { throw RegionalLoadError(interval: interval, message: "Released target failed") }
            }
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            let isTailQuery = await optional.before(interval)
            let records = try await file.alignments(in: interval, budget: budget)
            if isTailQuery { await optional.tailReturned() }
            return records
        })
        try await files.openedSession(fixture: "rolling", indexFormat: indexFormat, session: session)
        let controller = ViewerWindowController(session: session)
        controller.showWindow(nil)
        let window = try #require(controller.window)
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
        window.appearance = NSAppearance(named: .aqua)
        let workspace = try #require(window.contentView)
        let scroll = try #require(workspace.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try #require(scroll.documentView)
        let spinner = try #require(workspace.subviews.compactMap { $0 as? NSProgressIndicator }.first)
        let editor = try #require(workspace.subviews.compactMap { $0 as? NSTextField }.first { $0.isEditable })
        session.editInterval("tiny:1450-1549")
        await session.submitInterval()?.value
        await optional.waitForTail()
        try Task.checkCancellation()
        let committed = session.presentation
        #expect(committed.alignments.count == 80)
        #expect(committed.alignments.allSatisfy { $0.name.hasPrefix("retained_") })
        session.editInterval("tiny:9-2")
        session.submitInterval()
        workspace.layoutSubtreeIfNeeded()
        stack.mouseDown(with: try rollingMouse(.leftMouseDown, fraction: 0.75, in: stack, window: window))
        stack.mouseDragged(with: try rollingMouse(.leftMouseDragged, fraction: 0.2475, in: stack, window: window))
        #expect(session.presentation.target?.formatted == "tiny:1,500-1,599")
        stack.mouseDragged(with: try rollingMouse(.leftMouseDragged, fraction: -0.2525, in: stack, window: window))
        #expect(session.presentation.target?.formatted == "tiny:1,550-1,649")
        #expect(abs(session.presentation.previewOffsetInBases - 0.25) < 0.000001)
        try rollingWheel(-5000, in: stack)
        let offset = session.presentation.verticalOffset
        #expect(offset > 0)
        let before = session.presentation
        await optional.releaseTail()
        // A subsequent optional request proves the returned chunk was handled
        // by the session, rather than merely decoded by the injected reader.
        await optional.waitForFollowingQuery()
        try Task.checkCancellation()
        workspace.layoutSubtreeIfNeeded()
        let arrived = session.presentation
        #expect(arrived.target == before.target)
        #expect(arrived.previewOffsetInBases == before.previewOffsetInBases)
        #expect(arrived.verticalOffset == offset)
        #expect(Double(scroll.contentView.bounds.origin.y) == offset)
        #expect(arrived.rowCount >= before.rowCount)
        #expect(editor.stringValue == "tiny:9-2")
        #expect(arrived.intervalError != nil)
        #expect(!arrived.isLoading && spinner.isHidden)
        #expect(window.attachedSheet == nil)
        for retained in before.alignments {
            #expect(arrived.alignments.first { $0.id == retained.id }?.row == retained.row)
        }
        let forward = try #require(arrived.alignments.first { $0.name == "tail_forward" })
        let reverse = try #require(arrived.alignments.first { $0.name == "tail_reverse" })
        let missing = try #require(arrived.alignments.first { $0.name == "tail_missing" })
        #expect(forward.referenceStart == 1800 && reverse.referenceStart == 1800)
        #expect(arrived.alignments.count == 83)
        let bitmap = try rollingBitmap(stack, window: window, height: arrived.rowCount * 18)
        let x = Int(stack.bounds.width * 0.5)
        let a = try rollingColor(bitmap, x: x, y: forward.row * 18 + 4)
        let c = try rollingColor(bitmap, x: x, y: reverse.row * 18 + 4)
        #expect(a.greenComponent > a.redComponent && a.greenComponent > a.blueComponent)
        #expect(c.blueComponent > c.redComponent && c.blueComponent > c.greenComponent)
        let border = try rollingColor(bitmap, x: x, y: missing.row * 18 + 3)
        let interior = try rollingColor(bitmap, x: x, y: missing.row * 18 + 9)
        #expect(max(border.redComponent, border.greenComponent, border.blueComponent) < 0.2)
        #expect(min(interior.redComponent, interior.greenComponent, interior.blueComponent) > 0.95)

        // Further displacement still uses the original pointer-down anchor.
        stack.mouseDragged(with: try rollingMouse(.leftMouseDragged, fraction: -0.7525, in: stack, window: window))
        #expect(session.presentation.target?.formatted == "tiny:1,600-1,699")
        #expect(abs(session.presentation.previewOffsetInBases - 0.25) < 0.000001)
        try rollingWheel(-90, in: stack)
        #expect(session.presentation.verticalOffset > offset)
        #expect(stack.visibleRect.contains(NSPoint(x: stack.bounds.midX, y: CGFloat(missing.row * 18 + 9))),
                "New tail rows become visible through real native scrolling during the same gesture")
        stack.mouseDragged(with: try rollingMouse(.leftMouseDragged, fraction: -4.2525, in: stack, window: window))
        #expect(session.presentation.target?.formatted == "tiny:1,950-2,049")
        #expect(!session.presentation.isLoading && spinner.isHidden)
        let releaseOffset = session.presentation.verticalOffset
        stack.mouseUp(with: try rollingMouse(.leftMouseUp, fraction: -4.2525, in: stack, window: window))
        let pending = session.submitInterval()
        await optional.waitForRequired()
        try Task.checkCancellation()
        #expect(session.presentation.isLoading && !spinner.isHidden)
        #expect(editor.stringValue == "tiny:1,950-2,049")
        #expect(session.presentation.intervalError == nil)
        session.editInterval("newer native draft")
        await optional.releaseFollowingQuery()
        await optional.releaseRequired()
        await pending?.value
        #expect(editor.stringValue == "newer native draft")
        #expect(!session.presentation.isLoading && spinner.isHidden)
        if failRelease {
            #expect(session.presentation.target == committed.target)
            #expect(session.presentation.alignments == committed.alignments)
            #expect(session.presentation.rowCount == committed.rowCount)
            #expect(session.presentation.verticalOffset == 0)
            #expect(window.attachedSheet != nil)
            #expect(session.presentation.regionalError?.interval.formatted == "tiny:1,950-2,049")
        } else {
            #expect(session.presentation.target?.formatted == "tiny:1,950-2,049")
            #expect(session.presentation.alignments.isEmpty)
            #expect(session.presentation.rowCount >= arrived.rowCount)
            #expect(session.presentation.verticalOffset == releaseOffset)
            #expect(Double(scroll.contentView.bounds.origin.y) == releaseOffset)
            #expect(window.attachedSheet == nil)
            #expect(session.presentation.regionalError == nil)
        }
    }
}

private actor RollingNativeGate {
    private var hasTail = false
    private var returnedTail = false
    private var hasFollowing = false
    private var entered = Set<Int>()
    private var released = Set<Int>()
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private var finished = false

    func before(_ interval: GenomicInterval) async -> Bool {
        if !hasTail, interval.start <= 1800, interval.end >= 1800 {
            hasTail = true
            await hold(1)
            return true
        }
        if returnedTail, !hasFollowing {
            hasFollowing = true
            await hold(2)
        }
        return false
    }

    func tailReturned() { returnedTail = true }
    func waitForTail() async { await waitFor(1) }
    func releaseTail() { release(1) }
    func waitForFollowingQuery() async { await waitFor(2) }
    func releaseFollowingQuery() { release(2) }
    func holdRequired() async { await hold(3) }
    func waitForRequired() async { await waitFor(3) }
    func releaseRequired() { release(3) }

    private func hold(_ key: Int) async {
        entered.insert(key)
        waiting.removeValue(forKey: key)?.resume()
        guard !finished, !released.contains(key) else { return }
        await withCheckedContinuation { pending[key] = $0 }
    }

    private func waitFor(_ key: Int) async {
        guard !finished, !entered.contains(key), !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[key] = $0 }
        } onCancel: {
            Task { await self.finish() }
        }
    }

    private func release(_ key: Int) {
        released.insert(key)
        pending.removeValue(forKey: key)?.resume()
    }

    func finish() {
        finished = true
        for continuation in pending.values { continuation.resume() }
        for continuation in waiting.values { continuation.resume() }
        pending.removeAll()
        waiting.removeAll()
    }
}

@MainActor
private func rollingMouse(_ type: NSEvent.EventType, fraction: CGFloat, in view: NSView, window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: view.bounds.width * fraction,
                                                                            y: view.bounds.minY + 8), to: nil),
                                   modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
}

@MainActor
private func rollingWheel(_ delta: Int32, in view: NSView) throws {
    let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                    wheel1: delta, wheel2: 0, wheel3: 0))
    view.scrollWheel(with: try #require(NSEvent(cgEvent: wheel)))
}

@MainActor
private func rollingBitmap(_ view: NSView, window: NSWindow, height: Int) throws -> NSBitmapImageRep {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(view.bounds.width)), pixelsHigh: height,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    let cg = context.cgContext
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    window.effectiveAppearance.performAsCurrentDrawingAppearance {
        view.draw(NSRect(x: 0, y: 0, width: view.bounds.width, height: CGFloat(height)))
    }
    cg.flush()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

private func rollingColor(_ bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
}
