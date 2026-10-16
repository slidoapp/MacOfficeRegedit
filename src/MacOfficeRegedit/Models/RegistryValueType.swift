/// https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types
enum RegistryValueType: Int64, CaseIterable, Hashable {
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

    var name: String { "\(self)" }

    /// Types offered in the "New" menus, in the order Windows regedit lists them.
    static let creatable: [RegistryValueType] = [.REG_SZ, .REG_BINARY, .REG_DWORD, .REG_QWORD, .REG_MULTI_SZ, .REG_EXPAND_SZ]

    /// Label used in "New" menus, matching Windows regedit.
    var newMenuTitle: String {
        switch self {
        case .REG_SZ: return "String Value"
        case .REG_BINARY: return "Binary Value"
        case .REG_DWORD: return "DWORD (32-bit) Value"
        case .REG_QWORD: return "QWORD (64-bit) Value"
        case .REG_MULTI_SZ: return "Multi-String Value"
        case .REG_EXPAND_SZ: return "Expandable String Value"
        default: return name
        }
    }

    var defaultData: RegistryData {
        switch self {
        case .REG_SZ, .REG_EXPAND_SZ, .REG_LINK: return .string("")
        case .REG_MULTI_SZ: return .multiString([])
        case .REG_DWORD, .REG_DWORD_BIG_ENDIAN: return .dword(0)
        case .REG_QWORD: return .qword(0)
        default: return .binary([])
        }
    }
}
