import Foundation

final class DataStore: ObservableObject {
    @Published var valueTableItems: [RegistryValueTableItem]
    @Published var regValues: [RegistryValue] {
        didSet {
            self.valueTableItems = self.regValues.map {
                RegistryValueTableItem(fromRegValue: $0)
            }
        }
    }
    
    @Published var allKeys: [RegistryKeyViewModel]
    @Published var currentPath: String = ""
    @Published var selectedKey: RegistryKeyViewModel? {
        didSet {
            guard let selectedKey else {
                return
            }
  
            self.currentPath = selectedKey.path
            self.regValues = self.reader.fetchValues(nodeId: selectedKey.id)
        }
    }
    
    private let reader = Reader()
    
    init(isPreview: Bool = false) {
        self.allKeys = [RegistryKeyViewModel]()
        self.regValues = [RegistryValue]()
        self.valueTableItems = [RegistryValueTableItem]()
        
        if (isPreview) {
            self.populatePreview()
        }
        else {
            self.reader.connect()
            let fStart = CFAbsoluteTimeGetCurrent()

            let _allKeys = reader.fetchKeys()
            Task { @MainActor in
                self.allKeys = _allKeys.map {
                    RegistryKeyViewModel($0)
                }
            }
            
            let ms = (CFAbsoluteTimeGetCurrent() - fStart) * 1000
            debugPrint("Fetching keys took: \(Int(ms)) ms.")
        }
    }
    
    func deleteKey(id: Int64) {
        func deleteRecursive(keys: inout [RegistryKeyViewModel]) {
            keys = keys.filter { $0.id != id }
            for key in keys {
                if var ch = key.children {
                    deleteRecursive(keys: &ch)
                }
            }
        }
        
        debugPrint("Deleting item with id \(id)")
        deleteRecursive(keys: &self.allKeys)
    }
    
    
    private func populatePreview() {
        let _allKeys = [
            RegistryKey(nodeId: 1, parentId: -1, name: "Foo", path: "Foo", subKeys: [
                RegistryKey(nodeId: 11, parentId: 1,  name: "Bar", path: "Foo\\Bar", subKeys: [])
            ])]
        
        Task { @MainActor in
            self.allKeys = _allKeys.map {
                RegistryKeyViewModel($0)
            }
        }

        self.regValues = [
            RegistryValue(nodeId: 1, name: "Dominik", type: .REG_SZ, value: "a"),
            RegistryValue(nodeId: 2, name: "Palo", type: .REG_SZ, value: "b")
        ]
    }
}
