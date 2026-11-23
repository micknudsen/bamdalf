import AppKit
@testable import BamdalfKit
import Testing

@MainActor
@Suite(.serialized)
struct NativePileupInspectionTests {
    private func inspectionReference(_ base: String) -> String {
        ">tiny\n" + String(repeating: base, count: 2_000) + "\n>other_reference\n" + String(repeating: "A", count: 800)
    }

    @Test(arguments: ["bai", "csi"])
    func activeSourcesOwnTheCountsThroughoutInspection(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files, index: index)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:81-120")
        try #require(viewer.session.presentation.alignments.count == 20)
        try viewer.click(100)
        try await viewer.expectPanel("tiny:100", "Base depth 100   A 90 (90%)   C 0 (0%)   G 0 (0%)   T 10 (10%)")
        await viewer.navigate("tiny:390-510")
        try viewer.click(400)
        try await viewer.expectPanel("tiny:400", "Base depth 8   A 8 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Deletions 2   Reference skips 3")
        try viewer.click(500)
        let unresolved = "Base depth 10   A 0 (0%)   C 8 (80%)   G 0 (0%)   T 0 (0%)   Unresolved = 2 (20%)"
        try await viewer.expectPanel("tiny:500", unresolved)
        await viewer.navigate("other_reference:1-40")
        let lower = try files.reference("lower.bref", fasta: inspectionReference("c"))
        let ambiguous = try files.reference("ambiguous.bref", fasta: inspectionReference("R"))
        await viewer.session.openReference(lower)
        try await viewer.expectPanel("tiny:500 · Reference c", "Base depth 10   A 0 (0%)   C 10 (100%)   G 0 (0%)   T 0 (0%)")
        #expect(viewer.hasLabel("outside current view"))
        await viewer.session.openReference(ambiguous)
        try await viewer.expectPanel("tiny:500 · Reference R", unresolved)
        #expect(viewer.hasLabel("outside current view"))
        viewer.controller.closeReference(nil)
        try await viewer.expectPanel("tiny:500", unresolved)
        #expect(viewer.hasLabel("outside current view"))
        await viewer.navigate("tiny:481-520")
        #expect(!viewer.hasLabel("outside current view"))

