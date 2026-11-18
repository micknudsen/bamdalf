import Foundation

public struct ReferenceContig: Sendable {
    public let name: String
    public let length: Int64
    public let m5: String
}

public struct ReferenceProvenance: Sendable {
    public let sourceName: String
    public let creator: String
    public let createdUTC: String
}

/// A read-only v1 reference with exact, byte-sensitive names and 1-based inclusive intervals.
public actor ReferenceBundle {
    public nonisolated let url: URL
    public nonisolated let provenance: ReferenceProvenance
    public nonisolated let contigs: [ReferenceContig]
    nonisolated let fileIdentity: ReferenceFileIdentity
    private let db: ReferenceDatabase
    // Swift String equality normalizes Unicode. The bundle dictionary uses UTF-8 byte identity.
    private let index: [Data: (length: Int64, firstChunk: Int64)]

    public init(opening url: URL) throws {
        try ReferenceFormat.checkURL(url)
        guard let identity = try ReferenceFileIdentity.at(url) else { throw POSIXError(.ENOENT) }
        try ReferenceFormat.checkHeader(url)
        let db = try ReferenceDatabase(url)
        try db.execute("BEGIN")
        try ReferenceFormat.checkSchema(db)
        provenance = try ReferenceFormat.provenance(db)
        let dictionary = try db.statement("""
            SELECT id, CASE WHEN length(CAST(name AS BLOB)) <= \(ReferenceFormat.fieldBytes) THEN name END, length,
                CASE WHEN length(CAST(m5 AS BLOB)) = 32 THEN m5 END, first_chunk
            FROM contigs ORDER BY id LIMIT \(ReferenceFormat.maxContigs + 1)
            """)
        var contigs: [ReferenceContig] = []
        var index: [Data: (length: Int64, firstChunk: Int64)] = [:]
        var nameBytes = 0
        var lastChunk: Int64 = 0
        while try dictionary.next() {
            guard contigs.count < ReferenceFormat.maxContigs, try dictionary.integer(0) == contigs.count + 1 else {
                throw ReferenceBundleError("Invalid contig dictionary count or order.")
            }
            let contig = try ReferenceContig(name: dictionary.text(1), length: dictionary.integer(2), m5: dictionary.text(3, limit: 32))
            let key = Data(contig.name.utf8)
            nameBytes += key.count
            guard nameBytes <= ReferenceFormat.dictionaryBytes, index[key] == nil else {
                throw ReferenceBundleError("Oversized dictionary or duplicate contig name.")
            }
            guard contig.m5.utf8.count == 32, contig.m5.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ReferenceBundleError("Invalid sequence digest for \(contig.name).")
            }
            let first = try dictionary.integer(4)
            guard contig.length > 0, lastChunk < Int64.max, first == lastChunk + 1 else {
                throw ReferenceBundleError("Invalid chunk range for \(contig.name).")
            }
            let (last, overflow) = first.addingReportingOverflow((contig.length - 1) / Int64(ReferenceFormat.chunkBytes))
            guard !overflow else { throw ReferenceBundleError("Contig chunk range exceeds format bounds.") }
            lastChunk = last
            contigs.append(contig)
            index[key] = (contig.length, first)
        }
        // Separate indexed extrema leave interior chunks untouched until a regional read.
        guard !contigs.isEmpty, try db.scalarInteger("SELECT min(id) FROM chunks") == 1,
              try db.scalarInteger("SELECT max(id) FROM chunks") == lastChunk else {
            throw ReferenceBundleError("Invalid reference payload index bounds.")
        }
        guard try ReferenceFileIdentity.at(url) == identity else {
            throw ReferenceBundleError("The reference file changed while opening. Choose it again.")
        }
        self.fileIdentity = identity
        self.url = url
        self.contigs = contigs
        self.index = index
        self.db = db
    }

    public func read(_ interval: GenomicInterval) throws -> Data {
        guard let record = index[Data(interval.reference.utf8)] else {
            throw ReferenceBundleError("Unknown reference contig \(interval.reference).")
        }
        guard interval.start > 0, interval.start <= interval.end, interval.end <= record.length else {
            throw ReferenceBundleError("Interval outside the bounds of \(interval.reference).")
        }
        let size = Int64(ReferenceFormat.chunkBytes)
        let start = interval.start - 1
        let first = record.firstChunk + start / size
        let last = record.firstChunk + (interval.end - 1) / size
        let rows = try db.statement("""
            SELECT id, CASE WHEN typeof(bases) = 'blob' AND length(bases) <= \(ReferenceFormat.chunkBytes) THEN bases END
            FROM chunks WHERE id BETWEEN ? AND ? ORDER BY id
            """)
        try rows.bind(first, at: 1)
        try rows.bind(last, at: 2)
        var bases = Data()
        for id in first...last {
            try Task.checkCancellation()
            guard try rows.next(), try rows.integer(0) == id else {
                throw ReferenceBundleError("Incomplete reference sequence for \(interval.reference).")
            }
            let offset = (id - record.firstChunk) * size
            let count = Int(min(size, record.length - offset))
            try rows.withBases(1, count: count) { chunk in
                guard chunk.allSatisfy({ ReferenceFormat.alphabet[Int($0)] }) else {
                    throw ReferenceBundleError("Invalid sequence character in bundle contig \(interval.reference).")
                }
                let lower = Int(max(0, start - offset))
                let upper = Int(min(Int64(count), interval.end - offset))
                bases.append(chunk.baseAddress! + lower, count: upper - lower)
            }
        }
        return bases
    }
}
