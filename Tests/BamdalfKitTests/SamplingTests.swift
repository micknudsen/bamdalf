import Foundation
import Testing
import BamdalfKit

struct SamplingTests {
    @Test(arguments: ["bai", "csi"])
    @MainActor
    func byteDistinctReadGroupsRemainSeparateDespiteUnicodeCanonicalEquivalence(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .disabled, samplingGroupBudget: 1, samplingSeed: { 42 }, samplingPriority: { _, _ in 1 })
        try await files.openedSession(fixture: "sampling-unicode", indexFormat: index, session: session)
        session.editInterval("tiny:100-120")
        await session.submitInterval()?.value
        #expect(session.presentation.isDownsampled)
        #expect(session.presentation.alignments.count == 1)
        // The two-byte composed RG sorts before the three-byte decomposed RG
        // in the independently specified length-prefixed identity encoding.
        #expect(session.presentation.alignments.map(\.referenceStart) == [101])
        #expect(session.presentation.alignments.first?.readGroup.map { Array($0.utf8) } == [0xC3, 0xA9])
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func exactGroupBudgetCoordinatesEligibleMembersAfterFiltering(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        // All priorities tie: stable identity ordering excludes only RG=ab, QNAME=c.
        let session = ViewerSession(prefetch: .disabled, samplingGroupBudget: 7, samplingSeed: { 42 }, samplingPriority: { _, _ in 1 })
        try await files.openedSession(fixture: "sampling", indexFormat: index, session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        #expect(session.presentation.isDownsampled)
        #expect(session.presentation.alignments.count == 11)
        #expect(session.presentation.alignments.filter { $0.name == "shared" && $0.readGroup == "a" }.count == 4)
        #expect(session.presentation.alignments.filter { $0.name == "shared" && $0.readGroup == "b" }.count == 2)
        #expect(session.presentation.alignments.filter { $0.name == "*" }.count == 2)
        #expect(!session.presentation.alignments.contains { $0.name == "filtered" || $0.name == "c" })
    }

    @Test(arguments: [false, true])
    @MainActor
    func tiedPrioritiesUseStableUnambiguousIdentitiesRegardlessOfRetrievalOrder(reversed: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            return reversed ? records.reversed() : records
        }, samplingGroupBudget: 5, samplingSeed: { 42 }, samplingPriority: { _, _ in 99 })
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        // Unnamed offsets, absent RG, empty RG, then (a,bc); (ab,c) stays distinct.
        #expect(session.presentation.alignments.map(\.referenceStart).sorted() == [106, 107, 108, 109, 110])
        #expect(session.presentation.alignments.map(\.name).sorted() == ["*", "*", "bc", "shared", "shared"])
        #expect(session.presentation.alignments.filter { $0.name == "shared" }.map(\.readGroup) == [nil, ""])
        let originalIDs = session.presentation.alignments.map(\.id)
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.id) == originalIDs)
    }

    @Test
    @MainActor
    func exactBudgetBoundaryAndEmptyTargetsSucceedWithoutSamplingOrOutsideMembers() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .disabled, samplingGroupBudget: 8, samplingSeed: { 42 })
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.count == 12)
        #expect(!session.presentation.isDownsampled)
        session.editInterval("tiny:101-103")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments.map(\.referenceStart) == [101, 102, 103])
        #expect(!session.presentation.isDownsampled)
        session.editInterval("tiny:200-300")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments.isEmpty)
        #expect(!session.presentation.isDownsampled && !session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
    }

    @Test
    @MainActor
    func cachedNarrowTargetRecoversAnOmittedGroupAndNearbySamplesKeepSurvivingRows() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.start == 701 { await gate.pause(451) }
            return records
        }, samplingGroupBudget: 7, samplingSeed: { 42 }, samplingPriority: { _, _ in 1 })
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        let rows = session.presentation.rowCount
        session.scrollVertically(to: 100)
        session.editInterval("tiny:100-600")
        let pending = session.submitInterval()
        await gate.waitFor(451)
        #expect(session.presentation.isLoading)
        // The earlier R already fetched the newly visible group. It participates
        // immediately, while the missing outer search edge still keeps loading.
        #expect(session.presentation.alignments.map(\.referenceStart) == [101, 102, 103, 106, 107, 108, 109, 110, 401, 501])
        for record in session.presentation.alignments {
            if let previous = original.first(where: { $0.id == record.id }) { #expect(record.row == previous.row) }
        }
        session.scrollVertically(to: 200)
        await gate.release(451)
        await pending?.value
        #expect(session.presentation.isDownsampled)
        #expect(session.presentation.alignments.contains { $0.name == "newcomer" })
        for record in session.presentation.alignments {
            if let previous = original.first(where: { $0.id == record.id }) { #expect(record.row == previous.row) }
        }
        #expect(session.presentation.verticalOffset == 200)
        #expect(session.presentation.rowCount >= rows)
        session.editInterval("tiny:120-120")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments.map(\.name) == ["c"])
        #expect(!session.presentation.isDownsampled)
        #expect(session.presentation.verticalOffset == 200)
        session.editInterval("tiny:1000-1100")
        await session.submitInterval()?.value
        session.editInterval("tiny:100-450")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.isDownsampled)
        #expect(session.presentation.verticalOffset == 0)
        #expect(Set(session.presentation.alignments.map(\.id)) == Set(original.map(\.id)))
    }

    @Test
    @MainActor
    func failedSampledNavigationRestoresWarningAndCompleteCandidatesAtTheTop() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            if target.start == 701 {
                await gate.pause(451)
                throw RegionalLoadError(interval: target, message: "Controlled sampling failure")
            }
            return try await file.alignments(in: target)
        }, samplingGroupBudget: 7, samplingSeed: { 42 }, samplingPriority: { _, _ in 1 })
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        session.scrollVertically(to: 100)
        session.editInterval("tiny:100-600")
        let pending = session.submitInterval()
        await gate.waitFor(451)
        session.editInterval("newer draft")
        await gate.release(451)
        await pending?.value
        #expect(session.presentation.isDownsampled && !session.presentation.isLoading)
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.verticalOffset == 0)
        #expect(session.presentation.intervalText == "newer draft")
        #expect(session.presentation.regionalError != nil)
        session.editInterval("tiny:120-120")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments.map(\.name) == ["c"])
        #expect(!session.presentation.isDownsampled)
    }

    @Test(arguments: [UInt64(0), 42, .max])
    @MainActor
    func seedReproducesTheSameSampleAfterEvictionReloadAndReopening(seed: UInt64) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .disabled, samplingGroupBudget: 4, samplingSeed: { seed })
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        let expected = Set(session.presentation.alignments.map(\.id))
        #expect(session.presentation.isDownsampled)
        for start in stride(from: 1001, through: 11001, by: 1000) {
            session.editInterval("tiny:\(start)-\(start + 9)")
            await session.submitInterval()?.value
        }
        session.editInterval("tiny:100-450")
        let reload = session.submitInterval()
        #expect(reload != nil, "Evicted candidates require a real indexed reload")
        await reload?.value
        #expect(Set(session.presentation.alignments.map(\.id)) == expected)
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        await session.submitInterval()?.value
        #expect(Set(session.presentation.alignments.map(\.id)) == expected)
    }

    @Test(arguments: [false, true])
    @MainActor
    func staleSampledResultCannotReplaceNewerReadyOrWideStatus(wide: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 700 { await gate.pause(100) }
            return records
        }, samplingGroupBudget: 4, samplingSeed: { 42 })
        try await files.openedSession(fixture: "sampling", session: session)
        session.editInterval("tiny:100-450")
        let older = session.submitInterval()
        await gate.waitFor(100)
        session.editInterval(wide ? "tiny:1-20000" : "tiny:15001-15010")
        await session.submitInterval()?.value
        let expected = session.presentation
        await gate.release(100)
        await older?.value
        #expect(session.presentation.target == expected.target)
        #expect(session.presentation.alignments == expected.alignments)
        #expect(!session.presentation.isDownsampled && !session.presentation.isLoading)
    }

    @Test
    @MainActor
    func oneWholeViewBudgetUsesHighestGroupPrioritiesWithoutLocalDensityQuotas() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        // Controlled priorities a=97...h=104. Dense block has six groups and
        // sparse block two, but the highest four are e,f,g,h across the whole view.
        let session = ViewerSession(prefetch: .disabled, samplingGroupBudget: 4, samplingSeed: { 42 },
                                    samplingPriority: { _, identity in UInt64(identity.last!) })
        try await files.openedSession(fixture: "density", session: session)
        session.editInterval("tiny:1000-2100")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name).sorted() == ["e", "e", "f", "f", "g", "g", "h", "h"])
        #expect(session.presentation.isDownsampled)
        // A 3:1 candidate-group density becomes 1:1 in this controlled sample:
        // relative density is an expectation, never an exact local quota.
        #expect(session.presentation.alignments.filter { $0.referenceStart < 2000 }.count == 4)
        #expect(session.presentation.alignments.filter { $0.referenceStart >= 2000 }.count == 4)
    }

    @Test(arguments: [17001, 18001])
    @MainActor
    func malformedPresentReadGroupFailsTheRegionInsteadOfUsingAbsentNamespace(start: Int) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "malformed-rg")
        session.editInterval("tiny:101-110")
        await session.submitInterval()?.value
        let prior = session.presentation.alignments
        session.editInterval("tiny:\(start)-\(start + 9)")
        await session.submitInterval()?.value
        #expect(session.presentation.regionalError?.message.contains("RG") == true)
        #expect(session.presentation.target?.formatted == "tiny:101-110")
        #expect(session.presentation.alignments == prior)
        #expect(!session.presentation.isLoading)
    }
}
