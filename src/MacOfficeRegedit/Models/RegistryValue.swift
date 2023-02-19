struct RegistryValue: Decodable {
    let nodeId: Int64
    let name: String
    var type: RegistryValueType?
    var value: Any?

    private enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case name = "name"
    }
}
