import Foundation
import Testing
import BamdalfKit

struct RollingPressureTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"])
    @MainActor
    func fractionalMotionDoesNotRetryAnUnretainableOptionalRangeAndReleaseLoadsIt(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let optional = PrefetchGate()
        let refreshed = RegionGate()
        let required = PressureRequiredQueries()
        defer {
            Task {
                await optional.releaseAll()
                await refreshed.release(1)
            }
        }
        let session = ViewerSession(prefetch: .init(maximumBytes: 600), loadRegion: { file, interval in
            await required.record(interval)
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            await optional.pause(interval)
            return try await file.alignments(in: interval, budget: budget)
        })
        defer { session.onPresentationChange = nil }
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:5000-5099")
        await session.submitInterval()?.value
        await optional.waitForOptional(1)
        try Task.checkCancellation()
        await optional.releaseNext()
        await optional.waitForOptional(2)
        try Task.checkCancellation()

        // The two empty neighboring chunks fit the small budget. At this
        // fractional preview, R ends at 5601, two bases beyond their coverage.
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -2.511)
        #expect(session.presentation.target?.formatted == "tiny:5,251-5,350")
        #expect(abs(session.presentation.previewOffsetInBases - 0.1) < 0.000001)
        await optional.releaseNext()
        await optional.waitForOptional(3)
        try Task.checkCancellation()
        #expect(await optional.optionalIntervals().map(\.formatted) == [
            "tiny:4,500-4,749", "tiny:5,350-5,599", "tiny:5,600-5,601",
        ])

        // This successful empty query cannot be retained alongside the closer
        // chunks. Wait for the public preview refresh to prove admission and
        // trimming have run, rather than only waiting for the reader to return.
        session.onPresentationChange = {
            Task { await refreshed.pause(1) }
        }
        await optional.releaseNext()
        await refreshed.waitFor(1)
        try Task.checkCancellation()
        session.onPresentationChange = nil
        await refreshed.release(1)
        #expect(session.presentation.alignments.isEmpty)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)

        // Only the fractional pointer position changes; V/R endpoints stay
        // identical. Optional work must remember the pressure outcome instead
        // of decoding 5600...5601 again in a newly started task.
        session.previewAlignmentDrag(horizontalFraction: -2.512)
        await optional.waitForOptional(4)
        try Task.checkCancellation()
        let nextOptional = await optional.optionalIntervals().last?.formatted
        #expect(nextOptional == "tiny:5,602-5,851")
        #expect(session.presentation.target?.formatted == "tiny:5,251-5,350")
        #expect(abs(session.presentation.previewOffsetInBases - 0.2) < 0.000001)

        // Pressure suppression is optional-only. The rounded committed R ends
        // at 5600, and release must still fetch that missing base normally.
        let pending = session.endAlignmentDrag()
        #expect(pending != nil)
        #expect(session.presentation.isLoading)
        await pending?.value
        #expect(await required.intervals().map(\.formatted) == ["tiny:4,750-5,349", "tiny:5,600-5,600"])
        #expect(session.presentation.target?.formatted == "tiny:5,251-5,350")
        #expect(session.presentation.alignments.isEmpty)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await optional.releaseAll()
    }
}

private actor PressureRequiredQueries {
    private var requested: [GenomicInterval] = []

    func record(_ interval: GenomicInterval) { requested.append(interval) }
    func intervals() -> [GenomicInterval] { requested }
}
