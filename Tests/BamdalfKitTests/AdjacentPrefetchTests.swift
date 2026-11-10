import Foundation
import Testing
import BamdalfKit

struct AdjacentPrefetchTests {
    @Test
    @MainActor
    func rulerOnlyTransitionReleasesPriorRequiredProtection() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .init(maximumBytes: 1))
        try await files.openedSession(fixture: "rows", session: session)
        session.editInterval("tiny:100-200")
        await session.submitInterval()?.value
        let saved = Set(session.presentation.alignments.map(\.id))
        session.editInterval("tiny:1-20000")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(!session.presentation.isLoading)
        session.editInterval("tiny:100-200")
        let reload = session.submitInterval()
        #expect(reload != nil, "A ruler-only view no longer protects the former alignment region")
        await reload?.value
        #expect(Set(session.presentation.alignments.map(\.id)) == saved)
        #expect(session.presentation.alignments.count == 80)
        #expect(session.presentation.regionalError == nil)
    }

    @Test
    @MainActor
    func failedTargetPartialDataLosesRequiredProtectionAfterRestoration() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .init(maximumBytes: 1), loadRegion: { file, interval in
            if interval.start == 1261 {
                throw RegionalLoadError(interval: interval, message: "Expanded right edge failed")
            }
            return try await file.alignments(in: interval)
        })
        try await files.openedSession(fixture: "rows", session: session)
        session.editInterval("tiny:1000-1010")
        await session.submitInterval()?.value
        let saved = session.presentation
        session.editInterval("tiny:100-1500")
        await session.submitInterval()?.value
        #expect(session.presentation.regionalError != nil)
        #expect(session.presentation.target == saved.target)
        #expect(session.presentation.alignments == saved.alignments)
        session.editInterval("tiny:100-200")
        let reload = session.submitInterval()
        #expect(reload != nil, "The failed target's old left edge must no longer bypass the optional byte budget")
        await reload?.value
        #expect(session.presentation.alignments.count == 80)
        #expect(Set(session.presentation.alignments.map(\.id)).count == 80)
        #expect(session.presentation.regionalError == nil)
    }

    @Test(arguments: ["bai", "csi"], [3, 100])
    @MainActor
    func budgetedPrefetchAndMixedCoveragePreserveCompleteCandidatesAndSamples(indexFormat: String, budget: Int) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .init(maximumBytes: 1024), samplingGroupBudget: budget,
                                    samplingSeed: { 42 }, samplingPriority: { _, identity in UInt64(identity.last!) })
        try await files.openedSession(fixture: "bounded-tails", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        let expectedNames = budget == 3 ? ["left_boundary", "right_boundary", "supplementary"] : [
            "deletion", "left_boundary", "left_reverse", "missing", "right_boundary", "right_forward",
            "right_reverse", "same", "same", "shared", "skip", "supplementary",
        ]
        #expect(session.presentation.alignments.map(\.name).sorted() == expectedNames)
        let expected = Set(session.presentation.alignments.map(\.id))
        for route in [["tiny:9500-10500"], ["tiny:9700-9749", "tiny:10261-10300"], ["tiny:20000-20010", "tiny:50000-50010"]] {
            for target in route {
                session.editInterval(target)
                await session.submitInterval()?.value
            }
            session.editInterval("tiny:10001-10010")
            await session.submitInterval()?.value
            #expect(Set(session.presentation.alignments.map(\.id)) == expected)
            #expect(session.presentation.alignments.map(\.name).sorted() == expectedNames)
            #expect(session.presentation.isDownsampled == (budget == 3))
            #expect(!session.presentation.isLoading)
            #expect(session.presentation.regionalError == nil)
        }
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
    }

    @Test
    @MainActor
    func visibleRecordsDoNotMakeAMissingRequiredEdgeReady() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let optional = PrefetchGate()
        let required = RegionGate()
        let session = ViewerSession(loadRegion: { file, interval in
            if interval.end == 10760 { await required.pause(1) }
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            await optional.pause(interval)
            return try await file.alignments(in: interval, budget: budget)
        })
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        await optional.waitForOptional(1)
        session.editInterval("tiny:10001-10510")
        let pending = session.submitInterval()
        await required.waitFor(1)
        #expect(!session.presentation.alignments.isEmpty)
        #expect(session.presentation.isLoading)
        #expect(await optional.optionalIntervals().count == 1)
        await required.release(1)
        await pending?.value
        await optional.waitForOptional(2)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await optional.releaseAll()
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func completeEmptyOptionalCoverageIsReusable(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let optional = PrefetchGate()
        let session = ViewerSession(loadRegion: { file, interval in
            await optional.recordRequired(interval)
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            await optional.pause(interval)
            return try await file.alignments(in: interval, budget: budget)
        })
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:5000-5099")
        await session.submitInterval()?.value
        await optional.waitForOptional(1)
        await optional.releaseNext()
        await optional.waitForOptional(2)
        #expect(await optional.optionalIntervals().first?.formatted == "tiny:4,500-4,749")
        session.editInterval("tiny:4950-5049")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments.isEmpty)
        #expect(!session.presentation.isLoading)
        #expect(await optional.requiredCount() == 1)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await optional.releaseAll()
    }

    @Test(arguments: [false, true])
    @MainActor
    func optionalFailureIsQuietAndSuppressedButRequiredNavigationRetries(failRequired: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let optional = PrefetchGate()
        let required = RegionGate()
        let session = ViewerSession(loadRegion: { file, interval in
            if interval.start < 9751 {
                await required.pause(1)
                if failRequired { throw RegionalLoadError(interval: interval, message: "Required retry failed") }
            }
            return try await file.alignments(in: interval)
        }, samplingGroupBudget: 1, samplingSeed: { 9 }, loadPrefetchRegion: { file, interval, budget in
            let ordinal = await optional.pause(interval)
            if ordinal == 1 { throw RegionalLoadError(interval: interval, message: "Optional edge failed") }
            return try await file.alignments(in: interval, budget: budget)
        })
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        await optional.waitForOptional(1)
        let ready = session.presentation
        await optional.releaseNext()
        await optional.waitForOptional(2)
        #expect(session.presentation.alignments == ready.alignments)
        #expect(session.presentation.isDownsampled == ready.isDownsampled)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)

        // A new ready zoom requests buffers again but does not retry the failed
        // left range. Its next controlled request is on the right.
        await session.zoom(.in)?.value
        await optional.waitForOptional(3)
        let intervals = await optional.optionalIntervals()
        #expect(intervals[0].formatted == "tiny:9,501-9,750")
        #expect(intervals.dropFirst().allSatisfy { $0.start > 10000 })
        let recovery = session.presentation
        session.scrollVertically(to: 200)
        session.editInterval("tiny:9751-9760")
        let load = session.submitInterval()
        #expect(load != nil)
        await required.waitFor(1)
        #expect(session.presentation.isLoading)
        session.editInterval("newer draft")
        await optional.releaseAll()
        await required.release(1)
        await load?.value
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.intervalText == "newer draft")
        if failRequired {
            #expect(session.presentation.target == recovery.target)
            #expect(session.presentation.alignments == recovery.alignments)
            #expect(session.presentation.regionalError?.interval.formatted == "tiny:9,751-9,760")
            #expect(session.presentation.verticalOffset == 0)
        } else {
            #expect(session.presentation.target?.formatted == "tiny:9,751-9,760")
            #expect(session.presentation.regionalError == nil)
            #expect(!session.presentation.alignments.isEmpty)
        }
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func smallOptionalBudgetDoesNotKeepEveryOverlappingRequiredSnapshot(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .init(maximumBytes: 1))
        try await files.openedSession(fixture: "bounded-tails", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        for shift in 1...10 {
            session.editInterval("tiny:\(10001 + shift)-\(10010 + shift)")
            await session.submitInterval()?.value
            #expect(!session.presentation.isLoading)
            #expect(session.presentation.regionalError == nil)
        }
        session.editInterval("tiny:10001-10010")
        let reload = session.submitInterval()
        #expect(reload != nil, "Old edge coverage outside current R must compete for the optional byte budget")
        await reload?.value
        #expect(Set(session.presentation.alignments.map(\.id)) == Set(original.map(\.id)))
        #expect(session.presentation.regionalError == nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"])
    @MainActor
    func requiredReadinessPrecedesOptionalCoverageAndNearbyPanReusesIt(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = PrefetchGate()
        let session = ViewerSession(loadRegion: { file, target in
            await gate.recordRequired(target)
            return try await file.alignments(in: target)
        }, samplingGroupBudget: 1, samplingSeed: { 5 }, loadPrefetchRegion: { file, target, budget in
            await gate.pause(target)
            return try await file.alignments(in: target, budget: budget)
        })
        try await files.openedSession(fixture: "bounded-tails", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        let ready = session.presentation
        #expect(!ready.isLoading)
        #expect(ready.isDownsampled)
        await gate.waitForOptional(1)
        try Task.checkCancellation()
        #expect(session.presentation.alignments == ready.alignments)
        #expect(session.presentation.rowCount == ready.rowCount)
        #expect(session.presentation.isDownsampled)
        #expect(!session.presentation.isLoading)
        await gate.releaseNext()
        await gate.waitForOptional(2)
        // One side is complete, and the opposite query has started. Release it
        // before navigating; foreground cancellation must safely close it.
        await gate.releaseNext()
        let requested = await gate.optionalIntervals()
        let side = requested[0]
        let next = side.end < 9751 ? "tiny:9996-10005" : "tiny:10006-10015"
        session.editInterval(next)
        #expect(session.submitInterval() == nil, "The completed adjacent chunk covers this nearby target")
        #expect(!session.presentation.isLoading)
        #expect(await gate.requiredCount() == 1)
        #expect(session.presentation.regionalError == nil)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.releaseAll()
    }
}

actor PrefetchGate {
    private var required: [GenomicInterval] = []
    private var optional: [GenomicInterval] = []
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    private var released = false

    func recordRequired(_ interval: GenomicInterval) { required.append(interval) }
    func requiredCount() -> Int { required.count }
    func optionalIntervals() -> [GenomicInterval] { optional }

    @discardableResult
    func pause(_ interval: GenomicInterval) async -> Int {
        optional.append(interval)
        let ordinal = optional.count
        let ready = observers.filter { $0.0 <= optional.count }
        observers.removeAll { $0.0 <= optional.count }
        for (_, continuation) in ready { continuation.resume() }
        guard !released else { return ordinal }
        await withCheckedContinuation { pending.append($0) }
        return ordinal
    }

    func waitForOptional(_ count: Int) async {
        guard optional.count < count, !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { observers.append((count, $0)) }
        } onCancel: {
            Task { await self.cancelWaiters() }
        }
    }

    private func cancelWaiters() {
        for (_, continuation) in observers { continuation.resume() }
        observers.removeAll()
    }

    func releaseNext() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().resume()
    }

    func releaseAll() {
        released = true
        for continuation in pending { continuation.resume() }
        pending.removeAll()
    }
}
