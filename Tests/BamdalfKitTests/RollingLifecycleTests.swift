import Foundation
import Testing
import BamdalfKit

struct RollingLifecycleTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    @MainActor
    func validNavigationRetiresActiveRefillButCanceledAndFailedReplacementPreserveTheGesture(replaceBAM: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RollingLifecycleGate()
        defer { Task { await gate.finish() } }
        let session = ViewerSession(loadRegion: { file, interval in
            if interval.start > 15000 || file.url.lastPathComponent == "rows.bam" {
                await gate.hold("destination required")
            }
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            let records = try await file.alignments(in: interval, budget: budget)
            if file.url.lastPathComponent == "bounded-tails.bam", interval.start <= 9751, interval.end >= 9751 {
                await gate.hold("refill")
                await gate.signal("returned:refill")
                if !replaceBAM { throw RegionalLoadError(interval: interval, message: "Obsolete refill failed") }
            }
            if interval.start <= 10011, interval.end >= 10011 { await gate.signal("cluster decoded") }
            return records
        })
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:10401-10410")
        await session.submitInterval()?.value
        await gate.waitFor("cluster decoded")
        try Task.checkCancellation()
        session.editInterval("tiny:9-2")
        session.submitInterval()
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: 39.95)
        await gate.waitFor("started:refill")
        try Task.checkCancellation()
        let preview = session.presentation
        await session.openBAM(nil)
        await session.openBAM(files.sources.appendingPathComponent("opening.bam"))
        await session.chooseIndex(nil)
        await session.openBAM(files.directory.appendingPathComponent("absent.bam"))
        #expect(session.presentation.openError != nil)
        session.dismissOpenError()
        #expect(session.presentation.sessionID == preview.sessionID)
        #expect(session.presentation.target == preview.target)
        #expect(session.presentation.previewOffsetInBases == preview.previewOffsetInBases)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError != nil)
        #expect(!(await gate.hasEvent("canceled:refill")))

        if replaceBAM { try await files.openedSession(fixture: "rows", session: session) }
        let destination = replaceBAM ? "tiny:10001-10010" : "tiny:20001-20010"
        session.editInterval(destination)
        let pending = session.submitInterval()
        #expect(pending != nil)
        await gate.waitFor("started:destination required")
        await gate.waitFor("canceled:refill")
        try Task.checkCancellation()
        session.editInterval("new destination draft")
        session.scrollVertically(to: 100)
        await gate.release("refill")
        await gate.waitFor("returned:refill")
        await gate.release("destination required")
        await pending?.value
        let delivered = session.presentation
        #expect(delivered.target?.formatted == (replaceBAM ? "tiny:10,001-10,010" : "tiny:20,001-20,010"))
        #expect(delivered.alignments.isEmpty)
        #expect(delivered.regionalError == nil)
        #expect(delivered.intervalText == "new destination draft")
        #expect(delivered.previewOffsetInBases == 0)
        #expect(delivered.verticalOffset == 100)
        #expect(!delivered.isLoading)
        #expect((delivered.sessionID != preview.sessionID) == replaceBAM)
        // A late pointer event from the retired gesture cannot move the new
        // target, publish the old file's tail, or restore its invalid draft.
        session.previewAlignmentDrag(horizontalFraction: -100)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.target == delivered.target)
        #expect(session.presentation.alignments == delivered.alignments)
        #expect(session.presentation.intervalText == delivered.intervalText)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.finish()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    @MainActor
    func failedRefillCanRevealTailGeometryButReleaseStillRetriesItsMissingCoverage(failRequired: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RollingLifecycleGate()
        defer { Task { await gate.finish() } }
        let session = ViewerSession(loadRegion: { file, interval in
            if interval.start <= 9751, interval.end >= 9751 {
                await gate.hold("required retry")
                if failRequired { throw RegionalLoadError(interval: interval, message: "Required retry failed") }
            }
            return try await file.alignments(in: interval)
        }, samplingGroupBudget: 3, samplingSeed: { 42 },
                                    samplingPriority: { _, identity in UInt64(identity.last!) },
                                    loadPrefetchRegion: { file, interval, budget in
            await gate.attempted(interval)
            if interval.start <= 9751, interval.end >= 9751 {
                await gate.hold("optional failure")
                throw RegionalLoadError(interval: interval, message: "Optional required-edge chunk failed")
            }
            let records = try await file.alignments(in: interval, budget: budget)
            if interval.start <= 10011, interval.end >= 10011 { await gate.signal("cluster decoded") }
            return records
        })
        defer { session.onPresentationChange = nil }
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:10401-10410")
        await session.submitInterval()?.value
        let committed = session.presentation
        await gate.waitFor("cluster decoded")
        try Task.checkCancellation()
        session.editInterval("tiny:9-2")
        session.submitInterval()
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: 39.95)
        session.scrollVertically(to: 200)
        await gate.waitFor("started:optional failure")
        try Task.checkCancellation()
        let expected = ["left_boundary", "right_boundary", "supplementary"]
        session.onPresentationChange = {
            if session.presentation.alignments.map(\.name).sorted() == expected {
                Task { await gate.signal("tail geometry displayed") }
            }
        }
        await gate.release("optional failure")
        // The following complete optional chunk below R includes the record
        // ending at 9751. Its full tail can be drawn even though the failed
        // required edge 9751...9900 still has no completed coverage.
        await gate.waitFor("tail geometry displayed")
        try Task.checkCancellation()
        session.onPresentationChange = nil
        #expect(session.presentation.target?.formatted == "tiny:10,001-10,010")
        #expect(session.presentation.isDownsampled)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError != nil)
        #expect(session.presentation.verticalOffset == 200)
        #expect(await gate.attemptedIntervals().filter { $0.start <= 9751 && $0.end >= 9751 }.count == 1)

        let pending = session.endAlignmentDrag()
        #expect(pending != nil, "Visible tail geometry cannot prove the failed R coverage complete")
        #expect(session.presentation.isLoading)
        await gate.waitFor("started:required retry")
        try Task.checkCancellation()
        session.editInterval("a newer draft")
        session.scrollVertically(to: 300)
        await gate.release("required retry")
        await pending?.value
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.intervalText == "a newer draft")
        if failRequired {
            #expect(session.presentation.target == committed.target)
            #expect(session.presentation.alignments == committed.alignments)
            #expect(session.presentation.verticalOffset == 0)
            #expect(session.presentation.regionalError?.interval.formatted == "tiny:10,001-10,010")
        } else {
            #expect(session.presentation.target?.formatted == "tiny:10,001-10,010")
            #expect(session.presentation.alignments.map(\.name).sorted() == expected)
            #expect(Set(session.presentation.alignments.map(\.id)).count == 3)
            #expect(session.presentation.verticalOffset == 300)
            #expect(session.presentation.regionalError == nil)
        }
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.finish()
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    @MainActor
    func earlierRequiredOutcomeWaitsForReleaseWhileRefillRefreshesTheLatestPreview(failEarlier: Bool, changedRelease: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RollingLifecycleGate()
        defer { Task { await gate.finish() } }
        let session = ViewerSession(loadRegion: { file, interval in
            if interval.start == 10146 {
                await gate.hold("earlier required")
                if failEarlier { throw RegionalLoadError(interval: interval, message: "Earlier target failed") }
            }
            return try await file.alignments(in: interval)
        }, samplingGroupBudget: 3, samplingSeed: { 42 },
                                    samplingPriority: { _, identity in UInt64(identity.last!) },
                                    loadPrefetchRegion: { file, interval, budget in
            if await gate.claim("first optional") { await gate.hold("initial optional") }
            let records = try await file.alignments(in: interval, budget: budget)
            await gate.completed(interval)
            return records
        })
        defer { session.onPresentationChange = nil }
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:10401-10410")
        await session.submitInterval()?.value
        let committed = session.presentation
        await gate.waitFor("started:initial optional")
        try Task.checkCancellation()
        let earlier = session.pan(.left)
        #expect(earlier != nil)
        await gate.waitFor("started:earlier required")
        await gate.waitFor("canceled:initial optional")
        try Task.checkCancellation()
        await gate.release("initial optional")

        session.editInterval("tiny:9-2")
        session.submitInterval()
        let draftError = try #require(session.presentation.intervalError)
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: 39.45)
        session.scrollVertically(to: 200)
        #expect(session.presentation.target?.formatted == "tiny:10,001-10,010")
        #expect(abs(session.presentation.previewOffsetInBases - 0.5) < 0.000001)
        let expected = ["left_boundary", "right_boundary", "supplementary"]
        session.onPresentationChange = {
            if session.presentation.alignments.map(\.name).sorted() == expected {
                Task { await gate.signal("latest sample displayed") }
            }
        }
        await gate.release("earlier required")
        await earlier?.value
        #expect(session.presentation.target?.formatted == "tiny:10,001-10,010")
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError == draftError)
        #expect(session.presentation.verticalOffset == 200)
        #expect(!session.presentation.isLoading)
        await gate.waitFor("latest sample displayed")
        try Task.checkCancellation()
        session.onPresentationChange = nil

        if changedRelease {
            #expect(session.endAlignmentDrag() == nil)
            #expect(session.presentation.target?.formatted == "tiny:10,001-10,010")
            #expect(session.presentation.alignments.map(\.name).sorted() == expected)
            #expect(session.presentation.intervalText == "tiny:10,001-10,010")
            #expect(session.presentation.intervalError == nil)
            #expect(session.presentation.regionalError == nil)
            #expect(session.presentation.verticalOffset == 200)
        } else {
            session.previewAlignmentDrag(horizontalFraction: 0)
            #expect(session.presentation.target?.formatted == "tiny:10,396-10,405")
            await session.endAlignmentDrag()?.value
            #expect(session.presentation.target?.formatted == (failEarlier ? "tiny:10,401-10,410" : "tiny:10,396-10,405"))
            #expect(session.presentation.alignments == committed.alignments)
            #expect(session.presentation.intervalText == "tiny:9-2")
            #expect(session.presentation.intervalError == draftError)
            #expect(session.presentation.verticalOffset == (failEarlier ? 0 : 200))
            #expect((session.presentation.regionalError != nil) == failEarlier)
            if failEarlier { #expect(session.presentation.regionalError?.interval.formatted == "tiny:10,396-10,405") }
        }
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.previewOffsetInBases == 0)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.finish()
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"], ["unchanged", "commit", "failure"])
    @MainActor
    func completedSampledPreviewRemainsProvisionalUntilItsRelease(indexFormat: String, release: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RollingLifecycleGate()
        defer { Task { await gate.finish() } }
        let session = ViewerSession(loadRegion: { file, interval in
            if interval.start > 15000 {
                await gate.hold("required failure")
                throw RegionalLoadError(interval: interval, message: "Changed release failed")
            }
            return try await file.alignments(in: interval)
        }, samplingGroupBudget: 3, samplingSeed: { 42 },
                                    samplingPriority: { _, identity in UInt64(identity.last!) },
                                    loadPrefetchRegion: { file, interval, budget in
            if interval.start < 10151, interval.end >= 10011 {
                await gate.hold("cluster")
            }
            if interval.start > 15000 { await gate.hold("far optional") }
            let records = try await file.alignments(in: interval, budget: budget)
            await gate.completed(interval)
            return records
        })
        defer { session.onPresentationChange = nil }
        try await files.openedSession(fixture: "bounded-tails", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:10401-10410")
        await session.submitInterval()?.value
        let committed = session.presentation
        #expect(committed.alignments.isEmpty)
        await gate.waitFor("started:cluster")
        try Task.checkCancellation()

        session.editInterval("tiny:9-2")
        session.submitInterval()
        let rejectedDraft = try #require(session.presentation.intervalError)
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: 35)
        session.previewAlignmentDrag(horizontalFraction: 39.95)
        session.scrollVertically(to: 200)
        let incomplete = session.presentation
        #expect(incomplete.target?.formatted == "tiny:10,001-10,010")
        #expect(abs(incomplete.previewOffsetInBases - 0.5) < 0.000001)
        #expect(incomplete.alignments.map(\.name).sorted() == ["outside_right", "right_boundary"])
        #expect(!incomplete.isLoading)

        // This independently worked sample requires both the held cluster and
        // aligned base 9751 from the newly requested left required edge.
        let expected = ["left_boundary", "right_boundary", "supplementary"]
        session.onPresentationChange = {
            if session.presentation.alignments.map(\.name).sorted() == expected {
                Task { await gate.signal("complete sample displayed") }
            }
        }
        await gate.release("cluster")
        await gate.waitFor("complete sample displayed")
        try Task.checkCancellation()
        session.onPresentationChange = nil
        let readyPreview = session.presentation
        #expect(readyPreview.target == incomplete.target)
        #expect(readyPreview.previewOffsetInBases == incomplete.previewOffsetInBases)
        #expect(readyPreview.intervalText == "tiny:9-2")
        #expect(readyPreview.intervalError == rejectedDraft)
        #expect(readyPreview.verticalOffset == 200)
        #expect(readyPreview.isDownsampled)
        #expect(!readyPreview.isLoading)
        #expect(readyPreview.regionalError == nil)
        #expect(Set(readyPreview.alignments.map(\.id)).count == 3)
        for retained in incomplete.alignments where expected.contains(retained.name) {
            #expect(readyPreview.alignments.first { $0.id == retained.id }?.row == retained.row)
        }
        // The initial R was 10151...10660. These completed loader intervals
        // cover its missing spans for fractional preview R=9751...10261.
        let completed = await gate.completedIntervals()
        for boundary in [Int64(9751), 9900, 9901, 10150] {
            #expect(completed.contains { $0.start <= boundary && $0.end >= boundary })
        }
        for left in readyPreview.alignments {
            for right in readyPreview.alignments where left.id != right.id && left.row == right.row {
                #expect(left.drawnEnd < right.drawnStart || right.drawnEnd < left.drawnStart)
            }
        }

        // Later displacement still refers to pointer-down, not to the target
        // at which the completion repainted the preview.
        session.previewAlignmentDrag(horizontalFraction: 39.85)
        #expect(session.presentation.target?.formatted == "tiny:10,002-10,011")
        session.previewAlignmentDrag(horizontalFraction: 39.95)
        if release == "unchanged" {
            session.previewAlignmentDrag(horizontalFraction: 0)
            #expect(session.endAlignmentDrag() == nil)
            #expect(session.presentation.target == committed.target)
            #expect(session.presentation.alignments == committed.alignments)
            #expect(session.presentation.intervalText == "tiny:9-2")
            #expect(session.presentation.intervalError == rejectedDraft)
            #expect(session.presentation.verticalOffset == 200)
        } else if release == "commit" {
            #expect(session.endAlignmentDrag() == nil, "All preview R coverage has completed before release")
            #expect(session.presentation.target?.formatted == "tiny:10,001-10,010")
            #expect(session.presentation.intervalText == "tiny:10,001-10,010")
            #expect(session.presentation.intervalError == nil)
            #expect(session.presentation.previewOffsetInBases == 0)
            #expect(session.presentation.alignments.map(\.name).sorted() == expected)
            #expect(session.presentation.verticalOffset == 200)
        } else {
            session.previewAlignmentDrag(horizontalFraction: -2000)
            let pending = session.endAlignmentDrag()
            #expect(pending != nil)
            #expect(session.presentation.isLoading)
            await gate.waitFor("started:required failure")
            try Task.checkCancellation()
            session.editInterval("a newer draft")
            session.scrollVertically(to: 300)
            await gate.release("required failure")
            await pending?.value
            #expect(session.presentation.target == committed.target)
            #expect(session.presentation.alignments == committed.alignments)
            #expect(session.presentation.rowCount == committed.rowCount)
            #expect(session.presentation.intervalText == "a newer draft")
            #expect(session.presentation.verticalOffset == 0)
            #expect(session.presentation.regionalError?.interval.formatted == "tiny:30,401-30,410")
        }
        #expect(!session.presentation.isLoading)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
        await gate.finish()
    }
}

