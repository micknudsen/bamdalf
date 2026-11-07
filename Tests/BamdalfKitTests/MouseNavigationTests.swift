import Testing
import BamdalfKit

struct MouseNavigationTests {
    @Test(arguments: ["bai", "csi"])
    @MainActor
    func recordsAdmittedDuringPreviewKeepTheirRowsThroughFurtherMotionAndRelease(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "navigation", indexFormat: indexFormat)
        // Cache the newcomer, then enter a fresh layout containing only lead/anchor.
        for target in ["tiny:120-159", "tiny:500-539", "tiny:100-139"] {
            session.editInterval(target)
            await session.submitInterval()?.value
        }
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -0.5)
        let newcomer = try #require(session.presentation.alignments.first { $0.name == "new_tail" })
        #expect(newcomer.row == 2)
        let extent = session.presentation.rowCount
        session.previewAlignmentDrag(horizontalFraction: -0.75)
        #expect(session.presentation.target?.formatted == "tiny:130-169")
        #expect(session.presentation.alignments.first { $0.id == newcomer.id }?.row == newcomer.row)
        #expect(session.presentation.rowCount >= extent)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.alignments.first { $0.id == newcomer.id }?.row == newcomer.row)
        #expect(session.presentation.rowCount >= extent)
    }

    @Test(arguments: [false, true])
    @MainActor
    func newNavigationOrBAMReplacementRetiresAnUncommittedDrag(replaceBAM: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "navigation")
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -0.5)
        if replaceBAM {
            try await files.openedSession(fixture: "opening", session: session)
            #expect(session.presentation.target == nil)
        } else {
            session.editInterval("tiny:500-539")
            await session.submitInterval()?.value
            #expect(session.presentation.target?.formatted == "tiny:500-539")
            #expect(!session.presentation.isLoading)
        }
        let current = session.presentation
        session.previewAlignmentDrag(horizontalFraction: -1)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.target == current.target)
        #expect(session.presentation.bamURL == current.bamURL)
        #expect(session.presentation.intervalText == current.intervalText)
        #expect(session.presentation.alignments == current.alignments)
        #expect(!session.presentation.isLoading)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func clickedLocusZoomUsesTheHitBaseAndLowerCoordinateCenterTies(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(indexFormat: indexFormat)
        let cases: [(String, ZoomDirection, Double, String)] = [
            ("tiny:101-140", .in, 0.25, "tiny:101-120"),
            ("tiny:101-140", .in, 0, "tiny:91-110"),
            ("tiny:101-140", .in, 0.99, "tiny:130-149"),
            ("tiny:101-140", .out, 0.5, "tiny:81-160"),
            ("tiny:101-105", .in, 0.4, "tiny:102-104"),
            ("tiny:1-5", .out, 0, "tiny:1-10"),
            ("tiny:1996-2000", .out, 1, "tiny:1,991-2,000"),
            ("tiny:1-2000", .in, 0, "tiny:1-1,000"),
            ("tiny:1-2000", .out, 0, "tiny:1-2,000"),
            ("tiny:101-101", .in, 0, "tiny:101-101"),
            ("tiny:101-101", .out, 0, "tiny:100-101"),
        ]
        for (input, direction, fraction, expected) in cases {
            session.editInterval(input)
            await session.submitInterval()?.value
            await session.zoom(direction, atHorizontalFraction: fraction)?.value
            #expect(session.presentation.target?.formatted == expected)
            #expect(session.presentation.intervalText == expected)
        }
    }

    @Test(arguments: [false, true])
    @MainActor
    func unchangedReleaseAllowsTheExistingLoadToFinishWithoutReplacingANewerDraft(failOlder: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 159 {
                await gate.pause(159)
                if failOlder { throw RegionalLoadError(interval: target, message: "Existing request failed") }
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let older = session.pan(.right)
        await gate.waitFor(159)
        session.editInterval("tiny:9-2")
        session.submitInterval()
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -1)
        await gate.release(159)
        await older?.value
        #expect(session.presentation.target?.formatted == "tiny:160-199")
        session.previewAlignmentDrag(horizontalFraction: 0)
        await session.endAlignmentDrag()?.value
        #expect(await gate.count(159) == 1)
        #expect(session.presentation.target?.formatted == (failOlder ? "tiny:100-139" : "tiny:120-159"))
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError != nil)
        #expect(!session.presentation.isLoading)
        #expect((session.presentation.regionalError != nil) == failOlder)
        #expect(session.presentation.alignments.contains { $0.name == "new_tail" } == !failOlder)
    }

    @Test
    @MainActor
    func dragRoundsHalfBaseDisplacementsAwayFromZeroAndClampsWithoutShrinking() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession()
        let cases: [(String, Double, String)] = [
            ("tiny:100-104", 0.1, "tiny:99-103"),
            ("tiny:100-104", -0.1, "tiny:101-105"),
            ("tiny:100-104", 0.09, "tiny:100-104"),
            ("tiny:100-104", -0.09, "tiny:100-104"),
            ("tiny:1-5", 1, "tiny:1-5"),
            ("tiny:1996-2000", -1, "tiny:1,996-2,000"),
            ("tiny:100-104", 1e100, "tiny:1-5"),
            ("tiny:100-104", -1e100, "tiny:1,996-2,000"),
            ("tiny:100-104", .nan, "tiny:100-104"),
        ]
        for (input, fraction, expected) in cases {
            session.editInterval(input)
            await session.submitInterval()?.value
            session.editInterval("preserve during preview")
            session.beginAlignmentDrag()
            session.previewAlignmentDrag(horizontalFraction: fraction)
            #expect(session.presentation.target?.formatted == expected)
            #expect(session.presentation.intervalText == "preserve during preview")
            await session.endAlignmentDrag()?.value
            #expect(session.presentation.target?.formatted == expected)
        }
    }

    @Test(arguments: [false, true])
    @MainActor
    func completionDuringDragCannotReplacePreviewOrItsSuccessfulRestorationPoint(failOlder: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 159 {
                await gate.pause(159)
                if failOlder { throw RegionalLoadError(interval: target, message: "Older failed") }
            }
            if target.end == 199 { throw RegionalLoadError(interval: target, message: "Committed drag failed") }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        let older = session.pan(.right)
        await gate.waitFor(159)
        session.editInterval("tiny:9-2")
        session.submitInterval()
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -1)
        let preview = session.presentation.alignments
        session.scrollVertically(to: 200)
        await gate.release(159)
        await older?.value
        #expect(session.presentation.target?.formatted == "tiny:160-199")
        #expect(session.presentation.alignments == preview)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError != nil)
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.verticalOffset == 200)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.target?.formatted == "tiny:100-139")
        #expect(session.presentation.alignments == saved)
        #expect(session.presentation.intervalText == "tiny:100-139")
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:160-199")
    }

    @Test(arguments: [false, true])
    @MainActor
    func changedDragReleaseLoadsMissingDataAndRestoresTheLastCommittedViewOnFailure(fail: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            if target.end == 159 {
                await gate.pause(159)
                if fail { throw RegionalLoadError(interval: target, message: "Drag target failed") }
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        session.editInterval("older rejected draft")
        session.submitInterval()
        session.scrollVertically(to: 100)
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -0.5)
        #expect(await gate.count(159) == 0)
        let pending = session.endAlignmentDrag()
        #expect(session.presentation.target?.formatted == "tiny:120-159")
        #expect(session.presentation.intervalText == "tiny:120-159")
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.isLoading)
        guard pending != nil else { return }
        await gate.waitFor(159)
        session.scrollVertically(to: 200)
        session.editInterval("tiny:8-2")
        session.submitInterval()
        await gate.release(159)
        await pending?.value
        #expect(session.presentation.intervalText == "tiny:8-2")
        #expect(session.presentation.intervalError != nil)
        #expect(!session.presentation.isLoading)
        if fail {
            #expect(session.presentation.target?.formatted == "tiny:100-139")
            #expect(session.presentation.alignments == saved)
            #expect(session.presentation.verticalOffset == 0)
            #expect(session.presentation.regionalError?.interval.formatted == "tiny:120-159")
        } else {
            #expect(session.presentation.target?.formatted == "tiny:120-159")
            #expect(Set(session.presentation.alignments.map(\.name)) == ["lead", "anchor", "new_tail"])
            for retained in saved { #expect(session.presentation.alignments.first { $0.id == retained.id }?.row == retained.row) }
            #expect(session.presentation.verticalOffset == 200)
            #expect(session.presentation.regionalError == nil)
        }
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func dragPreviewUsesLoadedGeometryWithoutLoadingOrChangingDrafts(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let requests = MouseRequests()
        let session = ViewerSession(loadRegion: { file, target in
            await requests.record(target.formatted)
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:100-139")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        let requested = await requests.values
        session.editInterval("tiny:9-2")
        session.submitInterval()
        let error = try #require(session.presentation.intervalError)
        session.scrollVertically(to: 100)
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -0.5)
        #expect(session.presentation.target?.formatted == "tiny:120-159")
        #expect(Set(session.presentation.alignments.map(\.name)) == ["lead", "anchor"])
        for retained in original {
            #expect(session.presentation.alignments.first { $0.id == retained.id }?.row == retained.row)
        }
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError == error)
        #expect(session.presentation.verticalOffset == 100)
        #expect(!session.presentation.isLoading)
        #expect(await requests.values == requested)

        // Preview displacement is relative to pointer-down, not accumulated.
        session.previewAlignmentDrag(horizontalFraction: 0)
        #expect(session.presentation.target?.formatted == "tiny:100-139")
        #expect(session.presentation.alignments == original)
        #expect(session.endAlignmentDrag() == nil)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError == error)
        #expect(await requests.values == requested)
    }
}

private actor MouseRequests {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
