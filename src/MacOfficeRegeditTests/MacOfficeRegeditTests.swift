import SQLite
import XCTest
@testable import MacOfficeRegedit

/// Creates an empty database with the schema Office uses.
func makeTestDatabase(file: StaticString = #filePath) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MacOfficeRegeditTests-\(UUID().uuidString).reg")
    let connection = try Connection(url.path)
    try connection.execute("""
        CREATE TABLE HKEY_CURRENT_USER (node_id INTEGER PRIMARY KEY ASC, parent_id, name TEXT COLLATE nocase, write_time, UNIQUE (parent_id, name));
        CREATE TABLE HKEY_CURRENT_USER_values (node_id INTEGER, name TEXT COLLATE nocase, type INTEGER, value, UNIQUE (node_id, name));
        CREATE TABLE db_metadata (schema_ver INTEGER, min_schema_ver INTEGER, cache_table BINARY);
        INSERT INTO db_metadata VALUES (6, 6, NULL);
        INSERT INTO HKEY_CURRENT_USER VALUES (1, -1, 'Software', X'30E52D090E08DD01');
        INSERT INTO HKEY_CURRENT_USER VALUES (2, 1, 'Microsoft', X'30E52D090E08DD01');
        INSERT INTO HKEY_CURRENT_USER VALUES (3, 2, 'Office', X'30E52D090E08DD01');
        INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Name', 1, 'Office');
        INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Negative', 4, -2144143964);
        INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Big', 11, 9174090607676276057);
        INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Blob', 3, X'7B002200');
        INSERT INTO HKEY_CURRENT_USER_values VALUES (3, '', 1, 'default');
        INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Unset', 1, NULL);
        """)
    return url
}

final class ModelTests: XCTestCase {
    func testFileTimeDecodesOfficeWriteTime() throws {
        let date = try XCTUnwrap(FileTime.date(fromBytes: [0x30, 0xE5, 0x2D, 0x09, 0x0E, 0x08, 0xDD, 0x01]))
        XCTAssertEqual(date.timeIntervalSince1970, 1_782_768_426.755, accuracy: 0.001)
    }

