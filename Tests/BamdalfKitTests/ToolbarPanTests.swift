import Testing
import BamdalfKit

struct ToolbarPanTests {
    @Test
    @MainActor
    func oneBasePansPreserveRetainedRowsAndScrollDespiteNonoverlappingCoordinates() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "navigation")
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        session.editInterval("tiny:120-120")
        await session.submitInterval()?.value
        let anchor = try #require(session.presentation.alignments.first { $0.name == "anchor" })
        let extent = session.presentation.rowCount
        session.scrollVertically(to: 100)
        #expect(session.pan(.right) == nil)
        #expect(session.presentation.target?.formatted == "tiny:121-121")
        #expect(Set(session.presentation.alignments.map(\.name)) == ["anchor", "new_tail"])
        #expect(session.presentation.alignments.first { $0.id == anchor.id }?.row == anchor.row)
        #expect(session.presentation.rowCount == extent)
        #expect(session.presentation.verticalOffset == 100)
    }

    @Test
    @MainActor
    func rulerOnlyPansUpdateCoordinatesWithoutQueryingOrDrawing() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(loadRegion: { _, target in
            throw RegionalLoadError(interval: target, message: "A ruler-only pan must not query")
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:1-15000")
        #expect(session.submitInterval() == nil)
        #expect(session.pan(.right) == nil)
        #expect(session.presentation.target?.formatted == "tiny:5,001-20,000")
        #expect(session.presentation.intervalText == "tiny:5,001-20,000")
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.message == "Zoom in to see alignments")
        #expect(session.presentation.alignments.isEmpty)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
        #expect(session.pan(.left) == nil)
        #expect(session.presentation.target?.formatted == "tiny:1-15,000")
    }

    @Test(arguments: [false, true])
    @MainActor
    func failedPanRestoresTheSuccessfulViewAndProtectsOnlyANewerDraft(editAfterPan: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 409 {
                await gate.pause(159)
                throw RegionalLoadError(interval: target, message: "Pan region failed")
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        session.scrollVertically(to: 100)
        session.editInterval("discard this older draft")
        let pending = session.pan(.right)
        await gate.waitFor(159)
        if editAfterPan {
            session.editInterval("tiny:9-2")
            session.submitInterval()
        }
        await gate.release(159)
        await pending?.value
        #expect(session.presentation.target?.formatted == "tiny:100-139")
        #expect(session.presentation.alignments == saved)
        #expect(session.presentation.verticalOffset == 0)
        #expect(session.presentation.intervalText == (editAfterPan ? "tiny:9-2" : "tiny:100-139"))
        #expect((session.presentation.intervalError != nil) == editAfterPan)
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:120-159")
        #expect(session.presentation.regionalError?.message == "Pan region failed")
        #expect(!session.presentation.isLoading)
    }

    @Test(arguments: [false, true])
    @MainActor
    func aLaterPanWinsOverAnOlderSuccessOrFailure(failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 409 {
                await gate.pause(159)
                if failLate { throw RegionalLoadError(interval: target, message: "Old pan failed") }
            }
            return records
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let old = session.pan(.right)
        await gate.waitFor(159)
        await session.pan(.right)?.value
        #expect(session.presentation.target?.formatted == "tiny:140-179")
        let accepted = session.presentation.alignments
        session.editInterval("newer draft")
        await gate.release(159)
        await old?.value
        #expect(session.presentation.target?.formatted == "tiny:140-179")
        #expect(session.presentation.alignments == accepted)
        #expect(session.presentation.intervalText == "newer draft")
        #expect(session.presentation.regionalError == nil)
        #expect(!session.presentation.isLoading)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func pansAcrossMissingAndReusedCoverageKeepSurvivingRowsAndNewerScroll(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 409 { await gate.pause(159) }
            return records
        })
        try await files.openedSession(fixture: "navigation", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        #expect(Set(original.map(\.name)) == ["lead", "anchor", "new_tail"])
        session.scrollVertically(to: 100)
        let pending = session.pan(.right)
        #expect(session.presentation.target?.formatted == "tiny:120-159")
        await gate.waitFor(159)
        #expect(session.presentation.isLoading)
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.verticalOffset == 100)
        session.scrollVertically(to: 200)
        await gate.release(159)
        await pending?.value
        #expect(session.presentation.verticalOffset == 200)
        let withNewcomer = session.presentation.alignments
        #expect(Set(withNewcomer.map(\.name)) == ["lead", "anchor", "new_tail"])
        for retained in original {
            #expect(withNewcomer.first { $0.id == retained.id }?.row == retained.row)
        }
        let tail = try #require(withNewcomer.first { $0.name == "new_tail" })
        #expect(tail.drawnStart == 50)
        #expect(original.first { $0.id == tail.id }?.row == tail.row)
        let extent = session.presentation.rowCount
        await session.pan(.right)?.value
        #expect(session.presentation.target?.formatted == "tiny:140-179")
        #expect(session.presentation.rowCount == extent)
        #expect(session.presentation.verticalOffset == 200)
        for retained in session.presentation.alignments {
            #expect(withNewcomer.first { $0.id == retained.id }?.row == retained.row)
        }
        #expect(session.pan(.left) == nil)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.target?.formatted == "tiny:120-159")
        #expect(session.presentation.rowCount == extent)
        #expect(session.presentation.verticalOffset == 200)
    }

    @Test
    @MainActor
    func changedPansReplaceRejectedInputButBoundaryPansPreserveDraftAndPendingLoad() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.start == 1741 { await gate.pause(2000) }
            return records
        })
        try await files.openedSession(session: session)
        session.editInterval("tiny:1981-1990")
        await session.submitInterval()?.value
        session.editInterval("tiny:2-1")
        session.submitInterval()
        #expect(session.presentation.intervalError != nil)
        await session.pan(.right)?.value
        #expect(session.presentation.target?.formatted == "tiny:1,986-1,995")
        #expect(session.presentation.intervalText == "tiny:1,986-1,995")
        #expect(session.presentation.intervalError == nil)

        // Padding already covers the boundary after a nearby pan. Reopen to
        // exercise a boundary no-op while its first required query is pending.
        try await files.openedSession(session: session)
        session.editInterval("tiny:1991-2000")
        let pending = session.submitInterval()
        await gate.waitFor(2000)
        session.editInterval("tiny:3-2")
        session.submitInterval()
        let error = session.presentation.intervalError
        session.scrollVertically(to: 50)
        #expect(session.pan(.right) == nil)
        #expect(session.presentation.intervalText == "tiny:3-2")
        #expect(session.presentation.intervalError == error)
        #expect(session.presentation.isLoading)
        #expect(session.presentation.verticalOffset == 50)
        await gate.release(2000)
        await pending?.value
        #expect(session.presentation.intervalText == "tiny:3-2")
        #expect(session.presentation.intervalError == error)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.target?.formatted == "tiny:1,991-2,000")
        #expect(session.presentation.verticalOffset == 50)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func panRoundsHalfSpansUpAndClampsWithoutChangingReferenceOrWidth(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(indexFormat: indexFormat)
        #expect(session.pan(.left) == nil)
        #expect(session.presentation.target == nil)

        // Independently worked examples use inclusive widths. Odd halves round
        // up in both directions, including a one-base pan taking one base.
        let examples: [(String, PanDirection, String)] = [
            ("tiny:101-110", .right, "tiny:106-115"),
            ("tiny:101-110", .left, "tiny:96-105"),
            ("tiny:101-105", .right, "tiny:104-108"),
            ("tiny:101-105", .left, "tiny:98-102"),
            ("tiny:101-101", .right, "tiny:102-102"),
            ("tiny:101-101", .left, "tiny:100-100"),
            ("tiny:2-11", .left, "tiny:1-10"),
            ("tiny:1990-1999", .right, "tiny:1,991-2,000"),
            ("tiny:1-1", .left, "tiny:1-1"),
            ("tiny:2000-2000", .right, "tiny:2,000-2,000"),
            ("tiny:1-2000", .left, "tiny:1-2,000"),
            ("tiny:1-2000", .right, "tiny:1-2,000"),
            ("other_reference:790-799", .right, "other_reference:791-800"),
        ]
        for (input, direction, expected) in examples {
            session.editInterval(input)
            await session.submitInterval()?.value
            let load = session.pan(direction)
            #expect(session.presentation.target?.formatted == expected)
            #expect(session.presentation.intervalText == expected)
            await load?.value
            #expect(session.presentation.regionalError == nil)
        }
    }
}
