import Foundation
import SQLite
import SQLite3

/// Access to the SQLite database in which Microsoft Office for Mac stores its `HKEY_CURRENT_USER` registry hive.
///
/// Schema (as created by Office):
/// ```
/// HKEY_CURRENT_USER        (node_id INTEGER PRIMARY KEY, parent_id, name TEXT COLLATE nocase, write_time, UNIQUE(parent_id, name))
/// HKEY_CURRENT_USER_values (node_id INTEGER, name TEXT COLLATE nocase, type INTEGER, value, UNIQUE(node_id, name))
/// ```
final class RegistryDatabase {
    private enum Tables {
        static let keys = "HKEY_CURRENT_USER"
        static let values = "HKEY_CURRENT_USER_values"
    }

    /// The registry used by Office apps (a symlink to the current database file).
    static var officeRegistryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/MicrosoftRegistrationDB.reg")
    }

    let url: URL
    let isReadOnly: Bool
    private let connection: Connection
    private var transactionDepth = 0

    /// Selects a value row. TEXT is read as raw bytes because SQLite.swift reads text as a C string,
    /// which would cut it at the first NUL (e.g. in `REG_MULTI_SZ` data stored as text).
    private static let valueColumns = """
        node_id, name, type, CASE WHEN typeof(value) = 'text' THEN CAST(value AS BLOB) ELSE value END, typeof(value)
        """

    /// - Parameter busyTimeout: Seconds to wait for locks held by Office apps.
    init(url: URL, readOnly: Bool = false, busyTimeout: Double = 5) throws {
        let resolvedURL = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw RegistryError.databaseNotFound(url)
        }

        self.url = resolvedURL
        self.isReadOnly = readOnly || !FileManager.default.isWritableFile(atPath: resolvedURL.path)
        self.connection = try Connection(resolvedURL.path, readonly: isReadOnly)
        self.connection.busyTimeout = busyTimeout

        try validateSchema()
    }

    private func validateSchema() throws {
        let tables: Set<String>
        do {
            tables = Set(try rows("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0[0] as? String })
        } catch {
            throw RegistryError.invalidDatabase(error.localizedDescription)
        }
        for table in [Tables.keys, Tables.values] where !tables.contains(table) {
            throw RegistryError.invalidDatabase("missing table \(table)")
        }
    }

    // MARK: - Reading

    func fetchAllKeys() throws -> [RegistryKey] {
        try rows("SELECT node_id, parent_id, name, write_time FROM \(Tables.keys)").compactMap { row in
            guard let id = row[0] as? Int64 else {
                return nil
            }
            return RegistryKey(
                id: id,
                parentId: (row[1] as? Int64) ?? RegistryKey.rootId,
                name: RegistryDatabase.string(row[2]),
                writeTime: RegistryDatabase.date(row[3])
            )
        }
    }

    func fetchValues(keyId: Int64) throws -> [RegistryValue] {
        try rows("SELECT \(RegistryDatabase.valueColumns) FROM \(Tables.values) WHERE node_id = ?", keyId)
            .map(RegistryDatabase.value(fromRow:))
    }

    func fetchAllValues() throws -> [RegistryValue] {
        try rows("SELECT \(RegistryDatabase.valueColumns) FROM \(Tables.values)")
            .map(RegistryDatabase.value(fromRow:))
    }

    func fetchValue(keyId: Int64, name: String) throws -> RegistryValue? {
        try rows("SELECT \(RegistryDatabase.valueColumns) FROM \(Tables.values) WHERE node_id = ? AND name = ?", keyId, name)
            .first
            .map(RegistryDatabase.value(fromRow:))
    }

    func keyExists(id: Int64) throws -> Bool {
        if id == RegistryKey.rootId {
            return true
        }
        let count = try connection.scalar("SELECT COUNT(*) FROM \(Tables.keys) WHERE node_id = ?", id) as? Int64
        return (count ?? 0) > 0
    }

    func fetchKey(id: Int64) throws -> RegistryKey? {
        if id == RegistryKey.rootId {
            return .root
        }
        return try rows("SELECT node_id, parent_id, name, write_time FROM \(Tables.keys) WHERE node_id = ?", id).first.map { row in
            RegistryKey(
                id: id,
                parentId: (row[1] as? Int64) ?? RegistryKey.rootId,
                name: RegistryDatabase.string(row[2]),
                writeTime: RegistryDatabase.date(row[3])
            )
        }
    }

    /// Guards against acting on a stale id: SQLite reuses the highest rowid after a delete, so a key
    /// deleted by Office could be replaced by an unrelated key with the same id.
    func verifyKey(_ expected: RegistryKey) throws {
        guard let current = try fetchKey(id: expected.id),
              current.parentId == expected.parentId,
              RegistryValue.normalize(current.name) == RegistryValue.normalize(expected.name) else {
            throw RegistryError.keyNotFound(expected.id)
        }
    }

    func childKeyId(parentId: Int64, name: String) throws -> Int64? {
        try connection.scalar("SELECT node_id FROM \(Tables.keys) WHERE parent_id = ? AND name = ?", parentId, name) as? Int64
    }

    // MARK: - Writing keys

    @discardableResult
    func createKey(named name: String, parentId: Int64) throws -> RegistryKey {
        try ensureWritable()
        try RegistryKey.validateName(name)
        var key: RegistryKey?
        try atomically {
            guard try keyExists(id: parentId) else {
                throw RegistryError.keyNotFound(parentId)
            }
            if try childKeyId(parentId: parentId, name: name) != nil {
                throw RegistryError.keyAlreadyExists(name)
            }
            let now = Date()
            try connection.run(
                "INSERT INTO \(Tables.keys) (parent_id, name, write_time) VALUES (?, ?, ?)",
                parentId, name, Blob(bytes: FileTime.bytes(from: now))
            )
            key = RegistryKey(id: connection.lastInsertRowid, parentId: parentId, name: name, writeTime: now)
            try touchKey(id: parentId, at: now)
        }
        return key!
    }

    /// Returns the id of the key at `path` (below the hive), creating missing keys along the way.
    func createKeyPath(_ path: [String]) throws -> Int64 {
        var parentId = RegistryKey.rootId
        for name in path {
            if let id = try childKeyId(parentId: parentId, name: name) {
                parentId = id
            } else {
                parentId = try createKey(named: name, parentId: parentId).id
            }
        }
        return parentId
    }

    func renameKey(id: Int64, to newName: String) throws {
        try ensureWritable()
        guard id != RegistryKey.rootId else {
            throw RegistryError.cannotModifyRoot
        }
        try RegistryKey.validateName(newName)
        try atomically {
            guard let parentId = try connection.scalar("SELECT parent_id FROM \(Tables.keys) WHERE node_id = ?", id) as? Int64 else {
                throw RegistryError.keyNotFound(id)
            }
            if let existing = try childKeyId(parentId: parentId, name: newName), existing != id {
                throw RegistryError.keyAlreadyExists(newName)
            }
            let now = Date()
            try connection.run(
                "UPDATE \(Tables.keys) SET name = ?, write_time = ? WHERE node_id = ?",
                newName, Blob(bytes: FileTime.bytes(from: now)), id
            )
            try touchKey(id: parentId, at: now)
        }
    }

    /// Deletes the key, all of its subkeys and all of their values.
    func deleteKey(id: Int64) throws {
        try ensureWritable()
        guard id != RegistryKey.rootId else {
            throw RegistryError.cannotModifyRoot
        }
        let subtree = """
            WITH RECURSIVE subtree(id) AS (
                SELECT ?
                UNION ALL
                SELECT k.node_id FROM \(Tables.keys) k JOIN subtree s ON k.parent_id = s.id
            )
            """
        try atomically {
            guard let parentId = try connection.scalar("SELECT parent_id FROM \(Tables.keys) WHERE node_id = ?", id) as? Int64 else {
                throw RegistryError.keyNotFound(id)
            }
            try connection.run("\(subtree) DELETE FROM \(Tables.values) WHERE node_id IN subtree", id)
            try connection.run("\(subtree) DELETE FROM \(Tables.keys) WHERE node_id IN subtree", id)
            try touchKey(id: parentId, at: Date())
        }
    }

    // MARK: - Writing values

    /// Adds a new value; fails if a value with the same name exists.
    func insertValue(_ value: RegistryValue) throws {
        try ensureWritable()
        try ensureValueKey(value.keyId)
        try atomically {
            if try fetchValue(keyId: value.keyId, name: value.name) != nil {
                throw RegistryError.valueAlreadyExists(value.name)
            }
            try writeValue(value)
        }
    }

    /// Replaces the data (and type) of an existing value, renaming it if `originalName` differs.
    func updateValue(_ value: RegistryValue, originalName: String) throws {
        try ensureWritable()
        try ensureValueKey(value.keyId)
        try atomically {
            guard try fetchValue(keyId: value.keyId, name: originalName) != nil else {
                throw RegistryError.valueNotFound(originalName)
            }
            if RegistryValue.normalize(value.name) != RegistryValue.normalize(originalName), try fetchValue(keyId: value.keyId, name: value.name) != nil {
                throw RegistryError.valueAlreadyExists(value.name)
            }
            try connection.run("DELETE FROM \(Tables.values) WHERE node_id = ? AND name = ?", value.keyId, originalName)
            try writeValue(value)
        }
    }

    /// Creates or replaces a value. Used by `.reg` import.
    func upsertValue(_ value: RegistryValue) throws {
        try ensureWritable()
        try ensureValueKey(value.keyId)
        try atomically {
            try connection.run("DELETE FROM \(Tables.values) WHERE node_id = ? AND name = ?", value.keyId, value.name)
            try writeValue(value)
        }
    }

    func renameValue(keyId: Int64, from oldName: String, to newName: String) throws {
        guard var value = try fetchValue(keyId: keyId, name: oldName) else {
            throw RegistryError.valueNotFound(oldName)
        }
        value.name = newName
        try updateValue(value, originalName: oldName)
    }

    func deleteValue(keyId: Int64, name: String) throws {
        try ensureWritable()
        try atomically {
            try connection.run("DELETE FROM \(Tables.values) WHERE node_id = ? AND name = ?", keyId, name)
            guard connection.changes > 0 else {
                throw RegistryError.valueNotFound(name)
            }
            try touchKey(id: keyId, at: Date())
        }
    }

    /// Runs several operations atomically. Calls may be nested.
    func transaction(_ block: () throws -> Void) throws {
        try ensureWritable()
        try atomically(block)
    }

    // MARK: - Backup

    /// Writes a consistent copy of the database to `destination`.
    func backup(to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try connection.run("VACUUM INTO ?", destination.path)
    }

    // MARK: - Private

    /// Runs `block` in a transaction; nested calls use savepoints.
    ///
    /// The outermost level uses `BEGIN IMMEDIATE` so the write lock is taken up front, honouring `busyTimeout`
    /// (SQLite doesn't wait when upgrading a read lock), and always ends in `COMMIT` or `ROLLBACK`, so a
    /// failed commit (e.g. while Office holds a lock) can't leave a transaction open that locks Office out.
    private func atomically(_ block: () throws -> Void) throws {
        if transactionDepth > 0 {
            let name = "sp_\(transactionDepth)"
            try connection.run("SAVEPOINT \(name)")
            transactionDepth += 1
            defer { transactionDepth -= 1 }
            do {
                try block()
                try connection.run("RELEASE \(name)")
            } catch {
                try connection.run("ROLLBACK TO \(name)")
                try connection.run("RELEASE \(name)")
                throw error
            }
            return
        }

        try connection.run("BEGIN IMMEDIATE")
        transactionDepth = 1
        defer { transactionDepth = 0 }
        do {
            try block()
            try connection.run("COMMIT")
        } catch {
            if sqlite3_get_autocommit(connection.handle) == 0 {
                try connection.run("ROLLBACK")
            }
            throw error
        }
    }

    private func writeValue(_ value: RegistryValue) throws {
        // Strings are bound as UTF-8 bytes and cast to TEXT, so embedded NULs survive (see `valueColumns`).
        let placeholder = RegistryDatabase.isText(value.data) ? "CAST(? AS TEXT)" : "?"
        try connection.run(
            "INSERT INTO \(Tables.values) (node_id, name, type, value) VALUES (?, ?, ?, \(placeholder))",
            value.keyId, value.name, value.type.rawValue, RegistryDatabase.binding(for: value.data)
        )
        try touchKey(id: value.keyId, at: Date())
    }

    private func touchKey(id: Int64, at date: Date) throws {
        guard id != RegistryKey.rootId else {
            return
        }
        try connection.run("UPDATE \(Tables.keys) SET write_time = ? WHERE node_id = ?", Blob(bytes: FileTime.bytes(from: date)), id)
    }

    private func ensureWritable() throws {
        if isReadOnly {
            throw RegistryError.readOnly
        }
    }

    private func ensureValueKey(_ keyId: Int64) throws {
        guard keyId != RegistryKey.rootId else {
            throw RegistryError.cannotModifyRoot
        }
        guard try keyExists(id: keyId) else {
            throw RegistryError.keyNotFound(keyId)
        }
    }

    private func rows(_ sql: String, _ bindings: Binding?...) throws -> [[Binding?]] {
        let statement = try connection.prepare(sql, bindings)
        var result = [[Binding?]]()
        while let row = try statement.failableNext() {
            result.append(row)
        }
        return result
    }

    // MARK: - Conversions

    private static func string(_ binding: Binding?) -> String {
        switch binding {
        case let string as String: return string
        case let blob as Blob: return String(decoding: blob.bytes, as: UTF8.self)
        case let binding?: return "\(binding)"
        case nil: return ""
        }
    }

    private static func date(_ binding: Binding?) -> Date? {
        switch binding {
        case let blob as Blob: return FileTime.date(fromBytes: blob.bytes)
        case let ticks as Int64 where ticks > 0: return FileTime.date(fromTicks: UInt64(ticks))
        default: return nil
        }
    }

    private static func value(fromRow row: [Binding?]) -> RegistryValue {
        let type = (row[2] as? Int64).flatMap(RegistryValueType.init(rawValue:)) ?? .REG_NONE
        var stored = row[3]
        if row[4] as? String == "text", let blob = stored as? Blob {
            stored = String(decoding: blob.bytes, as: UTF8.self)
        }
        return RegistryValue(
            keyId: (row[0] as? Int64) ?? RegistryKey.rootId,
            name: string(row[1]),
            type: type,
            data: data(from: stored, type: type)
        )
    }

    static func data(from binding: Binding?, type: RegistryValueType) -> RegistryData {
        switch binding {
        case nil:
            return .none
        case let number as Int64:
            switch type {
            case .REG_DWORD, .REG_DWORD_BIG_ENDIAN:
                return .dword(UInt32(truncatingIfNeeded: number))
            case .REG_SZ, .REG_EXPAND_SZ, .REG_LINK:
                return .string(String(number))
            default:
                return .qword(UInt64(bitPattern: number))
            }
        case let string as String:
            return type == .REG_MULTI_SZ
                ? .multiString(string.split(separator: "\0", omittingEmptySubsequences: true).map(String.init))
                : .string(string)
        case let blob as Blob:
            return type == .REG_MULTI_SZ
                ? .multiString(RegistryData.multiString(fromUTF16LE: blob.bytes))
                : .binary(blob.bytes)
        case let binding?:
            return .string("\(binding)")
        }
    }

    static func isText(_ data: RegistryData) -> Bool {
        if case .string = data {
            return true
        }
        return false
    }

    /// Encodes data using the same storage classes Office uses. Strings are returned as UTF-8 bytes,
    /// to be inserted with `CAST(? AS TEXT)`.
    static func binding(for data: RegistryData) -> Binding? {
        switch data {
        case .none: return nil
        case .string(let string): return Blob(bytes: Array(string.utf8))
        // Not TEXT joined by NULs: SQLite.swift binds text as a C string, which would truncate at the first NUL.
        case .multiString(let strings): return Blob(bytes: RegistryData.multiStringBytes(strings))
        case .dword(let number): return Int64(Int32(bitPattern: number))
        case .qword(let number): return Int64(bitPattern: number)
        case .binary(let bytes): return Blob(bytes: bytes)
        }
    }
}
