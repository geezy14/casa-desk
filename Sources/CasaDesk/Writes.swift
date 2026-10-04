import Foundation
import SQLite3
import EventKit
import Contacts
import CasaDeskCore

// v2 writes and sends — "everything but System Events" (2026-10-03).
//
// ⛔ EVERY change is a DRY RUN unless --force is given (and --dry-run always wins). The dry run prints the exact change;
//    the assistant shows it to the person and runs the same command with --force only after they say yes.
// ⛔ SENDS (Messages, Mail) also need --confirm CODE. The code comes from the dry run and is tied to the exact recipient
//    and text, so only the text the person approved can go out. Each code sends ONCE (a repeat needs --again).
// ⛔ The only delete is `calendar delete --id ID --force`. Nothing else deletes: reminders complete, notes append,
//    contacts gain fields, a canceled event is kept and marked.
// ⛔ Never System Events / UI scripting. Apps are driven through EventKit, Contacts, or their own scripting dictionary,
//    with input passed as a JSON argument — never spliced into script text.
// ⛔ Optional allowlist for sends: ~/.config/casa-desk/allowlist (one number, email or chat guid per line).

let configDir = home + "/.config/casa-desk"
let stateDir = home + "/Library/Application Support/casa-desk"
let logPath = home + "/Library/Logs/casa-desk/actions.jsonl"

// MARK: - The gate

enum WriteMode { case preview, apply }

func writeMode(_ a: Args) -> WriteMode {
    if a.flags.contains("--dry-run") { return .preview }
    return a.flags.contains("--force") ? .apply : .preview
}

func lines(_ d: [String: Any]) -> String {
    d.keys.sorted().map { k in
        let v = d[k]!
        if let sub = v as? [String: Any] { return "  \(k): " + sub.keys.sorted().map { "\($0)=\(sub[$0]!)" }.joined(separator: ", ") }
        return "  \(k): \(v)"
    }.joined(separator: "\n")
}

/// Print what WOULD happen and stop. Nothing has changed.
func preview(_ action: String, _ would: [String: Any], code: String? = nil) -> Never {
    var obj: [String: Any] = ["dryRun": true, "changed": false, "action": action, "would": would]
    let hint: String
    if let code {
        obj["confirmCode"] = code
        hint = "Nothing was sent. Show the person exactly this. Only after they say yes, run the same command with --force --confirm \(code)."
    } else {
        hint = "Nothing changed. Show the person this. Only after they say yes, run the same command with --force."
    }
    obj["hint"] = hint
    Out.emit(obj) { "DRY RUN — \(action)\n\(lines(would))\n\(hint)" }
}

/// Record the change (time, action, target — never message text) and print it.
func done(_ action: String, target: String, _ result: [String: Any]) -> Never {
    ActionLog.append(action, target: target)
    Out.emit(["done": true, "changed": true, "action": action, "result": result]) { "DONE — \(action)\n\(lines(result))" }
}

enum ActionLog {
    static func append(_ action: String, target: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (logPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let row: [String: Any] = ["at": LA.iso(Date()), "action": action, "target": target]
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        data.append(Data("\n".utf8))
        if !fm.fileExists(atPath: logPath) { fm.createFile(atPath: logPath, contents: nil, attributes: [.posixPermissions: 0o600]) }
        if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(data); try? h.close() }
    }
}

// MARK: - Sends: allowlist, confirm code, send-once ledger

func loadAllowlist() -> Allowlist {
    Allowlist(text: (try? String(contentsOfFile: configDir + "/allowlist", encoding: .utf8)) ?? "")
}

enum SentLedger {
    static let path = stateDir + "/sent.json"
    static func load() -> [String: String] {
        FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
    }
    /// Claim `code` BEFORE sending, so a timeout that actually delivered can't be retried into a double send.
    static func claim(_ code: String, again: Bool) -> String? {
        var all = load()
        let dayAgo = Date().addingTimeInterval(-86_400)
        let f = ISO8601DateFormatter()
        all = all.filter { (f.date(from: $0.value) ?? .distantPast) > dayAgo }          // keep a day of history
        if let when = all[code], !again { return when }
        all[code] = f.string(from: Date())
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]) {
            FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
        }
        return nil
    }
}

