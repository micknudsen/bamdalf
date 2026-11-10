import Foundation
import Testing
import BamdalfKit

struct AlignmentLayoutTests {
    @Test
    @MainActor
    func fullDrawnExtentsNeverOverlapAndNewerScrollingSurvivesNearbyLoad() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 551 { await gate.pause(301) }
            return records
        })
        let bam = files.sources.appendingPathComponent("rows.bam")
        await session.openBAM(bam)
        await session.chooseIndex(bam.appendingPathExtension("bai"))
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.count == 80)
        #expect(Set(session.presentation.alignments.map(\.id)).count == 80)
        #expect(Set(session.presentation.alignments.map(\.row)).count == 80)
        #expect(session.presentation.rowCount == 80)
        session.scrollVertically(to: 400)
        session.editInterval("tiny:0100-0300")
        await session.submitInterval()?.value
        #expect(session.presentation.verticalOffset == 400)

        session.editInterval("tiny:102-301")
        let pending = session.submitInterval()
        #expect(session.presentation.verticalOffset == 400)
        await gate.waitFor(301)
        session.scrollVertically(to: 200)
        await gate.release(301)
        await pending?.value
        #expect(session.presentation.verticalOffset == 200)
        #expect(session.presentation.rowCount == 80)

        let displayed = session.presentation.alignments
        await session.openBAM(nil)
        await session.openBAM(bam)
        await session.chooseIndex(nil)
        await session.openBAM(files.directory.appendingPathComponent("missing.bam"))
        #expect(session.presentation.alignments == displayed)
        #expect(session.presentation.verticalOffset == 200)

        session.editInterval("tiny:1001-1054")
        await session.submitInterval()?.value
        #expect(session.presentation.verticalOffset == 0)
        #expect(session.presentation.alignments.count == 2)
        #expect(Set(session.presentation.alignments.map(\.row)).count == 2)
        for records in Dictionary(grouping: session.presentation.alignments, by: \.row).values {
            let sorted = records.sorted { $0.drawnStart < $1.drawnStart }
            for pair in zip(sorted, sorted.dropFirst()) {
                #expect(pair.0.drawnEnd < pair.1.drawnStart)
            }
        }
    }
}
