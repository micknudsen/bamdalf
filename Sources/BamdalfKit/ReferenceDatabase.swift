import Foundation
import SQLite3

struct ReferenceBundleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Each connection belongs to one synchronous importer or one ReferenceBundle actor.
final class ReferenceDatabase {
    fileprivate let handle: OpaquePointer

    init(_ url: URL, creating: Bool = false) throws {
        var db: OpaquePointer?
        let flags = creating ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        let status = sqlite3_open_v2(url.path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            let error = ReferenceBundleError(String(cString: sqlite3_errmsg(db)))
            sqlite3_close(db)
            throw error
        }
        handle = db
        // Cap SQLite's own row allocations, including malformed schemas or payloads.
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, Int32(ReferenceFormat.chunkBytes + 4096))
        try execute("PRAGMA trusted_schema=OFF; PRAGMA mmap_size=0; PRAGMA cache_size=-4096;")
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    func statement(_ sql: String) throws -> ReferenceStatement {
        try ReferenceStatement(self, sql)
    }

    fileprivate func check(_ status: Int32) throws {
        guard status == SQLITE_OK else {
            throw ReferenceBundleError("Reference database: \(String(cString: sqlite3_errmsg(handle))).")
        }
    }
}

final class ReferenceStatement {
    private let db: ReferenceDatabase
    private let statement: OpaquePointer

    fileprivate init(_ db: ReferenceDatabase, _ sql: String) throws {
        self.db = db
        var pointer: OpaquePointer?
        try db.check(sqlite3_prepare_v2(db.handle, sql, -1, &pointer, nil))
        statement = pointer!
    }

    deinit { sqlite3_finalize(statement) }

    func next() throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        case let status: try db.check(status); return false
        }
    }

    func insert() throws {
        _ = try next()
        try db.check(sqlite3_reset(statement))
    }

    func bind(_ value: Int64, at column: Int32) throws {
        try db.check(sqlite3_bind_int64(statement, column, value))
    }

    func bind(_ value: String, at column: Int32) throws {
        let utf8 = value.utf8CString
        try utf8.withUnsafeBufferPointer { bytes in
            try db.check(sqlite3_bind_text(statement, column, bytes.baseAddress, Int32(bytes.count - 1),
                                           unsafeBitCast(-1, to: sqlite3_destructor_type.self)))
        }
    }

    func bind(_ bytes: [UInt8], at column: Int32) throws {
        try bytes.withUnsafeBytes { buffer in
            try db.check(sqlite3_bind_blob(statement, column, buffer.baseAddress, Int32(buffer.count),
                                           unsafeBitCast(-1, to: sqlite3_destructor_type.self)))
        }
    }

    func integer(_ column: Int32) throws -> Int64 {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else {
            throw ReferenceBundleError("Expected an integer in the reference bundle.")
        }
        return sqlite3_column_int64(statement, column)
    }

    func text(_ column: Int32, limit: Int = ReferenceFormat.fieldBytes) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              (1...limit).contains(Int(sqlite3_column_bytes(statement, column))),
              let pointer = sqlite3_column_text(statement, column),
              let value = String(bytes: UnsafeBufferPointer(start: pointer, count: Int(sqlite3_column_bytes(statement, column))),
                                 encoding: .utf8) else {
            throw ReferenceBundleError("Invalid or oversized text in the reference bundle.")
        }
        return value
    }

    func withBases(_ column: Int32, count: Int, _ body: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB,
              sqlite3_column_bytes(statement, column) == count,
              let bytes = sqlite3_column_blob(statement, column) else {
            throw ReferenceBundleError("Invalid reference sequence chunk length or type.")
        }
        try body(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: count))
    }
}

extension ReferenceDatabase {
    func scalarInteger(_ sql: String) throws -> Int64? {
        let row = try statement(sql)
        guard try row.next(), !row.isNull(0) else { return nil }
        return try row.integer(0)
    }
}

extension ReferenceStatement {
    fileprivate func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(statement, column) == SQLITE_NULL
    }
}
