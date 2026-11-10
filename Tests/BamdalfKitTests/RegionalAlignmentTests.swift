import Foundation
import Testing
import BamdalfKit

struct RegionalAlignmentTests {
    @Test(arguments: ["bai", "csi"])
    @MainActor
    func realIndexedRegionDrawsEligibleBodiesAndTailOnlyOverlaps(index: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "alignments", indexFormat: index)
        session.editInterval("tiny:95-115")
        let loading = session.submitInterval()
        #expect(session.presentation.isLoading)
        #expect(session.presentation.target?.formatted == "tiny:95-115")
        await loading?.value
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.alignments.map(\.name).sorted() == ["forward", "reverse", "supplementary"])
        let forward = try #require(session.presentation.alignments.first { $0.name == "forward" })
        #expect(forward.referenceStart == 101)
        #expect(forward.referenceEnd == 110)
        #expect(forward.drawnStart == 91)
        #expect(forward.drawnEnd == 115)
        #expect(forward.segments.map(\.kind) == [.softClip, .aligned, .softClip])
        #expect(forward.segments.first?.sequence == "ACGTNRY=AC")
        #expect(session.presentation.message.isEmpty)

        session.editInterval("tiny:95-100")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name).sorted() == ["forward", "reverse"])
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
    }
    @Test
    @MainActor
    func allStandardCIGAROperationsPreserveReferenceAndStoredSequenceGeometry() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "alignments")
        session.editInterval("tiny:1001-1014")
        await session.submitInterval()?.value
        let alignment = try #require(session.presentation.alignments.first)
        #expect(alignment.isReverse)
        #expect(alignment.cigar == "2H3S4M1I1P2=1X2D3N2M4S1H")
        #expect(alignment.referenceStart == 1001 && alignment.referenceEnd == 1014)
        #expect(alignment.drawnStart == 998 && alignment.drawnEnd == 1018)
        #expect(alignment.segments.map(\.kind) == [.softClip, .aligned, .insertion, .aligned, .aligned, .deletion, .skip, .aligned, .softClip])
        #expect(alignment.segments.map(\.start) == [998, 1001, 1005, 1005, 1007, 1008, 1010, 1013, 1015])
        #expect(alignment.segments.map(\.end) == [1001, 1005, 1005, 1007, 1008, 1010, 1013, 1015, 1019])
        #expect(alignment.segments.first?.sequence == "ACG")
        #expect(alignment.segments.last?.sequence == "TNRY")

        session.editInterval("tiny:2050-2060")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name) == ["skip"])
        #expect(session.presentation.alignments.first?.segments.first { $0.kind == .skip }?.start == 2011)
        #expect(session.presentation.alignments.first?.segments.first { $0.kind == .skip }?.end == 2111)

        session.editInterval("tiny:3001-3010")
        await session.submitInterval()?.value
        let missing = try #require(session.presentation.alignments.first)
        #expect(missing.drawnStart == 2996 && missing.drawnEnd == 3015)
        #expect(missing.segments.filter { $0.kind == .softClip }.allSatisfy { $0.sequence == nil })
        #expect(missing.segments.contains { $0.kind == .aligned && $0.start == 3001 && $0.end == 3011 })
    }

    @Test(arguments: ["missing", "inconsistent"])
    @MainActor
    func detectedInvalidCIGARFailsTheRegionAndRestoresThePreviousData(defect: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "\(defect)-cigar")
        session.editInterval("tiny:101-110")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name) == ["good"])
        session.editInterval("tiny:17001-17011")
        await session.submitInterval()?.value
        #expect(session.presentation.regionalError != nil)
        #expect(session.presentation.target?.formatted == "tiny:101-110")
        #expect(session.presentation.alignments.map(\.name) == ["good"])
        #expect(!session.presentation.isLoading)
    }

    @Test
    @MainActor
    func detectedIndexHeaderMismatchPreservesPopulatedViewWithoutFallback() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "rows")
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        session.scrollVertically(to: 200)
        let previous = session.presentation
        let bam = files.directory.appendingPathComponent("mismatched.bam")
        let bad = bam.appendingPathExtension("bai")
        let good = bam.appendingPathExtension("csi")
        for (source, target) in [("opening.bam", bam), ("rows.bam.bai", bad), ("opening.bam.csi", good)] {
            try FileManager.default.copyItem(at: files.sources.appendingPathComponent(source), to: target)
        }
        await session.openBAM(bam)
        await session.chooseIndex(bad)
        #expect(session.presentation.openError?.fileURL == bad)
        #expect(session.presentation.openError?.message.contains("reference count") == true)
        #expect(session.presentation.bamURL == previous.bamURL)
        #expect(session.presentation.target == previous.target)
        #expect(session.presentation.alignments == previous.alignments)
        #expect(session.presentation.verticalOffset == 200)
        await session.openBAM(bam)
        await session.chooseIndex(good)
        #expect(session.presentation.bamURL == bam)
        #expect(session.presentation.indexURL == good)
        #expect(session.presentation.openError == nil)
    }

}
