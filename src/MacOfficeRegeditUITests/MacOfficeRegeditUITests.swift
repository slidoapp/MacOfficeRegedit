import XCTest

/// UI tests always run against a throwaway database, never the live Office registry.
final class MacOfficeRegeditUITests: XCTestCase {
    private var databaseURL: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("UITest-\(UUID().uuidString).reg")
        try createFixture(at: databaseURL)

        app = XCUIApplication()
        app.launchArguments = [
            "-RegistryDatabasePath", databaseURL.path,
            "-RegistryBackupsPath", backupsURL.path,
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(at: backupsURL)
    }

    private var backupsURL: URL {
        databaseURL.deletingPathExtension().appendingPathExtension("backups")
    }

    func testNavigateAndEditDword() throws {
        let address = app.textFields["addressBar"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.doubleClick()
        address.typeKey("a", modifierFlags: .command)
        address.typeText("HKCU\\Software\\Microsoft\\Office\n")
        XCTAssertEqual(address.value as? String, "Computer\\HKEY_CURRENT_USER\\Software\\Microsoft\\Office")
        attachScreenshot("Navigated")

        let table = valuesTable
        let cell = text("Lcid", in: table)
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(text("0x0000041b (1051)", in: table).exists)
        cell.doubleClick()

        let data = app.textFields["valueData"]
        XCTAssertTrue(data.waitForExistence(timeout: 5))
        attachScreenshot("Edit DWORD")
        data.doubleClick()
        data.typeKey("a", modifierFlags: .command)
        data.typeText("405\n")

        XCTAssertTrue(text("0x00000405 (1029)", in: table).waitForExistence(timeout: 5))
        attachScreenshot("Edited")
    }

    func testEditCommandsActOnFocusedPane() throws {
        let address = app.textFields["addressBar"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.doubleClick()
        address.typeKey("a", modifierFlags: .command)
        address.typeText("Software\\Microsoft\\Office\n")

        let value = text("Lcid", in: valuesTable)
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.click()
        app.menuBars.menuItems["Rename"].click()
        XCTAssertTrue(app.staticTexts["Rename Value"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))

        // Clicking the (already selected) key moves focus to the tree; the value stays selected.
        app.outlines["keysTree"].staticTexts["Office"].click()
        let rename = app.menuBars.menuItems["Rename"]
        XCTAssertTrue(rename.isEnabled, "Rename should be enabled")
        rename.click()
        XCTAssertTrue(app.staticTexts["Rename Key"].waitForExistence(timeout: 5))
        attachScreenshot("Rename Key")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testBinaryEditorOpens() throws {
        let address = app.textFields["addressBar"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.doubleClick()
        address.typeKey("a", modifierFlags: .command)
        address.typeText("Software\\Microsoft\\Office\n")
        let cell = text("Settings", in: valuesTable)
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.doubleClick()
        XCTAssertTrue(app.staticTexts["Edit Binary Value"].waitForExistence(timeout: 5))
        attachScreenshot("Edit Binary")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testFind() throws {
        XCTAssertTrue(app.textFields["addressBar"].waitForExistence(timeout: 5))
        app.typeKey("f", modifierFlags: .command)
        let text = app.textFields["findText"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.typeText("lcid\n")
        XCTAssertTrue(app.staticTexts["2 matches. Double-click to go to a match; ⌘G finds the next one."].waitForExistence(timeout: 5))
        attachScreenshot("Find")
        app.typeKey(.escape, modifierFlags: [])
    }

    func testTreeExpansionAndContextMenu() throws {
        let tree = app.outlines["keysTree"]
        XCTAssertTrue(tree.waitForExistence(timeout: 5))
        let software = tree.staticTexts["Software"]
        XCTAssertTrue(software.waitForExistence(timeout: 5))
        software.rightClick()
        app.menuItems["Expand All"].click()
        XCTAssertTrue(tree.staticTexts["Office"].waitForExistence(timeout: 5))
        tree.staticTexts["Office"].click()
        XCTAssertEqual(app.textFields["addressBar"].value as? String, "Computer\\HKEY_CURRENT_USER\\Software\\Microsoft\\Office")
        attachScreenshot("Tree")
    }

    /// SwiftUI's `Table` is exposed to accessibility as an outline.
    private var valuesTable: XCUIElement {
        app.outlines["valuesTable"]
    }

    /// Table cell text is exposed as the static text's value rather than its label.
    private func text(_ string: String, in element: XCUIElement) -> XCUIElement {
        element.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", string, string)).firstMatch
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func createFixture(at url: URL) throws {
        let utf16JSON = Array("{\"enabled\":true,\"items\":[1,2,3]}".utf16).flatMap { [String(format: "%02X", $0 & 0xff), String(format: "%02X", $0 >> 8)] }.joined()
        let sql = """
            CREATE TABLE HKEY_CURRENT_USER (node_id INTEGER PRIMARY KEY ASC, parent_id, name TEXT COLLATE nocase, write_time, UNIQUE (parent_id, name));
            CREATE TABLE HKEY_CURRENT_USER_values (node_id INTEGER, name TEXT COLLATE nocase, type INTEGER, value, UNIQUE (node_id, name));
            INSERT INTO HKEY_CURRENT_USER VALUES (1, -1, 'Software', X'30E52D090E08DD01');
            INSERT INTO HKEY_CURRENT_USER VALUES (2, 1, 'Microsoft', X'30E52D090E08DD01');
            INSERT INTO HKEY_CURRENT_USER VALUES (3, 2, 'Office', X'30E52D090E08DD01');
            INSERT INTO HKEY_CURRENT_USER VALUES (4, 3, 'Word', X'30E52D090E08DD01');
            INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Lcid', 4, 1051);
            INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Name', 1, 'Office');
            INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Negative', 4, -2144143964);
            INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Big', 11, 9174090607676276057);
            INSERT INTO HKEY_CURRENT_USER_values VALUES (3, 'Settings', 3, X'\(utf16JSON)');
            INSERT INTO HKEY_CURRENT_USER_values VALUES (3, '', 1, 'default');
            INSERT INTO HKEY_CURRENT_USER_values VALUES (4, 'UiLcid', 4, 1051);
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
