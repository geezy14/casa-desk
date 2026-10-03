import Foundation
import EventKit
import Contacts
import CasaDeskCore

// Casa Desk — a local, READ-ONLY Apple toolkit for assistants (v1, 2026-10-03).
//
// ⛔ READ-ONLY BY CONSTRUCTION. There is no code path that creates, changes or deletes anything: no EKEventStore.save,
//    no CNSaveRequest, no Notes/Mail writes, no sends, no Shortcuts runs. Never UI scripting (no System Events).
// ⛔ LOCAL ONLY. Nothing here opens a network connection. Output goes to stdout for the assistant that ran it.
// ⛔ Times are America/Los_Angeles.

// MARK: - Output

struct Out {
    nonisolated(unsafe) static var json = false   // set once at startup, before anything reads it

    static func emit(_ obj: Any, human: () -> String) -> Never {
        if json {
            let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            print(human())
        }
        exit(0)
    }

    static func fail(_ error: String, _ hint: String, code: Int32 = 1, extra: [String: Any] = [:]) -> Never {
        if json {
            var obj: [String: Any] = extra; obj["error"] = error; obj["hint"] = hint
            let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            FileHandle.standardError.write(Data("error: \(error)\nhint: \(hint)\n".utf8))
        }
        exit(code)
    }
}

let needsPermission = "needs permission: run casa-desk doctor --request (and click Allow), or allow it in System Settings → Privacy & Security"

// MARK: - Arguments

struct Args {
    var positional: [String] = []
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ raw: [String]) {
        var i = 0
        // Every --option takes a value except these switches. `--opt=value` also works (for values starting with "--").
        let switches: Set<String> = ["--json", "--request", "--help", "--groups", "--include-completed",
                                     "--name-only"]
        while i < raw.count {
            let a = raw[i]
            if a.hasPrefix("--"), let eq = a.firstIndex(of: "=") { options[String(a[..<eq])] = String(a[a.index(after: eq)...]); i += 1; continue }
            if a.hasPrefix("--"), !switches.contains(a), i + 1 < raw.count { options[a] = raw[i + 1]; i += 2; continue }
            if a.hasPrefix("--") { flags.insert(a); i += 1; continue }
            positional.append(a); i += 1
        }
    }

    func need(_ key: String, _ hint: String) -> String {
        guard let v = options[key], !v.trimmingCharacters(in: .whitespaces).isEmpty else { Out.fail("missing \(key)", hint, code: 2) }
        return v
    }

    var limit: Int { max(1, min(500, Int(options["--limit"] ?? "") ?? 50)) }

    func day(_ key: String) -> Date? {
        guard let s = options[key] else { return nil }
        guard let d = LA.day(s) else { Out.fail("bad date for \(key): \(s)", "Use YYYY-MM-DD, e.g. 2026-10-03.", code: 2) }
        return d
    }
}

// MARK: - Permissions

func eventStatus(_ type: EKEntityType) -> String {
    switch EKEventStore.authorizationStatus(for: type) {
    case .fullAccess: return "granted"
    case .writeOnly: return "write-only (needs full access to read)"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not asked yet"
    @unknown default: return "unknown"
    }
}

func contactsStatus() -> String {
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized: return "granted"
    case .limited: return "limited"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "not asked yet"
    @unknown default: return "unknown"
    }
}

func requireEvents(_ store: EKEventStore, _ type: EKEntityType) async {
    if EKEventStore.authorizationStatus(for: type) == .fullAccess { return }
    Out.fail("no \(type == .event ? "calendar" : "reminders") access", needsPermission, code: 3)
}

// MARK: - Commands

func doctor(_ a: Args) async -> Never {
    if a.flags.contains("--request") {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToEvents()
        _ = try? await store.requestFullAccessToReminders()
        _ = try? await CNContactStore().requestAccess(for: .contacts)
    }
    let report: [String: Any] = [
        "calendar": eventStatus(.event),
        "reminders": eventStatus(.reminder),
        "contacts": contactsStatus(),
        "notes": "asks on first use (Automation → Notes)",
        "messages": messagesStatus(),
        "mail": "asks on first use (Automation → Mail)",
        "shortcuts": "list only (no permission needed)",
        "focus": focusAccess(),
        "safari": safariAccess(),
        "icloudDrive": FileManager.default.fileExists(atPath: iCloudRoot) ? "available" : "not set up on this Mac",
        "readOnly": true,
        "version": "0.2.0",
    ]
    Out.emit(report) {
        ["casa-desk 0.2.0",
         "calendar:  \(report["calendar"]!)", "reminders: \(report["reminders"]!)", "contacts:  \(report["contacts"]!)",
         "notes:     \(report["notes"]!)", "messages:  \(report["messages"]!)", "mail:      \(report["mail"]!)",
         "focus:     \(report["focus"]!)", "safari:    \(report["safari"]!)", "icloud:    \(report["icloudDrive"]!)",
         "read-only: yes"].joined(separator: "\n")
    }
}

