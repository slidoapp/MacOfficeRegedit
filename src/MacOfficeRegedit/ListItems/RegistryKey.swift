import Foundation

struct RegistryKey: Identifiable, Hashable {
    let id: Int64
    let name: String
    var children: [RegistryKey]?
}
