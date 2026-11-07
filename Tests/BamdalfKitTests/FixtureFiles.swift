import Foundation
import Testing

struct FixtureFiles {
    let directory: URL
    let sources: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        sources = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
