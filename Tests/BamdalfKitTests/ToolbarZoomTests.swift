import Testing
import BamdalfKit

struct ToolbarZoomTests {
    @Test(arguments: ["bai", "csi"])
    @MainActor
    func zoomOutDoesNotMoveRetainedRowsWhenInsertionMarkersBecomeCrowded(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "zoom", indexFormat: indexFormat)
        session.editInterval("tiny:1000-1011")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        #expect(original.count == 3)
        let insertions = original.filter { $0.segments.contains { $0.kind == .insertion } }
        #expect(insertions.count == 2)
        #expect(Set(insertions.map(\.row)).count == 1)
        let extent = session.presentation.rowCount
        session.scrollVertically(to: 100)
        for _ in 0..<9 { await session.zoom(.out)?.value }
        // At this scale the five-base separation is less than a one-point
        // marker stroke. Decoration must not repack surviving alignments.
        #expect(session.presentation.target?.formatted == "tiny:1-6,144")
        for retained in original {
            #expect(session.presentation.alignments.first { $0.id == retained.id }?.row == retained.row)
        }
        #expect(session.presentation.rowCount == extent)
        #expect(session.presentation.verticalOffset == 100)
        #expect(!session.presentation.isAlignmentSuppressed)
    }

    @Test(arguments: [true, false])
    @MainActor
    func zoomAtAMinimumOrMaximumPreservesDraftErrorAndPendingLoad(minimum: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            await gate.pause(1)
            return records
        })
        try await files.openedSession(session: session)
        session.editInterval(minimum ? "tiny:101-101" : "tiny:1-2000")
        let pending = session.submitInterval()
        await gate.waitFor(1)
        let target = session.presentation.target
        session.editInterval("tiny:3-2")
        session.submitInterval()
        let error = try #require(session.presentation.intervalError)
        session.scrollVertically(to: 100)
        #expect(session.zoom(minimum ? .in : .out) == nil)
        #expect(session.presentation.target == target)
        #expect(session.presentation.intervalText == "tiny:3-2")
        #expect(session.presentation.intervalError == error)
        #expect(session.presentation.isLoading)
        #expect(session.presentation.verticalOffset == 100)
        await gate.release(1)
        await pending?.value
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.target == target)
        #expect(session.presentation.intervalText == "tiny:3-2")
        #expect(session.presentation.intervalError == error)
        #expect(session.presentation.verticalOffset == 100)
    }

    @Test(arguments: [false, true])
    @MainActor
    func failedZoomRestoresTheSuccessfulViewWhileProtectingANewerDraft(editAfterZoom: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 159 {
                await gate.pause(159)
                throw RegionalLoadError(interval: target, message: "Zoom region failed")
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        session.scrollVertically(to: 100)
        session.editInterval("discard this older draft")
        let pending = session.zoom(.out)
        #expect(session.presentation.intervalText == "tiny:80-159")
        await gate.waitFor(159)
        if editAfterZoom {
            session.editInterval("tiny:9-2")
            session.submitInterval()
        }
        await gate.release(159)
        await pending?.value
        #expect(session.presentation.target?.formatted == "tiny:100-139")
        #expect(session.presentation.alignments == saved)
        #expect(session.presentation.verticalOffset == 0)
        #expect(session.presentation.intervalText == (editAfterZoom ? "tiny:9-2" : "tiny:100-139"))
        #expect((session.presentation.intervalError != nil) == editAfterZoom)
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:80-159")
        #expect(session.presentation.regionalError?.message == "Zoom region failed")
        #expect(!session.presentation.isLoading)
    }

    @Test(arguments: [false, true])
    @MainActor
    func wideZoomSupersedesOlderLoadingAndReturnsFreshUsingAdequateCoverage(failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let requests = ZoomRequests()
        let session = ViewerSession(loadRegion: { file, target in
            await requests.record(target.formatted)
            let records = try await file.alignments(in: target)
            if target.end == 159 {
                await gate.pause(159)
                let attempt = await gate.count(159)
                if failLate && attempt == 1 {
                    throw RegionalLoadError(interval: target, message: "Obsolete zoom failure")
                }
            }
            return records
        }, alignmentVisibilityLimit: 80)
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        session.scrollVertically(to: 100)
        let old = session.zoom(.out)
        await gate.waitFor(159)
        let issued = await requests.values
        #expect(session.zoom(.out) == nil)
        #expect(session.presentation.target?.formatted == "tiny:40-199")
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.message == "Zoom in to see alignments")
        #expect(session.presentation.alignments.isEmpty)
        #expect(!session.presentation.isLoading)
        #expect(await requests.values == issued)
        session.editInterval("newer unfinished draft")
        await gate.release(159)
        await old?.value
        #expect(session.presentation.target?.formatted == "tiny:40-199")
        #expect(session.presentation.intervalText == "newer unfinished draft")
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.alignments.isEmpty)
        let returning = session.zoom(.in)
        #expect(session.presentation.target?.formatted == "tiny:80-159")
        #expect(session.presentation.intervalText == "tiny:80-159")
        #expect(!session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.verticalOffset == 0)
        await gate.waitFor(159)
        session.scrollVertically(to: 200)
        await gate.release(159)
        await returning?.value
        #expect(session.presentation.verticalOffset == 200)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["lead", "anchor", "new_tail"])
        let completeRequests = await requests.values
        #expect(session.zoom(.out) == nil)
        #expect(session.presentation.alignments.isEmpty)
        #expect(session.zoom(.in) == nil)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.verticalOffset == 0)
        #expect(await requests.values == completeRequests)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func zoomRetainsSurvivingRowsAndNewerScrollWhileAdmittingAnEarlierTail(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 159 { await gate.pause(159) }
            return records
        })
        try await files.openedSession(fixture: "navigation", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        #expect(Set(original.map(\.name)) == ["lead", "anchor"])
        session.scrollVertically(to: 100)
        #expect(session.zoom(.in) == nil)
        #expect(session.presentation.target?.formatted == "tiny:110-129")
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.verticalOffset == 100)
        #expect(session.zoom(.out) == nil)
        let pending = session.zoom(.out)
        #expect(session.presentation.target?.formatted == "tiny:80-159")
        await gate.waitFor(159)
        #expect(session.presentation.isLoading)
        #expect(session.presentation.alignments == original)
        session.scrollVertically(to: 200)
        await gate.release(159)
        await pending?.value
        let expanded = session.presentation.alignments
        #expect(Set(expanded.map(\.name)) == ["lead", "anchor", "new_tail"])
        for retained in original { #expect(expanded.first { $0.id == retained.id }?.row == retained.row) }
        let tail = try #require(expanded.first { $0.name == "new_tail" })
        #expect(tail.drawnStart == 50)
        #expect(!original.map(\.row).contains(tail.row))
        #expect(session.presentation.verticalOffset == 200)
        let extent = session.presentation.rowCount
        #expect(session.zoom(.in) == nil)
        #expect(session.presentation.target?.formatted == "tiny:100-139")
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.rowCount == extent)
        #expect(session.presentation.verticalOffset == 200)
        #expect(!session.presentation.isLoading)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func zoomRoundsWidthsUpAndCenterTiesDownThenShiftsWithinTheReference(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(indexFormat: indexFormat)
        #expect(session.zoom(.in) == nil)
        #expect(session.presentation.target == nil)

        // Worked inclusive-coordinate examples, including half-base center ties.
        let examples: [(String, ZoomDirection, String)] = [
            ("tiny:101-110", .in, "tiny:103-107"),
            ("tiny:101-110", .out, "tiny:96-115"),
            ("tiny:101-105", .in, "tiny:102-104"),
            ("tiny:101-105", .out, "tiny:98-107"),
            ("tiny:101-102", .in, "tiny:101-101"),
            ("tiny:101-101", .out, "tiny:100-101"),
            ("tiny:1-5", .out, "tiny:1-10"),
            ("tiny:1996-2000", .out, "tiny:1,991-2,000"),
            ("tiny:1-1", .in, "tiny:1-1"),
            ("tiny:2000-2000", .in, "tiny:2,000-2,000"),
            ("tiny:2000-2000", .out, "tiny:1,999-2,000"),
            ("tiny:1-2000", .in, "tiny:501-1,500"),
            ("tiny:1-2000", .out, "tiny:1-2,000"),
            ("tiny:1-1200", .out, "tiny:1-2,000"),
            ("other_reference:790-799", .out, "other_reference:781-800"),
            ("other_reference:100-700", .out, "other_reference:1-800"),
        ]
        for (input, direction, expected) in examples {
            session.editInterval(input)
            await session.submitInterval()?.value
            let load = session.zoom(direction)
            #expect(session.presentation.target?.formatted == expected)
            #expect(session.presentation.intervalText == expected)
            await load?.value
            #expect(session.presentation.regionalError == nil)
        }
    }
}

private actor ZoomRequests {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
