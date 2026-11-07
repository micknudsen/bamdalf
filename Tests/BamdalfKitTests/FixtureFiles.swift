import Foundation
import Testing
import BamdalfKit

struct FixtureFiles {
    let directory: URL
    let sources: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sources = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    @MainActor
    @discardableResult
    func openedSession(fixture: String = "opening", indexFormat: String = "bai", session: ViewerSession? = nil) async throws -> ViewerSession {
        let session = session ?? ViewerSession()
        let bam = sources.appendingPathComponent("\(fixture).bam")
        let index = bam.appendingPathExtension(indexFormat)
        await session.openBAM(bam)
        await session.chooseIndex(index)
        try #require(session.presentation.bamURL == bam)
        try #require(session.presentation.indexURL == index)
        return session
    }
}
