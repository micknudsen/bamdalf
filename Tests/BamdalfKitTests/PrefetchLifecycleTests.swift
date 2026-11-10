import Foundation
import Testing
import BamdalfKit

struct PrefetchLifecycleTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"])
    @MainActor
    func completedOptionalCoverageCannotMoveADragOrPromoteItsRecoveryView(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = LifecycleLoadGate()
        let session = ViewerSession(prefetch: .init(chunkBases: 250), loadRegion: { file, interval in
            if interval.start == 951 {
                await gate.hold("required")
                throw RegionalLoadError(interval: interval, message: "Changed release failed")
            }
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            let records = try await file.alignments(in: interval, budget: budget)
            await gate.hold(interval.start == 701 ? "first" : "second")
            return records
        })
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        let committed = session.presentation
        #expect(committed.alignments.count == 80)
        await gate.waitFor("started:first")
        try Task.checkCancellation()

        // Same-target submission must leave the existing optional work useful.
        #expect(session.submitInterval() == nil)
        session.editInterval("tiny:9-2")
        session.submitInterval()
        session.beginAlignmentDrag()
        session.previewAlignmentDrag(horizontalFraction: -0.1)
        session.scrollVertically(to: 200)
        let preview = session.presentation
        #expect(preview.target?.formatted == "tiny:135-485")
        #expect(preview.alignments.count == 80)
        await gate.release("first")
        // Starting the following chunk proves the earlier result has been
        // handled, rather than merely returned from the injected loader.
        await gate.waitFor("started:second")
        try Task.checkCancellation()
        #expect(session.presentation.target == preview.target)
        #expect(session.presentation.alignments == preview.alignments)
        #expect(session.presentation.rowCount == preview.rowCount)
        #expect(session.presentation.verticalOffset == 200)
        #expect(session.presentation.intervalText == "tiny:9-2")
        #expect(session.presentation.intervalError != nil)
        #expect(session.presentation.regionalError == nil)
        #expect(!session.presentation.isLoading)

        session.previewAlignmentDrag(horizontalFraction: -0.2)
        #expect(session.presentation.target?.formatted == "tiny:170-520")
        for alignment in preview.alignments {
            #expect(session.presentation.alignments.first { $0.id == alignment.id }?.row == alignment.row)
        }
        // Outrun the completed buffer. A failure on release must restore the
        // successful committed view, never either fully loaded preview.
        session.previewAlignmentDrag(horizontalFraction: -3)
        let changed = session.endAlignmentDrag()
        await gate.waitFor("started:required")
        try Task.checkCancellation()
        session.editInterval("a newer draft")
        session.scrollVertically(to: 300)
        await gate.release("required")
        await changed?.value
        #expect(session.presentation.target == committed.target)
        #expect(session.presentation.alignments == committed.alignments)
        #expect(session.presentation.rowCount == committed.rowCount)
        #expect(session.presentation.verticalOffset == 0)
        #expect(session.presentation.intervalText == "a newer draft")
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:1,153-1,503")
        #expect(!session.presentation.isLoading)
        await gate.release("second")
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["bai", "csi"])
    @MainActor
    func failedAndCanceledReplacementPreserveOptionalWorkButSuccessfulReplacementOwnsCoverage(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = LifecycleLoadGate()
        let session = ViewerSession(prefetch: .init(chunkBases: 250), loadPrefetchRegion: { file, interval, budget in
            let records = try await file.alignments(in: interval, budget: budget)
            if file.url.lastPathComponent == "bounded-tails.bam" {
                let label = interval.start < 10151 ? "old-left" : "old-right"
                await gate.hold(label)
                await gate.signal("returned:\(label)")
            }
            return records
        })
        try await files.openedSession(fixture: "bounded-tails", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:10401-10410")
        await session.submitInterval()?.value
        let oldSession = session.presentation.sessionID
        let oldView = session.presentation
        await gate.waitFor("started:old-left")
        try Task.checkCancellation()
        await session.openBAM(nil)
        await session.openBAM(files.sources.appendingPathComponent("opening.bam"))
        await session.chooseIndex(nil)
        await session.openBAM(files.directory.appendingPathComponent("absent.bam"))
        #expect(session.presentation.openError != nil)
        session.dismissOpenError()
        #expect(session.presentation.sessionID == oldSession)
        #expect(session.presentation.target == oldView.target)
        #expect(session.presentation.alignments == oldView.alignments)
        await gate.release("old-left")
        await gate.waitFor("started:old-right")
        try Task.checkCancellation()

        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        #expect(session.presentation.sessionID != oldSession)
        #expect(session.presentation.target == nil)
        #expect(session.presentation.alignments.isEmpty)
        await gate.waitFor("canceled:old-right")
        await gate.release("old-right")
        await gate.waitFor("returned:old-right")
        // The old left query contained the cluster around 10011. None of those
        // records or that query's coverage may transfer into the new BAM.
        session.editInterval("tiny:10001-10010")
        let fresh = session.submitInterval()
        #expect(fresh != nil)
        await fresh?.value
        #expect(session.presentation.alignments.isEmpty)
        #expect(session.presentation.regionalError == nil)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.count == 80)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["identical"])
        #expect(session.presentation.regionalError == nil)
        #expect(!session.presentation.isLoading)
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["jump", "reference", "wide"], [false, true])
    @MainActor
    func deliberateNavigationRetiresOptionalWorkAndIgnoresItsLateOutcome(route: String, failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = LifecycleLoadGate()
        let session = ViewerSession(prefetch: .init(chunkBases: 250), loadRegion: { file, interval in
            if interval.start > 15000 || interval.reference == "other" {
                await gate.hold("foreground")
            }
            return try await file.alignments(in: interval)
        }, loadPrefetchRegion: { file, interval, budget in
            let records = try await file.alignments(in: interval, budget: budget)
            if interval.reference == "tiny", interval.end == 9750 {
                await gate.hold("obsolete")
                await gate.signal("returned:obsolete")
                if failLate { throw RegionalLoadError(interval: interval, message: "Obsolete optional error") }
            }
            return records
        })
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        await gate.waitFor("started:obsolete")
        try Task.checkCancellation()
        let destination = route == "jump" ? "tiny:20001-20010"
            : route == "reference" ? "other:10001-10010" : "tiny:1-20000"
        session.editInterval(destination)
        let navigation = session.submitInterval()
        let target = session.presentation.target
        await gate.waitFor("canceled:obsolete")
        try Task.checkCancellation()
        if route != "wide" { await gate.waitFor("started:foreground") }
        session.editInterval("preserve this newer draft")
        session.scrollVertically(to: 100)
        await gate.release("obsolete")
        await gate.waitFor("returned:obsolete")
        if route != "wide" { await gate.release("foreground") }
        await navigation?.value
        #expect(session.presentation.target == target)
        #expect(session.presentation.intervalText == "preserve this newer draft")
        #expect(session.presentation.verticalOffset == 100)
        #expect(session.presentation.alignments.isEmpty)
        #expect(session.presentation.regionalError == nil)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.isAlignmentSuppressed == (route == "wide"))
        session.editInterval("tiny:1-20000")
        await session.submitInterval()?.value
    }
}

/// Controlled loading events, including the cancellation of an in-flight query.
/// Cancellation deliberately leaves its result held, allowing late-success and
/// late-error cases to exercise session ownership independently of reader checks.
private actor LifecycleLoadGate {
    private var events = Set<String>()
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var held: [String: [CheckedContinuation<Void, Never>]] = [:]

    func signal(_ event: String) {
        events.insert(event)
        for continuation in waiting.removeValue(forKey: event) ?? [] { continuation.resume() }
    }

    func waitFor(_ event: String) async {
        guard !events.contains(event), !Task.isCancelled else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[event, default: []].append($0) }
        } onCancel: {
            Task { await self.cancelWaiters() }
        }
    }

    func hold(_ label: String) async {
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
        guard var continuations = held[label], !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
        held[label] = continuations.isEmpty ? nil : continuations
    }

    private func cancelWaiters() {
        for continuations in waiting.values {
            for continuation in continuations { continuation.resume() }
        }
        waiting.removeAll()
        for continuations in held.values {
            for continuation in continuations { continuation.resume() }
        }
        held.removeAll()
    }
}
