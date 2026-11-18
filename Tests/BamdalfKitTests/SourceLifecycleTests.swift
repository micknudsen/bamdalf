import BamdalfKit
import Foundation
import Testing

@MainActor
struct SourceLifecycleTests {
    private func reference(in files: FixtureFiles, named name: String = "assembly", base: Character = "A") throws -> URL {
        try files.reference(name + ".bref", fasta: ">extra\nGTAC\n>tiny\n" + String(repeating: base, count: 20_000)
            + "\n>other_reference\n" + String(repeating: "G", count: 20_000))
    }

    private func openPair(_ files: FixtureFiles, in session: ViewerSession, reference: URL,
                          at interval: String = "tiny:101-110") async throws {
        session.setViewportWidth(100)
        await session.openReference(reference)
        try await files.openedSession(fixture: "rows", session: session)
        session.editInterval(interval)
        await session.submitInterval()?.value
    }

    @Test(arguments: [false, true])
    func cancelingAnOpenProtectsBothTracksAndTheEditor(evenIfReaderFails: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let original = try reference(in: files)
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadBAM: { url, index in
            let bam = try await BAMFile.open(url, indexURL: index)
            if url.lastPathComponent == "alignments.bam" {
                await gate.pause(1)
                if evenIfReaderFails { throw CocoaError(.fileReadUnknown) }
            }
            return bam
        })
        try await openPair(files, in: session, reference: original)
        session.scrollVertically(to: 120)
        let prior = session.presentation
        session.beginAlignmentDrag()
        let candidate = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(candidate)
        let pending = Task { await session.chooseIndex(candidate.appendingPathExtension("bai")) }
        await gate.waitFor(1)
        await session.endAlignmentDrag()?.value
        #expect(session.presentation.isOpening)
        session.editInterval("unfinished edit")
        pending.cancel()
        await gate.release(1)
        await pending.value
        let after = session.presentation
        #expect(after.openError == nil && !after.isOpening)
        #expect(after.bamURL == prior.bamURL && after.referenceURL == original && after.sessionID == prior.sessionID)
        #expect(after.target == prior.target && after.alignments == prior.alignments && after.verticalOffset == 120)
        #expect(after.referenceBases?.bases == Data("AAAAAAAAAA".utf8) && after.intervalText == "unfinished edit")
    }

    @Test(arguments: [false, true], [false, true])
    func replacingABAMDuringNavigationStartsNewRowsAndOwnsItsFirstRegionalFailure(
        failOldRead: Bool, failNewRead: Bool
    ) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let original = try reference(in: files)
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, region in
            let records = try await file.alignments(in: region)
            if file.url.lastPathComponent == "rows.bam", await gate.pauseIfArmed(1) {
                if failOldRead { throw RegionalLoadError(interval: region, message: "Retired BAM failed") }
            }
            if file.url.lastPathComponent == "alignments.bam", await gate.pauseIfArmed(2) {
                if failNewRead { throw RegionalLoadError(interval: region, message: "New BAM read failed") }
            }
            return records
        })
        try await openPair(files, in: session, reference: original)
        try #require(session.presentation.rowCount == 80)
        session.scrollVertically(to: 120)
        await gate.arm(1)
        session.editInterval("tiny:1001-1010")
        let obsolete = session.submitInterval()
        await gate.waitFor(1)
        session.editInterval("keep my edit")
        await gate.arm(2)
        let nextBAM = files.sources.appendingPathComponent("alignments.bam")
        await session.openBAM(nextBAM)
        let replacement = Task { await session.chooseIndex(nextBAM.appendingPathExtension("bai")) }
        await gate.waitFor(2)
        let loading = session.presentation
        #expect(loading.bamURL == nextBAM && loading.referenceURL == original)
        #expect(loading.target?.formatted == "tiny:1,001-1,010" && loading.isLoading)
        #expect(loading.alignments.isEmpty && loading.rowCount == 0 && loading.verticalOffset == 0)
        #expect(loading.intervalText == "keep my edit")
        await gate.release(2)
        await replacement.value
        await gate.release(1)
        await obsolete?.value
        let after = session.presentation
        #expect(after.bamURL == nextBAM && after.referenceURL == original && after.openError == nil)
        #expect(after.intervalText == "keep my edit" && !after.isLoading && after.verticalOffset == 0)
        if failNewRead {
            #expect(after.target == nil && after.alignments.isEmpty && after.rowCount == 0 && after.referenceBases == nil)
            #expect(after.message == "Enter a genomic interval" && after.regionalError?.message == "New BAM read failed")
        } else {
            #expect(after.target?.formatted == "tiny:1,001-1,010" && after.regionalError == nil)
            #expect(after.alignments.map(\.name) == ["complex"])
            #expect(after.alignments.map(\.row) == [0] && after.rowCount == 1)
            #expect(after.referenceBases?.bases == Data("AAAAAAAAAA".utf8))
        }
        session.editInterval("tiny:101-110")
        await session.submitInterval()?.value
        #expect(Set(session.presentation.alignments.map(\.name)) == ["forward", "reverse", "supplementary"])
        #expect(session.presentation.regionalError == nil)
    }

    @Test(arguments: [false, true])
    func failedNavigationAfterChangingTheReferenceRestoresOnlyValidBAMRows(replace: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let original = try reference(in: files)
        let replacement = try reference(in: files, named: "replacement", base: "c")
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadReferenceRegion: { bundle, region in
            if region.start == 1001 {
                if bundle.url == original { await gate.pause(1) }
                else {
                    await gate.pause(2)
                    throw RegionalLoadError(interval: region, message: "Unreadable new target")
                }
            }
            return try await bundle.read(region)
        }, loadRegion: { bam, region in
            if await gate.pauseIfArmed(2) {
                throw RegionalLoadError(interval: region, message: "Unreadable new target")
            }
            return try await bam.alignments(in: region)
        })
        try await openPair(files, in: session, reference: original)
        let prior = session.presentation
        try #require(prior.rowCount == 80)
        session.editInterval("tiny:1001-1010")
        let obsolete = session.submitInterval()
        await gate.waitFor(1)
        if !replace { await gate.arm(2) }
        let changed = Task {
            if replace { await session.openReference(replacement) }
            else {
                session.closeReference()
                await session.submitInterval()?.value
            }
        }
        await gate.waitFor(2)
        session.editInterval("newer draft")
        await gate.release(2)
        await changed.value
        await gate.release(1)
        await obsolete?.value
        let after = session.presentation
        #expect(after.bamURL == prior.bamURL && after.referenceURL == (replace ? replacement : nil))
        #expect(after.target == prior.target && after.rowCount == 80 && after.alignments == prior.alignments)
        #expect(after.referenceBases?.bases == (replace ? Data("cccccccccc".utf8) : nil))
        #expect(after.regionalError?.message == "Unreadable new target" && after.intervalText == "newer draft")
    }

    @Test(arguments: [false, true], [false, true])
    func changingReferenceDuringASpeculativeReadDiscardsItsLateOutcome(close: Bool, failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let original = try reference(in: files)
        let replacement = try files.reference("replacement.bref", fasta: ">tiny\n" + String(repeating: "c", count: 20_000)
            + "\n>extra\nTgCa")
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadReferenceRegion: { bundle, region in
            if bundle.url == original, region.start == 2 {
                await gate.pause(1)
                if failLate { throw RegionalLoadError(interval: region, message: "Speculative read failed") }
            }
            return try await bundle.read(region)
        })
        try await openPair(files, in: session, reference: original, at: "extra:1-2")
        session.beginAlignmentDrag()
        let pending = session.previewAlignmentDrag(horizontalFraction: -0.5)
        await gate.waitFor(1)
        if close { session.closeReference() } else { await session.openReference(replacement) }
        session.editInterval("edit after source change")
        await gate.release(1)
        await pending?.value
        let after = session.presentation
        #expect(after.bamURL?.lastPathComponent == "rows.bam" && after.referenceURL == (close ? nil : replacement))
        #expect(after.target?.formatted == (close ? nil : "extra:1-2"))
        #expect(after.referenceBases?.bases == (close ? nil : Data("Tg".utf8)))
        #expect(after.previewOffsetInBases == 0 && after.alignments.isEmpty && after.rowCount == 0)
        #expect(after.regionalError == nil && after.intervalText == "edit after source change")
        if close {
            #expect(after.message == "Enter a genomic interval")
            session.editInterval("extra:1-2")
            await session.submitInterval()?.value
            #expect(session.presentation.intervalError != nil)
        } else {
            session.beginAlignmentDrag()
            await session.previewAlignmentDrag(horizontalFraction: -0.5)?.value
            #expect(session.presentation.referenceBases?.bases == Data("gC".utf8))
            await session.endAlignmentDrag()?.value
            #expect(session.presentation.target?.formatted == "extra:2-3")
        }
    }

    @Test func changingTheNavigationDictionaryRetiresItsObsoleteDraftError() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let original = try reference(in: files)
        let replacement = try files.reference("replacement.bref", fasta: ">tiny\n" + String(repeating: "c", count: 20_000)
            + "\n>new\nCAT")
        let session = ViewerSession(prefetch: .disabled)
        try await openPair(files, in: session, reference: original)
        session.editInterval("new:1-3")
        await session.submitInterval()?.value
        try #require(session.presentation.intervalError != nil)
        await session.openReference(replacement)
        #expect(session.presentation.intervalText == "new:1-3" && session.presentation.intervalError == nil)
        #expect(session.presentation.target?.formatted == "tiny:101-110")
        await session.submitInterval()?.value
        #expect(session.presentation.referenceBases?.bases == Data("CAT".utf8))
    }

    @Test func anUnreadableRecoveryReleasesTheRequiredBAMRegion() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let original = try reference(in: files)
        let replacement = try reference(in: files, named: "replacement", base: "c")
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .init(maximumBytes: 1), loadReferenceRegion: { bundle, region in
            if bundle.url == replacement, await gate.count(1) == 0 {
                await gate.pause(1)
                throw RegionalLoadError(interval: region, message: "Cannot read replacement bases")
            }
            return try await bundle.read(region)
        }, loadRegion: { bam, region in
            if await gate.count(1) > 0 { throw RegionalLoadError(interval: region, message: "BAM retry failed") }
            return try await bam.alignments(in: region)
        })
        try await openPair(files, in: session, reference: original)
        try #require(session.presentation.rowCount == 80)
        let changed = Task { await session.openReference(replacement) }
        await gate.waitFor(1)
        await gate.release(1)
        await changed.value
        try #require(session.presentation.target == nil && session.presentation.regionalError?.message == "Cannot read replacement bases")
        // Once interval entry has no recovery view, those 80 rows exceed the optional budget.
        session.editInterval("tiny:101-110")
        await session.submitInterval()?.value
        #expect(session.presentation.regionalError?.message == "BAM retry failed")
        #expect(session.presentation.alignments.isEmpty && session.presentation.target == nil)
    }
}
