import XCTest
@testable import CasaDeskCore

final class WriteCoreTests: XCTestCase {
    func testDateTimeParsesInLosAngeles() {
        XCTAssertEqual(LA.iso(LA.dateTime("2026-10-06T09:30")!), "2026-10-06T09:30:00-07:00")
        XCTAssertEqual(LA.iso(LA.dateTime("2026-12-01 18:05")!), "2026-12-01T18:05:00-08:00")
        XCTAssertEqual(LA.iso(LA.dateTime("2026-10-06T09:30:15")!), "2026-10-06T09:30:15-07:00")
    }

    func testDateTimeRejectsMalformed() {
        for s in ["2026-10-06", "2026-10-06T25:00", "2026-10-06T9:30", "2026-02-30T10:00", "10/06/2026 09:30", "2026-10-06T09:60"] {
            XCTAssertNil(LA.dateTime(s), s)
        }
    }

    func testDueComponents() {
        let day = LA.dueComponents("2026-10-06")!
        XCTAssertEqual([day.year, day.month, day.day], [2026, 10, 6])
        XCTAssertNil(day.hour)
        let timed = LA.dueComponents("2026-10-06T17:00")!
        XCTAssertEqual(timed.hour, 17); XCTAssertEqual(timed.minute, 0)
        XCTAssertNil(LA.dueComponents("tomorrow"))
    }

    func testHandleNormalize() {
        XCTAssertEqual(Handle.normalize("(323) 555-0100"), "+13235550100")
        XCTAssertEqual(Handle.normalize("1-323-555-0100"), "+13235550100")
        XCTAssertEqual(Handle.normalize("+44 20 7946 0000"), "+442079460000")
        XCTAssertEqual(Handle.normalize(" Someone@Example.COM "), "someone@example.com")
        XCTAssertTrue(Handle.isAddress("323-555-0100"))
        XCTAssertTrue(Handle.isAddress("a@b.co"))
        XCTAssertFalse(Handle.isAddress("Mom"))
        XCTAssertFalse(Handle.isAddress("Jo Smith"))
    }

    func testAllowlist() {
        XCTAssertFalse(Allowlist(text: "").isActive)
        XCTAssertTrue(Allowlist(text: "# nothing yet\n\n").allows("+13235550100"), "an empty allowlist is off")
        let list = Allowlist(text: "+1 (323) 555-0100  # me\nFriend@Example.com\niMessage;+;chat123\n")
        XCTAssertTrue(list.isActive)
        XCTAssertEqual(list.entries.count, 3)
        XCTAssertTrue(list.allows("3235550100"))
        XCTAssertTrue(list.allows("friend@example.com"))
        XCTAssertTrue(list.allows("iMessage;+;chat123"))
        XCTAssertFalse(list.allows("+13235550199"))
        XCTAssertFalse(list.allows("stranger@example.com"))
        XCTAssertFalse(list.allows("iMessage;+;chat124"))
    }

    func testConfirmCodeIsTiedToExactText() {
        let a = ConfirmCode.make(["messages", "iMessage", "+13235550100", "on my way"])
        XCTAssertEqual(a.count, 8)
        XCTAssertEqual(a, ConfirmCode.make(["messages", "iMessage", "+13235550100", "on my way"]))
        XCTAssertNotEqual(a, ConfirmCode.make(["messages", "iMessage", "+13235550100", "on my way!"]))
        XCTAssertNotEqual(a, ConfirmCode.make(["messages", "iMessage", "+13235550101", "on my way"]))
        // The separator can't be faked by moving text between fields.
        XCTAssertNotEqual(ConfirmCode.make(["a", "bc"]), ConfirmCode.make(["ab", "c"]))
    }

    func testHTMLEscapes() {
        XCTAssertEqual(HTML.fromText("a < b & \"c\"\nnext"), "a &lt; b &amp; &quot;c&quot;<br>next")
        XCTAssertEqual(HTML.fromText("<script>x</script>"), "&lt;script&gt;x&lt;/script&gt;")
    }
}
