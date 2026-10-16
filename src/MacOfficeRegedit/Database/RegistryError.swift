import Foundation

enum RegistryError: LocalizedError, Equatable {
    case databaseNotFound(URL)
    case invalidDatabase(String)
    case readOnly
    case keyNotFound(Int64)
    case valueNotFound(String)
    case keyAlreadyExists(String)
    case valueAlreadyExists(String)
    case invalidName(String)
    case invalidData(String)
    case cannotModifyRoot

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let url):
            return "The registry database was not found at \(url.path). Is Microsoft Office installed?"
        case .invalidDatabase(let reason):
            return "The file is not a valid Office registry database: \(reason)"
        case .readOnly:
            return "The registry is opened read-only."
        case .keyNotFound:
            return "The key no longer exists. It may have been deleted by another application."
        case .valueNotFound(let name):
            return "The value \"\(name)\" no longer exists."
        case .keyAlreadyExists(let name):
            return "A key named \"\(name)\" already exists. Type another name and try again."
        case .valueAlreadyExists(let name):
            return "A value named \"\(name)\" already exists. Type another name and try again."
        case .invalidName(let reason):
            return reason
        case .invalidData(let reason):
            return reason
        case .cannotModifyRoot:
            return "The \(RegistryPath.hive) root key cannot be modified."
        }
    }
}
