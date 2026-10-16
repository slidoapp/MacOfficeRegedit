import Foundation

/// Contents of a Windows `.reg` file, limited to the `HKEY_CURRENT_USER` hive.
struct RegFileDocument: Equatable {
    struct Value: Equatable {
        /// Empty string is the key's default value, written as `@`.
        var name: String
        var type: RegistryValueType
        /// `nil` deletes the value (`"name"=-`).
        var data: RegistryData?
    }

    struct Key: Equatable {
        /// Key names below `HKEY_CURRENT_USER`; empty for the hive root.
        var path: [String]
        /// `[-HKEY_CURRENT_USER\...]` deletes the key and all its subkeys.
        var isDeletion: Bool
        var values: [Value]
    }

    var keys: [Key]
}

enum RegFileError: LocalizedError, Equatable {
    case invalidEncoding
    case invalidHeader(line: Int)
    case unsupportedHive(line: Int, hive: String)
    case invalidKey(line: Int)
    case valueOutsideKey(line: Int)
    case invalidValue(line: Int)
    case unterminatedString(line: Int)
    case invalidDword(line: Int)
    case invalidHex(line: Int)
    case invalidDataLength(line: Int, type: RegistryValueType, expected: Int, actual: Int)
    case unknownValueType(line: Int, type: String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The file is not a valid text file."
        case .invalidHeader(let line):
            return "Line \(line): The file does not start with \"\(RegFile.header)\"."
        case .unsupportedHive(let line, let hive):
            return "Line \(line): Only keys in \(RegistryPath.hive) can be imported, not \(hive)."
        case .invalidKey(let line):
            return "Line \(line): The key name is malformed."
        case .valueOutsideKey(let line):
            return "Line \(line): The value is not preceded by a key."
        case .invalidValue(let line):
            return "Line \(line): The value is malformed."
        case .unterminatedString(let line):
            return "Line \(line): The string is missing its closing quotation mark."
        case .invalidDword(let line):
            return "Line \(line): The DWORD value must be 1 to 8 hexadecimal digits."
        case .invalidHex(let line):
            return "Line \(line): The binary data must be comma-separated hexadecimal bytes."
        case .invalidDataLength(let line, let type, let expected, let actual):
            return "Line \(line): \(type.name) data must be \(expected) bytes long, not \(actual)."
        case .unknownValueType(let line, let type):
            return "Line \(line): The value type \(type) is not supported."
        }
    }
}

/// Reads and writes Windows Registry Editor `.reg` files in the same format as Windows regedit.
enum RegFile {
    static let header = "Windows Registry Editor Version 5.00"

    /// regedit wraps hex data once a line reaches this many characters (excluding the trailing `\`).
    private static let maxHexColumn = 77
    private static let lineBreak = "\r\n"

    // MARK: - Serialization

    static func serialize(_ document: RegFileDocument) -> String {
        var lines = [header]
        for key in document.keys {
            lines.append("")
            lines.append("[" + (key.isDeletion ? "-" : "") + RegistryPath.qualified(key.path) + "]")
            lines.append(contentsOf: key.values.map(serialize))
        }
        lines.append("")
        return lines.joined(separator: lineBreak) + lineBreak
    }

