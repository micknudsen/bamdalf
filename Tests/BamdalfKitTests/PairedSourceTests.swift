import BamdalfKit
import Foundation
import Testing

@MainActor
struct PairedSourceTests {
    @Test(arguments: [false, true]) func addingTheOtherSourceKeepsTheLocusAndDisplaysBothTracks(referenceFirst: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let reference = try files.reference("assembly.bref", fasta: ">extra\nAaTG\n>other_reference\n"
            + String(repeating: "G", count: 800) + "\n>tiny\n" + String(repeating: "AcGT", count: 500))
        let session = ViewerSession(prefetch: .disabled)
        session.setViewportWidth(240)
        if referenceFirst { await session.openReference(reference) }
        else { try await files.openedSession(session: session) }
        #expect(session.presentation.target == nil)
        session.editInterval("tiny:99-112")
        await session.submitInterval()?.value
        if referenceFirst { try await files.openedSession(session: session) }
        else { await session.openReference(reference) }
        let view = session.presentation
        #expect(view.referenceURL == reference && view.bamURL?.lastPathComponent == "opening.bam")
        #expect(view.references.map(\.name) == ["extra", "other_reference", "tiny"])
        #expect(view.target?.formatted == "tiny:99-112")
        #expect(view.referenceBases?.bases == Data("GTAcGTAcGTAcGT".utf8))
        #expect(view.alignments.map(\.name) == ["pair1"])
        #expect(view.alignments.first?.referenceStart == 101 && view.alignments.first?.referenceEnd == 110)
    }
}

extension PairedSourceTests {
    private static let last = "e\u{301}"

    @Test(arguments: ["m5-matching", "m5-partial"]) func availableChecksumsAreComparedIndependentOfHeaderOrder(fixture: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession()
        session.setViewportWidth(100)
        let first = fixture == "m5-partial" ? "CCCCCCCC" : "acgtACGT"
        let reference = try files.reference("assembly.bref", fasta: ">extra\nA\n>\(Self.last)\nttTT\n>main\n\(first)")
        await session.openReference(reference)
        try await files.openedSession(fixture: fixture, session: session)
        session.editInterval("\(Self.last):1-4")
        await session.submitInterval()?.value
        #expect(session.presentation.referenceBases?.bases == Data("ttTT".utf8))
        #expect(session.presentation.alignments.map(\.name) == ["last"])
    }

    @Test(arguments: [false, true], ["missing", "case", "bytes", "length", "M5", "first M5"])
    func incompatibleSecondSourcePreservesTheOriginalView(referenceFirst: Bool, defect: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let lastName = ["missing": "extra", "case": "E\u{301}", "bytes": "é"][defect] ?? Self.last
        let lastBases = ["length": "TTT", "M5": "TTTA"][defect] ?? "ttTT"
        let firstBases = defect == "first M5" ? "CCCCCCCC" : "acgtACGT"
        let reference = try files.reference("assembly.bref", fasta: ">main\n\(firstBases)\n>\(lastName)\n\(lastBases)")
        let fixture = defect == "first M5" ? "m5-matching" : "m5-partial"
        let bam = files.sources.appendingPathComponent(fixture + ".bam")
        let session = ViewerSession(prefetch: .disabled)
        session.setViewportWidth(100)
        if referenceFirst { await session.openReference(reference) }
        else { try await files.openedSession(fixture: fixture, session: session) }
        session.editInterval("main:2-6")
        await session.submitInterval()?.value
        session.scrollVertically(to: 12)
        session.editInterval("a pending draft")
        let original = session.presentation
        if referenceFirst {
            await session.openBAM(bam)
            await session.chooseIndex(bam.appendingPathExtension("bai"))
        } else { await session.openReference(reference) }
        let after = session.presentation
        let error = try #require(after.openError)
        #expect(error.fileURL == (referenceFirst ? bam : reference))
        #expect(error.message.contains(defect == "first M5" ? "main" : Self.last))
        if defect.contains("M5") { #expect(error.message.contains("M5")) }
        if defect == "length" { #expect(error.message.contains("length")) }
        #expect(after.bamURL == original.bamURL && after.indexURL == original.indexURL)
        #expect(after.referenceURL == original.referenceURL && after.sessionID == original.sessionID)
        #expect(after.target == original.target && after.intervalText == original.intervalText)
        #expect(after.references == original.references && after.verticalOffset == original.verticalOffset)
        #expect(after.alignments == original.alignments && after.referenceBases?.bases == original.referenceBases?.bases)
    }
}

extension PairedSourceTests {
    @Test func referenceOnlyContigSkipsRequiredAndSpeculativeBAMReads() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        // The BAM declares the decomposed name. The reference also has its composed spelling.
        let reference = try files.reference("assembly.bref", fasta: ">é\naCGtacGT\n>main\nACGTACGT\n>\(Self.last)\nTTTT")
        let session = ViewerSession(loadRegion: { bam, target in
            #expect(!target.reference.utf8.elementsEqual("é".utf8))
            return try await bam.alignments(in: target)
        }, loadPrefetchRegion: { bam, target, budget in
            #expect(!target.reference.utf8.elementsEqual("é".utf8))
            return try await bam.alignments(in: target, budget: budget)
        })
        session.setViewportWidth(64)
        await session.openReference(reference)
        session.editInterval("é:1-4")
        await session.submitInterval()?.value
        try await files.openedSession(fixture: "m5-matching", session: session)
        #expect(session.presentation.referenceBases?.bases == Data("aCGt".utf8))
        #expect(session.presentation.alignments.isEmpty && session.presentation.regionalError == nil)
        session.editInterval("\(Self.last):1-4")
        await session.submitInterval()?.value
        #expect(session.presentation.alignments.map(\.name) == ["last"])
        session.editInterval("é:1-4")
        await session.submitInterval()?.value
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.25)?.value
        #expect(session.presentation.alignments.isEmpty)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.referenceBases?.bases == Data("CGta".utf8))
        #expect(session.presentation.alignments.isEmpty && session.presentation.rowCount == 0)
        #expect(session.presentation.message.isEmpty && session.presentation.regionalError == nil)
        #expect(!session.presentation.isLoading && !session.presentation.isDownsampled)
    }
}
