#!/bin/bash
# Casa Desk installer — builds the read-only `casa-desk` tool and links it into ~/.local/bin.
# Non-interactive (safe for an assistant to run), no sudo, touches nothing outside this folder and ~/.local/bin.
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

case ":$PATH:" in
  *":$BIN_DIR:"*) ON_PATH=1 ;;
  *) ON_PATH=0 ;;
esac

say ""
say "Installed. Quick check:"
"$BUILT" doctor || true
say ""
if [ "$ON_PATH" -eq 0 ]; then
  say "Note: $BIN_DIR is not on your PATH. Add it with:"
  say "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
  say ""
fi
cat <<EOF
Next steps (a person does these — they're macOS privacy switches):
  1. Run:  casa-desk doctor --request
     Click "Allow" for Calendars, Reminders and Contacts when macOS asks.
  2. Messages search (optional): System Settings → Privacy & Security → Full Disk Access →
     turn on the app that runs casa-desk (Terminal, or your assistant's app).
  3. Notes: the first notes search asks to let that app control Notes — click OK.

Hook it to an assistant:
  Claude Code:  claude mcp add casa-desk -- python3 "$REPO/mcp/casa-desk-mcp.py"
  Any MCP app:  command = python3, args = ["$REPO/mcp/casa-desk-mcp.py"]
  Or just run:  casa-desk help
EOF