/// Shared checks for a send that is about to go out. Fails unless --confirm matches the dry run's code.
func gateSend(_ a: Args, code: String, allowTarget: String) {
    guard loadAllowlist().allows(allowTarget) else {
        Out.fail("\(allowTarget) is not on the send allowlist", "Allowed recipients are in ~/.config/casa-desk/allowlist. The person edits that file, not the assistant.", code: 4)
    }
    guard let given = a.options["--confirm"] else {
        Out.fail("a send needs --confirm CODE", "Run the same command without --force first; it prints the exact message and its code.", code: 4)
    }
    guard given.lowercased() == code else {
        Out.fail("--confirm doesn't match this exact message", "The recipient or text changed since the dry run. Run the dry run again and get a new yes.", code: 4)
    }
    if let when = SentLedger.claim(code, again: a.flags.contains("--again")) {
        Out.fail("this exact message was already sent at \(when)", "Casa Desk sends each approved message once. If the person really wants it sent again, add --again.", code: 4)
    }
}

func runJXA(_ script: String, _ payload: [String: Any], app: String, timeout: TimeInterval = 90) -> [String: Any] {
    let arg = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
    let (status, out, err) = runProcess("/usr/bin/osascript", ["-l", "JavaScript", "-e", script, arg], timeout: timeout)
    guard status == 0, let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any] else {
        let why = err.contains("-1743") || err.lowercased().contains("not authorized")
            ? "Allow Automation → \(app) for the app running casa-desk (System Settings → Privacy & Security → Automation)."
            : err.trimmingCharacters(in: .whitespacesAndNewlines)
        Out.fail("\(app) didn't do it", why.isEmpty ? "osascript failed (exit \(status))" : why, code: 3)
    }
    if let e = obj["error"] as? String { Out.fail(e, obj["hint"] as? String ?? "", code: 2) }
    return obj
}

// MARK: - Reminders: add, complete, edit

func priorityValue(_ s: String?) -> Int? {
    guard let s else { return nil }
    switch s.lowercased() {
    case "high", "1": return 1
    case "medium", "5": return 5
    case "low", "9": return 9
    case "none", "0": return 0
    default: Out.fail("bad --priority \(s)", "Use high, medium, low or none.", code: 2)
    }
}

func dueOption(_ a: Args) -> DateComponents? {
    guard let s = a.options["--due"] else { return nil }
    guard let dc = LA.dueComponents(s) else { Out.fail("bad --due \(s)", "Use YYYY-MM-DD, or YYYY-MM-DDTHH:MM for a time.", code: 2) }
    return dc
}

func dueString(_ dc: DateComponents?) -> String {
    guard let dc, let d = LA.calendar.date(from: dc) else { return "none" }
    return dc.hour == nil ? LA.dayString(d) : LA.iso(d)
}

