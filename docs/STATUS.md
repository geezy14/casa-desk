# Casa Desk status

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
