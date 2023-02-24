import Foundation

class ContentModel: ObservableObject {
    @Published var values: [RegistryValueTableItem]
    @Published var allKeys: [RegistryKeyListItem]
    @Published var currentPath: String = ""
    @Published var selectedKey: RegistryKeyListItem? {
        didSet {
            guard let selectedKey else {
                return
            }
  
            self.currentPath = selectedKey.path
            self.values = self.reader.fetchValues(nodeId: selectedKey.id).map {
                RegistryValueTableItem(fromRegValue: $0)
            }
        }
    }
    
    private let reader = Reader()
    
    init(isPreview: Bool = false) {
        self.allKeys = [RegistryKeyListItem]()
        self.values = [RegistryValueTableItem]()
        
        if (isPreview) {
            self.populatePreview()
        }
        else {
            self.reader.connect()
            let fStart = CFAbsoluteTimeGetCurrent()
            self.allKeys = reader.fetchKeys().map {
                RegistryKeyListItem(fromRegKey: $0)
            }
            
            let ms = (CFAbsoluteTimeGetCurrent() - fStart) * 1000
            debugPrint("Fetching keys took: \(Int(ms)) ms.")
        }
    }
    
    private func populatePreview() {
//        self.allKeys = [
//            RegistryKey(id: 1, name: "Foo", path: "Foo", subKeys: [
//                RegistryKey(id: 11, name: "Bar", path: "Foo\\Bar", subKeys: [])
//            ])
//        ]
//
//        self.values = [
//            RegistryValue(id: "1/Dominik", name: "Dominik", type: .REG_BINARY, data: "a"),
//            RegistryValue(id: "1/Palo", name: "Palo", type: .REG_DWORD, data: "b")
//        ]
    }
}
