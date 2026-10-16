import Foundation

/// Windows `FILETIME`: number of 100-nanosecond intervals since 1601-01-01 00:00:00 UTC.
///
/// The `write_time` column stores it as an 8-byte little-endian blob.
/// See https://learn.microsoft.com/en-us/windows/win32/api/minwinbase/ns-minwinbase-filetime
enum FileTime {
    /// Seconds between 1601-01-01 and 1970-01-01.
    static let unixEpochOffset: TimeInterval = 11_644_473_600
    static let ticksPerSecond: Double = 10_000_000

    static func date(fromTicks ticks: UInt64) -> Date {
        Date(timeIntervalSince1970: Double(ticks) / ticksPerSecond - unixEpochOffset)
    }

    static func ticks(from date: Date) -> UInt64 {
        let ticks = (date.timeIntervalSince1970 + unixEpochOffset) * ticksPerSecond
        return ticks <= 0 ? 0 : UInt64(ticks)
    }

    static func date(fromBytes bytes: [UInt8]) -> Date? {
        guard bytes.count == 8 else {
            return nil
        }
        let ticks = bytes.reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return ticks == 0 ? nil : date(fromTicks: ticks)
    }

    static func bytes(from date: Date) -> [UInt8] {
        withUnsafeBytes(of: ticks(from: date).littleEndian, Array.init)
    }
}
