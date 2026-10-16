import XCTest
@testable import MacOfficeRegedit

final class RegFileTests: XCTestCase {
    private typealias Key = RegFileDocument.Key
    private typealias Value = RegFileDocument.Value

    private static let settingsBytes: [UInt8] = [
        0x30, 0x00, 0x00, 0x00, 0xfe, 0xff, 0xff, 0xff, 0x02, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00,
        0x3e, 0x00, 0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xd0, 0x03, 0x00, 0x00,
        0x80, 0x07, 0x00, 0x00, 0xf8, 0x03, 0x00, 0x00, 0x60, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
    ]

    private static let settingsLine = """
        "Settings"=hex:30,00,00,00,fe,ff,ff,ff,02,00,00,00,03,00,00,00,3e,00,00,00,28,\\\r
          00,00,00,00,00,00,00,d0,03,00,00,80,07,00,00,f8,03,00,00,60,00,00,00,01,00,\\\r
          00,00
        """

    private static let allTypesDocument = RegFileDocument(keys: [
        Key(path: ["Software", "Test"], isDeletion: false, values: [
            Value(name: "", type: .REG_SZ, data: .string("Default")),
            Value(name: "String", type: .REG_SZ, data: .string("Hello \"World\" C:\\Path\\")),
            Value(name: "Dword", type: .REG_DWORD, data: .dword(42)),
            Value(name: "Qword", type: .REG_QWORD, data: .qword(0x0102_0304_0506_0708)),
            Value(name: "Binary", type: .REG_BINARY, data: .binary([0xde, 0xad, 0xbe, 0xef])),
            Value(name: "EmptyBinary", type: .REG_BINARY, data: .binary([])),
            Value(name: "Expand", type: .REG_EXPAND_SZ, data: .string("%A%")),
            Value(name: "Multi", type: .REG_MULTI_SZ, data: .multiString(["a", "b"])),
            Value(name: "EmptyMulti", type: .REG_MULTI_SZ, data: .multiString([])),
            Value(name: "None", type: .REG_NONE, data: .binary([0x01, 0x02])),
            Value(name: "Null", type: .REG_SZ, data: RegistryData.none),
            Value(name: "NullQword", type: .REG_QWORD, data: RegistryData.none),
            Value(name: "Big", type: .REG_DWORD_BIG_ENDIAN, data: .dword(0x0102_0304)),
            Value(name: "Resource", type: .REG_RESOURCE_LIST, data: .binary([0xff])),
            Value(name: "Requirements", type: .REG_RESOURCE_REQUIREMENTS_LIST, data: .binary([0x00])),
            Value(name: "Lines", type: .REG_SZ, data: .string("a\nb")),
            Value(name: "Na\"me\\", type: .REG_SZ, data: .string("")),
            Value(name: "Deleted", type: .REG_NONE, data: nil),
        ]),
        Key(path: ["Software", "Old"], isDeletion: true, values: []),
        Key(path: [], isDeletion: false, values: [
            Value(name: "Root", type: .REG_DWORD, data: .dword(0xffff_ffff)),
        ]),
    ])

    private static let allTypesText = [
        "Windows Registry Editor Version 5.00",
        "",
        "[HKEY_CURRENT_USER\\Software\\Test]",
        "@=\"Default\"",
        "\"String\"=\"Hello \\\"World\\\" C:\\\\Path\\\\\"",
        "\"Dword\"=dword:0000002a",
        "\"Qword\"=hex(b):08,07,06,05,04,03,02,01",
        "\"Binary\"=hex:de,ad,be,ef",
        "\"EmptyBinary\"=hex:",
        "\"Expand\"=hex(2):25,00,41,00,25,00,00,00",
        "\"Multi\"=hex(7):61,00,00,00,62,00,00,00,00,00",
        "\"EmptyMulti\"=hex(7):00,00",
        "\"None\"=hex(0):01,02",
        "\"Null\"=hex(1):",
        "\"NullQword\"=hex(b):",
        "\"Big\"=hex(5):01,02,03,04",
        "\"Resource\"=hex(8):ff",
        "\"Requirements\"=hex(a):00",
        "\"Lines\"=hex(1):61,00,0a,00,62,00,00,00",
        "\"Na\\\"me\\\\\"=\"\"",
        "\"Deleted\"=-",
        "",
        "[-HKEY_CURRENT_USER\\Software\\Old]",
        "",
        "[HKEY_CURRENT_USER]",
        "\"Root\"=dword:ffffffff",
        "",
        "",
    ].joined(separator: "\r\n")

