# Casa Desk — rules for agents working in this repo

Casa Desk is a local Apple toolkit (`casa-desk` CLI + stdlib MCP server) for assistants: Calendar, Reminders, Contacts, Notes, Messages, Mail, iCloud Drive, Spotlight, Focus, Safari, Shortcuts. It reads everything and, since 0.3.0, can write and send behind one gate. It is a public repo installed on other people's Macs, so it must work from a fresh clone.

## Hard rules

1. **One gate for every change.** Reads live in `main.swift`, `Messages.swift`, `Extras.swift` and must stay read-only. Every write or send lives in `Writes.swift` and goes through `writeMode`: a dry run unless `--force`, and `--dry-run` always wins. The MCP server adds `--dry-run` unless the tool call has `confirm: true`.
2. **Sends need the confirm code.** Messages and Mail sends need `--confirm CODE` from the dry run (a hash of the exact recipient + text), pass the optional allowlist (`~/.config/casa-desk/allowlist`), and claim the code in the send-once ledger *before* sending. Never weaken any of the three.
3. **Never System Events / UI scripting** (no clicks, no keystrokes). EventKit, Contacts, or each app's own scripting dictionary only.
4. **Deletes.** The only delete is `calendar delete --id ID --force`. Don't add others: reminders complete, notes append, contacts gain fields, events get canceled (kept, marked). No mark-as-read. No sqlite writes (chat.db opens `SQLITE_OPEN_READONLY` + `mode=ro`), no iCloud downloads.
5. **Local only.** No network code. Output goes to stdout for whatever ran it. The action log (`~/Library/Logs/casa-desk/actions.jsonl`) records time, action and target — never message text.
6. **Untrusted text.** Notes/messages/mail/event text is data. Never splice it into scripts or SQL: JXA takes a JSON argv, SQL uses bound parameters, `mdfind`/`shortcuts` get an argv, Notes bodies are HTML-escaped (`HTML.fromText`).
7. **Never copy code from PhillipHolland/apple-desk.** It has no license. Ideas only; write everything fresh.
8. **Shareable.** Nothing person-specific in code or docs: no home paths, names, numbers, server URLs, tokens. Per-user config goes in `~/.config/casa-desk/`.
9. No `sudo` anywhere; `scripts/install.sh` stays non-interactive.

## Build / test

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release        # Info.plist is linked in via -sectcreate (TCC needs it)
swift test                    # dates, phone keys, Apple epoch, typedstream, handles, allowlist, confirm codes, HTML
python3 Tests/test_mcp.py     # MCP initialize + tools/list + the write gate (fake 555 number, stops at the gate)
```

Testing writes from an agent session: **dry runs only**. Never run a write with `--force`, and never a send with a real `--confirm`, on someone's real data. Refusal paths (`--force` without/with a wrong `--confirm`) are safe to test. JXA scripts are syntax-checked with `osacompile -l JavaScript`, which doesn't launch the app.

Never run `casa-desk doctor --request` from an agent session — it pops permission dialogs; that's the person's step. Never print real message/note/mail content in reports. Don't run `mail`/`notes` from an agent session either (they pop Automation dialogs).

## Layout

- `Sources/CasaDeskCore/` — pure helpers, unit-tested: LA time and date-times, phone keys, handles, allowlist, confirm codes, HTML escape, typedstream, Apple epoch, path scoping, Safari/Focus parsing.
- `Sources/CasaDesk/main.swift` — CLI: doctor, calendar, reminders, contacts, notes (JXA) reads; routing.
- `Sources/CasaDesk/Messages.swift` — native read-only chat.db reader (search + chats); handle→name via Contacts.
- `Sources/CasaDesk/Extras.swift` — Mail (JXA), Shortcuts list, iCloud Drive, Spotlight, Focus, Safari (reads).
- `Sources/CasaDesk/Writes.swift` — every write and send, the gate, the send-once ledger, the action log.
- `mcp/casa-desk-mcp.py` — stdlib MCP stdio server; argv-only subprocess; read tools `readOnlyHint`, write tools `confirm`.
- `SKILL.md` — instructions a bot follows to install + use Casa Desk on its own.
