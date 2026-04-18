#!/usr/bin/env bash
# cc-slim-statusline installer
# Usage: curl -fsSL https://raw.githubusercontent.com/stroniarz/cc-slim-statusline/main/install.sh | bash

set -e

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_PATH="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
SRC_URL="https://raw.githubusercontent.com/stroniarz/cc-slim-statusline/main/statusline.sh"

echo "→ Installing cc-slim-statusline to $SCRIPT_PATH"

# Check deps
command -v jq >/dev/null 2>&1 || {
  echo "✗ 'jq' is required. Install with: brew install jq  (or apt install jq)" >&2
  exit 1
}

mkdir -p "$CLAUDE_DIR"

# Download
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$SRC_URL" -o "$SCRIPT_PATH"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$SCRIPT_PATH" "$SRC_URL"
else
  echo "✗ Need curl or wget." >&2
  exit 1
fi

chmod +x "$SCRIPT_PATH"
echo "✓ Script installed."

# Wire up settings.json
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

# Use jq to inject statusLine while preserving existing keys
tmp=$(mktemp)
jq --arg cmd "bash $SCRIPT_PATH" \
   '.statusLine = {"type": "command", "command": $cmd}' \
   "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "✓ Registered in $SETTINGS"
echo ""
echo "Done. Start a new Claude Code session to see the statusline."
