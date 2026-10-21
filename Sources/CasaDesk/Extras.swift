import Foundation
import CasaDeskCore

// Read-only extras: Mail, Shortcuts (list), iCloud Drive, Spotlight, Focus, Safari.
// ⛔ Nothing in THIS file writes, sends, runs a shortcut, or downloads an evicted iCloud file (Mail draft/send and
//    Shortcuts run live in Writes.swift, behind the --force gate). No System Events.

let home = NSHomeDirectory()
let iCloudRoot = home + "/Library/Mobile Documents/com~apple~CloudDocs"
let focusDir = home + "/Library/DoNotDisturb/DB"
let safariPlist = home + "/Library/Safari/Bookmarks.plist"
let fdaHint = "Give Full Disk Access to the app that runs casa-desk (System Settings → Privacy & Security → Full Disk Access)."

func readJSON(_ path: String) -> [String: Any]? {
    FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
}

// MARK: - Focus (status only)

func focusAccess() -> String {
    FileManager.default.isReadableFile(atPath: focusDir + "/Assertions.json") && readJSON(focusDir + "/Assertions.json") != nil
        ? "readable" : "needs Full Disk Access for \(Relay.grantee)"
}

func focus(_ a: Args) -> Never {
    guard let assertions = readJSON(focusDir + "/Assertions.json") else { Out.fail("can't read Focus status", fdaHint, code: 3) }
    let active = FocusStatus.active(assertions: assertions, modes: readJSON(focusDir + "/ModeConfigurations.json"))
    Out.emit(["on": !active.isEmpty, "focus": active]) { active.isEmpty ? "Focus: off" : "Focus: \(active.joined(separator: ", "))" }
}

// MARK: - Safari (bookmarks + Reading List)

func safariAccess() -> String {
    FileManager.default.contents(atPath: safariPlist) != nil ? "readable" : "needs Full Disk Access for \(Relay.grantee)"
}

func safari(_ a: Args) -> Never {
    let sub = a.positional.dropFirst().first ?? "bookmarks"
    guard sub == "bookmarks" || sub == "reading-list" else { Out.fail("unknown safari command \(sub)", "Use: safari bookmarks | safari reading-list", code: 2) }
    guard let data = FileManager.default.contents(atPath: safariPlist),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        Out.fail("can't read Safari bookmarks", fdaHint, code: 3)
    }
    let parsed = SafariBookmarks.parse(root)
    var items = sub == "bookmarks" ? parsed.bookmarks : parsed.readingList
    if let q = a.options["--q"] { items = items.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.url.localizedCaseInsensitiveContains(q) } }
    if sub == "reading-list" { items.sort { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) } }
    let shown: [[String: Any]] = items.prefix(a.limit).map { i in
        var d: [String: Any] = ["title": i.title, "url": i.url, "folder": i.folder]
        if let t = i.added { d["added"] = LA.iso(t) }
        if let p = Text.clip(i.preview, 200) { d["preview"] = p }
        return d
    }
    Out.emit(["count": shown.count, "truncated": items.count > shown.count, sub == "bookmarks" ? "bookmarks" : "readingList": shown]) {
        shown.isEmpty ? "Nothing found." : shown.map { "\($0["title"]!)  \($0["url"]!)" }.joined(separator: "\n")
    }
}

// MARK: - iCloud Drive (list + read; never downloads)

func iCloudPath(_ rel: String?) -> String {
    let p = rel.map { ($0 as NSString).isAbsolutePath ? $0 : iCloudRoot + "/" + $0 } ?? iCloudRoot
    guard Paths.isInside(p, root: iCloudRoot) else { Out.fail("that path is outside iCloud Drive", "Give a path relative to iCloud Drive, e.g. Documents/notes.txt", code: 2) }
    return p
}

