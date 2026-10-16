import AppKit

extension RegistryStore {
    static var defaultBackupsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacOfficeRegedit/Backups", isDirectory: true)
    }

    private static let backupsToKeep = 30

    func backup(_ database: RegistryDatabase) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let name = database.url.deletingPathExtension().lastPathComponent
        let timestamp = formatter.string(from: Date())
        var destination = backupsDirectory.appendingPathComponent("\(name)_\(timestamp).reg")
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = backupsDirectory.appendingPathComponent("\(name)_\(timestamp)-\(suffix).reg")
            suffix += 1
        }
        do {
            try database.backup(to: destination)
        } catch {
            throw RegistryError.invalidData("Could not back up the registry before modifying it, so nothing was changed: \(error.localizedDescription)")
        }
        pruneBackups()
    }

    private func pruneBackups() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }
        // Only ever delete files this app created.
        let pattern = try? NSRegularExpression(pattern: #"_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-\d{3}(-\d+)?\.reg$"#)
        let backups = files.filter { url in
            let name = url.lastPathComponent
            return pattern?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }
        let sorted = backups.sorted {
            let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhs > rhs
        }
        sorted.dropFirst(RegistryStore.backupsToKeep).forEach { try? fileManager.removeItem(at: $0) }
    }

    func revealBackups() {
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupsDirectory)
    }
}