func eventDict(_ e: EKEvent) -> [String: Any] {
    var d: [String: Any] = [
        "id": e.eventIdentifier ?? "", "title": e.title ?? "", "start": LA.iso(e.startDate), "end": LA.iso(e.endDate),
        "allDay": e.isAllDay, "calendar": e.calendar?.title ?? "",
    ]
    if let l = e.location, !l.isEmpty { d["location"] = l }
    if let n = Text.clip(e.notes, 300) { d["notes"] = n }
    if let u = e.url?.absoluteString { d["url"] = u }
    return d
}

func calendar(_ a: Args) async -> Never {
    let store = EKEventStore()
    await requireEvents(store, .event)
    let sub = a.positional.dropFirst().first ?? "list"
    let today = LA.calendar.startOfDay(for: Date())
    var from = a.day("--from") ?? today
    var to = a.options["--to"].flatMap { LA.endOfDay($0) } ?? LA.calendar.date(byAdding: .day, value: 7, to: from)!
    if sub == "search" && a.options["--from"] == nil { from = LA.calendar.date(byAdding: .day, value: -90, to: today)! }
    if sub == "search" && a.options["--to"] == nil { to = LA.calendar.date(byAdding: .day, value: 90, to: today)! }
    guard to > from else { Out.fail("--to is before --from", "Give a range that moves forward.", code: 2) }
    var cals = store.calendars(for: .event)
    if let name = a.options["--calendar"] {
        cals = cals.filter { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }
        if cals.isEmpty { Out.fail("no calendar named \(name)", "Calendars: \(store.calendars(for: .event).map(\.title).joined(separator: ", "))", code: 2) }
    }
    var events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: cals))
        .sorted { $0.startDate < $1.startDate }
    if sub == "search" {
        guard let q = a.options["--q"], !q.isEmpty else { Out.fail("search needs --q", "e.g. casa-desk calendar search --q dentist", code: 2) }
        events = events.filter { ($0.title ?? "").localizedCaseInsensitiveContains(q) || ($0.location ?? "").localizedCaseInsensitiveContains(q)
            || ($0.notes ?? "").localizedCaseInsensitiveContains(q) }
    } else if sub != "list" {
        Out.fail("unknown calendar command \(sub)", "Use: calendar list | calendar search", code: 2)
    }
    let shown = events.prefix(a.limit).map(eventDict)
    Out.emit(["from": LA.dayString(from), "to": LA.dayString(to.addingTimeInterval(-1)), "count": shown.count,
              "truncated": events.count > shown.count, "events": shown]) {
        shown.isEmpty ? "No events." : shown.map { "\($0["start"]!)  \($0["title"]!)  [\($0["calendar"]!)]" }.joined(separator: "\n")
    }
}

func reminders(_ a: Args) async -> Never {
    let store = EKEventStore()
    await requireEvents(store, .reminder)
    let sub = a.positional.dropFirst().first ?? "list"
    let lists = store.calendars(for: .reminder)
    if sub == "lists" {
        let names = lists.map(\.title).sorted()
        Out.emit(["count": names.count, "lists": names]) { names.joined(separator: "\n") }
    }
    guard sub == "list" else { Out.fail("unknown reminders command \(sub)", "Use: reminders lists | reminders list", code: 2) }
    var cals = lists
    if let name = a.options["--list"] {
        cals = lists.filter { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }
        if cals.isEmpty { Out.fail("no reminders list named \(name)", "Lists: \(lists.map(\.title).joined(separator: ", "))", code: 2) }
    }
    let includeDone = a.flags.contains("--include-completed")
    let dueBy = a.options["--due-by"].flatMap { LA.endOfDay($0) }
    if a.options["--due-by"] != nil && dueBy == nil { Out.fail("bad date for --due-by", "Use YYYY-MM-DD.", code: 2) }
    let predicate = includeDone ? store.predicateForReminders(in: cals)
        : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: dueBy, calendars: cals)
    let items: [[String: Any]] = await withCheckedContinuation { cont in
        store.fetchReminders(matching: predicate) { rs in
            let rows = (rs ?? []).map { r -> [String: Any] in
                var d: [String: Any] = ["id": r.calendarItemIdentifier, "title": r.title ?? "", "list": r.calendar?.title ?? "", "completed": r.isCompleted,
                                        "priority": r.priority]
                if let dc = r.dueDateComponents, let due = LA.calendar.date(from: dc) {
                    d["due"] = dc.hour == nil ? LA.dayString(due) : LA.iso(due)
                }
                if let n = Text.clip(r.notes, 300) { d["notes"] = n }
                return d
            }
            cont.resume(returning: rows)
        }
    }
    let sorted = items.sorted { ($0["due"] as? String ?? "9999") < ($1["due"] as? String ?? "9999") }
    let shown = Array(sorted.prefix(a.limit))
    Out.emit(["count": shown.count, "truncated": sorted.count > shown.count, "reminders": shown]) {
        shown.isEmpty ? "No reminders." : shown.map { "\($0["due"] ?? "—")  \($0["title"]!)  [\($0["list"]!)]" }.joined(separator: "\n")
    }
}

