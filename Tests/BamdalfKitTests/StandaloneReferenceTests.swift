import BamdalfKit
import Foundation
import Testing

extension FixtureFiles {
    func reference(_ filename: String, name: String? = nil, fasta: String) throws -> URL {
        let input = directory.appendingPathComponent("source.fa")
        let output = directory.appendingPathComponent(filename)
        try Data(fasta.utf8).write(to: input)
        try ReferenceBundle.create(from: input, at: output, name: name ?? output.deletingPathExtension().lastPathComponent, creator: "Standalone reference test")
        try FileManager.default.removeItem(at: input)
        return output
    }
}

@MainActor
struct StandaloneReferenceTests {
    @Test func browseAReferenceWithoutItsFASTAOrABAM() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("sample.bref", fasta: ">one\naCGtnRyK\n>two\nAC")
        let session = ViewerSession()
        session.setViewportWidth(100)
        #expect(session.presentation.referenceURL == nil)
        await session.openReference(url)
        #expect(session.presentation.referenceURL == url)
        #expect(session.presentation.intervalEntryAvailable)
        #expect(session.presentation.message == "Enter a genomic interval")
        session.editInterval("one:2-5")
        await session.submitInterval()?.value
        #expect(session.presentation.referenceBases?.bases == Data("CGtn".utf8))
        #expect(session.presentation.alignments.isEmpty && session.presentation.bamURL == nil)
        await session.pan(.right)?.value
        #expect(session.presentation.referenceBases?.bases == Data("tnRy".utf8))
        await session.zoom(.in)?.value
        #expect(session.presentation.referenceBases?.bases == Data("nR".utf8))
        session.closeReference()
        #expect(session.presentation.referenceURL == nil)
        #expect(session.presentation.referenceBases == nil)
        #expect(!session.presentation.intervalEntryAvailable && session.presentation.target == nil)
        #expect(session.presentation.message == "No BAM file open")
    }
}

extension StandaloneReferenceTests {
    @Test func replacementUsesExactContigNamesAndKeepsOnlyValidTargets() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let first = try files.reference("one.bref", fasta: ">é\nAAAA\n>e\u{301}\nCcGT")
        let second = try files.reference("two.bref", fasta: ">e\u{301}\nTGCA")
        let shorter = try files.reference("short.bref", fasta: ">e\u{301}\nT")
        let session = ViewerSession()
        session.setViewportWidth(100)
        await session.openReference(first)
        session.editInterval("é:1-2")
        await session.submitInterval()?.value
        session.editInterval("e\u{301}:1-2")
        await session.submitInterval()?.value
        #expect(session.presentation.referenceBases?.bases == Data("Cc".utf8))
        session.editInterval("keep my draft")
        await session.openReference(nil)
        await session.openReference(files.directory.appendingPathComponent("missing.bref"))
        #expect(session.presentation.referenceURL == first)
        #expect(session.presentation.intervalText == "keep my draft")
        #expect(session.presentation.openError?.fileURL.lastPathComponent == "missing.bref")
        await session.openReference(second)
        #expect(session.presentation.referenceBases?.bases == Data("TG".utf8))
        session.editInterval("é:1-2")
        await session.submitInterval()?.value
        #expect(session.presentation.intervalError != nil)
        await session.openReference(shorter)
        #expect(session.presentation.referenceURL == shorter && session.presentation.target == nil)
        #expect(session.presentation.intervalText.isEmpty)
        #expect(session.presentation.message == "Enter a genomic interval")
    }
}

extension StandaloneReferenceTests {
    @Test(arguments: [false, true]) func requiredFailureRestoresOnlyThisReferenceAndPreservesANewerDraft(replace: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let first = try files.reference("first.bref", fasta: ">one\naCGtnRyK")
        let replacement = try files.reference("new.bref", fasta: ">one\nTTTTTTTT")
        let gate = RegionGate()
        let session = ViewerSession(loadReferenceRegion: { bundle, interval in
            if bundle.url == first && interval.start == 5 {
                await gate.pause(5)
                throw RegionalLoadError(interval: interval, message: "Unreadable reference chunk")
            }
            return try await bundle.read(interval)
        })
        session.setViewportWidth(8)
        await session.openReference(first)
        session.editInterval("one:1-2")
        await session.submitInterval()?.value
        session.editInterval("one:5-6")
        let pending = session.submitInterval()
        await gate.waitFor(5)
        if replace { await session.openReference(replacement) }
        session.editInterval("newer draft")
        await gate.release(5)
        await pending?.value
        #expect(session.presentation.referenceURL == (replace ? replacement : first))
        #expect(session.presentation.intervalText == "newer draft")
        #expect(session.presentation.regionalError?.interval.formatted == (replace ? nil : "one:5-6"))
        #expect(session.presentation.referenceBases?.bases == Data((replace ? "TT" : "aC").utf8))
        session.editInterval("one:3-4")
        await session.submitInterval()?.value
        #expect(session.presentation.referenceBases?.bases == Data((replace ? "TT" : "Gt").utf8))
    }

    @Test func resizingToOnePointRequiresSequenceAndHiddenDetailNeedsNoRead() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("sample.bref", fasta: ">one\nAacCGgTt")
        let session = ViewerSession(loadReferenceRegion: { _, interval in
            throw RegionalLoadError(interval: interval, message: "Unreadable visible bases")
        })
        session.setViewportWidth(7.99)
        await session.openReference(url)
        session.editInterval("one:1-8")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.target?.formatted == "one:1-8")
        #expect(session.presentation.referenceBases == nil && session.presentation.regionalError == nil)
        session.editInterval("draft while the overview is visible")
        await session.setViewportWidth(8)?.value
        #expect(session.presentation.intervalText == "draft while the overview is visible")
        #expect(session.presentation.target == nil)
        #expect(session.presentation.regionalError?.interval.formatted == "one:1-8")
        #expect(session.presentation.referenceURL == url)
    }
}

