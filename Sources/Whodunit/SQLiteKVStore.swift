import Foundation

#if os(macOS)
import SQLite3

enum SQLiteKVStore {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    final class DB {
        fileprivate let handle: OpaquePointer?

        init?(url: URL) {
            var db: OpaquePointer?
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
            let rc = sqlite3_open_v2(url.path, &db, flags, nil)
            guard rc == SQLITE_OK else {
                if db != nil { sqlite3_close(db) }
                return nil
            }
            self.handle = db
            sqlite3_busy_timeout(db, 50)
        }

        func valueData(forKey key: String) -> Data? {
            guard let handle else { return nil }
            let sql = "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

            let bytes = sqlite3_column_blob(stmt, 0)
            let count = sqlite3_column_bytes(stmt, 0)
            guard let bytes, count > 0 else { return Data() }
            return Data(bytes: bytes, count: Int(count))
        }

        func valueString(forKey key: String) -> String? {
            guard let data = valueData(forKey: key) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        deinit {
            if let handle { sqlite3_close(handle) }
        }
    }
}

#endif