        // With a paired reference, switching BAMs keeps this viewport. Only the selection disappears.
        await viewer.session.openReference(ambiguous)
        try await viewer.expectPanel("tiny:500 · Reference R", unresolved)
        let replacement = files.sources.appendingPathComponent("opening.bam")
        await viewer.session.openBAM(replacement)
        await viewer.session.chooseIndex(nil)
        try await viewer.expectPanel("tiny:500 · Reference R", unresolved)
        #expect(try !viewer.rulerMarkerPixels().isEmpty)
        await viewer.session.openBAM(files.directory.appendingPathComponent("missing.bam"))
        try #require(viewer.session.presentation.openError != nil)
        viewer.session.dismissOpenError()
        try await viewer.expectPanel("tiny:500 · Reference R", unresolved)
        #expect(try !viewer.rulerMarkerPixels().isEmpty)
        // A press that began on the outgoing BAM cannot finish as a selection on its replacement.
        viewer.stack.mouseDown(with: try viewer.event(.leftMouseDown, position: 501))
        try await files.openedSession(fixture: "opening", indexFormat: index, session: viewer.session)
        viewer.stack.mouseUp(with: try viewer.event(.leftMouseUp, position: 501))
        let stack = try #require(viewer.stack as? GenomicAlignmentView)
        await stack.pendingClick?.value
        #expect(viewer.session.presentation.target?.formatted == "tiny:481-520")
        #expect(!viewer.visibleViews(in: viewer.workspace).contains { ($0 as? NSButton)?.title == "Close" })
        #expect(try viewer.rulerMarkerPixels().isEmpty)
    }

    @Test
    func pendingOffscreenCountsCannotOutliveTheirReferenceOrBAM() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let lower = try files.reference("lower.bref", fasta: inspectionReference("c"))
        let ambiguous = try files.reference("ambiguous.bref", fasta: inspectionReference("R"))
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadReferenceRegion: { bundle, interval in
            let bases = try await bundle.read(interval)
            if interval.start == 500 && interval.end == 500 {
                _ = await gate.pauseIfArmed(500)
            }
            return bases
        })
        let viewer = try await InspectionWindow(files: files, session: session)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:481-520")
        try viewer.click(500)
        let unresolved = "Base depth 10   A 0 (0%)   C 8 (80%)   G 0 (0%)   T 0 (0%)   Unresolved = 2 (20%)"
        try await viewer.expectPanel("tiny:500", unresolved)
        await viewer.navigate("other_reference:1-40")

        await gate.arm(500)
        await session.openReference(lower)
        try await viewer.expectPanel("tiny:500", "Loading…")
        await gate.waitFor(500)
        let oldReference = try #require(session.inspectionTask)
        await session.openReference(ambiguous)
        try await viewer.expectPanel("tiny:500 · Reference R", unresolved)
        await gate.release(500)
        await oldReference.value
        try await viewer.expectPanel("tiny:500 · Reference R", unresolved)
        #expect(viewer.hasLabel("outside current view"))

        await gate.arm(500)
        await session.openReference(lower)
        try await viewer.expectPanel("tiny:500", "Loading…")
        await gate.waitFor(500)
        let oldBAM = try #require(session.inspectionTask)
        try await files.openedSession(fixture: "opening", session: session)
        await gate.release(500)
        await oldBAM.value
        #expect(!viewer.visibleViews(in: viewer.workspace).contains { ($0 as? NSButton)?.title == "Close" })
        await viewer.navigate("tiny:481-520")
        try viewer.click(500)
        try await viewer.expectPanel("tiny:500 · Reference c", "Base depth 0   A 0   C 0   G 0   T 0")
    }

    @Test(arguments: [false, true])
    func selectedColumnMarksTheRulerAndOutlinesReadableTracks(withReference: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession()
        let viewer = try InspectionWindow(session: session)
        defer { viewer.window.close() }
        if withReference {
            let reference = try files.reference("two.bref", fasta: ">tiny\n" + String(repeating: "c", count: 2000)
                                                + "\n>other_reference\n" + String(repeating: "a", count: 800))
            await session.openReference(reference)
        }
        await viewer.navigate("tiny:91-128")
        try #require(viewer.stack.bounds.width == 608) // 16 points per base; base 101 spans x = 160..<176.
        let ruler = try #require(viewer.visibleViews(in: viewer.workspace).first { $0.accessibilityLabel() == "Genomic ruler" })
        var tracks = [viewer.stack]
        if withReference {
            tracks.append(try #require(viewer.visibleViews(in: viewer.workspace).first { $0.accessibilityLabel() == "Reference sequence" }))
        }
        let before = try tracks.map { try renderAlignmentBitmap(in: $0, window: viewer.window) }
        let rulerBefore = try renderTrackBitmap(in: ruler, window: viewer.window, height: 20)
        try viewer.click(101)
        try await viewer.expectPanel(withReference ? "tiny:101 · Reference c" : "tiny:101",
                                     "Base depth 1   A 1 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)")
        let rulerAfter = try renderTrackBitmap(in: ruler, window: viewer.window, height: 20)
        // The region beneath the ruler baseline contains only the selection marker.
        let marker = (0..<608).filter { rulerBefore.colorAt(x: $0, y: 11) != rulerAfter.colorAt(x: $0, y: 11) }
        #expect(marker.contains(168) && marker.allSatisfy { (162...174).contains($0) })
        for (track, original) in zip(tracks, before) {
            let marked = try renderAlignmentBitmap(in: track, window: viewer.window)
            for y in [1, 8, track === viewer.stack ? 35 : 16] {
                let changes = (0..<608).filter { original.colorAt(x: $0, y: y) != marked.colorAt(x: $0, y: y) }
                #expect(changes.contains { (159...161).contains($0) } && changes.contains { (174...176).contains($0) })
                #expect(changes.allSatisfy { (159...161).contains($0) || (174...176).contains($0) })
            }
            // Every interior pixel, including the base glyph and mismatch color, survives selection.
            for y in 3..<15 {
                #expect((162..<174).allSatisfy { original.colorAt(x: $0, y: y) == marked.colorAt(x: $0, y: y) })
            }
        }
        let close = try viewer.closeButton()
        close.sendAction(close.action, to: close.target)
        for (track, original) in zip(tracks, before) {
            let restored = try renderAlignmentBitmap(in: track, window: viewer.window)
            #expect(restored.representation(using: .png, properties: [:]) == original.representation(using: .png, properties: [:]))
        }
    }

    @Test
    func onePointColumnsKeepConsecutiveMismatchAndReferenceColors() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession()
        let viewer = try InspectionWindow(session: session)
        defer { viewer.window.close() }
        let reference = try files.reference("threshold.bref", fasta: ">tiny\n" + String(repeating: "t", count: 2000)
                                            + "\n>other_reference\n" + String(repeating: "a", count: 800))
        await session.openReference(reference)
        await viewer.navigate("tiny:1-608")
        try #require(viewer.stack.bounds.width == 608)
        let referenceRow = try #require(viewer.visibleViews(in: viewer.workspace).first { $0.accessibilityLabel() == "Reference sequence" })
        let tracks = [viewer.stack, referenceRow]
        let before = try tracks.map { try renderAlignmentBitmap(in: $0, window: viewer.window) }
        // Positions 101–103 are consecutive A, C and G mismatches against reference t.
        try #require(before[0].colorAt(x: 100, y: 8) != before[0].colorAt(x: 101, y: 8))
        try #require(before[0].colorAt(x: 101, y: 8) != before[0].colorAt(x: 102, y: 8))
        try viewer.click(102)
        try await viewer.expectPanel("tiny:102 · Reference t", "Base depth 1   A 0 (0%)   C 1 (100%)   G 0 (0%)   T 0 (0%)")
        for (track, original) in zip(tracks, before) {
            let marked = try renderAlignmentBitmap(in: track, window: viewer.window)
            #expect((100...102).allSatisfy { marked.colorAt(x: $0, y: 8) == original.colorAt(x: $0, y: 8) })
            #expect((100...102).contains { marked.colorAt(x: $0, y: 1) != original.colorAt(x: $0, y: 1) })
        }
    }

    @Test
    func selectedColumnTracksTheClipWidthWhenAppKitTilesTheScroller() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:81-120")
        try viewer.click(100)
        try await viewer.expectPanel("tiny:100", "Base depth 100   A 90 (90%)   C 0 (0%)   G 0 (0%)   T 10 (10%)")
        let ruler = try #require(viewer.visibleViews(in: viewer.workspace).first { $0.accessibilityLabel() == "Genomic ruler" })
        let originalWidth = viewer.scroll.contentView.bounds.width
        viewer.scroll.scrollerStyle = .legacy
        viewer.workspace.layoutSubtreeIfNeeded()
        let width = viewer.scroll.contentView.bounds.width
        try #require(width < originalWidth)
        #expect(viewer.stack.bounds.width == width)
        #expect(ruler.bounds.width == width)
        // Base 100 spans fractions 19/40 to 20/40 of the tiled viewport.
        let stack = try renderAlignmentBitmap(in: viewer.stack, window: viewer.window)
        let edge = Int(ceil(width * 19 / 40))
        #expect(stack.colorAt(x: edge, y: 1) != stack.colorAt(x: edge - 2, y: 1))
    }

    @Test
    func markerFollowsNavigationAndThePanelRetainsItsBAMCoordinate() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try InspectionWindow(session: await files.openedSession())
        defer { viewer.window.close() }
        let first = "Base depth 1   A 1 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)"
        let second = "Base depth 1   A 0 (0%)   C 0 (0%)   G 1 (100%)   T 0 (0%)"
        await viewer.navigate("tiny:91-128")
        try #require(viewer.stack.bounds.width == 608)
        func expectMarker(at center: Int?) throws {
            let pixels = try viewer.rulerMarkerPixels()
            if let center {
                #expect(pixels.contains(center) && pixels.allSatisfy { abs($0 - center) <= 5 })
            } else {
                #expect(pixels.isEmpty)
            }
        }
        func isOutside() -> Bool {
            viewer.visibleViews(in: viewer.workspace).contains { ($0 as? NSTextField)?.stringValue == "outside current view" }
        }
        try viewer.click(101)
        try await viewer.expectPanel("tiny:101", first)
        try expectMarker(at: 168)
        // While the pointer is held four points from mouse-down, the integral target
        // remains unchanged but the selected column has moved a quarter of a base.
        viewer.stack.mouseDown(with: try viewer.event(.leftMouseDown, position: 120))
        viewer.stack.mouseDragged(with: try viewer.event(.leftMouseDragged, position: 120, xOffset: 4))
        try expectMarker(at: 172)
        viewer.stack.mouseUp(with: try viewer.event(.leftMouseUp, position: 120, xOffset: 4))
        try expectMarker(at: 168)
        try viewer.drag(from: 120, to: 117) // The viewport advances three bases.
        try expectMarker(at: 120)
        try viewer.drag(from: 120, to: 100)
        try expectMarker(at: nil)
        #expect(isOutside())
        try await viewer.expectPanel("tiny:101", first)
        try viewer.drag(from: 120, to: 140)
        try expectMarker(at: 120)
        #expect(!isOutside())

        try viewer.click(102)
        let firstClick = try #require((viewer.stack as? GenomicAlignmentView)?.pendingClick)
        try viewer.click(102, count: 2)
        await firstClick.value
        try expectMarker(at: 272) // tiny:93-111, 32 points per base.
        try viewer.click(102, modifiers: .option)
        try expectMarker(at: 296) // tiny:83-120, 16 points per base.
        try await viewer.expectPanel("tiny:101", first)

        await viewer.navigate("other_reference:1-500")
        try await viewer.expectPanel("tiny:101", first)
        try expectMarker(at: nil)
        #expect(isOutside())
        await viewer.navigate("tiny:91-128")
        try expectMarker(at: 168)
        #expect(!isOutside())

        await viewer.navigate("other_reference:191-228")
        try viewer.click(201)
        try await viewer.expectPanel("other_reference:201", second)
        try expectMarker(at: 168)
        #expect(!isOutside())
        let close = try viewer.closeButton()
        close.sendAction(close.action, to: close.target)
        try expectMarker(at: nil)
        #expect(!viewer.visibleViews(in: viewer.workspace).contains(close))
        try viewer.click(202)
        try await viewer.expectPanel("other_reference:202", first)
        try expectMarker(at: 184)
    }

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
        let reference = try files.reference("counts.bref", fasta: inspectionReference("c"))
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
        try await viewer.expectPanel("tiny:302 · Reference c", "Base depth 1   A 0 (0%)   C 1 (100%)   G 0 (0%)   T 0 (0%)   Deletions 1   Reference skips 1")
        // At 303 four stored bases accompany missing SEQ and an insertion.
        try viewer.click(303)
        try await viewer.expectPanel("tiny:303 · Reference c", "Base depth 4   A 1 (25%)   C 1 (25%)   G 1 (25%)   T 1 (25%)   Sequence unavailable 1   Insertion after this base 1")
    }

    @Test(arguments: ["bai", "csi"])
    func gapsAndMissingSequenceStayOutsideBaseDepth(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files, index: index)
        defer { viewer.window.close() }
        await viewer.navigate("tiny:390-410")
        // A missing sequence still supplies its CIGAR deletion. A clipped T also crosses 400.
        try viewer.click(400)
        try await viewer.expectPanel("tiny:400", "Base depth 8   A 8 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Deletions 2   Reference skips 3")
        try viewer.click(402)
        try await viewer.expectPanel("tiny:402", "Base depth 0   A 0   C 0   G 0   T 0   Deletions 2")
        try viewer.click(399)
        try await viewer.expectPanel("tiny:399", "Base depth 4   A 4 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Sequence unavailable 1")
    }

    @Test(arguments: ["bai", "csi"])
    func insertionsCountSupportingAlignmentsAtTheFollowingBoundary(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, interval in
            _ = await gate.pauseIfArmed(1)
            return try await file.alignments(in: interval)
        })
        let viewer = try await InspectionWindow(files: files, index: index, session: session)
        defer { viewer.window.close() }
        // The 250-base tail margin fills the cache through 410. Hold the next viewport load
        // so inspection must find the alignment that starts with an insertion at 411.
        await viewer.navigate("tiny:120-160")
        await gate.arm(1)
        session.editInterval("tiny:390-425")
        let viewport = session.submitInterval()
        await gate.waitFor(1)
        defer { Task { await gate.release(1) } }
        let at410 = "Base depth 1   A 1 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Insertion after this base 2"
        try viewer.click(410)
        try await viewer.expectPanel("tiny:410", at410)
        await gate.release(1)
        await viewport?.value
        try viewer.click(409)
        try await viewer.expectPanel("tiny:409", "Base depth 0   A 0   C 0   G 0   T 0")
        try viewer.click(410)
        try await viewer.expectPanel("tiny:410", at410)
        try viewer.click(411)
        try await viewer.expectPanel("tiny:411", "Base depth 2   A 0 (0%)   C 1 (50%)   G 1 (50%)   T 0 (0%)")
        // A mapped insertion-only CIGAR supports its boundary without supplying a base on either side.
        try viewer.click(420)
        try await viewer.expectPanel("tiny:420", "Base depth 0   A 0   C 0   G 0   T 0   Insertion after this base 1")
        try viewer.click(421)
        try await viewer.expectPanel("tiny:421", "Base depth 0   A 0   C 0   G 0   T 0")
        await viewer.navigate("tiny:1,990-2,000")
        try viewer.click(2_000)
        try await viewer.expectPanel("tiny:2,000", "Base depth 1   A 1 (100%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Insertion after this base 1")
    }

    @Test
    func selectionRequiresAnUnmodifiedClickAtOnePointPerBaseOnABAMContig() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let viewer = try await InspectionWindow(files: files)
        defer { viewer.window.close() }
        let reference = try files.reference("extra.bref", fasta: inspectionReference("R") + "\n>extra\nACGT")
        await viewer.session.openReference(reference)
        let width = Int(viewer.stack.bounds.width)
        await viewer.navigate("tiny:1-\(width)")
        try viewer.click(302)
        let heading = "tiny:302 · Reference R"
        let detail = "Base depth 1   A 0 (0%)   C 0 (0%)   G 0 (0%)   T 0 (0%)   Unresolved = 1 (100%)   Deletions 1   Reference skips 1"
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
            if [1, 100, 300].contains(interval.start) {
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

    func event(_ type: NSEvent.EventType, position: Int64, xOffset: CGFloat = 0, y: CGFloat = 8, count: Int = 1,
               modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let target = try #require(session.presentation.target)
        let x = (CGFloat(position - target.start) + 0.5) * stack.bounds.width / CGFloat(target.end - target.start + 1)
        let point = stack.convert(NSPoint(x: x + xOffset, y: scroll.contentView.bounds.minY + y), to: nil)
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

    func rulerMarkerPixels() throws -> [Int] {
        let ruler = try #require(visibleViews(in: workspace).first { $0.accessibilityLabel() == "Genomic ruler" })
        let image = try renderTrackBitmap(in: ruler, window: window, height: 20)
        return (0..<image.pixelsWide).filter { (image.colorAt(x: $0, y: 11)?.alphaComponent ?? 0) > 0.1 }
    }

    func hasLabel(_ text: String) -> Bool {
        visibleViews(in: workspace).contains { ($0 as? NSTextField)?.stringValue == text }
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
