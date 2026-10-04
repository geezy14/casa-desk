import Foundation
import SQLite3
import Contacts
import CasaDeskCore

// Messages history, read straight from ~/Library/Messages/chat.db.
// ⛔ READ-ONLY: opened with SQLITE_OPEN_READONLY and `mode=ro`. Never writes, never marks read, never sends.
// ⛔ Needs Full Disk Access for whatever app runs casa-desk (Terminal, Grok Bot…). doctor says so plainly.

let chatDBPath = NSHomeDirectory() + "/Library/Messages/chat.db"

final class ChatDB {
    let db: OpaquePointer

    init?() {
        var h: OpaquePointer?
        let uri = "file:\(chatDBPath)?mode=ro"
        guard sqlite3_open_v2(uri, &h, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let h else {
            if let h { sqlite3_close(h) }
            return nil
        }
        // Opening can "succeed" without access; a real read proves it.
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(h, "SELECT 1 FROM message LIMIT 1", -1, &st, nil) == SQLITE_OK else { sqlite3_close(h); return nil }
        sqlite3_finalize(st)
        db = h
    }
    deinit { sqlite3_close(db) }

    struct Row { let date: Date; let fromMe: Bool; let handle: String; let text: String; let chatName: String?; let isGroup: Bool; let chatGuid: String }

    /// Messages matching the filters, newest first. `handles` limits to those people (1:1 unless includeGroups).
    func query(handles: [String]?, search: String?, since: Date?, until: Date?, includeGroups: Bool, limit: Int) -> [Row] {
        var sql = """
        SELECT m.date, m.is_from_me, COALESCE(h.id, ''), m.text, m.attributedBody, c.display_name, c.style, COALESCE(c.guid, '')
        FROM message m
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN chat c ON c.ROWID = cmj.chat_id
        WHERE (m.text IS NOT NULL OR m.attributedBody IS NOT NULL)
        """
        var binds: [Any] = []
        if let since { sql += " AND m.date >= ?"; binds.append(AppleTime.raw(since)) }
        if let until { sql += " AND m.date < ?"; binds.append(AppleTime.raw(until)) }
        if let handles {
            let ph = handles.map { _ in "?" }.joined(separator: ",")
            // The person's own messages, plus mine in a chat that person is in.
            sql += """
             AND c.ROWID IN (SELECT chj.chat_id FROM chat_handle_join chj JOIN handle hh ON hh.ROWID = chj.handle_id
                             WHERE hh.id IN (\(ph)))
            """
            binds += handles
            if !includeGroups { sql += " AND c.style = 45" }
        }
        sql += " ORDER BY m.date DESC"
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, b) in binds.enumerated() {
            if let v = b as? Int64 { sqlite3_bind_int64(st, Int32(i + 1), v) }
            else if let s = b as? String { sqlite3_bind_text(st, Int32(i + 1), s, -1, transient) }
        }
        var rows: [Row] = []
        // A search with few hits walks the whole history (~1M rows ≈ 8s); --since makes it fast.
        while sqlite3_step(st) == SQLITE_ROW {
            let date = AppleTime.date(sqlite3_column_int64(st, 0))
            let fromMe = sqlite3_column_int(st, 1) == 1
            let handle = String(cString: sqlite3_column_text(st, 2))
            var text = sqlite3_column_text(st, 3).map { String(cString: $0) } ?? ""
            if text.isEmpty, let blob = sqlite3_column_blob(st, 4) {
                let n = Int(sqlite3_column_bytes(st, 4))
                let bytes = Array(UnsafeBufferPointer(start: blob.assumingMemoryBound(to: UInt8.self), count: n))
                text = TypedStream.string(from: bytes) ?? ""
            }
            text = text.replacingOccurrences(of: "\u{FFFC}", with: "[attachment]").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if let search, !text.localizedCaseInsensitiveContains(search) { continue }
            let chatName = sqlite3_column_text(st, 5).map { String(cString: $0) }
            let isGroup = sqlite3_column_int(st, 6) == 43
            let guid = String(cString: sqlite3_column_text(st, 7))
            rows.append(Row(date: date, fromMe: fromMe, handle: handle, text: text, chatName: chatName?.isEmpty == true ? nil : chatName, isGroup: isGroup, chatGuid: guid))
            if rows.count >= limit { break }
        }
        return rows
    }
}

/// Names for phone numbers and emails, from the Contacts framework (when allowed). Without access, handles stay raw.
struct HandleNames {
    var byKey: [String: String] = [:]

    init() {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { return }
        let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey].map { $0 as CNKeyDescriptor }
            + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]
        try? CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { c, _ in
            guard let name = CNContactFormatter.string(from: c, style: .fullName), !name.isEmpty else { return }
            for p in c.phoneNumbers { byKey[Phone.key(p.value.stringValue)] = name }
            for e in c.emailAddresses { byKey[(e.value as String).lowercased()] = name }
        }
    }

    func name(_ handle: String) -> String? {
        handle.contains("@") ? byKey[handle.lowercased()] : byKey[Phone.key(handle)]
    }

    /// Every chat.db handle that belongs to people whose name contains `query` (or the query itself if it's a number/email).
    func handles(for query: String, in db: ChatDB) -> [String] {
        var all: [String] = []
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db.db, "SELECT DISTINCT id FROM handle", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW { all.append(String(cString: sqlite3_column_text(st, 0))) }
        }
        sqlite3_finalize(st)
        if query.contains("@") { return all.filter { $0.lowercased() == query.lowercased() } }
        if Phone.looksLikePhone(query) { let k = Phone.key(query); return all.filter { Phone.key($0) == k } }
        return all.filter { (name($0) ?? "").localizedCaseInsensitiveContains(query) }
    }
}

