# Casa Desk roadmap

## v1 — read-only (2026-10-03) ✅
Calendar, Reminders, Contacts, Notes (JXA), Messages (native chat.db reader + chats). CLI + MCP. Shareable install.

## v1.1 — read-only extras (2026-10-03) ✅
Mail list/search/read (JXA), Shortcuts list, iCloud Drive list/read (no downloads), Spotlight (paths, scoped, refuses Keychains/Messages/Mail/cookies), Focus status, Safari bookmarks + Reading List. Never System Events.

## v2 — "everything but System Events" (0.3.0, 2026-10-03) ✅
Built as designed, plus a confirm code tied to the exact recipient + text and a send-once ledger. Every write/send carries, in the CLI itself: `--force` required, `--dry-run` showing the exact change, a printed record of what changed, and no deletes without `--force` + an explicit id ("get rid of" = hide/archive). MCP write tools would require `confirm: true`, set only after the person's yes.
- Reminders: add, complete, edit (title, due, notes, list).
- Calendar: create, update/move, cancel (kept, marked canceled); delete only `--force` + id.
- Notes: create, append. Contacts: add, edit fields (no delete).
- Messages send via Messages' scripting dictionary: 1:1 `--to`, group only by a named `--chat-guid`; plain text; optional allowlist `~/.config/casa-desk/allowlist`. Draft → explicit yes → send once, no retries. No mark-read.
- Mail: drafts; send only with `--force` after an explicit yes.
- Shortcuts: run only with `--force`.

## Later / maybe
- ✅ Public repo, MIT (2026-10-03).
- Signed/notarized binary so friends can skip building.
