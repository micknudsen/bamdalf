import Foundation

enum ReferenceFormat {
    static let chunkBytes = 65_536
    static let fieldBytes = 4096
    static let maxContigs = 100_000
    static let dictionaryBytes = 16 * 1024 * 1024
    static let alphabet: [Bool] = {
        var letters = Array(repeating: false, count: 256)
        for base in "ACGTRYSWKMBDHVNacgtryswkmbdhvn".utf8 { letters[Int(base)] = true }
        return letters
    }()

    static func checkURL(_ url: URL) throws {
        guard url.isFileURL, url.pathExtension == "bref" else {
            throw ReferenceBundleError("Choose a local file with the .bref suffix.")
        }
    }

    static func checkHeader(_ url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Reject WAL before opening with SQLite, which could otherwise require sidecars.
        guard let header = try file.read(upToCount: 20), header.count == 20,
              header.prefix(16).elementsEqual("SQLite format 3\0".utf8), header[18] == 1, header[19] == 1 else {
            throw ReferenceBundleError("Expected a complete rollback-journal reference database header.")
        }
    }

    static func checkSchema(_ db: ReferenceDatabase) throws {
        guard try db.scalarInteger("PRAGMA application_id") == 0x42524546 else {
            throw ReferenceBundleError("Unrecognized reference bundle identity.")
        }
        guard try db.scalarInteger("PRAGMA user_version") == 2 else {
            throw ReferenceBundleError("Unsupported reference bundle version. Regenerate the bundle from its FASTA.")
        }
        let encoding = try db.statement("PRAGMA encoding")
        guard try encoding.next(), try encoding.text(0) == "UTF-8" else {
            throw ReferenceBundleError("Unsupported reference database encoding.")
        }
        try checkTable(db, name: "metadata", fields: [("source_name", "TEXT"), ("creator", "TEXT"),
                                                      ("created_utc", "TEXT"), ("chunk_bytes", "INTEGER"),
                                                      ("bundle_name", "TEXT")])
        try checkTable(db, name: "contigs", fields: [("name", "TEXT"), ("length", "INTEGER"),
                                                     ("m5", "TEXT"), ("first_chunk", "INTEGER")])
        try checkTable(db, name: "chunks", fields: [("bases", "BLOB")])
        // v2 requires a full unique binary key on name, not a partial or compound index.
        let uniqueNames = try db.scalarInteger("""
            SELECT 1 FROM pragma_index_list('contigs') AS i
            WHERE i.[unique] = 1 AND i.partial = 0
              AND (SELECT count(*) FROM pragma_index_xinfo(i.name) WHERE key = 1) = 1
              AND EXISTS (SELECT 1 FROM pragma_index_xinfo(i.name) WHERE key = 1 AND name = 'name' AND coll = 'BINARY')
            LIMIT 1
            """)
        guard uniqueNames == 1 else { throw ReferenceBundleError("Invalid contig name index in reference schema.") }
    }

    private static func checkTable(_ db: ReferenceDatabase, name: String, fields: [(String, String)]) throws {
        // These table names are fixed format constants. A separate PK index means id is not the rowid alias.
        let ordinary = try db.scalarInteger("""
            SELECT 1 FROM pragma_table_list('\(name)')
            WHERE schema='main' AND type='table' AND wr=0 AND ncol=\(fields.count + 1)
              AND NOT EXISTS (SELECT 1 FROM pragma_index_list('\(name)') WHERE origin='pk')
            """)
        let error = ReferenceBundleError("Invalid reference schema for \(name). Regenerate the bundle from its FASTA.")
        guard ordinary == 1 else { throw error }
        let columns = try db.statement("SELECT name, type, [notnull], pk, hidden FROM pragma_table_xinfo('\(name)') ORDER BY cid")
        for (i, field) in ([("id", "INTEGER")] + fields).enumerated() {
            guard try columns.next(), try columns.text(0) == field.0, try columns.text(1).uppercased() == field.1,
                  try columns.integer(3) == (i == 0 ? 1 : 0), try columns.integer(4) == 0,
                  try i == 0 || columns.integer(2) == 1 else { throw error }
        }
    }

    static func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReferenceBundleError("Enter a nonblank bundle name.") }
        guard trimmed.utf8.count <= fieldBytes else {
            throw ReferenceBundleError("The bundle name exceeds the 4,096-byte UTF-8 limit.")
        }
        return trimmed
    }

    static func name(_ db: ReferenceDatabase) throws -> String {
        let invalidName = ReferenceBundleError("Invalid or missing bundle name. Regenerate the bundle from its FASTA.")
        let row = try db.statement("""
            SELECT CASE WHEN length(CAST(bundle_name AS BLOB)) <= \(fieldBytes) THEN bundle_name END
            FROM metadata WHERE id = 1
            """)
        guard try row.next() else { throw invalidName }
        do {
            let name = try row.text(0)
            guard try validatedName(name).utf8.elementsEqual(name.utf8) else { throw invalidName }
            return name
        } catch {
            throw invalidName
        }
    }

    static func provenance(_ db: ReferenceDatabase) throws -> ReferenceProvenance {
        let rows = try db.statement("""
            SELECT id, CASE WHEN length(CAST(source_name AS BLOB)) <= \(fieldBytes) THEN source_name END,
                CASE WHEN length(CAST(creator AS BLOB)) <= \(fieldBytes) THEN creator END,
                CASE WHEN length(CAST(created_utc AS BLOB)) <= \(fieldBytes) THEN created_utc END, chunk_bytes
            FROM metadata LIMIT 2
            """)
        guard try rows.next(), try rows.integer(0) == 1, try rows.integer(4) == chunkBytes else {
            throw ReferenceBundleError("Invalid reference bundle metadata.")
        }
        let value = try ReferenceProvenance(sourceName: rows.text(1), creator: rows.text(2), createdUTC: rows.text(3))
        guard !value.sourceName.utf8.contains(47), !value.sourceName.utf8.contains(0), ![".", ".."].contains(value.sourceName),
              validTimestamp(value.createdUTC), try !rows.next() else {
            throw ReferenceBundleError("Invalid reference bundle provenance metadata.")
        }
        return value
    }

    private static func validTimestamp(_ text: String) -> Bool {
        let timestamp = /([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?(?:Z|\+00:00)/
        guard let match = text.wholeMatch(of: timestamp) else { return false }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let components = DateComponents(year: Int(match.1), month: Int(match.2), day: Int(match.3),
                                        hour: Int(match.4), minute: Int(match.5), second: Int(match.6))
        return components.isValidDate(in: calendar)
    }
}
