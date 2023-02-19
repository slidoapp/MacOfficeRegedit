import Foundation

struct RegistryKeyListItem: Identifiable, Hashable {
    let id: Int64
    let name: String
    let path: String
    var children: [RegistryKeyListItem]?

    init(fromRegKey regKey: RegistryKey) {
        self.id = regKey.nodeId
        self.name = regKey.name
        self.path = regKey.path ?? ""
        
        if let subKeys = regKey.subKeys, !subKeys.isEmpty {
            self.children = subKeys.map {
                RegistryKeyListItem(fromRegKey: $0)
            }
        }
    }
}