    private static let export = """
        Windows Registry Editor Version 5.00

        ; Exported from Microsoft Office
        [HKEY_CURRENT_USER\\Software\\Microsoft\\Office\\16.0\\Common]
        @="Default value"
        "Path"="C:\\\\Program Files\\\\Microsoft Office\\\\"
        "Quote"="say \\"hi\\""
        "Count"=dword:0000000A
        "Big"=hex(b):00,10,00,00,00,00,00,00
        "Settings"=hex:30,00,00,00,fe,ff,ff,ff,02,00,00,00,03,00,00,00,3e,00,00,00,28,\\
          00,00,00,00,00,00,00,d0,03,00,00,80,07,00,00,f8,03,00,00,60,00,00,00,01,00,\\
          00,00
        "Expand"=hex(2):25,00,54,00,45,00,4d,00,50,00,25,00,00,00
        "Multi"=hex(7):6f,00,6e,00,65,00,00,00,74,00,77,00,6f,00,00,00,00,00
        "Obsolete"=-
           "Indented" = dword:1

        [-HKEY_CURRENT_USER\\Software\\Microsoft\\Office\\16.0\\Old]

        [hkcu\\Software\\Alias]
        "Empty"=""
        "LegacyString"=hex(1):41,00,00,00

        """

    private static let exportDocument = RegFileDocument(keys: [
        Key(path: ["Software", "Microsoft", "Office", "16.0", "Common"], isDeletion: false, values: [
            Value(name: "", type: .REG_SZ, data: .string("Default value")),
            Value(name: "Path", type: .REG_SZ, data: .string("C:\\Program Files\\Microsoft Office\\")),
            Value(name: "Quote", type: .REG_SZ, data: .string("say \"hi\"")),
            Value(name: "Count", type: .REG_DWORD, data: .dword(10)),
            Value(name: "Big", type: .REG_QWORD, data: .qword(0x1000)),
            Value(name: "Settings", type: .REG_BINARY, data: .binary(settingsBytes)),
            Value(name: "Expand", type: .REG_EXPAND_SZ, data: .string("%TEMP%")),
            Value(name: "Multi", type: .REG_MULTI_SZ, data: .multiString(["one", "two"])),
            Value(name: "Obsolete", type: .REG_NONE, data: nil),
            Value(name: "Indented", type: .REG_DWORD, data: .dword(1)),
        ]),
        Key(path: ["Software", "Microsoft", "Office", "16.0", "Old"], isDeletion: true, values: []),
        Key(path: ["Software", "Alias"], isDeletion: false, values: [
            Value(name: "Empty", type: .REG_SZ, data: .string("")),
            Value(name: "LegacyString", type: .REG_SZ, data: .string("A")),
        ]),
    ])

    private func document(_ values: Value...) -> RegFileDocument {
        RegFileDocument(keys: [Key(path: ["Software"], isDeletion: false, values: values)])
    }

    private func parseError(_ body: String) -> RegFileError? {
        do {
            _ = try RegFile.parse(RegFile.header + "\n\n" + body)
            return nil
        } catch {
            return error as? RegFileError
        }
    }

    // MARK: - Serialization

    func testSerializeAllTypes() {
        XCTAssertEqual(RegFile.serialize(Self.allTypesDocument), Self.allTypesText)
    }

    func testSerializeEmptyDocument() {
        XCTAssertEqual(RegFile.serialize(RegFileDocument(keys: [])), "Windows Registry Editor Version 5.00\r\n\r\n")
    }

    func testSerializeWrapsLikeRegedit() {
        let text = RegFile.serialize(document(Value(name: "Settings", type: .REG_BINARY, data: .binary(Self.settingsBytes))))
        XCTAssertEqual(text, "Windows Registry Editor Version 5.00\r\n\r\n[HKEY_CURRENT_USER\\Software]\r\n" + Self.settingsLine + "\r\n\r\n")
    }

    func testSerializeWrapBoundary() {
        let fits = RegFile.serialize(Value(name: "x", type: .REG_BINARY, data: .binary(Array(repeating: 0, count: 23))))
        XCTAssertEqual(fits, "\"x\"=hex:" + Array(repeating: "00", count: 23).joined(separator: ","))
        XCTAssertEqual(fits.count, 76)

        let wraps = RegFile.serialize(Value(name: "x", type: .REG_BINARY, data: .binary(Array(repeating: 0, count: 24))))
        XCTAssertEqual(wraps, "\"x\"=hex:" + Array(repeating: "00", count: 23).joined(separator: ",") + ",\\\r\n  00")
    }

