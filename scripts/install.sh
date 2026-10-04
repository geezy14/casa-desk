#!/bin/bash
# Casa Desk installer — builds `casa-desk`, links it into ~/.local/bin, and builds ~/Applications/Casa Desk.app.
# Non-interactive (safe for an assistant to run), no sudo, touches nothing outside this folder, ~/.local/bin and that app.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${CASA_DESK_BIN_DIR:-$HOME/.local/bin}"
cd "$REPO"

say() { printf '%s\n' "$*"; }
die() { printf 'casa-desk install: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Casa Desk only runs on macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "needs macOS 14 (Sonoma) or newer; this Mac has $(sw_vers -productVersion)."

# Prefer full Xcode when it's installed; otherwise the Command Line Tools are enough.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
command -v swift >/dev/null 2>&1 || die "Swift isn't installed. Run: xcode-select --install   (then run this again)"

say "Building Casa Desk (release)…"
swift build -c release 2>&1 | tail -n 3
BUILT="$REPO/.build/release/casa-desk"
[ -x "$BUILT" ] || die "build finished but $BUILT is missing."

mkdir -p "$BIN_DIR"
ln -sf "$BUILT" "$BIN_DIR/casa-desk"
say "Linked $BIN_DIR/casa-desk → $BUILT"

# ⭐ Casa Desk.app: the same binary with its own identity, so macOS asks "Casa Desk" for permission once, whatever app
# (Grok Bot, Terminal, Claude) runs the command. The `casa-desk` command hands its work to this app automatically.
APP="${CASA_DESK_APP:-$HOME/Applications/Casa Desk.app}"
mkdir -p "$APP/Contents/MacOS"
cp -f "$BUILT" "$APP/Contents/MacOS/casa-desk"
cp -f "$REPO/Support/Info.plist" "$APP/Contents/Info.plist"
# A real signing identity keeps the permissions across rebuilds; without one, ad-hoc signing works but macOS asks
# again after each update. CASA_DESK_SIGN overrides ("-" = ad-hoc).
SIGN="${CASA_DESK_SIGN:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [ -n "$SIGN" ] && [ "$SIGN" != "-" ] && codesign --force --sign "$SIGN" --identifier local.casa-desk "$APP" 2>/dev/null; then
  say "Built $APP (signed: $SIGN)"
else
  codesign --force --sign - --identifier local.casa-desk "$APP" || die "couldn't sign $APP"
  say "Built $APP (ad-hoc signed — macOS may ask for permissions again after an update)"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ON_PATH=1 ;;
  *) ON_PATH=0 ;;
esac

say ""
say "Installed. Quick check:"
"$BIN_DIR/casa-desk" doctor || true
say ""
if [ "$ON_PATH" -eq 0 ]; then
  say "Note: $BIN_DIR is not on your PATH. Add it with:"
  say "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
  say ""
fi
cat <<EOF
Next steps (a person does these — they're macOS privacy switches, and they all belong to "Casa Desk"):
  1. Run:  casa-desk doctor --request
     Click "Allow" when macOS asks whether "Casa Desk" can use Calendars, Reminders and Contacts.
  2. Messages, Focus and Safari (optional): System Settings → Privacy & Security → Full Disk Access →
     click +, press Cmd-Shift-G, type ~/Applications, pick "Casa Desk".
  3. Notes / Mail / Messages sending: the first use asks to let "Casa Desk" control that app — click OK.

Hook it to an assistant:
  Claude Code:  claude mcp add casa-desk -- python3 "$REPO/mcp/casa-desk-mcp.py"
  Any MCP app:  command = python3, args = ["$REPO/mcp/casa-desk-mcp.py"]
  Or just run:  casa-desk help
EOF
