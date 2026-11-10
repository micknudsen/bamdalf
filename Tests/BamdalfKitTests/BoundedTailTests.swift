import Foundation
import Testing
import BamdalfKit

struct BoundedTailTests {
    @Test(arguments: ["bai", "csi"])
    @MainActor
    func directAndCachedTailOnlyViewsUseTheSameCandidates(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "alignments", indexFormat: index)
        session.editInterval("tiny:95-100")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name).sorted() == ["forward", "reverse"])
        let fresh = session.presentation.alignments.map(\.id).sorted()
        session.editInterval("tiny:101-115")
        await session.submitInterval()?.value
        session.editInterval("tiny:95-100")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.id).sorted() == fresh)
        #expect(!session.presentation.isLoading)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func exactSearchBoundariesKeepBothTailSidesAndDistinctRecords(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "bounded-tails", indexFormat: index)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        // M=250: R=9751...10260. The boundary bodies intersect by one base;
        // outside bodies miss R by one base despite tails that reach V.
        #expect(session.presentation.alignments.map(\.name).sorted() == [
            "deletion", "left_boundary", "left_reverse", "missing", "right_boundary",
            "right_forward", "right_reverse", "same", "same", "shared", "skip", "supplementary",
        ])
        #expect(Set(session.presentation.alignments.map(\.id)).count == 12)
        let boundary = try #require(session.presentation.alignments.first { $0.name == "right_boundary" })
        #expect(boundary.referenceStart == 10260)
        #expect(boundary.drawnStart == 10000)
        let left = try #require(session.presentation.alignments.first { $0.name == "left_boundary" })
        #expect(left.referenceEnd == 9751 && left.drawnEnd == 10011)
        #expect(session.presentation.alignments.filter { $0.name == "shared" }.count == 1)
        #expect(session.presentation.alignments.first { $0.name == "missing" }?.segments.first?.sequence == nil)
        #expect(session.presentation.alignments.first { $0.name == "right_reverse" }?.segments.first?.sequence == "TGCANTGCAN")
        #expect(session.presentation.alignments.first { $0.name == "left_reverse" }?.segments.last?.sequence == "GGGGGGGGGG")
    }

    @Test(arguments: ["bai", "csi"], [3, 100])
    @MainActor
    func freshPanCachedMixedAndEvictedViewsSelectTheSameEligibleGroups(index: String, budget: Int) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(samplingGroupBudget: budget, samplingSeed: { 42 },
                                    samplingPriority: { _, identity in UInt64(identity.last!) })
        try await files.openedSession(fixture: "bounded-tails", indexFormat: index, session: session)
        session.editInterval("tiny:10001-10010")
        await session.submitInterval()?.value
        let expected = session.presentation.alignments.map(\.id).sorted()
        #expect(expected.count == (budget == 3 ? 3 : 12))
        if budget == 3 {
            #expect(session.presentation.alignments.map(\.name).sorted() == ["left_boundary", "right_boundary", "supplementary"])
        }
        for route in [["tiny:9500-10500"], ["tiny:9700-9749", "tiny:10261-10300"], ["tiny:9996-10005"]] {
            try await files.openedSession(fixture: "bounded-tails", indexFormat: index, session: session)
            for target in route {
                session.editInterval(target)
                await session.submitInterval()?.value
            }
            if route.last == "tiny:9996-10005" {
                await session.pan(.right)?.value
            } else {
                session.editInterval("tiny:10001-10010")
                await session.submitInterval()?.value
            }
            #expect(session.presentation.alignments.map(\.id).sorted() == expected)
            #expect(!session.presentation.isLoading)
            #expect(session.presentation.isDownsampled == (budget == 3))
        }
        for start in stride(from: 20000, through: 50000, by: 3000) {
            session.editInterval("tiny:\(start)-\(start + 9)")
            await session.submitInterval()?.value
        }
        session.editInterval("tiny:10001-10010")
        let reload = session.submitInterval()
        #expect(reload != nil)
        await reload?.value
        #expect(session.presentation.alignments.map(\.id).sorted() == expected)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func searchClampsAtReferenceEndsWithoutTruncatingSelectedTails(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let requests = TailQueries()
        let session = ViewerSession(loadRegion: { file, query in
            await requests.record(query.formatted)
            return try await file.alignments(in: query)
        })
        try await files.openedSession(fixture: "bounded-tails", indexFormat: index, session: session)
        #expect(await requests.values.isEmpty)
        session.editInterval("tiny:1-1")
        await session.submitInterval()?.value
        #expect(await requests.values == ["tiny:1-251"])
        #expect(session.presentation.alignments.map(\.name) == ["start"])
        #expect(session.presentation.alignments.first?.drawnStart == -4)
        session.editInterval("tiny:60000-60000")
        await session.submitInterval()?.value
        #expect(await requests.values == ["tiny:1-251", "tiny:59,750-60,000"])
        #expect(session.presentation.alignments.map(\.name) == ["end"])
        #expect(session.presentation.alignments.first?.drawnEnd == 60005)
    }

    @Test
    @MainActor
    func visibleCachedTailsDoNotFinishMissingSearchCoverage() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, query in
            if query.end == 10260 { await gate.pause(1) }
            return try await file.alignments(in: query)
        })
        try await files.openedSession(fixture: "bounded-tails", session: session)
        session.editInterval("tiny:9700-9749")
        await session.submitInterval()?.value
        session.editInterval("tiny:10001-10010")
        let pending = session.submitInterval()
        await gate.waitFor(1)
        #expect(session.presentation.isLoading)
        #expect(session.presentation.alignments.filter { $0.name == "same" }.count == 2)
        await gate.release(1)
        await pending?.value
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.alignments.count == 12)

        // zzzz was fetched inside R but never displayed in the first target.
        // The completed coverage must still be backed by that offscreen record.
        session.editInterval("tiny:9900-9909")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name).sorted() == ["left_boundary", "outside_left", "zzzz"])
    }

    @Test(arguments: ["missing", "inconsistent"])
    @MainActor
    func malformedOffscreenRecordInsideRequiredSearchRestoresTheCommittedView(defect: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "\(defect)-cigar")
        session.editInterval("tiny:101-110")
        await session.submitInterval()?.value
        let committed = session.presentation.alignments
        session.editInterval("tiny:16751-16760")
        await session.submitInterval()?.value
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:16,751-16,760")
        #expect(session.presentation.target?.formatted == "tiny:101-110")
        #expect(session.presentation.alignments == committed)
        #expect(!session.presentation.isLoading)
    }
}

private actor TailQueries {
    var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
