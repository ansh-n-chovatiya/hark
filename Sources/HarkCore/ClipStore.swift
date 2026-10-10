import CryptoKit
import Foundation
import SQLite3

public struct Clip: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let text: String
    public let source: String
    public let at: Date

    public init(id: Int64, text: String, source: String, at: Date) {
        self.id = id
        self.text = text
        self.source = source
        self.at = at
    }
}

public enum ClipStoreError: Error, Equatable {
    case database(String)
    case wrongKey
}

public final class ClipStore: @unchecked Sendable {
    public static let titleLength = 120

    private let database: Database
    private let key: SymmetricKey
    private let limit: Int
    private let queue = DispatchQueue(label: "dev.hark.clips")
    private let lock = NSLock()
    private var clips: [Clip]
    private var nextID: Int64

    public init(url: URL, key: SymmetricKey, limit: Int) throws {
        self.key = key
        self.limit = max(limit, 1)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try Database(path: url.path)
        try database.execute(
            """
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            CREATE TABLE IF NOT EXISTS clips (
                id INTEGER PRIMARY KEY,
                copied_at REAL NOT NULL,
                source TEXT NOT NULL,
                ciphertext BLOB NOT NULL
            );
            """)
        let stored = try database.newest(self.limit)
        clips = try stored.map { row in
            Clip(id: row.id, text: try Self.open(row.ciphertext, with: key), source: row.source, at: row.at)
        }
        nextID = try database.highestID() + 1
    }

    public func add(text: String, source: String, at: Date) {
        lock.lock()
        if clips.first?.text == text {
            lock.unlock()
            return
        }
        let clip = Clip(id: nextID, text: text, source: source, at: at)
        nextID += 1
        clips.insert(clip, at: 0)
        var newestDropped: Int64?
        if clips.count > limit {
            newestDropped = clips[limit].id
            clips.removeSubrange(limit...)
        }
        lock.unlock()

        queue.async { [database, key] in
            do {
                try database.insert(clip, ciphertext: try Self.seal(clip.text, with: key))
                if let newestDropped {
                    try database.deleteThrough(newestDropped)
                }
            } catch {
                FileHandle.standardError.write(Data("hark: could not write clipboard history: \(error)\n".utf8))
            }
        }
    }

    /// Newest first.
    public func all() -> [Clip] {
        lock.withLock { clips }
    }

    public func asItems(now: Date = Date()) -> [Item] {
        let formatter = RelativeDateTimeFormatter()
        return all().map { clip in
            Item(
                id: "clip:\(clip.id)",
                kind: .clip,
                title: Self.title(for: clip.text),
                detail: formatter.localizedString(for: clip.at, relativeTo: now),
                owner: clip.source,
                lastUsed: clip.at,
                payload: ["clipID": String(clip.id)]
            )
        }
    }

    /// Returns once every write queued so far has reached the file.
    public func flush() {
        queue.sync {}
    }

    static func title(for text: String) -> String {
        var title = ""
        var length = 0
        var pendingSpace = false
        for character in text {
            if character.isWhitespace {
                pendingSpace = length > 0
                continue
            }
            if pendingSpace {
                if length + 1 >= titleLength { break }
                title.append(" ")
                length += 1
                pendingSpace = false
            }
            title.append(character)
            length += 1
            if length == titleLength { break }
        }
        return title
    }

    private static func seal(_ text: String, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(Data(text.utf8), using: key).combined else {
            throw ClipStoreError.database("sealed entry has no combined form")
        }
        return combined
    }

    private static func open(_ ciphertext: Data, with key: SymmetricKey) throws -> String {
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext),
            let plain = try? AES.GCM.open(box, using: key),
            let text = String(data: plain, encoding: .utf8)
        else { throw ClipStoreError.wrongKey }
        return text
    }
}

/// One connection, used by the initialiser and afterwards only on the store's write queue.
private final class Database: @unchecked Sendable {
    struct Row {
        let id: Int64
        let at: Date
        let source: String
        let ciphertext: Data
    }

    private let handle: OpaquePointer
    // SQLITE_TRANSIENT is a C macro Swift cannot import; it tells SQLite to copy the bound bytes.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var opened: OpaquePointer?
        let code = sqlite3_open_v2(
            path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(opened)
            throw ClipStoreError.database(message)
        }
        handle = opened
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    func newest(_ limit: Int) throws -> [Row] {
        let statement = try prepare("SELECT id, copied_at, source, ciphertext FROM clips ORDER BY id DESC LIMIT ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(limit))
        var rows: [Row] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw lastError() }
            let length = Int(sqlite3_column_bytes(statement, 3))
            let ciphertext = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: length) } ?? Data()
            rows.append(
                Row(
                    id: sqlite3_column_int64(statement, 0),
                    at: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1)),
                    source: sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "",
                    ciphertext: ciphertext
                ))
        }
        return rows
    }

    func highestID() throws -> Int64 {
        let statement = try prepare("SELECT COALESCE(MAX(id), 0) FROM clips")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return sqlite3_column_int64(statement, 0)
    }

    func insert(_ clip: Clip, ciphertext: Data) throws {
        let statement = try prepare("INSERT INTO clips (id, copied_at, source, ciphertext) VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, clip.id)
        sqlite3_bind_double(statement, 2, clip.at.timeIntervalSinceReferenceDate)
        sqlite3_bind_text(statement, 3, clip.source, -1, Self.transient)
        ciphertext.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), Self.transient)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    func deleteThrough(_ id: Int64) throws {
        let statement = try prepare("DELETE FROM clips WHERE id <= ?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        return statement
    }

    private func lastError() -> ClipStoreError {
        .database(String(cString: sqlite3_errmsg(handle)))
    }
}
