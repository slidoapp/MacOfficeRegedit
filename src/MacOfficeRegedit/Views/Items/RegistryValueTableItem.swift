import Foundation
import SQLite

struct RegistryValueTableItem: Identifiable {
    let id: String
    let name: String
    let type: String
    let icon: String
    let data: String
    
    init(fromRegValue regValue: RegistryValue) {
        self.id = "\(regValue.nodeId):\(regValue.name)"
        self.name = regValue.name.isEmpty ? "(Default)" : regValue.name
        self.icon = regValue.type == .REG_BINARY ? "KeyValueBinary" : "KeyValueString"
        self.type = "\(regValue.type!)"
        self.data = RegistryValueTableItem.getDataString(regValue: regValue)
    }
    
    private static func getDataString(regValue: RegistryValue) -> String {
        guard let val = regValue.value else {
            return "❌"
        }
        
        switch regValue.type {
        case .REG_DWORD, .REG_DWORD_BIG_ENDIAN:
            let num = val as! Int64
            return String(format: "0x%08x (\(num))", num)
        case .REG_QWORD:
            let num = val as! Int64
            return String(format: "0x%016x (\(num))", num)
        case .REG_BINARY:
            let bin = val as! [UInt8]
            return bin.map {
                String(format: "%02x", $0)
             }.joined(separator: " ")
        default:
            return val as! String
        }
    }
}
