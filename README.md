# Casa Desk

Casa Desk lets your AI assistant (Grok Bot, Claude, or anything that speaks MCP) **look things up and get things done** in the Apple apps on your Mac: calendar, reminders, contacts, notes, Messages, Mail, iCloud Drive, Spotlight, Focus, Safari bookmarks and Reading List, and your Shortcuts.

It runs on your Mac and nothing gets uploaded anywhere. Every change is shown to you first and only happens after you say yes.

## What it does

| Ask your assistant… | Casa Desk reads |
|---|---|
| "What's on my calendar this week?" | Calendar |
| "What reminders are due Friday?" | Reminders |
| "What's Sam's number?" | Contacts |
| "Find my note about the Wi-Fi password" | Notes |
| "What did Alex text me about dinner?" | Messages |
| "Did the landlord email back?" | Mail |
| "What's in my iCloud Drive Taxes folder?" | iCloud Drive |
| "Find my lease PDF" | Spotlight (file paths only) |
| "Am I in a Focus right now?" | Focus |
| "What's on my Reading List?" | Safari |

| Ask your assistant… | Casa Desk does (after your yes) |
|---|---|
| "Remind me to call the dentist Monday at 5" | adds a reminder |
| "Move my 3pm to 4" / "cancel lunch Friday" | updates or cancels an event |
| "Save Sam's new number" | adds or updates a contact |
| "Start a note with the gate code" | creates or appends to a note |
| "Text Alex I'm running late" | sends that exact iMessage/SMS |
| "Draft a reply to the landlord" | opens a draft in Mail for you to send |
| "Run my Good Night shortcut" | runs a Shortcut |

## How changes work

Every change is a **dry run first**. Your assistant shows you exactly what would happen (the event, the reminder, the exact text and who it goes to). Nothing changes until you say yes and the assistant runs it again with `--force`.

Sends (Messages, Mail) have two more locks:
- **A confirm code.** The dry run prints a short code tied to the exact recipient and text. The send only goes out with that code, so if one character changes, it's refused and you're asked again.
- **Once.** Each approved message sends one time. A repeat is refused unless you ask for it again.
- **Optional allowlist.** Put phone numbers, emails or group chat ids (one per line) in `~/.config/casa-desk/allowlist`, and Casa Desk will only send to those. No file means no allowlist.

## What it never does

- **Never clicks or types for you.** No System Events and no UI scripting. Casa Desk only uses each app's own data, Apple's frameworks, or the app's scripting dictionary.
- **Never deletes**, with one exception: `calendar delete` with an event id, after your yes. Reminders get completed, events get marked canceled, contacts only gain fields, notes only get added to.
- **Never marks messages read** and never downloads iCloud files that are stored only in the cloud.
- **Never goes online.** It reads and changes things on this Mac and prints the answer to the assistant that asked. A local log of what changed (time, action, target; never message text) is kept in `~/Library/Logs/casa-desk/actions.jsonl`.

## Install

You need a Mac on macOS 14 (Sonoma) or newer, plus Apple's free developer tools. If you don't have them, run `xcode-select --install` once.

```bash
git clone https://github.com/geezy14/casa-desk.git ~/Developer/casa-desk
~/Developer/casa-desk/scripts/install.sh
```

The installer builds Casa Desk, puts a small **Casa Desk** app in `~/Applications` (no Dock icon, no window), and puts a `casa-desk` command in `~/.local/bin`. The command quietly runs its work through that app, so macOS permissions are granted to "Casa Desk" once and work no matter which assistant or Terminal runs it. It doesn't use `sudo` and doesn't touch anything else. If that folder isn't on your PATH yet, the installer prints the line to add.

If you use Grok Bot, you can just share this folder (or [SKILL.md](SKILL.md)) with the bot. It installs everything itself and then tells you which switches to click.

## The permission clicks (one time)

macOS asks you before any app reads your stuff. Casa Desk can't click these for you, and it never tries to.

1. **Calendar, Reminders and Contacts.** Run `casa-desk doctor --request` and click **Allow** on each popup asking about **Casa Desk**.
   Missed one? Go to System Settings → Privacy & Security → Calendars (or Reminders, or Contacts) and switch on Casa Desk there.
2. **Messages (optional).** Messages history lives in a protected file. Open System Settings → Privacy & Security → **Full Disk Access**, click **+**, press Cmd-Shift-G, type `~/Applications`, and choose **Casa Desk**. Skip this if you don't want your assistant reading texts.
3. **Notes, Mail and Messages.** The first time something uses Notes or Mail (or sends a message), macOS asks to let that app control Notes, Mail or Messages. Click **OK**. That's the app's own scripting, not System Events.
4. **Focus and Safari** use Full Disk Access too, the same switch as Messages.

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
casa-desk mail search --q invoice
casa-desk icloud list --path Documents
casa-desk spotlight search --q lease --in ~/Documents
casa-desk focus status
casa-desk safari reading-list
```

Changes (each one prints a dry run; add `--force` after your yes):
```bash
casa-desk reminders add --title "Call the dentist" --due 2026-10-05T17:00
casa-desk calendar create --title "Lunch" --start 2026-10-09T12:30 --minutes 60
casa-desk calendar cancel --id EVENT_ID
casa-desk contacts edit --id CONTACT_ID --add-phone "323-555-0100"
casa-desk notes create --title "Gate code" --body "4512"
casa-desk messages send --to "Alex" --text "Running 10 late"     # then: --force --confirm CODE
casa-desk mail draft --to landlord@example.com --subject "Lease" --body "Hi…"
casa-desk shortcuts run --name "Good Night"
```

Every command accepts `--json` and `--limit N` (the default is 50). Run `casa-desk help` for the full list. Times are Pacific time (America/Los_Angeles).

## Settings

None are needed. The only one is the optional send allowlist, `~/.config/casa-desk/allowlist`. You edit it, not your assistant.

## Privacy

Casa Desk only answers the assistant that runs it, on your Mac. What that assistant does with the answer is up to the assistant. Turn on only the permissions you're comfortable with, and keep the allowlist on if you want sends limited to a few people.

## License

MIT. See [LICENSE](LICENSE).
