import Foundation

// Messages stores many texts only in `attributedBody`, an NSArchiver "typedstream" blob, with `text` NULL.
// The plain string sits right after the "NSString" class marker: a '+' (0x2B) then a length, then UTF-8 bytes.
// Length: one byte, or 0x81 + UInt16 little-endian, or 0x82 + UInt32 little-endian.
public enum TypedStream {
    public static func string(from blob: [UInt8]) -> String? {
        let marker = Array("NSString".utf8)
        guard let start = find(marker, in: blob) else { return nil }
        var i = start + marker.count
        // The '+' type tag follows within a few bytes.
        let limit = min(blob.count, i + 12)
        while i < limit && blob[i] != 0x2B { i += 1 }
        guard i < limit else { return nil }
        i += 1
        guard i < blob.count else { return nil }
        var length = 0
        switch blob[i] {
        case 0x81:
            guard i + 2 < blob.count else { return nil }
            length = Int(blob[i + 1]) | Int(blob[i + 2]) << 8; i += 3
        case 0x82:
            guard i + 4 < blob.count else { return nil }
            length = Int(blob[i + 1]) | Int(blob[i + 2]) << 8 | Int(blob[i + 3]) << 16 | Int(blob[i + 4]) << 24; i += 5
        default:
            length = Int(blob[i]); i += 1
        }
        guard length > 0, i + length <= blob.count else { return nil }
        return String(bytes: blob[i..<(i + length)], encoding: .utf8)
    }

    static func find(_ needle: [UInt8], in hay: [UInt8]) -> Int? {
        guard needle.count <= hay.count else { return nil }
        var i = 0
        while i <= hay.count - needle.count {
            if hay[i] == needle[0] && Array(hay[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return nil
    }
}

public enum AppleTime {
    /// chat.db `date`: nanoseconds since 2001-01-01 on modern macOS, seconds on old rows.
    public static func date(_ raw: Int64) -> Date {
        let secs = raw > 1_000_000_000_000 ? Double(raw) / 1_000_000_000 : Double(raw)
        return Date(timeIntervalSinceReferenceDate: secs)
    }

    /// The other way, in nanoseconds (what modern rows hold), for WHERE clauses.
    public static func raw(_ d: Date) -> Int64 { Int64(d.timeIntervalSinceReferenceDate * 1_000_000_000) }
}
