import Foundation

/// Helpers for Windows-style registry paths such as `Computer\HKEY_CURRENT_USER\Software\Microsoft`.
///
/// The Office registry only contains the `HKEY_CURRENT_USER` hive, so paths are represented
/// internally as the list of key names below it.
enum RegistryPath {
    static let computer = "Computer"
    static let hive = "HKEY_CURRENT_USER"
    static let hiveAbbreviation = "HKCU"
    static let separator: Character = "\\"

    /// Full path as displayed in the address bar.
    static func display(_ components: [String]) -> String {
        ([computer, hive] + components).joined(separator: String(separator))
    }

    /// Path as written in `.reg` files and "Copy Key Name".
    static func qualified(_ components: [String]) -> String {
        ([hive] + components).joined(separator: String(separator))
    }

    /// Parses a user-entered path into key names below the hive.
    ///
    /// Accepts an optional `Computer\` prefix, the full or abbreviated hive name, forward slashes,
    /// and redundant separators. Returns `nil` for paths into a different hive.
    static func components(of path: String) -> [String]? {
        var parts = path
            .replacingOccurrences(of: "/", with: String(separator))
            .split(separator: separator, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let first = parts.first, first.caseInsensitiveCompare(computer) == .orderedSame {
            parts.removeFirst()
        }
        guard let first = parts.first else {
            return []
        }
        if first.caseInsensitiveCompare(hive) == .orderedSame || first.caseInsensitiveCompare(hiveAbbreviation) == .orderedSame {
            parts.removeFirst()
            return parts
        }
        if first.uppercased().hasPrefix("HKEY_") || ["HKLM", "HKCR", "HKU", "HKCC"].contains(first.uppercased()) {
            return nil
        }
        // Relative to the hive, e.g. "Software\Microsoft".
        return parts
    }
}
