import Foundation
import SQLite

class Reader {
    let regDbFile = FileManager()
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/MicrosoftRegistrationDB.reg")
        .resolvingSymlinksInPath()

    var dbConnection: Connection?
    
    func connect() {
        do {
            self.dbConnection = try Connection(self.regDbFile.absoluteString)
        } catch {
            print("ERROR: \(error)")
        }
    }
    
    func fetchKeys(parentId: Int64 = -1, path: String = "Computer\\HKEY_CURRENT_USER") -> [RegistryKey] {
        var items = [RegistryKey]()
        guard let db = self.dbConnection else {
            // log error
            return items
        }
        
        let query = Tables.hkcuKeys.filter(HkcuKeysCols.parentId == parentId)

        do {
            for row in try db.prepare(query) {
                let path = "\(path)\\\(row[HkcuKeysCols.name])"
                let children = self.fetchKeys(parentId: row[HkcuKeysCols.nodeId], path: path)
                
                items.append(RegistryKey(
                    id: row[HkcuKeysCols.nodeId],
                    name: row[HkcuKeysCols.name],
                    path: path,
                    children: children
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
        guard let db = self.dbConnection else {
            // log error
            return items
        }

        let query = Tables.hkcuValues.filter(HkcuValuesCols.nodeId == nodeId)
        
        do {
            for row in try db.prepare(query) {
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
