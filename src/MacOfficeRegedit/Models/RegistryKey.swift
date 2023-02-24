struct RegistryKey: Decodable {
    let nodeId: Int64
    let parentId: Int64
    let name: String
    var writeTime: WinDate?

    var path: String?
    var subKeys: [RegistryKey]?
    
    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case parentId = "parent_id"
        case name = "name"
    }
}
