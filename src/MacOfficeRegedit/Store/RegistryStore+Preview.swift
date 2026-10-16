#if DEBUG
import Foundation
import SQLite

extension RegistryStore {
    /// A store with a small demo registry (made-up values), for SwiftUI previews.
    static func preview(selecting path: String = "Software\\Microsoft\\Office\\16.0\\Word\\Options") -> RegistryStore {
        let store = RegistryStore()
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Preview-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("MicrosoftRegistrationDB.reg")
            try Connection(url.path).execute(previewSQL)
            store.backupsDirectory = folder.appendingPathComponent("Backups")
            store.open(url: url)
            store.navigate(to: path)
        } catch {
            store.show(error)
        }
        return store
    }

    private static let previewSQL = """
        CREATE TABLE HKEY_CURRENT_USER (node_id INTEGER PRIMARY KEY ASC, parent_id, name TEXT COLLATE nocase, write_time, UNIQUE (parent_id, name));
        CREATE TABLE HKEY_CURRENT_USER_values (node_id INTEGER, name TEXT COLLATE nocase, type INTEGER, value, UNIQUE (node_id, name));
        INSERT INTO HKEY_CURRENT_USER VALUES
            (1, -1, 'Software', X'005ED31EC05BDD01'), (2, 1, 'Microsoft', X'005ED31EC05BDD01'),
            (3, 2, 'Office', X'005ED31EC05BDD01'), (4, 3, '16.0', X'005ED31EC05BDD01'),
            (5, 4, 'Common', X'005ED31EC05BDD01'), (6, 5, 'General', X'005ED31EC05BDD01'),
            (7, 4, 'Word', X'005ED31EC05BDD01'), (8, 7, 'Options', X'005ED31EC05BDD01'),
            (9, 4, 'Excel', X'005ED31EC05BDD01'), (10, 9, 'Options', X'005ED31EC05BDD01');
        INSERT INTO HKEY_CURRENT_USER_values VALUES
            (6, 'ShownFirstRunOptin', 4, 1),
            (8, '', 1, NULL), (8, 'AutoSaveEnabled', 4, 1), (8, 'DefaultFormat', 1, 'Docx'),
            (8, 'DefaultFont', 1, 'Aptos'), (8, 'Zoom', 4, 120), (8, 'LastUpdateCheck', 11, 134364444600000000),
            (8, 'WindowPlacement', 3, X'2C0000000200000003000000FFFFFFFF'),
            (10, 'AutoSaveEnabled', 4, 1), (10, 'Zoom', 4, 100);
        """
}
#endif