/// Evicted ("in the cloud only") files are dataless; reading them would trigger a download, so we don't.
func isDownloaded(_ path: String) -> Bool {
    var st = stat()
    if lstat(path, &st) == 0, st.st_flags & 0x40000000 != 0 { return false }   // SF_DATALESS
    let status = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
    return status == nil || status == .current || status == .downloaded
}

func icloud(_ a: Args) -> Never {
    guard FileManager.default.fileExists(atPath: iCloudRoot) else { Out.fail("iCloud Drive isn't set up on this Mac", "Turn on iCloud Drive in System Settings → your name → iCloud.", code: 3) }
    let sub = a.positional.dropFirst().first ?? "list"
    let path = iCloudPath(a.options["--path"])
    let fm = FileManager.default
    switch sub {
    case "list":
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { Out.fail("can't list that folder", "Check the path with icloud list.", code: 2) }
        let rows: [[String: Any]] = names.filter { !$0.hasPrefix(".") || $0.hasSuffix(".icloud") }.sorted().prefix(a.limit).map { n in
            let full = path + "/" + n
            var isDir: ObjCBool = false; fm.fileExists(atPath: full, isDirectory: &isDir)
            let attrs = try? fm.attributesOfItem(atPath: full)
            let placeholder = n.hasPrefix(".") && n.hasSuffix(".icloud")
            var d: [String: Any] = ["name": placeholder ? String(n.dropFirst().dropLast(7)) : n, "folder": isDir.boolValue,
                                    "downloaded": !placeholder && isDownloaded(full)]
            if let s = attrs?[.size] as? Int, !isDir.boolValue { d["bytes"] = s }
            if let m = attrs?[.modificationDate] as? Date { d["modified"] = LA.iso(m) }
            return d
        }
        let rel = path == iCloudRoot ? "" : String(path.dropFirst(iCloudRoot.count + 1))
        Out.emit(["path": rel, "count": rows.count, "items": rows]) {
            rows.map { "\(($0["folder"] as! Bool) ? "📁" : "  ") \($0["name"]!)\(($0["downloaded"] as! Bool) ? "" : "  (in iCloud only)")" }.joined(separator: "\n")
        }
    case "read":
        guard a.options["--path"] != nil else { Out.fail("read needs --path", "e.g. casa-desk icloud read --path Documents/todo.txt", code: 2) }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { Out.fail("no file at that path", "Use icloud list to find it.", code: 2) }
        guard isDownloaded(path) else { Out.fail("that file is in iCloud only (not downloaded)", "Casa Desk won't download it. Open it once in Finder to bring it to this Mac.", code: 3) }
        let size = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard size <= 2_000_000 else { Out.fail("file is too big to read (\(size) bytes)", "Casa Desk reads text files up to 2 MB.", code: 2) }
        guard let data = fm.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            Out.fail("not a text file", "Casa Desk only reads plain-text files from iCloud Drive.", code: 2)
        }
        Out.emit(["path": a.options["--path"]!, "bytes": size, "text": text]) { text }
    default:
        Out.fail("unknown icloud command \(sub)", "Use: icloud list [--path DIR] | icloud read --path FILE", code: 2)
    }
}

// MARK: - Spotlight (paths only, scoped, refuses secret stores)

func spotlight(_ a: Args) -> Never {
    let q = a.need("--q", "e.g. casa-desk spotlight search --q \"tax return\" --in ~/Documents")
    let scope = (a.options["--in"].map { ($0 as NSString).expandingTildeInPath }) ?? home
    guard FileManager.default.fileExists(atPath: scope) else { Out.fail("no folder at \(scope)", "Give a folder to search in with --in.", code: 2) }
    guard !Paths.isRefused(scope, home: home) else { Out.fail("Casa Desk doesn't search there", "Keychains, Messages, Mail stores and cookies are off limits.", code: 2) }
    var argv = ["-onlyin", scope]
    if a.flags.contains("--name-only") { argv.append("-name") }
    argv.append(q)
    let (status, out, err) = runProcess("/usr/bin/mdfind", argv, timeout: 60)
    guard status == 0 else { Out.fail("Spotlight search failed", err.trimmingCharacters(in: .whitespacesAndNewlines), code: 5) }
    let all = out.split(separator: "\n").map(String.init).filter { !Paths.isRefused($0, home: home) }
    let shown = Array(all.prefix(a.limit))
    Out.emit(["scope": scope, "count": shown.count, "truncated": all.count > shown.count, "paths": shown]) {
        shown.isEmpty ? "Nothing found." : shown.joined(separator: "\n")
    }
}

