import Foundation
import Testing
import BamdalfKit

struct RegionalOrderingTests {
    @Test(arguments: [false, true])
    @MainActor
    func onlyLatestChangedTargetCanCompleteOrFail(failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let alignments = try await file.alignments(in: target)
            await gate.pause(target.end == 360 ? 101 : 1001)
            if failLate && target.end == 360 {
                throw RegionalLoadError(interval: target, message: "Controlled read failure")
            }
            return alignments
        })
        await session.openBAM(files.sources.appendingPathComponent("alignments.bam"))
        await session.chooseIndex(files.sources.appendingPathComponent("alignments.bam.bai"))
        session.editInterval("tiny:101-110")
        let older = session.submitInterval()
        await gate.waitFor(101)
        session.editInterval("tiny:1001-1014")
        let newer = session.submitInterval()
        await gate.waitFor(1001)
        #expect(session.presentation.isLoading)
        #expect(session.presentation.alignments.isEmpty)
        session.editInterval("tiny:1,001-1,014")
        let same = session.submitInterval()
        #expect(await gate.count(1001) == 1)
        await gate.release(1001)
        await newer?.value
        await same?.value
        #expect(session.presentation.alignments.map(\.name) == ["complex"])
        session.editInterval("newer draft")
        await gate.release(101)
        await older?.value
        #expect(session.presentation.target?.formatted == "tiny:1,001-1,014")
        #expect(session.presentation.alignments.map(\.name) == ["complex"])
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.intervalText == "newer draft")
    }
    @Test(arguments: ["tiny:101-110", "tiny:5000-5010", ""], [false, true])
    @MainActor
    func failedTargetRestoresOnlySuccessfulDataAndProtectsANewerDraft(prior: String, editDuringLoad: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            if target.end == 2260 {
                await gate.pause(2001)
                throw RegionalLoadError(interval: target, message: "Controlled selected-index failure")
            }
            return try await file.alignments(in: target)
        })
        let bam = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        if !prior.isEmpty {
            session.editInterval(prior)
            await session.submitInterval()?.value
        }
        let successful = session.presentation.alignments
        let previousTarget = session.presentation.target
        session.editInterval("tiny:2001-2010")
        let pending = session.submitInterval()
        await gate.waitFor(2001)
        #expect(session.presentation.alignments.isEmpty)
        #expect(session.presentation.isLoading)
        if editDuringLoad {
            session.editInterval("invalid newer draft")
            session.submitInterval()
            #expect(session.presentation.intervalError != nil)
        }
        await gate.release(2001)
        await pending?.value
        #expect(session.presentation.target == previousTarget)
        #expect(session.presentation.alignments == successful)
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.intervalText == (editDuringLoad ? "invalid newer draft" : previousTarget?.formatted ?? ""))
        #expect((session.presentation.intervalError != nil) == editDuringLoad)
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:2,001-2,010")
        #expect(session.presentation.regionalError?.message == "Controlled selected-index failure")
        #expect(session.presentation.message == (prior.isEmpty ? "Enter a genomic interval" : ""))
    }

    @Test(arguments: [false, true])
    @MainActor
    func successfulBAMReplacementInvalidatesOldRegionalResults(failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            await gate.pause(101)
            if failLate { throw RegionalLoadError(interval: target, message: "Old BAM failed") }
            return records
        })
        let bam = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        session.editInterval("tiny:101-110")
        let pending = session.submitInterval()
        await gate.waitFor(101)
        let replacement = files.sources.appendingPathComponent("opening.bam")
        await session.openBAM(replacement)
        await session.chooseIndex(replacement.appendingPathExtension("bai"))
        #expect(!session.presentation.isLoading)
        await gate.release(101)
        await pending?.value
        #expect(session.presentation.bamURL == replacement)
        #expect(session.presentation.target == nil)
        #expect(session.presentation.alignments.isEmpty)
        #expect(session.presentation.rowCount == 0)
        #expect(session.presentation.regionalError == nil)
        #expect(session.presentation.message == "Enter a genomic interval")
    }

}

actor RegionGate {
    private var pending: [Int64: CheckedContinuation<Void, Never>] = [:]
    private var observers: [Int64: CheckedContinuation<Void, Never>] = [:]
    private var counts: [Int64: Int] = [:]

    func pause(_ key: Int64) async {
        counts[key, default: 0] += 1
        await withCheckedContinuation { continuation in
            pending[key] = continuation
            observers.removeValue(forKey: key)?.resume()
        }
    }
    func waitFor(_ key: Int64) async {
        if pending[key] != nil { return }
        await withCheckedContinuation { observers[key] = $0 }
    }
    func release(_ key: Int64) { pending.removeValue(forKey: key)?.resume() }
    func count(_ key: Int64) -> Int { counts[key, default: 0] }
}