nonisolated(unsafe) let contactKeys: [CNKeyDescriptor] = [
    CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
    CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactBirthdayKey,
].map { $0 as CNKeyDescriptor } + [CNContactFormatter.descriptorForRequiredKeys(for: .fullName)]

func contactDict(_ c: CNContact) -> [String: Any] {
    var d: [String: Any] = [
        "id": c.identifier,
        "name": CNContactFormatter.string(from: c, style: .fullName) ?? "\(c.givenName) \(c.familyName)",
        "phones": c.phoneNumbers.map { $0.value.stringValue },
        "emails": c.emailAddresses.map { $0.value as String },
    ]
    if !c.nickname.isEmpty { d["nickname"] = c.nickname }
    if !c.organizationName.isEmpty { d["organization"] = c.organizationName }
    if let b = c.birthday, let m = b.month, let day = b.day {
        d["birthday"] = b.year.map { String(format: "%04d-%02d-%02d", $0, m, day) } ?? String(format: "--%02d-%02d", m, day)
    }
    return d
}

func contacts(_ a: Args) -> Never {
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
        Out.fail("no contacts access", needsPermission, code: 3)
    }
    let store = CNContactStore()
    let sub = a.positional.dropFirst().first ?? "search"
    if sub == "show" {
        guard let id = a.options["--id"] else { Out.fail("show needs --id", "Get an id from contacts search.", code: 2) }
        guard let c = try? store.unifiedContact(withIdentifier: id, keysToFetch: contactKeys) else {
            Out.fail("no contact with that id", "Search again; ids can change after a merge.", code: 2)
        }
        let d = contactDict(c)
        Out.emit(d) { "\(d["name"]!)\n" + (d["phones"] as! [String]).joined(separator: "\n") }
    }
    guard sub == "search", let q = a.options["--q"]?.trimmingCharacters(in: .whitespaces), !q.isEmpty else {
        Out.fail("use: contacts search --q TEXT | contacts show --id ID", "Search matches name, nickname, phone and email.", code: 2)
    }
    var found: [CNContact] = []
    let isPhone = Phone.looksLikePhone(q), qKey = Phone.key(q)
    let req = CNContactFetchRequest(keysToFetch: contactKeys)
    try? store.enumerateContacts(with: req) { c, stop in
        let name = (CNContactFormatter.string(from: c, style: .fullName) ?? "") + " " + c.nickname
        let hit = name.localizedCaseInsensitiveContains(q)
            || c.organizationName.localizedCaseInsensitiveContains(q)
            || c.emailAddresses.contains { ($0.value as String).localizedCaseInsensitiveContains(q) }
            || (isPhone && c.phoneNumbers.contains { Phone.key($0.value.stringValue) == qKey })
        if hit { found.append(c) }
        if found.count >= a.limit { stop.pointee = true }
    }
    let rows = found.map(contactDict)
    Out.emit(["count": rows.count, "contacts": rows]) {
        rows.isEmpty ? "No contacts match." : rows.map { "\($0["name"]!)  \(($0["phones"] as! [String]).first ?? "")  id=\($0["id"]!)" }.joined(separator: "\n")
    }
}