func reminderList(_ store: EKEventStore, _ name: String?) -> EKCalendar {
    if let name {
        let lists = store.calendars(for: .reminder)
        guard let l = lists.first(where: { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            Out.fail("no reminders list named \(name)", "Lists: \(lists.map(\.title).joined(separator: ", "))", code: 2)
        }
        return l
    }
    guard let l = store.defaultCalendarForNewReminders() else { Out.fail("no default reminders list", "Pass --list NAME.", code: 2) }
    return l
}

func reminderSnapshot(_ r: EKReminder) -> [String: Any] {
    var d: [String: Any] = ["title": r.title ?? "", "list": r.calendar?.title ?? "", "due": dueString(r.dueDateComponents),
                            "completed": r.isCompleted, "priority": r.priority]
    if let n = Text.clip(r.notes, 200) { d["notes"] = n }
    return d
}

func remindersWrite(_ a: Args, _ sub: String) async -> Never {
    let store = EKEventStore()
    await requireEvents(store, .reminder)
    let mode = writeMode(a)
    switch sub {
    case "add":
        let title = a.need("--title", "e.g. casa-desk reminders add --title \"Call the dentist\" --due 2026-10-06")
        let list = reminderList(store, a.options["--list"])
        guard list.allowsContentModifications else { Out.fail("the list \(list.title) is read-only", "Pick another --list.", code: 2) }
        let due = dueOption(a), pri = priorityValue(a.options["--priority"])
        var would: [String: Any] = ["title": title, "list": list.title, "due": dueString(due)]
        if let n = a.options["--notes"] { would["notes"] = n }
        if let pri { would["priority"] = pri }
        if mode == .preview { preview("add reminder", would) }
        let r = EKReminder(eventStore: store)
        r.title = title; r.calendar = list; r.dueDateComponents = due; r.notes = a.options["--notes"]
        if let pri { r.priority = pri }
        do { try store.save(r, commit: true) } catch { Out.fail("couldn't save the reminder", "\(error.localizedDescription)", code: 5) }
        var result = reminderSnapshot(r); result["id"] = r.calendarItemIdentifier
        done("add reminder", target: r.calendarItemIdentifier, result)

    case "complete", "edit":
        let id = a.need("--id", "Get the id from casa-desk reminders list.")
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { Out.fail("no reminder with that id", "List again; ids come from reminders list.", code: 2) }
        guard r.calendar?.allowsContentModifications != false else { Out.fail("that reminder's list is read-only", "It can't be changed from this Mac.", code: 2) }
        let before = reminderSnapshot(r)
        if sub == "complete" {
            if r.isCompleted { Out.fail("that reminder is already done", "Nothing to change.", code: 2) }
            if mode == .preview { preview("complete reminder", ["id": id, "reminder": before]) }
            r.isCompleted = true
        } else {
            if let t = a.options["--title"] { r.title = t }
            if a.flags.contains("--clear-due") { r.dueDateComponents = nil }
            else if let due = dueOption(a) { r.dueDateComponents = due }
            if let n = a.options["--notes"] { r.notes = n }
            if let pri = priorityValue(a.options["--priority"]) { r.priority = pri }
            if a.options["--list"] != nil { r.calendar = reminderList(store, a.options["--list"]) }
            let after = reminderSnapshot(r)
            if NSDictionary(dictionary: after).isEqual(to: before) { Out.fail("nothing to change", "Give --title, --due, --clear-due, --notes, --priority or --list.", code: 2) }
            if mode == .preview { preview("edit reminder", ["id": id, "before": before, "after": after]) }
        }
        do { try store.save(r, commit: true) } catch { Out.fail("couldn't save the reminder", "\(error.localizedDescription)", code: 5) }
        var result = reminderSnapshot(r); result["id"] = id
        done(sub == "complete" ? "complete reminder" : "edit reminder", target: id, result)

    default:
        Out.fail("unknown reminders command \(sub)", "Use: reminders lists | list | add | complete | edit", code: 2)
    }
}

// MARK: - Calendar: create, update, cancel, delete

func eventCalendar(_ store: EKEventStore, _ name: String?) -> EKCalendar {
    if let name {
        let cals = store.calendars(for: .event)
        guard let c = cals.first(where: { $0.title.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            Out.fail("no calendar named \(name)", "Calendars: \(cals.map(\.title).joined(separator: ", "))", code: 2)
        }
        guard c.allowsContentModifications else { Out.fail("the calendar \(c.title) is read-only", "Pick another --calendar.", code: 2) }
        return c
    }
    guard let c = store.defaultCalendarForNewEvents else { Out.fail("no default calendar", "Pass --calendar NAME.", code: 2) }
    return c
}

func moment(_ key: String, _ s: String, allDay: Bool) -> Date {
    if allDay {
        guard let d = LA.day(s) else { Out.fail("bad \(key) \(s)", "All-day events take YYYY-MM-DD.", code: 2) }
        return d
    }
    guard let d = LA.dateTime(s) else { Out.fail("bad \(key) \(s)", "Use YYYY-MM-DDTHH:MM (Los Angeles time), e.g. 2026-10-06T09:30.", code: 2) }
    return d
}

func eventSnapshot(_ e: EKEvent) -> [String: Any] {
    var d = eventDict(e)
    d.removeValue(forKey: "id")
    if e.hasAttendees { d["invitees"] = e.attendees?.count ?? 0 }
    if e.hasRecurrenceRules { d["repeats"] = true }
    return d
}

func calendarWrite(_ a: Args, _ sub: String) async -> Never {
    let store = EKEventStore()
    await requireEvents(store, .event)
    let mode = writeMode(a)
    let allDay = a.flags.contains("--all-day")

    if sub == "create" {
        let title = a.need("--title", "e.g. casa-desk calendar create --title \"Dentist\" --start 2026-10-06T09:30 --minutes 45")
        let cal = eventCalendar(store, a.options["--calendar"])
        let start = moment("--start", a.need("--start", "Give --start (YYYY-MM-DDTHH:MM, or YYYY-MM-DD with --all-day)."), allDay: allDay)
        var end: Date
        if let e = a.options["--end"] {
            end = moment("--end", e, allDay: allDay)          // all-day: the last day, inclusive (EventKit's own rule)
        } else if allDay {
            end = start
        } else {
            guard let mins = Int(a.options["--minutes"] ?? "60"), (1...1440).contains(mins) else { Out.fail("bad --minutes", "1 to 1440.", code: 2) }
            end = start.addingTimeInterval(Double(mins) * 60)
        }
        guard allDay ? end >= start : end > start else { Out.fail("the event ends before it starts", "Check --start and --end.", code: 2) }
        let e = EKEvent(eventStore: store)
        e.title = title; e.calendar = cal; e.isAllDay = allDay; e.startDate = start; e.endDate = end
        e.timeZone = allDay ? nil : LA.tz
        e.location = a.options["--location"]; e.notes = a.options["--notes"]
        if mode == .preview { preview("create event", eventSnapshot(e)) }
        do { try store.save(e, span: .thisEvent, commit: true) } catch { Out.fail("couldn't save the event", "\(error.localizedDescription)", code: 5) }
        var result = eventSnapshot(e); result["id"] = e.eventIdentifier ?? ""
        done("create event", target: e.eventIdentifier ?? "", result)
    }

    guard ["update", "cancel", "delete"].contains(sub) else {
        Out.fail("unknown calendar command \(sub)", "Use: calendar list | search | create | update | cancel | delete", code: 2)
    }
    let id = a.need("--id", "Get the id from casa-desk calendar list or search.")
    guard let e = store.event(withIdentifier: id) else { Out.fail("no event with that id", "List again; ids come from calendar list/search.", code: 2) }
    guard e.calendar?.allowsContentModifications != false else { Out.fail("that event's calendar is read-only", "It can't be changed from this Mac.", code: 2) }
    let before = eventSnapshot(e)
    var warn: [String] = []
    if e.hasAttendees { warn.append("this event has invitees; changing it may send them an update") }
    if e.hasRecurrenceRules { warn.append("it repeats; only this one occurrence changes") }

    switch sub {
    case "update":
        if let t = a.options["--title"] { e.title = t }
        if let l = a.options["--location"] { e.location = l }
        if let n = a.options["--notes"] { e.notes = n }
        if a.options["--calendar"] != nil { e.calendar = eventCalendar(store, a.options["--calendar"]) }
        if let s = a.options["--start"] {
            let length = e.endDate.timeIntervalSince(e.startDate)
            e.startDate = moment("--start", s, allDay: e.isAllDay)
            e.endDate = e.startDate.addingTimeInterval(length)                               // a move keeps its length
        }
        if let s = a.options["--end"] { e.endDate = moment("--end", s, allDay: e.isAllDay) }
        if let m = a.options["--minutes"] {
            guard let mins = Int(m), (1...1440).contains(mins) else { Out.fail("bad --minutes", "1 to 1440.", code: 2) }
            e.endDate = e.startDate.addingTimeInterval(Double(mins) * 60)
        }
        guard e.isAllDay ? e.endDate >= e.startDate : e.endDate > e.startDate else { Out.fail("the event would end before it starts", "Check --start/--end.", code: 2) }
        let after = eventSnapshot(e)
        if NSDictionary(dictionary: after).isEqual(to: before) { Out.fail("nothing to change", "Give --title, --start, --end, --minutes, --location, --notes or --calendar.", code: 2) }
        if mode == .preview { preview("update event", ["id": id, "before": before, "after": after, "warnings": warn]) }
    case "cancel":
        // Kept on the calendar and marked, never removed: EventKit can't set the status, so the title carries it.
        let t = e.title ?? ""
        if t.hasPrefix("Canceled: ") { Out.fail("that event is already marked canceled", "Nothing to change.", code: 2) }
        e.title = "Canceled: " + t
        if mode == .preview { let after = eventSnapshot(e); preview("cancel event (kept, marked canceled)", ["id": id, "before": before, "after": after, "warnings": warn]) }
    default: // delete
        if mode == .preview { preview("DELETE event", ["id": id, "event": before, "warnings": warn + ["this removes the event; it can't be undone from Casa Desk"]]) }
        do { try store.remove(e, span: .thisEvent, commit: true) } catch { Out.fail("couldn't delete the event", "\(error.localizedDescription)", code: 5) }
        done("delete event", target: id, ["id": id, "deleted": before])
    }
    do { try store.save(e, span: .thisEvent, commit: true) } catch { Out.fail("couldn't save the event", "\(error.localizedDescription)", code: 5) }
    var result = eventSnapshot(e); result["id"] = id
    done(sub == "cancel" ? "cancel event" : "update event", target: id, result)
}

// MARK: - Contacts: add, edit (no delete)

nonisolated(unsafe) let contactEditKeys: [CNKeyDescriptor] = contactKeys + [CNContactTypeKey as CNKeyDescriptor]

func contactsWrite(_ a: Args, _ sub: String) -> Never {
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else { Out.fail("no contacts access", needsPermission, code: 3) }
    let store = CNContactStore()
    let mode = writeMode(a)
    switch sub {
    case "add":
        let c = CNMutableContact()
        c.givenName = a.options["--first"] ?? ""
        c.familyName = a.options["--last"] ?? ""
        c.nickname = a.options["--nickname"] ?? ""
        c.organizationName = a.options["--org"] ?? ""
        guard !(c.givenName + c.familyName + c.organizationName).trimmingCharacters(in: .whitespaces).isEmpty else {
            Out.fail("a contact needs a name", "Give --first and/or --last (or --org).", code: 2)
        }
        if let p = a.options["--phone"] { c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: p))] }
        if let e = a.options["--email"] { c.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: e as NSString)] }
        var would = contactDict(c); would.removeValue(forKey: "id")
        // Warn about a likely duplicate so the person can say "edit that one instead".
        let name = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, let same = try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: contactKeys), !same.isEmpty {
            would["possibleDuplicates"] = same.prefix(5).map { ["id": $0.identifier, "name": CNContactFormatter.string(from: $0, style: .fullName) ?? ""] }
        }
        if mode == .preview { preview("add contact", would) }
        let req = CNSaveRequest(); req.add(c, toContainerWithIdentifier: nil)
        do { try store.execute(req) } catch { Out.fail("couldn't add the contact", "\(error.localizedDescription)", code: 5) }
        done("add contact", target: c.identifier, contactDict(c))

    case "edit":
        let id = a.need("--id", "Get the id from casa-desk contacts search.")
        guard let found = try? store.unifiedContact(withIdentifier: id, keysToFetch: contactEditKeys),
              let c = found.mutableCopy() as? CNMutableContact else { Out.fail("no contact with that id", "Search again; ids can change after a merge.", code: 2) }
        let before = contactDict(found)
        if let v = a.options["--first"] { c.givenName = v }
        if let v = a.options["--last"] { c.familyName = v }
        if let v = a.options["--nickname"] { c.nickname = v }
        if let v = a.options["--org"] { c.organizationName = v }
        if let p = a.options["--add-phone"] {
            if c.phoneNumbers.contains(where: { Phone.key($0.value.stringValue) == Phone.key(p) }) { Out.fail("that contact already has \(p)", "Nothing to change.", code: 2) }
            c.phoneNumbers.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: p)))
        }
        if let e = a.options["--add-email"] {
            if c.emailAddresses.contains(where: { ($0.value as String).lowercased() == e.lowercased() }) { Out.fail("that contact already has \(e)", "Nothing to change.", code: 2) }
            c.emailAddresses.append(CNLabeledValue(label: CNLabelHome, value: e as NSString))
        }
        let after = contactDict(c)
        if NSDictionary(dictionary: after).isEqual(to: before) { Out.fail("nothing to change", "Give --first, --last, --nickname, --org, --add-phone or --add-email. Casa Desk never removes fields.", code: 2) }
        if mode == .preview { preview("edit contact", ["id": id, "before": before, "after": after]) }
        let req = CNSaveRequest(); req.update(c)
        do { try store.execute(req) } catch { Out.fail("couldn't save the contact", "\(error.localizedDescription)", code: 5) }
        done("edit contact", target: id, after)

    default:
        Out.fail("unknown contacts command \(sub)", "Use: contacts search | show | add | edit (Casa Desk never deletes contacts)", code: 2)
    }
}

