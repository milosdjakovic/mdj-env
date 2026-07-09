#!/bin/bash
set -e

# Wire the stowed statusline script into Claude Code's settings.json.
# settings.json is intentionally not tracked/stowed (Claude Code writes to it
# directly), so the statusLine key must be merged in here rather than symlinked.

SETTINGS="$HOME/.claude/settings.json"
COMMAND="~/.claude/statusline-command.sh"
SCRIPT="$HOME/.claude/statusline-command.sh"

# Claude Code runs the statusLine command directly, so the script must be
# executable or it fails with "permission denied" and falls back to the default
# statusline. The bit is tracked in git (100755), but ensure it here too in case
# it is ever lost. chmod follows the stow symlink to the repo file (idempotent).
[ -e "$SCRIPT" ] && chmod +x "$SCRIPT"

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
