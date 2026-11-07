import Foundation
import Testing
import BamdalfKit

struct IntervalEntryTests {
    @Test
    @MainActor
    func onlySuccessfulBAMReplacementClearsTheTargetAndRejectedDraft() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        let bam = files.sources.appendingPathComponent("opening.bam")
        let index = files.sources.appendingPathComponent("opening.bam.bai")
        await session.openBAM(bam)
        await session.chooseIndex(index)
        session.editInterval("tiny:1-1")
        session.submitInterval()
        session.editInterval("tiny:1-2001")
        session.submitInterval()
        let target = session.presentation.target
        let error = session.presentation.intervalError

        await session.openBAM(nil)
        await session.openBAM(bam)
        await session.chooseIndex(nil)
        await session.openBAM(files.directory.appendingPathComponent("missing.bam"))
        #expect(session.presentation.target == target)
        #expect(session.presentation.intervalText == "tiny:1-2001")
        #expect(session.presentation.intervalError == error)

        await session.openBAM(bam)
        await session.chooseIndex(index)
        #expect(session.presentation.target == nil)
        #expect(session.presentation.intervalText == "")
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.message == "Enter a genomic interval")
    }

    @Test
    @MainActor
    func editingAndEscapePreserveTheTargetWithoutValidatingDrafts() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession()
        session.editInterval("tiny:10-1")
        session.submitInterval()
        #expect(session.presentation.intervalError == "Start must be at or before end.")
        session.editInterval("tiny:10-1")
        #expect(session.presentation.intervalError != nil)
        session.resetIntervalEditor()
        #expect(session.presentation.intervalText == "")
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.target == nil)

        session.editInterval("other_reference:800-800")
        session.submitInterval()
        let target = session.presentation.target
        #expect(target?.formatted == "other_reference:800-800")
        session.editInterval("other_reference:800-801")
        session.submitInterval()
        #expect(session.presentation.intervalError != nil)
        session.editInterval("incomplete:")
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.target == target)
        session.resetIntervalEditor()
        #expect(session.presentation.intervalText == "other_reference:800-800")
        #expect(session.presentation.target == target)
        session.editInterval("other_reference:0800-0800")
        session.submitInterval()
        #expect(session.presentation.target == target)
        #expect(session.presentation.intervalText == "other_reference:800-800")
    }

    @Test(arguments: [
        "Tiny:1-10", "chr1:1-10", "tiny:0-10", "tiny:11-10", "tiny:1-2001",
        "other_reference:1-801", "tiny:1,00-2,000", "tiny:1-20,00", "tiny:1-1,000,",
        "tiny: 1-10", "tiny:1 -10", "tiny:1-1 0", "ti ny:1-10", "tiny:1–10", "tiny:1—10",
        "tiny:1", "tiny", "tiny:-1-10", "tiny:1--10", "tiny:1-10-", "tiny:+1-10",
        "tiny:1.0-10", "tiny:１-10", "tiny:1-9223372036854775808", ""
    ])
    @MainActor
    func rejectedSubmissionRetainsExactTextAndPreviousTarget(text: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession()
        session.editInterval("tiny:100-200")
        session.submitInterval()

        session.editInterval(text)
        session.submitInterval()

        #expect(session.presentation.intervalText == text)
        #expect(session.presentation.target?.formatted == "tiny:100-200")
        #expect(session.presentation.intervalError?.isEmpty == false)
    }

    @Test(arguments: ["tiny:1000-2000", "tiny:1,000-2,000", " \n tiny:1,000-2,000\t"])
    @MainActor
    func validSubmissionUsesRealHeaderBoundsAndFormatsTheTarget(text: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession()

        session.editInterval(text)
        session.submitInterval()

        #expect(session.presentation.intervalText == "tiny:1,000-2,000")
        #expect(session.presentation.target?.reference == "tiny")
        #expect(session.presentation.target?.start == 1000)
        #expect(session.presentation.target?.end == 2000)
        #expect(session.presentation.intervalError == nil)
        #expect(session.presentation.message.isEmpty)
    }
}
