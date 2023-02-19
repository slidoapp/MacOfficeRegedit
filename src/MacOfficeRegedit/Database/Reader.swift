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
    
    func fetchKeys(parentRegKey: RegistryKey? = nil) -> [RegistryKey] {
        typealias Table = RegistryKeysTable
        
        guard let db = self.dbConnection else {
            // log error
            return []
        }
        
        let parentId = parentRegKey?.nodeId ?? -1
        let query = Table.name
            .filter(Table.Expressions.parentId == parentId)
            .order(Table.Expressions.name.asc)
        do {
            return try db.prepareRowIterator(query).map {
                var regKey: RegistryKey = try $0.decode()
                let parentPath = parentRegKey?.path ?? "Computer\\HKEY_CURRENT_USER"
                regKey.path = "\(parentPath)\\\(regKey.name)"
                regKey.writeTime = try $0.get(Table.Expressions.writeTime).bytes
                regKey.subKeys = self.fetchKeys(parentRegKey: regKey)
                return regKey
            }
        }
        catch {
            print("ERROR: \(error)")
            return []
        }
    }
    
    func fetchValues(nodeId: Int64) -> [RegistryValue] {
        typealias Table = RegistryValuesTable

        guard let db = self.dbConnection else {
            // log error
            return []
        }
        let query = Table.name
            .filter(Table.Expressions.nodeId == nodeId)
        do {
            return try db.prepareRowIterator(query).map {
                var regValue: RegistryValue = try $0.decode()
                let valueType = try $0.get(Table.Expressions.type)
                regValue.type = valueType
                regValue.value = Table.Helpers.readValue(fromRow: $0, forValueType: valueType)
                return regValue
            }
        }
        catch {
            print("ERROR: \(error)")
            return []
        }
    }
}