    func testFileTimeRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.5)
        let decoded = try XCTUnwrap(FileTime.date(fromBytes: FileTime.bytes(from: date)))
        XCTAssertEqual(decoded.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.000_001)
    }

    func testFileTimeRejectsInvalidBytes() {
        XCTAssertNil(FileTime.date(fromBytes: [1, 2, 3]))
        XCTAssertNil(FileTime.date(fromBytes: [0, 0, 0, 0, 0, 0, 0, 0]))
    }

    func testPathParsing() {
        XCTAssertEqual(RegistryPath.components(of: "Computer\\HKEY_CURRENT_USER\\Software\\Microsoft"), ["Software", "Microsoft"])
        XCTAssertEqual(RegistryPath.components(of: "hkcu/software//microsoft/"), ["software", "microsoft"])
        XCTAssertEqual(RegistryPath.components(of: "Software\\Microsoft"), ["Software", "Microsoft"])
        XCTAssertEqual(RegistryPath.components(of: "Computer"), [])
        XCTAssertEqual(RegistryPath.components(of: "HKEY_CURRENT_USER"), [])
        XCTAssertNil(RegistryPath.components(of: "HKEY_LOCAL_MACHINE\\Software"))
        XCTAssertNil(RegistryPath.components(of: "HKLM\\Software"))
        XCTAssertEqual(RegistryPath.display(["Software"]), "Computer\\HKEY_CURRENT_USER\\Software")
        XCTAssertEqual(RegistryPath.qualified(["Software"]), "HKEY_CURRENT_USER\\Software")
    }

    func testDisplayStrings() {
        XCTAssertEqual(RegistryData.dword(0x8032F5A4).displayString, "0x8032f5a4 (2150823332)")
        XCTAssertEqual(RegistryData.qword(9_174_090_607_676_276_057).displayString, "0x7f50eacd1fcabd59 (9174090607676276057)")
        XCTAssertEqual(RegistryData.qword(UInt64.max).displayString, "0xffffffffffffffff (18446744073709551615)")
        XCTAssertEqual(RegistryData.binary([0x7B, 0x00]).displayString, "7b 00")
        XCTAssertEqual(RegistryData.binary([]).displayString, "(zero-length binary value)")
        XCTAssertEqual(RegistryData.none.displayString, "(value not set)")
        XCTAssertEqual(RegistryData.multiString(["a", "b"]).displayString, "a b")
    }

    /// Ported from PR #1: hex rendering must keep all 32 bits of a DWORD and the upper 32 bits of a QWORD.
    func testDwordHexRenderingPreservesAll32Bits() {
        let data = RegistryDatabase.data(from: Int64(0x89abcdef), type: .REG_DWORD)
        XCTAssertEqual(data.displayString, "0x89abcdef (2309737967)")
    }

    func testQwordHexRenderingPreservesUpper32Bits() {
        let data = RegistryDatabase.data(from: Int64(0x0123456789abcdef), type: .REG_QWORD)
        XCTAssertEqual(data.displayString, "0x0123456789abcdef (81985529216486895)")
    }

    func testUTF16Helpers() {
        let bytes = RegistryData.multiStringBytes(["ab", "č"])
        XCTAssertEqual(bytes, [0x61, 0, 0x62, 0, 0, 0, 0x0D, 0x01, 0, 0, 0, 0])
        XCTAssertEqual(RegistryData.multiString(fromUTF16LE: bytes), ["ab", "č"])
        XCTAssertEqual(RegistryData.string(fromUTF16LE: RegistryData.utf16LEBytes("hi", terminated: true)), "hi")
    }

    func testStorageEncodingMatchesOffice() {
        XCTAssertEqual(RegistryDatabase.binding(for: .dword(0x8032F5A4)) as? Int64, -2_144_143_964)
        XCTAssertEqual(RegistryDatabase.data(from: Int64(-2_144_143_964), type: .REG_DWORD), .dword(0x8032F5A4))
        XCTAssertEqual(RegistryDatabase.binding(for: .qword(UInt64.max)) as? Int64, -1)
        XCTAssertEqual(RegistryDatabase.data(from: Int64(-1), type: .REG_QWORD), .qword(UInt64.max))
        XCTAssertEqual(RegistryDatabase.data(from: nil, type: .REG_SZ), RegistryData.none)
        XCTAssertEqual(RegistryDatabase.data(from: "a\0b", type: .REG_MULTI_SZ), .multiString(["a", "b"]))
        let multi = RegistryDatabase.binding(for: .multiString(["a", "b"]))
        XCTAssertEqual(RegistryDatabase.data(from: multi, type: .REG_MULTI_SZ), .multiString(["a", "b"]))
    }

    func testNumericEditorParsing() {
        let dwordMax = UInt64(UInt32.max)
        XCTAssertEqual(EditNumericValueView.parse("ff", base: .hexadecimal, maximum: dwordMax), 255)
        XCTAssertEqual(EditNumericValueView.parse("0xFF", base: .hexadecimal, maximum: dwordMax), 255)
        XCTAssertEqual(EditNumericValueView.parse("", base: .decimal, maximum: dwordMax), 0)
        XCTAssertEqual(EditNumericValueView.parse("4294967295", base: .decimal, maximum: dwordMax), dwordMax)
        XCTAssertNil(EditNumericValueView.parse("4294967296", base: .decimal, maximum: dwordMax))
        XCTAssertNil(EditNumericValueView.parse("1ffffffff", base: .hexadecimal, maximum: dwordMax))
        XCTAssertNil(EditNumericValueView.parse("12g", base: .hexadecimal, maximum: dwordMax))
        XCTAssertNil(EditNumericValueView.parse("-1", base: .decimal, maximum: dwordMax))
        XCTAssertEqual(EditNumericValueView.parse("ffffffffffffffff", base: .hexadecimal, maximum: .max), .max)
    }

    func testKeyNameValidation() {
        XCTAssertThrowsError(try RegistryKey.validateName(""))
        XCTAssertThrowsError(try RegistryKey.validateName("a\\b"))
        XCTAssertNoThrow(try RegistryKey.validateName("16.0"))
    }
}

final class RegistryDatabaseTests: XCTestCase {
    private var url: URL!
    private var database: RegistryDatabase!

    override func setUpWithError() throws {
        url = try makeTestDatabase()
        database = try RegistryDatabase(url: url)
    }

