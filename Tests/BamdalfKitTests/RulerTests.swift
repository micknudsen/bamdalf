import Foundation
import Testing
import BamdalfKit

struct RulerTests {
    @Test
    @MainActor
    func rulerUsesFullCoordinatesAndReducesDensityWithoutAbbreviations() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        await session.openBAM(files.sources.appendingPathComponent("coordinates.bam"))
        await session.chooseIndex(files.sources.appendingPathComponent("coordinates.bam.csi"))
        #expect(session.presentation.rulerTicks(availableWidth: 1000).isEmpty)
        session.editInterval("large_reference:1-300000000")
        session.submitInterval()
        #expect(session.presentation.intervalText == "large_reference:1-300,000,000")

        let wide = session.presentation.rulerTicks(availableWidth: 1000)
        #expect(wide.map(\.label) == ["50,000,000", "100,000,000", "150,000,000", "200,000,000", "250,000,000", "300,000,000"])
        let narrow = session.presentation.rulerTicks(availableWidth: 250)
        #expect(narrow.map(\.label) == ["200,000,000"])
        #expect(wide.allSatisfy { $0.fraction >= 0 && $0.fraction <= 1 })
        session.editInterval("unfinished:")
        #expect(session.presentation.rulerTicks(availableWidth: 1000) == wide)

        session.editInterval("large_reference:150000000-150000000")
        session.submitInterval()
        let single = session.presentation.rulerTicks(availableWidth: 1000)
        #expect(single.map(\.label) == ["150,000,000"])
        #expect(single.first?.fraction == 0.5)
        session.editInterval("ref:with-hyphen:1-100")
        session.submitInterval()
        #expect(session.presentation.target?.reference == "ref:with-hyphen")
        #expect(session.presentation.intervalError == nil)
    }
}
