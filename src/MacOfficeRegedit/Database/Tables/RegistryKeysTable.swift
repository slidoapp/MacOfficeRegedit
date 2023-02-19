import SQLite

struct RegistryKeysTable {
    static let name = Table("HKEY_CURRENT_USER")
    
    struct Expressions {
        static let nodeId = Expression<Int64>("node_id")
        static let parentId = Expression<Int64>("parent_id")
        static let name = Expression<Blob>("name")
        static let writeTime = Expression<Blob>("write_time")
    }
}
