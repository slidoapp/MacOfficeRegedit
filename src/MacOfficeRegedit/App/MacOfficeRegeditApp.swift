import SwiftUI

@main
struct MacOfficeRegeditApp: App {
    @StateObject private var store = RegistryStore()
    @StateObject private var officeApps = OfficeAppsMonitor()

    var body: some Scene {
        Window("Registry Editor", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(officeApps)
                .task {
                    openInitialDatabase()
                }
        }
        .commands {
            RegistryCommands(store: store)
        }
    }

    /// `-RegistryDatabasePath <path>` opens another database (e.g. a copy, for testing);
    /// `-RegistryReadOnly YES` opens it read-only; `-RegistryBackupsPath <path>` changes where backups go.
    private func openInitialDatabase() {
        guard store.database == nil, store.openError == nil else {
            return
        }
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: "RegistryBackupsPath") {
            store.backupsDirectory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let path = defaults.string(forKey: "RegistryDatabasePath") {
            store.open(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath), readOnly: defaults.bool(forKey: "RegistryReadOnly"))
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            // Unit tests are hosted in the app; never touch the real registry from them.
            store.open(url: RegistryDatabase.officeRegistryURL, readOnly: defaults.bool(forKey: "RegistryReadOnly"))
        }
    }
}