    func testSerializeLongValuesStayWithin80Columns() {
        let values = [
            Value(name: "x", type: .REG_BINARY, data: .binary(Array(0...255))),
            Value(name: String(repeating: "n", count: 40), type: .REG_EXPAND_SZ, data: .string(String(repeating: "%PATH%;", count: 20))),
            Value(name: "Multi", type: .REG_MULTI_SZ, data: .multiString(Array(repeating: "Lorem ipsum dolor", count: 10))),
        ]
        let text = RegFile.serialize(document(values[0], values[1], values[2]))
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.filter { $0.count > 80 }, [])
        XCTAssertEqual(try RegFile.parse(text), document(values[0], values[1], values[2]))
    }

    // MARK: - Parsing

    func testParseRegeditExport() throws {
        XCTAssertEqual(try RegFile.parse(Self.export), Self.exportDocument)
    }

    func testParseCRLFExport() throws {
        let crlf = Self.export.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(try RegFile.parse(crlf), Self.exportDocument)
    }

    func testParseAllTypes() throws {
        XCTAssertEqual(try RegFile.parse(Self.allTypesText), Self.allTypesDocument)
    }

    func testParseLenientForms() throws {
        let text = """
            \u{feff}
            Windows Registry Editor Version 5.00
            [HKEY_Current_User\\\\Software\\]
            @=-
            "Short"=hex(4):2a,00,00,00
            "Upper"=HEX(B):FF,FF,FF,FF,FF,FF,FF,FF
            "Digit"=hex:1,a,
            "Wrapped"=hex:01,\\
            ; not a comment inside data
            """
        XCTAssertThrowsError(try RegFile.parse(text))

        let valid = text.replacingOccurrences(of: "; not a comment inside data", with: "  02")
        XCTAssertEqual(try RegFile.parse(valid), document(
            Value(name: "", type: .REG_NONE, data: nil),
            Value(name: "Short", type: .REG_DWORD, data: .dword(42)),
            Value(name: "Upper", type: .REG_QWORD, data: .qword(.max)),
            Value(name: "Digit", type: .REG_BINARY, data: .binary([0x01, 0x0a])),
            Value(name: "Wrapped", type: .REG_BINARY, data: .binary([0x01, 0x02]))
        ))
    }

    // MARK: - Round trips

    func testRoundTrips() throws {
        XCTAssertEqual(try RegFile.parse(RegFile.serialize(Self.allTypesDocument)), Self.allTypesDocument)
        XCTAssertEqual(try RegFile.parse(RegFile.serialize(Self.exportDocument)), Self.exportDocument)

        let encoded = RegFile.encode(RegFile.serialize(Self.allTypesDocument))
        XCTAssertEqual(try RegFile.parse(RegFile.decode(encoded)), Self.allTypesDocument)

        // Types whose default data reads back differently are covered in testLossyRoundTrips.
        let lossy: [RegistryValueType] = [.REG_NONE, .REG_LINK, .REG_RESOURCE_LIST, .REG_FULL_RESOURCE_DESCRIPTOR, .REG_RESOURCE_REQUIREMENTS_LIST]
        for type in RegistryValueType.allCases where !lossy.contains(type) {
            let doc = document(
                Value(name: "Default", type: type, data: type.defaultData),
                Value(name: "Null", type: type, data: RegistryData.none)
            )
            XCTAssertEqual(try RegFile.parse(RegFile.serialize(doc)), doc, type.name)
        }
    }

    func testLossyRoundTrips() throws {
        // An empty `hex(N):` always reads back as SQL NULL.
        let empty = document(Value(name: "a", type: .REG_NONE, data: .binary([])))
        XCTAssertEqual(try RegFile.parse(RegFile.serialize(empty)), document(Value(name: "a", type: .REG_NONE, data: RegistryData.none)))

        // Only REG_SZ, REG_EXPAND_SZ and REG_MULTI_SZ hex data is decoded as text.
        let link = document(Value(name: "a", type: .REG_LINK, data: .string("x")))
        XCTAssertEqual(try RegFile.parse(RegFile.serialize(link)), document(Value(name: "a", type: .REG_LINK, data: .binary([0x78, 0x00, 0x00, 0x00]))))
    }

    // MARK: - Encoding

    func testEncodeUTF16LEWithBOM() {
        XCTAssertEqual(RegFile.encode("Hi€"), Data([0xff, 0xfe, 0x48, 0x00, 0x69, 0x00, 0xac, 0x20]))
    }

    func testDecode() throws {
        XCTAssertEqual(try RegFile.decode(RegFile.encode("Ünïcødé 😀")), "Ünïcødé 😀")
        XCTAssertEqual(try RegFile.decode(Data([0xfe, 0xff, 0x00, 0x48, 0x00, 0x69])), "Hi")
        XCTAssertEqual(try RegFile.decode(Data([0xef, 0xbb, 0xbf, 0xc3, 0xa9])), "é")
        XCTAssertEqual(try RegFile.decode(Data([0xc3, 0xa9])), "é")
        XCTAssertEqual(try RegFile.decode(Data([0x48, 0x00, 0x69, 0x00])), "Hi")
        XCTAssertEqual(try RegFile.decode(Data([0x80, 0xe9])), "€é")
        XCTAssertEqual(try RegFile.decode(Data()), "")
        XCTAssertThrowsError(try RegFile.decode(Data([0xff, 0xfe, 0x41]))) { error in
            XCTAssertEqual(error as? RegFileError, .invalidEncoding)
        }
    }

    // MARK: - Errors

    func testHeaderErrors() {
        for (text, line) in [("", 1), ("REGEDIT4\r\n", 1), ("\n\nWindows Registry Editor Version 4.00", 3), ("[HKEY_CURRENT_USER]", 1)] {
            XCTAssertThrowsError(try RegFile.parse(text)) { error in
                XCTAssertEqual(error as? RegFileError, .invalidHeader(line: line))
            }
        }
    }

    func testParseErrors() {
        let cases: [(String, RegFileError)] = [
            ("[HKEY_LOCAL_MACHINE\\Software]", .unsupportedHive(line: 3, hive: "HKEY_LOCAL_MACHINE")),
            ("[-HKLM\\Software]", .unsupportedHive(line: 3, hive: "HKLM")),
            ("[HKEY_CURRENT_USER\\Software", .invalidKey(line: 3)),
            ("[]", .invalidKey(line: 3)),
            ("\"a\"=\"b\"", .valueOutsideKey(line: 3)),
            ("[HKCU]\nName=1", .invalidValue(line: 4)),
            ("[HKCU]\n\"a\"=foo", .invalidValue(line: 4)),
            ("[HKCU]\n\"a\"=\"b\" junk", .invalidValue(line: 4)),
            ("[HKCU]\n\"a\"", .invalidValue(line: 4)),
            ("[HKCU]\n\"a\"=hex(4:00", .invalidValue(line: 4)),
            ("[HKCU]\n\"a\"=\"b", .unterminatedString(line: 4)),
            ("[HKCU]\n\"a\"=\"b\\\"", .unterminatedString(line: 4)),
            ("[HKCU]\n\"a=1", .unterminatedString(line: 4)),
            ("[HKCU]\n\"a\"=dword:123456789", .invalidDword(line: 4)),
            ("[HKCU]\n\"a\"=dword:xyz", .invalidDword(line: 4)),
            ("[HKCU]\n\"a\"=dword:", .invalidDword(line: 4)),
            ("[HKCU]\n\"a\"=dword:-1", .invalidDword(line: 4)),
            ("[HKCU]\n\"a\"=hex:0g", .invalidHex(line: 4)),
            ("[HKCU]\n\"a\"=hex:123", .invalidHex(line: 4)),
            ("[HKCU]\n\"a\"=hex:00,,01", .invalidHex(line: 4)),
            ("[HKCU]\n\"a\"=hex:00,\\\n  zz", .invalidHex(line: 4)),
            ("[HKCU]\n\"a\"=hex(b):00,01", .invalidDataLength(line: 4, type: .REG_QWORD, expected: 8, actual: 2)),
            ("[HKCU]\n\"a\"=hex(4):00", .invalidDataLength(line: 4, type: .REG_DWORD, expected: 4, actual: 1)),
            ("[HKCU]\n\"a\"=hex(c):00", .unknownValueType(line: 4, type: "hex(c)")),
        ]
        for (body, expected) in cases {
            XCTAssertEqual(parseError(body), expected, body)
        }
    }

    func testErrorDescriptionsIncludeLineNumbers() {
        XCTAssertEqual(
            RegFileError.unsupportedHive(line: 7, hive: "HKLM").errorDescription,
            "Line 7: Only keys in HKEY_CURRENT_USER can be imported, not HKLM."
        )
        XCTAssertEqual(
            RegFileError.invalidDataLength(line: 3, type: .REG_QWORD, expected: 8, actual: 2).errorDescription,
            "Line 3: REG_QWORD data must be 8 bytes long, not 2."
        )
    }
}
