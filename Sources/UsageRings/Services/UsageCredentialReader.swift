import UsageCore
import Foundation
import SQLite3

enum UsageCredentialReader {
    static func cursorCookie(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        try cursorCookie(token: cursorToken(home: home), now: Date())
    }

    static func cursorToken(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        let location = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: location.path) else { throw UsageReadError.missingSession }
        let token: String
        do {
            token = try readCursorToken(location: location, immutable: false)
        } catch {
            // Immutable mode must never ignore an active WAL containing a newer account/session.
            guard !FileManager.default.fileExists(atPath: location.path + "-wal"),
                  !FileManager.default.fileExists(atPath: location.path + "-shm") else { throw error }
            token = try readCursorToken(location: location, immutable: true)
        }
        _ = try cursorCookie(token: token, now: Date())
        return token
    }

    static func cursorCookie(token: String, now: Date) throws -> String {
        guard let json = payload(token),
              let subject = json["sub"] as? String,
              let userID = subject.split(separator: "|").last,
              !userID.isEmpty,
              userID.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }),
              let expiresAt = json["exp"] as? Double else { throw UsageReadError.missingSession }
        guard expiresAt > now.timeIntervalSince1970 + 60 else { throw UsageReadError.expiredSession }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
    }

    private static func readCursorToken(location: URL, immutable: Bool) throws -> String {
        var database: OpaquePointer?
        let path = immutable ? location.absoluteString + "?immutable=1" : location.path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw UsageReadError.missingSession
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw UsageReadError.missingSession
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0) else { throw UsageReadError.missingSession }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        guard let token = decodeToken(data), !token.isEmpty else { throw UsageReadError.missingSession }
        return token
    }

    static func decodeToken(_ data: Data) -> String? {
        if !data.isEmpty, data.count.isMultiple(of: 2),
           stride(from: 0, to: data.count, by: 2).allSatisfy({ data[$0] > 0 && data[$0] < 128 && data[$0 + 1] == 0 }) {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ part in
            !part.isEmpty && part.utf8.allSatisfy { byte in
                (65...90).contains(byte) || (97...122).contains(byte)
                    || (48...57).contains(byte) || byte == 45 || byte == 95
            }
        }) else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
