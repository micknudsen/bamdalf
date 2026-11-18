import Foundation
import Testing
import BamdalfKit

struct ReferenceBundleTests {
    @Test func portableCasePreservingBundle() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let source = files.directory.appendingPathComponent("source.fna")
        let destination = files.directory.appendingPathComponent("portable.bref")
        try Data(">chrA wrapped\r\naCgTRY\r\nswkMbdhVN\r\n>chrB\nT".utf8).write(to: source)
        try ReferenceBundle.create(from: source, at: destination, creator: "bamdalf/test")
        try FileManager.default.removeItem(at: source)
        let bundle = try ReferenceBundle(opening: destination)
        #expect(bundle.contigs.map(\.name) == ["chrA", "chrB"])
        #expect(bundle.contigs.map(\.length) == [15, 1])
        #expect(bundle.contigs.map(\.m5) == ["a00785ce69d2eaeb6da9a59cc69e47f1", "b9ece18c950afbfa6b0fdbfa4ff731d3"])
        #expect(bundle.provenance.sourceName == "source.fna")
        #expect(bundle.provenance.creator == "bamdalf/test")
        let bases = try await bundle.read(GenomicInterval(reference: "chrA", start: 1, end: 15))
        #expect(String(decoding: bases, as: UTF8.self) == "aCgTRYswkMbdhVN")
        let last = try await bundle.read(GenomicInterval(reference: "chrB", start: 1, end: 1))
        #expect(last == Data("T".utf8))
    }
}

extension ReferenceBundleTests {
    @Test(arguments: [
        ("PRAGMA user_version=2", "version"),
        ("PRAGMA application_id=123", "identity"),
        ("UPDATE metadata SET chunk_bytes=32768", "metadata"),
        ("UPDATE metadata SET source_name='../source.fa'", "metadata"),
        ("UPDATE metadata SET source_name='a/' || char(769) || 'b'", "metadata"),
        ("UPDATE metadata SET source_name='a' || char(0) || 'b'", "metadata"),
        ("UPDATE metadata SET created_utc='yesterday'", "metadata"),
        ("UPDATE metadata SET created_utc='2026-02-31T00:00:00Z'", "metadata"),
        ("UPDATE metadata SET created_utc='2026-01-01T00:00:00ZgarbageZ'", "metadata"),
        ("UPDATE metadata SET creator=zeroblob(6000)", "text"),
        ("UPDATE metadata SET creator=hex(zeroblob(2049))", "text"),
        ("UPDATE contigs SET m5=upper(m5)", "digest"),
        ("UPDATE contigs SET length=3.5", "integer"),
        ("UPDATE contigs SET first_chunk=9223372036854775807", "range"),
        ("DELETE FROM chunks", "index"),
        ("ALTER TABLE chunks RENAME TO other; CREATE VIEW chunks AS SELECT * FROM other", "schema"),
        ("ALTER TABLE chunks RENAME TO other; CREATE TABLE chunks(id INTEGER PRIMARY KEY, bases TEXT NOT NULL)", "schema"),
        ("ALTER TABLE chunks RENAME TO other; CREATE TABLE chunks(id INTEGER PRIMARY KEY DESC, bases BLOB NOT NULL)", "schema")
    ])
    func openingValidatesDocumentedStructure(mutation: (String, String)) throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let file = try makeBundle(in: files.directory)
        try changeFixture(file, sql: mutation.0)
        expectFailure(containing: mutation.1) { _ = try ReferenceBundle(opening: file) }
    }
}

private func makeBundle(in directory: URL, fasta: String = ">one\nATgC") throws -> URL {
    let source = directory.appendingPathComponent("example.fa")
    try Data(fasta.utf8).write(to: source)
    let file = directory.appendingPathComponent("example.bref")
    try ReferenceBundle.create(from: source, at: file, creator: "bamdalf/test")
    return file
}

