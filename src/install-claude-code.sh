#!/bin/bash
set -e

# Install Claude Code from Anthropic's native installer.
#
# Not the claude-code cask, because Claude Code switches its own updater off when Homebrew
# installed it, and this repository never upgrades anything on a setup run, so the cask would
# stay on whatever version a machine first got. The native copy updates itself, which is why
# this step only ever installs it once. decisions/claude-code-install.md has it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/lib/backup.sh"

NATIVE="$HOME/.local/bin/claude"

if [[ -x "$NATIVE" ]]; then
    echo "Claude Code already installed, $("$NATIVE" --version 2>/dev/null || echo "version unknown")"
else
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    echo "Claude Code installed successfully"
fi

# A cask left over from before this step still sits on PATH behind the native copy and never
# updates. It is not removed here, since this Homebrew prefix may belong to another account and
# only a person can type that password.
if command -v brew >/dev/null 2>&1 && brew list --cask claude-code >/dev/null 2>&1; then
    mdj_note "The claude-code cask is still installed and no longer used. Remove it with brew uninstall --cask claude-code."
fi
