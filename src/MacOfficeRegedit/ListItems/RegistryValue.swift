import Foundation

struct RegistryValue: Identifiable {
    let id: String // node_id+name
    let name: String
    let type: RegistryValueType?
    let data: String?

    var typeString: String {
        return "\(self.type!)"
    }
    
    var dataString: String {
        return "\(self.data ?? "")"
    }
}

enum RegistryValueType: Int64 {
    case REG_NONE = 0
    case REG_SZ = 1
    case REG_EXPAND_SZ = 2
    case REG_BINARY = 3
    case REG_DWORD = 4
    case REG_DWORD_BIG_ENDIAN = 5
    case REG_LINK = 6
    case REG_MULTI_SZ = 7
    case REG_RESOURCE_LIST = 8
    case REG_FULL_RESOURCE_DESCRIPTOR = 9
    case REG_RESOURCE_REQUIREMENTS_LIST = 10
    case REG_QWORD = 11
    
    static func fromInt(_ type: Int64) -> RegistryValueType {
        return .REG_BINARY
    }
}
