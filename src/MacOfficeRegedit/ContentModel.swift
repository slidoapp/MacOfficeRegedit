
import Foundation

class ContentModel: ObservableObject {
    @Published var values: [RegistryValue]
    @Published var allKeys: [RegistryKey]
    @Published var currentPath: String = ""
    @Published var selectedKey: RegistryKey? {
        didSet {
            guard let selectedKey else {
                return
            }
  
            self.currentPath = selectedKey.path
            self.values = self.reader.fetchValues(nodeId: selectedKey.id)
        }
    }
    
    private let reader = Reader()
    
    init(isPreview: Bool = false) {
        self.allKeys = [RegistryKey]()
        self.values = [RegistryValue]()
        
        if (isPreview) {
            self.populatePreview()
        }
        else {
            self.reader.connect()
            self.allKeys = reader.fetchKeys()
        }
    }
    
    // TODO: move to actrions
    func modifyValue(_ item: RegistryValue) {
        //
    }
    
    private func populatePreview() {
        self.allKeys = [
            RegistryKey(id: 1, name: "Foo", path: "Foo", subKeys: [
                RegistryKey(id: 11, name: "Bar", path: "Foo\\Bar", subKeys: [])
            ])
        ]
        
        self.values = [
            RegistryValue(id: "1/Dominik", name: "Dominik", type: .REG_BINARY, data: "a"),
            RegistryValue(id: "1/Palo", name: "Palo", type: .REG_DWORD, data: "b")
        ]
    }
}
