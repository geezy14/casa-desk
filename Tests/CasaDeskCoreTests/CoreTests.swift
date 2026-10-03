import XCTest
@testable import CasaDeskCore

final class CoreTests: XCTestCase {
    func testDayParsesInLosAngeles() {
        let d = LA.day("2026-10-03")
        XCTAssertNotNil(d)
        XCTAssertEqual(LA.iso(d!), "2026-10-03T00:00:00-07:00")
        XCTAssertEqual(LA.dayString(d!), "2026-10-03")
    }

    func testDayRejectsMalformed() {
        XCTAssertNil(LA.day("2026-13-01"))
        XCTAssertNil(LA.day("2026-02-30"))
        XCTAssertNil(LA.day("10/03/2026"))
        XCTAssertNil(LA.day("26-10-03"))
    }

    func testEndOfDayIsNextMidnight() {
        XCTAssertEqual(LA.iso(LA.endOfDay("2026-10-03")!), "2026-10-04T00:00:00-07:00")
        // Across the DST change (Nov 1 2026): still the next LA midnight.
        XCTAssertEqual(LA.iso(LA.endOfDay("2026-11-01")!), "2026-11-02T00:00:00-08:00")
    }

    func testPhoneKeyLastTenDigits() {
        XCTAssertEqual(Phone.key("+1 (323) 555-0142"), "3235550142")
        XCTAssertEqual(Phone.key("3235550142"), "3235550142")
        XCTAssertEqual(Phone.key("+13235550142"), "3235550142")
        XCTAssertEqual(Phone.key("555-0142"), "5550142")
    }

    func testLooksLikePhone() {
        XCTAssertTrue(Phone.looksLikePhone("(323) 555-0142"))
        XCTAssertTrue(Phone.looksLikePhone("+1 323 555 0142"))
        XCTAssertFalse(Phone.looksLikePhone("Sam"))
        XCTAssertFalse(Phone.looksLikePhone("123"))
    }

    func testAppleTimeNanosAndSeconds() {
        // 2026-10-03 00:00 LA = 812_703_600 s after 2001-01-01.
        let secs: Int64 = 812_703_600
        XCTAssertEqual(LA.iso(AppleTime.date(secs)), "2026-10-03T00:00:00-07:00")
        XCTAssertEqual(LA.iso(AppleTime.date(secs * 1_000_000_000)), "2026-10-03T00:00:00-07:00")
        XCTAssertEqual(AppleTime.raw(LA.day("2026-10-03")!), secs * 1_000_000_000)
    }

    func testTypedStreamShortAndLongStrings() {
        func blob(_ s: String) -> [UInt8] {
            let body = Array(s.utf8)
            let len: [UInt8] = body.count < 0x80 ? [UInt8(body.count)] : [0x81, UInt8(body.count & 0xFF), UInt8(body.count >> 8)]
            return [0x04, 0x0B] + Array("streamtyped".utf8) + [0x84, 0x01] + Array("NSString".utf8) + [0x01, 0x94, 0x84, 0x01, 0x2B] + len + body + [0x86]
        }
        XCTAssertEqual(TypedStream.string(from: blob("on my way 🚗")), "on my way 🚗")
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(TypedStream.string(from: blob(long)), long)
        XCTAssertNil(TypedStream.string(from: Array("no marker here".utf8)))
        XCTAssertNil(TypedStream.string(from: Array("NSString".utf8) + [0x2B, 0x50, 0x41]))   // length past the end
    }

    func testClip() {
        XCTAssertNil(Text.clip(nil, 10))
        XCTAssertEqual(Text.clip("a  b\nc", 10), "a b c")
        XCTAssertEqual(Text.clip("abcdefghijkl", 5), "abcd…")
    }
}
