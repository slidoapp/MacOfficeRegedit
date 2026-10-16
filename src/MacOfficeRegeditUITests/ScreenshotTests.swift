import XCTest

/// Captures the README screenshots from a demo registry with made-up values (never a real one, which holds
/// account details). Skipped unless `REGEDIT_SCREENSHOTS` is set; run `scripts/update-screenshots.sh`, which
/// exports the attachments, since the sandboxed test runner can't write to the repository.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var databaseURL: URL!
    private var app: XCUIApplication!

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["REGEDIT_SCREENSHOTS"] != nil else {
            throw XCTSkip("Run scripts/update-screenshots.sh to regenerate the README screenshots")
        }
        continueAfterFailure = false
        // Named like the real registry, since the file name is shown as the window subtitle.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        databaseURL = folder.appendingPathComponent("MicrosoftRegistrationDB.reg")
        try createDemoRegistry(at: databaseURL)

        app = XCUIApplication()
        app.launchArguments = [
            "-RegistryDatabasePath", databaseURL.path,
            "-RegistryBackupsPath", folder.appendingPathComponent("Backups").path,
            "-ApplePersistenceIgnoreState", "YES",
            // Same window size for every capture, regardless of the frame saved by earlier runs.
            "-NSWindow Frame main", "100 100 1180 780 0 0 2560 1600 ",
        ]
        app.launch()
    }

    override func tearDown() async throws {
        app?.terminate()
        if let databaseURL {
            try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
        }
    }

    func testCaptureScreenshots() throws {
        // Main window: the Word options with a value selected.
        navigate(to: "HKEY_CURRENT_USER\\Software\\Microsoft\\Office\\16.0\\Word\\Options")
        let zoom = text("Zoom", in: app.outlines["valuesTable"])
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click()
        save("main-window")

        // DWORD editor.
        zoom.doubleClick()
        XCTAssertTrue(app.textFields["valueData"].waitForExistence(timeout: 5))
        save("edit-dword")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))

        // Binary editor with the UTF-16 text preview of a JSON value.
        navigate(to: "HKCU\\Software\\Microsoft\\Office\\16.0\\Common\\ExperimentConfigs\\Ecs")
        let config = text("Config", in: app.outlines["valuesTable"])
        XCTAssertTrue(config.waitForExistence(timeout: 5))
        config.doubleClick()
        let preview = app.checkBoxes["Show as UTF-16LE text"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.click()
        save("edit-binary")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 5))

        // Find across keys, values and data.
        app.typeKey("f", modifierFlags: .command)
        let find = app.textFields["findText"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.typeKey("a", modifierFlags: .command)
        find.typeText("autosave\n")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '4 matches'")).firstMatch.waitForExistence(timeout: 5))
        save("find")
        app.typeKey(.escape, modifierFlags: [])
    }

    private func navigate(to path: String) {
        let address = app.textFields["addressBar"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.doubleClick()
        address.typeKey("a", modifierFlags: .command)
        address.typeText(path + "\n")
    }

    /// Table cell text is exposed as the static text's value rather than its label.
    private func text(_ string: String, in element: XCUIElement) -> XCUIElement {
        element.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", string, string)).firstMatch
    }

    /// Attaches a screenshot of the window; the attachment name becomes the file name.
    private func save(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func createDemoRegistry(at url: URL) throws {
        // 2026-10-14 09:41 UTC as a little-endian FILETIME.
        let time = "X'005ED31EC05BDD01'"
        let ecs = #"{"ecsVersion":"1.4","configIds":["P-R-1123441-1-4","P-D-1093384-2-8"],"features":{"Word.AutoSaveDefault":true,"Excel.Lambda":true,"Office.NewLook":false},"refreshInterval":3600}"#
        let ecsHex = Array(ecs.utf16).map { String(format: "%02X%02X", $0 & 0xff, $0 >> 8) }.joined()
        let keys: [(Int, Int, String)] = [
            (1, -1, "Software"), (2, 1, "Microsoft"), (3, 2, "Office"), (4, 3, "16.0"),
            (5, 4, "Common"), (6, 5, "General"), (7, 5, "Toolbars"), (8, 5, "ExperimentConfigs"), (9, 8, "Ecs"),
            (10, 5, "LanguageResources"), (11, 4, "Word"), (12, 11, "Options"), (13, 11, "File MRU"),
            (14, 4, "Excel"), (15, 14, "Options"), (16, 4, "PowerPoint"), (17, 16, "Options"),
            (18, 4, "Outlook"), (19, 18, "Preferences"), (20, 2, "AutoUpdate"),
        ]
        let values: [String] = [
            "(6, 'ShownFirstRunOptin', 4, 1)", "(6, 'FirstRunTime', 11, 134364444600000000)",
            "(10, 'UILanguageTag', 1, 'en-us')", "(10, 'EditingLanguageTag', 1, 'en-us')",
            "(9, 'Config', 3, X'\(ecsHex)')", "(9, 'LastUpdate', 11, 134364444600000000)",
            "(12, '', 1, NULL)",
            "(12, 'AutoSaveEnabled', 4, 1)", "(12, 'AutoRecoverTime', 4, 10)", "(12, 'DefaultFormat', 1, 'Docx')",
            "(12, 'DefaultFont', 1, 'Aptos')", "(12, 'Zoom', 4, 120)", "(12, 'ShowFormattingMarks', 4, 0)",
            "(12, 'Lcid', 4, 1033)", "(12, 'LastUpdateCheck', 11, 134364444600000000)",
            "(12, 'WindowPlacement', 3, X'2C0000000200000003000000FFFFFFFFFFFFFFFF8A0000005A000000F20500003C040000')",
            "(12, 'TemplatesPath', 1, '~/Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized')",
            "(13, 'Max Display', 4, 25)",
            "(15, 'AutoSaveEnabled', 4, 1)", "(15, 'DefaultFormat', 4, 51)", "(15, 'Zoom', 4, 100)",
            "(17, 'AutoSaveEnabled', 4, 1)", "(17, 'DefaultView', 4, 0)",
            "(19, 'ReadingPane', 4, 1)", "(19, 'ConversationView', 4, 1)",
            "(20, 'ChannelName', 1, 'Current')", "(20, 'HowToCheck', 1, 'AutomaticDownload')",
        ]
        let sql = """
            CREATE TABLE HKEY_CURRENT_USER (node_id INTEGER PRIMARY KEY ASC, parent_id, name TEXT COLLATE nocase, write_time, UNIQUE (parent_id, name));
            CREATE TABLE HKEY_CURRENT_USER_values (node_id INTEGER, name TEXT COLLATE nocase, type INTEGER, value, UNIQUE (node_id, name));
            INSERT INTO HKEY_CURRENT_USER VALUES \(keys.map { "(\($0.0), \($0.1), '\($0.2)', \(time))" }.joined(separator: ", "));
            INSERT INTO HKEY_CURRENT_USER_values VALUES \(values.joined(separator: ", "));
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, sql]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
