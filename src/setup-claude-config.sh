#!/bin/bash
set -e

# Copy Claude Code configuration files with safety checks
# Unlike stow, this copies files so Claude can modify them without breaking symlinks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SRC="$SCRIPT_DIR/../templates/claude/.claude"
CLAUDE_DEST="$HOME/.claude"

if [[ ! -d "$CLAUDE_SRC" ]]; then
    echo "Error: Claude config source not found at $CLAUDE_SRC"
    exit 1
fi

# Copy file with diff check - prompts user if destination differs
copy_with_check() {
    local src="$1"
    local dest="$2"
    local name="$(basename "$dest")"

    # Handle symlinks - remove and replace with file
    if [[ -L "$dest" ]]; then
        echo "Removing symlink: $dest"
        rm -f "$dest"
    fi

    if [[ ! -f "$dest" ]]; then
        cp "$src" "$dest"
        echo "Created: $dest"
    elif diff -q "$src" "$dest" >/dev/null 2>&1; then
        echo "Unchanged: $dest"
    else
        echo ""
        echo "=== $name differs ==="
        diff --color=auto "$dest" "$src" || true
        echo ""
        read -p "Overwrite $name? [y/N] " choice
        case "$choice" in
            y|Y)
                cp "$src" "$dest"
                echo "Updated: $dest"
                ;;
            *)
                echo "Skipped: $dest"
                ;;
        esac
    fi
}

echo "Setting up Claude Code configuration..."

# Ensure directories exist
mkdir -p "$CLAUDE_DEST/commands"

# Handle commands directory if it's a symlink
if [[ -L "$CLAUDE_DEST/commands" ]]; then
    echo "Removing symlink: $CLAUDE_DEST/commands"
    rm -f "$CLAUDE_DEST/commands"
    mkdir -p "$CLAUDE_DEST/commands"
fi

# Copy main config files
copy_with_check "$CLAUDE_SRC/settings.json" "$CLAUDE_DEST/settings.json"
copy_with_check "$CLAUDE_SRC/statusline-command.sh" "$CLAUDE_DEST/statusline-command.sh"

# Copy commands (add/remove lines as needed per machine)
copy_with_check "$CLAUDE_SRC/commands/commit.md" "$CLAUDE_DEST/commands/commit.md"

echo ""
echo "Claude Code configuration complete"
