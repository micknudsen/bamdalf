import Foundation
import Testing
import BamdalfKit

struct OpenBAMTests {
    @Test(arguments: [false, true])
    @MainActor
    func malformedOrMissingBAMReportsTheReaderFailureWithoutOpeningIt(missing: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bam = directory.appendingPathComponent("invalid.bam")
        if !missing { try Data("not a BAM file".utf8).write(to: bam) }
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam.bai"),
                                        to: bam.appendingPathExtension("bai"))
        let session = ViewerSession()

        await session.openBAM(bam)

        #expect(session.presentation.bamURL == nil)
        #expect(session.presentation.openError?.fileURL == bam)
        #expect(session.presentation.openError?.message.contains(missing ? "No such file" : "not in BAM format") == true)
        #expect(session.presentation.message == "No BAM file open")
    }

    @Test
    @MainActor
    func failedOrCanceledReplacementPreservesTheBAMAndEditableDraftWithoutIndexFallback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let original = directory.appendingPathComponent("original.bam")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam"), to: original)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam.bai"),
                                        to: original.appendingPathExtension("bai"))
        let session = ViewerSession()
        await session.openBAM(original)
        session.editInterval("tiny:100-120")

        await session.openBAM(nil)
        #expect(session.presentation.bamURL == original)
        #expect(session.presentation.intervalText == "tiny:100-120")

        let replacement = directory.appendingPathComponent("replacement.bam")
        try FileManager.default.copyItem(at: original, to: replacement)
        let brokenIndex = replacement.appendingPathExtension("bai")
        try Data("broken index".utf8).write(to: brokenIndex)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam.csi"),
                                        to: replacement.appendingPathExtension("csi"))
        await session.openBAM(replacement)
        await session.chooseIndex(nil)
        #expect(session.presentation.bamURL == original)
        #expect(session.presentation.intervalText == "tiny:100-120")
        await session.openBAM(replacement)
        await session.chooseIndex(brokenIndex)

        #expect(session.presentation.openError?.fileURL == brokenIndex)
        #expect(session.presentation.openError?.message.contains("selected BAM index") == true)
        #expect(session.presentation.bamURL == original)
        #expect(session.presentation.intervalText == "tiny:100-120")
        #expect(session.presentation.indexURL == original.appendingPathExtension("bai"))
        session.dismissOpenError()
        #expect(session.presentation.openError == nil)

        await session.openBAM(replacement)
        await session.chooseIndex(replacement.appendingPathExtension("csi"))
        #expect(session.presentation.bamURL == replacement)
        #expect(session.presentation.intervalText == "")
        #expect(session.presentation.message == "Enter a genomic interval")
    }

    @Test(arguments: ["sample.bam.bai", "sample.bai", "sample.bam.csi", "sample.csi"])
    @MainActor
    func aSingleRealIndexOpensTheBAMWithItsHeaderReferences(indexName: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let bam = directory.appendingPathComponent("sample.bam")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam"), to: bam)
        let format = indexName.hasSuffix("bai") ? "bai" : "csi"
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("opening.bam.\(format)"),
                                        to: directory.appendingPathComponent(indexName))
        let session = ViewerSession()

        await session.openBAM(bam)

        #expect(session.presentation.openError == nil)
        #expect(session.presentation.indexChoice == nil)
        #expect(session.presentation.bamURL == bam)
        #expect(session.presentation.indexURL?.lastPathComponent == indexName)
        #expect(session.presentation.message == "Enter a genomic interval")
        #expect(session.presentation.references.map(\.name) == ["tiny", "other_reference"])
        #expect(session.presentation.references.map(\.length) == [2000, 800])
        #expect(session.presentation.intervalEntryAvailable)
    }

    @Test
    @MainActor
    func allFourIndexNamesRequireExplicitChoiceAndCancellationPreservesTheWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bam = directory.appendingPathComponent("sample.bam")
        let names = ["sample.bam.bai", "sample.bai", "sample.bam.csi", "sample.csi"]
        try Data().write(to: bam)
        for name in names { try Data().write(to: directory.appendingPathComponent(name)) }
        let session = ViewerSession()

        await session.openBAM(bam)

        #expect(Set(session.presentation.indexChoice?.candidates.map(\.lastPathComponent) ?? []) == Set(names))
        #expect(session.presentation.openError == nil)
        #expect(session.presentation.bamURL == nil)
        await session.chooseIndex(nil)
        #expect(session.presentation.indexChoice == nil)
        #expect(session.presentation.message == "No BAM file open")
    }

    @Test
    @MainActor
    func missingIndexReportsTheSelectedBAMWithoutReplacingTheWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bam = directory.appendingPathComponent("sample.bam")
        try Data().write(to: bam)
        let session = ViewerSession()

        await session.openBAM(bam)

        #expect(session.presentation.message == "No BAM file open")
        #expect(session.presentation.openError?.message.contains("No supported BAM index") == true)
        #expect(session.presentation.openError?.fileURL == bam)
        #expect(session.presentation.bamURL == nil)
    }
}