// Notes has no public framework, so this goes through the Notes app with JavaScript for Automation.
// ⛔ The query travels as a JSON ARGUMENT, never spliced into script text — no injection.
let notesJXA = #"""
function run(argv) {
  var a = JSON.parse(argv[0]);
  var Notes = Application('Notes');
  function iso(d) { return d ? d.toISOString() : null; }
  function row(n, full) {
    var body = n.plaintext() || '';
    var folder = ''; try { folder = n.container().name(); } catch (e) {}
    return { id: n.id(), title: n.name(), folder: folder, modified: iso(n.modificationDate()),
             body: full ? body : body.replace(/\s+/g, ' ').slice(0, 200) };
  }
  if (a.mode === 'show') {
    var n = Notes.notes.byId(a.id);
    try { n.name(); } catch (e) { return JSON.stringify({ error: 'no note with that id', hint: 'Search again.' }); }
    return JSON.stringify(row(n, true));
  }
  var q = a.q;
  var hits = Notes.notes.whose({ _or: [ { name: { _contains: q } }, { plaintext: { _contains: q } } ] })();
  var out = [];
  for (var i = 0; i < hits.length && out.length < a.limit; i++) { out.push(row(hits[i], false)); }
  return JSON.stringify({ count: out.length, notes: out });
}
"""#

func runProcess(_ path: String, _ args: [String], timeout: TimeInterval = 60) -> (Int32, String, String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { return (127, "", "\(error)") }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if p.isRunning { p.terminate(); return (124, "", "timed out after \(Int(timeout))s (a permission dialog may be waiting on screen)") }
    let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (p.terminationStatus, o, e)
}

func notes(_ a: Args) -> Never {
    let sub = a.positional.dropFirst().first ?? "search"
    var payload: [String: Any] = ["limit": a.limit]
    if sub == "show" {
        guard let id = a.options["--id"] else { Out.fail("show needs --id", "Get an id from notes search.", code: 2) }
        payload["mode"] = "show"; payload["id"] = id
    } else if sub == "search" {
        guard let q = a.options["--q"], !q.isEmpty else { Out.fail("search needs --q", "e.g. casa-desk notes search --q wifi", code: 2) }
        payload["mode"] = "search"; payload["q"] = q
    } else { Out.fail("unknown notes command \(sub)", "Use: notes search | notes show", code: 2) }
    let arg = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    let (status, out, err) = runProcess("/usr/bin/osascript", ["-l", "JavaScript", "-e", notesJXA, arg], timeout: 90)
    guard status == 0, let data = out.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        let why = err.contains("-1743") || err.lowercased().contains("not authorized")
            ? "Allow Automation → Notes for the app running casa-desk (System Settings → Privacy & Security → Automation)."
            : err.trimmingCharacters(in: .whitespacesAndNewlines)
        Out.fail("notes unavailable", why.isEmpty ? "osascript failed" : why, code: 3)
    }
    if let e = obj["error"] as? String { Out.fail(e, obj["hint"] as? String ?? "", code: 2) }
    Out.emit(obj) {
        if let list = obj["notes"] as? [[String: Any]] {
            return list.isEmpty ? "No notes match." : list.map { "\($0["title"]!)  [\($0["folder"]!)]  id=\($0["id"]!)" }.joined(separator: "\n")
        }
        return "\(obj["title"] ?? "")\n\n\(obj["body"] ?? "")"
    }
}

// Messages lives in Messages.swift (native read-only chat.db reader).

// MARK: - Main

let usage = """
casa-desk 0.2.0 — read-only Apple data for your assistants (local only, never UI scripting)

  casa-desk doctor [--request]
  casa-desk calendar list   [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--calendar NAME]
  casa-desk calendar search --q TEXT [--from …] [--to …]
  casa-desk reminders lists
  casa-desk reminders list  [--list NAME] [--due-by YYYY-MM-DD] [--include-completed]
  casa-desk contacts search --q TEXT        (name, nickname, phone, email)
  casa-desk contacts show   --id ID
  casa-desk notes search    --q TEXT
  casa-desk notes show      --id ID
  casa-desk messages search --who NAME|NUMBER|EMAIL [--since --until --grep --groups]
  casa-desk messages search --search TEXT [--since --until]
  casa-desk messages chats  [--q NAME]       (conversations with their chatGuid)
  casa-desk mail list       [--mailbox NAME] [--account NAME]
  casa-desk mail search     --q TEXT          (subject and sender)
  casa-desk mail read       --id ID [--mailbox NAME]
  casa-desk shortcuts list  [--q TEXT]
  casa-desk icloud list     [--path DIR]
  casa-desk icloud read     --path FILE       (text, downloaded files only)
  casa-desk spotlight search --q TEXT [--in DIR] [--name-only]
  casa-desk focus status
  casa-desk safari bookmarks [--q TEXT]
  casa-desk safari reading-list [--q TEXT]

  --json for JSON, --limit N (default 50). Nothing here writes, deletes, sends or runs anything.
"""

let args = Args(Array(CommandLine.arguments.dropFirst()))
Out.json = args.flags.contains("--json")
switch args.positional.first {
case "doctor": await doctor(args)
case "calendar": await calendar(args)
case "reminders": await reminders(args)
case "contacts": contacts(args)
case "notes": notes(args)
case "messages": messages(args)
case "mail": mail(args)
case "shortcuts": shortcuts(args)
case "icloud": icloud(args)
case "spotlight": spotlight(args)
case "focus": focus(args)
case "safari": safari(args)
case "help", nil: print(usage); exit(0)
default: Out.fail("unknown command \(args.positional.first!)", "Run casa-desk help.", code: 2)
}
