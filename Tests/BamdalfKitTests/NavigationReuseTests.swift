import Foundation
import Testing
import BamdalfKit

struct NavigationReuseTests {
    @Test(arguments: [1, 12])
    @MainActor
    func historicalEvictionCannotDiscardCoverageBackingAnActiveProvisionalView(stages: Int) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if (550..<650).contains(target.end) { await gate.pause(target.end - 250) }
            return records
        })
        try await files.openedSession(fixture: "rows", indexFormat: "bai", session: session)
        session.editInterval("tiny:100-200")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        // Fill the documented historical snapshot budget, leaving this result
        // oldest. Returning to it must make its coverage active again.
        for start in stride(from: 2000, through: 8000, by: 1000) {
            session.editInterval("tiny:\(start)-\(start + 99)")
            await session.submitInterval()?.value
        }
        session.editInterval("tiny:100-200")
        #expect(session.submitInterval() == nil)
        var partial: Task<Void, Never>?
        for stage in 0..<stages {
            session.editInterval("tiny:\(50 - stage)-\(300 + stage)")
            let next = session.submitInterval()
            await gate.waitFor(Int64(300 + stage))
            if stage > 0 {
                await gate.release(Int64(299 + stage))
                await partial?.value
            }
            partial = next
            #expect(session.presentation.alignments == saved)
        }
        session.scrollVertically(to: 200)
        session.editInterval("tiny:110-190")
        let ready = session.submitInterval()
        #expect(ready == nil, "Still-loaded complete coverage must survive historical cache admission")
        #expect(session.presentation.alignments == saved)
        #expect(session.presentation.verticalOffset == 200)
        #expect(!session.presentation.isLoading)
        await ready?.value
        await gate.release(Int64(299 + stages))
        await partial?.value
        #expect(session.presentation.target?.formatted == "tiny:110-190")
        #expect(session.presentation.alignments == saved)
    }

    @Test
    @MainActor
    func expandedViewsStayProvisionalAndFileReplacementOwnsCoverage() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            if target.end == 550 {
                await gate.pause(300)
                throw RegionalLoadError(interval: target, message: "Second missing interval failed")
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "navigation", indexFormat: "bai", session: session)
        session.editInterval("tiny:150-155")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        session.editInterval("tiny:100-300")
        let pending = session.submitInterval()
        await gate.waitFor(300)
        #expect(session.presentation.isLoading)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["anchor", "new_tail", "lead", "late"])
        await gate.release(300)
        await pending?.value
        #expect(session.presentation.alignments == saved)
        #expect(session.presentation.target?.formatted == "tiny:150-155")
        #expect(session.presentation.regionalError?.interval.formatted == "tiny:100-300")
        session.dismissRegionalError(try #require(session.presentation.regionalError?.id))

        await session.openBAM(nil)
        let bam = files.sources.appendingPathComponent("navigation.bam")
        await session.openBAM(bam)
        await session.chooseIndex(nil)
        await session.openBAM(files.directory.appendingPathComponent("absent.bam"))
        #expect(session.presentation.alignments == saved)
        session.dismissOpenError()
        session.editInterval("tiny:151-154")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.alignments == saved)

        let oldSession = session.presentation.sessionID
        let replacement = files.sources.appendingPathComponent("rows.bam")
        await session.openBAM(replacement)
        await session.chooseIndex(replacement.appendingPathExtension("bai"))
        #expect(session.presentation.sessionID != oldSession)
        session.editInterval("tiny:151-154")
        let newFileLoad = session.submitInterval()
        #expect(newFileLoad != nil, "Coverage from another BAM must not be reused")
        #expect(session.presentation.alignments.isEmpty)
        await newFileLoad?.value
        #expect(session.presentation.alignments.count == 80)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["identical"])
    }

    @Test(arguments: [false, true])
    @MainActor
    func aReadyReusedTargetSupersedesOlderPartialSuccessOrFailure(failLate: Bool) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 450 {
                await gate.pause(200)
                if failLate { throw RegionalLoadError(interval: target, message: "Late missing-region failure") }
            }
            return records
        })
        try await files.openedSession(fixture: "navigation", indexFormat: "bai", session: session)
        session.editInterval("tiny:100-120")
        await session.submitInterval()?.value
        session.editInterval("tiny:115-200")
        let old = session.submitInterval()
        await gate.waitFor(200)
        #expect(session.presentation.isLoading)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["lead", "anchor", "new_tail"])
        session.editInterval("tiny:100-110")
        #expect(session.submitInterval() == nil)
        let accepted = session.presentation.alignments
        #expect(!session.presentation.isLoading)
        session.editInterval("newer draft")
        await gate.release(200)
        await old?.value
        #expect(session.presentation.target?.formatted == "tiny:100-110")
        #expect(session.presentation.alignments == accepted)
        #expect(session.presentation.intervalText == "newer draft")
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.regionalError == nil)
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func revisitingEvictedDataReconstructsTheCompleteDistinctRecordSet(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = ViewerSession(prefetch: .init(maximumBytes: 1024))
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        for start in stride(from: 2000, through: 19000, by: 500) {
            session.editInterval("tiny:\(start)-\(start + 99)")
            await session.submitInterval()?.value
            #expect(session.presentation.alignments.isEmpty)
            #expect(!session.presentation.isLoading)
        }
        session.editInterval("tiny:100-300")
        let reloaded = session.submitInterval()
        #expect(reloaded != nil, "This sustained traversal exceeds the bounded historical cache")
        await reloaded?.value
        #expect(Set(session.presentation.alignments.map(\.id)) == Set(original.map(\.id)))
        #expect(session.presentation.alignments.count == 80)
        #expect(session.presentation.alignments.allSatisfy { record in
            original.contains { $0.id == record.id && $0.segments == record.segments }
        })
        #expect(session.presentation.verticalOffset == 0)
        #expect(session.presentation.regionalError == nil)
    }

    @Test
    @MainActor
    func partialFailuresNeverReplaceTheSavedViewOrForceARecoveryQuery() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            if target.end > 550 {
                await gate.pause(target.end - 250)
                throw RegionalLoadError(interval: target, message: "Controlled missing-region failure")
            }
            return try await file.alignments(in: target)
        })
        try await files.openedSession(fixture: "rows", indexFormat: "bai", session: session)
        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        let saved = session.presentation.alignments
        for attempt in 0..<12 {
            let end = Int64(400 + attempt)
            let targetText = "tiny:\(50 - attempt)-\(end)"
            session.scrollVertically(to: 200)
            session.editInterval(targetText)
            let work = session.submitInterval()
            #expect(session.presentation.alignments == saved)
            #expect(session.presentation.isLoading)
            await gate.waitFor(end)
            #expect(session.presentation.alignments == saved)
            session.editInterval("newer invalid draft")
            session.submitInterval()
            await gate.release(end)
            await work?.value
            #expect(session.presentation.target?.formatted == "tiny:100-300")
            #expect(session.presentation.alignments == saved)
            #expect(session.presentation.verticalOffset == 0)
            #expect(session.presentation.intervalText == "newer invalid draft")
            #expect(session.presentation.intervalError != nil)
            #expect(session.presentation.regionalError?.interval.formatted == targetText)
            #expect(!session.presentation.isLoading)
        }
        session.editInterval("tiny:110-200")
        let recovery = session.submitInterval()
        #expect(recovery == nil, "The restored successful data remains adequate after failed navigation")
        #expect(session.presentation.alignments == saved)
        #expect(!session.presentation.isLoading)
        await recovery?.value
    }

    @Test
    @MainActor
    func disjointReferenceAndWideTransitionsStartFreshWithoutDiscardingAdequateData() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 405 { await gate.pause(155) }
            return records
        })
        try await files.openedSession(fixture: "navigation", indexFormat: "bai", session: session)
        let sessionID = session.presentation.sessionID
        session.editInterval("tiny:100-120")
        await session.submitInterval()?.value
        let anchor = try #require(session.presentation.alignments.first { $0.name == "anchor" })
        #expect(anchor.row > 0)
        session.scrollVertically(to: 30)
        session.editInterval("tiny:145-155")
        let pending = session.submitInterval()
        #expect(Set(session.presentation.alignments.map(\.name)) == ["anchor", "new_tail"])
        #expect(session.presentation.alignments.first { $0.name == "new_tail" }?.row == 0, "Disjoint targets freshly pack full drawn extents")
        #expect(session.presentation.verticalOffset == 0)
        await gate.waitFor(155)
        session.scrollVertically(to: 15)
        await gate.release(155)
        await pending?.value
        #expect(session.presentation.alignments.first { $0.name == "anchor" }?.row == 1)
        #expect(session.presentation.verticalOffset == 15)

        session.editInterval("other_reference:101-120")
        let referenceChange = session.submitInterval()
        #expect(session.presentation.alignments.isEmpty)
        #expect(session.presentation.verticalOffset == 0)
        await referenceChange?.value
        #expect(session.presentation.alignments.map(\.name) == ["other"])
        session.scrollVertically(to: 15)
        session.editInterval("tiny:145-155")
        #expect(session.submitInterval() == nil)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["anchor", "new_tail"])
        #expect(session.presentation.verticalOffset == 0)

        session.editInterval("tiny:1-12000")
        #expect(session.submitInterval() == nil)
        #expect(session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.alignments.isEmpty)
        session.editInterval("tiny:145-155")
        #expect(session.submitInterval() == nil)
        #expect(!session.presentation.isLoading)
        #expect(!session.presentation.isAlignmentSuppressed)
        #expect(session.presentation.verticalOffset == 0)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["anchor", "new_tail"])
        #expect(session.presentation.sessionID == sessionID)
    }

    @Test
    @MainActor
    func retainedRowsSurviveNewEarlierTailsVacanciesAndWidthChanges() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "navigation")
        session.editInterval("tiny:100-120")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        #expect(Set(original.map(\.name)) == ["lead", "anchor", "new_tail"])
        session.scrollVertically(to: 20)

        session.editInterval("tiny:115-270")
        let pending = session.submitInterval()
        #expect(Set(session.presentation.alignments.map(\.name)) == ["lead", "anchor", "new_tail", "late"])
        await pending?.value
        let expanded = session.presentation.alignments
        #expect(Set(expanded.map(\.name)) == ["lead", "anchor", "new_tail", "late"])
        for record in original {
            #expect(expanded.first { $0.id == record.id }?.row == record.row)
        }
        let tail = try #require(expanded.first { $0.name == "new_tail" })
        #expect(original.first { $0.id == tail.id }?.row == tail.row, "The already visible full tail retains its row")
        #expect(session.presentation.verticalOffset == 20)
        let extent = session.presentation.rowCount

        session.editInterval("tiny:160-270")
        #expect(session.submitInterval() == nil)
        #expect(Set(session.presentation.alignments.map(\.name)) == ["anchor", "late"])
        for record in session.presentation.alignments {
            #expect(expanded.first { $0.id == record.id }?.row == record.row)
        }
        #expect(session.presentation.rowCount == extent, "Vacant rows must not shorten the scrollable stack")
        #expect(session.presentation.verticalOffset == 20)

        session.editInterval("tiny:100-300")
        await session.submitInterval()?.value
        let final = session.presentation.alignments
        for record in expanded where record.name == "anchor" || record.name == "late" {
            #expect(final.first { $0.id == record.id }?.row == record.row)
        }
        for row in Dictionary(grouping: final, by: \.row).values {
            let sorted = row.sorted { $0.drawnStart < $1.drawnStart }
            for pair in zip(sorted, sorted.dropFirst()) {
                #expect(pair.0.drawnEnd < pair.1.drawnStart)
            }
        }
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func partialCoverageKeepsAvailableRecordsAndScrollUntilMissingDataCompletes(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let gate = RegionGate()
        let session = ViewerSession(prefetch: .disabled, loadRegion: { file, target in
            let records = try await file.alignments(in: target)
            if target.end == 430 { await gate.pause(180) }
            return records
        })
        try await files.openedSession(fixture: "rows", indexFormat: indexFormat, session: session)
        session.editInterval("tiny:100-150")
        await session.submitInterval()?.value
        let original = session.presentation.alignments
        session.scrollVertically(to: 400)
        session.editInterval("tiny:140-180")
        let pending = session.submitInterval()
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.verticalOffset == 400)
        #expect(session.presentation.isLoading, "Alignments reaching 250 do not establish coverage through 180")
        #expect(session.presentation.target?.formatted == "tiny:140-180")
        await gate.waitFor(180)
        session.scrollVertically(to: 200)
        session.editInterval("tiny:0140-0180")
        let repeated = session.submitInterval()
        #expect(await gate.count(180) == 1)
        await gate.release(180)
        await pending?.value
        await repeated?.value
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.alignments.count == 80)
        #expect(session.presentation.verticalOffset == 200)
        #expect(!session.presentation.isLoading)

        session.editInterval("tiny:110-175")
        let combined = session.submitInterval()
        #expect(combined == nil, "Union of completed queries covers this target")
        #expect(!session.presentation.isLoading)
        #expect(session.presentation.alignments == original)
        #expect(session.presentation.verticalOffset == 200)
        await combined?.value
    }

    @Test(arguments: ["bai", "csi"])
    @MainActor
    func completedCoverageImmediatelyServesEligibleAndEmptyTargets(indexFormat: String) async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let session = try await files.openedSession(fixture: "alignments", indexFormat: indexFormat)
        session.editInterval("tiny:90-2200")
        await session.submitInterval()?.value
        let originals = session.presentation.alignments
        var showedLoading = false
        session.onPresentationChange = { showedLoading = showedLoading || session.presentation.isLoading }

        for (text, expected) in [
            ("tiny:95-100", Set(["forward", "reverse"])),
            ("tiny:100-105", Set(["forward", "reverse", "supplementary"])),
            ("tiny:2050-2060", Set(["skip"])),
            ("tiny:1500-1510", Set<String>()),
        ] {
            session.editInterval(text)
            let work = session.submitInterval()
            #expect(work == nil, "Completed coverage must be ready synchronously")
            #expect(!session.presentation.isLoading)
            #expect(!showedLoading, "A ready target must not briefly publish a spinner")
            #expect(Set(session.presentation.alignments.map(\.name)) == expected)
            #expect(session.presentation.message.isEmpty)
            #expect(session.presentation.alignments.allSatisfy { record in
                originals.contains { $0.id == record.id && $0.segments == record.segments }
            })
            await work?.value
        }
    }
}