private func expectFailure(containing message: String, _ operation: () throws -> Void) {
    do {
        try operation()
        Issue.record("Expected failure containing ‘\(message)’")
    } catch {
        #expect(error.localizedDescription.localizedCaseInsensitiveContains(message))
    }
}

private func changeFixture(_ url: URL, sql: String) throws {
    // Edit a documented v1 file outside the production module, as an external writer could.
    let sqlite = Process()
    sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    sqlite.arguments = [url.path, sql]
    try sqlite.run()
    sqlite.waitUntilExit()
    try #require(sqlite.terminationStatus == 0)
}

extension ReferenceBundleTests {
    @Test(arguments: [
        (">one\nAC\n>one duplicate\nG", "Duplicate FASTA name ‘one’"),
        (">   \r\nA", "FASTA name"), (">x\n>y\nA", "Empty FASTA sequence for x"),
        (">x\naN?", "‘?’ in x at base 3"), (">x\nAC GT", "in x at base 3"),
        ("AT\n>x\nG", "before first"), ("", "No FASTA records"),
        (">" + String(repeating: "x", count: 4097) + "\nA", "Oversized FASTA name")
    ])
    func failedImportIdentifiesTheProblemAndPublishesNothing(example: (String, String)) throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        expectFailure(containing: example.1) { _ = try makeBundle(in: files.directory, fasta: example.0) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["example.fa"])
    }
}