extension StandaloneReferenceTests {
    @Test(arguments: [false, true]) func fractionalDragShowsAvailableBasesAndRetriesOptionalFailures(failPreview: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("sample.bref", fasta: ">one\naCGtnRyK")
        let session = ViewerSession(loadReferenceRegion: { bundle, interval in
            if failPreview && interval.start == 2 && interval.end == 6 {
                throw RegionalLoadError(interval: interval, message: "Optional drag edge unavailable")
            }
            return try await bundle.read(interval)
        })
        session.setViewportWidth(32)
        await session.openReference(url)
        session.editInterval("one:2-5")
        await session.submitInterval()?.value
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.125)?.value
        #expect(session.presentation.previewOffsetInBases == -0.5)
        #expect(session.presentation.target?.formatted == "one:3-6")
        #expect(session.presentation.referenceBases?.bases == Data((failPreview ? "CGtn" : "CGtnR").utf8))
        #expect(session.presentation.regionalError == nil && !session.presentation.isLoading)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.target?.formatted == "one:3-6")
        #expect(session.presentation.referenceBases?.bases == Data("GtnR".utf8))
        #expect(session.presentation.regionalError == nil)
    }
}

extension StandaloneReferenceTests {
    @Test func failedTargetRestoresAReadableOverviewAtItsNewScale() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("selected.bref", fasta: ">one\nAaCGtnRY")
        let gate = RegionGate()
        let session = ViewerSession(loadReferenceRegion: { bundle, interval in
            if interval.start == 4 {
                await gate.pause(4)
                throw RegionalLoadError(interval: interval, message: "Cannot read selected region")
            }
            return try await bundle.read(interval)
        })
        session.setViewportWidth(2)
        await session.openReference(url)
        session.editInterval("one:1-3")
        await session.submitInterval()?.value
        session.editInterval("one:4-5")
        let pending = session.submitInterval()
        await gate.waitFor(4)
        session.setViewportWidth(8)
        session.editInterval("newer edit")
        await gate.release(4)
        await pending?.value
        #expect(session.presentation.target?.formatted == "one:1-3")
        #expect(session.presentation.referenceBases?.bases == Data("AaC".utf8))
        #expect(session.presentation.intervalText == "newer edit")
        #expect(session.presentation.regionalError?.interval.formatted == "one:4-5")
    }

    @Test func returningToAFailedPreviewWaitsForRequiredNavigationToRetry() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try files.reference("selected.bref", fasta: ">one\nAaCGtnRY\n>two\nTtAGccGG")
        let failure = FirstPreviewFailure()
        let session = ViewerSession(loadReferenceRegion: { bundle, interval in
            if interval.start == 2 && interval.end == 6, await failure.take() {
                throw RegionalLoadError(interval: interval, message: "Optional read failed")
            }
            return try await bundle.read(interval)
        })
        session.setViewportWidth(32)
        await session.openReference(url)
        session.editInterval("one:2-5")
        await session.submitInterval()?.value
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.125)?.value
        await session.previewAlignmentDrag(horizontalFraction: 0)?.value
        await session.endAlignmentDrag()?.value
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.125)?.value
        #expect(session.presentation.referenceBases?.bases == Data("aCGt".utf8))
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.referenceBases?.bases == Data("CGtn".utf8))
        session.editInterval("two:2-5")
        await session.submitInterval()?.value
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.125)?.value
        #expect(session.presentation.referenceBases?.bases == Data("tAGcc".utf8))
        await session.endAlignmentDrag()?.value
    }
}

private actor FirstPreviewFailure {
    private var available = true
    func take() -> Bool {
        defer { available = false }
        return available
    }
}

extension StandaloneReferenceTests {
    @Test func recoveryReadCompletingDuringADragWaitsForRelease() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let reference = try files.reference("assembly.bref", fasta: ">one\nAaCGtnRY")
        let gate = RegionGate()
        let session = ViewerSession(loadReferenceRegion: { bundle, interval in
            if interval.start == 4 && interval.end == 5 {
                await gate.pause(4)
                throw RegionalLoadError(interval: interval, message: "Cannot read target")
            }
            if interval.start == 1 { await gate.pause(1) }
            return try await bundle.read(interval)
        })
        session.setViewportWidth(2)
        await session.openReference(reference)
        session.editInterval("one:1-3")
        await session.submitInterval()?.value
        session.editInterval("one:4-5")
        let pending = session.submitInterval()
        await gate.waitFor(4)
        session.setViewportWidth(8)
        await gate.release(4)
        await gate.waitFor(1)
        session.beginAlignmentDrag()
        await session.previewAlignmentDrag(horizontalFraction: -0.2)?.value
        await gate.release(1)
        await pending?.value
        try #require(session.presentation.regionalError == nil)
        #expect(session.presentation.target?.formatted == "one:4-5" && session.presentation.previewOffsetInBases > 0)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.regionalError?.interval.formatted == "one:4-5" && !session.presentation.isLoading)
        #expect(session.presentation.target?.formatted == "one:1-3")
        #expect(session.presentation.referenceBases?.bases == Data("AaC".utf8))
    }
}