    override func tearDownWithError() throws {
        database = nil
        try? FileManager.default.removeItem(at: url)
    }

    func testReadsKeysAndValues() throws {
        let keys = try database.fetchAllKeys()
        XCTAssertEqual(keys.map(\.name).sorted(), ["Microsoft", "Office", "Software"])
        XCTAssertNotNil(keys.first?.writeTime)

        let values = Dictionary(uniqueKeysWithValues: try database.fetchValues(keyId: 3).map { ($0.name, $0) })
        XCTAssertEqual(values["Name"]?.data, .string("Office"))
        XCTAssertEqual(values["Negative"]?.data, .dword(0x8032F5A4))
        XCTAssertEqual(values["Big"]?.data, .qword(9_174_090_607_676_276_057))
        XCTAssertEqual(values["Blob"]?.data, .binary([0x7B, 0, 0x22, 0]))
        XCTAssertEqual(values[""]?.data, .string("default"))
        XCTAssertEqual(values["Unset"]?.data, RegistryData.none)
    }

    func testRejectsNonRegistryDatabase() throws {
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: other) }
        try Connection(other.path).execute("CREATE TABLE foo (a)")
        XCTAssertThrowsError(try RegistryDatabase(url: other))
        XCTAssertThrowsError(try RegistryDatabase(url: other.appendingPathExtension("missing"))) { error in
            guard case RegistryError.databaseNotFound = error else {
                return XCTFail("Unexpected error \(error)")
            }
        }
    }

    func testCreateRenameAndDeleteKeys() throws {
        let key = try database.createKey(named: "Excel", parentId: 3)
        XCTAssertEqual(try database.childKeyId(parentId: 3, name: "excel"), key.id)
        XCTAssertThrowsError(try database.createKey(named: "EXCEL", parentId: 3)) {
            XCTAssertEqual($0 as? RegistryError, .keyAlreadyExists("EXCEL"))
        }
        XCTAssertThrowsError(try database.createKey(named: "x", parentId: 999))

        let top = try database.createKey(named: "Top", parentId: RegistryKey.rootId)
        XCTAssertEqual(top.parentId, RegistryKey.rootId)

        try database.renameKey(id: key.id, to: "Word")
        XCTAssertNil(try database.childKeyId(parentId: 3, name: "Excel"))
        XCTAssertEqual(try database.childKeyId(parentId: 3, name: "Word"), key.id)
        // Changing only the case of the name is allowed.
        try database.renameKey(id: key.id, to: "WORD")
        XCTAssertThrowsError(try database.renameKey(id: RegistryKey.rootId, to: "x"))

        try database.deleteKey(id: 1)
        XCTAssertEqual(try database.fetchAllKeys().map(\.name), ["Top"])
        XCTAssertTrue(try database.fetchAllValues().isEmpty)
    }

    func testCreateKeyPath() throws {
        let id = try database.createKeyPath(["software", "Microsoft", "New", "Deep"])
        let keys = try database.fetchAllKeys()
        XCTAssertEqual(keys.count, 5)
        XCTAssertEqual(keys.first { $0.id == id }?.name, "Deep")
        XCTAssertEqual(try database.createKeyPath([]), RegistryKey.rootId)
    }

    func testValueOperations() throws {
        let value = RegistryValue(keyId: 3, name: "Count", type: .REG_DWORD, data: .dword(0xFFFF_FFFF))
        try database.insertValue(value)
        XCTAssertEqual(try database.fetchValue(keyId: 3, name: "count")?.data, .dword(0xFFFF_FFFF))
        XCTAssertThrowsError(try database.insertValue(value)) {
            XCTAssertEqual($0 as? RegistryError, .valueAlreadyExists("Count"))
        }

        var updated = value
        updated.data = .dword(7)
        try database.updateValue(updated, originalName: "Count")
        XCTAssertEqual(try database.fetchValue(keyId: 3, name: "Count")?.data, .dword(7))

        try database.renameValue(keyId: 3, from: "Count", to: "Total")
        XCTAssertNil(try database.fetchValue(keyId: 3, name: "Count"))
        XCTAssertEqual(try database.fetchValue(keyId: 3, name: "Total")?.data, .dword(7))
        XCTAssertThrowsError(try database.renameValue(keyId: 3, from: "Total", to: "name"))

        try database.deleteValue(keyId: 3, name: "Total")
        XCTAssertNil(try database.fetchValue(keyId: 3, name: "Total"))
        XCTAssertThrowsError(try database.deleteValue(keyId: 3, name: "Total"))

        XCTAssertThrowsError(try database.insertValue(RegistryValue(keyId: RegistryKey.rootId, name: "x", type: .REG_SZ, data: .string(""))))
        XCTAssertThrowsError(try database.insertValue(RegistryValue(keyId: 999, name: "x", type: .REG_SZ, data: .string(""))))
    }

    func testAllDataTypesRoundTrip() throws {
        let samples: [RegistryValue] = [
            .init(keyId: 2, name: "sz", type: .REG_SZ, data: .string("Příliš žluťoučký")),
            .init(keyId: 2, name: "expand", type: .REG_EXPAND_SZ, data: .string("%HOME%")),
            .init(keyId: 2, name: "multi", type: .REG_MULTI_SZ, data: .multiString(["a", "b c"])),
            .init(keyId: 2, name: "dword", type: .REG_DWORD, data: .dword(0x8000_0000)),
            .init(keyId: 2, name: "qword", type: .REG_QWORD, data: .qword(0xFFFF_FFFF_FFFF_FFFE)),
            .init(keyId: 2, name: "bin", type: .REG_BINARY, data: .binary([0, 1, 255])),
            .init(keyId: 2, name: "none", type: .REG_SZ, data: .none),
        ]
        for sample in samples {
            try database.insertValue(sample)
        }
        let reopened = try RegistryDatabase(url: url)
        for sample in samples {
            XCTAssertEqual(try reopened.fetchValue(keyId: 2, name: sample.name), sample)
        }
    }

    func testWritesTouchKeyWriteTime() throws {
        let before = try XCTUnwrap(try database.fetchAllKeys().first { $0.id == 3 }?.writeTime)
        try database.insertValue(RegistryValue(keyId: 3, name: "x", type: .REG_SZ, data: .string("")))
        let after = try XCTUnwrap(try database.fetchAllKeys().first { $0.id == 3 }?.writeTime)
        XCTAssertGreaterThan(after, before)
        XCTAssertEqual(after.timeIntervalSinceNow, 0, accuracy: 60)
    }

    func testFailedTransactionRollsBackAndLeavesDatabaseUsable() throws {
        XCTAssertThrowsError(try database.transaction {
            try database.createKey(named: "Temp", parentId: 3)
            try database.createKey(named: "Temp", parentId: 3)
        })
        XCTAssertNil(try database.childKeyId(parentId: 3, name: "Temp"))

        // A later write must be committed (i.e. no transaction was left open).
        try database.createKey(named: "After", parentId: 3)
        let reopened = try RegistryDatabase(url: url, readOnly: true)
        XCTAssertNotNil(try reopened.childKeyId(parentId: 3, name: "After"))
    }

    func testTextWithNULsSurvives() throws {
        // Office could store REG_MULTI_SZ as TEXT with NUL separators; SQLite.swift would cut it at the first NUL.
        try Connection(url.path).run("INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'MultiText', 7, CAST(X'6100620000' AS TEXT))")
        XCTAssertEqual(try database.fetchValue(keyId: 3, name: "MultiText")?.data, .multiString(["a", "b"]))

        let value = RegistryValue(keyId: 3, name: "WithNUL", type: .REG_SZ, data: .string("a\0b"))
        try database.insertValue(value)
        XCTAssertEqual(try database.fetchValue(keyId: 3, name: "WithNUL")?.data, .string("a\0b"))
        let storageClass = try Connection(url.path).scalar("SELECT typeof(value) FROM HKEY_CURRENT_USER_values WHERE name = 'WithNUL'") as? String
        XCTAssertEqual(storageClass, "text")
    }

    func testFailedCommitWhileLockedDoesNotLeaveTransactionOpen() throws {
        let database = try RegistryDatabase(url: url, busyTimeout: 0.2)
        let office = try Connection(url.path)
        // Another process (Office) holds a read lock, so our COMMIT cannot get an exclusive lock.
        try office.run("BEGIN")
        _ = try office.scalar("SELECT COUNT(*) FROM HKEY_CURRENT_USER")
        XCTAssertThrowsError(try database.createKey(named: "Blocked", parentId: 3))
        try office.run("COMMIT")

        // Office must be able to write again, i.e. we released our locks.
        try office.run("INSERT INTO HKEY_CURRENT_USER (parent_id, name) VALUES (3, 'ByOffice')")
        XCTAssertNil(try database.childKeyId(parentId: 3, name: "Blocked"))

        // And our next write must actually be committed, not nested in a dangling transaction.
        try database.createKey(named: "After", parentId: 3)
        XCTAssertNotNil(try Connection(url.path).scalar("SELECT node_id FROM HKEY_CURRENT_USER WHERE name = 'After'"))
    }

    func testWriteWaitsForOfficeWriteLock() throws {
        let office = try Connection(url.path)
        try office.run("BEGIN IMMEDIATE")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            _ = try? office.run("COMMIT")
        }
        // busyTimeout (5 s) applies because the write lock is requested up front.
        try database.createKey(named: "Waited", parentId: 3)
        XCTAssertNotNil(try database.childKeyId(parentId: 3, name: "Waited"))
    }

    func testVerifyKeyDetectsReusedId() throws {
        let office = try RegistryDatabase(url: url)
        let stale = try XCTUnwrap(try database.fetchKey(id: 3))
        try office.deleteKey(id: 3)
        let replacement = try office.createKey(named: "Unrelated", parentId: 1)
        XCTAssertEqual(replacement.id, 3, "SQLite reuses the highest rowid")
        XCTAssertThrowsError(try database.verifyKey(stale))
    }

    func testValueIdsMatchSQLiteNameComparison() {
        let nfc = RegistryValue(keyId: 1, name: "caf\u{e9}", type: .REG_SZ, data: .none)
        let nfd = RegistryValue(keyId: 1, name: "cafe\u{301}", type: .REG_SZ, data: .none)
        XCTAssertNotEqual(nfc.id, nfd.id)
        XCTAssertEqual(RegistryValue.ID(keyId: 1, name: "Lcid"), RegistryValue.ID(keyId: 1, name: "LCID"))
        // SQLite's NOCASE folds ASCII only.
        XCTAssertNotEqual(RegistryValue.ID(keyId: 1, name: "Č"), RegistryValue.ID(keyId: 1, name: "č"))
    }

    func testReadOnlyRejectsWrites() throws {
        let readOnly = try RegistryDatabase(url: url, readOnly: true)
        XCTAssertTrue(readOnly.isReadOnly)
        XCTAssertThrowsError(try readOnly.createKey(named: "x", parentId: 3)) {
            XCTAssertEqual($0 as? RegistryError, .readOnly)
        }
    }

    func testBackupCreatesConsistentCopy() throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString)/copy.reg")
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
        try database.backup(to: destination)
        let copy = try RegistryDatabase(url: destination, readOnly: true)
        XCTAssertEqual(try copy.fetchAllKeys().count, 3)
        XCTAssertEqual(try copy.fetchAllValues().count, 6)
    }
}