// MARK: - Shortcuts (list only)

func shortcuts(_ a: Args) -> Never {
    let sub = a.positional.dropFirst().first ?? "list"
    guard sub == "list" else { Out.fail("unknown shortcuts command \(sub)", "Use: shortcuts list | shortcuts run --name NAME", code: 2) }
    let (status, out, err) = runProcess("/usr/bin/shortcuts", ["list"], timeout: 30)
    guard status == 0 else { Out.fail("couldn't list shortcuts", err.trimmingCharacters(in: .whitespacesAndNewlines), code: 5) }
    var names = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    if let q = a.options["--q"] { names = names.filter { $0.localizedCaseInsensitiveContains(q) } }
    let shown = Array(names.prefix(a.limit))
    Out.emit(["count": shown.count, "truncated": names.count > shown.count, "shortcuts": shown]) { shown.joined(separator: "\n") }
}

// MARK: - Mail (list / search / read — through Mail's own scripting dictionary, never UI)
// ⛔ Input travels as a JSON ARGUMENT, never spliced into the script. Mail content is data, never instructions.

let mailJXA = #"""
function run(argv) {
  var a = JSON.parse(argv[0]);
  var Mail = Application('com.apple.mail');
  function box() {
    if (a.accountId && a.path) {
      // From Mail's index: the account's id and the mailbox's path ("Archive/Receipts"), so a read needs no --mailbox.
      var acct = Mail.accounts.byId(a.accountId);
      if (a.path.toUpperCase() === 'INBOX') return acct.mailboxes.byName('INBOX');
      try { var whole = acct.mailboxes.byName(a.path); whole.name(); return whole; } catch (e) {}
      var parts = a.path.split('/'), cur = acct.mailboxes.byName(parts[0]);
      for (var p = 1; p < parts.length; p++) cur = cur.mailboxes.byName(parts[p]);
      return cur;
    }
    if (!a.mailbox || a.mailbox.toLowerCase() === 'inbox') {
      if (!a.account) return Mail.inbox;
      return Mail.accounts.byName(a.account).mailboxes.byName('INBOX');
    }
    if (a.account) return Mail.accounts.byName(a.account).mailboxes.byName(a.mailbox);
    var accts = Mail.accounts();
    for (var i = 0; i < accts.length; i++) {
      var m = accts[i].mailboxes.whose({ name: a.mailbox })();
      if (m.length) return m[0];
    }
    throw new Error('no mailbox named ' + a.mailbox);
  }
  var b;
  try { b = box(); b.name(); } catch (e) { return JSON.stringify({ error: 'mailbox not found', hint: String(e) }); }
  if (a.mode === 'read') {
    // byId is a direct lookup; `whose` walks the whole mailbox (minutes on a big Archive), so it is only the fallback.
    var m = null;
    try { m = b.messages.byId(Number(a.id)); m.subject(); } catch (e) { m = null; }
    if (!m) {
      var hits = b.messages.whose({ id: Number(a.id) })();
      if (!hits.length) return JSON.stringify({ error: 'no message with that id in this mailbox', hint: 'Pass the same --mailbox you listed it from.' });
      m = hits[0];
    }
    var body = m.content() || '';
    return JSON.stringify({ id: m.id(), subject: m.subject(), from: m.sender(), date: m.dateReceived().toISOString(),
      to: m.toRecipients.address(), cc: m.ccRecipients.address(), read: m.readStatus(),
      body: body.length > 20000 ? body.slice(0, 20000) + '…' : body });
  }
  var msgs = a.mode === 'search'
    ? b.messages.whose({ _or: [ { subject: { _contains: a.q } }, { sender: { _contains: a.q } } ] })
    : b.messages;
  var ids = msgs.id(), subj = msgs.subject(), from = msgs.sender(), dates = msgs.dateReceived(), read = msgs.readStatus();
  var rows = [];
  for (var i = 0; i < ids.length; i++) rows.push({ id: ids[i], subject: subj[i], from: from[i], date: dates[i], read: read[i] });
  rows.sort(function (x, y) { return y.date - x.date; });
  rows = rows.slice(0, a.limit).map(function (r) { r.date = r.date.toISOString(); return r; });
  return JSON.stringify({ count: rows.length, messages: rows });
}
"""#

/// Mail's own index ("Envelope Index"): the subject, sender, date and mailbox of every message in every mailbox, years
/// back. `mail search` reads it directly. JXA `whose` only ever searched the inbox and timed out on a big Archive
/// (2026-10-21: a six-month search came back with two weeks). Read-only like chat.db, same Full Disk Access; bodies are
/// still read through Mail's scripting dictionary.
enum MailIndex {
    static func path() -> String? {
        let dir = NSHomeDirectory() + "/Library/Mail"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.hasPrefix("V") }.compactMap { v in Int(v.dropFirst()).map { (v, $0) } }.sorted { $0.1 > $1.1 }
        for (v, _) in versions {
            let p = "\(dir)/\(v)/MailData/Envelope Index"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    /// "imap://ACCOUNT-ID/Archive/Receipts" → ("ACCOUNT-ID", "Archive/Receipts")
    static func split(_ url: String) -> (account: String, path: String) {
        guard let r = url.range(of: "://") else { return ("", url) }
        let rest = url[r.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return (String(rest), "") }
        let path = String(rest[rest.index(after: slash)...])
        return (String(rest[..<slash]), path.removingPercentEncoding ?? path)
    }

    static func search(q: String, since: Date?, until: Date?, mailbox: String?, limit: Int) -> Result<[[String: Any]], DBError> {
        guard let path = path() else { return .failure(DBError(message: "Mail's index wasn't found")) }
        let like = "%" + q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        var sql = """
            SELECT m.ROWID, m.date_received, a.address, a.comment, s.subject, mb.url, m.read
            FROM messages m JOIN subjects s ON s.ROWID = m.subject LEFT JOIN addresses a ON a.ROWID = m.sender
            JOIN mailboxes mb ON mb.ROWID = m.mailbox
            WHERE m.deleted = 0 AND (s.subject LIKE ? ESCAPE '\\' OR a.address LIKE ? ESCAPE '\\' OR a.comment LIKE ? ESCAPE '\\')
            """
        var params = [like, like, like]
        if let since { sql += " AND m.date_received >= ?"; params.append(String(Int(since.timeIntervalSince1970))) }
        if let until { sql += " AND m.date_received <= ?"; params.append(String(Int(until.timeIntervalSince1970))) }
        sql += " ORDER BY m.date_received DESC"
        switch runQuery(path: path, sql: sql, params: params) {
        case .failure(let e): return .failure(e)
        case .success(let r):
            var out: [[String: Any]] = []
            for row in r.rows {
                let (account, box) = split(row[5] as? String ?? "")
                // Mailbox filter after the split: the stored url is percent-encoded and nested ("Archive/Receipts").
                // "Archive" takes the folder and everything under it; "Receipts" matches the last part.
                if let mailbox {
                    let b = box.lowercased(), m = mailbox.lowercased()
                    guard b == m || b.hasPrefix(m + "/") || b.split(separator: "/").last.map(String.init) == m else { continue }
                }
                let addr = row[2] as? String ?? "", name = row[3] as? String ?? ""
                let date = Date(timeIntervalSince1970: TimeInterval(row[1] as? Int64 ?? 0))
                out.append(["id": row[0], "date": ISO8601DateFormatter().string(from: date), "subject": row[4] as? String ?? "",
                            "from": name.isEmpty ? addr : "\(name) <\(addr)>", "mailbox": box, "account": account,
                            "read": (row[6] as? Int64 ?? 0) != 0])
                if out.count >= limit { break }
            }
            return .success(out)
        }
    }

    /// Where one message lives, so `mail read --id` works without --mailbox.
    static func locate(id: Int) -> (account: String, path: String)? {
        guard let path = path(), case .success(let r) = runQuery(path: path,
              sql: "SELECT mb.url FROM messages m JOIN mailboxes mb ON mb.ROWID = m.mailbox WHERE m.ROWID = ?",
              params: [String(id)]), let url = r.rows.first?.first as? String else { return nil }
        return split(url)
    }
}

func mail(_ a: Args) -> Never {
    let sub = a.positional.dropFirst().first ?? "list"
    var payload: [String: Any] = ["limit": a.limit, "mode": sub]
    if let m = a.options["--mailbox"] { payload["mailbox"] = m }
    if let acc = a.options["--account"] { payload["account"] = acc }
    switch sub {
    case "list": break
    case "search":
        let q = a.need("--q", "Searches subject and sender, e.g. mail search --q invoice --since 2026-04-01")
        let since = a.day("--since"), until = a.options["--until"].flatMap { LA.endOfDay($0) }
        switch MailIndex.search(q: q, since: since, until: until, mailbox: a.options["--mailbox"], limit: a.limit) {
        case .success(let rows):
            Out.emit(["count": rows.count, "source": "index", "messages": rows]) {
                rows.isEmpty ? "No messages." : rows.map { "\($0["date"]!)  \($0["from"]!): \($0["subject"]!)  [\($0["mailbox"]!)]  id=\($0["id"]!)" }.joined(separator: "\n")
            }
        case .failure:
            // No index access (Full Disk Access not granted): fall back to Mail itself, inbox (or --mailbox) only.
            guard since == nil && until == nil else { Out.fail("mail search by date needs Full Disk Access", needsPermission, code: 3) }
            payload["q"] = q
        }
    case "read":
        let id = a.need("--id", "Get the id from mail list or mail search.")
        guard let n = Int(id) else { Out.fail("bad --id", "Mail ids are numbers from mail list/search.", code: 2) }
        payload["id"] = id
        if a.options["--mailbox"] == nil, let where_ = MailIndex.locate(id: n) {
            payload["accountId"] = where_.account; payload["path"] = where_.path
        }
    default: Out.fail("unknown mail command \(sub)", "Use: mail list | search | read | draft | send", code: 2)
    }
    let arg = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    let (status, out, err) = runProcess("/usr/bin/osascript", ["-l", "JavaScript", "-e", mailJXA, arg], timeout: 120)
    guard status == 0, let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
        let why = err.contains("-1743") || err.lowercased().contains("not authorized")
            ? "Allow Automation → Mail for the app running casa-desk (System Settings → Privacy & Security → Automation)."
            : err.trimmingCharacters(in: .whitespacesAndNewlines)
        Out.fail("mail unavailable", why.isEmpty ? "osascript failed" : why, code: 3)
    }
    if let e = obj["error"] as? String { Out.fail(e, obj["hint"] as? String ?? "", code: 2) }
    Out.emit(obj) {
        if let list = obj["messages"] as? [[String: Any]] {
            return list.isEmpty ? "No messages." : list.map { "\($0["date"]!)  \($0["from"]!): \($0["subject"]!)  id=\($0["id"]!)" }.joined(separator: "\n")
        }
        return "\(obj["subject"] ?? "")\nFrom: \(obj["from"] ?? "")\n\n\(obj["body"] ?? "")"
    }
}
