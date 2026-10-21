import Foundation
import SQLite3

// `db` — read-only SQL over Apple's own local databases, for scripts that need more than the other commands give
// (a daily digest that counts every conversation, reads calendar colours and attendees, double-checks reminders…).
// Running it through Casa Desk means only Casa Desk needs Full Disk Access, not every script that wants the data.
// ⛔ READ-ONLY, three ways: SQLITE_OPEN_READONLY + `mode=ro`, `PRAGMA query_only`, and sqlite3_stmt_readonly on the
//    one statement (SELECT / WITH only — anything else is refused). Values are bound parameters, never spliced (rule 6).
// ⛔ Only these files: Messages, Calendar, Reminders, Contacts, and Mail's Envelope Index (subjects, senders, dates,
//    mailboxes — never message bodies) — no other path is opened.

enum AppleDB {
    static let home = NSHomeDirectory()
    /// The databases each name covers (Reminders and Contacts keep one file per account).
    static func files(_ name: String) -> [String] {
        let fm = FileManager.default
        func each(_ dir: String, _ pick: (String) -> String?) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted().compactMap(pick).filter { fm.fileExists(atPath: $0) }
        }
        switch name {
        case "messages": return [home + "/Library/Messages/chat.db"]
        case "calendar": return [home + "/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"]
        case "reminders":
            let d = home + "/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
            return each(d) { $0.hasSuffix(".sqlite") ? d + "/" + $0 : nil }
        case "contacts":
            let d = home + "/Library/Application Support/AddressBook/Sources"
            return each(d) { d + "/" + $0 + "/AddressBook-v22.abcddb" }
        case "mail": return MailIndex.path().map { [$0] } ?? []
        default: return []
        }
    }
    static let names = ["messages", "calendar", "reminders", "contacts", "mail"]
    /// A path is allowed only if it is one of the files above.
    static func allowed(_ path: String) -> Bool {
        let p = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return names.flatMap(files).contains { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path == p }
    }
}

func db(_ a: Args) {
    let sub = a.positional.dropFirst().first ?? ""
    switch sub {
    case "files":
        let name = a.need("--db", "--db messages|calendar|reminders|contacts|mail")
        guard AppleDB.names.contains(name) else { Out.fail("unknown database \(name)", "Use messages, calendar, reminders, contacts or mail.", code: 2) }
        let fs = AppleDB.files(name)
        Out.emit(["db": name, "files": fs]) { fs.joined(separator: "\n") }
    case "query":
        let sql = a.need("--sql", "--sql \"SELECT …\" (bound values: --param V, repeat in order)")
        let paths: [String]
        if let p = a.options["--path"] {
            guard AppleDB.allowed(p) else { Out.fail("not an allowed database", "--path must be one listed by `casa-desk db files`.", code: 2) }
            paths = [p]
        } else {
            let name = a.need("--db", "--db messages|calendar|reminders|contacts|mail, or --path FILE")
            guard AppleDB.names.contains(name) else { Out.fail("unknown database \(name)", "Use messages, calendar, reminders, contacts or mail.", code: 2) }
            paths = AppleDB.files(name)
        }
        let head = sql.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard head.hasPrefix("select") || head.hasPrefix("with") else { Out.fail("read-only: SELECT or WITH only", "This command never changes anything.", code: 2) }
        let params = a.multi["--param"] ?? []
        var results: [[String: Any]] = []
        for path in paths {
            switch runQuery(path: path, sql: sql, params: params) {
            case .success(let r): results.append(["file": path, "columns": r.columns, "rows": r.rows])
            case .failure(let e): results.append(["file": path, "error": e.message])
            }
        }
        if paths.count == 1, let err = results.first?["error"] as? String {
            Out.fail(err, err.contains("authoriz") || err.contains("open") ? needsPermission : "Check the SQL.", extra: ["file": paths[0]])
        }
        Out.emit(["results": results]) { results.map { r in "\(r["file"] ?? ""): \((r["rows"] as? [Any])?.count ?? 0) rows" }.joined(separator: "\n") }
    default:
        Out.fail("unknown db command", "casa-desk db files --db NAME · casa-desk db query --db NAME|--path FILE --sql S [--param V …]", code: 2)
    }
}

struct DBError: Error { let message: String }

func runQuery(path: String, sql: String, params: [String]) -> Result<(columns: [String], rows: [[Any]]), DBError> {
    var h: OpaquePointer?
    guard sqlite3_open_v2("file:\(path)?mode=ro", &h, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let h else {
        if let h { sqlite3_close(h) }
        return .failure(DBError(message: "couldn't open \(URL(fileURLWithPath: path).lastPathComponent)"))
    }
    defer { sqlite3_close(h) }
    sqlite3_exec(h, "PRAGMA query_only = 1", nil, nil, nil)
    var st: OpaquePointer?
    var tail: UnsafePointer<CChar>?
    guard sqlite3_prepare_v2(h, sql, -1, &st, &tail) == SQLITE_OK, let st else {
        return .failure(DBError(message: String(cString: sqlite3_errmsg(h))))
    }
    defer { sqlite3_finalize(st) }
    if let tail, !String(cString: tail).trimmingCharacters(in: CharacterSet(charactersIn: " \n\t;")).isEmpty {
        return .failure(DBError(message: "one statement only"))
    }
    guard sqlite3_stmt_readonly(st) != 0 else { return .failure(DBError(message: "read-only: that statement would write")) }
    for (i, v) in params.enumerated() {
        let idx = Int32(i + 1)
        if let n = Int64(v) { sqlite3_bind_int64(st, idx, n) }
        else if let d = Double(v) { sqlite3_bind_double(st, idx, d) }
        else { sqlite3_bind_text(st, idx, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    let n = sqlite3_column_count(st)
    let cols = (0..<n).map { String(cString: sqlite3_column_name(st, $0)) }
    var rows: [[Any]] = []
    while true {
        let rc = sqlite3_step(st)
        if rc == SQLITE_DONE { break }
        guard rc == SQLITE_ROW else { return .failure(DBError(message: String(cString: sqlite3_errmsg(h)))) }
        var row: [Any] = []
        for c in 0..<n {
            switch sqlite3_column_type(st, c) {
            case SQLITE_INTEGER: row.append(sqlite3_column_int64(st, c))
            case SQLITE_FLOAT: row.append(sqlite3_column_double(st, c))
            case SQLITE_TEXT: row.append(String(cString: sqlite3_column_text(st, c)))
            case SQLITE_BLOB:
                let len = Int(sqlite3_column_bytes(st, c))
                let data = len > 0 ? Data(bytes: sqlite3_column_blob(st, c), count: len) : Data()
                row.append(["b64": data.base64EncodedString()])
            default: row.append(NSNull())
            }
        }
        rows.append(row)
        if rows.count >= 500_000 { return .failure(DBError(message: "more than 500,000 rows — narrow the query")) }
    }
    return .success((cols, rows))
}