@MainActor
final class RegistryStoreTests: XCTestCase {
    private var url: URL!
    private var store: RegistryStore!

    override func setUp() async throws {
        url = try makeTestDatabase()
        store = RegistryStore()
        store.backupsDirectory = url.deletingPathExtension().appendingPathExtension("backups")
        store.open(url: url)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: store.backupsDirectory)
        store = nil
        try? FileManager.default.removeItem(at: url)
    }

    func testOpenBuildsTreeAndSelectsRoot() {
        XCTAssertNil(store.openError)
        XCTAssertEqual(store.selectedKeyId, RegistryKey.rootId)
        XCTAssertEqual(store.children(of: RegistryKey.rootId).map(\.name), ["Software"])
        XCTAssertEqual(store.path(of: 3), "Computer\\HKEY_CURRENT_USER\\Software\\Microsoft\\Office")
        XCTAssertTrue(store.values.isEmpty)
    }

    func testOpenMissingDatabaseReportsError() {
        store.open(url: url.appendingPathExtension("missing"))
        XCTAssertNotNil(store.openError)
        XCTAssertNil(store.database)
    }

    func testNavigateExpandsAncestorsAndLoadsValues() {
        XCTAssertTrue(store.navigate(to: "hkcu\\software\\MICROSOFT\\office"))
        XCTAssertEqual(store.selectedKeyId, 3)
        XCTAssertTrue(store.expandedKeyIds.isSuperset(of: [RegistryKey.rootId, 1, 2]))
        XCTAssertEqual(store.addressText, "Computer\\HKEY_CURRENT_USER\\Software\\Microsoft\\Office")
        // Default value first, then by name.
        XCTAssertEqual(store.values.map(\.name), ["", "Big", "Blob", "Name", "Negative", "Unset"])
        XCTAssertFalse(store.navigate(to: "Software\\Nope"))
        XCTAssertFalse(store.navigate(to: "HKLM\\Software"))
    }

    func testEditingFlow() throws {
        store.navigate(to: "Software\\Microsoft")
        try store.createKey(named: "Excel", parentId: 2)
        let excel = try XCTUnwrap(store.selectedKey)
        XCTAssertEqual(excel.name, "Excel")
        XCTAssertEqual(store.children(of: 2).map(\.name), ["Excel", "Office"])

        try store.saveValue(RegistryValue(keyId: excel.id, name: "Zoom", type: .REG_DWORD, data: .dword(100)), originalName: nil)
        XCTAssertEqual(store.values.map(\.name), ["Zoom"])
        try store.renameValue(store.values[0], to: "Scale")
        XCTAssertEqual(store.values.map(\.name), ["Scale"])

        try store.renameKey(excel, to: "PowerPoint")
        XCTAssertEqual(store.addressText, "Computer\\HKEY_CURRENT_USER\\Software\\Microsoft\\PowerPoint")

        store.confirmDeletion(.key(try XCTUnwrap(store.selectedKey)))
        XCTAssertEqual(store.selectedKeyId, 2)
        XCTAssertEqual(store.children(of: 2).map(\.name), ["Office"])
        XCTAssertNil(store.alertMessage)
        // Exactly one backup is made per opened database, before the first change.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.backupsDirectory.path).count, 1)
    }

    func testStaleDialogCannotModifyReusedKey() throws {
        store.navigate(to: "Software\\Microsoft\\Office")
        let stale = try XCTUnwrap(store.selectedKey)
        // Office deletes the key and creates another one that gets the same id, before we reload.
        let office = try RegistryDatabase(url: url)
        try office.deleteKey(id: stale.id)
        XCTAssertEqual(try office.createKey(named: "Unrelated", parentId: 1).id, stale.id)

        XCTAssertThrowsError(try store.renameKey(stale, to: "Renamed"))
        XCTAssertThrowsError(try store.saveValue(RegistryValue(keyId: stale.id, name: "x", type: .REG_SZ, data: .string("")), originalName: nil))
        store.confirmDeletion(.key(stale))
        XCTAssertNotNil(store.alertMessage)
        XCTAssertEqual(try office.fetchKey(id: stale.id)?.name, "Unrelated")
    }

    func testDeleteWithValuesPaneFocusedNeverDeletesKey() {
        store.navigate(to: "Software\\Microsoft\\Office")
        store.focusedPane = .values
        store.selectedValueIds = []
        store.beginDelete()
        XCTAssertNil(store.pendingDeletion)
        store.focusedPane = .keys
        store.beginDelete()
        guard case .key(let key) = store.pendingDeletion else {
            return XCTFail("Expected a key deletion")
        }
        XCTAssertEqual(key.name, "Office")
    }

    func testBackupPruningKeepsForeignFiles() throws {
        try FileManager.default.createDirectory(at: store.backupsDirectory, withIntermediateDirectories: true)
        let foreign = store.backupsDirectory.appendingPathComponent("notes.txt")
        try Data().write(to: foreign)
        for index in 0..<35 {
            let old = store.backupsDirectory.appendingPathComponent("Old_2020-01-01_00-00-00-\(String(format: "%03d", index)).reg")
            try Data().write(to: old)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: old.path)
        }
        try store.createKey(named: "Trigger", parentId: 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.backupsDirectory.path)
        XCTAssertTrue(files.contains("notes.txt"))
        XCTAssertEqual(files.filter { $0.hasSuffix(".reg") }.count, 30)
    }
}