    static func serialize(_ value: RegFileDocument.Value) -> String {
        let prefix = value.name.isEmpty ? "@=" : "\"\(escape(value.name))\"="
        guard let data = value.data else {
            return prefix + "-"
        }
        switch (value.type, data) {
        case (_, .none):
            // An explicit type tag without bytes; `hex:` alone would read back as an empty REG_BINARY.
            return hexLine(prefix: prefix, type: value.type, explicitType: true, bytes: [])
        case (.REG_SZ, .string(let string)) where !string.contains(where: \.isNewline):
            return prefix + "\"\(escape(string))\""
        case (.REG_DWORD, .dword(let number)):
            return prefix + String(format: "dword:%08x", number)
        case (.REG_DWORD_BIG_ENDIAN, .dword(let number)):
            return hexLine(prefix: prefix, type: value.type, bytes: withUnsafeBytes(of: number.bigEndian, Array.init))
        default:
            return hexLine(prefix: prefix, type: value.type, bytes: data.rawBytes)
        }
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func hexLine(prefix: String, type: RegistryValueType, explicitType: Bool = false, bytes: [UInt8]) -> String {
        let tag = type == .REG_BINARY && !explicitType ? "hex:" : String(format: "hex(%llx):", type.rawValue)
        var result = prefix + tag
        var column = result.utf16.count
        for (index, byte) in bytes.enumerated() {
            result += String(format: "%02x", byte)
            if index == bytes.count - 1 {
                break
            }
            result += ","
            column += 3
            if column >= maxHexColumn {
                result += "\\" + lineBreak + "  "
                column = 2
            }
        }
        return result
    }

    // MARK: - Parsing

    static func parse(_ text: String) throws -> RegFileDocument {
        var parser = Parser(text: text)
        return try parser.parse()
    }

    private struct Parser {
        let lines: [String]
        var index = 0

        init(text: String) {
            var text = text
            if text.unicodeScalars.first == "\u{feff}" {
                text.unicodeScalars.removeFirst()
            }
            lines = text
                .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        /// Returns the next line and its 1-based number.
        mutating func nextLine() -> (String, Int)? {
            guard index < lines.count else {
                return nil
            }
            index += 1
            return (lines[index - 1], index)
        }

        mutating func parse() throws -> RegFileDocument {
            var headerLine: (String, Int)?
            while let line = nextLine() {
                if !line.0.isEmpty {
                    headerLine = line
                    break
                }
            }
            guard let (header, headerNumber) = headerLine else {
                throw RegFileError.invalidHeader(line: 1)
            }
            guard header == RegFile.header else {
                throw RegFileError.invalidHeader(line: headerNumber)
            }

            var keys = [RegFileDocument.Key]()
            while let (line, number) = nextLine() {
                if line.isEmpty || line.hasPrefix(";") {
                    continue
                }
                if line.hasPrefix("[") {
                    keys.append(try parseKey(line, number: number))
                    continue
                }
                guard !keys.isEmpty else {
                    throw RegFileError.valueOutsideKey(line: number)
                }
                keys[keys.count - 1].values.append(try parseValue(line, number: number))
            }
            return RegFileDocument(keys: keys)
        }

        func parseKey(_ line: String, number: Int) throws -> RegFileDocument.Key {
            guard let end = line.lastIndex(of: "]") else {
                throw RegFileError.invalidKey(line: number)
            }
            var path = line[line.index(after: line.startIndex)..<end]
            let isDeletion = path.hasPrefix("-")
            if isDeletion {
                path.removeFirst()
            }
            var components = path
                .split(separator: RegistryPath.separator, omittingEmptySubsequences: true)
                .map(String.init)
            guard let hive = components.first?.trimmingCharacters(in: .whitespaces), !hive.isEmpty else {
                throw RegFileError.invalidKey(line: number)
            }
            guard hive.caseInsensitiveCompare(RegistryPath.hive) == .orderedSame
                || hive.caseInsensitiveCompare(RegistryPath.hiveAbbreviation) == .orderedSame
            else {
                throw RegFileError.unsupportedHive(line: number, hive: hive)
            }
            components.removeFirst()
            return RegFileDocument.Key(path: components, isDeletion: isDeletion, values: [])
        }

        mutating func parseValue(_ line: String, number: Int) throws -> RegFileDocument.Value {
            let scalars = Array(line.unicodeScalars)
            let name: String
            var position: Int
            switch scalars.first {
            case "@"?:
                name = ""
                position = 1
            case "\""?:
                (name, position) = try Parser.quotedString(scalars, from: 1, line: number)
            default:
                throw RegFileError.invalidValue(line: number)
            }
            position = Parser.skipWhitespace(scalars, from: position)
            guard position < scalars.count, scalars[position] == "=" else {
                throw RegFileError.invalidValue(line: number)
            }
            position = Parser.skipWhitespace(scalars, from: position + 1)
            let data = String(String.UnicodeScalarView(scalars[position...]))
            let lowercased = data.lowercased()

            if data == "-" {
                return RegFileDocument.Value(name: name, type: .REG_NONE, data: nil)
            }
            if data.hasPrefix("\"") {
                let (string, end) = try Parser.quotedString(scalars, from: position + 1, line: number)
                guard Parser.skipWhitespace(scalars, from: end) == scalars.count else {
                    throw RegFileError.invalidValue(line: number)
                }
                return RegFileDocument.Value(name: name, type: .REG_SZ, data: .string(string))
            }
            if lowercased.hasPrefix("dword:") {
                let digits = lowercased.dropFirst("dword:".count)
                guard (1...8).contains(digits.count), digits.allSatisfy(\.isHexDigit), let number32 = UInt32(digits, radix: 16) else {
                    throw RegFileError.invalidDword(line: number)
                }
                return RegFileDocument.Value(name: name, type: .REG_DWORD, data: .dword(number32))
            }
            if lowercased.hasPrefix("hex:") {
                let bytes = try hexBytes(String(lowercased.dropFirst("hex:".count)), line: number)
                return RegFileDocument.Value(name: name, type: .REG_BINARY, data: .binary(bytes))
            }
            if lowercased.hasPrefix("hex("), let close = lowercased.firstIndex(of: ")") {
                let typeDigits = lowercased[lowercased.index(lowercased.startIndex, offsetBy: 4)..<close]
                let afterClose = lowercased[lowercased.index(after: close)...]
                guard (1...8).contains(typeDigits.count), typeDigits.allSatisfy(\.isHexDigit),
                      let rawType = Int64(typeDigits, radix: 16), afterClose.hasPrefix(":")
                else {
                    throw RegFileError.invalidValue(line: number)
                }
                guard let type = RegistryValueType(rawValue: rawType) else {
                    throw RegFileError.unknownValueType(line: number, type: "hex(\(typeDigits))")
                }
                let bytes = try hexBytes(String(afterClose.dropFirst()), line: number)
                return RegFileDocument.Value(name: name, type: type, data: try Parser.data(type: type, bytes: bytes, line: number))
            }
            throw RegFileError.invalidValue(line: number)
        }

        /// Parses comma-separated hex bytes, consuming `\` continuation lines.
        mutating func hexBytes(_ text: String, line: Int) throws -> [UInt8] {
            var text = text
            while text.hasSuffix("\\") {
                text.removeLast()
                guard let (next, _) = nextLine() else {
                    break
                }
                text += next
            }
            var tokens = text
                .filter { !$0.isWhitespace }
                .split(separator: ",", omittingEmptySubsequences: false)
            if tokens.last?.isEmpty == true {
                tokens.removeLast()
            }
            return try tokens.map { token in
                guard (1...2).contains(token.count), token.allSatisfy(\.isHexDigit), let byte = UInt8(token, radix: 16) else {
                    throw RegFileError.invalidHex(line: line)
                }
                return byte
            }
        }

        /// Converts the bytes of a `hex(N):` value to typed data.
        static func data(type: RegistryValueType, bytes: [UInt8], line: Int) throws -> RegistryData {
            if bytes.isEmpty {
                return .none
            }
            switch type {
            case .REG_SZ, .REG_EXPAND_SZ:
                return .string(RegistryData.string(fromUTF16LE: bytes))
            case .REG_MULTI_SZ:
                return .multiString(RegistryData.multiString(fromUTF16LE: bytes))
            case .REG_DWORD:
                guard bytes.count == 4 else {
                    throw RegFileError.invalidDataLength(line: line, type: type, expected: 4, actual: bytes.count)
                }
                return .dword(bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) })
            case .REG_DWORD_BIG_ENDIAN where bytes.count == 4:
                return .dword(bytes.reduce(0) { $0 << 8 | UInt32($1) })
            case .REG_QWORD:
                guard bytes.count == 8 else {
                    throw RegFileError.invalidDataLength(line: line, type: type, expected: 8, actual: bytes.count)
                }
                return .qword(bytes.reversed().reduce(0) { $0 << 8 | UInt64($1) })
            default:
                return .binary(bytes)
            }
        }

        /// Reads a quoted string starting just after the opening quote.
        /// Returns the unescaped string and the position just after the closing quote.
        static func quotedString(_ scalars: [Unicode.Scalar], from start: Int, line: Int) throws -> (String, Int) {
            var result = String.UnicodeScalarView()
            var position = start
            while position < scalars.count {
                let scalar = scalars[position]
                switch scalar {
                case "\"":
                    return (String(result), position + 1)
                case "\\" where position + 1 < scalars.count && (scalars[position + 1] == "\\" || scalars[position + 1] == "\""):
                    result.append(scalars[position + 1])
                    position += 2
                default:
                    result.append(scalar)
                    position += 1
                }
            }
            throw RegFileError.unterminatedString(line: line)
        }

        static func skipWhitespace(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
            var position = start
            while position < scalars.count, scalars[position].properties.isWhitespace {
                position += 1
            }
            return position
        }
    }

