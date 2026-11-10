import Foundation
import Testing
import BamdalfKit

struct RegionalReaderSchedulingTests {
    @Test(arguments: ["bai", "csi"])
    @MainActor
    func optionalWorkCountsExcludedRecordsAndAllowsCompleteEmptyResults(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "alignments", indexFormat: index)
        session.editInterval("tiny:100-120")
        await session.submitInterval()?.value
        let interval = try #require(session.presentation.target)
        let url = files.sources.appendingPathComponent("alignments.bam")
        let file = try await BAMFile.open(url, indexURL: url.appendingPathExtension(index))
        // Seven records overlap this region; only three survive flag exclusion.
        // Optional decoded work includes the other four records too.
        do {
            _ = try await file.alignments(in: interval,
                budget: RegionalQueryBudget(maximumRecords: 3, maximumBytes: 1_000_000))
            Issue.record("Excluded records still consume optional decoding work")
        } catch is RegionalQueryBudgetExceeded {}
        let complete = try await file.alignments(in: interval,
            budget: RegionalQueryBudget(maximumRecords: 7, maximumBytes: 1_000_000))
        #expect(Set(complete.map(\.name)) == ["forward", "reverse", "supplementary"])

        session.editInterval("tiny:10000-10010")
        await session.submitInterval()?.value
        let empty = try await file.alignments(in: #require(session.presentation.target),
            budget: RegionalQueryBudget(maximumRecords: 1, maximumBytes: 1))
        #expect(empty.isEmpty)
    }

    @Test(arguments: ["bai", "csi"], ["records", "retained_bytes", "record_workspace"])
    @MainActor
    func optionalBudgetCannotTurnAnIncompleteQueryIntoSuccessfulCoverage(index: String, limit: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "rows", indexFormat: index)
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        let interval = try #require(session.presentation.target)
        let url = files.sources.appendingPathComponent("rows.bam")
        let file = try await BAMFile.open(url, indexURL: url.appendingPathExtension(index))
        let byteLimit = limit == "record_workspace" ? 256 : limit == "retained_bytes" ? 10_000 : 1_000_000
        let budget = RegionalQueryBudget(maximumRecords: limit == "records" ? 79 : 1_000,
                                         maximumBytes: byteLimit)
        do {
            _ = try await file.alignments(in: interval, budget: budget)
            Issue.record("Optional budget exhaustion must not return a truncated successful query")
        } catch is RegionalQueryBudgetExceeded {}

        // Both a mandatory retry and an exactly sufficient record budget must
        // return all 80 distinct records, including byte-identical alignments.
        let mandatory = try await file.alignments(in: interval)
        let sufficient = try await file.alignments(in: interval,
            budget: RegionalQueryBudget(maximumRecords: 80, maximumBytes: 1_000_000))
        #expect(mandatory.count == 80)
        #expect(Set(mandatory.map(\.id)).count == 80)
        #expect(sufficient == mandatory)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func canceledQueryCannotReturnCompleteCoverageAndReaderRemainsUsable(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = files.sources.appendingPathComponent("rows.bam")
        let file = try await BAMFile.open(url, indexURL: url.appendingPathExtension(index))
        let session = try await files.openedSession(fixture: "rows", indexFormat: index)
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        let interval = try #require(session.presentation.target)
        let gate = RegionGate()
        let canceled = Task {
            await gate.pause(1)
            return try await file.alignments(in: interval)
        }
        await gate.waitFor(1)
        canceled.cancel()
        await gate.release(1)
        do {
            _ = try await canceled.value
            Issue.record("A canceled query must throw instead of establishing complete coverage")
        } catch is CancellationError {
            // A canceled query is neither a successful empty result nor partial coverage.
        }
        let complete = try await file.alignments(in: interval)
        #expect(complete.count == 80)
        #expect(Set(complete.map(\.id)).count == 80)
        #expect(complete.allSatisfy { $0.name == "identical" && $0.referenceStart == 101 && $0.referenceEnd == 250 })
    }
}
