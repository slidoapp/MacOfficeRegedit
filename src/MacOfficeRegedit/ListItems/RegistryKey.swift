import Foundation

struct RegistryKey: Identifiable, Hashable {
    let id: Int64
    let name: String
    let path: String
    let children: [RegistryKey]?
}