    // MARK: - Encoding

    /// UTF-16LE with a byte order mark, as written by Windows regedit.
    static func encode(_ text: String) -> Data {
        Data([0xff, 0xfe] + RegistryData.utf16LEBytes(text, terminated: false))
    }

    /// Decodes a `.reg` file: UTF-16 (LE or BE, with BOM or LE without), UTF-8, or Windows-1252.
    static func decode(_ data: Data) throws -> String {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xff, 0xfe]) {
            return try utf16String(bytes.dropFirst(2), littleEndian: true)
        }
        if bytes.starts(with: [0xfe, 0xff]) {
            return try utf16String(bytes.dropFirst(2), littleEndian: false)
        }
        if bytes.starts(with: [0xef, 0xbb, 0xbf]) {
            guard let string = String(bytes: bytes.dropFirst(3), encoding: .utf8) else {
                throw RegFileError.invalidEncoding
            }
            return string
        }
        if bytes.count >= 2, bytes[0] != 0, bytes[1] == 0 {
            return try utf16String(bytes[...], littleEndian: true)
        }
        if let string = String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .windowsCP1252)
            ?? String(bytes: bytes, encoding: .isoLatin1) {
            return string
        }
        throw RegFileError.invalidEncoding
    }

    private static func utf16String(_ bytes: ArraySlice<UInt8>, littleEndian: Bool) throws -> String {
        guard bytes.count % 2 == 0 else {
            throw RegFileError.invalidEncoding
        }
        let units = stride(from: bytes.startIndex, to: bytes.endIndex, by: 2).map { index -> UInt16 in
            let first = UInt16(bytes[index])
            let second = UInt16(bytes[index + 1])
            return littleEndian ? first | second << 8 : first << 8 | second
        }
        return String(decoding: units, as: UTF16.self)
    }
}