// MARK: - Notes: create, append (through the Notes app's scripting dictionary)

let notesWriteJXA = #"""
function run(argv) {
  var a = JSON.parse(argv[0]);
  var Notes = Application('com.apple.Notes');
  if (a.mode === 'create') {
    var folder;
    if (a.folder) {
      folder = Notes.folders.byName(a.folder);
      try { folder.name(); } catch (e) { return JSON.stringify({ error: 'no Notes folder named ' + a.folder, hint: 'Leave out --folder to use the default.' }); }
    } else {
      folder = Notes.defaultAccount.defaultFolder;
    }
    var n = Notes.Note({ body: a.html });
    folder.notes.push(n);
    return JSON.stringify({ id: n.id(), title: n.name(), folder: folder.name() });
  }
  var note = Notes.notes.byId(a.id);
  try { note.name(); } catch (e) { return JSON.stringify({ error: 'no note with that id', hint: 'Search again with notes search.' }); }
  if (note.passwordProtected()) return JSON.stringify({ error: 'that note is locked', hint: 'Casa Desk does not change locked notes.' });
  var folderName = ''; try { folderName = note.container().name(); } catch (e) {}
  if (a.mode === 'peek') return JSON.stringify({ id: note.id(), title: note.name(), folder: folderName });
  note.body = note.body() + '<div>' + a.html + '</div>';
  return JSON.stringify({ id: note.id(), title: note.name(), folder: folderName });
}
"""#

func notesWrite(_ a: Args, _ sub: String) -> Never {
    let mode = writeMode(a)
    switch sub {
    case "create":
        let title = a.need("--title", "e.g. casa-desk notes create --title \"Gate code\" --body \"4512\"")
        let body = a.options["--body"] ?? ""
        let html = "<div><h1>\(HTML.fromText(title))</h1></div>" + (body.isEmpty ? "" : "<div>\(HTML.fromText(body))</div>")
        var would: [String: Any] = ["title": title, "body": body]
        if let f = a.options["--folder"] { would["folder"] = f }
        if mode == .preview { preview("create note", would) }
        var payload: [String: Any] = ["mode": "create", "html": html]
        if let f = a.options["--folder"] { payload["folder"] = f }
        let r = runJXA(notesWriteJXA, payload, app: "Notes")
        done("create note", target: r["id"] as? String ?? "", r)
    case "append":
        let id = a.need("--id", "Get the id from casa-desk notes search.")
        let text = a.need("--text", "The text to add at the end of the note.")
        if mode == .preview {
            let peek = runJXA(notesWriteJXA, ["mode": "peek", "id": id], app: "Notes")
            preview("append to note", ["note": peek, "adds": text])
        }
        let r = runJXA(notesWriteJXA, ["mode": "append", "id": id, "html": HTML.fromText(text)], app: "Notes")
        done("append to note", target: id, r)
    default:
        Out.fail("unknown notes command \(sub)", "Use: notes search | show | create | append (Casa Desk never deletes notes)", code: 2)
    }
}

// MARK: - Messages: send (the Messages app's scripting dictionary — never UI scripting)

// ⚠️ By BUNDLE ID, never by name: on macOS 27, Application('Messages') resolved to "Messages Assistant Extension", and
// on the real app `service type` fails (AppleEvent handler failed), so picking an account by service crashed every
// 1:1 send (2026-10-04). Sends now go to a CHAT by its id — the conversation that already exists — which is what
// Messages itself does; it picks iMessage or SMS for that conversation. Mode 'check' resolves the target, sends nothing.
let messagesSendJXA = #"""
function run(argv) {
  var a = JSON.parse(argv[0]);
  var M = Application('com.apple.MobileSMS');
  function chat(id) { try { var c = M.chats.byId(id); c.id(); return c; } catch (e) { return null; } }
  var target = null, via = '';
  if (a.chatGuid) { target = chat(a.chatGuid); via = 'conversation'; }
  if (!target && a.to) { target = chat('any;-;' + a.to); via = 'conversation'; }
  if (!target && a.to) {
    try { var ps = M.participants.whose({ handle: a.to })(); if (ps.length) { target = ps[0]; via = 'participant'; } } catch (e) {}
  }
  if (!target) {
    return JSON.stringify(a.chatGuid
      ? { error: 'Messages has no chat with that id', hint: 'Get it again from casa-desk messages chats.' }
      : { error: 'no conversation with ' + a.to + ' in Messages yet', hint: 'Send the first message to this person from Messages yourself; after that Casa Desk can send to them.' });
  }
  if (a.mode === 'check') return JSON.stringify({ ok: true, via: via });
  M.send(a.text, { to: target });
  return JSON.stringify({ sent: true, via: via });
}
"""#

/// The newest 1:1 conversation id in chat.db for this handle (e.g. "any;-;+13235550100"), if there is one.
func oneToOneChat(_ handle: String) -> String? {
    guard let db = ChatDB() else { return nil }
    var st: OpaquePointer?
    defer { sqlite3_finalize(st) }
    let sql = """
    SELECT c.guid, c.chat_identifier, COALESCE(MAX(cmj.message_date), 0) FROM chat c
    LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
    WHERE c.style = 45 GROUP BY c.ROWID ORDER BY 3 DESC
    """
    guard sqlite3_prepare_v2(db.db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
    let wantEmail = handle.contains("@"), key = wantEmail ? handle.lowercased() : Phone.key(handle)
    while sqlite3_step(st) == SQLITE_ROW {
        let ident = String(cString: sqlite3_column_text(st, 1))
        if (wantEmail ? ident.lowercased() : Phone.key(ident)) == key, !ident.isEmpty {
            return String(cString: sqlite3_column_text(st, 0))
        }
    }
    return nil
}

/// --to NAME|NUMBER|EMAIL → one handle (and a name to show). A name must match exactly one number or email.
func resolveRecipient(_ to: String) -> (handle: String, name: String?) {
    if Handle.isAddress(to) {
        let h = Handle.normalize(to)
        return (h, HandleNames().name(h))
    }
    guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
        Out.fail("can't look up \(to) without Contacts access", "Pass a phone number or email with --to, or allow Contacts (casa-desk doctor --request).", code: 3)
    }
    let matches = (try? CNContactStore().unifiedContacts(matching: CNContact.predicateForContacts(matchingName: to), keysToFetch: contactKeys)) ?? []
    var options: [(String, String)] = []
    for c in matches {
        let name = CNContactFormatter.string(from: c, style: .fullName) ?? to
        for p in c.phoneNumbers { options.append((Handle.normalize(p.value.stringValue), name)) }
        for e in c.emailAddresses { options.append(((e.value as String).lowercased(), name)) }
    }
    var seen = Set<String>(); options = options.filter { seen.insert($0.0).inserted }
    if options.count == 1 { return (options[0].0, options[0].1) }
    if options.isEmpty { Out.fail("no contact with a number or email matches \(to)", "Pass the phone number or email with --to.", code: 2) }
    Out.fail("\(to) matches more than one number or email", "Pick one and pass it with --to: " + options.prefix(8).map { "\($0.1) \($0.0)" }.joined(separator: "; "), code: 2)
}

func messagesSend(_ a: Args) -> Never {
    let text = a.need("--text", "The exact message to send.")
    // --service is accepted for older callers and ignored: Messages picks iMessage or SMS for the conversation itself.
    var payload: [String: Any] = ["text": text]
    var would: [String: Any] = ["text": text, "characters": text.count]
    let target: String
    if let guid = a.options["--chat-guid"] {
        guard a.options["--to"] == nil else { Out.fail("give --to or --chat-guid, not both", "--chat-guid is for group chats.", code: 2) }
        target = guid
        payload["chatGuid"] = guid
        would["chat"] = guid
        if let db = ChatDB() {
            // Show who's in it, so the person approves the right group.
            let names = HandleNames()
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db.db, "SELECT COALESCE(c.display_name,''), h.id FROM chat c JOIN chat_handle_join chj ON chj.chat_id = c.ROWID JOIN handle h ON h.ROWID = chj.handle_id WHERE c.guid = ?", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_text(st, 1, guid, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                var people: [String] = [], title = ""
                while sqlite3_step(st) == SQLITE_ROW {
                    title = String(cString: sqlite3_column_text(st, 0))
                    let h = String(cString: sqlite3_column_text(st, 1)); people.append(names.name(h) ?? h)
                }
                if people.isEmpty { sqlite3_finalize(st); Out.fail("no chat with that guid", "Get it from casa-desk messages chats.", code: 2) }
                would["people"] = people
                if !title.isEmpty { would["chatName"] = title }
            }
            sqlite3_finalize(st)
        }
    } else {
        let to = a.need("--to", "--to NAME|NUMBER|EMAIL for one person, or --chat-guid GUID for a group (from messages chats).")
        let r = resolveRecipient(to)
        target = r.handle
        payload["to"] = r.handle
        if let guid = oneToOneChat(r.handle) { payload["chatGuid"] = guid }    // the existing thread, as Messages knows it
        would["to"] = r.handle
        if let n = r.name { would["name"] = n }
    }
    let code = ConfirmCode.make(["messages", target, text])
    if !loadAllowlist().allows(target) { would["allowlist"] = "NOT on ~/.config/casa-desk/allowlist — this send will be refused" }
    if writeMode(a) == .preview {
        // Prove Messages can reach this conversation before anyone says yes (sends nothing).
        var check = payload; check["mode"] = "check"; check["text"] = ""
        let r = runJXA(messagesSendJXA, check, app: "Messages", timeout: 60)
        would["reaches"] = (r["via"] as? String) == "participant" ? "Messages contact" : "existing conversation"
        preview("send message", would, code: code)
    }
    gateSend(a, code: code, allowTarget: target)
    let r = runJXA(messagesSendJXA, payload, app: "Messages", timeout: 60)
    done("send message", target: target, ["to": target, "characters": text.count, "sent": r["sent"] as? Bool ?? false])
}

// MARK: - Mail: draft (opens for the person to review), send

let mailWriteJXA = #"""
function run(argv) {
  var a = JSON.parse(argv[0]);
  var Mail = Application('com.apple.mail');
  var msg = Mail.OutgoingMessage({ subject: a.subject, content: a.body, visible: a.mode === 'draft' });
  Mail.outgoingMessages.push(msg);
  a.to.forEach(function (x) { msg.toRecipients.push(Mail.ToRecipient({ address: x })); });
  a.cc.forEach(function (x) { msg.ccRecipients.push(Mail.CcRecipient({ address: x })); });
  if (a.from) msg.sender = a.from;
  if (a.mode === 'send') { msg.send(); return JSON.stringify({ sent: true }); }
  try { msg.save(); } catch (e) {}
  return JSON.stringify({ drafted: true, open: true });
}
"""#

func emails(_ s: String?) -> [String] {
    let list = (s ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    for e in list where !(e.contains("@") && !e.contains(" ")) { Out.fail("bad email \(e)", "Comma-separated email addresses.", code: 2) }
    return list
}

func mailWrite(_ a: Args, _ sub: String) -> Never {
    let to = emails(a.need("--to", "One or more email addresses, comma-separated."))
    let cc = emails(a.options["--cc"])
    let subject = a.need("--subject", "The email's subject line.")
    let body = a.options["--body"] ?? ""
    var payload: [String: Any] = ["mode": sub, "to": to, "cc": cc, "subject": subject, "body": body]
    if let f = a.options["--from"] { payload["from"] = f }
    var would: [String: Any] = ["to": to.joined(separator: ", "), "subject": subject, "body": body]
    if !cc.isEmpty { would["cc"] = cc.joined(separator: ", ") }
    if let f = a.options["--from"] { would["from"] = f }

    if sub == "draft" {
        // A draft changes nothing anyone else sees: it opens in Mail for the person to read, edit and send themselves.
        if writeMode(a) == .preview { preview("draft email (opens in Mail; the person sends it)", would) }
        let r = runJXA(mailWriteJXA, payload, app: "Mail")
        done("draft email", target: to.joined(separator: ","), r)
    }
    let code = ConfirmCode.make(["mail", to.joined(separator: ","), cc.joined(separator: ","), a.options["--from"] ?? "", subject, body])
    let blocked = (to + cc).filter { !loadAllowlist().allows($0) }
    if !blocked.isEmpty { would["allowlist"] = "NOT on the allowlist: \(blocked.joined(separator: ", ")) — this send will be refused" }
    if writeMode(a) == .preview { preview("send email", would, code: code) }
    gateSend(a, code: code, allowTarget: blocked.first ?? to[0])
    _ = runJXA(mailWriteJXA, payload, app: "Mail", timeout: 120)
    done("send email", target: (to + cc).joined(separator: ","), ["to": to, "cc": cc, "subject": subject, "sent": true])
}

// MARK: - Shortcuts: run

func shortcutsRun(_ a: Args) -> Never {
    let name = a.need("--name", "The shortcut's exact name, from casa-desk shortcuts list.")
    let (status, out, _) = runProcess("/usr/bin/shortcuts", ["list"], timeout: 30)
    guard status == 0, out.split(separator: "\n").contains(where: { $0 == name }) else {
        Out.fail("no shortcut named \(name)", "Use the exact name from casa-desk shortcuts list.", code: 2)
    }
    var would: [String: Any] = ["shortcut": name]
    if let i = a.options["--input"] { would["input"] = i }
    if writeMode(a) == .preview { preview("run shortcut", would) }
    let tmp = NSTemporaryDirectory() + "casa-desk-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: tmp) }                 // our own temp files only
    var argv = ["run", name, "--output-path", tmp + "/out"]
    if let i = a.options["--input"] {
        FileManager.default.createFile(atPath: tmp + "/in.txt", contents: Data(i.utf8))
        argv += ["--input-path", tmp + "/in.txt"]
    }
    let (rs, _, rerr) = runProcess("/usr/bin/shortcuts", argv, timeout: 300)
    guard rs == 0 else { Out.fail("the shortcut failed", rerr.trimmingCharacters(in: .whitespacesAndNewlines), code: 5) }
    var result: [String: Any] = ["shortcut": name, "ran": true]
    if let data = FileManager.default.contents(atPath: tmp + "/out"), let s = String(data: data, encoding: .utf8) {
        result["output"] = s.count > 20_000 ? String(s.prefix(20_000)) + "…" : s
    }
    ActionLog.append("run shortcut", target: name)
    Out.emit(["done": true, "changed": true, "action": "run shortcut", "result": result]) { result["output"] as? String ?? "Ran \(name)." }
}

// MARK: - Routing

/// Runs the command if it's a write or send; returns if it's a read.
func routeWrite(_ a: Args) async {
    let cmd = a.positional.first ?? "", sub = a.positional.dropFirst().first ?? ""
    switch (cmd, sub) {
    case ("reminders", "add"), ("reminders", "complete"), ("reminders", "edit"): await remindersWrite(a, sub)
    case ("calendar", "create"), ("calendar", "update"), ("calendar", "cancel"), ("calendar", "delete"): await calendarWrite(a, sub)
    case ("contacts", "add"), ("contacts", "edit"): contactsWrite(a, sub)
    case ("notes", "create"), ("notes", "append"): notesWrite(a, sub)
    case ("messages", "send"): messagesSend(a)
    case ("mail", "draft"), ("mail", "send"): mailWrite(a, sub)
    case ("shortcuts", "run"): shortcutsRun(a)
    default: return
    }
}
