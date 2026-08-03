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
