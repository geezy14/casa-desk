# Casa Desk status

## 2026-10-07 — 0.3.3: sends can attach files
- Reported: an assistant had to send a skill file as pasted text because Casa Desk couldn't attach files.
- `--file PATH` (repeatable) on `messages send`, `mail send` and `mail draft`; MCP tools take `files: [paths]`. `messages send` needs `--text` or `--file`. Files must exist, be readable, and be at most 100 MB. Relative paths resolve against the caller's folder (the relay passes `CASA_DESK_CWD`).
- ⛔ The confirm code now covers each file's path, size and SHA-256, so only the file shown in the dry run can go; edit or swap it and the code fails. Text-only codes are unchanged.
- Messages: each file is copied to `~/Pictures/Casa Desk/<id>/` and sent from there (Messages is sandboxed and silently fails on files it can't read). The copies are kept. Mail: attached via `Mail.Attachment`, with a 1 s pause before sending.
- Verified: build, swift test 19/19, MCP 5/5, both JXA scripts compile, dry runs list the files, a wrong code is refused, editing the file changes the code. The real attach-and-send is untested until the first approved send.

## 2026-10-04 — 0.3.2: Messages send fixed for macOS 27
- Reported from Grok Bot: a 1:1 send failed at `Messages.accounts.whose({serviceType})`. Root causes (probed read-only on macOS 27): `Application('Messages')` resolved to "Messages Assistant Extension", and on the real app reading `service type` fails ("AppleEvent handler failed").
- Fix: every app is addressed by bundle id (com.apple.MobileSMS, com.apple.Notes, com.apple.mail). Sends go to the existing conversation by its chat id (from chat.db, e.g. `any;-;+1…`), falling back to a Messages participant by handle; no conversation = a clear error (start it in Messages first). `--service` is ignored now (Messages picks iMessage/SMS per conversation). The dry run now checks Messages can reach the target (sends nothing).
- Verified: dry runs reach a real 1:1 (by guid and by handle) and a real group; a fake number gets "no conversation". The final `send` call itself is untested until the first approved real send. swift test 19/19, MCP 5/5.

## 2026-10-03 — 0.3.1: its own app identity
- Problem (reported from Grok Bot): under Grok Bot Helper, `doctor --request` returned with no prompt; Calendar/Reminders/Contacts stayed "not asked yet", Contacts flickered "denied", and Terminal's grants didn't carry over (TCC charges the responsible app).
- Fix: install.sh builds `~/Applications/Casa Desk.app` (same binary, LSUIElement, bundle id local.casa-desk, signed with an Apple Development identity when present, else ad-hoc). The CLI relays every command into it through LaunchServices, so all permissions belong to "Casa Desk". Exit codes and output pass through; `CASA_DESK_DIRECT=1` bypasses.
- Verified on a Mac: doctor reports `runs as: Casa Desk.app` with its own (fresh) permission state, exit codes 0/3/4 pass through, MCP 5/5, swift test 19/19.
- 2026-10-04: `doctor --request` through the app showed the Casa Desk prompts; after Allow, calendar/reminders/contacts = granted and reads work.

## 2026-10-03 — 0.3.0: writes and sends ("everything but System Events")
- New `Writes.swift`: reminders add/complete/edit; calendar create/update/cancel/delete (delete = the only delete, id + --force); contacts add/edit (never removes fields); notes create/append (JXA, HTML-escaped, never locked notes); messages send (Messages scripting dictionary, 1:1 `--to` or group `--chat-guid`); mail draft/send; shortcuts run.
- One gate: dry run unless `--force`; `--dry-run` always wins. Sends also need `--confirm CODE` (hash of exact recipient + text), pass the optional allowlist, and send once (ledger claimed before sending; `--again` to repeat). Action log without message text.
- MCP: 15 write tools (36 total), dry run unless `confirm: true`; sends need `confirm_code`.
- Tests: `swift test` 19/19, `python3 Tests/test_mcp.py` 5/5. Dry runs checked on a real Mac (calendar, messages, mail, shortcuts); refusals checked (no code, wrong code). Notes/Messages/Mail JXA syntax-checked with osacompile, not run. Nothing was created or sent.
- Repo made public, MIT license.

## 2026-10-03 — 0.2.0: read-only extras
- Added Mail list/search/read, Shortcuts list, iCloud Drive list/read, Spotlight search, Focus status, Safari bookmarks/Reading List, `messages chats` (chatGuid), ids on calendar/reminder results. MCP now 21 tools, all readOnlyHint.
- Tests: `swift test` 12/12, `python3 Tests/test_mcp.py` 3/3. Mail JXA syntax-checked with osacompile; not run (would pop an Automation dialog).
- ⏸ Writes/sends (v2 in docs/ROADMAP.md) NOT built: the agent's safety check blocked adding write/delete code from a relayed request. Built in 0.3.0 after the owner's direct go-ahead.

## 2026-10-03 — v1 (0.1.0) built
- CLI `casa-desk`: doctor, calendar list/search, reminders lists/list, contacts search/show, notes search/show, messages search. All `--json` / `--limit` (default 50). Times America/Los_Angeles. Errors `{error, hint}`.
- Messages: own read-only chat.db reader (sqlite `mode=ro`, Apple-epoch ns/s, attributedBody typedstream fallback, names via Contacts framework). Needs Full Disk Access.
- MCP: `mcp/casa-desk-mcp.py`, stdlib, all tools readOnlyHint. `scripts/install.sh` (no sudo, non-interactive), `SKILL.md` for bots.
- Private repo at the time (public + MIT since 0.3.0).

### Not done / next
- Permissions on the owner's Mac: reminders + contacts "not asked yet" until `doctor --request` is run by a person.
- MCP not registered anywhere — person runs the `claude mcp add` line.