func messages(_ a: Args) -> Never {
    guard let db = ChatDB() else {
        Out.fail("can't read Messages history", "Give Full Disk Access to the app that runs casa-desk (System Settings → Privacy & Security → Full Disk Access), then try again.", code: 3)
    }
    let names = HandleNames()
    if a.positional.dropFirst().first == "chats" { chats(a, db, names) }
    guard a.positional.dropFirst().first ?? "search" == "search" else { Out.fail("unknown messages command", "Use: messages search | messages chats", code: 2) }
    let since = a.day("--since"), until = a.options["--until"].flatMap { LA.endOfDay($0) }
    var handles: [String]? = nil
    var search = a.options["--search"]
    if search?.isEmpty == true { Out.fail("--search needs text", "e.g. casa-desk messages search --search dinner --since 2026-09-01", code: 2) }
    if search == nil {
        guard let who = a.options["--who"], !who.isEmpty else {
            Out.fail("use: messages search --who NAME|NUMBER|EMAIL  or  --search TEXT", "Optional: --since --until --grep --groups --limit", code: 2)
        }
        let hs = names.handles(for: who, in: db)
        if hs.isEmpty {
            let why = CNContactStore.authorizationStatus(for: .contacts) == .authorized
                ? "No conversation found for \(who). Try a phone number or email."
                : "Allow Contacts (casa-desk doctor --request) so names work, or pass a phone number or email."
            Out.fail("no one matched \(who)", why, code: 2)
        }
        handles = hs
        search = a.options["--grep"]
    }
    let rows = db.query(handles: handles, search: search, since: since, until: until,
                        includeGroups: a.flags.contains("--groups") || handles == nil, limit: a.limit)
    let out: [[String: Any]] = rows.map { r in
        var d: [String: Any] = ["date": LA.iso(r.date), "from": r.fromMe ? "me" : (names.name(r.handle) ?? r.handle), "text": r.text]
        if r.isGroup { d["group"] = r.chatName ?? "group chat"; d["chatGuid"] = r.chatGuid }
        return d
    }
    Out.emit(["count": out.count, "messages": out]) {
        out.isEmpty ? "No messages." : out.reversed().map { "\($0["date"]!)  \($0["from"]!): \($0["text"]!)" }.joined(separator: "\n")
    }
}

/// For doctor: can this process read chat.db right now?
func messagesStatus() -> String {
    ChatDB() != nil ? "granted (Full Disk Access)" : "needs Full Disk Access for \(Relay.grantee)"
}

/// Recent conversations (newest first) with their guid, name and people — for finding a group chat.
func chats(_ a: Args, _ db: ChatDB, _ names: HandleNames) -> Never {
    let sql = """
    SELECT c.ROWID, c.guid, COALESCE(c.display_name, ''), c.style, MAX(cmj.message_date)
    FROM chat c JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
    GROUP BY c.ROWID ORDER BY 5 DESC
    """
    var st: OpaquePointer?, people: OpaquePointer?
    guard sqlite3_prepare_v2(db.db, sql, -1, &st, nil) == SQLITE_OK,
          sqlite3_prepare_v2(db.db, "SELECT h.id FROM chat_handle_join chj JOIN handle h ON h.ROWID = chj.handle_id WHERE chj.chat_id = ?", -1, &people, nil) == SQLITE_OK
    else { Out.fail("couldn't read chats", "chat.db layout not recognized.", code: 5) }
    defer { sqlite3_finalize(st); sqlite3_finalize(people) }
    let q = a.options["--q"]
    var rows: [[String: Any]] = []
    while sqlite3_step(st) == SQLITE_ROW, rows.count < a.limit {
        sqlite3_reset(people); sqlite3_bind_int64(people, 1, sqlite3_column_int64(st, 0))
        var who: [String] = []
        while sqlite3_step(people) == SQLITE_ROW { let h = String(cString: sqlite3_column_text(people, 0)); who.append(names.name(h) ?? h) }
        let name = String(cString: sqlite3_column_text(st, 2))
        if let q, !name.localizedCaseInsensitiveContains(q), !who.contains(where: { $0.localizedCaseInsensitiveContains(q) }) { continue }
        rows.append(["chatGuid": String(cString: sqlite3_column_text(st, 1)), "name": name.isEmpty ? who.joined(separator: ", ") : name,
                     "group": sqlite3_column_int(st, 3) == 43, "people": who, "lastMessage": LA.iso(AppleTime.date(sqlite3_column_int64(st, 4)))])
    }
    Out.emit(["count": rows.count, "chats": rows]) {
        rows.map { "\($0["lastMessage"]!)  \($0["name"]!)\(($0["group"] as! Bool) ? "  (group)" : "")" }.joined(separator: "\n")
    }
}
