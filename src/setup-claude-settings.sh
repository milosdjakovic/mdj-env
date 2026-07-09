#!/bin/bash
set -e

# Wire the stowed statusline script into Claude Code's settings.json.
# settings.json is intentionally not tracked/stowed (Claude Code writes to it
# directly), so the statusLine key must be merged in here rather than symlinked.

SETTINGS="$HOME/.claude/settings.json"
COMMAND="~/.claude/statusline-command.sh"

if [ -f "$SETTINGS" ] && [ "$(jq -r '.statusLine.command // ""' "$SETTINGS")" = "$COMMAND" ]; then
    echo "Claude statusLine already configured"
    exit 0
fi

echo "Configuring Claude statusLine..."

mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp="$(mktemp)"
jq --arg cmd "$COMMAND" \
    '.statusLine = {"type": "command", "command": $cmd}' \
    "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Claude statusLine configured successfully"
