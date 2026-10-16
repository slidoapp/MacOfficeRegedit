import Foundation

/// Typed payload of a registry value.
///
/// The Office registry database stores the `value` column with whatever SQLite storage class fits:
/// `TEXT` for strings, `INTEGER` for DWORD/QWORD (DWORDs as sign-extended 32-bit integers) and `BLOB` for binary data.
enum RegistryData: Hashable {
    /// SQL `NULL` – Windows shows this as "(value not set)".
    case none
    case string(String)
    case multiString([String])
    case dword(UInt32)
    case qword(UInt64)
    case binary([UInt8])

    // MARK: - Display

    /// Text shown in the "Data" column, formatted like Windows regedit.
    var displayString: String {
        switch self {
        case .none:
            return "(value not set)"
        case .string(let string):
            return string
        case .multiString(let strings):
            return strings.joined(separator: " ")
        case .dword(let number):
            return String(format: "0x%08x (%u)", number, number)
        case .qword(let number):
            return String(format: "0x%016llx (%llu)", number, number)
        case .binary(let bytes):
            if bytes.isEmpty {
                return "(zero-length binary value)"
            }
            let limit = 128
            let hex = bytes.prefix(limit).map { String(format: "%02x", $0) }.joined(separator: " ")
            return bytes.count > limit ? hex + " …" : hex
        }
    }

    /// Raw bytes as Windows would store them, used by the binary editor and `.reg` export.
    var rawBytes: [UInt8] {
        switch self {
        case .none:
            return []
        case .string(let string):
            return RegistryData.utf16LEBytes(string, terminated: true)
        case .multiString(let strings):
            return RegistryData.multiStringBytes(strings)
        case .dword(let number):
            return withUnsafeBytes(of: number.littleEndian, Array.init)
        case .qword(let number):
            return withUnsafeBytes(of: number.littleEndian, Array.init)
        case .binary(let bytes):
            return bytes
        }
    }

    // MARK: - UTF-16LE helpers

    static func utf16LEBytes(_ string: String, terminated: Bool) -> [UInt8] {
        var units = Array(string.utf16)
        if terminated {
            units.append(0)
        }
        return units.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
    }

    /// Decodes UTF-16LE bytes, stopping at the first NUL terminator.
    static func string(fromUTF16LE bytes: [UInt8]) -> String {
        let units = utf16Units(bytes)
        let end = units.firstIndex(of: 0) ?? units.endIndex
        return String(decoding: units[..<end], as: UTF16.self)
    }

    /// `REG_MULTI_SZ` layout: NUL-terminated UTF-16LE strings followed by an extra NUL.
    static func multiStringBytes(_ strings: [String]) -> [UInt8] {
        strings.flatMap { utf16LEBytes($0, terminated: true) } + [0, 0]
    }

    static func multiString(fromUTF16LE bytes: [UInt8]) -> [String] {
        var result = [String]()
        var current = [UInt16]()
        for unit in utf16Units(bytes) {
            if unit == 0 {
                if current.isEmpty {
                    break
                }
                result.append(String(decoding: current, as: UTF16.self))
                current.removeAll()
            } else {
                current.append(unit)
            }
        }
        if !current.isEmpty {
            result.append(String(decoding: current, as: UTF16.self))
        }
        return result
    }

    private static func utf16Units(_ bytes: [UInt8]) -> [UInt16] {
        stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
    }
}
