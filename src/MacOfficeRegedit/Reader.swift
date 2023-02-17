import Foundation
import SQLite

class Reader {
    let regDbFile = FileManager()
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/MicrosoftRegistrationDB.reg")
        .resolvingSymlinksInPath()

    var dbConnection: Connection?
    
    init() {
        do {
            //self.dbConnection = try Connection(self.regDbFile.absoluteString)
            self.dbConnection = try Connection("/Users/dpalo/Library/Group Containers/UBF8T346G9.Office/MicrosoftRegistrationDB.reg")
        } catch {
            print("ERROR: \(error)")
        }
    }
    
    func fetchKeys(parentId: Int64 = -1) -> [RegistryKey] {
        var items = [RegistryKey]()
        let query = Tables.hkcuKeys.filter(HkcuKeysCols.parentId == parentId)

        do {
            for row in try self.dbConnection!.prepare(query) {
                items.append(RegistryKey(
                    id: row[HkcuKeysCols.nodeId],
                    name: row[HkcuKeysCols.name],
                    children: self.fetchKeys(parentId: row[HkcuKeysCols.nodeId])
                ))
            }
        }
        catch {
            print("ERROR: \(error)")
            return items
        }

        return items
    }
    
    func fetchValues(nodeId: Int64) -> [RegistryValue] {
        var items = [RegistryValue]()
        let query = Tables.hkcuValues.filter(HkcuValuesCols.nodeId == nodeId)
        
        do {
            for row in try self.dbConnection!.prepare(query) {
                items.append(RegistryValue(
                    id: "\(nodeId)/\(row[HkcuValuesCols.name])",
                    name: row[HkcuValuesCols.name],
                    type: RegistryValueType(rawValue: row[HkcuValuesCols.type]),
                    data: row[HkcuValuesCols.value]
                ))
            }
        }
        catch {
            print("ERROR: \(error)")
            return items
        }
        
        return items
    }
}


struct Tables {
    static let hkcuKeys = Table("HKEY_CURRENT_USER")
    static let hkcuValues = Table("HKEY_CURRENT_USER_values")
}

struct HkcuKeysCols {
    static let nodeId = Expression<Int64>("node_id")
    static let parentId = Expression<Int64>("parent_id")
    static let name = Expression<String>("name")
}

struct HkcuValuesCols {
    static let nodeId = Expression<Int64>("node_id")
    static let name = Expression<String>("name")
    static let type = Expression<Int64>("type")
    static let value = Expression<String?>("value")
}
