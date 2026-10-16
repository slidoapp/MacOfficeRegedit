import Foundation

/// Pure helpers behind the binary value editor: hex parsing/formatting and hex dump generation.
enum HexFormatting {
    enum ParseError: LocalizedError, Equatable {
        /// `position` is the zero-based index of the offending character (in Unicode scalars).
        case invalidCharacter(Character, position: Int)
        case oddDigitCount(Int)

        var errorDescription: String? {
            switch self {
            case .invalidCharacter(let character, let position):
                let shown = character.unicodeScalars.allSatisfy { $0.properties.isWhitespace || $0.value < 0x20 }
                    ? String(format: "U+%04X", character.unicodeScalars.first?.value ?? 0)
                    : "\"\(character)\""
                return "Invalid character \(shown) at position \(position + 1). Use hexadecimal digits 0–9 and A–F only."
            case .oddDigitCount(let count):
                return "Odd number of hex digits (\(count)). Every byte needs exactly two digits."
            }
        }
    }

    /// A single line of a hex dump: offset, hex bytes and their ASCII representation.
    struct DumpLine: Identifiable, Hashable {
        let offset: Int
        let offsetText: String
        /// Padded to the full line width so that the ASCII column stays aligned on the last line.
        let hexText: String
        let asciiText: String

        var id: Int { offset }

        var text: String { "\(offsetText)  \(hexText)  \(asciiText)" }
    }

    /// Number of bytes per line, matching Windows regedit's "Edit Binary Value" dialog.
    static let bytesPerLine = 8

    private static let hexDigits = Array("0123456789ABCDEF".utf8)

    // MARK: - Parsing

    /// Parses hex digits into bytes.
    ///
    /// Whitespace (including newlines) and commas are ignored, as is an optional `0x`/`0X` prefix at the start
    /// of each separated token. The digits are read as one continuous stream, so their total count must be even.
    static func parse(_ text: String) throws -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(text.utf8.count / 2)
        let scalars = Array(text.unicodeScalars)
        var pendingNibble: UInt8?
        var digitCount = 0
        var isTokenStart = true
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "," || scalar.properties.isWhitespace {
                isTokenStart = true
                index += 1
                continue
            }
            if isTokenStart, scalar == "0", index + 1 < scalars.count, scalars[index + 1] == "x" || scalars[index + 1] == "X" {
                isTokenStart = false
                index += 2
                continue
            }
            isTokenStart = false
            guard let nibble = nibbleValue(scalar) else {
                throw ParseError.invalidCharacter(Character(scalar), position: index)
            }
            digitCount += 1
            if let high = pendingNibble {
                bytes.append(high << 4 | nibble)
                pendingNibble = nil
            } else {
                pendingNibble = nibble
            }
            index += 1
        }
        if pendingNibble != nil {
            throw ParseError.oddDigitCount(digitCount)
        }
        return bytes
    }

    private static func nibbleValue(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 0x30...0x39: return UInt8(scalar.value - 0x30)
        case 0x41...0x46: return UInt8(scalar.value - 0x41 + 10)
        case 0x61...0x66: return UInt8(scalar.value - 0x61 + 10)
        default: return nil
        }
    }

    // MARK: - Formatting

    /// Two uppercase hex digits per byte separated by spaces, `bytesPerLine` bytes per line.
    static func format(_ bytes: [UInt8], bytesPerLine: Int = bytesPerLine) -> String {
        var utf8 = [UInt8]()
        utf8.reserveCapacity(bytes.count * 3)
        for (index, byte) in bytes.enumerated() {
            if index > 0 {
                utf8.append(index % bytesPerLine == 0 ? UInt8(ascii: "\n") : UInt8(ascii: " "))
            }
            utf8.append(hexDigits[Int(byte >> 4)])
            utf8.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: utf8, as: UTF8.self)
    }

    /// Printable ASCII is shown as is, everything else as ".".
    static func asciiCharacter(_ byte: UInt8) -> Character {
        (0x20...0x7e).contains(byte) ? Character(Unicode.Scalar(byte)) : "."
    }

    static func offsetText(_ offset: Int) -> String {
        var utf8 = [UInt8](repeating: UInt8(ascii: "0"), count: 8)
        var remaining = UInt32(truncatingIfNeeded: offset)
        for position in stride(from: 7, through: 0, by: -1) {
            utf8[position] = hexDigits[Int(remaining & 0x0f)]
            remaining >>= 4
        }
        return String(decoding: utf8, as: UTF8.self)
    }

    static func dumpLines(_ bytes: [UInt8], bytesPerLine: Int = bytesPerLine) -> [DumpLine] {
        let hexWidth = bytesPerLine * 3 - 1
        return stride(from: 0, to: bytes.count, by: bytesPerLine).map { offset in
            let chunk = bytes[offset..<min(offset + bytesPerLine, bytes.count)]
            var hex = [UInt8]()
            hex.reserveCapacity(hexWidth)
            var ascii = [UInt8]()
            ascii.reserveCapacity(chunk.count)
            for byte in chunk {
                if !hex.isEmpty {
                    hex.append(UInt8(ascii: " "))
                }
                hex.append(hexDigits[Int(byte >> 4)])
                hex.append(hexDigits[Int(byte & 0x0f)])
                ascii.append((0x20...0x7e).contains(byte) ? byte : UInt8(ascii: "."))
            }
            hex.append(contentsOf: repeatElement(UInt8(ascii: " "), count: hexWidth - hex.count))
            return DumpLine(
                offset: offset,
                offsetText: offsetText(offset),
                hexText: String(decoding: hex, as: UTF8.self),
                asciiText: String(decoding: ascii, as: UTF8.self)
            )
        }
    }

    // MARK: - Text detection

    /// Heuristic for "these bytes are a UTF-16LE string", e.g. the JSON documents Office stores as `REG_BINARY`.
    ///
    /// Requires an even byte count, valid UTF-16 without control characters (except tab, CR, LF),
    /// only NUL padding after the first NUL terminator, and mostly ASCII-range characters so that
    /// arbitrary binary data, which tends to decode as random CJK characters, is rejected.
    static func looksLikeUTF16LEText(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2, bytes.count % 2 == 0 else {
            return false
        }
        let units = stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
        let end = units.firstIndex(of: 0) ?? units.endIndex
        guard end > 0, units[end...].allSatisfy({ $0 == 0 }) else {
            return false
        }
        let text = units[..<end]
        var asciiCount = 0
        var iterator = text.makeIterator()
        var decoder = UTF16()
        decoding: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar):
                switch scalar.value {
                case 0x09, 0x0a, 0x0d, 0x20...0x7e:
                    asciiCount += 1
                case 0x00...0x1f, 0x7f...0x9f:
                    return false
                default:
                    break
                }
            case .emptyInput:
                break decoding
            case .error:
                return false
            }
        }
        return asciiCount * 2 >= text.count
    }
}
