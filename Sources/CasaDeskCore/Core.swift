import Foundation

// Pure helpers (no Apple frameworks) so they can be unit-tested.

public enum LA {
    public static let tz = TimeZone(identifier: "America/Los_Angeles")!
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c
    }

    /// "2026-10-03" → midnight that day in Los Angeles. nil if malformed.
    public static func day(_ s: String) -> Date? {
        let p = s.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              (1...12).contains(m), (1...31).contains(d), p[0].count == 4 else { return nil }
        var dc = DateComponents(); dc.year = y; dc.month = m; dc.day = d
        guard let date = calendar.date(from: dc), calendar.component(.day, from: date) == d else { return nil }
        return date
    }

    /// End of that LA day (start of the next day).
    public static func endOfDay(_ s: String) -> Date? {
        day(s).flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
    }

    /// ISO-8601 with the LA offset, e.g. 2026-10-03T09:30:00-07:00.
    public static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = tz
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    public static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = tz; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

public enum Phone {
    /// Last 10 digits, so "+1 (323) 555-0142", "3235550142" and "+13235550142" match. Shorter numbers stay whole.
    public static func key(_ s: String) -> String {
        let d = s.filter(\.isNumber)
        return d.count >= 10 ? String(d.suffix(10)) : d
    }

    /// Does this query look like a phone number (enough digits, nothing but phone punctuation)?
    public static func looksLikePhone(_ q: String) -> Bool {
        let digits = q.filter(\.isNumber).count
        let allowed = CharacterSet(charactersIn: "0123456789+-() .")
        return digits >= 7 && q.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public enum Text {
    /// First n characters, single-spaced, with an ellipsis when cut.
    public static func clip(_ s: String?, _ n: Int) -> String? {
        guard let s, !s.isEmpty else { return nil }
        let one = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return one.count <= n ? one : String(one.prefix(n - 1)) + "…"
    }
}
