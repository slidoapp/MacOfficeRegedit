import XCTest
@testable import MacOfficeRegedit

final class HexFormattingTests: XCTestCase {
    // MARK: - Parsing

    func testParseEmpty() throws {
        XCTAssertEqual(try HexFormatting.parse(""), [])
        XCTAssertEqual(try HexFormatting.parse("  \n\t, ,"), [])
    }

    func testParseValid() throws {
        XCTAssertEqual(try HexFormatting.parse("00 01 7f 80 ff"), [0x00, 0x01, 0x7f, 0x80, 0xff])
        XCTAssertEqual(try HexFormatting.parse("DEADbeef"), [0xde, 0xad, 0xbe, 0xef])
    }

    func testParseIgnoresSeparators() throws {
        XCTAssertEqual(try HexFormatting.parse("01,02, 03\n04\r\n05\t06  ,07"), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(try HexFormatting.parse("\n 0a 0b \n"), [0x0a, 0x0b])
    }

    func testParseDigitsAcrossSeparatorsFormOneStream() throws {
        XCTAssertEqual(try HexFormatting.parse("1 2 3 4"), [0x12, 0x34])
        XCTAssertEqual(try HexFormatting.parse("123\n4"), [0x12, 0x34])
    }

    func testParseHexPrefixes() throws {
        XCTAssertEqual(try HexFormatting.parse("0x01, 0X02,0xff"), [0x01, 0x02, 0xff])
        XCTAssertEqual(try HexFormatting.parse("0x0102"), [0x01, 0x02])
        XCTAssertEqual(try HexFormatting.parse("0x"), [])
    }

    func testParseRejectsPrefixInsideToken() {
        XCTAssertThrowsError(try HexFormatting.parse("010x02")) { error in
            XCTAssertEqual(error as? HexFormatting.ParseError, .invalidCharacter("x", position: 3))
        }
    }

    func testParseOddDigitCount() {
        XCTAssertThrowsError(try HexFormatting.parse("0")) { error in
            XCTAssertEqual(error as? HexFormatting.ParseError, .oddDigitCount(1))
        }
        XCTAssertThrowsError(try HexFormatting.parse("01 02 0")) { error in
            XCTAssertEqual(error as? HexFormatting.ParseError, .oddDigitCount(5))
        }
    }

    func testParseInvalidCharacters() {
        XCTAssertThrowsError(try HexFormatting.parse("01 0g")) { error in
            XCTAssertEqual(error as? HexFormatting.ParseError, .invalidCharacter("g", position: 4))
        }
        XCTAssertThrowsError(try HexFormatting.parse("01-02")) { error in
            XCTAssertEqual(error as? HexFormatting.ParseError, .invalidCharacter("-", position: 2))
        }
        XCTAssertThrowsError(try HexFormatting.parse("é1"))
        XCTAssertThrowsError(try HexFormatting.parse("０１"), "Full-width digits are not hex digits")
    }

    func testParseErrorMessages() {
        XCTAssertNotNil(HexFormatting.ParseError.oddDigitCount(3).errorDescription)
        XCTAssertTrue(HexFormatting.ParseError.invalidCharacter("g", position: 0).errorDescription?.contains("\"g\"") ?? false)
    }

    // MARK: - Formatting

    func testFormat() {
        XCTAssertEqual(HexFormatting.format([]), "")
        XCTAssertEqual(HexFormatting.format([0x00, 0xab, 0xff]), "00 AB FF")
        XCTAssertEqual(HexFormatting.format(Array(0...8)), "00 01 02 03 04 05 06 07\n08")
        XCTAssertEqual(HexFormatting.format(Array(0...15)), "00 01 02 03 04 05 06 07\n08 09 0A 0B 0C 0D 0E 0F")
        XCTAssertEqual(HexFormatting.format([1, 2, 3], bytesPerLine: 2), "01 02\n03")
    }

    func testFormatRoundTrip() throws {
        let bytes = (0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 37) }
        XCTAssertEqual(try HexFormatting.parse(HexFormatting.format(bytes)), bytes)
    }

