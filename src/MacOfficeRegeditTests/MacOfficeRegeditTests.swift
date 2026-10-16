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

    func testValueIdsMatchSQLiteNameComparison() {
        let nfc = RegistryValue(keyId: 1, name: "caf\u{e9}", type: .REG_SZ, data: .none)
        let nfd = RegistryValue(keyId: 1, name: "cafe\u{301}", type: .REG_SZ, data: .none)
        XCTAssertNotEqual(nfc.id, nfd.id)
        XCTAssertEqual(RegistryValue.ID(keyId: 1, name: "Lcid"), RegistryValue.ID(keyId: 1, name: "LCID"))
        // SQLite's NOCASE folds ASCII only.
        XCTAssertNotEqual(RegistryValue.ID(keyId: 1, name: "Č"), RegistryValue.ID(keyId: 1, name: "č"))
    }
}

@MainActor
final class RegistryStoreTests: XCTestCase {
    private var url: URL!
    private var store: RegistryStore!

    override func setUp() async throws {
        url = try makeTestDatabase()
        store = RegistryStore()
        store.open(url: url)
    }

    override func tearDown() async throws {
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
}
