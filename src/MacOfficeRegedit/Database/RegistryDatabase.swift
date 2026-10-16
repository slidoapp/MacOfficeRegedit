import Foundation
import SQLite

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

    func childKeyId(parentId: Int64, name: String) throws -> Int64? {
        try connection.scalar("SELECT node_id FROM \(Tables.keys) WHERE parent_id = ? AND name = ?", parentId, name) as? Int64
    }

    // MARK: - Private

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

}