    func testAsciiCharacter() {
        XCTAssertEqual(HexFormatting.asciiCharacter(0x41), "A")
        XCTAssertEqual(HexFormatting.asciiCharacter(0x20), " ")
        XCTAssertEqual(HexFormatting.asciiCharacter(0x7e), "~")
        XCTAssertEqual(HexFormatting.asciiCharacter(0x00), ".")
        XCTAssertEqual(HexFormatting.asciiCharacter(0x7f), ".")
        XCTAssertEqual(HexFormatting.asciiCharacter(0xe9), ".")
    }

    func testOffsetText() {
        XCTAssertEqual(HexFormatting.offsetText(0), "00000000")
        XCTAssertEqual(HexFormatting.offsetText(8), "00000008")
        XCTAssertEqual(HexFormatting.offsetText(0x562), "00000562")
        XCTAssertEqual(HexFormatting.offsetText(0xABCDEF12), "ABCDEF12")
    }

    // MARK: - Hex dump

    func testDumpLinesEmpty() {
        XCTAssertEqual(HexFormatting.dumpLines([]), [])
    }

    func testDumpLines() {
        let bytes: [UInt8] = Array("Hello, World".utf8) + [0x00, 0x7f, 0xff]
        let lines = HexFormatting.dumpLines(bytes)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.map(\.offset), [0, 8])
        XCTAssertEqual(lines[0].text, "00000000  48 65 6C 6C 6F 2C 20 57  Hello, W")
        XCTAssertEqual(lines[1].offsetText, "00000008")
        XCTAssertEqual(lines[1].hexText, "6F 72 6C 64 00 7F FF   ")
        XCTAssertEqual(lines[1].asciiText, "orld...")
        XCTAssertEqual(lines[1].text, "00000008  6F 72 6C 64 00 7F FF     orld...")
    }

    func testDumpLinesAreAligned() {
        let lines = HexFormatting.dumpLines(Array(0..<21))
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(Set(lines.map(\.hexText.count)), [23])
        XCTAssertEqual(lines.last?.hexText, "10 11 12 13 14         ")
    }

    func testDumpLinesLargeValue() {
        let bytes = [UInt8](repeating: 0x41, count: 16 * 1024)
        let lines = HexFormatting.dumpLines(bytes)
        XCTAssertEqual(lines.count, 2048)
        XCTAssertEqual(lines.last?.offsetText, "00003FF8")
        XCTAssertEqual(lines.last?.asciiText, "AAAAAAAA")
    }

    // MARK: - UTF-16LE detection

    func testLooksLikeUTF16LETextJSON() {
        let json = "{\"enabled\":true,\"name\":\"Žluťoučký kůň\"}"
        XCTAssertTrue(HexFormatting.looksLikeUTF16LEText(RegistryData.utf16LEBytes(json, terminated: true)))
        XCTAssertTrue(HexFormatting.looksLikeUTF16LEText(RegistryData.utf16LEBytes(json, terminated: false)))
        XCTAssertTrue(HexFormatting.looksLikeUTF16LEText(RegistryData.utf16LEBytes("a\r\n\tb", terminated: true) + [0, 0]))
    }

    func testLooksLikeUTF16LETextRejectsBinary() {
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([]))
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([0, 0]))
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([0x41, 0x00, 0x42]), "Odd byte count")
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([0x01, 0x00, 0x02, 0x00]), "Control characters")
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([0x41, 0x00, 0x00, 0x00, 0x42, 0x00]), "Data after the terminator")
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([0x00, 0xd8, 0x41, 0x00]), "Unpaired surrogate")
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText(Array("ABCDEFGH".utf8)), "ASCII/UTF-8 decodes as CJK")
        XCTAssertFalse(HexFormatting.looksLikeUTF16LEText([0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe]))
    }
}