extension ReferenceBundleTests {
    @Test func boundedReadsValidateOnlyRequestedChunksAndReturnNoPartialSequence() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let file = try makeBundle(in: files.directory,
                                  fasta: ">edge\n" + String(repeating: "A", count: 65534) + "tR\nysG"
                                    + String(repeating: "C", count: 65533) + "N\n>next\nn")
        let cross = GenomicInterval(reference: "edge", start: 65534, end: 65539)
        let single = GenomicInterval(reference: "edge", start: 131073, end: 131073)
        do {
            let intact = try ReferenceBundle(opening: file)
            #expect(try await intact.read(cross) == Data("AtRysG".utf8))
            #expect(try await intact.read(single) == Data("N".utf8))
            for endpoints: (Int64, Int64) in [(0, 1), (-1, 2), (2, 1), (131073, 131074), (1, .max)] {
                await #expect(throws: (any Error).self) {
                    try await intact.read(GenomicInterval(reference: "edge", start: endpoints.0, end: endpoints.1))
                }
            }
        }
        for mutation in ["UPDATE chunks SET bases=zeroblob(65536) WHERE id=2",
                         "UPDATE chunks SET bases='A' WHERE id=2", "UPDATE chunks SET bases=x'41' WHERE id=2",
                         "DELETE FROM chunks WHERE id=2"] {
            try changeFixture(file, sql: mutation)
            let bundle = try ReferenceBundle(opening: file)
            #expect(try await bundle.read(single) == Data("N".utf8))
            await #expect(throws: (any Error).self) { try await bundle.read(cross) }
        }
    }

    @Test func relocatedBundleIsUsableInAReadOnlyDirectoryWithoutSidecars() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let fasta = ">ACG\r\nACGTRYSWKMBDHVN\r\nacgtryswkmbdhvn\n"
        let original = try makeBundle(in: files.directory, fasta: fasta)
        try FileManager.default.removeItem(at: files.directory.appendingPathComponent("example.fa"))
        let folder = files.directory.appendingPathComponent("read only")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let moved = folder.appendingPathComponent("a #?.bref")
        try FileManager.default.moveItem(at: original, to: moved)
        let snapshot = try Data(contentsOf: moved)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: moved.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let bundle = try ReferenceBundle(opening: moved)
        #expect(bundle.contigs[0].m5 == "bbecac2bf7f252c05b5bc85337c9bf70")
        #expect(try await bundle.read(GenomicInterval(reference: "ACG", start: 1, end: 30))
                == Data("ACGTRYSWKMBDHVNacgtryswkmbdhvn".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a #?.bref"])
        #expect(try Data(contentsOf: moved) == snapshot)
    }

    @Test func namesUseExactUTF8BytesAcrossInputBufferBoundaries() async throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let fasta = ">" + String(repeating: " ", count: 1_048_573) + "é description\r\nA\n>e\u{301}\nT\n>\u{feff}a\nG\n>a\nC"
        let file = try makeBundle(in: files.directory, fasta: fasta)
        let bundle = try ReferenceBundle(opening: file)
        #expect(bundle.contigs.map { Array($0.name.utf8) } == [[0xc3, 0xa9], [0x65, 0xcc, 0x81], [0xef, 0xbb, 0xbf, 0x61], [0x61]])
        #expect(try await bundle.read(GenomicInterval(reference: "é", start: 1, end: 1)) == Data("A".utf8))
        #expect(try await bundle.read(GenomicInterval(reference: "e\u{301}", start: 1, end: 1)) == Data("T".utf8))
        #expect(try await bundle.read(GenomicInterval(reference: "\u{feff}a", start: 1, end: 1)) == Data("G".utf8))
        #expect(try await bundle.read(GenomicInterval(reference: "a", start: 1, end: 1)) == Data("C".utf8))
        await #expect(throws: (any Error).self) { try await bundle.read(GenomicInterval(reference: "É", start: 1, end: 1)) }
    }

    @Test func invalidSuffixWALAndTruncatedFilesFailToOpen() throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let file = try makeBundle(in: files.directory, fasta: ">chr\n" + String(repeating: "A", count: 70000))
        let badSuffix = file.deletingPathExtension().appendingPathExtension("fna")
        try FileManager.default.copyItem(at: file, to: badSuffix)
        expectFailure(containing: ".bref") { _ = try ReferenceBundle(opening: badSuffix) }
        expectFailure(containing: ".bref") { try ReferenceBundle.create(from: badSuffix, at: badSuffix, creator: "bamdalf/test") }
        let wal = files.directory.appendingPathComponent("wal.bref")
        try FileManager.default.copyItem(at: file, to: wal)
        try changeFixture(wal, sql: "PRAGMA journal_mode=WAL")
        expectFailure(containing: "rollback") { _ = try ReferenceBundle(opening: wal) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 7000)
        try handle.close()
        #expect(throws: (any Error).self) { try ReferenceBundle(opening: file) }
    }

    @Test func cancellationAndPublicationFailuresPreserveTheDestination() throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let url = try makeBundle(in: files.directory)
        let before = try Data(contentsOf: url)
        let source = files.directory.appendingPathComponent("example.fa")
        #expect(throws: CancellationError.self) {
            try ReferenceBundle.create(from: source, at: url, creator: "bamdalf/test") { read, _ in
                if read > 0 { throw CancellationError() }
            }
        }
        #expect(throws: (any Error).self) {
            try ReferenceBundle.create(from: source, at: url, creator: "bamdalf/test")
        }
        #expect(try Data(contentsOf: url) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path).sorted() == ["example.bref", "example.fa"])
    }
}

extension ReferenceBundleTests {
    @Test func aShortenedInputIsNeverPublishedAsACompleteReference() throws {
        let files = try FixtureFiles()
        defer { files.remove() }
        let source = files.directory.appendingPathComponent("changing.fa")
        try Data((">x\n" + String(repeating: "A", count: 2_000_000)).utf8).write(to: source)
        let url = files.directory.appendingPathComponent("changed.bref")
        expectFailure(containing: "size changed") {
            try ReferenceBundle.create(from: source, at: url, creator: "bamdalf/test") { read, total in
                if read > 0 && read < total {
                    let writer = try FileHandle(forWritingTo: source)
                    try writer.truncate(atOffset: UInt64(read))
                    try writer.close()
                }
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: files.directory.path) == ["changing.fa"])
    }
}
