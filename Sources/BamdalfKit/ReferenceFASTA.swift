import CryptoKit
import Darwin
import Foundation

extension ReferenceBundle {
    /// Creates a fully validated bundle at a fresh destination. Progress reports consumed and total FASTA bytes.
    public static func create(from source: URL, at destination: URL, creator: String,
                              progress: @Sendable (Int64, Int64) throws -> Void = { _, _ in }) throws {
        try ReferenceFormat.checkURL(destination)
        guard source.isFileURL else { throw ReferenceBundleError("Choose a local uncompressed FASTA file.") }
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".bamdalf-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: staging) }
        let candidate = staging.appendingPathComponent("reference.bref")
        try writeBundle(fromFASTA: source, to: candidate, creator: creator, progress: progress)
        _ = try ReferenceBundle(opening: candidate)
        try Task.checkCancellation()
        guard renamex_np(candidate.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

private func writeBundle(fromFASTA source: URL, to candidate: URL, creator: String,
                        progress: (Int64, Int64) throws -> Void) throws {
    guard !creator.isEmpty, creator.utf8.count <= ReferenceFormat.fieldBytes,
          source.lastPathComponent.utf8.count <= ReferenceFormat.fieldBytes else {
        throw ReferenceBundleError("Invalid or oversized FASTA provenance metadata.")
    }
    let file = try FileHandle(forReadingFrom: source)
    defer { try? file.close() }
    let total = try file.seekToEnd()
    guard total <= Int64.max else { throw ReferenceBundleError("FASTA exceeds the supported size.") }
    try file.seek(toOffset: 0)
    let db = try ReferenceDatabase(candidate, creating: true)
    try db.execute("""
        PRAGMA journal_mode=DELETE;
        PRAGMA synchronous=FULL;
        BEGIN;
        PRAGMA application_id=0x42524546;
        PRAGMA user_version=1;
        CREATE TABLE metadata (id INTEGER PRIMARY KEY, source_name TEXT NOT NULL, creator TEXT NOT NULL,
            created_utc TEXT NOT NULL, chunk_bytes INTEGER NOT NULL);
        CREATE TABLE contigs (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE BINARY,
            length INTEGER NOT NULL, m5 TEXT NOT NULL, first_chunk INTEGER NOT NULL);
        CREATE TABLE chunks (id INTEGER PRIMARY KEY, bases BLOB NOT NULL);
        """)
    let metadata = try db.statement("INSERT INTO metadata VALUES (1, ?, ?, ?, ?)")
    try metadata.bind(source.lastPathComponent, at: 1)
    try metadata.bind(creator, at: 2)
    try metadata.bind(ISO8601DateFormatter().string(from: Date()), at: 3)
    try metadata.bind(Int64(ReferenceFormat.chunkBytes), at: 4)
    try metadata.insert()
    let writer = try FASTARecords(db)
    try writer.importRecords(from: file, totalBytes: Int64(total), progress: progress)
    try db.execute("COMMIT")
}

private final class FASTARecords {
    private let chunks: ReferenceStatement
    private let contigs: ReferenceStatement
    private var name: String?
    private var names = Set<Data>()
    private var totalNameBytes = 0
    private var firstChunk: Int64 = 1
    private var nextChunk: Int64 = 1
    private var length: Int64 = 0
    private var digest = Insecure.MD5()

    init(_ db: ReferenceDatabase) throws {
        chunks = try db.statement("INSERT INTO chunks VALUES (?, ?)")
        contigs = try db.statement("INSERT INTO contigs VALUES (?, ?, ?, ?, ?)")
    }

    func importRecords(from file: FileHandle, totalBytes: Int64, progress: (Int64, Int64) throws -> Void) throws {
        var sequence: [UInt8] = []
        sequence.reserveCapacity(ReferenceFormat.chunkBytes)
        var header: [UInt8] = []
        var inHeader = false
        var endedName = false
        var lineStart = true
        var carriageReturn = false
        var consumed: Int64 = 0
        try progress(0, totalBytes)
        // Foundation's file reads can retain autoreleased blocks up to the caller's
        // next event-loop turn, including the entire input on a background task.
        while let block = try autoreleasepool(invoking: { try file.read(upToCount: 1 << 20) }), !block.isEmpty {
            try Task.checkCancellation()
            try block.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                for byte in bytes {
                    if byte == 10 {
                        if inHeader { try begin(header); inHeader = false }
                        carriageReturn = false
                        lineStart = true
                    } else if carriageReturn {
                        throw ReferenceBundleError("Expected LF after CR in FASTA.")
                    } else if byte == 13 {
                        carriageReturn = true
                    } else if inHeader {
                        if byte == 32 || (9...12).contains(byte) {
                            if !header.isEmpty { endedName = true }
                        } else if !endedName {
                            guard header.count < ReferenceFormat.fieldBytes else {
                                throw ReferenceBundleError("Oversized FASTA name.")
                            }
                            header.append(byte)
                        }
                    } else if lineStart && byte == 62 {
                        try finish(&sequence)
                        inHeader = true
                        endedName = false
                        header.removeAll(keepingCapacity: true)
                        lineStart = false
                    } else {
                        guard name != nil else { throw ReferenceBundleError("Sequence before first FASTA header.") }
                        sequence.append(byte)
                        if sequence.count == ReferenceFormat.chunkBytes { try writeChunk(&sequence) }
                        lineStart = false
                    }
                }
            }
            guard Int64(block.count) <= totalBytes - consumed else { throw ReferenceBundleError("FASTA size changed during creation.") }
            consumed += Int64(block.count)
            try progress(consumed, totalBytes)
        }
        guard consumed == totalBytes else { throw ReferenceBundleError("FASTA size changed during creation.") }
        guard !carriageReturn else { throw ReferenceBundleError("Expected LF after CR in FASTA.") }
        if inHeader { try begin(header) }
        guard name != nil else { throw ReferenceBundleError("No FASTA records.") }
        try finish(&sequence)
    }

    private func begin(_ header: [UInt8]) throws {
        guard !header.isEmpty, let name = String(bytes: header, encoding: .utf8) else {
            throw ReferenceBundleError("Missing or invalid FASTA name.")
        }
        guard names.count < ReferenceFormat.maxContigs, totalNameBytes + header.count <= ReferenceFormat.dictionaryBytes else {
            throw ReferenceBundleError("FASTA contig dictionary exceeds format bounds.")
        }
        guard names.insert(Data(header)).inserted else { throw ReferenceBundleError("Duplicate FASTA name ‘\(name)’.") }
        self.name = name
        totalNameBytes += header.count
        firstChunk = nextChunk
        length = 0
        digest = Insecure.MD5()
    }

    private func writeChunk(_ sequence: inout [UInt8]) throws {
        if let invalid = sequence.firstIndex(where: { !ReferenceFormat.alphabet[Int($0)] }) {
            let byte = sequence[invalid]
            let symbol = (32...126).contains(byte) ? "‘\(Character(UnicodeScalar(byte)))’" : String(format: "0x%02X", byte)
            throw ReferenceBundleError("Invalid FASTA base \(symbol) in \(name!) at base \(length + Int64(invalid) + 1).")
        }
        let uppercase = sequence.map { $0 & 0xDF }
        uppercase.withUnsafeBytes { digest.update(bufferPointer: $0) }
        try chunks.bind(nextChunk, at: 1)
        try chunks.bind(sequence, at: 2)
        try chunks.insert()
        nextChunk += 1
        length += Int64(sequence.count)
        sequence.removeAll(keepingCapacity: true)
    }

    private func finish(_ sequence: inout [UInt8]) throws {
        guard let name else { return }
        if !sequence.isEmpty { try writeChunk(&sequence) }
        guard length > 0 else { throw ReferenceBundleError("Empty FASTA sequence for \(name).") }
        try contigs.bind(Int64(names.count), at: 1)
        try contigs.bind(name, at: 2)
        try contigs.bind(length, at: 3)
        try contigs.bind(digest.finalize().map { String(format: "%02x", $0) }.joined(), at: 4)
        try contigs.bind(firstChunk, at: 5)
        try contigs.insert()
    }
}
