import Foundation
import Testing
import BamdalfKit

struct RollingPrefetchTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"], [false, true])
    @MainActor
    func rollingRefillClampsAtReferenceEndsWithoutRestartingForClampedMotion(indexFormat: String, rightEnd: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = PrefetchGate()
        defer { Task { await gate.releaseAll() } }
        let session = ViewerSession(loadRegion: { file, interval in
            await gate.recordRequired(interval)
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            await gate.pause(interval)
            return try await file.alignments(in: interval, budget: budget)
        })
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval(rightEnd ? "tiny:19901-20000" : "tiny:1-100")
        await session.submitInterval()?.value
        await gate.waitForOptional(1)
        try Task.checkCancellation()
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: rightEnd ? 1 : -1)
        #expect(session.presentation.target?.formatted == (rightEnd ? "tiny:19,801-19,900" : "tiny:101-200"))
        #expect(!session.presentation.isLoading)
        await gate.releaseNext()
        await gate.waitForOptional(2)
        try Task.checkCancellation()
        #expect(session.endAlignmentDrag() == nil, "The first complete chunk covers the preview's entire R")
        let towardEnd: PanDirection = rightEnd ? .right : .left
        for _ in 0..<2 { #expect(session.pan(towardEnd) == nil) }
        for _ in 0..<12 { #expect(session.pan(towardEnd) == nil) }
        session.beginAlignmentDrag()
        for fraction in [10.0, 100.0, 1e100] {
            session.previewAlignmentDrag(horizontalFraction: rightEnd ? -fraction : fraction)
        }
        #expect(session.endAlignmentDrag() == nil)
        #expect(session.presentation.target?.formatted == (rightEnd ? "tiny:19,901-20,000" : "tiny:1-100"))
        let requested = await gate.optionalIntervals()
        #expect(requested.map(\.formatted) == (rightEnd
            ? ["tiny:19,401-19,650", "tiny:19,301-19,400"]
            : ["tiny:351-600", "tiny:601-700"]))
        #expect(requested.allSatisfy { $0.start >= 1 && $0.end <= 20000 })
        #expect(await gate.requiredCount() == 1)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.releaseAll()
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"])
    @MainActor
    func rollingPansRefillBeforeRequiredCoverageRunsOutAndCoalesceMotion(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = PrefetchGate()
        defer { Task { await gate.releaseAll() } }
        let session = ViewerSession(loadRegion: { file, interval in
            await gate.recordRequired(interval)
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            await gate.pause(interval)
            return try await file.alignments(in: interval, budget: budget)
        })
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:5000-5099")
        await session.submitInterval()?.value
        await gate.waitForOptional(1)
        try Task.checkCancellation()
        #expect(await gate.optionalIntervals().first?.formatted == "tiny:4,500-4,749")
        await gate.releaseNext()
        await gate.waitForOptional(2)
        try Task.checkCancellation()

        // Completed coverage reaches 4500 on the left. The first two 50-base
        // pans leave 200 and 150 bases beyond R; the third leaves only 100.
        // Keep the opposite-side chunk in flight through all three motions.
        for expected in ["tiny:4,950-5,049", "tiny:4,900-4,999", "tiny:4,850-4,949"] {
            #expect(session.pan(.left) == nil)
            #expect(session.presentation.target?.formatted == expected)
            #expect(!session.presentation.isLoading)
        }
        await gate.releaseNext()
        await gate.waitForOptional(3)
        try Task.checkCancellation()
        let intervals = await gate.optionalIntervals()
        #expect(intervals.map(\.formatted) == ["tiny:4,500-4,749", "tiny:5,350-5,599", "tiny:4,350-4,499"])
        #expect(await gate.requiredCount() == 1)
        #expect(session.presentation.target?.formatted == "tiny:4,850-4,949")
        #expect(session.presentation.regionalError == nil)

        // Reverse while that new left chunk is still pending. The completed
        // trailing buffer carries every pan; the next chunk serves the latest
        // rightward demand instead of continuing the obsolete left plan.
        for _ in 0..<7 { #expect(session.pan(.right) == nil) }
        #expect(session.presentation.target?.formatted == "tiny:5,200-5,299")
        await gate.releaseNext()
        await gate.waitForOptional(4)
        try Task.checkCancellation()
        #expect(await gate.optionalIntervals().last?.formatted == "tiny:5,600-5,799")
        #expect(await gate.requiredCount() == 1)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.releaseAll()
    }
}
