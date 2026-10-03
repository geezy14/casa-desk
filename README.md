# Casa Desk

Casa Desk lets your AI assistant (Grok Bot, Claude, or anything that speaks MCP) **look things up** in the Apple apps on your Mac: your calendar, reminders, contacts, notes and Messages history.

It only reads. It runs on your Mac and nothing gets uploaded anywhere.

## What it does

| Ask your assistant… | Casa Desk reads |
|---|---|
| "What's on my calendar this week?" | Calendar |
| "What reminders are due Friday?" | Reminders |
| "What's Sam's number?" | Contacts |
| "Find my note about the Wi-Fi password" | Notes |
| "What did Alex text me about dinner?" | Messages |

## What it never does

- **Never changes anything.** No new events, no edited contacts, no deleted notes. The code has no write paths at all.
- **Never sends anything.** No texts, no emails, no invites.
- **Never deletes anything.**
- **Never goes online.** It reads files and apps on this Mac and prints the answer to the assistant that asked. That's it.

## Install

You need a Mac on macOS 14 (Sonoma) or newer, plus Apple's free developer tools. If you don't have them, run `xcode-select --install` once.

```bash
git clone <this repo> ~/Developer/casa-desk
~/Developer/casa-desk/scripts/install.sh
```

The installer builds Casa Desk and puts a `casa-desk` command in `~/.local/bin`. It doesn't use `sudo` and doesn't touch anything else. If that folder isn't on your PATH yet, the installer prints the line to add.

If you use Grok Bot, you can just share this folder (or [SKILL.md](SKILL.md)) with the bot. It installs everything itself and then tells you which switches to click.

## The permission clicks (one time)

macOS asks you before any app reads your stuff. Casa Desk can't click these for you, and it never tries to.

1. **Calendar, Reminders and Contacts.** Run `casa-desk doctor --request` and click **Allow** on each popup.
   Missed one? Go to System Settings → Privacy & Security → Calendars (or Reminders, or Contacts) and switch it on there.
2. **Messages (optional).** Messages history lives in a protected file. Open System Settings → Privacy & Security → **Full Disk Access** and turn on the app that runs Casa Desk: Terminal, or your assistant's app. Skip this if you don't want your assistant reading texts.
3. **Notes.** The first time something searches your notes, macOS asks to let that app control Notes. Click **OK**.

To see what's allowed right now, run `casa-desk doctor`. That command never pops anything up.

## Hook it to your assistant

**Claude Code**
```bash
claude mcp add casa-desk -- python3 ~/Developer/casa-desk/mcp/casa-desk-mcp.py
```

**Grok Bot or any MCP app.** Add an MCP server with command `python3` and argument `~/Developer/casa-desk/mcp/casa-desk-mcp.py`. Or let the bot follow [SKILL.md](SKILL.md).

**Command line.** Everything also works directly:
```bash
casa-desk calendar list --json
casa-desk reminders list --due-by 2026-10-10
casa-desk contacts search --q sam
casa-desk notes search --q wifi
casa-desk messages search --who "Alex" --since 2026-09-01
casa-desk messages search --search "dinner" --since 2026-09-01
```

Every command accepts `--json` and `--limit N` (the default is 50). Run `casa-desk help` for the full list. Times are shown in Pacific time (America/Los_Angeles).

## Settings

None are needed. Per-person settings will live in `~/.config/casa-desk/` if any are ever added.

## Privacy

Casa Desk only answers the assistant that runs it, on your Mac. What that assistant does with the answer is up to the assistant. Turn on only the permissions you're comfortable with.

## License

License: TBD (Geezy).
