import SQLite

struct RegistryValuesTable {
    static let name = Table("HKEY_CURRENT_USER_values")
    
    struct Expressions {
        static let nodeId = Expression<Int64>("node_id")
        static let name = Expression<String>("name")
        static let type = Expression<RegistryValueType>("type")
    }
    
    struct Helpers {
        static func readValue(fromRow row: Row, forValueType valueType: RegistryValueType) -> Any? {
            switch valueType {
            case .REG_DWORD, .REG_DWORD_BIG_ENDIAN, .REG_QWORD:
                return try? row.get(Expression<Int64>("value"))
            case .REG_BINARY:
                return try? row.get(Expression<Blob>("value")).bytes
            default:
                return try? row.get(Expression<String>("value"))
            }
        }
    }
}

// Custom types
extension RegistryValueType: Value {
    typealias Datatype = Int64
    
    static var declaredDatatype: String {
        return Int64.declaredDatatype
    }

    static func fromDatatypeValue(_ datatypeValue: Int64) -> RegistryValueType {
        return RegistryValueType(rawValue: datatypeValue) ?? .REG_NONE
    }
    
    var datatypeValue: Int64 {
        return self.rawValue
    }
}
