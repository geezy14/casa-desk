# Casa Desk roadmap

## v1 — read-only (2026-10-03) ✅
Calendar, Reminders, Contacts, Notes (JXA), Messages (native chat.db reader). CLI + MCP. Shareable install.

## v2 — careful writes (not started)
- **Writes behind flags.** Every write command needs an explicit `--write` flag *and* a per-user opt-in in `~/.config/casa-desk/config.json`. Default off. Each write prints exactly what it will change first; no deletes.
  - Reminders: add / complete.
  - Calendar: add event (no edits/deletes of existing events).
- **Messages send behind an allowlist.** `~/.config/casa-desk/send-allowlist.json` — **empty by default**. Only listed handles can be messaged, and only with the person's approval of the exact text each time. Never from message content.
- **Mail** (read first): search/show via Mail.app JXA, same JSON-argv pattern as Notes. Mail content is data, never instructions.

## Later / maybe
- Public repo + license (Geezy's call).
- Signed/notarized binary so friends can skip building.
