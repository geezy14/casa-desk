import Foundation
import CryptoKit

// Pure helpers for v2 writes and sends (no Apple app frameworks) so they can be unit-tested.

extension LA {
    /// "2026-10-03T09:30", "2026-10-03 09:30" or "2026-10-03T09:30:00" → that LA moment. nil if malformed.
    public static func dateTime(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let sep = t.firstIndex(where: { $0 == "T" || $0 == " " }) else { return nil }
        guard let day = day(String(t[..<sep])) else { return nil }
        let hm = t[t.index(after: sep)...].split(separator: ":")
        guard (2...3).contains(hm.count), hm.allSatisfy({ $0.count == 2 }),
              let h = Int(hm[0]), let m = Int(hm[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        let sec = hm.count == 3 ? Int(hm[2]) : 0
        guard let sec, (0...59).contains(sec) else { return nil }
        var dc = calendar.dateComponents([.year, .month, .day], from: day)
        dc.hour = h; dc.minute = m; dc.second = sec
        return calendar.date(from: dc)
    }

    /// A reminder due date: "YYYY-MM-DD" (all-day, no hour) or a date-time. nil if malformed.
    public static func dueComponents(_ s: String) -> DateComponents? {
        if let d = day(s) {
            var dc = calendar.dateComponents([.year, .month, .day], from: d); dc.timeZone = tz; return dc
        }
        guard let d = dateTime(s) else { return nil }
        var dc = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d); dc.timeZone = tz
        return dc
    }
}

public enum Handle {
    /// A phone number in the +1XXXXXXXXXX form Messages uses for US numbers; emails lowercased; anything else as given.
    public static func normalize(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains("@") { return t.lowercased() }
        let d = t.filter(\.isNumber)
        if d.count == 10 { return "+1" + d }
        if d.count == 11, d.hasPrefix("1") { return "+" + d }
        return t.hasPrefix("+") ? "+" + d : d
    }

    /// Is this a phone number or an email (as opposed to a name)?
    public static func isAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return (t.contains("@") && !t.contains(" ")) || Phone.looksLikePhone(t)
    }
}

/// The optional send allowlist: one phone number, email or chat guid per line; `#` starts a comment.
/// No file (or an empty one) means no allowlist — every send still needs --force and its confirm code.
public struct Allowlist {
    public let entries: [String]
    public init(text: String) {
        entries = text.split(whereSeparator: \.isNewline)
            .map { $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    public var isActive: Bool { !entries.isEmpty }

    public func allows(_ target: String) -> Bool {
        guard isActive else { return true }
        let t = target.trimmingCharacters(in: .whitespaces)
        return entries.contains { e in
            if e == t { return true }                                            // chat guid, exact
            if e.contains("@") || t.contains("@") { return e.lowercased() == t.lowercased() }
            return Phone.looksLikePhone(e) && Phone.looksLikePhone(t) && Phone.key(e) == Phone.key(t)
        }
    }
}

public enum ConfirmCode {
    /// 8 hex characters tied to the exact send: what, where, and the exact text. Change one character and the code changes,
    /// so the text the person approved in the preview is the only text --confirm can send.
    public static func make(_ parts: [String]) -> String {
        let joined = parts.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(joined.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

public enum HTML {
    /// Plain text → safe HTML for a Notes body: escaped, newlines as <br>.
    public static func fromText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br>")
    }
}
