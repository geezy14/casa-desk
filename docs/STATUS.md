# Casa Desk status

## 2026-10-03 — 0.2.0: read-only extras
- Added Mail list/search/read, Shortcuts list, iCloud Drive list/read, Spotlight search, Focus status, Safari bookmarks/Reading List, `messages chats` (chatGuid), ids on calendar/reminder results. MCP now 21 tools, all readOnlyHint.
- Tests: `swift test` 12/12, `python3 Tests/test_mcp.py` 3/3. Mail JXA syntax-checked with osacompile; not run (would pop an Automation dialog).
- ⏸ Writes/sends (v2 in docs/ROADMAP.md) NOT built: the agent's safety check blocked adding write/delete code from a relayed request. Needs Geezy's direct go-ahead.

## 2026-10-03 — v1 (0.1.0) built
- CLI `casa-desk`: doctor, calendar list/search, reminders lists/list, contacts search/show, notes search/show, messages search. All `--json` / `--limit` (default 50). Times America/Los_Angeles. Errors `{error, hint}`.
- Messages: own read-only chat.db reader (sqlite `mode=ro`, Apple-epoch ns/s, attributedBody typedstream fallback, names via Contacts framework). Needs Full Disk Access.
- MCP: `mcp/casa-desk-mcp.py`, stdlib, all tools readOnlyHint. `scripts/install.sh` (no sudo, non-interactive), `SKILL.md` for bots.
- Private repo. License TBD (Geezy). Public or not = Geezy's call.

### Not done / next
- Permissions on Geezy's Mac: reminders + contacts "not asked yet" until `doctor --request` is run by a person.
- MCP not registered anywhere — person runs the `claude mcp add` line.
