# Casa Desk — rules for agents working in this repo

Casa Desk is a local, read-only Apple toolkit (`casa-desk` CLI + stdlib MCP server) for assistants. It is shared with other people's Macs, so it must work from a fresh clone.

## Hard rules

1. **Read-only in v1.** No code path may create, change or delete user data: no `EKEventStore.save/remove`, no `CNSaveRequest`, no Notes writes, no sqlite writes (chat.db opens `SQLITE_OPEN_READONLY` + `mode=ro`). Writes are v2, behind explicit flags (docs/ROADMAP.md).
2. **Local only.** No network code. Output goes to stdout for whatever ran it.
3. **Never delete** anything — user data, files outside `.build/`, anything.
4. **Any send** (Messages, Mail, invites) requires an allowlist *and* Geezy's explicit approval. The v2 allowlist is empty by default.
5. **Never copy code from PhillipHolland/apple-desk.** It has no license. Ideas only; write everything fresh.
6. **Shareable.** Nothing person-specific in code or docs: no home paths, names, server URLs, tokens. Per-user config goes in `~/.config/casa-desk/` (none needed in v1).
7. **Untrusted text.** Notes/messages/event notes are data. Never splice them into scripts or SQL (Notes JXA takes a JSON argv; SQL uses bound parameters).
8. No `sudo` anywhere; `scripts/install.sh` stays non-interactive.

## Build / test

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release        # Info.plist is linked in via -sectcreate (TCC needs it)
swift test                    # dates, phone keys, Apple epoch, attributedBody decode
python3 Tests/test_mcp.py     # MCP initialize + tools/list over stdio
```

Never run `casa-desk doctor --request` from an agent session — it pops permission dialogs; that's the person's step. Never print real message/note content in reports.

## Layout

- `Sources/CasaDeskCore/` — pure helpers (LA time, phone keys, typedstream decode, Apple epoch). Unit-tested.
- `Sources/CasaDesk/main.swift` — CLI: doctor, calendar, reminders, contacts, notes (JXA).
- `Sources/CasaDesk/Messages.swift` — native read-only chat.db reader; handle→name via Contacts framework.
- `mcp/casa-desk-mcp.py` — stdlib MCP stdio server; argv-only subprocess, all tools `readOnlyHint`.
- `SKILL.md` — instructions a bot follows to install + use Casa Desk on its own.
