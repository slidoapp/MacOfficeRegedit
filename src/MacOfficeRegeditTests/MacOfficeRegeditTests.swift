//
//  MacOfficeRegeditTests.swift
//  MacOfficeRegeditTests
//
//  Created by dpalo on 17/02/2023.
//

import XCTest
@testable import MacOfficeRegedit

final class MacOfficeRegeditTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testDwordHexRenderingPreservesAll32Bits() throws {
        let value = RegistryValue(
            nodeId: 1,
            name: "DwordValue",
            type: .REG_DWORD,
            value: Int64(0x89abcdef)
        )

        let item = RegistryValueTableItem(fromRegValue: value)

        XCTAssertEqual(item.data, "0x89abcdef (2309737967)")
    }

    func testQwordHexRenderingPreservesUpper32Bits() throws {
        let value = RegistryValue(
            nodeId: 1,
            name: "QwordValue",
            type: .REG_QWORD,
            value: Int64(0x0123456789abcdef)
        )

        let item = RegistryValueTableItem(fromRegValue: value)

        XCTAssertEqual(item.data, "0x0123456789abcdef (81985529216486895)")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

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

    func testUTF16Helpers() {
        let bytes = RegistryData.multiStringBytes(["ab", "č"])
        XCTAssertEqual(bytes, [0x61, 0, 0x62, 0, 0, 0, 0x0D, 0x01, 0, 0, 0, 0])
        XCTAssertEqual(RegistryData.multiString(fromUTF16LE: bytes), ["ab", "č"])
        XCTAssertEqual(RegistryData.string(fromUTF16LE: RegistryData.utf16LEBytes("hi", terminated: true)), "hi")
    }
}
