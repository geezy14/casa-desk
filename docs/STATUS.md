# Casa Desk status

## 2026-10-03 — v1 (0.1.0) built
- CLI `casa-desk`: doctor, calendar list/search, reminders lists/list, contacts search/show, notes search/show, messages search. All `--json` / `--limit` (default 50). Times America/Los_Angeles. Errors `{error, hint}`.
- Messages: own read-only chat.db reader (sqlite `mode=ro`, Apple-epoch ns/s, attributedBody typedstream fallback, names via Contacts framework). Needs Full Disk Access.
- MCP: `mcp/casa-desk-mcp.py`, stdlib, 10 tools, all readOnlyHint.
- `scripts/install.sh` (no sudo, non-interactive), `SKILL.md` for bots.
- Tests: `swift test` 8/8, `python3 Tests/test_mcp.py` 3/3.
- Private repo. License TBD (Geezy). Public or not = Geezy's call.

### Not done / next
- Permissions on Geezy's Mac: reminders + contacts "not asked yet" until `doctor --request` is run by a person.
- MCP not registered anywhere — person runs the `claude mcp add` line.
