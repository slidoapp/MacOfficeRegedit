import Foundation

/// A single row of the `HKEY_CURRENT_USER` table.
struct RegistryKey: Identifiable, Hashable {
    /// `parent_id` of top-level keys. Also used as the id of the synthetic `HKEY_CURRENT_USER` root node.
    static let rootId: Int64 = -1

    let id: Int64
    var parentId: Int64
    var name: String
    var writeTime: Date?

    var isRoot: Bool { id == RegistryKey.rootId }

    static let root = RegistryKey(id: rootId, parentId: rootId, name: RegistryPath.hive, writeTime: nil)

    /// Windows does not allow backslashes in key names (they separate path components).
    static func validateName(_ name: String) throws {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw RegistryError.invalidName("Key name cannot be empty.")
        }
        if name.contains("\\") {
            throw RegistryError.invalidName("Key name cannot contain a backslash (\\).")
        }
        if name.count > 255 {
            throw RegistryError.invalidName("Key name cannot be longer than 255 characters.")
        }
    }
}
