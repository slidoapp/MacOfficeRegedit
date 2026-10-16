import Foundation

/// A single row of the `HKEY_CURRENT_USER_values` table.
struct RegistryValue: Identifiable, Hashable {
    struct ID: Hashable {
        let keyId: Int64
        /// Bytes rather than `String`: Swift treats canonically equivalent strings (e.g. NFC and NFD "é")
        /// as equal, while SQLite allows both as distinct names.
        let normalizedName: [UInt8]

        init(keyId: Int64, name: String) {
            self.keyId = keyId
            self.normalizedName = Array(RegistryValue.normalize(name).utf8)
        }
    }

    /// Value names are compared with SQLite's `COLLATE nocase`, which only folds ASCII letters.
    static func normalize(_ name: String) -> String {
        String(String.UnicodeScalarView(name.unicodeScalars.map { scalar in
            ("A"..."Z").contains(scalar) ? Unicode.Scalar(scalar.value + 32)! : scalar
        }))
    }

    let keyId: Int64
    /// Empty string is the key's default value.
    var name: String
    var type: RegistryValueType
    var data: RegistryData

    var id: ID { ID(keyId: keyId, name: name) }

    var isDefault: Bool { name.isEmpty }

    var displayName: String { isDefault ? "(Default)" : name }

    /// Name of the bundled icon matching the Windows regedit look.
    var iconName: String {
        switch type {
        case .REG_SZ, .REG_EXPAND_SZ, .REG_MULTI_SZ, .REG_LINK:
            return "KeyValueString"
        default:
            return "KeyValueBinary"
        }
    }
}

extension RegistryValue {
    /// The default (empty) data used when creating a new value of the given type.
    static func makeNew(keyId: Int64, name: String, type: RegistryValueType) -> RegistryValue {
        RegistryValue(keyId: keyId, name: name, type: type, data: type.defaultData)
    }
}
