import Foundation

@MainActor class RegistryKeyViewModel: ObservableObject, Identifiable {
    private(set) var data: RegistryKey
    let id: Int64
    let name: String
    let path: String
    let children: [RegistryKeyViewModel]?
    
    init(_ registryKey: RegistryKey) {
        self.data = registryKey
        self.id = registryKey.nodeId
        self.name = registryKey.name
        self.path = registryKey.path!
        
        if let subKeys = registryKey.subKeys, !subKeys.isEmpty {
            self.children = subKeys.map { RegistryKeyViewModel($0) }
        } else {
            self.children = nil
        }
    }
}

extension RegistryKeyViewModel: Hashable {
    nonisolated static func == (lhs: RegistryKeyViewModel, rhs: RegistryKeyViewModel) -> Bool {
        return lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
    
}
