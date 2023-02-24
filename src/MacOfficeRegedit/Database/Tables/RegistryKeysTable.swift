import Foundation
import SQLite

struct RegistryKeysTable {
    static let name = Table("HKEY_CURRENT_USER")
    
    struct Expressions {
        static let nodeId = Expression<Int64>("node_id")
        static let parentId = Expression<Int64>("parent_id")
        static let name = Expression<Blob>("name")
        static let writeTime = Expression<WinDate>("write_time")
    }
}

// Custom types
extension WinDate: Value {
    typealias Datatype = Blob
    
    static var declaredDatatype: String {
        return Int64.declaredDatatype
    }

    static func fromDatatypeValue(_ datatypeValue: Blob) -> WinDate {
        return WinDate(bytes: datatypeValue.bytes)
    }
    
    var datatypeValue: Blob {
        return Blob(bytes: self.bytes)
    }
}

struct WinDate {
    let bytes: [UInt8]

    static let ldapEpoch = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.date(from: "1601")!
    }()
    
    // see https://www.epochconverter.com/ldap
    var date: Date? {
        let ticks = UInt64(littleEndian: Data(bytes).withUnsafeBytes {
            $0.load(as: UInt64.self)
        })

        let milliseconds = ticks / 10000 // 1 tick = 100 nanosecods
        let seconds = Double(milliseconds) / 1000
        return WinDate.ldapEpoch.addingTimeInterval(seconds)
    }
}