private actor RollingLifecycleGate {
    private var events = Set<String>()
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var held: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var released = Set<String>()
    private var finished = false
    private var intervals: [GenomicInterval] = []
    private var attempts: [GenomicInterval] = []
    private var claims = Set<String>()

    func claim(_ label: String) -> Bool { claims.insert(label).inserted }
    func hasEvent(_ event: String) -> Bool { events.contains(event) }
    func completed(_ interval: GenomicInterval) { intervals.append(interval) }
    func completedIntervals() -> [GenomicInterval] { intervals }
    func attempted(_ interval: GenomicInterval) { attempts.append(interval) }
    func attemptedIntervals() -> [GenomicInterval] { attempts }

    func signal(_ event: String) {
        events.insert(event)
        for continuation in waiting.removeValue(forKey: event) ?? [] { continuation.resume() }
    }

    func waitFor(_ event: String) async {
        guard !finished, !events.contains(event), !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[event, default: []].append($0) }
        } onCancel: {
            Task { await self.finish() }
        }
    }

    func hold(_ label: String) async {
        guard !finished, !released.contains(label) else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                held[label, default: []].append(continuation)
                signal("started:\(label)")
            }
        } onCancel: {
            Task { await self.signal("canceled:\(label)") }
        }
    }

    func release(_ label: String) {
        released.insert(label)
        for continuation in held.removeValue(forKey: label) ?? [] { continuation.resume() }
    }

    func finish() {
        finished = true
        for continuations in waiting.values { for continuation in continuations { continuation.resume() } }
        for continuations in held.values { for continuation in continuations { continuation.resume() } }
        waiting.removeAll()
        held.removeAll()
    }
}
